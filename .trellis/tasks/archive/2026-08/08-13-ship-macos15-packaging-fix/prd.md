# Ship macOS 15 Packaging Fix

## Goal

Integrate the verified macOS 15 packaging compatibility fix onto the latest remote `develop`, then publish a new preview release whose arm64 and x86_64 DMGs are built with a macOS 14.0 deployment target.

## What I Already Know

* Commit `9840837` fixes the macOS 15 crash caused by `libRightClickProCore.dylib` inheriting a macOS 26.0 deployment target.
* The fix passes locally on macOS 26.5.2 with Xcode 26.2: 54 tests pass, DMG packaging succeeds, and all eight packaged Mach-O files report `minos 14.0`.
* `origin/develop` does not contain the fix and currently builds on macOS 26 runners without an explicit deployment target.
* `origin/develop` contains newer update-check and GitHub Release publishing changes that must be preserved.
* Tag `v0.1.3` triggered both macOS 15 jobs, but release compilation failed because the static `NSImage?` cache in `RightClickProIconAsset` was not main-actor isolated. The tag remains immutable and has no GitHub Release.
* The next patch release is `v0.1.4`.

## Requirements

* Start from the latest `origin/develop` in a new `codex/` branch.
* Integrate only the functional macOS compatibility commit, not the archived task or journal commits from the old branch.
* Preserve all newer `develop` behavior, including app network entitlements and tag-driven GitHub Release publishing.
* Pin CI to explicit macOS 15 arm64 and Intel runners.
* Set the packaging deployment target to macOS 14.0 across SwiftPM, direct `swiftc`, Xcode, generated Info.plists, and CI environment variables.
* Reject packaged executables or embedded dylibs whose Mach-O deployment target differs from 14.0.
* Push the integrated branch and merge it into remote `develop` without rewriting shared history.
* Main-actor isolate the shared AppKit icon cache so both macOS 15 runners pass Swift concurrency checks.
* Create and push tag `v0.1.4` only after the follow-up fix is on `develop`.
* Verify the tag-triggered arm64 package job, x86_64 package job, Release publishing job, and published DMG assets.

## Acceptance Criteria

* [x] Shell syntax, workflow YAML, whitespace, Swift build, and all tests pass.
* [x] Local release DMG packaging succeeds on the current macOS 26 host.
* [x] All packaged app, Finder extension, XPC, and core dylib Mach-O files report `minos 14.0`.
* [x] All generated bundle Info.plists report `LSMinimumSystemVersion=14.0`.
* [x] The fix is present on remote `develop`.
* [x] Tag `v0.1.3` points to the initial fixed `develop` commit but its workflow failed before packaging.
* [x] Tag `v0.1.4` points to the final fixed `develop` commit.
* [x] GitHub Actions completes both architecture builds and the release job successfully.
* [x] The `v0.1.4` GitHub Release exposes both arm64 and x86_64 DMG assets.

## Rollback

* Do not push a release tag if local validation or integration fails.
* If the remote packaging workflow fails after tagging, diagnose and fix forward on `develop`; do not move or overwrite the existing tag.

## Out Of Scope

* Developer ID signing and notarization.
* Changing the product minimum below macOS 14.
* Unrelated Swift application behavior or UI changes.

## Technical Notes

* Compatibility source commit: `98408373d3ccd3baff01bc8be7df875e0c864e79`.
* Relevant files: `.github/workflows/package-macos.yml`, `scripts/ci-swift-check.sh`, `scripts/package-macos.sh`, `docs/github-actions-packaging.md`.
* Relevant spec: `.trellis/spec/backend/quality-guidelines.md`.
