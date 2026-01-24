# Claude Code Configuration

## Project Overview

Laerdal SimServer Imager - A Qt/QML-based disk imaging tool forked from Raspberry Pi Imager. Used for writing factory images to storage devices with customization options.

**Key Technologies:** Qt 6, QML, C++20, CMake 3.22+

## Project Structure

- `src/` - Main source code (C++ and QML)
- `src/wizard/` - QML wizard step components
- `src/wizard/dialogs/` - QML dialog components used by the wizard
- `src/qmlcomponents/` - Reusable QML UI components
- `src/github/` - GitHub API integration (OAuth, releases, artifacts)
- `src/repository/` - Repository management (Laerdal CDN, GitHub sources)
- `src/dependencies/` - Bundled libraries (curl, libarchive, zstd, zlib, nghttp2, etc.)
- `src/linux/`, `src/windows/`, `src/mac/` - Platform-specific implementations
- `src/test/` - Catch2 unit tests
- `debian/` - Debian packaging
- `.github/workflows/` - CI/CD configuration
- `doc/` - Documentation (user guide, performance analysis, schema notes)

## Key Source Files

### Core Application

- `src/main.cpp` - Entry point (CLI and GUI modes)
- `src/imagewriter.h/cpp` - Main orchestrator: download/write/verify operations, OS list, drive selection, GitHub auth, SPU copy. Exposes Q_INVOKABLE methods to QML
- `src/cli.h/cpp` - CLI mode implementation with progress reporting
- `src/config.h` - Compile-time configuration (default URLs, OAuth client ID, repos)

### Download & Extraction Pipeline

- `src/downloadthread.h/cpp` - Multi-threaded download using libcurl with resume, proxy, and bottleneck detection
- `src/downloadextractthread.h/cpp` - Downloads and simultaneously decompresses (.xz, .gz, .bz2, .zst) using ring buffers
- `src/localfileextractthread.h/cpp` - Extraction from local files instead of network downloads
- `src/archiveentryextractthread.h/cpp` - Extracts individual entries from archive files
- `src/archiveentryiodevice.h/cpp` - QIODevice wrapper for reading archive entries
- `src/vsiextractthread.h/cpp` - Specialized extractor for Laerdal VSI (Versioned Sparse Image) format
- `src/ringbuffer.h/cpp` - Lock-free ring buffer for producer/consumer pipeline
- `src/systemmemorymanager.h/cpp` - Memory-aware buffer sizing for write pipeline

### Drive & Device Management

- `src/drivelistmodel.h/cpp` - QAbstractListModel for available storage drives
- `src/drivelistitem.h/cpp` - Data structure for a single drive (path, size, USB/SCSI, mount points)
- `src/drivelistmodelpollthread.h/cpp` - Background thread polling for drive changes
- `src/driveformatthread.h/cpp` - Thread for writing images to storage devices
- `src/hwlistmodel.h/cpp` - Hardware/target device list model (SimPad, etc.)
- `src/disk_formatter.h/cpp` - Low-level disk formatting utilities
- `src/disk_format_helper.h` - Platform-specific formatting helpers
- `src/mount_helper.h` - Platform-specific mount/unmount utilities
- `src/devicewrapper.h/cpp` - Unified interface for raw device read/write
- `src/devicewrapperpartition.h/cpp` - Partition handling within device wrapper
- `src/devicewrapperfatpartition.h/cpp` - FAT32 partition handling for SPU copy mode

### OS & Image Management

- `src/oslistmodel.h/cpp` - QAbstractListModel for OS/image list with CDN and GitHub source support
- `src/imageadvancedoptions.h/cpp` - Enum flags for advanced image options
- `src/customization_generator.h/cpp` - Generates firstrun.sh and cloud-init YAML

### Cache & Network

- `src/cachemanager.h/cpp` - Disk cache with background verification
- `src/asynccachewriter.h/cpp` - Asynchronous cache writing
- `src/curlfetcher.h/cpp` - Wrapper around libcurl for HTTP/HTTPS operations
- `src/curlnetworkconfig.h/cpp` - Network configuration (proxy, auth, headers)
- `src/networkaccessmanagerfactory.h/cpp` - Qt network access manager factory for QML

### SPU Support

- `src/spucopythread.h/cpp` - Thread for copying SPU files to FAT32-formatted drives

### Performance & Telemetry

- `src/performancestats.h/cpp` - Performance data collection and JSON export
- `src/downloadstatstelemetry.h/cpp` - Download statistics telemetry

### Utilities

- `src/acceleratedcryptographichash.h` - Hardware-accelerated SHA256/MD5
- `src/iconimageprovider.h/cpp` - QML image provider for OS icons
- `src/iconmultifetcher.h/cpp` - Batch icon fetching
- `src/nativefiledialog.h/cpp` - Native file selection dialogs
- `src/platformhelper.h/cpp` - Platform detection utilities
- `src/platformquirks.h` - Platform-specific workarounds
- `src/suspend_inhibitor.h/cpp` - Prevents system sleep during writes
- `src/clipboardhelper.h/cpp` - Clipboard access
- `src/secureboot.h/cpp` - Secure Boot configuration
- `src/wlancredentials.h/cpp` - WiFi credential handling
- `src/urlfmt.h/cpp` - URL formatting and parsing
- `src/file_operations.h/cpp` - Cross-platform file operations
- `src/device_info.h/cpp` - Hardware device information detection
- `src/aligned_buffer.h` - Memory-aligned buffer for efficient I/O
- `src/bootimgcreator.h` - Boot image creation (platform-specific implementations)
- `src/embedded_config.h` - Embedded mode configuration

### GitHub Integration (`src/github/`)

- `githubauth.h/cpp` - OAuth Device Flow authentication (states: Idle, WaitingForUserCode, Polling, Authenticated, Error)
- `githubclient.h/cpp` - API client: releases, branch files, artifact inspection/download, release asset download with auth

### Repository Management (`src/repository/`)

- `repositorymanager.h/cpp` - Multi-source manager with environment support (Production, Test, Dev, Beta, RC). Handles artifact inspection, branch filtering, OS list aggregation
- `githubsource.h/cpp` - GitHub repository source (releases and branch files)
- `laerdalcdnsource.h/cpp` - Laerdal CDN source for factory images

## QML Architecture

### Singletons (in `src/`)

- `Style.qml` - Design tokens: colors (`laerdalBlue` #2e7fa1, success/error/warning), font sizes (`fontSizeTitle`, `fontSizeHeading`, `fontSizeDescription`), spacing (`spacingSmall`/`Medium`/`Large`), component-specific properties (button colors, progress bar colors, scrollbar width)
- `Utils.qml` - Utility functions: `formatBytes()`, `formatDuration()`, `formatTimeRemaining()`, `calculateThroughputMbps()`, `calculateThroughputKBps()`, `calculateAverageSpeed()`, `calculateTimeRemainingKBps()`
- `CommonStrings.qml` - Shared translatable strings and file filter definitions
- `main.qml` - Root ApplicationWindow, dialog instances, signal forwarding from C++

### Wizard Flow

The wizard uses a step-based navigation system in `src/wizard/WizardContainer.qml`:

```text
Device → Source → OS Selection → [CI Artifact Selection] → Storage → Writing → Done
                                                                   ↘ SPU Copy → Done
```

- **CI Artifact Selection** (step 3) is conditionally shown only for GitHub CI artifacts needing ZIP inspection
- Direct CDN files (.wic, .spu, .vsi) skip from OS Selection directly to Storage
- SPU files route to a separate SPU Copy step (index 10) instead of Writing
- Step indices: Device=0, Source=1, OS=2, CIArtifact=3, Storage=4, Writing=5, Done=6
- WizardContainer tracks: `isWriting`, `isDownloading`, `currentStep`, `permissibleStepsBitmap`

### Wizard Steps (`src/wizard/`)

- `WizardStepBase.qml` - Base component: next/back/skip buttons, title, subtitle, sidebar info
- `WizardContainer.qml` - Step orchestrator with StackView navigation and state management
- `DeviceSelectionStep.qml` - Target device (SimPad, etc.) selection
- `SourceSelectionStep.qml` - Source type selection (CDN, GitHub, local file)
- `OSSelectionStep.qml` - OS/image selection from repository list
- `CIArtifactSelectionStep.qml` - CI artifact download + file selection from ZIP
- `StorageSelectionStep.qml` - Storage device (USB/SD) selection
- `WritingStep.qml` - Write operation with progress, speed, ETA display
- `DoneStep.qml` - Completion screen with write statistics and "Write Another" option
- `SPUCopyStep.qml` - SPU file copy to FAT32 device
- `LanguageSelectionStep.qml` - Language selection (optional first step)
- Customization steps (currently disabled for Laerdal): `HostnameCustomizationStep`, `UserCustomizationStep`, `WifiCustomizationStep`, `SshCustomizationStep`, `LocaleCustomizationStep`, `IfAndFeaturesCustomizationStep`, `SecureBootCustomizationStep`, `PiConnectCustomizationStep`, `RemoteAccessStep`

### Wizard Dialogs (`src/wizard/dialogs/`)

- `AppOptionsDialog.qml` - Application settings (cache management, repository selection)
- `DebugOptionsDialog.qml` - Debug options (secret: Ctrl+Alt+S)
- `GitHubLoginDialog.qml` - GitHub OAuth device flow login
- `RepositorySelectionDialog.qml` - Repository/CDN environment selection
- `RepositoryDialog.qml` - Repository configuration
- `ConfirmSystemDriveDialog.qml` - System drive write confirmation
- `ConfirmUnfilterDialog.qml` - Unfiltered OS list confirmation
- `UpdateAvailableDialog.qml` - Version update notification
- `KeychainPermissionDialog.qml` - Keychain access permission

### Reusable Components (`src/qmlcomponents/`)

**Buttons:**

- `ImButton.qml` - Standard button (white bg, blue text, Laerdal disabled states)
- `ImButtonRed.qml` - Red destructive action button
- `ImCloseButton.qml` - Close/X button
- `ImOptionButton.qml` - Option/choice button
- `ImOptionPill.qml` - Pill-shaped option selector
- `ImToggleTab.qml` - Tab toggle between options

**Form Inputs:**

- `ImTextField.qml` - Text input with context menu
- `ImPasswordField.qml` - Password input with masking
- `ImCheckBox.qml` - Checkbox control
- `ImRadioButton.qml` - Radio button control
- `ImComboBox.qml` - Dropdown selector with editable search

**Display:**

- `ImBadge.qml` - Badge with color variants (indigo/SPU, emerald/WIC, cyan/VSI, purple/CI, green/release)
- `ImBanner.qml` - Info banner
- `ImLoadingBanner.qml` - Loading state banner
- `MarqueeText.qml` - Scrolling text for overflow
- `ImProgressBar.qml` - Progress bar with rounded borders, glassy effect, smooth animation, indeterminate mode

**Lists:**

- `SelectionListView.qml` - Keyboard-navigable selection list
- `SelectionListDelegate.qml` - List item delegate (icon, title, description, badges, metadata)
- `OSSelectionListView.qml` - Specialized OS selection list with filtering

**Dialogs:**

- `BaseDialog.qml` - Base modal dialog with header system
- `MessageDialog.qml` - Generic message dialog
- `ConfirmDialog.qml` - Confirmation with cancel/confirm buttons
- `ErrorDialog.qml` - Error message dialog
- `WarningDialog.qml` - Warning message dialog
- `ActionMessageDialog.qml` - Dialog with primary + secondary action buttons
- `ImPopup.qml` - Popup overlay

**File Dialogs:**

- `ImFileDialog.qml` - File open dialog (QML fallback for native)
- `ImSaveFileDialog.qml` - File save dialog (QML fallback for native)

**Scrolling:**

- `ImScrollBar.qml` - Styled scrollbar (pill shape, Laerdal blue, hover/press transitions)

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

Test files:

- `src/test/customization_generator_test.cpp` - firstrun.sh generation tests
- `src/fat_partition_test.cpp` - FAT partition handling tests
- `src/disk_formatter_test.cpp` - Disk formatting tests

## Platform Support

- **Linux**: x86_64 and aarch64, GnuTLS, D-Bus, AppImage/Debian packaging
- **Windows**: MinGW and MSVC, Inno Setup installer
- **macOS**: Universal binary (x86_64 + arm64), DMG packaging

Platform-specific code lives in `src/linux/`, `src/windows/`, `src/mac/` with corresponding `Platform.cmake` files.

## RPI Imager JSON Schema

This project uses the Raspberry Pi Imager JSON format for OS image lists. The official schema is at:
`github.com/raspberrypi/rpi-imager/blob/qml/doc/json-schema/os-list-schema.json`

### Required Fields (per OS entry)

| Field | Type | Description |
| ----- | ---- | ----------- |
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
| ----- | ---- | ----------- |
| `init_format` | string | Initialization format type |
| `website` | string | Project website URL |
| `architecture` | string | Target architecture (e.g., "armhf", "aarch64") |
| `matching_type` | string | Device matching behavior ("exclusive" or "inclusive") |
| `subitems_url` | string | URL to fetch nested OS list |
| `subitems` | array | Inline nested OS entries |

### Version Handling

**Important**: There is NO separate `version` field in the RPI Imager schema. Version information must be embedded in the `name` field.

The application extracts version from `name` using this regex pattern:

```regex
v?(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?
```

Examples of valid name formats:

- `"SimPad PLUS v1.2.3"`
- `"Factory Image 2.0.1"`
- `"My Image v1.0.0.4"` (4-part version)

## Image Types

The application supports three image types, determined by URL file extension:

| Type | Extension | Description | Badge Color |
| ---- | --------- | ----------- | ----------- |
| **WIC** | `.wic`, `.wic.xz`, `.wic.gz`, `.wic.bz2`, `.wic.zst` | Standard disk image (full flash) | Emerald `#10b981` |
| **VSI** | `.vsi` | Versioned Sparse Image (delta updates) | Cyan `#06b6d4` |
| **SPU** | `.spu` | Software Package Update (firmware files copied to device) | Indigo `#6366f1` |

Image type is NOT stored in JSON metadata - it's determined at runtime from the URL extension to maintain RPI Imager JSON compatibility.

## Coding Conventions

- Qt signal/slot architecture with `Q_OBJECT` macro
- Platform-specific code uses `#ifdef Q_OS_LINUX`, `Q_OS_WIN`, `Q_OS_MACOS`
- QML classes exposed via `QML_ELEMENT` macro
- Primary namespace: `rpi_imager` (inherited from Raspberry Pi Imager)
- QML components use `pragma ComponentBehavior: Bound` for strict property access
- Required properties declared with `required property` syntax
- All wizard steps inherit from `WizardStepBase`

## Pre-Commit Checklist

Before committing, update `RELEASE_NOTES.md` and `debian/changelog` with entries describing the changes being committed.

## Post-Change Workflow

After completing code changes, always build the project to verify there are no compilation errors:

```bash
cmake --build build --parallel
```

This ensures QML syntax errors and C++ compilation issues are caught before committing.

### QML Linting

Use `qmllint` to check QML files for issues before committing. **Always fix all qmllint warnings** - do not leave any unresolved.

```bash
# Lint a specific file
/opt/Qt/6.10.1/gcc_64/bin/qmllint src/path/to/File.qml

# Lint all QML files in a directory
find src -name "*.qml" -exec /opt/Qt/6.10.1/gcc_64/bin/qmllint {} \;
```

Common issues qmllint catches:

- Unqualified access to IDs from outer components (fix with `pragma ComponentBehavior: Bound` and qualified references)
- Missing required properties in delegates
- Type mismatches and undefined properties
- `var` properties used as functions (use proper function declarations instead)

**Note:** qmllint may report false positives for C++ types from the RpiImager module (e.g., `ImageWriter`, `DriveListModel`) since the module is not available to the static analyzer. These warnings about "Member not found on type" for C++ QML types can be ignored.
