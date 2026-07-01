# State Management

Settings state is centralized in `SettingsViewModel`. It bridges Core storage models to SwiftUI screens and owns persistence commands.

## State Categories

| State | Owner | Examples |
|-------|-------|----------|
| Durable config | `RightClickProCore` JSON files via `SettingsViewModel` | `RightClickProConfig`, `DirectoryBookmarkCatalog` |
| View model state | `SettingsViewModel` | `selectedSection`, `statusMessage`, `statusTone`, `hasUnsavedChanges`, `recentOperations` |
| Local UI state | Individual views | filters, grouping modes, preview context, editing drafts |
| Derived state | Computed properties/functions | enabled action count, root menu progress, sidebar badges |

Reference files: `Sources/RightClickProAppPreview/SettingsViewModel.swift` and the section views under `Sources/RightClickProAppPreview/`.

## Persistence Rules

- `SettingsViewModel.loadOrBootstrap()` uses `ConfigurationBootstrapper` and applies the result.
- `saveConfig()` validates and writes both `bookmarks.json` and `config.json`.
- Directory add/edit/delete operations currently save immediately through `saveDirectoryChanges`.
- Template/action/developer edits mark unsaved changes and require the main save action.
- `reloadRecentOperations()` reads `operation-log.jsonl` and keeps the latest 80 reversed for display.
- Finder menu repair state lives in `SettingsViewModel.isRepairingFinderMenu`, `finderExtensionNeedsAttention`, and `finderExtensionSetupMessage`; the ViewModel sends `SystemMaintenanceRequest` through ActionRunner XPC instead of running system commands directly from SwiftUI.
- Full Disk Access overview state lives in `SettingsViewModel.fullDiskAccessStatus`; the ViewModel checks it through `SystemMaintenanceRequest(task: .checkFullDiskAccess)` so the UI reflects ActionRunner's real execution permission, not the sandboxed app process.
- Full Disk Access checks must be user-initiated from the overview CTA. Do not schedule the probe from app bootstrap or `NSApplication.didBecomeActiveNotification`; representative protected-path reads can trigger repeated macOS authorization prompts.
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
- Do not call `SMAppService` directly from SwiftUI views; route login-item reads and writes through `SettingsViewModel`.
- Do not show the Finder Extension setup banner after automatic setup succeeds; show it only when setup fails or needs manual attention.
- Do not let an action lose all `ActionVisibility` cases.
- Do not add config entries without back-reference actions.
- Do not treat a preview-only filter/sort as persisted unless it updates `RightClickProConfig`.

## Scenario: Launch at Login Setting

### 1. Scope / Trigger

- Trigger: adding or changing the macOS "登录时自动启动" setting in the overview/settings surface.
- This is system state managed by macOS ServiceManagement, not durable app config.

### 2. Signatures

- ViewModel state and commands:
  ```swift
  enum LaunchAtLoginStatus: Equatable
  var launchAtLoginToggleIsOn: Bool
  var launchAtLoginStatusMessage: String
  var launchAtLoginStatusTone: StatusTone
  func refreshLaunchAtLoginStatus()
  func setLaunchAtLoginEnabled(_ isEnabled: Bool)
  func openLoginItemsSettings()
  ```
- System API:
  ```swift
  import ServiceManagement
  SMAppService.mainApp.status
  try SMAppService.mainApp.register()
  try SMAppService.mainApp.unregister()
  ```

### 3. Contracts

- `LaunchAtLoginStatus.enabled` maps to `SMAppService.Status.enabled`.
- `LaunchAtLoginStatus.disabled` maps to `.notRegistered`.
- `LaunchAtLoginStatus.requiresApproval` maps to `.requiresApproval`; the UI toggle should remain on because the app has requested the login item and the user must approve it in System Settings.
- `LaunchAtLoginStatus.unavailable` covers `.notFound`, thrown register/unregister errors, and unknown future statuses.
- `refreshLaunchAtLoginStatus()` runs during `SettingsViewModel.bootstrap()` and when the app becomes active so external System Settings changes are reflected.
- The setting does not mark `hasUnsavedChanges` and is not saved to `config.json`.

### 4. Validation & Error Matrix

- `register()` throws -> refresh status and show `"更新登录项失败：..."` with `.error`.
- `unregister()` throws -> refresh status and show `"更新登录项失败：..."` with `.error`.
- Status is `.requiresApproval` -> show warning tone and provide an "打开登录项" action.
- Status is `.notFound` -> show unavailable status; do not pretend the switch is enabled.

### 5. Good/Base/Bad Cases

- Good: user turns the switch on, `SMAppService.mainApp.register()` succeeds, status refreshes to `.enabled` or `.requiresApproval`.
- Base: user disables the item from System Settings while the app is open; when the app becomes active, `refreshLaunchAtLoginStatus()` updates the switch.
- Bad: writing a `launchAtLogin` flag into `RightClickProConfig` and showing it as enabled even though macOS has disabled the login item.
- Bad: a SwiftUI row calls `SMAppService.mainApp.register()` directly and bypasses status messages.

### 6. Tests Required

- Run `swift build --target RightClickProAppPreview` after settings UI changes.
- Run `scripts/ci-swift-check.sh debug`.
- Run `scripts/package-macos.sh debug` because the preview app imports `ServiceManagement`.
- When touching fallback compilation, manually verify direct `swiftc` compilation with `Sources/RightClickProAppPreview/*.swift` and `-framework ServiceManagement`.
- Manual smoke test: open the settings overview, toggle login-at-startup on/off, and confirm System Settings > General > Login Items reflects the change or shows the expected approval state.

### 7. Wrong vs Correct

Wrong:
```swift
Toggle("登录时启动", isOn: $config.launchAtLogin)
```

Correct:
```swift
Toggle(
    "",
    isOn: Binding(
        get: { viewModel.launchAtLoginToggleIsOn },
        set: { viewModel.setLaunchAtLoginEnabled($0) }
    )
)
```
