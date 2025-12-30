#!/bin/bash
#
# Regenerate macOS .icns file from SVG source
# Requires ImageMagick with librsvg support and macOS iconutil
#
# Usage: ./regenerate_icons_from_svg.sh
#
# NOTE: This script must be run on macOS (requires iconutil)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG_SOURCE="${SCRIPT_DIR}/../linux/icon/laerdal-simserver-imager.svg"
ICONSET_DIR="${SCRIPT_DIR}/../icons/laerdal-simserver-imager.iconset"
OUTPUT_ICNS="${SCRIPT_DIR}/../icons/laerdal-simserver-imager.icns"

# Check for macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: This script must be run on macOS (requires iconutil)"
    exit 1
fi

# Check for ImageMagick
if command -v magick &> /dev/null; then
    CONVERT_CMD="magick"
elif command -v convert &> /dev/null; then
    CONVERT_CMD="convert"
else
    echo "Error: ImageMagick not found. Please install ImageMagick."
    echo "  brew install imagemagick"
    exit 1
fi

# Check for iconutil
if ! command -v iconutil &> /dev/null; then
    echo "Error: iconutil not found (should be available on macOS)"
    exit 1
fi

# Check SVG exists
if [[ ! -f "$SVG_SOURCE" ]]; then
    echo "Error: SVG source not found: $SVG_SOURCE"
    exit 1
fi

echo "Generating macOS icon from SVG..."
echo "Source: $SVG_SOURCE"
echo "Using ImageMagick: $CONVERT_CMD"
echo ""

# Clean and create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# macOS iconset sizes (name -> actual pixels)
declare -A SIZES=(
    ["icon_16x16.png"]=16
    ["icon_16x16@2x.png"]=32
    ["icon_32x32.png"]=32
    ["icon_32x32@2x.png"]=64
    ["icon_128x128.png"]=128
    ["icon_128x128@2x.png"]=256
    ["icon_256x256.png"]=256
    ["icon_256x256@2x.png"]=512
    ["icon_512x512.png"]=512
    ["icon_512x512@2x.png"]=1024
)

# Generate PNGs at each size
for name in "${!SIZES[@]}"; do
    size=${SIZES[$name]}
    PNG_FILE="${ICONSET_DIR}/${name}"
    echo "  Generating ${name} (${size}x${size})..."
    $CONVERT_CMD -background none -density 300 "$SVG_SOURCE" -resize "${size}x${size}" "$PNG_FILE"
done

# Generate .icns file
echo ""
echo "Creating ${OUTPUT_ICNS}..."
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

if [[ -f "$OUTPUT_ICNS" ]]; then
    echo ""
    echo "Successfully created: ${OUTPUT_ICNS}"
    ls -la "$OUTPUT_ICNS"

    # Clean up iconset directory
    rm -rf "$ICONSET_DIR"
else
    echo "Error: Failed to create ${OUTPUT_ICNS}"
    exit 1
fi
