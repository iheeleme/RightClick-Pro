# Add GitHub Latest Version Update Check

## Goal

Add an in-app version update check for RightClick Pro, using GitHub Releases as the source of truth so users can see whether their installed app is current and jump to the release page when a newer version exists.

## What I Already Know

* User requested: "增加版本更新检查能力，更新版本使用GitHub 的最新版本检查".
* The app is a native macOS SwiftUI menu bar app.
* Settings UI lives in `Sources/RightClickProAppPreview/`.
* `AppMetadata.versionText` currently reads `CFBundleShortVersionString` and `CFBundleVersion` from `Bundle.main`.
* `scripts/package-macos.sh` writes `CFBundleShortVersionString` from `RIGHTCLICKPRO_VERSION`, GitHub tag name, GitHub SHA, or `0.0.0-dev`.
* README uses GitHub Releases at `https://github.com/iheeleme/RightClick-Pro/releases`.
* GitHub's latest release endpoint currently returns 404 for `iheeleme/RightClick-Pro`, so "no full release yet" must be handled gracefully.

## Assumptions

* MVP should check manually from the settings Overview page rather than silently polling in the background.
* The GitHub repository is `iheeleme/RightClick-Pro`.
* "Latest version" means GitHub latest published full release, not draft releases or prereleases.

## Requirements

* Add an update-check state model that can represent unchecked, checking, up-to-date, update available, and unavailable states.
* Fetch GitHub's latest release endpoint for `iheeleme/RightClick-Pro`.
* Use GitHub's formal latest release semantics only; prereleases are not included in MVP checks.
* Compare GitHub `tag_name` against the current app short version from `Bundle.main`.
* Strip a leading `v` before comparing versions.
* Surface network/API failures as user-readable status messages.
* Treat GitHub 404 from latest release as "no public full release available yet".
* Add a visible control in the Overview screen for checking updates and opening GitHub releases.

## Acceptance Criteria

* [ ] User can manually trigger "检查更新" from the Overview settings screen.
* [ ] While checking, the UI disables duplicate checks and shows a checking state.
* [ ] If GitHub reports a newer release, the UI shows the latest tag/version and offers to open the release page.
* [ ] If the installed version is current, the UI says it is up to date.
* [ ] If GitHub returns 404, the UI explains that no public full release is available yet.
* [ ] Network and decoding failures do not crash the app and are shown as retryable errors.
* [ ] Swift compile checks pass.

## Definition of Done

* Tests added/updated where version comparison is separated into testable logic.
* `swift build --target RightClickProAppPreview` passes.
* `scripts/ci-swift-check.sh debug` passes or any failure is documented.
* UI change follows existing Overview panel visual style.

## Out of Scope

* Automatic background polling.
* Auto-download or in-app installation.
* Sparkle integration.
* Authentication or private GitHub API tokens.
* Draft release support.
* Prerelease update checks.

## Technical Approach

MVP should keep the network/UI behavior in the app target and extract version comparison into a small testable helper where practical. The Overview page can add a compact `UpdateCheckPanel` near the existing launch/login and permission panels.

## Decision (ADR-lite)

**Context**: GitHub offers a dedicated latest release endpoint for published full releases. Including prereleases would require a different endpoint and custom filtering.

**Decision**: Use only GitHub's latest full release endpoint for this task.

**Consequences**: Users on preview/test channels will not be notified about prereleases. The implementation stays simpler, stable, and aligned with public release distribution.

## Research References

* `research/github-release-api.md` — GitHub's latest release API behavior, fields, and edge cases.

## Technical Notes

* Likely files:
  * `Sources/RightClickProAppPreview/RightClickProAppPreview.swift`
  * `Sources/RightClickProAppPreview/SettingsViewModel.swift`
  * `Sources/RightClickProAppPreview/OverviewViews.swift`
  * new helper file under `Sources/RightClickProAppPreview/` or reusable comparison helper under `RightClickProCore` if tests need Core target access.
* Relevant specs:
  * `.trellis/spec/frontend/index.md`
  * `.trellis/spec/frontend/state-management.md`
  * `.trellis/spec/frontend/component-guidelines.md`
  * `.trellis/spec/frontend/quality-guidelines.md`
  * `.trellis/spec/backend/index.md`
  * `.trellis/spec/backend/error-handling.md`
  * `.trellis/spec/backend/quality-guidelines.md`
