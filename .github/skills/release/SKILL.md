---
name: release
description: Prepare and publish a SimServer Imager release when asked to create a new version, release commit, or release tag.
---

# SimServer Imager release

Use the repository's existing tag-driven release workflow. Do not manually
create a GitHub release or upload packages: `.github/workflows/build.yml`
builds the packages and publishes the release when a `v*` tag is pushed.

## Inspect before changing

- Check `git status --short`, the current branch, and remote configuration.
  Leave unrelated changes and untracked files untouched.
- Inspect the most recent release commit and annotated tag:
  `git log --oneline -10`, `git tag --list 'v*' --sort=-version:refname`,
  and `git show <previous-tag>`.
- Read `RELEASE_NOTES.md`, the top of `debian/changelog`, and the workflow's
  triggers, concurrency configuration, and `release` job.
- Confirm the requested version does not already exist locally or remotely.
  Never replace or force-push an existing release tag.
- Compare changes since the previous release to identify the new release's
  actual contents.

Reference releases: `v1.0.12.b` points to release commit `4e1b800c`;
`v1.0.12.c` points to `48c7a0fa`. Inspect the latest release rather than
assuming these remain the most recent.

## Prepare release metadata

1. Update `RELEASE_NOTES.md` to describe only changes since the previous
   release. Keep `## What's New in {{VERSION}}`: CI substitutes the version.
   Update the full-changelog URL to compare the previous tag with the new tag.
2. Add a top entry in `debian/changelog` using the version without the `v`
   prefix and `stable; urgency=medium`. Include the release's changes and a
   current RFC 2822 timestamp. Preserve previous release entries.
   If new changes were added to the previous release's entry during
   development, move those changes into the new entry.
3. The application version comes from Git tags through `git describe` in
   `src/CMakeLists.txt`; do not introduce a hard-coded version bump.
4. Run `git diff --check` and review the complete release metadata diff.
   Documentation-only preparation does not require another build. If code
   changes are needed, follow the repository's build and test instructions.

## Commit and publish

Stage only the intended release files. Follow the established commit and
annotated-tag format, substituting the requested version:

```bash
git add RELEASE_NOTES.md debian/changelog
git commit -m "chore: Release vX.Y.Z" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

Unless explicitly instructed otherwise, retain the Copilot co-author trailer.

### Avoid cancelling the release workflow

The workflow currently uses one concurrency group for all refs:
`group: ${{ github.workflow }}` with `cancel-in-progress: true`.
Main-branch pushes create draft releases; tag pushes publish final releases.

**Do not push the main branch and release tag together.** This was done for
`v1.0.12.c`, and the main-branch run cancelled the tag run immediately.

1. Push the release commit to `main` without the tag:
   `git push origin main`.
2. Confirm the main-branch workflow for that commit has started, preferably
   wait until it finishes, before pushing the release tag. Do not assume push
   event ordering.
3. Push the annotated tag explicitly:
   `git push origin refs/tags/vX.Y.Z`.
4. Verify remote `main`, the tag, and its peeled commit with `git ls-remote`.
5. Inspect the workflow run for the **tag**, not just the same commit on
   `main`. Avoid further main-branch pushes while the release run is active.

Do not silently change the workflow's concurrency configuration as part of
release preparation.

## Verify publication and recover failures

- Check the tag workflow using GitHub Actions tools or GitHub CLI. Successful
  Linux, Windows, and macOS package jobs allow the `release` job to publish
  `Release vX.Y.Z` as a non-draft release with the generated notes and packages.
- Confirm the GitHub release exists for the requested tag, is not a draft,
  and has the expected package assets before reporting publication complete.
- If concurrency cancels the tag run, rerun that existing run after the
  conflicting run has finished. With authenticated GitHub CLI:
  `gh run rerun <tag-run-id> --repo Laerdal-Medical/simserver-imager`.
  Do not delete, move, or re-create the tag to retrigger the workflow.
- Do not assume `gh` or API credentials are available. Never expose
  credentials. If rerunning is unavailable, provide the exact Actions run
  URL and state that publication is blocked pending a manual rerun.
- Distinguish "release commit and tag pushed" from "release published".
  If CI is still running, report it as pending rather than complete.
