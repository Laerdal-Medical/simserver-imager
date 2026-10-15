# Release Notes

## Unreleased

- Keep Download only visible in the artifact contents view and select the first
  file by default, preserving the previous selection when navigating back

## What's New in {{VERSION}}

### New Features

- Download selected images without selecting or writing a storage device.
  Save CDN images, authenticated GitHub release assets, or the selected file
  from CI artifacts in their original format, with progress, cancellation,
  overwrite confirmation, and an Open containing folder action (#1)
- Open the application cache folder from App Options → Cache

### Improvements

- Branch filter dropdown uses the available window space below its selector
  to show more branches at once
- Expand behavioral regression coverage for build selection, download-only
  saving, pipeline helpers, and QML transfer calculations; separate automated
  application tests from hardware diagnostics and bundled-library tests
- Configure all five standard Laerdal GitHub build repositories by default,
  including existing installations, while preserving saved repository settings (#4)
- Image list ordering improved: GitHub releases are shown first, then CI
  builds on all branches sorted by date (newest first), then CDN images by
  version. Stable versions sort ahead of prereleases, and equal versions and
  dates use deterministic ordering (#3)
- CI builds load incrementally from paginated, branch-filtered successful
  workflow runs, allowing selection while older builds continue loading
- Loading banners use a smaller spinner with more space before the message

### Bug Fixes

- Correct reversed mouse-wheel scrolling in dropdown lists
- Preserve partial cache files for download resume and reject undersized format
  targets before writing filesystem metadata
- CI build page updates no longer reset the list or interrupt clicks
- Initial loading overlay disappears as soon as matching builds arrive

**Full changelog:** https://github.com/Laerdal-Medical/simserver-imager/compare/v1.0.11...v1.0.12
