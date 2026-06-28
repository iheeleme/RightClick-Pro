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
App Group Container
├── config.json
├── bookmarks.json
├── cut-clipboard.json
└── operation-log.jsonl
```

Config writes use atomic file replacement via `Data.write(..., .atomic)`. Operation logs are stored as JSONL and capped to the latest 500 records by default.

Unsigned/local preview builds may not have an App Group entitlement. In that case, the runtime falls back to:

```text
~/Library/Application Support/com.iheeleme.rightclickpro
```

On machines where `group.com.iheeleme.rightclickpro` is available, the app writes default preview configuration there. The bootstrapper injects existing Desktop, Downloads, Documents, and Code directories as monitored/common directories.

## Authorization Model

The ActionRunner resolves monitored and common directory bookmarks before each request, starts security-scoped access when bookmark data exists, then builds an `AuthorizedPathValidator` from those resolved URLs. MVP file operations must target authorized paths only.

Finder Sync copies menu items through Finder before dispatching the selected command back to the extension. Do not rely on `representedObject` for action payloads there; leaf menu items use stable integer `tag` values that map back to pending actions held by `FinderSyncController`.

## Current Build Note

The current development machine has Swift Command Line Tools but no full Xcode installation selected, so SwiftPM tests cover the core module. The preview packaging script manually embeds:

```text
RightClick Pro.app
├── Contents/PlugIns/RightClickProFinderExtension.appex
│   └── Contents/XPCServices/RightClickProActionRunner.xpc
└── Contents/XPCServices/RightClickProActionRunner.xpc
```

The preview `.appex` is linked as an `_NSExtensionMain` executable so PlugInKit can discover it for local Finder Sync testing. A complete Xcode project plus Developer ID signing and notarization are still required before treating the artifact as a normal public macOS download.

For local preview testing, the embedded ActionRunner XPC service is signed with the App Group entitlement but without the app sandbox entitlement. The code-level authorized-directory validator still constrains file mutations, while this avoids sandbox denial when exercising auto-injected Desktop/Documents/Downloads/Code paths before a real user-selected security-scoped bookmark flow is implemented.

On first app launch after a DMG install, the settings app asks the embedded ActionRunner XPC service to register the bundled Finder Sync extension with PlugInKit and request enablement. The same XPC maintenance path backs the "restart Finder" repair action, so the sandboxed app does not run `pluginkit` or signal Finder directly.
