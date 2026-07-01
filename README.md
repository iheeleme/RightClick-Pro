# RightClick Pro

RightClick Pro is a native macOS Finder context-menu productivity tool for developers and power users. It adds configurable right-click actions to Finder, backed by a lightweight Finder Sync extension and a user-level XPC action runner.

> Current status: preview build. The project can produce local and GitHub Actions DMG artifacts, but it is not yet Developer ID signed or notarized.

## Features

- Global Finder right-click menu powered by Finder Sync.
- Shortcut directories for quick open, move, and copy actions.
- File operations including cut, paste, copy, move, and text-file creation.
- Built-in file templates for text, Markdown, JSON, `.gitignore`, and Swift files.
- Developer app shortcuts for Terminal, VS Code, Cursor, and custom macOS apps.
- Command templates with realtime stdout/stderr output, stop control, timeout handling, and operation history.
- Sensitive command environment variables stored in macOS Keychain.
- Operation history stored locally as JSONL.
- Login-at-startup setting through macOS ServiceManagement.
- Full Disk Access guidance and Finder Extension repair actions in the settings UI.

## Why This Exists

Finder's built-in context menu is useful, but it is not designed around repeatable developer workflows. RightClick Pro focuses on the few actions that are easiest to reach from Finder and annoying to repeat by hand:

- open the current folder in a development tool;
- move or copy selected files to common destinations;
- create a starter file in the current directory;
- run a known command against the current folder or selected item;
- inspect recent file operations when something fails.

## Requirements

- macOS 14 Sonoma or later.
- Swift 6 toolchain for development builds.
- Full Disk Access is recommended for real file actions and command templates.
- Finder Extension must be enabled in System Settings.

## Installation

### From a DMG

GitHub Actions artifacts are DMG-only preview packages when the packaging workflow runs.

1. Open the DMG.
2. Drag `RightClick Pro.app` into `/Applications`.
3. Launch `RightClick Pro` from `/Applications`.
4. If macOS blocks the app because it is not notarized, remove quarantine for local testing:

```bash
xattr -cr "/Applications/RightClick Pro.app"
```

5. Open the app again. The app will attempt to register the bundled Finder Extension and reload Finder once.
6. If the Finder menu does not appear, open RightClick Pro settings and use the Finder Extension repair action.

### Local Developer Install

```bash
scripts/package-macos.sh debug
rm -rf "/Applications/RightClick Pro.app"
ditto "dist/staging/RightClick Pro.app" "/Applications/RightClick Pro.app"
xattr -cr "/Applications/RightClick Pro.app"
open "/Applications/RightClick Pro.app"
```

The installed app owns runtime Finder Extension registration. The staging bundle is not registered by default, so Finder does not show source-directory build artifacts as app icons.

## Build From Source

Run the core checks:

```bash
scripts/ci-swift-check.sh debug
```

Build the preview app target:

```bash
swift build --target RightClickProAppPreview
```

Build a local preview app bundle:

```bash
scripts/package-macos.sh debug
```

Build a local preview DMG:

```bash
RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh release
```

## Architecture

```text
Finder
  -> RightClickProFinderExtension
  -> NSXPCConnection
  -> RightClickProActionRunner.xpc
  -> RightClickProCore
```

The package is split into four main targets:

- `RightClickProCore` owns shared models, menu building, storage, file operations, command execution, operation logging, and XPC contracts.
- `RightClickProFinderExtension` reads shared config and renders Finder menus. It does not mutate files directly.
- `RightClickProActionRunnerService` exposes the XPC service and delegates requests to the core action runner.
- `RightClickProAppPreview` is the SwiftUI/AppKit menu-bar app and settings window.

Runtime state is stored in the App Group container when available, with a local Application Support fallback for unsigned preview builds:

```text
App Group Container
├── config.json
├── bookmarks.json
├── cut-clipboard.json
├── operation-log.jsonl
├── pending-command-run.json
├── command-runs/
└── icon-cache/
    └── v1/
```

More details are in [docs/architecture.md](docs/architecture.md).

## Security and Permissions

RightClick Pro does not install a privileged helper. File operations and command templates run as the current user through the packaged XPC service.

The Finder menu is globally visible, while actual execution is still governed by macOS permissions. If macOS denies access, RightClick Pro surfaces Full Disk Access guidance instead of using a custom directory allowlist as an authorization boundary.

Command templates are intentionally template-based. The app does not support ad-hoc command entry from Finder's context menu.

## Packaging Notes

The current preview package is manually assembled from a Swift Package. It embeds:

```text
RightClick Pro.app
├── Contents/PlugIns/RightClickProFinderExtension.appex
│   └── Contents/XPCServices/RightClickProActionRunner.xpc
└── Contents/XPCServices/RightClickProActionRunner.xpc
```

The preview bundle is ad-hoc signed when `codesign` is available. Public distribution still needs a full Xcode project, Developer ID signing, and notarization.

See [docs/github-actions-packaging.md](docs/github-actions-packaging.md) for CI packaging details.

## Repository Layout

```text
Sources/
├── RightClickProCore/
├── RightClickProFinderExtension/
├── RightClickProActionRunnerService/
└── RightClickProAppPreview/
Tests/
└── RightClickProCoreTests/
scripts/
├── ci-swift-check.sh
└── package-macos.sh
docs/
├── architecture.md
└── github-actions-packaging.md
```

## Development Workflow

Before sending a change, run:

```bash
git diff --check
scripts/ci-swift-check.sh debug
```

After settings UI, Finder extension, XPC, entitlement, or packaging changes, also run:

```bash
scripts/package-macos.sh debug
```

For local Finder Sync smoke tests against the staging bundle:

```bash
RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
```

## Known Limitations

- Preview builds are not Developer ID signed or notarized.
- The project is still SwiftPM-first and does not yet include a full Xcode app project.
- Finder Sync behavior may require enabling the extension manually in System Settings.
- Full Disk Access is user-controlled; the app can guide and check, but it cannot silently grant itself permission.
- The current conflict strategy keeps both files by default; a richer conflict-confirmation UI is still future work.
- License metadata has not been added yet.

## Contributing

Issues and pull requests are welcome. Please keep changes aligned with the existing target boundaries:

- put shared contracts and execution logic in `RightClickProCore`;
- keep Finder menu rendering in `RightClickProFinderExtension`;
- keep settings UI and AppKit/SwiftUI presentation in `RightClickProAppPreview`;
- keep the XPC service entry point thin.

When adding or changing a Finder action kind, expect to update models, menu projection, execution, settings display, and tests together.

## License

This repository does not currently include a `LICENSE` file. Until a license is added, treat the source as visible for review and collaboration, but not explicitly licensed for redistribution or commercial reuse.
