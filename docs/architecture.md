# RightTool Architecture

RightTool is split into a lightweight Finder Sync extension and a user-level XPC ActionRunner.

```text
Finder
  → FinderSyncExtension
  → NSXPCConnection
  → RightToolActionRunner
  → FileOperationService / App opener / OperationLog
```

## Boundaries

* `RightToolCore` owns shared models, menu building, storage, authorization checks, file operations, action execution, operation logging, and XPC adapter types.
* `RightToolFinderExtension` reads shared config and renders Finder menus. It must not perform file mutations directly.
* `RightToolActionRunnerService` exposes the XPC service boundary and delegates requests to `ActionRunner`.
* `RightToolAppPreview` is a SwiftUI/AppKit scaffold for the menu-bar app and settings window.

## MVP Storage

```text
App Group Container
├── config.json
├── bookmarks.json
├── cut-clipboard.json
└── operation-log.jsonl
```

Config writes use atomic file replacement via `Data.write(..., .atomic)`. Operation logs are stored as JSONL and capped to the latest 500 records by default.

Unsigned/local preview builds may not have an App Group entitlement. In that case, the runtime falls back to:

```text
~/Library/Application Support/com.righttool.app
```

On machines where `group.com.righttool.app` is available, the app writes default preview configuration there. The bootstrapper injects existing Desktop, Downloads, Documents, and Code directories as monitored/common directories.

## Authorization Model

The ActionRunner builds an `AuthorizedPathValidator` from monitored and common directory bookmarks. MVP file operations must target authorized paths only.

## Current Build Note

The current development machine has Swift Command Line Tools but no full Xcode installation selected, so SwiftPM tests cover the core module. Building and signing the final `.app` / `.appex` bundle requires opening the package/project in Xcode and wiring the Finder Sync extension and XPC service targets into a macOS app bundle.
