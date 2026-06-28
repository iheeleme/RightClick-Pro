# macOS Permissions and Finder Sync Notes

## Sources

- Apple Support: Full Disk Access user setting
  <https://support.apple.com/guide/mac-help/change-privacy-security-settings-on-mac-mchl211c911f/mac>
- Apple Developer Documentation: `FIFinderSyncController.directoryURLs`
  <https://developer.apple.com/documentation/findersync/fifindersynccontroller/directoryurls>
- Apple Developer Documentation: Accessing files from the macOS App Sandbox
  <https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox>

## Relevant Findings

- Full Disk Access is a user-controlled macOS privacy permission in System Settings. The app cannot silently enable it for itself.
- Finder Sync extensions still need a `directoryURLs` scope. Setting this to `/` is the clearest way to express a global Finder menu scope for this task.
- Full Disk Access and App Sandbox file access are separate layers. Full Disk Access can grant privacy access, but sandboxed processes still need their own file-access model. In this repo's current preview package, the main app and Finder extension are sandboxed while `ActionRunner.xpc` is packaged without app sandboxing, so privileged file operations and command execution should converge on `ActionRunner.xpc`.

## Repo Constraints Observed

- `FinderSyncController` currently derives `directoryURLs` from configured monitored directories and filters contexts back to those monitored directories before returning menu items.
- `ActionRunner` currently builds `AuthorizedPathValidator` from `monitoredDirectoryIDs + commonDirectoryIDs`, so runtime file actions are still tied to configured directories.
- Command templates currently run in the main app command window via `Process`, with realtime stdout/stderr handled directly in `CommandRunViewModel`.
- Existing config schema uses `monitoredDirectoryIDs` and `commonDirectoryIDs`. This task migrates to schema v2 with `shortcutDirectoryIDs`.
