# State Management

Settings state is centralized in `SettingsViewModel`. It bridges Core storage models to SwiftUI screens and owns persistence commands.

## State Categories

| State | Owner | Examples |
|-------|-------|----------|
| Durable config | `RightClickProCore` JSON files via `SettingsViewModel` | `RightClickProConfig`, `DirectoryBookmarkCatalog` |
| View model state | `SettingsViewModel` | `selectedSection`, `statusMessage`, `statusTone`, `hasUnsavedChanges`, `recentOperations` |
| Local UI state | Individual views | filters, grouping modes, preview context, editing drafts |
| Derived state | Computed properties/functions | enabled action count, root menu progress, sidebar badges |

Reference file: `Sources/RightClickProAppPreview/RightClickProAppPreview.swift`.

## Persistence Rules

- `SettingsViewModel.loadOrBootstrap()` uses `ConfigurationBootstrapper` and applies the result.
- `saveConfig()` validates and writes both `bookmarks.json` and `config.json`.
- Directory add/edit/delete operations currently save immediately through `saveDirectoryChanges`.
- Template/action/developer edits mark unsaved changes and require the main save action.
- `reloadRecentOperations()` reads `operation-log.jsonl` and keeps the latest 80 reversed for display.
- Finder menu repair state lives in `SettingsViewModel.isRepairingFinderMenu`, `finderExtensionNeedsAttention`, and `finderExtensionSetupMessage`; the ViewModel sends `SystemMaintenanceRequest` through ActionRunner XPC instead of running system commands directly from SwiftUI.
- Full Disk Access overview state lives in `SettingsViewModel.fullDiskAccessStatus`; the ViewModel checks it through `SystemMaintenanceRequest(task: .checkFullDiskAccess)` so the UI reflects ActionRunner's real execution permission, not the sandboxed app process.
- Successful automatic Finder extension setup is keyed by the bundled `.appex` install signature in `UserDefaults`; the signature must include filesystem resource identity so same-version reinstall/overwrite triggers one fresh Finder preload, while repeated launches of the same physical extension skip Finder restarts.

## Command Rules

Use command methods for mutations:

- Actions: `setActionEnabled`, `setActionPlacement`, `toggleActionVisibility`, `moveAction`.
- Templates: `upsertTemplate`, `deleteTemplate`, `moveTemplate`.
- Developer entries: `upsertDeveloperEntrypoint`, `deleteDeveloperEntrypoint`, `moveDeveloperEntrypoint`.
- Directories: `addDirectoryBookmarkFromPanel`, `replaceDirectoryBookmarkFromPanel`, `deleteDirectoryBookmark`, `setDirectoryBookmarkEnabled`, `moveDirectoryBookmark`.
- Finder repair: `repairFinderContextMenu(restartFinder:userInitiated:)` and `restartFinder()`.

Commands must keep related config references synchronized. Examples:

- Adding a `FileTemplate` creates or updates a matching `.createFile` action.
- Deleting a `FileTemplate` removes matching `.createFile` actions.
- Adding a `DeveloperEntrypoint` creates or updates a matching `.openInApp` action.
- Deleting a directory removes monitored/common IDs and generated directory actions.
- Moving templates/developer entries/directories normalizes associated action order values.

## Validation

Before persisting, validate:

- Enabled root actions do not exceed `maxRootMenuActions`.
- Template IDs/titles/default filenames are non-empty.
- Template and developer IDs are unique.
- Developer titles and bundle identifiers are non-empty.
- File names do not contain `/`.

Use `SettingsValidationError` for user-facing save errors.

## Anti-Patterns

- Do not mutate `config.actions` from child views without a ViewModel command.
- Do not run `pluginkit`, `killall`, or `osascript` directly from SwiftUI views; route Finder menu repair through `SettingsViewModel` and ActionRunner XPC.
- Do not probe Full Disk Access directly from SwiftUI views or the sandboxed app process; route the check through ActionRunner XPC and hide the overview prompt after a successful probe.
- Do not show the Finder Extension setup banner after automatic setup succeeds; show it only when setup fails or needs manual attention.
- Do not let an action lose all `ActionVisibility` cases.
- Do not add config entries without back-reference actions.
- Do not treat a preview-only filter/sort as persisted unless it updates `RightClickProConfig`.
