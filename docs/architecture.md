# RightClick Pro Architecture

RightClick Pro is split into a lightweight Finder Sync extension and a user-level XPC ActionRunner. Swift package, target, module, and public project types use the `RightClickPro*` naming family.

```text
Finder
  → FinderSyncExtension
  → NSXPCConnection
  → RightClickProActionRunner
  → FileOperationService / App opener / OperationLog
```

## Boundaries

* `RightClickProCore` owns shared models, menu building, storage, authorization checks, file operations, action execution, operation logging, and XPC adapter types.
* `RightClickProFinderExtension` reads shared config and renders Finder menus. It must not perform file mutations directly.
* `RightClickProActionRunnerService` exposes the XPC service boundary and delegates requests to `ActionRunner`.
* `RightClickProAppPreview` is a SwiftUI/AppKit scaffold for the menu-bar app and settings window.

## MVP Storage

```text
~/Library/Application Support/com.iheeleme.rightclickpro
├── config.json
├── bookmarks.json
├── cut-clipboard.json
├── operation-log.jsonl
├── pending-command-run.json
├── command-runs/
└── icon-cache/
    └── v1/
```

Config writes use atomic file replacement via `Data.write(..., .atomic)`. Operation logs are stored as JSONL and capped to the latest 500 records by default.

The app, Finder extension, and ActionRunner XPC all resolve this real-user Application Support path. The packaged sandboxed app and extension include a narrow home-relative read/write entitlement for this app-owned directory, so first launch does not need to read or write `~/Library/Group Containers`. New installs inject existing Desktop and Downloads directories as shortcut targets. Existing bookmark entries are preserved during bootstrap and migration.

## Authorization Model

Finder menu scope is global: the Finder Sync extension registers `/` with `FIFinderSyncController.directoryURLs` and no longer filters menu visibility by configured directories. Configured directories are shortcut targets only.

The ActionRunner no longer treats configured directories as an authorization boundary. File actions and command templates attempt the requested file-system operation directly. When macOS denies access, user-facing failures point to System Settings > Privacy & Security > Full Disk Access. Directory bookmarks are still resolved opportunistically for shortcut destination actions and existing security-scoped bookmark data can help those paths, but real execution success is determined by macOS permissions.

Command templates execute in `RightClickProActionRunner.xpc`. The main app still owns the command output window, but it starts/stops runs through XPC and polls `command-runs/<run-id>.json` snapshots for stdout/stderr chunks, final status, exit code, and duration.

Finder Sync copies menu items through Finder before dispatching the selected command back to the extension. Do not rely on `representedObject` for action payloads there; leaf menu items use stable integer `tag` values that map back to pending actions held by `FinderSyncController`.

Finder may cold-start the Finder Sync extension after a long idle period. The extension therefore installs a fallback menu config before exposing the global Finder Sync scope, then loads config/bookmarks and repairs durable config in the background. `menu(for:)` serves from memory instead of doing synchronous JSON/bootstrap work during the menu request. Config refresh is scheduled after the menu has been returned, so a right-click does not become the disk-refresh trigger. Menu rendering does not synchronously resolve real app bundle or file-path icons on cache misses, and it also does not start that work from inside the callback. App icons show a generic SF Symbol placeholder immediately, file paths show lightweight folder/file placeholders where possible, and a low-priority background icon queue resolves the real icons with `NSWorkspace.shared.icon(forFile:)` only after a short no-menu idle window. Resolved icons are rasterized into small menu-ready PNG images, cached under `icon-cache/v1`, and loaded back into memory asynchronously on later extension starts, so later right-clicks do not become the first AppKit/ICNS draw point.

## Current Build Note

The current development machine has Swift Command Line Tools but no full Xcode installation selected, so SwiftPM tests cover the core module. The preview packaging script manually embeds:

```text
RightClick Pro.app
├── Contents/PlugIns/RightClickProFinderExtension.appex
│   └── Contents/XPCServices/RightClickProActionRunner.xpc
└── Contents/XPCServices/RightClickProActionRunner.xpc
```

The preview `.appex` is linked as an `_NSExtensionMain` executable so PlugInKit can discover it for local Finder Sync testing. A complete Xcode project plus Developer ID signing and notarization are still required before treating the artifact as a normal public macOS download.

For local preview testing, the embedded ActionRunner XPC service is signed without the app sandbox entitlement. It uses the same Application Support storage path as the app and Finder extension, while file actions and command templates rely on macOS Full Disk Access at execution time instead of a code-level configured-directory validator.

On first app launch after a DMG install, the settings app asks the embedded ActionRunner XPC service to register the bundled Finder Sync extension with PlugInKit, request enablement, and reload Finder once for the current packaged extension signature. The signature includes filesystem resource identity for the `.appex`, its `Info.plist`, the extension executable, and the host app bundle, so replacing the same version at the same path still triggers one fresh preload. Successful setup is recorded in user defaults, so subsequent launches skip the repair until the physical packaged extension changes again. The same XPC maintenance path backs the manual "restart Finder" repair action, so the sandboxed app does not run `pluginkit` or signal Finder directly.

Finder Sync receives `/` as its sync root. Menu items remain visible globally; individual actions are still filtered by invocation shape such as container, selection, or toolbar.
