#!/bin/bash
#
# Regenerate Windows .ico file from SVG source
# Requires ImageMagick with librsvg support
#
# Usage: ./regenerate_icons_from_svg.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG_SOURCE="${SCRIPT_DIR}/../linux/icon/laerdal-simserver-imager.svg"
OUTPUT_ICO="${SCRIPT_DIR}/../icons/laerdal-simserver-imager.ico"

# Check for ImageMagick
if command -v magick &> /dev/null; then
    CONVERT_CMD="magick"
elif command -v convert &> /dev/null; then
    CONVERT_CMD="convert"
else
    echo "Error: ImageMagick not found. Please install ImageMagick."
    echo "  macOS: brew install imagemagick"
    echo "  Ubuntu/Debian: sudo apt install imagemagick librsvg2-bin"
    echo "  Windows: https://imagemagick.org/script/download.php"
    exit 1
fi

# Check SVG exists
if [[ ! -f "$SVG_SOURCE" ]]; then
    echo "Error: SVG source not found: $SVG_SOURCE"
    exit 1
fi

# Windows .ico sizes
SIZES=(16 20 24 32 40 48 64 256)

echo "Generating Windows icon from SVG..."
echo "Source: $SVG_SOURCE"
echo "Using ImageMagick: $CONVERT_CMD"
echo ""

# Create temporary directory for PNGs
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Generate PNGs at each size
INPUT_FILES=""
for size in "${SIZES[@]}"; do
    PNG_FILE="${TEMP_DIR}/icon_${size}.png"
    echo "  Generating ${size}x${size}..."
    $CONVERT_CMD -background none -density 300 "$SVG_SOURCE" -resize "${size}x${size}" "$PNG_FILE"
    INPUT_FILES="$INPUT_FILES $PNG_FILE"
done

# Generate .ico file
echo ""
echo "Creating ${OUTPUT_ICO}..."
$CONVERT_CMD $INPUT_FILES "$OUTPUT_ICO"

if [[ -f "$OUTPUT_ICO" ]]; then
    echo ""
    echo "Successfully created: ${OUTPUT_ICO}"
    ls -la "$OUTPUT_ICO"
else
    echo "Error: Failed to create ${OUTPUT_ICO}"
    exit 1
fi
