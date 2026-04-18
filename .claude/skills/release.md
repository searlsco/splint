---
description: Release a new Splint version. Takes `major`, `minor`, or `patch`. Bumps the version, rolls CHANGELOG, runs tests, tags, and pushes.
---

# Release a new version of Splint

You are about to cut a release. Follow these steps exactly.

## Preconditions

- The working tree must be clean. If it isn't, stop and ask the user.
- The user must have specified one of `major`, `minor`, or `patch` as the
  argument. If they didn't, ask which.
- You must be on the `main` branch.

## Steps

1. Read `CHANGELOG.md`. Confirm the `## [Unreleased]` section contains
   real, non-empty entries describing what is shipping. If it does not,
   stop and ask the user to populate it first — a release with an empty
   CHANGELOG is a mistake.

2. Run `script/release <major|minor|patch>` with the requested bump.
   The script will:
   - Compute the next bare semver tag from the latest existing tag.
   - Roll `## [Unreleased]` into a dated `## [X.Y.Z] - YYYY-MM-DD` section.
   - Run `script/test` — stops on failure.
   - Commit the CHANGELOG update (if any).
   - Tag the commit with bare semver (no `v` prefix).
   - Push `main` and the tag.

3. After the script succeeds, the `Create GitHub Release` workflow
   (`.github/workflows/release.yml`) fires on the tag push and creates a
   GitHub Release with auto-generated notes. Verify it:

   ```bash
   gh run list --workflow "Create GitHub Release" --limit 1
   gh release view <next>
   ```

   Wait for the run to show `completed success` and confirm the release
   page exists.

4. Report the new version to the user and remind them that Swift Package
   Index will pick the tag up on its next crawl.

5. If any step fails, STOP. Do not retry blindly. Surface the error and
   let the user decide whether to re-run or investigate.

## Do not

- Do not amend previous tags.
- Do not force-push.
- Do not skip `script/test`.
- Do not hand-edit `CHANGELOG.md` outside of the `[Unreleased]` section
  unless the user explicitly asks you to.
