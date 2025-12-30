#!/bin/bash
#
# Upload WIC files to Azure Blob Storage and generate JSON manifest
#
# Usage:
#   ./upload-wic-to-cdn.sh [options] <source1> [source2] ...
#
# Sources can be:
#   - Local folders: /path/to/wics
#   - Remote SSH paths: user@server:/path/to/wics
#   - JSON URL: https://example.com/images.json (fetches URLs from os_list)
#
# Options:
#   -a, --account     Azure Storage account name (or set AZURE_STORAGE_ACCOUNT)
#   -k, --key         Azure Storage account key (or set AZURE_STORAGE_KEY)
#   -c, --container   Container name (default: software)
#   -t, --target      Target path in container (default: release/SimPad/Updates-imx6-imx8)
#   -o, --output      Output JSON filename (default: updates.json)
#   -u, --cdn-url     CDN base URL (default: https://laerdalcdn.blob.core.windows.net)
#   -i, --identity    SSH identity file (private key) for remote sources
#   --cache-dir       Directory to cache downloaded files (default: /tmp/wic-cache)
#   --keep-cache      Keep downloaded files in cache after completion
#   -n, --dry-run     Show what would be done without uploading
#   -h, --help        Show this help message
#
# Environment variables:
#   AZURE_STORAGE_ACCOUNT  - Storage account name
#   AZURE_STORAGE_KEY      - Storage account key
#   AZURE_STORAGE_CONTAINER - Container name
#   CDN_BASE_URL           - CDN base URL
#   SSH_IDENTITY_FILE      - SSH private key file
#
# Examples:
#   # Local folder only
#   ./upload-wic-to-cdn.sh /path/to/wics
#
#   # Remote SSH source
#   ./upload-wic-to-cdn.sh user@buildserver:/opt/yocto/deploy/images
#
#   # Mix of local and remote, keep cache
#   ./upload-wic-to-cdn.sh --keep-cache -i ~/.ssh/id_rsa \
#     /local/wics user@server1:/builds user@server2:/images
#
#   # From JSON URL (downloads WIC files listed in os_list)
#   ./upload-wic-to-cdn.sh https://laerdalcdn.blob.core.windows.net/software/release/SimPad/factory-images/images.json
#

set -euo pipefail

# Default values
CONTAINER="${AZURE_STORAGE_CONTAINER:-software}"
TARGET_PATH="release/SimPad/Updates-imx6-imx8"
OUTPUT_JSON="updates.json"
CDN_URL="${CDN_BASE_URL:-https://laerdalcdn.blob.core.windows.net}"
STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"
STORAGE_KEY="${AZURE_STORAGE_KEY:-}"
SSH_KEY="${SSH_IDENTITY_FILE:-}"
CACHE_DIR="/tmp/wic-cache"
KEEP_CACHE=false
DRY_RUN=false
SOURCES=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--account)
            STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        -k|--key)
            STORAGE_KEY="$2"
            shift 2
            ;;
        -c|--container)
            CONTAINER="$2"
            shift 2
            ;;
        -t|--target)
            TARGET_PATH="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_JSON="$2"
            shift 2
            ;;
        -u|--cdn-url)
            CDN_URL="$2"
            shift 2
            ;;
        -i|--identity)
            SSH_KEY="$2"
            shift 2
            ;;
        --cache-dir)
            CACHE_DIR="$2"
            shift 2
            ;;
        --keep-cache)
            KEEP_CACHE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            head -50 "$0" | tail -48
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            SOURCES+=("$1")
            shift
            ;;
    esac
done

# Validate inputs
if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "Error: No sources specified" >&2
    exit 1
fi

# Azure credentials only required for actual uploads
if [[ "$DRY_RUN" == "false" ]]; then
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        echo "Error: Azure Storage account not specified" >&2
        echo "Use -a/--account or set AZURE_STORAGE_ACCOUNT" >&2
        exit 1
    fi

    if [[ -z "$STORAGE_KEY" ]]; then
        echo "Error: Azure Storage key not specified" >&2
        echo "Use -k/--key or set AZURE_STORAGE_KEY" >&2
        exit 1
    fi
fi

# Check for required tools
for cmd in jq sha256sum md5sum rsync curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required command not found: $cmd" >&2
        exit 1
    fi
done

# Optional tools for getting accurate extract sizes
for cmd in xz zstd; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Warning: $cmd not found - extract size for .$cmd files will be estimated" >&2
    fi
done

# az cli only required for actual uploads
if [[ "$DRY_RUN" == "false" ]] && ! command -v az &>/dev/null; then
    echo "Error: Required command not found: az" >&2
    exit 1
fi

# Build SSH options
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o BatchMode=yes"
if [[ -n "$SSH_KEY" ]]; then
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "Error: SSH identity file not found: $SSH_KEY" >&2
        exit 1
    fi
    SSH_OPTS="$SSH_OPTS -i $SSH_KEY"
fi

echo "=== WIC File Uploader ==="
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER"
echo "Target Path: $TARGET_PATH"
echo "CDN URL: $CDN_URL"
echo "Cache Dir: $CACHE_DIR"
echo "Keep Cache: $KEEP_CACHE"
echo "Dry Run: $DRY_RUN"
if [[ -n "$SSH_KEY" ]]; then
    echo "SSH Key: $SSH_KEY"
fi
echo ""

# Create cache directory
mkdir -p "$CACHE_DIR"

# Function to check if source is a JSON URL
is_json_url() {
    [[ "$1" == http://* || "$1" == https://* ]] && [[ "$1" == *.json ]]
}

# Function to check if source is remote (SSH)
is_remote() {
    [[ "$1" == *:* && "$1" != /* && "$1" != http://* && "$1" != https://* ]]
}

# Function to fetch WIC files from JSON URL (os_list format)
fetch_from_json_url() {
    local json_url="$1"

    echo "Fetching WIC list from JSON: $json_url"

    # Download JSON
    local json_content
    json_content=$(curl -sS "$json_url") || {
        echo "  Error: Failed to fetch JSON from $json_url" >&2
        return 1
    }

    # Extract URLs from os_list
    local urls
    urls=$(echo "$json_content" | jq -r '.os_list[]?.url // empty' 2>/dev/null)

    if [[ -z "$urls" ]]; then
        echo "  No WIC URLs found in JSON"
        return
    fi

    # Download each WIC file
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue

        local filename
        filename=$(basename "$url")
        local local_path="$CACHE_DIR/$filename"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would download: $filename"
        else
            echo "  Downloading: $filename"
            curl -L --progress-bar -o "$local_path" "$url" || {
                echo "  Warning: Failed to download $url" >&2
                continue
            }
            WIC_FILES+=("$local_path")
            echo "  Downloaded: $filename"
        fi
    done <<< "$urls"
}

# Function to fetch files from remote source using rsync
fetch_remote_files() {
    local source="$1"
    local host="${source%%:*}"
    local remote_path="${source#*:}"

    echo "Fetching WIC files from $host:$remote_path (recursive)..."

    # Build SSH options
    local ssh_opts="-o StrictHostKeyChecking=accept-new -o BatchMode=yes"
    if [[ -n "$SSH_KEY" ]]; then
        ssh_opts="$ssh_opts -i $SSH_KEY"
    fi

    # First, find all WIC files on remote using SSH
    echo "  Scanning remote for WIC files..."
    local remote_files
    remote_files=$(ssh $ssh_opts "$host" "find '$remote_path' -type f \( -name '*.wic' -o -name '*.wic.zst' -o -name '*.wic.xz' -o -name '*.wic.gz' -o -name '*.wic.bz2' \) 2>/dev/null" || true)

    if [[ -z "$remote_files" ]]; then
        echo "  No WIC files found on remote"
        return
    fi

    # Download each file to flat cache directory
    while IFS= read -r remote_file; do
        [[ -z "$remote_file" ]] && continue
        local filename
        filename=$(basename "$remote_file")
        local local_path="$CACHE_DIR/$filename"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would download: $filename"
        else
            echo "  Downloading: $filename"
            rsync -avz --progress \
                -e "ssh $ssh_opts" \
                "$host:$remote_file" "$local_path"
        fi

        # Add to WIC_FILES array
        if [[ "$DRY_RUN" == "false" ]]; then
            WIC_FILES+=("$local_path")
            echo "  Downloaded: $filename"
        fi
    done <<< "$remote_files"
}

# Function to find local WIC files
find_local_files() {
    local folder="$1"

    if [[ ! -d "$folder" ]]; then
        echo "Warning: Local folder not found: $folder"
        return
    fi

    echo "Searching in: $folder"
    while IFS= read -r -d '' file; do
        WIC_FILES+=("$file")
        echo "  Found: $file"
    done < <(find "$folder" -type f \( -name "*.wic" -o -name "*.wic.zst" -o -name "*.wic.xz" -o -name "*.wic.gz" -o -name "*.wic.bz2" \) -print0)
}

# Collect WIC files from all sources
WIC_FILES=()
for source in "${SOURCES[@]}"; do
    if is_json_url "$source"; then
        fetch_from_json_url "$source"
    elif is_remote "$source"; then
        fetch_remote_files "$source"
    else
        find_local_files "$source"
    fi
done

if [[ ${#WIC_FILES[@]} -eq 0 ]]; then
    echo "No WIC files found"
    exit 0
fi

echo ""
echo "Found ${#WIC_FILES[@]} WIC file(s)"

# Function to parse device type from filename
parse_device_type() {
    local filename="$1"
    local lower_name=$(echo "$filename" | tr '[:upper:]' '[:lower:]')

    # Check for simpad2 first (must come before simpad check)
    if [[ "$lower_name" =~ simpad2|plus2|imx8 ]]; then
        echo "Plus2"
    # Check for simpad (SimPad Plus / imx6)
    elif [[ "$lower_name" =~ simpad|plus|imx6 ]]; then
        echo "Plus"
    elif [[ "$lower_name" =~ simman.*64 ]]; then
        echo "SimMan3G-64"
    elif [[ "$lower_name" =~ simman.*32 ]]; then
        echo "SimMan3G-32"
    elif [[ "$lower_name" =~ simman ]]; then
        echo "SimMan3G"
    else
        echo "unknown"
    fi
}

# Function to extract version from filename
parse_version() {
    local filename="$1"
    local version=""

    # Try different version patterns
    if [[ "$filename" =~ v?([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        version="${BASH_REMATCH[1]}"
    elif [[ "$filename" =~ ([0-9]{4}\.[0-9]{2}\.[0-9]{2}) ]]; then
        version="${BASH_REMATCH[1]}"
    elif [[ "$filename" =~ ([0-9]+\.[0-9]+) ]]; then
        version="${BASH_REMATCH[1]}"
    else
        version="0.0.0"
    fi

    echo "$version"
}

# Function to get display name
get_display_name() {
    local device_type="$1"
    local lower_type=$(echo "$device_type" | tr '[:upper:]' '[:lower:]')

    case "$lower_type" in
        plus2|imx8) echo "SimPad Plus 2" ;;
        plus|imx6) echo "SimPad Plus" ;;
        simman3g-64) echo "SimMan 3G (64-bit)" ;;
        simman3g-32) echo "SimMan 3G (32-bit)" ;;
        simman3g) echo "SimMan 3G" ;;
        *) echo "$device_type" ;;
    esac
}

# Function to get device tag
get_device_tag() {
    local device_type="$1"
    local lower_type=$(echo "$device_type" | tr '[:upper:]' '[:lower:]')

    case "$lower_type" in
        plus2) echo "imx8" ;;
        plus) echo "imx6" ;;
        simman3g-64) echo "simman3g-64" ;;
        simman3g-32) echo "simman3g-32" ;;
        *) echo "$lower_type" ;;
    esac
}

# Function to get icon
get_icon() {
    local device_type="$1"
    local lower_type=$(echo "$device_type" | tr '[:upper:]' '[:lower:]')

    case "$lower_type" in
        plus2) echo "icons/simpad_plus2.svg" ;;
        plus) echo "icons/simpad_plus.svg" ;;
        simman*) echo "icons/simman3g.svg" ;;
        *) echo "icons/use_custom.png" ;;
    esac
}

# Build os_list array
OS_LIST_JSON="[]"

for filepath in "${WIC_FILES[@]}"; do
    filename=$(basename "$filepath")
    echo ""
    echo "Processing: $filename"

    # Parse metadata
    device_type=$(parse_device_type "$filename")
    version=$(parse_version "$filename")
    display_name=$(get_display_name "$device_type")
    device_tag=$(get_device_tag "$device_type")
    icon=$(get_icon "$device_type")

    echo "  Device Type: $device_type"
    echo "  Version: $version"

    # Calculate hashes
    echo "  Calculating MD5..."
    md5_hash=$(md5sum "$filepath" | cut -d' ' -f1)

    echo "  Calculating SHA256..."
    sha256_hash=$(sha256sum "$filepath" | cut -d' ' -f1)

    # Get file size
    download_size=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null)

    # Estimate extract size (assume 4x compression for WIC)
    extract_size=$((download_size * 4))

    # Get release date from file modification time + 2 weeks
    file_mtime=$(stat -c%Y "$filepath" 2>/dev/null || stat -f%m "$filepath" 2>/dev/null)
    release_date=$(date -d "@$((file_mtime + 14*24*60*60))" +%Y-%m-%d 2>/dev/null || date -r "$((file_mtime + 14*24*60*60))" +%Y-%m-%d)

    # Build blob path and URL
    blob_path="${TARGET_PATH}/${filename}"
    download_url="${CDN_URL}/${CONTAINER}/${blob_path}"

    echo "  MD5: $md5_hash"
    echo "  SHA256: $sha256_hash"
    echo "  Size: $download_size"
    echo "  Release Date: $release_date"
    echo "  URL: $download_url"

    # Add to Raspberry Pi Imager format os_list
    os_entry=$(jq -n \
        --arg name "$display_name v$version" \
        --arg description "$display_name firmware version $version" \
        --arg url "$download_url" \
        --arg icon "$icon" \
        --argjson extract_size "$extract_size" \
        --arg extract_sha256 "$sha256_hash" \
        --arg extract_md5 "$md5_hash" \
        --argjson image_download_size "$download_size" \
        --arg release_date "$release_date" \
        --arg init_format "none" \
        --argjson devices "[\"$device_tag\"]" \
        '{
            name: $name,
            description: $description,
            url: $url,
            icon: $icon,
            extract_size: $extract_size,
            extract_sha256: $extract_sha256,
            extract_md5: $extract_md5,
            image_download_size: $image_download_size,
            release_date: $release_date,
            init_format: $init_format,
            devices: $devices
        }')

    OS_LIST_JSON=$(echo "$OS_LIST_JSON" | jq --argjson entry "$os_entry" '. + [$entry]')

    # Upload WIC file
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "  Uploading to CDN..."
        az storage blob upload \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" \
            --container-name "$CONTAINER" \
            --name "$blob_path" \
            --file "$filepath" \
            --overwrite \
            --no-progress
    else
        echo "  [DRY RUN] Would upload to: $blob_path"
    fi
done

# Generate Raspberry Pi Imager format JSON
OUTPUT_JSON_CONTENT=$(jq -n --argjson os_list "$OS_LIST_JSON" '{
    os_list: $os_list
}')

echo ""
echo "=== Generated JSON ==="
echo "$OUTPUT_JSON_CONTENT" | jq .

# Save and upload JSON file
TEMP_DIR=$(mktemp -d)
JSON_FILE="${TEMP_DIR}/${OUTPUT_JSON}"

echo "$OUTPUT_JSON_CONTENT" > "$JSON_FILE"

if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    echo "Uploading JSON file..."

    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER" \
        --name "${TARGET_PATH}/${OUTPUT_JSON}" \
        --file "$JSON_FILE" \
        --content-type "application/json" \
        --overwrite \
        --no-progress

    echo "Uploaded: ${TARGET_PATH}/${OUTPUT_JSON}"

    echo ""
    echo "=== Upload Complete ==="
    echo "JSON URL: ${CDN_URL}/${CONTAINER}/${TARGET_PATH}/${OUTPUT_JSON}"
else
    echo ""
    echo "[DRY RUN] Would upload:"
    echo "  - ${TARGET_PATH}/${OUTPUT_JSON}"
fi

# Cleanup
rm -rf "$TEMP_DIR"

if [[ "$KEEP_CACHE" == "false" ]]; then
    echo ""
    echo "Cleaning up cache..."
    rm -rf "$CACHE_DIR"
else
    echo ""
    echo "Cache kept at: $CACHE_DIR"
fi

echo ""
echo "Done!"
