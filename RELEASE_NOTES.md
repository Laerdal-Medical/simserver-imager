# Release Notes

## What's New in {{VERSION}}

### Improvements

- **SPU Copy Speed Display**: The SPU copy step now shows transfer speed (MB/s), bytes transferred, and estimated time remaining during copy operations, matching the write step UI
- **SPU Copy Status Messages**: Show accurate "Flushing to USB drive..." status when data is being synced after copy completes, instead of showing the stale preparation message
- **SPU Copy Progress Percentage**: The SPU copy step now shows copy progress percentage in the status text

### Bug Fixes

- **Device Change Invalidates Artifact Cache**: Changing the target device now correctly clears cached artifact state so that the CI artifact selection step re-filters files for the new device
- **Write Progress Bar Over 100%**: Fixed progress bar exceeding 100% when writing compressed images (e.g., .wic.xz) from release assets by passing unknown extract size and adding a runtime safety fallback to indeterminate mode
- **TypeError on Cached OS Restoration**: Fixed "Could not convert argument 0 from undefined to QUrl" warning when navigating back to OS selection by using the complete model entry directly instead of the delegate proxy
- **Duplicate Signal Handling in CI Artifact Step**: Fixed artifact download signals being processed multiple times by zombie step instances during StackView transitions
