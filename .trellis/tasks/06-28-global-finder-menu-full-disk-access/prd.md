# Global Finder Menu and Full Disk Access Migration

## Goal

RightClick Pro should stop using user-selected directories as the product's menu and authorization boundary. Finder right-click menus should be globally available, file actions and command templates should rely on macOS Full Disk Access at execution time, and directory configuration should become only a list of shortcut targets.

## What I Already Know

- The current app treats configured directories as three concepts at once:
  - Finder menu effective scope.
  - Runtime file-operation authorization boundary.
  - Common directory shortcut targets.
- The user confirmed the new model:
  - Finder menu scope is global.
  - The global Finder Sync scope for this task is `/`.
  - No system-path blacklist is added.
  - Menus remain visible even when Full Disk Access is not granted.
  - Execution failures should provide clear Full Disk Access guidance.
  - Command templates also move to the Full Disk Access model.
  - Command execution should migrate from the main app process to `ActionRunner.xpc`.
  - Command windows must keep realtime output.
- Default shortcut targets for new installs should be only Desktop and Downloads.
- Existing user configs should not have bookmark entries deleted.

## Research References

- [`research/macos-permissions-and-finder-sync.md`](research/macos-permissions-and-finder-sync.md) — macOS Full Disk Access, Finder Sync `directoryURLs`, and App Sandbox implications for this repo.

## Requirements

### Finder Menu Scope

- Set Finder Sync effective scope to `/`.
- Remove configured-directory filtering from menu visibility.
- Keep all three Finder entry points globally available:
  - Container / blank-space context menu.
  - Selection context menu.
  - Toolbar menu.
- Continue filtering individual actions by Finder invocation context.
- Do not add special blacklists for `/System`, `/Library`, `/usr`, `/bin`, or similar paths. Let real execution results and macOS permissions determine success/failure.

### Full Disk Access UX

- Add a settings-page Full Disk Access guidance banner.
- Provide an action to open the relevant macOS System Settings privacy pane when possible.
- Provide a lightweight "check permission" flow:
  - Attempt a representative protected file-system access.
  - Show "likely granted" when access succeeds.
  - Show guidance when access fails.
- Treat permission checks as advisory only. Real action execution remains the source of truth.
- When an action fails due to file-system permission/access issues, return a user-facing message that clearly points to Full Disk Access.

### Runtime Authorization Model

- Stop using configured directories as the runtime authorization boundary.
- File operations should no longer validate paths against configured shortcut directories.
- File actions should attempt the requested operation and report permission/access failures clearly.
- Preserve normal file-operation safety behavior such as conflict handling and operation logging.

### Config Schema Migration

- Migrate config schema to v2.
- Remove `monitoredDirectoryIDs` from the new model.
- Replace `commonDirectoryIDs` with `shortcutDirectoryIDs`.
- Decode/migrate old v1 config as:
  - `commonDirectoryIDs` -> `shortcutDirectoryIDs`.
  - `monitoredDirectoryIDs` -> discarded.
- Do not delete existing `bookmarks.json` entries during migration.
- Existing actions that target directory bookmarks should keep working if their target directory ID exists in `shortcutDirectoryIDs` or bookmarks.
- Update tests and docs to use `shortcutDirectoryIDs`.

### Default Shortcut Targets

- For new installs, default bookmarks should include:
  - Desktop.
  - Downloads.
- For new installs, do not default-inject:
  - Documents.
  - Code.
- Existing installs should preserve current user bookmarks and actions.

### Command Templates

- Command templates are part of the same Full Disk Access model.
- Move command execution from the sandboxed main app command window to `ActionRunner.xpc`.
- Preserve realtime output in the command window.
- Support stopping/cancelling an in-flight command from the command window.
- Record command success/failure in operation history.
- Preserve current command features:
  - Working directory modes.
  - Timeout handling.
  - Environment variables.
  - Sensitive environment variables stored in Keychain.
  - Command interpolation variables.

### Realtime Command Output Bridge

- Introduce a command-run transport between the main app and `ActionRunner.xpc`.
- The transport should allow:
  - Start command run.
  - Read/observe stdout and stderr incrementally.
  - Read final status, duration, and exit code.
  - Stop command run.
- Recommended implementation direction:
  - `ActionRunner.xpc` owns the `Process`.
  - Command run state/output is written to an app-group/shared storage location.
  - The main app command window observes or polls the shared run state and renders realtime output.

## Acceptance Criteria

- [ ] Finder menus appear under the `/` Finder Sync scope instead of configured monitored directories.
- [ ] RightClick Pro no longer hides menus merely because the current Finder path is outside configured directories.
- [ ] `RightClickProConfig` schema v2 exposes `shortcutDirectoryIDs` and no longer exposes `monitoredDirectoryIDs` as product model.
- [ ] v1 config decoding migrates `commonDirectoryIDs` into `shortcutDirectoryIDs`.
- [ ] v1 `monitoredDirectoryIDs` does not affect v2 menu scope or authorization.
- [ ] New default config/bookmarks include Desktop and Downloads only.
- [ ] Existing bookmark entries are preserved during bootstrap/migration.
- [ ] File actions are no longer blocked by configured-directory validation.
- [ ] Permission/access failures produce Full Disk Access guidance.
- [ ] Settings UI includes Full Disk Access guidance, open-settings action, and lightweight permission check.
- [ ] Command templates execute through `ActionRunner.xpc`.
- [ ] Command window still shows realtime stdout/stderr.
- [ ] Command stop/cancel still works.
- [ ] Unit tests cover schema migration, default bookmark changes, menu scope changes, and authorization-model changes.
- [ ] Project checks pass.

## Out of Scope

- User-configurable Finder Sync scope.
- System path blacklist or denylist.
- Notarization, Developer ID signing, or production distribution changes beyond docs required by this behavior.
- Deleting or pruning existing user bookmarks during migration.

## Technical Notes

- Likely impacted files:
  - `Sources/RightClickProCore/ActionModels.swift`
  - `Sources/RightClickProCore/Authorization.swift`
  - `Sources/RightClickProCore/ActionRunner.swift`
  - `Sources/RightClickProCore/CommandTemplates.swift`
  - `Sources/RightClickProCore/FinderSyncScope.swift`
  - `Sources/RightClickProCore/XPCAdapter.swift`
  - `Sources/RightClickProCore/ConfigurationBootstrapper.swift`
  - `Sources/RightClickProFinderExtension/FinderSyncController.swift`
  - `Sources/RightClickProAppPreview/RightClickProAppPreview.swift`
  - `Sources/RightClickProActionRunnerService/main.swift`
  - `Tests/RightClickProCoreTests/*`
  - `docs/architecture.md`
  - `docs/github-actions-packaging.md`
- Current `FinderSyncScope` has tests asserting parent-root registration and monitored-directory filtering. These should be rewritten for `/` global scope.
- Current `ActionRunner` creates `AuthorizedPathValidator` from configured directories. This must be replaced or narrowed so shortcut directories are not treated as an authorization boundary.
- Current command execution uses `Process` in `CommandRunViewModel`; moving it to XPC likely requires new codable command-run request/status/output models and XPC adapter methods.

## Definition of Done

- Tests added/updated for changed behavior.
- Swift checks pass with the project test/check script.
- Docs explain the new Full Disk Access model and shortcut-directory semantics.
- Migration behavior is covered by tests and does not delete user bookmarks.
