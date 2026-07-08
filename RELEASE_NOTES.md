# Release Notes

## What's New in {{VERSION}}

### New Features

### Improvements

- Image list ordering improved: GitHub releases are shown first, then
  main-branch CI builds sorted by date (newest first), then feature-branch
  builds and CDN images by version. Main-branch builds are ordered by date
  rather than build number because build numbers from different CI pipelines
  are not comparable
- Cached CI artifact ZIP files now include the image version in their filename
  (e.g. `artifact_2847561039_v9.2.0.127.zip`) for easier identification

### Bug Fixes

