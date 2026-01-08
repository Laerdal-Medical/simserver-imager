# Laerdal SimServer Imager

A tool for writing system images to SD cards and USB memory sticks for Laerdal SimPad devices and SimMan3G simulators.

Based on [Raspberry Pi Imager](https://github.com/raspberrypi/rpi-imager).

## Supported Image Types

| Type | Extension | Description |
|------|-----------|-------------|
| **WIC** | `.wic`, `.wic.xz`, `.wic.gz`, `.wic.bz2`, `.wic.zst` | Standard disk image - complete flash of storage device |
| **VSI** | `.vsi` | Versioned Sparse Image - efficient delta updates |
| **SPU** | `.spu` | Software Package Update - firmware files copied to mounted device |

## Documentation

- **[User Guide](doc/userguide.md)** - How to use the application
- **[Schema Notes](doc/schema-notes.md)** - JSON manifest format and validation

## Downloads

Download the latest release for your platform from the [Releases page](https://github.com/Laerdal-Medical/simserver-imager/releases):

- **Linux**: AppImage (x86_64, aarch64) or Debian package
- **Windows**: ZIP archive or installer
- **macOS**: DMG (x86_64, arm64)

## Building from Source

### Linux

#### Prerequisites

Install the build dependencies (Debian/Ubuntu):

```sh
sudo apt install --no-install-recommends build-essential cmake ninja-build git libgnutls28-dev
```

#### Get the source

```sh
git clone https://github.com/laerdal/simserver-imager
cd simserver-imager
```

#### Build with Qt from aqtinstall (recommended)

Install Qt using [aqtinstall](https://github.com/miurahr/aqtinstall):

```sh
pip install aqtinstall
aqt install-qt linux desktop 6.8.2 -O ~/Qt
```

Build the application:

```sh
cmake -B build -S src \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DQt6_ROOT=~/Qt/6.8.2/gcc_64

cmake --build build --parallel
```

#### Build the AppImage

```sh
./create-appimage.sh --qt-root=~/Qt/6.8.2/gcc_64
```

### Windows

#### Prerequisites

- Install [Qt 6.8](https://www.qt.io/download-open-source) with MSVC 2022 64-bit toolchain
- Install [Visual Studio 2022](https://visualstudio.microsoft.com/) with C++ workload
- For the installer, install [Inno Setup](https://jrsoftware.org/isdl.php)

#### Building

Using CMake:

```powershell
cmake -B build -S src `
    -DCMAKE_BUILD_TYPE=Release `
    -DQt6_ROOT="C:\Qt\6.8.2\msvc2022_64"

cmake --build build --config Release --parallel
```

Deploy Qt dependencies:

```powershell
New-Item -ItemType Directory -Force -Path dist
Copy-Item build\Release\laerdal-simserver-imager.exe dist\
& "C:\Qt\6.8.2\msvc2022_64\bin\windeployqt.exe" --qmldir src --release dist\laerdal-simserver-imager.exe
```

### macOS

#### Prerequisites

- Install [Qt 6.8](https://www.qt.io/download-open-source) or build from source using `./qt/build-qt-macos.sh`
- Xcode Command Line Tools

#### Building

```sh
cmake -B build -S src \
    -DCMAKE_BUILD_TYPE=Release \
    -DQt6_ROOT=/opt/Qt/6.8.2/macos

cmake --build build --parallel
```

Create DMG:

```sh
cd build
macdeployqt laerdal-simserver-imager.app -qmldir=../src
hdiutil create -volname "Laerdal SimServer Imager" \
    -srcfolder laerdal-simserver-imager.app \
    -ov -format UDZO \
    laerdal-simserver-imager.dmg
```

### CLI-only Build

For headless/server environments, build without GUI:

```sh
cmake -B build -S src \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_CLI_ONLY=ON \
    -DQt6_ROOT=~/Qt/6.8.2/gcc_64

cmake --build build --parallel
```

## Tooling

### CDN Upload Script

The `scripts/upload-wic-to-cdn.sh` script uploads images to Azure Blob Storage and generates the JSON manifest used by the application.

**Features:**

- Upload WIC, VSI, and SPU files to Azure CDN
- Generate RPI Imager-compatible JSON manifest
- Support for local folders, SSH remote sources, and JSON URLs
- Pattern matching for files and directories
- Append mode to merge with existing CDN manifest
- Skip existing blobs to avoid re-uploading

**Prerequisites:**

- Azure CLI (`az`) with storage extension
- `jq` for JSON processing
- SSH access for remote sources

**Basic usage:**

```sh
# Upload from local folder
./scripts/upload-wic-to-cdn.sh /path/to/images

# Upload from remote build server
./scripts/upload-wic-to-cdn.sh user@buildserver:/opt/yocto/deploy/images

# Upload only SPU files, append to existing manifest
./scripts/upload-wic-to-cdn.sh --spu-only --append /path/to/updates

# Dry run to preview changes
./scripts/upload-wic-to-cdn.sh --dry-run /path/to/images
```

**Environment variables:**

```sh
export AZURE_STORAGE_ACCOUNT="your-account"
export AZURE_STORAGE_KEY="your-key"
export AZURE_STORAGE_CONTAINER="software"
export CDN_BASE_URL="https://your-cdn.blob.core.windows.net"
```

See `./scripts/upload-wic-to-cdn.sh --help` for all options.

## Icon Regeneration

The app icon is stored as SVG at `src/linux/icon/laerdal-simserver-imager.svg`.

To regenerate platform-specific icons:

- **Windows** (.ico): `./src/windows/regenerate_icons_from_svg.sh` (requires ImageMagick)
- **macOS** (.icns): `./src/mac/regenerate_icons_from_svg.sh` (requires ImageMagick, must run on macOS)

## License

SPDX-License-Identifier: Apache-2.0

Copyright (C) 2025 Laerdal Medical

Based on Raspberry Pi Imager, Copyright (C) 2020-2024 Raspberry Pi Ltd
