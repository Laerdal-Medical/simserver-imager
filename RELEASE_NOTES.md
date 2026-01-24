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
- **CI Artifact Selection Step**: Unified wizard step for downloading CI artifacts and selecting files from ZIP archives, replacing modal dialogs with integrated wizard flow. All GitHub CI artifacts are routed through the artifact selection step for inspection. Direct CDN artifact files (.wic, .spu, .vsi) skip this step and advance directly to storage selection. Progress bars now use Laerdal brand blue color with custom styling and smooth indeterminate animations
- **Progress Bar Styling**: All progress bars (download, write, verify) now use consistent Laerdal brand colors - blue for writing/downloading operations and green for verification, with custom styling replacing Material Design defaults. Created reusable ImProgressBar component with rounded borders (8px radius), glassy effect (2px semi-transparent border), and indeterminate animation support
- **ScrollBar Styling**: All scrollbars now use consistent Laerdal brand styling with rounded corners (fully rounded pill shape), Laerdal blue color, and smooth hover/press state transitions. Created reusable ImScrollBar component that replaces default Qt ScrollBar styling across all list views and scrollable areas
- **Device Readiness Polling**: Replaced fixed sleep delays with intelligent device readiness polling across all platforms (Linux, Windows, macOS). Operations complete faster when devices are ready and wait longer when devices need more time
- **Drive List Refresh**: Improved drive list refresh and UI updates
- **Touch Scrolling**: Improved touch screen scrolling behavior across all list views and scrollable areas with smoother deceleration and better tap vs scroll gesture detection
- **SPU Copy Flow**: Improved SPU file copy workflow with auto-advance to done step, dedicated completion message, and display of SPU file and drive information during copy
- **Dialog Components**: Refactored dialog components with new BaseDialog header system for consistent styling and reusable dialog patterns
- **GitHub Artifact Handling**: Improved artifact handling and branch filtering
- **Write Pipeline Memory Reduction**: Reduced write buffer size from 8MB to 1MB and right-sized ring buffers to match the actual io_uring queue depth. Previously, ring buffer over-allocation (4GB+) caused memory pressure that blocked the UI thread via page faults. Now uses ~40MB total, eliminating UI stuttering during writes
- **Smooth Progress Bar**: Added width animation to progress bar fill, creating smooth visual transitions between completion events instead of discrete jumps
- **Linux io_uring Optimization**: Limit async I/O queue depth to 4 when using O_DIRECT to prevent massive latency buildup on USB devices. Reduces end-of-write drain time from ~175 seconds to ~2 seconds
- **Write Progress Logging**: Added periodic progress logging showing MB written, speed in MB/s, and pending writes for better diagnostics
- **Multi-Partition Detection**: Added API to detect drives with multiple partitions for improved SPU copy warnings
- **QML Lint Compliance**: Fixed unqualified property access across wizard components using `pragma ComponentBehavior: Bound`
- **OS Selection Navigation**: OS list model is no longer unnecessarily reloaded and re-sorted when navigating back to the OS selection step. The C++ model persists across QML component recreation, so data is only loaded once per session, improving performance and eliminating redundant sorting

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
- **Artifact File Type Detection**: Fix SPU and VSI files in CI artifacts being incorrectly identified as WIC, causing them to be written as disk images instead of using their correct write modes
- **Artifact Download Freeze**: Fix CI artifact downloads hanging indefinitely by using proper API timeout on the initial redirect request and enabling cancellation during the redirect phase
- **CI Artifact Step Navigation**: Fix CIArtifactSelectionStep not appearing in sidebar navigation, storage selection being skipped after file selection, OS selection state being lost when navigating to/from artifact selection, back button state preservation across navigation, wrong cached files being shown when selecting a different CI artifact, cached selections not being cleared when changing download source, cache not being restored when navigating back from storage selection, multiple items showing different highlight colors by synchronizing ListView currentIndex with selected file index, Back button skipping OSSelectionStep by removing duplicate signal handler in WizardContainer, improve download cancellation UX by enabling Back button during download instead of changing Next button to Cancel, and fix non-CI artifacts (Erase, Use custom, direct WIC/VSI/SPU files) incorrectly routing to artifact selection step instead of directly to storage selection
- **Write Complete Screen Alignment**: Align "Write statistics:" section with "Your choices:" section by using consistent heading font size (Style.fontSizeHeading), proper spacing, and fixed-width label columns (150px) to ensure data values align vertically across both sections for improved visual consistency on the completion screen
- **OS List Source Switch**: Fix system image list not updating when switching between CDN and GitHub artifact sources. The OS list model now detects source type changes and reloads accordingly
- **Write Another Freeze**: Fix application freeze when writing the same artifact image a second time via "Write Another". The archive streaming variables were cleared after the first write, causing the second write to fall through to DownloadExtractThread which deadlocked trying to resolve the internal `archive://` URL scheme as a network host
