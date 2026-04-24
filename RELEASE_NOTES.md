# Release Notes

## What's New in {{VERSION}}

### New Features

- **GitHub Releases as Top-Level Source**: GitHub Releases is now a dedicated source type alongside CDN and GitHub CI, making it easier to find and flash release images

### Improvements

- **Branch Filter ComboBox Usability**: The branch filter dropdown in CI source selection is now much easier to use — typing no longer jumps the cursor, Enter selects the highlighted branch and advances to the next step, and focusing the field selects all text for quick re-editing
- **Device Detection**: Centralized device name detection with improved CANCPU and LinkBox filtering for more accurate hardware matching

### Bug Fixes

- **Stale OS List Items**: Fixed Release items persisting in the CI Artifact view (and vice versa) when switching source types or branches — the model now properly clears when there are no matching results
- **FAT32 Backup Boot Sector (Windows)**: Fixed backup boot sector being written at the wrong sector offset (16 instead of 6) and containing an incorrect `hidden_sectors` BPB field — firmware that validates the backup sector no longer rejects the volume
- **FAT32 Volume Label (Windows)**: Drive is now correctly labeled "LAERDAL" instead of hardcoded "BOOT" when formatting on Windows
- **Storage Selection with Multiple Drives**: Fixed a bug where clicking any drive in the storage selection list always wrote to the first drive in the list — the correct clicked drive is now used regardless of how many drives are present
