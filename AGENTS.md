# Architecture and contributor guide

SimServer Imager is a Qt 6 / QML / C++20 disk-imaging application forked from
Raspberry Pi Imager. Prefer the existing signal/slot, model, and worker-thread
patterns. This file is a navigation map, not an exhaustive source inventory.

## Find the right entry point

| Task | Start here | Related code |
| --- | --- | --- |
| Startup, CLI options | `src/main.cpp`, `src/cli.cpp` | `src/config.h`, `src/embedded_config.h` |
| Wizard navigation, back/reset behavior | `src/wizard/WizardContainer.qml` | `src/wizard/WizardStepBase.qml`, individual steps |
| Repository/source/branch selection | `src/wizard/SourceSelectionStep.qml` | `src/repository/repositorymanager.cpp` |
| Image list labels, sorting, selection | `src/wizard/OSSelectionStep.qml`, `src/oslistmodel.cpp` | Repository conversion in `src/repository/repositorymanager.cpp` |
| Release assets or files inside a CI ZIP | `src/wizard/CIArtifactSelectionStep.qml` | `RepositoryManager::inspectArtifact()`, `src/github/githubclient.cpp` |
| Device compatibility and filename detection | `src/devicedetection.cpp` | `src/hwlistmodel.cpp`, `src/test/devicedetection_test.cpp` |
| GitHub login/API behavior | `src/github/githubauth.cpp`, `src/github/githubclient.cpp` | `src/wizard/dialogs/GitHubLoginDialog.qml` |
| Write source configuration and orchestration | `src/imagewriter.h`, `src/imagewriter.cpp` | `src/wizard/WritingStep.qml` |
| Download, decompression, verification | `src/downloadthread.cpp`, `src/downloadextractthread.cpp` | `src/localfileextractthread.cpp`, `src/archiveentryextractthread.cpp`, `src/vsiextractthread.cpp` |
| Buffers, cache, throughput | `src/ringbuffer.cpp`, `src/cachemanager.cpp` | `src/asynccachewriter.cpp`, `src/systemmemorymanager.cpp`, `src/performancestats.cpp` |
| Storage discovery and raw I/O | `src/drivelistmodel.cpp`, `src/drivelistmodelpollthread.cpp` | `src/devicewrapper.cpp`, `src/file_operations.cpp`, platform directories |
| Formatting and partitions | `src/disk_formatter.cpp`, `src/devicewrapperfatpartition.cpp` | `src/driveformatthread.cpp`, mount/format helpers |
| SPU copy mode | `src/wizard/SPUCopyStep.qml`, `ImageWriter::startSpuCopy()` | `src/spucopythread.cpp` |
| Download only, without writing media | `src/downloadonly.cpp`, `ImageWriter::startDownloadOnly()` | `src/qmlcomponents/DownloadOnlyDialog.qml` |
| Shared UI behavior and styling | `src/qmlcomponents/`, `src/Style.qml` | `src/Utils.qml`, `src/CommonStrings.qml` |
| OS customization | `src/customization_generator.cpp` | Customization steps in `src/wizard/`; currently disabled in the Laerdal flow |
| Packaging and releases | `.github/workflows/build.yml`, `debian/` | [Release skill](.github/skills/release/SKILL.md) |

## Main data flows

### Repository data to an image selection

`ImageWriter::initializeGitHubAuth()` creates and owns `GitHubAuth`,
`GitHubClient`, and `RepositoryManager`. Authentication changes configure the
client. `RepositoryManager` manages sources, environments, branch filters, and
conversion to OS-list JSON; see also `githubsource.cpp` and
`laerdalcdnsource.cpp` in `src/repository/`.

Repository updates emit `osListReady`, forwarded by `ImageWriter` as
`osListPrepared`. `OSListModel` parses entries, exposes QML roles, and handles
ordering/identity; `OSSelectionStep.qml` displays and selects them. If adding
metadata, wire conversion, model storage, role names/data, `getOsEntry()`, and
QML consumers together. Do not assume a delegate proxy is a complete JSON
object; back-navigation restoration uses `getOsEntry()`.

### Selection to storage and writing

Normal flow: Device -> Source -> OS -> optional CI Artifact / Release file
selection -> Storage -> Writing -> Done. Use the named step constants in
`WizardContainer.qml`; some extra/customization steps exist outside this flow.

`OSSelectionStep.inspectSelectedArtifact()` decides whether to configure a
direct source or defer to file selection. Release assets are already listed;
CI ZIP inspection goes through `RepositoryManager` and `GitHubClient`.
Some single-image CI artifacts bypass inspection through streaming.

The selection calls the appropriate `ImageWriter::setSrc*()` method.
`WritingStep` calls `startWrite()`, and `ImageWriter` selects/configures the
worker pipeline. Local and remote images use different worker paths; preserve
both when changing extraction or verification. Progress/errors return through
Qt signals and the wizard forwarding handlers.

SPU is a separate copy flow, not a raw disk-image write: Storage -> SPU Copy ->
Done. It has dedicated source setters and `SPUCopyThread`. Download only is
another separate operation; preserve its original-file semantics and do not
route it through device writes.

## State and compatibility invariants

- Wizard navigation clears/recreates step instances. State needed across steps
  belongs in `WizardContainer` or the appropriate C++ owner, not only in a
  step's local properties.
- `pendingArtifactInspection` and `pendingReleaseInspection` describe a new
  request; `cachedArtifact*` and `cachedSelectedFileIndex` support returning to
  a previous selection. A new release must take precedence over cached files.
  Releases use artifact ID zero, so that ID cannot identify a release.
- Changing the device must invalidate device-dependent selections and cached
  files so compatibility filtering runs again; see
  `invalidateDeviceDependentSteps()`. Changing OS invalidates downstream steps.
- OS list updates can reorder entries. Preserve selection using stable
  identity, not a row number or a retained delegate/model proxy.
- Leaving an asynchronous step must cancel relevant work or ignore stale
  signals. Inspect existing current-step guards and cancellation paths.
- Use `DeviceDetection` for shared device/file compatibility rather than
  creating competing filename rules in QML.
- Preserve Raspberry Pi OS-list JSON compatibility. Versions belong in `name`,
  not a new schema `version` field. Release tags/assets are GitHub-specific
  metadata; WIC/VSI/SPU handling is determined from filenames/URLs.
- Shared QML components live in `qmlcomponents`; use `Style`, `Utils`, and
  `CommonStrings` rather than duplicating tokens/helpers. Wizard steps inherit
  `WizardStepBase`; retain bound-component/required-property conventions.
- Platform behavior belongs in `src/linux/`, `src/windows/`, `src/mac/` and their
  `Platform.cmake` files or existing platform helpers. Avoid modifying bundled
  dependencies in `src/dependencies/` for application-level fixes.

## Build and focused validation

CMake's source directory is **`src`**, not the repository root. In this local
environment, choose the newest installed `/home/viktor/Qt/6.*/gcc_64` when
configuring; do not copy that machine-specific path into portable code.

```bash
cmake -B build -S src -DCMAKE_PREFIX_PATH=<installed-Qt-gcc_64>
cmake --build build --parallel
./build/test/repository_github_test '[repository][releases]'
ctest --test-dir build -L unit --output-on-failure
```

Always build after code changes. Run the smallest relevant test selection
first; targets and CTest registration are in `src/test/CMakeLists.txt`.

- `repository_github_test`: offline, signal-driven repository/GitHub behavior.
- `model_test`: OS ordering/identity, hardware models, and drive items.
- `devicedetection_test`: filenames and device compatibility.
- `core_io_test`: buffers, archive I/O, cache writing, and memory sizing.
- `downloadonly_test`: download-only behavior.
- `qml_utils_test`: QML helpers and UI regressions; runs offscreen.
- `customization_generator_test`, `disk_formatter_test`: their respective logic.

Never run real-media FAT tests casually: `fat_partition_test` is deliberately
excluded from CTest and requires explicit disposable-device/write opt-ins.
For QML edits, use the installed Qt's `qmllint` with project import paths;
distinguish unavailable C++ module metadata from actual QML warnings.

## Keep guidance current

Update directly affected sections here when changing ownership, navigation,
data flow, extension points, or validation commands. Link deeper documentation
instead of growing this into a duplicate source inventory. User-facing docs
are in `doc/userguide.md`, schema notes in `doc/schema-notes.md`, and performance
material in `doc/performance/`.

Before committing changes, update `RELEASE_NOTES.md` and `debian/changelog`.
For a release, follow the linked release skill, including separate branch/tag
pushes to avoid the workflow's shared concurrency group cancelling publication.
