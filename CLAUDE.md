# Claude Code Configuration

## Project Overview

Laerdal SimServer Imager - A Qt/QML-based disk imaging tool forked from Raspberry Pi Imager. Used for writing factory images to storage devices with customization options.

**Key Technologies:** Qt 6, QML, C++20, CMake 3.22+

## Project Structure

- `src/` - Main source code (C++ and QML)
- `src/wizard/` - QML wizard UI components
- `src/qmlcomponents/` - Reusable QML components
- `src/dependencies/` - Bundled libraries (curl, libarchive, zstd, zlib, nghttp2, etc.)
- `src/linux/`, `src/windows/`, `src/mac/` - Platform-specific implementations
- `src/test/` - Catch2 unit tests
- `src/github/` - GitHub API integration
- `src/repository/` - Repository management (Laerdal CDN, GitHub sources)
- `debian/` - Debian packaging
- `.github/workflows/` - CI/CD configuration

## Key Source Files

- `src/main.cpp` - Entry point (CLI and GUI modes)
- `src/imagewriter.h/cpp` - Main orchestrator for download/write operations
- `src/drivelistmodel.h/cpp` - Drive enumeration model
- `src/downloadthread.h/cpp` - Async download handling
- `src/driveformatthread.h/cpp` - Writing images to devices
- `src/cachemanager.h/cpp` - Disk cache with verification
- `src/config.h` - Compile-time configuration (repos, OAuth, URLs)

## Build Instructions

### CMake Configuration

The CMakeLists.txt is located in the `src/` directory. When configuring, use `-S src` to specify the source directory.

When running CMake, always use the following settings:

- **Qt 6 Location**: Qt is installed at `/opt/Qt/`. Look for available versions in `/opt/Qt/6.*/gcc_64` and use the latest one. Currently using `/opt/Qt/6.10.1/gcc_64`.
- **Parallel Builds**: Always use `--parallel` flag with cmake build commands

Example commands:

```bash
# Find available Qt versions
ls -d /opt/Qt/6.*/gcc_64

# Configure (use the latest available Qt version)
cmake -B build -S src -DCMAKE_PREFIX_PATH=/opt/Qt/6.10.1/gcc_64

# Build (always use --parallel)
cmake --build build --parallel
```

### Build Options

```bash
-DBUILD_CLI_ONLY=ON        # CLI-only without GUI components
-DBUILD_EMBEDDED=ON        # Embedded imager mode
-DENABLE_TELEMETRY=ON      # Enable telemetry (default: ON)
-DENABLE_CHECK_VERSION=ON  # Version checking (default: ON)
```

## Running Tests

Tests use Catch2 framework with CTest integration.

```bash
# Build and run all tests
cmake --build build --parallel
ctest --test-dir build

# Run specific test executable
./build/test/test_customization_generator
```

Test files are in `src/test/`:

- `customization_generator_test.cpp` - firstrun.sh generation
- `fat_partition_test.cpp` - FAT partition handling
- `disk_formatter_test.cpp` - Disk formatting

## Platform Support

- **Linux**: x86_64 and aarch64, GnuTLS, D-Bus, AppImage/Debian packaging
- **Windows**: MinGW and MSVC, Inno Setup installer
- **macOS**: Universal binary (x86_64 + arm64), DMG packaging

## RPI Imager JSON Schema

This project uses the Raspberry Pi Imager JSON format for OS image lists. The official schema is at:
`github.com/raspberrypi/rpi-imager/blob/qml/doc/json-schema/os-list-schema.json`

### Required Fields (per OS entry)

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Display name (version should be embedded here, e.g., "Image Name v1.2.3") |
| `description` | string | Brief description of the image |
| `icon` | string | URL or resource path to icon |
| `url` | string | Download URL for the image |
| `extract_size` | integer | Uncompressed image size in bytes |
| `extract_sha256` | string | SHA256 hash of uncompressed image |
| `image_download_size` | integer | Compressed download size in bytes |
| `release_date` | string | ISO 8601 date (YYYY-MM-DD) |
| `devices` | array | List of compatible device tags |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `init_format` | string | Initialization format type |
| `website` | string | Project website URL |
| `architecture` | string | Target architecture (e.g., "armhf", "aarch64") |
| `matching_type` | string | Device matching behavior ("exclusive" or "inclusive") |
| `subitems_url` | string | URL to fetch nested OS list |
| `subitems` | array | Inline nested OS entries |

### Version Handling

**Important**: There is NO separate `version` field in the RPI Imager schema. Version information must be embedded in the `name` field.

The application extracts version from `name` using this regex pattern:
```
v?(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?
```

Examples of valid name formats:
- `"SimPad PLUS v1.2.3"`
- `"Factory Image 2.0.1"`
- `"My Image v1.0.0.4"` (4-part version)

## Coding Conventions

- Qt signal/slot architecture with `Q_OBJECT` macro
- Platform-specific code uses `#ifdef Q_OS_LINUX`, `Q_OS_WIN`, `Q_OS_MACOS`
- QML classes exposed via `QML_ELEMENT` macro
- Primary namespace: `rpi_imager` (inherited from Raspberry Pi Imager)
