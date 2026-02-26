# Release Notes

## What's New in {{VERSION}}

### New Features

- **GitHub Releases as Top-Level Source**: GitHub Releases is now a dedicated source type alongside CDN and GitHub CI, making it easier to find and flash release images

### Improvements

- **Branch Filter ComboBox Usability**: The branch filter dropdown in CI source selection is now much easier to use — typing no longer jumps the cursor, Enter selects the highlighted branch and advances to the next step, and focusing the field selects all text for quick re-editing
- **Device Detection**: Centralized device name detection with improved CANCPU and LinkBox filtering for more accurate hardware matching

### Bug Fixes

- **Stale OS List Items**: Fixed Release items persisting in the CI Artifact view (and vice versa) when switching source types or branches — the model now properly clears when there are no matching results
