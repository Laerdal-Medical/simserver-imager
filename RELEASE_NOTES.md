# Release Notes

## What's New in {{VERSION}}

### Features

- **Download Resume**: Support for resuming interrupted downloads on startup with user confirmation dialog
- **Branch Filter Persistence**: Save and restore last selected branch filter across app restarts
- **Branch Filter Search**: Branch filter dropdown now supports type-ahead search for quickly finding branches in large repositories. Combobox now selects matching branch while typing and is fully editable
- **CLI SPU Support**: Full command-line support for SPU file copy operations with proper mount handling
- **SelectionListDelegate**: New reusable QML delegate component providing consistent styling for list items with icon, title, description, badges, and metadata across all wizard selection screens
- **Deferred Artifact Download**: CI artifacts are now downloaded only when user double-clicks or presses Next, reducing unnecessary downloads when browsing the artifact list
- **Install Authorization Button**: Added button to permission warning dialog for easier authorization flow
- **File Extension Registration**: WIC, VSI, and SPU files are now registered with the OS on all platforms (Windows, macOS, Linux). Double-click image files to open them directly in the imager

### Improvements

- **Write Progress Display**: Real-time speed (MB/s) and estimated time remaining shown during write operations. Completion screen now displays write statistics including total bytes written, duration, and average speed
- **Download Speed Display**: Real-time download speed (Mbps) and estimated time remaining shown during download and verify operations with proper network/disk I/O units
- **Device Readiness Polling**: Replaced fixed sleep delays with intelligent device readiness polling across all platforms (Linux, Windows, macOS). Operations complete faster when devices are ready and wait longer when devices need more time
- **Drive List Refresh**: Improved drive list refresh and UI updates
- **Touch Scrolling**: Improved touch screen scrolling behavior across all list views and scrollable areas with smoother deceleration and better tap vs scroll gesture detection
- **SPU Copy Flow**: Improved SPU file copy workflow with auto-advance to done step, dedicated completion message, and display of SPU file and drive information during copy
- **Dialog Components**: Refactored dialog components with new BaseDialog header system for consistent styling and reusable dialog patterns
- **GitHub Artifact Handling**: Improved artifact handling and branch filtering
- **Linux io_uring Optimization**: Limit async I/O queue depth to 4 when using O_DIRECT to prevent massive latency buildup on USB devices. Reduces end-of-write drain time from ~175 seconds to ~2 seconds
- **Write Progress Logging**: Added periodic progress logging showing MB written, speed in MB/s, and pending writes for better diagnostics
- **Multi-Partition Detection**: Added API to detect drives with multiple partitions for improved SPU copy warnings
- **QML Lint Compliance**: Fixed unqualified property access across wizard components using `pragma ComponentBehavior: Bound`

### Bug Fixes

- **Private Repo Downloads**: Fix 404 errors when downloading release assets from private GitHub repositories by using the API asset endpoint with proper authentication headers
- **SPU Release Discovery**: Include SPU files in GitHub release search filters so firmware updates are discovered alongside WIC and VSI images
- **ImBadge Style Fix**: Fix runtime ReferenceError warnings by using Style singleton directly instead of qualified RpiImager.Style access
- **Windows Upgrade Fix**: Preserve user cache and settings during Windows installer upgrades
- **macOS Build Fix**: Resolve deprecation warnings and use thin LTO for faster builds. Fixed QRegularExpression usage in mount helper
- **Windows FAT32 Fix**: Support formatting drives larger than 32GB as FAT32 using DiskFormatter with format.com to bypass Windows' artificial limit
- **Storage Removed Dialog**: Show storage removed dialog when device is removed during write operations with improved styling
- **SPU Device Removal**: Set write state during SPU copy to prevent spurious device removal dialog
- **Mount Helper Fix**: Check if device is already mounted before trying to get exclusive access, avoiding timeout when device is already in use
- **Large Artifact ID Fix**: Support GitHub artifact IDs larger than 2^31 by using JavaScript's safe integer range (2^53)
