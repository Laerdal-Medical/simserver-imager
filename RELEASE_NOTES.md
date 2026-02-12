# Release Notes

## What's New in 1.0.7

### Features

- **GitHub Release Grouping**: GitHub release assets are now grouped by release tag instead of showing each file as a separate entry. Selecting a release opens the file selection step where users can pick from available assets (factory images, system updates, etc.) filtered by the selected device platform
- **Release Filter Option**: Added "Releases" filter option in the GitHub source dropdown to show only releases without CI artifacts. The previous "All branches" option renamed to "Default branch" for clarity
- **Loading Indicator**: Added a loading spinner overlay when fetching GitHub images to prevent showing stale data while the list updates

### Improvements

- **SPU Copy Speed Display**: The SPU copy step now shows transfer speed (MB/s), bytes transferred, and estimated time remaining during copy operations, matching the write step UI
- **SPU Copy Status Messages**: Show accurate "Flushing to USB drive..." status when data is being synced after copy completes, instead of showing the stale preparation message
- **Device Selection Workflow**: "Erase" and "Use custom" options moved from OS selection to device/hardware selection step for a more intuitive workflow. "Use custom" now supports SPU files in addition to WIC/VSI images, allowing local firmware updates to be selected directly from device selection

### Bug Fixes

- **Fix ADD Button**: Fixed the ADD button in the GitHub repository dialog remaining disabled after adding a repository
- **Local File Bottleneck Detection**: Fix bottleneck status incorrectly showing "network" when extracting from local files. Local file extraction now correctly identifies "disk read" as the upstream bottleneck when throughput is limited
