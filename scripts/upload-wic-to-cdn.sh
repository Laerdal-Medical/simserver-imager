#!/bin/bash
#
# Upload WIC/VSI files to Azure Blob Storage and generate JSON manifest
#
# Usage:
#   ./upload-wic-to-cdn.sh [options] <source1> [source2] ...
#
# Sources can be:
#   - Local folders: /path/to/images
#   - Local with pattern: /path/to/images/*.vsi or /path/to/builds/Release*
#   - Remote SSH paths: user@server:/path/to/images
#   - Remote SSH with pattern: user@server:/path/*.vsi or user@server:/builds/Release*
#   - JSON URL: https://example.com/images.json (fetches URLs from os_list)
#
# Pattern matching:
#   - Patterns can match files directly: *.vsi, simpad*.wic.zst
#   - Patterns can match directories: Release*, build-202*
#   - When a pattern matches directories, all image files within are included
#
# Supported formats:
#   - WIC files: .wic, .wic.zst, .wic.xz, .wic.gz, .wic.bz2
#   - VSI files: .vsi (Versioned Sparse Image - Laerdal format)
#   - SPU files: .spu (SimPad Update - ISO UDF format)
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
#   --vsi-only        Only process VSI files (ignore WIC/SPU files)
#   --wic-only        Only process WIC files (ignore VSI/SPU files)
#   --spu-only        Only process SPU files (ignore WIC/VSI files)
#   --append          Fetch existing JSON from CDN and merge new entries (updates existing, adds new)
#   --skip-existing   Skip upload if blob already exists on CDN (still updates JSON)
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
#   # Local with file pattern
#   ./upload-wic-to-cdn.sh '/path/to/images/simpad*.vsi'
#
#   # Local with directory pattern (searches all matching directories)
#   ./upload-wic-to-cdn.sh '/path/to/builds/Release*'
#
#   # Remote SSH source (all images in directory)
#   ./upload-wic-to-cdn.sh user@buildserver:/opt/yocto/deploy/images
#
#   # Remote SSH with file pattern
#   ./upload-wic-to-cdn.sh 'user@buildserver:/opt/yocto/deploy/images/simpad*.vsi'
#
#   # Remote SSH with directory pattern
#   ./upload-wic-to-cdn.sh 'user@buildserver:/builds/Release*'
#
#   # Mix of local and remote, keep cache
#   ./upload-wic-to-cdn.sh --keep-cache -i ~/.ssh/id_rsa \
#     /local/wics user@server1:/builds user@server2:/images
#
#   # From JSON URL (downloads WIC files listed in os_list)
#   ./upload-wic-to-cdn.sh https://laerdalcdn.blob.core.windows.net/software/release/SimPad/factory-images/images.json
#
#   # Upload only VSI files
#   ./upload-wic-to-cdn.sh --vsi-only /path/to/images
#
#   # Upload only WIC files
#   ./upload-wic-to-cdn.sh --wic-only /path/to/images
#
#   # Append new VSI images to existing JSON (keeps existing WIC entries)
#   ./upload-wic-to-cdn.sh --append --vsi-only /path/to/vsi-images
#
#   # Upload only SPU files (firmware updates)
#   ./upload-wic-to-cdn.sh --spu-only /path/to/spu-images
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
VSI_ONLY=false
WIC_ONLY=false
SPU_ONLY=false
APPEND_MODE=false
SKIP_EXISTING=false
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
        --vsi-only)
            VSI_ONLY=true
            shift
            ;;
        --wic-only)
            WIC_ONLY=true
            shift
            ;;
        --spu-only)
            SPU_ONLY=true
            shift
            ;;
        --append)
            APPEND_MODE=true
            shift
            ;;
        --skip-existing)
            SKIP_EXISTING=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            head -80 "$0" | tail -79
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

# Check for mutually exclusive options
exclusive_count=0
[[ "$VSI_ONLY" == "true" ]] && ((exclusive_count++)) || true
[[ "$WIC_ONLY" == "true" ]] && ((exclusive_count++)) || true
[[ "$SPU_ONLY" == "true" ]] && ((exclusive_count++)) || true
if [[ $exclusive_count -gt 1 ]]; then
    echo "Error: Cannot specify more than one of --vsi-only, --wic-only, --spu-only" >&2
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
for cmd in jq sha256sum md5sum rsync curl xxd; do
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

echo "=== WIC/VSI File Uploader ==="
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER"
echo "Target Path: $TARGET_PATH"
echo "CDN URL: $CDN_URL"
echo "Cache Dir: $CACHE_DIR"
echo "Keep Cache: $KEEP_CACHE"
echo "Dry Run: $DRY_RUN"
echo "Append Mode: $APPEND_MODE"
echo "Skip Existing: $SKIP_EXISTING"
if [[ "$VSI_ONLY" == "true" ]]; then
    echo "File Filter: VSI only"
elif [[ "$WIC_ONLY" == "true" ]]; then
    echo "File Filter: WIC only"
elif [[ "$SPU_ONLY" == "true" ]]; then
    echo "File Filter: SPU only"
else
    echo "File Filter: WIC + VSI + SPU"
fi
if [[ -n "$SSH_KEY" ]]; then
    echo "SSH Key: $SSH_KEY"
fi
echo ""

# Create cache directory
mkdir -p "$CACHE_DIR"

# Function to check if a blob exists on Azure Storage
blob_exists() {
    local blob_path="$1"
    local result
    result=$(az storage blob exists \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER" \
        --name "$blob_path" \
        --output tsv 2>/dev/null)
    [[ "$result" == "True" ]]
}

# Function to build find pattern based on mode
get_find_pattern() {
    if [[ "$VSI_ONLY" == "true" ]]; then
        echo "-name '*.vsi'"
    elif [[ "$WIC_ONLY" == "true" ]]; then
        echo "\( -name '*.wic' -o -name '*.wic.zst' -o -name '*.wic.xz' -o -name '*.wic.gz' -o -name '*.wic.bz2' \)"
    elif [[ "$SPU_ONLY" == "true" ]]; then
        echo "-name '*.spu'"
    else
        echo "\( -name '*.wic' -o -name '*.wic.zst' -o -name '*.wic.xz' -o -name '*.wic.gz' -o -name '*.wic.bz2' -o -name '*.vsi' -o -name '*.spu' \)"
    fi
}

# Function to check if file matches current mode filter
matches_mode_filter() {
    local filename="$1"
    if [[ "$VSI_ONLY" == "true" ]]; then
        [[ "$filename" == *.vsi ]]
    elif [[ "$WIC_ONLY" == "true" ]]; then
        [[ "$filename" == *.wic || "$filename" == *.wic.zst || "$filename" == *.wic.xz || "$filename" == *.wic.gz || "$filename" == *.wic.bz2 ]]
    elif [[ "$SPU_ONLY" == "true" ]]; then
        [[ "$filename" == *.spu ]]
    else
        [[ "$filename" == *.wic || "$filename" == *.wic.zst || "$filename" == *.wic.xz || "$filename" == *.wic.gz || "$filename" == *.wic.bz2 || "$filename" == *.vsi || "$filename" == *.spu ]]
    fi
}

# Function to check if file is a VSI file
is_vsi_file() {
    [[ "$1" == *.vsi ]]
}

# Function to check if file is an SPU file
is_spu_file() {
    [[ "$1" == *.spu ]]
}

# Function to check if source is a JSON URL
is_json_url() {
    [[ "$1" == http://* || "$1" == https://* ]] && [[ "$1" == *.json ]]
}

# Function to check if source is remote (SSH)
is_remote() {
    [[ "$1" == *:* && "$1" != /* && "$1" != http://* && "$1" != https://* ]]
}

# Function to fetch image files from JSON URL (os_list format)
fetch_from_json_url() {
    local json_url="$1"

    echo "Fetching image list from JSON: $json_url"

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
        echo "  No image URLs found in JSON"
        return
    fi

    # Download each image file (filter based on mode)
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue

        local filename
        filename=$(basename "$url")

        # Check if file matches current mode filter
        if ! matches_mode_filter "$filename"; then
            echo "  Skipping (mode filter): $filename"
            continue
        fi

        local local_path="$CACHE_DIR/$filename"
        local blob_path="${TARGET_PATH}/${filename}"

        # Check if blob already exists when --skip-existing is enabled
        if [[ "$SKIP_EXISTING" == "true" && "$DRY_RUN" == "false" ]]; then
            if blob_exists "$blob_path"; then
                echo "  Skipping download (already on CDN): $filename"
                # For JSON URL source, we don't have remote path or build date
                # Store: filename|blob_path|local_path|remote_path|build_date
                SKIPPED_FILES+=("${filename}|${blob_path}|${local_path}||")
                continue
            fi
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would download: $filename"
        else
            echo "  Downloading: $filename"
            curl -L --progress-bar -o "$local_path" "$url" || {
                echo "  Warning: Failed to download $url" >&2
                continue
            }
            IMAGE_FILES+=("$local_path")
            echo "  Downloaded: $filename"
        fi
    done <<< "$urls"
}

# Function to check if path contains glob pattern characters
has_glob_pattern() {
    [[ "$1" == *"*"* || "$1" == *"?"* || "$1" == *"["* ]]
}

# Function to fetch files from remote source using rsync
fetch_remote_files() {
    local source="$1"
    local host="${source%%:*}"
    local remote_path="${source#*:}"

    # Build SSH options
    local ssh_opts="-o StrictHostKeyChecking=accept-new -o BatchMode=yes"
    if [[ -n "$SSH_KEY" ]]; then
        ssh_opts="$ssh_opts -i $SSH_KEY"
    fi

    local remote_files=""

    # Check if remote_path contains a glob pattern
    if has_glob_pattern "$remote_path"; then
        echo "Fetching image files from $host:$remote_path (pattern match)..."
        echo "  Expanding pattern on remote..."

        # Build find pattern for file types based on mode
        local find_pattern
        find_pattern=$(get_find_pattern)

        # First expand the glob pattern to get matching paths (files or directories)
        # Then search within those paths for image files
        # This handles both:
        #   - user@server:/path/to/*.vsi (pattern matches files directly)
        #   - user@server:/path/Release* (pattern matches directories)
        remote_files=$(ssh $ssh_opts "$host" "
            shopt -s nullglob
            for path in $remote_path; do
                if [[ -f \"\$path\" ]]; then
                    echo \"\$path\"
                elif [[ -d \"\$path\" ]]; then
                    find \"\$path\" -type f $find_pattern 2>/dev/null
                fi
            done
        " 2>/dev/null || true)

        # Filter results based on mode (--vsi-only, --wic-only)
        if [[ -n "$remote_files" ]]; then
            local filtered_files=""
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                local filename
                filename=$(basename "$file")
                if matches_mode_filter "$filename"; then
                    filtered_files+="$file"$'\n'
                fi
            done <<< "$remote_files"
            remote_files="$filtered_files"
        fi
    else
        echo "Fetching image files from $host:$remote_path (recursive)..."

        # First, find all image files on remote using SSH
        local find_pattern
        find_pattern=$(get_find_pattern)
        echo "  Scanning remote for image files..."
        remote_files=$(ssh $ssh_opts "$host" "find '$remote_path' -type f $find_pattern 2>/dev/null" || true)
    fi

    if [[ -z "$remote_files" ]]; then
        echo "  No image files found on remote"
        return
    fi

    # Deduplicate remote files - keep only the latest build per filename
    # For SPU files with same name in different build directories, keep the newest
    echo "  Deduplicating remote files..."
    local -A latest_remote_files  # filename -> "full_path|timestamp"

    while IFS= read -r remote_file; do
        [[ -z "$remote_file" ]] && continue
        local filename
        filename=$(basename "$remote_file")

        # Extract build timestamp from path
        local dir_name ts
        dir_name=$(dirname "$remote_file")
        dir_name=$(basename "$dir_name")
        if [[ "$dir_name" =~ ([0-9]{4})-?([0-9]{2})-?([0-9]{2})-?([0-9]{4})? ]]; then
            ts="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]:-0000}"
        else
            ts="0"
        fi

        if [[ -z "${latest_remote_files[$filename]:-}" ]]; then
            latest_remote_files[$filename]="${remote_file}|${ts}"
        else
            local existing_entry="${latest_remote_files[$filename]}"
            local existing_ts="${existing_entry#*|}"
            if [[ "$ts" > "$existing_ts" ]]; then
                echo "    [$filename] Replacing older build ($existing_ts) with newer ($ts)"
                latest_remote_files[$filename]="${remote_file}|${ts}"
            fi
        fi
    done <<< "$remote_files"

    # Rebuild remote_files with deduplicated list
    remote_files=""
    for filename in "${!latest_remote_files[@]}"; do
        local entry="${latest_remote_files[$filename]}"
        local filepath="${entry%|*}"
        remote_files+="$filepath"$'\n'
    done
    echo "  After deduplication: $(echo "$remote_files" | grep -c . || echo 0) file(s)"

    # Download each file to flat cache directory
    while IFS= read -r remote_file; do
        [[ -z "$remote_file" ]] && continue
        local filename
        filename=$(basename "$remote_file")
        local local_path="$CACHE_DIR/$filename"
        local blob_path="${TARGET_PATH}/${filename}"

        # Check if blob already exists when --skip-existing is enabled
        if [[ "$SKIP_EXISTING" == "true" && "$DRY_RUN" == "false" ]]; then
            if blob_exists "$blob_path"; then
                echo "  Skipping download (already on CDN): $filename"
                # Extract build date from remote path for release date
                local dir_name build_date
                dir_name=$(dirname "$remote_file")
                dir_name=$(basename "$dir_name")
                if [[ "$dir_name" =~ ([0-9]{4})-([0-9]{2})-([0-9]{2})-?([0-9]{4})? ]]; then
                    # Convert to ISO date format YYYY-MM-DD
                    build_date="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
                else
                    build_date=""
                fi
                # Store: filename|blob_path|local_path|remote_path|build_date
                SKIPPED_FILES+=("${filename}|${blob_path}|${local_path}|${remote_file}|${build_date}")
                continue
            fi
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "  [DRY RUN] Would download: $filename"
        else
            echo "  Downloading: $filename"
            rsync -avz --progress \
                -e "ssh $ssh_opts" \
                "$host:$remote_file" "$local_path"
        fi

        # Add to IMAGE_FILES array
        if [[ "$DRY_RUN" == "false" ]]; then
            IMAGE_FILES+=("$local_path")
            echo "  Downloaded: $filename"
        fi
    done <<< "$remote_files"
}

# Function to find local image files (WIC and/or VSI)
# Supports both directory paths and glob patterns
# Patterns can match files directly (*.vsi) or directories (Release*)
find_local_files() {
    local source="$1"

    # Check if source contains a glob pattern
    if has_glob_pattern "$source"; then
        echo "Searching with pattern: $source"

        # Use bash glob expansion (nullglob handles no matches)
        shopt -s nullglob
        local paths=($source)
        shopt -u nullglob

        if [[ ${#paths[@]} -eq 0 ]]; then
            echo "  No paths matched pattern"
            return
        fi

        for path in "${paths[@]}"; do
            if [[ -f "$path" ]]; then
                # Pattern matched a file directly
                local filename
                filename=$(basename "$path")

                # Apply mode filter
                if matches_mode_filter "$filename"; then
                    IMAGE_FILES+=("$path")
                    echo "  Found: $path"
                fi
            elif [[ -d "$path" ]]; then
                # Pattern matched a directory - search within it
                echo "  Searching in matched directory: $path"

                # Build find command based on mode
                local find_cmd="find \"$path\" -type f"
                if [[ "$VSI_ONLY" == "true" ]]; then
                    find_cmd="$find_cmd -name '*.vsi'"
                elif [[ "$WIC_ONLY" == "true" ]]; then
                    find_cmd="$find_cmd \( -name '*.wic' -o -name '*.wic.zst' -o -name '*.wic.xz' -o -name '*.wic.gz' -o -name '*.wic.bz2' \)"
                elif [[ "$SPU_ONLY" == "true" ]]; then
                    find_cmd="$find_cmd -name '*.spu'"
                else
                    find_cmd="$find_cmd \( -name '*.wic' -o -name '*.wic.zst' -o -name '*.wic.xz' -o -name '*.wic.gz' -o -name '*.wic.bz2' -o -name '*.vsi' -o -name '*.spu' \)"
                fi
                find_cmd="$find_cmd -print0"

                while IFS= read -r -d '' file; do
                    IMAGE_FILES+=("$file")
                    echo "  Found: $file"
                done < <(eval "$find_cmd")
            fi
        done
    else
        # Treat as directory path
        local folder="$source"

        if [[ ! -d "$folder" ]]; then
            echo "Warning: Local folder not found: $folder"
            return
        fi

        echo "Searching in: $folder"

        # Build find command based on mode
        local find_cmd="find \"$folder\" -type f"
        if [[ "$VSI_ONLY" == "true" ]]; then
            find_cmd="$find_cmd -name '*.vsi'"
        elif [[ "$WIC_ONLY" == "true" ]]; then
            find_cmd="$find_cmd \( -name '*.wic' -o -name '*.wic.zst' -o -name '*.wic.xz' -o -name '*.wic.gz' -o -name '*.wic.bz2' \)"
        elif [[ "$SPU_ONLY" == "true" ]]; then
            find_cmd="$find_cmd -name '*.spu'"
        else
            find_cmd="$find_cmd \( -name '*.wic' -o -name '*.wic.zst' -o -name '*.wic.xz' -o -name '*.wic.gz' -o -name '*.wic.bz2' -o -name '*.vsi' -o -name '*.spu' \)"
        fi
        find_cmd="$find_cmd -print0"

        while IFS= read -r -d '' file; do
            IMAGE_FILES+=("$file")
            echo "  Found: $file"
        done < <(eval "$find_cmd")
    fi
}

# Collect image files from all sources
IMAGE_FILES=()
# Track files that already exist on CDN (skipped downloads) - stores "filename|blob_path|local_path"
SKIPPED_FILES=()
for source in "${SOURCES[@]}"; do
    if is_json_url "$source"; then
        fetch_from_json_url "$source"
    elif is_remote "$source"; then
        fetch_remote_files "$source"
    else
        find_local_files "$source"
    fi
done

if [[ ${#IMAGE_FILES[@]} -eq 0 && ${#SKIPPED_FILES[@]} -eq 0 ]]; then
    echo "No image files found"
    exit 0
fi

echo ""
echo "Found ${#IMAGE_FILES[@]} image file(s) before deduplication"

# Function to parse device type from filename
parse_device_type() {
    local filename="$1"
    local lower_name=$(echo "$filename" | tr '[:upper:]' '[:lower:]')

    # Check specific device types first (more specific patterns before generic ones)
    # Check for "2" variants first (imx8-based)
    if [[ "$lower_name" =~ linkbox2|linkbox.*imx8 ]]; then
        echo "LinkBox2"
    elif [[ "$lower_name" =~ cancpu2|cancpu.*imx8 ]]; then
        echo "CANCPU2"
    elif [[ "$lower_name" =~ linkbox ]]; then
        echo "LinkBox"
    elif [[ "$lower_name" =~ cancpu ]]; then
        echo "CANCPU"
    elif [[ "$lower_name" =~ simpad2|plus2|imx8 ]]; then
        echo "Plus2"
    # Check for simpad (SimPad Plus / imx6) - must be explicit simpad, not just "plus"
    elif [[ "$lower_name" =~ simpad|imx6 ]]; then
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

# Function to extract build timestamp from path (e.g., /path/2024-07-10-1036/file.spu -> 2024071010360)
# Returns a sortable timestamp string, or file mtime if no build date found
get_build_timestamp() {
    local filepath="$1"
    local dir_name
    dir_name=$(dirname "$filepath")
    dir_name=$(basename "$dir_name")

    # Try to extract date from directory name (format: YYYY-MM-DD-HHMM or similar)
    if [[ "$dir_name" =~ ([0-9]{4})-?([0-9]{2})-?([0-9]{2})-?([0-9]{4})? ]]; then
        local ts="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]:-0000}"
        echo "$ts"
        return
    fi

    # Fallback to file modification time
    local mtime
    mtime=$(stat -c%Y "$filepath" 2>/dev/null || stat -f%m "$filepath" 2>/dev/null || echo "0")
    echo "$mtime"
}

# Function to get dedup key (base filename without build-specific parts)
# For SPU: use filename as-is (e.g., simpad-system-9.0.2.41.spu)
# For WIC/VSI: use device type + version
get_dedup_key() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    # For SPU files, the filename itself is the key (same name = same update)
    if [[ "$filename" == *.spu ]]; then
        echo "$filename"
        return
    fi

    # For WIC/VSI, extract device type and version
    local device_type version
    device_type=$(parse_device_type "$filename")
    version=$(parse_version "$filename")
    echo "${device_type}_${version}"
}

# Deduplicate files - keep only the latest build per version
deduplicate_files() {
    local -n files_array=$1
    local -A latest_files  # key -> "filepath|timestamp"

    echo "Deduplicating files..."

    for filepath in "${files_array[@]}"; do
        local key timestamp
        key=$(get_dedup_key "$filepath")
        timestamp=$(get_build_timestamp "$filepath")
        local filename
        filename=$(basename "$filepath")

        if [[ -z "${latest_files[$key]:-}" ]]; then
            # First file for this key
            latest_files[$key]="${filepath}|${timestamp}"
            echo "  [$key] First: $filename (ts: $timestamp)"
        else
            # Compare with existing
            local existing_entry="${latest_files[$key]}"
            local existing_ts="${existing_entry#*|}"

            if [[ "$timestamp" > "$existing_ts" ]]; then
                local old_file="${existing_entry%|*}"
                echo "  [$key] Replacing $(basename "$old_file") with $filename (ts: $timestamp > $existing_ts)"
                latest_files[$key]="${filepath}|${timestamp}"
            else
                echo "  [$key] Keeping existing, skipping $filename (ts: $timestamp <= $existing_ts)"
            fi
        fi
    done

    # Rebuild array with deduplicated files
    files_array=()
    for key in "${!latest_files[@]}"; do
        local entry="${latest_files[$key]}"
        local filepath="${entry%|*}"
        files_array+=("$filepath")
    done

    echo "After deduplication: ${#files_array[@]} file(s)"
}

# Apply deduplication to IMAGE_FILES
if [[ ${#IMAGE_FILES[@]} -gt 1 ]]; then
    deduplicate_files IMAGE_FILES
fi

echo ""
echo "Found ${#IMAGE_FILES[@]} image file(s) to process"
if [[ ${#SKIPPED_FILES[@]} -gt 0 ]]; then
    echo "Found ${#SKIPPED_FILES[@]} file(s) already on CDN (metadata only)"
fi

# Function to get display name
get_display_name() {
    local device_type="$1"
    local lower_type=$(echo "$device_type" | tr '[:upper:]' '[:lower:]')

    case "$lower_type" in
        plus2|imx8) echo "SimPad PLUS 2 System" ;;
        plus|imx6) echo "SimPad PLUS System" ;;
        linkbox2) echo "Link Box PLUS 2" ;;
        linkbox) echo "Link Box PLUS" ;;
        cancpu2) echo "CANCPU Module 2" ;;
        cancpu) echo "CANCPU Module" ;;
        simman3g-64) echo "SimMan 3G (64-bit)" ;;
        simman3g-32) echo "SimMan 3G (32-bit)" ;;
        simman3g) echo "SimMan 3G" ;;
        *) echo "$device_type" ;;
    esac
}

# Function to get device tags as JSON array
# SimPad Plus WIC images can run on CANCPU and LinkBox devices too
# VSI images are device-specific
get_device_tags() {
    local device_type="$1"
    local is_vsi="$2"  # "true" or "false"
    local lower_type=$(echo "$device_type" | tr '[:upper:]' '[:lower:]')

    case "$lower_type" in
        plus2)
            # SimPad Plus 2 WIC can also run on LinkBox2 and CANCPU2
            if [[ "$is_vsi" == "true" ]]; then
                echo '["imx8"]'
            else
                echo '["imx8", "linkbox2", "cancpu2"]'
            fi
            ;;
        plus)
            # SimPad Plus WIC can also run on LinkBox and CANCPU
            if [[ "$is_vsi" == "true" ]]; then
                echo '["imx6"]'
            else
                echo '["imx6", "linkbox", "cancpu"]'
            fi
            ;;
        linkbox2) echo '["linkbox2"]' ;;
        linkbox) echo '["linkbox"]' ;;
        cancpu2) echo '["cancpu2"]' ;;
        cancpu) echo '["cancpu"]' ;;
        simman3g-64) echo '["simman3g-64"]' ;;
        simman3g-32) echo '["simman3g-32"]' ;;
        *) echo "[\"$lower_type\"]" ;;
    esac
}

# Function to get icon
get_icon() {
    local device_type="$1"
    local lower_type=$(echo "$device_type" | tr '[:upper:]' '[:lower:]')

    case "$lower_type" in
        plus2) echo "icons/simpad_plus2.svg" ;;
        plus) echo "icons/simpad_plus.svg" ;;
        linkbox*) echo "icons/linkbox.svg" ;;
        cancpu*) echo "icons/cancpu.svg" ;;
        simman*) echo "icons/simman3g.svg" ;;
        *) echo "icons/use_custom.png" ;;
    esac
}

# Function to build os_entry JSON (RPI Imager format)
# Arguments: image_name description url icon extract_size md5_hash sha256_hash download_size release_date device_tags_json
# device_tags_json should be a JSON array like '["imx6", "cancpu", "linkbox"]'
# Note: Image type (wic/vsi/spu) is determined by URL extension, not a separate field
build_os_entry() {
    local image_name="$1"
    local description="$2"
    local url="$3"
    local icon="$4"
    local extract_size="$5"
    local md5_hash="$6"
    local sha256_hash="$7"
    local download_size="$8"
    local release_date="$9"
    local device_tags_json="${10}"

    local entry
    entry=$(jq -n \
        --arg name "$image_name" \
        --arg description "$description" \
        --arg url "$url" \
        --arg icon "$icon" \
        --argjson extract_size "$extract_size" \
        --arg extract_md5 "${md5_hash:-}" \
        --arg extract_sha256 "${sha256_hash:-}" \
        --argjson image_download_size "$download_size" \
        --arg release_date "$release_date" \
        --arg init_format "none" \
        --argjson devices "$device_tags_json" \
        '{
            name: $name,
            description: $description,
            url: $url,
            icon: $icon,
            extract_size: $extract_size,
            image_download_size: $image_download_size,
            release_date: $release_date,
            init_format: $init_format,
            devices: $devices
        } + (if $extract_md5 != "" then {extract_md5: $extract_md5} else {} end)
          + (if $extract_sha256 != "" then {extract_sha256: $extract_sha256} else {} end)')

    echo "$entry"
}

# Function to add or update os_entry in OS_LIST_JSON
# Sets url_exists to true/false as a side effect
add_or_update_os_entry() {
    local os_entry="$1"
    local download_url="$2"

    # Check if this URL already exists in the list
    url_exists=false
    for existing_url in "${EXISTING_URLS[@]}"; do
        if [[ "$existing_url" == "$download_url" ]]; then
            url_exists=true
            break
        fi
    done

    if [[ "$url_exists" == "true" ]]; then
        echo "  Updating existing entry in JSON"
        OS_LIST_JSON=$(echo "$OS_LIST_JSON" | jq --argjson entry "$os_entry" --arg url "$download_url" \
            'map(if .url == $url then $entry else . end)')
    else
        echo "  Adding new entry to JSON"
        OS_LIST_JSON=$(echo "$OS_LIST_JSON" | jq --argjson entry "$os_entry" '. + [$entry]')
        EXISTING_URLS+=("$download_url")
    fi
}

# Function to parse VSI header and extract metadata
# VSI Header (128 bytes, little-endian):
#   magic[4]           - "VSI1"
#   blockSize[4]       - int32
#   uncompressedSize[8] - int64
#   md5[16]            - MD5 of compressed payload
#   label[64]          - null-terminated string
#   version[28]        - null-terminated string
#   timestamp[4]       - int32 unix timestamp
parse_vsi_header() {
    local filepath="$1"
    local -n vsi_info=$2

    # Read the 128-byte header
    local header
    header=$(xxd -p -l 128 "$filepath" 2>/dev/null | tr -d '\n')

    if [[ -z "$header" || ${#header} -lt 256 ]]; then
        echo "  Warning: Could not read VSI header" >&2
        return 1
    fi

    # Check magic (first 4 bytes = "VSI1" = 56534931 in hex)
    local magic="${header:0:8}"
    if [[ "$magic" != "56534931" ]]; then
        echo "  Warning: Invalid VSI magic: $magic (expected 56534931)" >&2
        return 1
    fi

    # Parse blockSize (bytes 4-8, little-endian int32)
    local block_size_hex="${header:8:8}"
    # Reverse byte order for little-endian
    block_size_hex="${block_size_hex:6:2}${block_size_hex:4:2}${block_size_hex:2:2}${block_size_hex:0:2}"
    vsi_info[block_size]=$((16#$block_size_hex))

    # Parse uncompressedSize (bytes 8-16, little-endian int64)
    local uncomp_hex="${header:16:16}"
    # Reverse byte order for little-endian (8 bytes)
    uncomp_hex="${uncomp_hex:14:2}${uncomp_hex:12:2}${uncomp_hex:10:2}${uncomp_hex:8:2}${uncomp_hex:6:2}${uncomp_hex:4:2}${uncomp_hex:2:2}${uncomp_hex:0:2}"
    vsi_info[uncompressed_size]=$((16#$uncomp_hex))

    # Parse MD5 (bytes 16-32)
    vsi_info[md5]="${header:32:32}"

    # Parse label (bytes 32-96, null-terminated string)
    local label_hex="${header:64:128}"
    # Convert hex to ASCII, stopping at null
    local label=""
    for ((i=0; i<${#label_hex}; i+=2)); do
        local byte="${label_hex:$i:2}"
        if [[ "$byte" == "00" ]]; then
            break
        fi
        label+=$(printf "\\x$byte")
    done
    vsi_info[label]="$label"

    # Parse version (bytes 96-124, null-terminated string)
    local version_hex="${header:192:56}"
    local version=""
    for ((i=0; i<${#version_hex}; i+=2)); do
        local byte="${version_hex:$i:2}"
        if [[ "$byte" == "00" ]]; then
            break
        fi
        version+=$(printf "\\x$byte")
    done
    vsi_info[version]="$version"

    # Parse timestamp (bytes 124-128, little-endian int32)
    local ts_hex="${header:248:8}"
    ts_hex="${ts_hex:6:2}${ts_hex:4:2}${ts_hex:2:2}${ts_hex:0:2}"
    vsi_info[timestamp]=$((16#$ts_hex))

    return 0
}

# Function to parse SPU file metadata (ISO UDF format)
# SPU files contain vs2_label, vs2_sysversion, vs2_auth2 etc.
# Returns associative array with: label, version, date, devices (JSON array)
parse_spu_metadata() {
    local filepath="$1"
    local -n spu_info=$2
    local mount_point=""

    # Create temporary mount point
    mount_point=$(mktemp -d)

    # Try to mount the SPU file (ISO UDF format)
    local mounted=false
    if command -v fuseiso &>/dev/null; then
        if fuseiso "$filepath" "$mount_point" -o ro 2>/dev/null; then
            mounted=true
        fi
    fi

    if [[ "$mounted" == "false" ]]; then
        # Try system mount (requires root or sudo)
        if mount -t udf "$filepath" "$mount_point" -o loop,ro 2>/dev/null; then
            mounted=true
        fi
    fi

    if [[ "$mounted" == "false" ]]; then
        echo "  Warning: Could not mount SPU file (need fuseiso or root)" >&2
        rmdir "$mount_point" 2>/dev/null
        return 1
    fi

    # Read metadata files
    spu_info[label]=""
    spu_info[version]=""
    spu_info[date]=""
    spu_info[devices]="[]"

    if [[ -f "$mount_point/vs2_label" ]]; then
        spu_info[label]=$(cat "$mount_point/vs2_label" 2>/dev/null | tr -d '\n\r')
    fi

    if [[ -f "$mount_point/vs2_sysversion" ]]; then
        spu_info[version]=$(cat "$mount_point/vs2_sysversion" 2>/dev/null | tr -d '\n\r')
    fi

    if [[ -f "$mount_point/vs2_date" ]]; then
        spu_info[date]=$(cat "$mount_point/vs2_date" 2>/dev/null | tr -d '\n\r')
    fi

    # Parse vs2_auth2 to extract supported devices
    if [[ -f "$mount_point/vs2_auth2" ]]; then
        local devices=()
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue

            # Look for allow entries: "+ I=<product_id>"
            if [[ "$line" =~ ^\+[[:space:]]*I=([0-9-]+) ]]; then
                local product_id="${BASH_REMATCH[1]}"
                local device_tag=""

                # Map Product ID to device tag
                case "$product_id" in
                    20-19165*) device_tag="simman3g" ;;
                    20-1148*)  device_tag="cancpu" ;;
                    20-19560*) device_tag="cancpu2" ;;
                    204-30250*) device_tag="linkbox" ;;
                    20-19602*) device_tag="linkbox2" ;;
                    204-30150*) device_tag="imx6" ;;
                    20-19601*) device_tag="imx8" ;;
                esac

                # Add to devices array if not already present
                if [[ -n "$device_tag" ]]; then
                    local found=false
                    for d in "${devices[@]}"; do
                        [[ "$d" == "$device_tag" ]] && found=true && break
                    done
                    [[ "$found" == "false" ]] && devices+=("$device_tag")
                fi
            fi
        done < "$mount_point/vs2_auth2"

        # Convert to JSON array
        if [[ ${#devices[@]} -gt 0 ]]; then
            local json_array="["
            local first=true
            for d in "${devices[@]}"; do
                [[ "$first" == "true" ]] && first=false || json_array+=", "
                json_array+="\"$d\""
            done
            json_array+="]"
            spu_info[devices]="$json_array"
        fi
    fi

    # Unmount
    if command -v fusermount &>/dev/null; then
        fusermount -u "$mount_point" 2>/dev/null || true
    else
        umount "$mount_point" 2>/dev/null || true
    fi
    rmdir "$mount_point" 2>/dev/null

    return 0
}

# Initialize os_list array - fetch existing if in append mode
OS_LIST_JSON="[]"
EXISTING_URLS=()

if [[ "$APPEND_MODE" == "true" ]]; then
    existing_json_url="${CDN_URL}/${CONTAINER}/${TARGET_PATH}/${OUTPUT_JSON}"
    echo ""
    echo "Append mode: Fetching existing JSON from $existing_json_url"

    existing_json=$(curl -sS "$existing_json_url" 2>/dev/null || echo "")

    if [[ -n "$existing_json" ]] && echo "$existing_json" | jq -e '.os_list' &>/dev/null; then
        # Extract existing os_list
        OS_LIST_JSON=$(echo "$existing_json" | jq '.os_list // []')
        existing_count=$(echo "$OS_LIST_JSON" | jq 'length')
        echo "  Found $existing_count existing entries"

        # Build list of existing URLs for deduplication
        while IFS= read -r url; do
            [[ -n "$url" ]] && EXISTING_URLS+=("$url")
        done < <(echo "$OS_LIST_JSON" | jq -r '.[].url // empty')
    else
        echo "  No existing JSON found or invalid format, starting fresh"
    fi
fi

# Track new files being uploaded for deduplication
declare -A NEW_FILE_URLS

for filepath in "${IMAGE_FILES[@]}"; do
    filename=$(basename "$filepath")
    echo ""
    echo "Processing: $filename"

    # Determine file type
    is_vsi=false
    is_spu=false
    if is_vsi_file "$filename"; then
        is_vsi=true
        echo "  Format: VSI (Versioned Sparse Image)"
    elif is_spu_file "$filename"; then
        is_spu=true
        echo "  Format: SPU (SimPad Update)"
    else
        echo "  Format: WIC"
    fi

    # Parse metadata from filename (fallback)
    device_type=$(parse_device_type "$filename")
    version=$(parse_version "$filename")

    # For SPU files, try to extract metadata by mounting
    spu_label=""
    spu_version=""
    spu_date=""
    spu_devices="[]"
    if [[ "$is_spu" == "true" ]]; then
        declare -A spu_header
        if parse_spu_metadata "$filepath" spu_header; then
            spu_label="${spu_header[label]}"
            spu_version="${spu_header[version]}"
            spu_date="${spu_header[date]}"
            spu_devices="${spu_header[devices]}"
            echo "  SPU Label: $spu_label"
            echo "  SPU Version: $spu_version"
            echo "  SPU Date: $spu_date"
            echo "  SPU Devices: $spu_devices"
            # Use SPU version if available
            if [[ -n "$spu_version" ]]; then
                version="$spu_version"
            fi
        else
            echo "  Warning: Could not parse SPU metadata"
        fi
        unset spu_header
    fi

    # For VSI files, try to extract metadata from header
    vsi_label=""
    vsi_version=""
    vsi_timestamp=0
    if [[ "$is_vsi" == "true" ]]; then
        declare -A vsi_header
        if parse_vsi_header "$filepath" vsi_header; then
            extract_size="${vsi_header[uncompressed_size]}"
            vsi_label="${vsi_header[label]}"
            vsi_version="${vsi_header[version]}"
            vsi_timestamp="${vsi_header[timestamp]}"
            echo "  VSI Label: $vsi_label"
            echo "  VSI Version: $vsi_version"
            echo "  VSI Block Size: ${vsi_header[block_size]}"
            echo "  VSI Uncompressed Size: $extract_size"
            echo "  VSI Timestamp: $vsi_timestamp ($(date -d "@$vsi_timestamp" +%Y-%m-%d 2>/dev/null || date -r "$vsi_timestamp" +%Y-%m-%d 2>/dev/null || echo 'invalid'))"
            # Use VSI version if available and valid
            if [[ -n "$vsi_version" ]]; then
                version="$vsi_version"
            fi
        else
            echo "  Warning: Could not parse VSI header, using estimated extract size"
        fi
        unset vsi_header
    fi

    display_name=$(get_display_name "$device_type")
    # For SPU files, use devices from metadata; for others, use get_device_tags
    if [[ "$is_spu" == "true" && "$spu_devices" != "[]" ]]; then
        device_tags="$spu_devices"
    else
        device_tags=$(get_device_tags "$device_type" "$is_vsi")
    fi
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

    # For WIC files, estimate extract size (assume 4x compression)
    # For VSI files, we already got extract_size from header
    # For SPU files, extract_size equals download_size (no compression)
    if [[ "$is_spu" == "true" ]]; then
        extract_size=$download_size
    elif [[ "$is_vsi" != "true" ]]; then
        extract_size=$((download_size * 4))
    fi

    # Get release date
    # For VSI files with valid timestamp, use that
    # For SPU files with valid date, use that
    # Otherwise use file mtime
    if [[ "$is_vsi" == "true" && -n "$vsi_timestamp" && "$vsi_timestamp" -gt 0 ]] 2>/dev/null; then
        release_date=$(date -d "@$vsi_timestamp" +%Y-%m-%d 2>/dev/null || date -r "$vsi_timestamp" +%Y-%m-%d 2>/dev/null)
    elif [[ "$is_spu" == "true" && -n "$spu_date" ]]; then
        # SPU date is already in YYYY-MM-DD format or similar
        release_date="$spu_date"
    else
        file_mtime=$(stat -c%Y "$filepath" 2>/dev/null || stat -f%m "$filepath" 2>/dev/null)
        release_date=$(date -d "@$file_mtime" +%Y-%m-%d 2>/dev/null || date -r "$file_mtime" +%Y-%m-%d)
    fi

    # Build blob path and URL
    blob_path="${TARGET_PATH}/${filename}"
    download_url="${CDN_URL}/${CONTAINER}/${blob_path}"

    echo "  MD5: $md5_hash"
    echo "  SHA256: $sha256_hash"
    echo "  Download Size: $download_size"
    echo "  Extract Size: $extract_size"
    echo "  Release Date: $release_date"
    echo "  URL: $download_url"

    # Build name and description from VSI/SPU label if available
    # Only append version if it's not empty, not the default "0.0.0", and not already in the label
    version_suffix=""
    if [[ -n "$version" && "$version" != "0.0.0" ]]; then
        version_suffix=" v$version"
    fi

    if [[ -n "$spu_label" ]]; then
        # Check if label already contains the version number
        if [[ "$spu_label" == *"$version"* ]]; then
            image_name="$spu_label"
        else
            image_name="${spu_label}${version_suffix}"
        fi
        description="$spu_label firmware update"
    elif [[ -n "$vsi_label" ]]; then
        # Check if label already contains the version number
        if [[ "$vsi_label" == *"$version"* ]]; then
            image_name="$vsi_label"
        else
            image_name="${vsi_label}${version_suffix}"
        fi
        description="$vsi_label"
    else
        image_name="${display_name}${version_suffix}"
        description="$display_name firmware version $version"
    fi

    # Build the os_entry and add/update in JSON
    # Note: Image type (wic/vsi/spu) is determined by URL file extension
    os_entry=$(build_os_entry "$image_name" "$description" "$download_url" "$icon" \
        "$extract_size" "$md5_hash" "$sha256_hash" "$download_size" "$release_date" "$device_tags")
    add_or_update_os_entry "$os_entry" "$download_url"

    # Upload image file
    if [[ "$DRY_RUN" == "false" ]]; then
        should_upload=true

        # Check if blob already exists when --skip-existing is enabled
        if [[ "$SKIP_EXISTING" == "true" ]]; then
            echo "  Checking if blob exists..."
            if blob_exists "$blob_path"; then
                echo "  Skipping upload (blob already exists on CDN)"
                should_upload=false
            fi
        fi

        if [[ "$should_upload" == "true" ]]; then
            echo "  Uploading to CDN..."
            az storage blob upload \
                --account-name "$STORAGE_ACCOUNT" \
                --account-key "$STORAGE_KEY" \
                --container-name "$CONTAINER" \
                --name "$blob_path" \
                --file "$filepath" \
                --overwrite \
                --no-progress
        fi
    else
        echo "  [DRY RUN] Would upload to: $blob_path"
    fi
done

# Process skipped files (already on CDN) - try to get metadata from local file if available
for skipped_entry in "${SKIPPED_FILES[@]}"; do
    # Parse entry: filename|blob_path|local_path|remote_path|build_date
    IFS='|' read -r filename blob_path local_path remote_path source_build_date <<< "$skipped_entry"

    # Reset per-iteration variables
    blob_props=""
    blob_md5=""

    echo ""
    echo "Processing (existing on CDN): $filename"

    # Check if local file exists - try multiple locations:
    # 1. The stored local_path (cache directory)
    # 2. Search in original source directories for matching filename
    has_local_file=false
    if [[ -f "$local_path" ]]; then
        has_local_file=true
        echo "  Local file found: $local_path"
    else
        # Search for file in source directories
        for source in "${SOURCES[@]}"; do
            if [[ -d "$source" ]]; then
                found_file=$(find "$source" -name "$filename" -type f 2>/dev/null | head -1)
                if [[ -n "$found_file" && -f "$found_file" ]]; then
                    local_path="$found_file"
                    has_local_file=true
                    echo "  Local file found in source: $local_path"
                    break
                fi
            fi
        done
    fi

    # Fetch blob properties (needed for validation and later processing)
    echo "  Fetching blob properties..."
    blob_props=$(az storage blob show \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER" \
        --name "$blob_path" \
        --output json 2>/dev/null || echo "{}")

    blob_md5_b64=$(echo "$blob_props" | jq -r '.properties.contentSettings.contentMd5 // empty')
    if [[ -n "$blob_md5_b64" ]]; then
        blob_md5=$(echo "$blob_md5_b64" | base64 -d 2>/dev/null | xxd -p | tr -d '\n')
    fi

    # If local file found, validate checksum against blob
    if [[ "$has_local_file" == "true" && -n "$blob_md5" ]]; then
        echo "  Calculating local file MD5..."
        local_md5=$(md5sum "$local_path" | cut -d' ' -f1)

        if [[ "$local_md5" == "$blob_md5" ]]; then
            echo "  Checksum verified: local file matches CDN blob"
        else
            echo "  Checksum mismatch! Local: $local_md5, CDN: $blob_md5"
            echo "  Downloading correct version from CDN..."
            local_path="$CACHE_DIR/$filename"

            # Get blob URL and download
            blob_url="${CDN_URL}/${CONTAINER}/${blob_path}"
            if curl -L --progress-bar -o "$local_path" "$blob_url"; then
                echo "  Downloaded: $local_path"
                has_local_file=true
            else
                echo "  Warning: Failed to download from CDN - using blob metadata only"
                has_local_file=false
            fi
        fi
    elif [[ "$has_local_file" == "false" ]]; then
        # No local file found - download from CDN
        echo "  No local file found, downloading from CDN..."
        local_path="$CACHE_DIR/$filename"
        blob_url="${CDN_URL}/${CONTAINER}/${blob_path}"
        if curl -L --progress-bar -o "$local_path" "$blob_url"; then
            echo "  Downloaded: $local_path"
            has_local_file=true
        else
            echo "  Warning: Failed to download from CDN - using blob metadata only"
            has_local_file=false
        fi
    fi

    # Parse metadata from filename
    device_type=$(parse_device_type "$filename")
    version=$(parse_version "$filename")

    # Determine file type
    is_vsi=false
    is_spu=false
    if is_vsi_file "$filename"; then
        is_vsi=true
        echo "  Format: VSI (Versioned Sparse Image)"
    elif is_spu_file "$filename"; then
        is_spu=true
        echo "  Format: SPU (SimPad Update)"
    else
        echo "  Format: WIC"
    fi

    # For SPU files, try to extract metadata from local file by mounting
    spu_label=""
    spu_version=""
    spu_date=""
    spu_devices="[]"
    if [[ "$is_spu" == "true" && "$has_local_file" == "true" ]]; then
        declare -A spu_header
        if parse_spu_metadata "$local_path" spu_header; then
            spu_label="${spu_header[label]}"
            spu_version="${spu_header[version]}"
            spu_date="${spu_header[date]}"
            spu_devices="${spu_header[devices]}"
            echo "  SPU Label: $spu_label"
            echo "  SPU Version: $spu_version"
            echo "  SPU Date: $spu_date"
            echo "  SPU Devices: $spu_devices"
            # Use SPU version if available
            if [[ -n "$spu_version" ]]; then
                version="$spu_version"
            fi
        fi
        unset spu_header
    fi

    # For VSI files, try to extract metadata from local file header
    vsi_label=""
    vsi_version=""
    vsi_timestamp=0
    extract_size=0
    if [[ "$is_vsi" == "true" && "$has_local_file" == "true" ]]; then
        declare -A vsi_header
        if parse_vsi_header "$local_path" vsi_header; then
            extract_size="${vsi_header[uncompressed_size]}"
            vsi_label="${vsi_header[label]}"
            vsi_version="${vsi_header[version]}"
            vsi_timestamp="${vsi_header[timestamp]}"
            echo "  VSI Label: $vsi_label"
            echo "  VSI Version: $vsi_version"
            echo "  VSI Block Size: ${vsi_header[block_size]}"
            echo "  VSI Uncompressed Size: $extract_size"
            echo "  VSI Timestamp: $vsi_timestamp ($(date -d "@$vsi_timestamp" +%Y-%m-%d 2>/dev/null || date -r "$vsi_timestamp" +%Y-%m-%d 2>/dev/null || echo 'invalid'))"
            # Use VSI version if available and valid
            if [[ -n "$vsi_version" ]]; then
                version="$vsi_version"
            fi
        fi
        unset vsi_header
    fi

    display_name=$(get_display_name "$device_type")
    # For SPU files, use devices from metadata; for others, use get_device_tags
    if [[ "$is_spu" == "true" && "$spu_devices" != "[]" ]]; then
        device_tags="$spu_devices"
    else
        device_tags=$(get_device_tags "$device_type" "$is_vsi")
    fi
    icon=$(get_icon "$device_type")

    echo "  Device Type: $device_type"
    echo "  Version: $version"

    # Get blob properties from Azure (size, MD5) - only if not already fetched during validation
    if [[ -z "$blob_props" || "$blob_props" == "{}" ]]; then
        echo "  Fetching blob properties from CDN..."
        blob_props=$(az storage blob show \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" \
            --container-name "$CONTAINER" \
            --name "$blob_path" \
            --output json 2>/dev/null || echo "{}")
    fi

    download_size=$(echo "$blob_props" | jq -r '.properties.contentLength // 0')
    # Azure stores MD5 as base64, convert to hex (use cached value if available)
    if [[ -z "$blob_md5" ]]; then
        blob_md5_b64=$(echo "$blob_props" | jq -r '.properties.contentSettings.contentMd5 // empty')
        if [[ -n "$blob_md5_b64" ]]; then
            blob_md5=$(echo "$blob_md5_b64" | base64 -d 2>/dev/null | xxd -p | tr -d '\n')
        fi
    fi
    md5_hash="${blob_md5:-}"

    # For extract size: use VSI header if available, otherwise estimate
    # SPU files are uncompressed (no extract needed)
    if [[ "$extract_size" -eq 0 ]]; then
        if [[ "$is_spu" == "true" ]]; then
            # SPU files are uncompressed
            extract_size=$download_size
        elif [[ "$is_vsi" == "true" ]]; then
            # VSI files are typically ~2x compressed
            extract_size=$((download_size * 2))
        else
            extract_size=$((download_size * 4))
        fi
    fi

    # Get release date: prefer VSI timestamp, SPU date, source build date, then blob lastModified, then current date
    if [[ "$is_vsi" == "true" && -n "$vsi_timestamp" && "$vsi_timestamp" -gt 0 ]] 2>/dev/null; then
        release_date=$(date -d "@$vsi_timestamp" +%Y-%m-%d 2>/dev/null || date -r "$vsi_timestamp" +%Y-%m-%d 2>/dev/null)
        echo "  Release date from VSI header: $release_date"
    elif [[ "$is_spu" == "true" && -n "$spu_date" ]]; then
        release_date="$spu_date"
        echo "  Release date from SPU metadata: $release_date"
    elif [[ -n "$source_build_date" ]]; then
        # Use build date from source (SSH path) - already in YYYY-MM-DD format
        release_date="$source_build_date"
        echo "  Release date from source build directory: $release_date"
    elif [[ "$has_local_file" == "true" ]]; then
        file_mtime=$(stat -c%Y "$local_path" 2>/dev/null || stat -f%m "$local_path" 2>/dev/null)
        release_date=$(date -d "@$file_mtime" +%Y-%m-%d 2>/dev/null || date -r "$file_mtime" +%Y-%m-%d)
        echo "  Release date from local file mtime: $release_date"
    else
        blob_last_modified=$(echo "$blob_props" | jq -r '.properties.lastModified // empty')
        if [[ -n "$blob_last_modified" ]]; then
            release_date=$(date -d "$blob_last_modified" +%Y-%m-%d 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${blob_last_modified%%+*}" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
            echo "  Release date from blob lastModified: $release_date"
        else
            release_date=$(date +%Y-%m-%d)
        fi
    fi

    # Build blob URL
    download_url="${CDN_URL}/${CONTAINER}/${blob_path}"

    echo "  Download Size: $download_size"
    echo "  Extract Size: $extract_size (estimated)"
    echo "  URL: $download_url"
    if [[ -n "$md5_hash" ]]; then
        echo "  MD5: $md5_hash"
    fi

    # Build name and description from VSI/SPU label if available
    # Only append version if it's not empty, not the default "0.0.0", and not already in the label
    version_suffix=""
    if [[ -n "$version" && "$version" != "0.0.0" ]]; then
        version_suffix=" v$version"
    fi

    if [[ -n "$spu_label" ]]; then
        # Check if label already contains the version number
        if [[ "$spu_label" == *"$version"* ]]; then
            image_name="$spu_label"
        else
            image_name="${spu_label}${version_suffix}"
        fi
        description="$spu_label firmware update"
    elif [[ -n "$vsi_label" ]]; then
        # Check if label already contains the version number
        if [[ "$vsi_label" == *"$version"* ]]; then
            image_name="$vsi_label"
        else
            image_name="${vsi_label}${version_suffix}"
        fi
        description="$vsi_label"
    else
        image_name="${display_name}${version_suffix}"
        description="$display_name firmware version $version"
    fi

    # Build the os_entry and add/update in JSON (no sha256 for skipped files)
    # Note: Image type (wic/vsi/spu) is determined by URL file extension
    os_entry=$(build_os_entry "$image_name" "$description" "$download_url" "$icon" \
        "$extract_size" "$md5_hash" "" "$download_size" "$release_date" "$device_tags")
    add_or_update_os_entry "$os_entry" "$download_url"
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
