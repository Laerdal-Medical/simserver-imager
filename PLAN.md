# Plan: Improve Release Workflow

## Goal
Make release workflow build on every push to main and use a tracked `RELEASE_NOTES.md` file instead of tag messages.

## Changes

### 1. Create `RELEASE_NOTES.md`
- Location: repo root
- Contains release notes for the upcoming version
- Edited like any other file in the repo
- Cleared/updated after each release

### 2. Update `.github/workflows/build.yml`

#### Triggers
```yaml
on:
  push:
    branches: [main]
    tags:
      - 'v*'
  pull_request:
    branches: [main]
  workflow_dispatch:
```

#### Release job changes
- Run on both main branch pushes AND tag pushes
- On main: create/update draft release using `RELEASE_NOTES.md`
- On tag: finalize release (remove draft flag)
- Use `softprops/action-gh-release` with `body_path: RELEASE_NOTES.md`

#### Version handling for draft releases
- Draft release tag: use version from `src/config.h` or a fixed name like `draft`
- When tag is pushed: that becomes the final release

### 3. Release process

**Before (current):**
1. Edit debian/changelog
2. Create annotated tag with release notes as message
3. Push tag
4. CI builds and creates draft release
5. Manually publish

**After (proposed):**
1. Edit `RELEASE_NOTES.md` as you develop
2. Edit `debian/changelog`
3. Push to main → CI builds and updates draft release automatically
4. When ready: push tag (e.g., `git tag v1.0.6 && git push origin v1.0.6`)
5. CI finalizes release (removes draft flag)

## Files to modify
1. `.github/workflows/build.yml` - workflow triggers and release job
2. `RELEASE_NOTES.md` - new file with current v1.0.5 notes

## Questions
- Should draft release have a fixed name (e.g., "Next Release") or use version from config.h?
- Keep artifacts from every main push or only latest?
