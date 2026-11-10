# Release Notes

## What's New in {{VERSION}}

### Improvements

- Apply clang-format 19 to Laerdal-created C++ headers and sources, preserving
  upstream formatting in inherited and mixed files
- Document formatting ownership rules and limit local parallel tasks to 75% of
  available logical CPUs
- Use Ninja with CPU-limited parallelism for macOS CI builds and avoid
  deploying Qt twice before packaging
- Consistently use braces for conditional bodies throughout first-party code
- Expand contributor architecture guidance and document the release process
- Add a repository clang-format configuration and document formatting changed
  C++ lines with clang-format 19

### Bug Fixes

- Show shared SimPad sysinfo SPU assets for both i.MX6 and i.MX8 devices
- Fix Next on device selection jumping straight to storage when the OS list
  was still loading at startup
- Show a loading banner while the Laerdal image list is fetched, and only warn
  about an unreachable image server when the fetch fails and the CDN source is
  selected
- Show GitHub images immediately even while the Laerdal image list is still
  loading or unavailable

**Full changelog:** https://github.com/Laerdal-Medical/simserver-imager/compare/v1.0.12.c...v1.0.12.d
