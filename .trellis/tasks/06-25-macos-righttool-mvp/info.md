# Implementation Notes

## Current Implementation Slice

This session implemented the first code slice for the RightTool MVP:

* Swift Package manifest for the RightTool workspace.
* `RightToolCore` shared module:
  * Unified Action model.
  * Finder context and Action request/result contracts.
  * Menu builder with root-menu placement cap.
  * App Group storage path model.
  * Atomic JSON store.
  * JSONL operation log capped to recent records.
  * Directory bookmark catalog and security-scoped bookmark resolver.
  * Authorized path validator.
  * File operation service with conflict resolution.
  * Tool-internal cut clipboard store.
  * ActionRunner for create, cut, paste, move, copy, open directory, and open-in-app actions.
  * NSXPC adapter boundary.
  * NSXPC client for Finder Extension → ActionRunner requests.
* `RightToolActionRunnerService` XPC service scaffold.
* `RightToolAppPreview` SwiftUI/AppKit menu-bar/settings scaffold.
* `RightToolFinderExtension` Finder Sync scaffold.
* XCTest test files for core behavior.
* `docs/architecture.md` with process/storage/boundary notes.
* GitHub Actions packaging workflow:
  * `.github/workflows/package-macos.yml`
  * `scripts/ci-swift-check.sh`
  * `scripts/package-macos.sh`
  * `docs/github-actions-packaging.md`
  * `research/github-actions-packaging.md`
  * manual dispatch supports `version=0.1.0-test.1` for the first test package.

## Verification Performed

The local machine has Swift Command Line Tools but no full Xcode installation selected:

```text
xcodebuild requires Xcode, but active developer directory is CommandLineTools
```

SwiftPM is also failing even for a minimal package manifest because the local `PackageDescription` library cannot link its standard `Package(...)` initializer. This was reproduced outside the project with a temporary minimal package, so it is an environment/toolchain issue rather than a RightTool manifest issue.

Because of that, verification used direct `swiftc` checks:

* `RightToolCore` compiled as a temporary module and dylib.
* Manual runner passed for:
  * root-menu cap of 5 items;
  * create-file conflict keep-both behavior;
  * ActionRunner create-file flow;
  * internal cut/paste flow;
  * operation log writes.
* Direct typecheck passed for:
  * `RightToolActionRunnerService`;
  * `RightToolAppPreview`;
  * `RightToolFinderExtension`.

XCTest files are present but could not be run/typechecked directly because the Command Line Tools install does not expose an `XCTest` module and SwiftPM is blocked by the manifest-linking issue. Full XCTest execution should be done after installing/selecting Xcode.

## Next Implementation Steps

* Wire real Xcode app bundle targets for:
  * main app;
  * Finder Sync extension;
  * embedded XPC service.
* Wire the XPC service into a real signed app bundle and confirm the configured service name.
* Add a full Xcode project/scheme so GitHub Actions can produce signed `.app` / `.appex` archives instead of SwiftPM preview bundles.
* Add settings UI persistence for directories, actions, templates, and developer entrypoints.
* Add real security-scoped bookmark creation from user-selected directories.
* Add conflict-resolution UI in the main app.
* Run `swift test` / `xcodebuild test` after a full Xcode toolchain is available.
