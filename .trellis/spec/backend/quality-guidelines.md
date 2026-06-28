# Quality Guidelines

> Code quality standards for backend development.

---

## Overview

RightClick Pro quality checks center on SwiftPM compilation/tests, Finder extension packaging validation, and source-backed contracts. The project currently has no lint tool beyond Swift compiler checks and `git diff --check`.

---

## Forbidden Patterns

- Finder extension performing file mutations directly. Route all mutations through XPC to `ActionRunner`.
- Finder menu leaf items relying on `representedObject` for action payloads. Finder copies menu items and may drop it; use stable `tag` values.
- Default monitored directories derived from the sandbox container home.
- Packaging with `macos-latest` runner labels. Use explicit runner labels from `.github/workflows/package-macos.yml`.
- Adding a new action kind without updating Core execution, menu presentation, settings display/editing, and tests.
- Direct storage writes from SwiftUI child views.

---

## Required Patterns

- Shared behavior belongs in `RightClickProCore`.
- File mutations must validate authorized paths before touching disk.
- Storage writes must use `JSONFileStore` or `JSONLineOperationLog`.
- Finder extension startup must bootstrap config before assigning `FIFinderSyncController.default().directoryURLs`.
- Menu icon semantics must come from `MenuIconResolver` in Core and be rendered at the UI/process boundary.
- Test doubles should use existing in-memory/recording types where possible.

---

## Testing Requirements

- Run `scripts/ci-swift-check.sh debug` for Swift changes.
- Run `scripts/package-macos.sh debug` for App/Finder extension/XPC/packaging changes.
- Run targeted tests for changed Core behavior, for example:
  ```bash
  swift test --filter MenuBuilderTests
  swift test --filter ActionRunnerTests
  swift test --filter ConfigurationBootstrapperTests
  ```
- Run `bash -n scripts/ci-swift-check.sh scripts/package-macos.sh` after shell script edits.
- Run `ruby -e 'require "yaml"; YAML.load_file(".github/workflows/package-macos.yml")'` after workflow edits.

---

## Code Review Checklist

- Does the change preserve process boundaries: Finder extension renders, XPC transports, ActionRunner mutates?
- Are new Codable fields backward compatible with existing JSON where practical?
- Are path and bookmark changes tested with temporary directories?
- Does settings UI mutate through `SettingsViewModel` commands?
- Does packaging still produce a discoverable Finder Sync `.appex` and both ActionRunner XPC placements?

### Scenario: Global Finder Scope and Full Disk Access Runtime

#### 1. Scope / Trigger

- Trigger: changes to `RightClickProConfig`, `FinderSyncScope`, `FinderSyncController`, `ActionRunner`, directory bookmarks, or file-operation permission handling.
- This is a cross-layer contract because config JSON, Finder Sync menu visibility, XPC action execution, settings UI copy, and operation logs must describe the same authorization model.

#### 2. Signatures

- Persisted config v2:
  ```swift
  RightClickProConfig(schemaVersion: 2, shortcutDirectoryIDs: ["desktop", "downloads"])
  ```
- Finder Sync scope:
  ```swift
  FinderSyncScope.syncRoots() == [URL(fileURLWithPath: "/")]
  ```
- Runtime failure copy:
  ```swift
  FullDiskAccessAdvisor.userFacingMessage(for: error)
  ```
- Runtime permission probe:
  ```swift
  SystemMaintenanceRequest(task: .checkFullDiskAccess)
  SystemMaintenanceResult(hasFullDiskAccess: Bool?)
  ```

#### 3. Contracts

- `shortcutDirectoryIDs` is only a shortcut-target list for directory menu actions.
- `monitoredDirectoryIDs` is legacy decode input only and must not be encoded in new config JSON.
- v1 `commonDirectoryIDs` migrates to v2 `shortcutDirectoryIDs`; v1 `monitoredDirectoryIDs` is discarded.
- Finder menus are globally visible once config is loaded; individual action visibility still depends on `ActionVisibility` and invocation shape.
- File actions attempt real file operations and let macOS permission results determine success or failure.
- Permission-like failures must include Full Disk Access guidance.
- Settings overview Full Disk Access status must be probed through ActionRunner XPC, because the SwiftUI app process is sandboxed while `ActionRunner.xpc` is the process that owns file actions and command execution.
- `FullDiskAccessAdvisor.checkRepresentativeAccess()` must resolve protected probe paths under the real login user home, not the sandbox container home that `FileManager.homeDirectoryForCurrentUser` may report.
- Overview should hide the Full Disk Access setup banner once `SystemMaintenanceResult.hasFullDiskAccess == true`; show the banner only for unchecked/checking, missing permission, or XPC-unavailable states.

#### 4. Validation & Error Matrix

- Old config has `commonDirectoryIDs` -> decode into `shortcutDirectoryIDs`.
- Old config has `monitoredDirectoryIDs` only -> do not use it for menu scope or runtime authorization.
- File operation fails with `EPERM`, `EACCES`, or Cocoa no-permission errors -> append Full Disk Access guidance.
- Finder context outside shortcut directories -> still build a menu when actions match the invocation.
- ActionRunner permission probe returns `hasFullDiskAccess == true` -> overview treats permission as ready and hides the authorization prompt.
- ActionRunner permission probe returns `hasFullDiskAccess == false` -> overview shows a warning prompt with the System Settings shortcut.
- ActionRunner XPC probe fails or omits `hasFullDiskAccess` -> overview shows an error/unavailable state instead of claiming authorization is missing.

#### 5. Good/Base/Bad Cases

- Good: right-clicking `/System` still shows eligible menu items; execution may fail with Full Disk Access guidance.
- Good: new installs default to Desktop and Downloads shortcuts only.
- Good: after the user grants Full Disk Access and reactivates the app, SettingsViewModel probes ActionRunner XPC and the overview no longer shows the authorization prompt.
- Base: existing custom bookmark entries stay in `bookmarks.json` during bootstrap.
- Bad: adding a new check that hides Finder menus outside `shortcutDirectoryIDs`.
- Bad: reintroducing `AuthorizedPathValidator` or any configured-directory allowlist as the file-action boundary.
- Bad: probing Full Disk Access directly from the sandboxed SwiftUI app and showing a stale missing-permission prompt after ActionRunner is already authorized.

#### 6. Tests Required

- Codable migration: v1 `commonDirectoryIDs` -> v2 `shortcutDirectoryIDs`; old keys omitted on encode.
- Finder scope: `FinderSyncScope.syncRoots()` returns `/`.
- ActionRunner: file actions succeed in temporary directories even when `shortcutDirectoryIDs` is empty.
- Bootstrap: default bookmarks exclude Documents and Code for new installs while preserving existing bookmarks.
- SystemMaintenanceService: `.checkFullDiskAccess` returns true and false `hasFullDiskAccess` values without invoking shell commands.
- Packaging smoke: installed app launches, ActionRunner XPC is available on demand, and overview hides the Full Disk Access banner when the XPC probe reports authorized.

#### 7. Wrong vs Correct

Wrong:
```swift
let validator = AuthorizedPathValidator(authorizedDirectories: shortcutURLs)
try validator.validate(request.context.targetDirectory)
```

Correct:
```swift
let result = try fileService.createFile(template: template, in: request.context.targetDirectory)
```

Wrong:
```swift
if FullDiskAccessAdvisor.checkRepresentativeAccess() {
    fullDiskAccessStatusMessage = "已授权"
}
```
inside the sandboxed settings app.

Correct:
```swift
actionRunnerClient.performMaintenance(SystemMaintenanceRequest(task: .checkFullDiskAccess)) { result in
    // Render SystemMaintenanceResult.hasFullDiskAccess from ActionRunner.xpc.
}
```

### Scenario: XPC-Owned Command Template Runs

#### 1. Scope / Trigger

- Trigger: changes to `.runCommand` actions, `PendingCommandRunRequest`, `RightClickProActionRunnerXPCProtocol`, `CommandRunService`, command output windows, command environment variables, or command operation logging.
- This is a cross-process execution contract because Finder queues intent, the main app displays output, and `ActionRunner.xpc` owns the `Process`.

#### 2. Signatures

- XPC protocol:
  ```swift
  startCommandRun(requestData:reply:)
  commandRunStatus(requestData:reply:)
  stopCommandRun(requestData:reply:)
  ```
- Shared snapshot:
  ```swift
  CommandRunSnapshot(
      id: request.id,
      actionID: request.actionID,
      status: .running,
      outputChunks: [CommandRunOutputChunk(stream: .stdout, text: "...")]
  )
  ```
- Storage:
  ```text
  command-runs/<run-id>.json
  ```

#### 3. Contracts

- Finder extension may still queue `PendingCommandRunRequest` and wake the main app, but it must not run shell commands.
- Main app command windows start/stop commands through XPC and poll shared snapshots for realtime output.
- `ActionRunner.xpc` owns `/bin/zsh`, stdout/stderr pipes, timeout, stop/kill escalation, and final operation logging.
- Sensitive environment variables are loaded through `CommandSecretStoring`; they must not be written to snapshots or config JSON.
- Snapshot output chunks may include `.system`, `.stdout`, and `.stderr`; UI can render `combinedOutput`.

#### 4. Validation & Error Matrix

- Missing action/template -> `.error` snapshot and failure operation log.
- Working directory unreadable -> `.error` snapshot with Full Disk Access guidance.
- Timeout -> append timeout system chunk, terminate process, final status `.timedOut`.
- User stop -> append stop system chunk, terminate process, final status `.stopped`.
- XPC unavailable from UI -> command window shows an error and refreshes operation history once.

#### 5. Good/Base/Bad Cases

- Good: a quick command writes stdout to `command-runs/<id>.json` and logs success with exit code/duration.
- Good: stop from the command window asks XPC to stop the process and the final snapshot becomes `.stopped`.
- Base: old pending command payloads without scoped bookmarks still decode.
- Bad: `CommandRunViewModel` creates `Process()` directly in the main app.
- Bad: Finder extension sends scoped bookmark data for command execution.

#### 6. Tests Required

- Unit-test `CommandRunService` success path with snapshot output and success operation log.
- Unit-test `CommandRunService.stop(runID:)` with final `.stopped` status.
- Codable regression for `PendingCommandRunRequest` legacy scoped-bookmark fields.
- Direct typecheck or package check for App, Finder extension, XPC service, and Core after protocol changes.

#### 7. Wrong vs Correct

Wrong:
```swift
let process = Process()
try process.run()
```
inside `CommandRunViewModel`.

Correct:
```swift
actionRunnerClient.startCommandRun(request) { result in
    // Render CommandRunSnapshot from ActionRunner.xpc.
}
```

### Scenario: Finder Command Template Authorization

#### 1. Scope / Trigger

- Trigger: changes to command template execution from Finder menus, pending command run storage, directory authorization, sandbox entitlements, or security-scoped bookmark handling.
- This is a cross-process authorization contract because Finder extension, App Group JSON, and the menu-bar app all touch the same command run request.

#### 2. Signatures

- Finder extension queue:
  ```swift
  PendingCommandRunRequest(actionID: request.actionID, context: request.context)
  ```
- Pending request JSON:
  ```json
  {
    "id": "...",
    "actionID": "run-command",
    "context": { "targetDirectory": "/Users/me/Code", "selectedItems": [] },
    "createdAt": 1782518400
  }
  ```
- Main app authorization gate:
  ```swift
  try ensureReadableWorkingDirectory(directory, bookmarks: bookmarks)
  ```

#### 3. Contracts

- Finder extension may queue only the command intent: action ID plus `FinderContext`.
- Finder extension must not create `.withSecurityScope` bookmark data for command execution and pass it through `PendingCommandRunRequest`.
- Main app must use `DirectoryBookmarkCatalog.bookmarkDataBase64` that it previously saved, or ask the user through `NSOpenPanel` and then save the resulting app-scoped bookmark.
- `securityScopedBookmarks` on `PendingCommandRunRequest` is legacy decode compatibility only; production command execution must not depend on it.
- Selecting an authorized parent directory is valid when it contains the requested working directory, and the bookmark should be persisted to the matching configured directory.

#### 4. Validation & Error Matrix

- Working directory outside monitored/common directories -> `CommandTemplateError.unauthorizedWorkingDirectory`.
- Working directory inside configured directories but unreadable -> main app prompts with `NSOpenPanel`.
- User cancels the authorization panel -> `CommandTemplateError.inaccessibleWorkingDirectory`.
- User selects a directory that does not contain the working directory -> reject and return `inaccessibleWorkingDirectory`.
- Bookmark data save fails after access succeeds -> command may continue, but output should include a save failure message.

#### 5. Good/Base/Bad Cases

- Good: Finder queues a `runCommand` request for `~/Code/Project`; the main app resolves saved `~/Code` bookmark, starts scoped access, and runs the command without extra TCC prompts.
- Good: saved bookmark is missing; the main app prompts once, user selects `~/Code`, bookmark data is saved to the existing `code` bookmark, and later runs reuse it.
- Base: old pending JSON contains `securityScopedBookmarks`; decoding still succeeds, but command execution ignores that field.
- Bad: Finder extension creates scoped bookmark data for selected paths and the main app resolves it, which can trigger repeated macOS "access data from other apps" prompts.

#### 6. Tests Required

- Codable regression: `PendingCommandRunRequest` decodes legacy payloads without `securityScopedBookmarks`.
- Codable compatibility: old payloads containing `securityScopedBookmarks` still round-trip while the runtime ignores the field.
- Manual smoke: run a command template from Finder in a protected configured directory and verify only the main app directory authorization panel appears when saved bookmark data is missing.
- Packaging smoke: run `scripts/package-macos.sh debug` and verify the installed Finder extension is the newly registered `.appex`.

#### 7. Wrong vs Correct

Wrong:
```swift
PendingCommandRunRequest(
    actionID: request.actionID,
    context: request.context,
    securityScopedBookmarks: securityScopedBookmarks(for: request.context)
)
```

Correct:
```swift
PendingCommandRunRequest(
    actionID: request.actionID,
    context: request.context
)
```

### Scenario: Developer Entrypoint Dynamic Target

#### 1. Scope / Trigger

- Trigger: changes to `DeveloperTargetMode`, `FinderContext`, `.openInApp` handling, `ConfigurationBootstrapper`, developer entrypoint settings, or Finder menu invocation mapping.
- This is a cross-layer contract because Finder Sync captures invocation shape, XPC transports `FinderContext`, Core resolves the target URL, and the settings app persists the chosen mode.

#### 2. Signatures

- Persisted target mode:
  ```swift
  public enum DeveloperTargetMode: String, Codable, Equatable {
      case dynamic
      case currentDirectory
      case selectedItem
      case selectedItemDirectory
  }
  ```
- Finder request context:
  ```swift
  FinderContext(
      invocation: .selection | .container | .toolbar,
      targetDirectory: URL,
      selectedItems: [URL]
  )
  ```
- Runtime resolver:
  ```swift
  developerTargetURL(for entrypoint: DeveloperEntrypoint, context: FinderContext) -> URL
  ```
- App opener planner:
  ```swift
  DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: targetURL, appURL: appURL)
  ```

#### 3. Contracts

- `.dynamic` is the default `DeveloperEntrypoint.targetMode` for new and built-in developer entries.
- `.dynamic` target resolution:
  - `.selection` with a selected item -> first selected item.
  - `.container` -> `context.targetDirectory`, even if Finder reports stale selected items.
  - `.toolbar` with a selected item -> first selected item; otherwise `context.targetDirectory`.
- The Finder extension must keep passing the raw `FinderContext` through XPC; it must not resolve developer target URLs itself.
- `ActionRunner` owns target resolution so validation and operation logging use the same final URL.
- `ConfigurationBootstrapper` may repair built-in Terminal / VS Code / Cursor entries from old `.currentDirectory` defaults to `.dynamic` only when ID, title, and bundle identifier still match the built-in entry.
- Workspace-oriented developer apps should prefer a source-backed CLI opener when available, for example Codex `codex app <workspace>` or VS Code-family `code <workspace>`.
- CLI opener candidates must be existence-checked with `FileManager.isExecutableFile` before invocation; missing candidates fall back to `NSWorkspace.open`.
- When the resolved dynamic target is a file and the selected app is opened through a workspace CLI, pass the file's parent directory as the workspace.
- Unknown apps must keep the previous `NSWorkspace.open([targetURL], withApplicationAt:)` behavior.

#### 4. Validation & Error Matrix

- Dynamic mode with no selected items -> fall back to `targetDirectory`.
- Dynamic container invocation with non-empty `selectedItems` -> use `targetDirectory`.
- Resolved target outside authorized monitored/common directories -> existing `AuthorizedPathValidator` failure.
- Existing user-customized developer entrypoint -> do not force target mode migration unless it still matches a built-in entry exactly.
- Recognized developer app with missing bundled/global CLI -> fall back to `NSWorkspace.open` instead of failing.
- CLI `Process.run()` failure -> return `AppOpeningError.cannotOpen(executableURL.path)`.
- Unknown future enum raw value in stored JSON -> config decode fails until a migration is added; add Codable compatibility tests if introducing such migration.

#### 5. Good/Base/Bad Cases

- Good: selecting `~/Code/App` and choosing "在 Cursor 打开" opens Cursor with `~/Code/App`.
- Good: right-clicking blank space in `~/Code` and choosing the same entry opens Cursor with `~/Code`.
- Good: Finder toolbar action opens the selected item when Finder has an active selection, otherwise the current directory.
- Good: selecting `~/Code/App` and choosing "在 Codex 打开" invokes the app-bundled Codex CLI with `app ~/Code/App`.
- Good: selecting `~/Code/App/README.md` and choosing a workspace CLI app opens `~/Code/App` as the workspace.
- Base: existing custom entry with `.selectedItemDirectory` keeps that explicit behavior.
- Base: a recognized app whose CLI helper is absent still opens through macOS Launch Services.
- Bad: Finder Sync rewrites `.container` requests into selected-item paths before sending XPC.
- Bad: changing `.currentDirectory` semantics to mean dynamic, breaking explicit old configurations.
- Bad: invoking a hard-coded CLI path without checking that it exists and is executable.

#### 6. Tests Required

- Unit-test `ActionRunner` dynamic target resolution for selection, container, no-selection fallback, and toolbar fallback.
- Unit-test bootstrap repair for built-in developer entries previously saved with `.currentDirectory`.
- Unit-test `DeveloperAppOpenPlanner` for Codex, VS Code-family, JetBrains, documented editor CLIs, file-to-parent workspace conversion, and unknown-app fallback.
- Run:
  ```bash
  git diff --check
  swift test --filter ActionRunnerTests
  swift test --filter ConfigurationBootstrapperTests
  swift test --filter AppOpeningTests
  scripts/package-macos.sh debug
  scripts/ci-swift-check.sh debug
  ```
- If SwiftPM manifest loading is broken locally, run an equivalent direct `swiftc`/built-module smoke for dynamic resolution and record the SwiftPM failure separately.

#### 7. Wrong vs Correct

Wrong:
```swift
case .currentDirectory:
    return context.selectedItems.first ?? context.targetDirectory
```

Correct:
```swift
case .dynamic:
    switch context.invocation {
    case .selection, .toolbar:
        return context.selectedItems.first ?? context.targetDirectory
    case .container:
        return context.targetDirectory
    }
case .currentDirectory:
    return context.targetDirectory
```

### Scenario: macOS GitHub Actions Packaging

#### 1. Scope / Trigger

- Trigger: any change to `.github/workflows/package-macos.yml`, `scripts/ci-swift-check.sh`, `scripts/package-macos.sh`, `Package.swift`, or macOS packaging targets.
- This is an infrastructure contract because packaging depends on GitHub runner labels, Swift/Xcode toolchains, artifact actions, and optional signing/export environment variables.

#### 2. Signatures

- CI check command:
  ```bash
  scripts/ci-swift-check.sh <release|debug>
  ```
- Packaging command:
  ```bash
  scripts/package-macos.sh <release|debug>
  RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh <release|debug>
  RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
  ```
- Finder extension bootstrap before monitored-directory registration:
  ```swift
  _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
  FIFinderSyncController.default().directoryURLs = Set(FinderSyncScope.syncRoots(for: urls))
  ```
- Opt-in local preview PlugInKit registration order:
  ```bash
  RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
  pluginkit -a "$appex_path"
  pluginkit -e use -i "$FINDER_EXTENSION_BUNDLE_IDENTIFIER"
  ```
- Runtime Finder menu repair path:
  ```swift
  RightClickProActionRunnerXPCClient().performMaintenance(
      SystemMaintenanceRequest(
          task: .repairFinderContextMenu,
          finderExtensionPath: bundledAppexPath
      )
  )
  ```
- Optional Xcode archive inputs:
  ```text
  RIGHTCLICKPRO_XCODE_PROJECT=<path-to-xcodeproj>
  RIGHTCLICKPRO_XCODE_SCHEME=<scheme-name>
  RIGHTCLICKPRO_EXPORT_OPTIONS_PLIST=<optional-export-options-plist>
  ```
- Preview bundle identifiers and entitlements:
  ```text
  APP_NAME=RightClick Pro
  BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro
  XPC_BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro.ActionRunner
  FINDER_EXTENSION_BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro.FinderExtension
  APP_GROUP_IDENTIFIER=group.com.iheeleme.rightclickpro
  CODE_SIGN_IDENTITY=-
  ```
- Manual workflow input:
  ```yaml
  package_dmg: true | false
  ```
- Preview app and Finder extension entitlements include app sandbox, App Group, user-selected read/write, and app-scope bookmarks.
- Preview ActionRunner XPC entitlements include App Group but intentionally omit app sandbox for local smoke tests against auto-injected Desktop/Documents/Downloads/Code paths. Runtime authorization must still validate all file mutations against configured monitored/common directories.

#### 3. Contracts

- GitHub workflow must use explicit macOS runner labels, not `macos-latest`, to avoid packaging drift when GitHub changes aliases.
- The default packaging path is SwiftPM preview bundling while no complete Xcode project exists.
- The SwiftPM preview app bundle's user-facing name is `RightClick Pro.app`; Swift target/module/type names must use the `RightClickPro*` naming family.
- The SwiftPM preview bundle must still include `Contents/PlugIns/RightClickProFinderExtension.appex`.
- The preview bundle must place `RightClickProActionRunner.xpc` in `Contents/XPCServices/` and also inside `RightClickProFinderExtension.appex/Contents/XPCServices/` so `NSXPCConnection(serviceName:)` can resolve the service from the main app and the Finder extension process.
- The preview Finder Sync `.appex` must be a Mach-O `EXECUTE` binary linked with `_NSExtensionMain`; a Swift dylib inside an `.appex` is not a valid Finder Sync extension bundle for PlugInKit discovery.
- The preview `.appex` Info.plist must contain `NSExtensionPointIdentifier=com.apple.FinderSync`.
- Finder Sync extension startup must not assume the menu-bar app launched first. It must run `ConfigurationBootstrapper.bootstrap(paths:)` before loading config and assigning `FIFinderSyncController.default().directoryURLs`.
- Finder Sync must register parent sync roots rather than exact configured directory paths where possible, then filter each `FinderContext` back to the configured monitored directories before returning menus. Exact roots such as `~/Code` can make Finder sidebar favorites render with the extension app icon.
- Finder Sync extension cold-start must keep `menu(for:)` fast. It should set a fast monitored-directory fallback during `init`, serve menus from cached config/bookmark snapshots, cache rendered icons, and refresh/repair config in the background.
- Default injected Desktop/Downloads/Documents/Code bookmarks must use the real user home directory, not the sandbox container home returned by `FileManager.homeDirectoryForCurrentUser` inside sandboxed app/extension processes.
- Bootstrap must self-heal existing bookmark paths under the sandbox process home by remapping them to the real user home while preserving bookmark IDs, display names, bookmark data, and timestamps.
- Bootstrap must also repair older existing configs that are missing an available default directory. Append the missing default bookmark, monitored/common directory IDs, and generated directory actions while preserving unrelated custom actions, templates, developer entries, and user ordering as much as possible.
- Finder Sync menu leaf items must not rely on `representedObject` for action payloads after Finder copies menu items. Use a stable `tag` or another Finder-preserved primitive to map selected menu items back to pending actions.
- The ActionRunner must resolve directory bookmarks and hold security-scoped access during request execution before creating the authorized-path validator.
- The preview app, XPC service, Finder extension, and their embedded `libRightClickProCore.dylib` copies must be signed before zipping. Ad-hoc signing is acceptable for local test artifacts; public distribution still requires Developer ID signing and notarization.
- The packaging script must validate the preview bundle before upload so CI cannot publish an artifact that lacks a discoverable Finder Sync extension.
- The packaging script must not register the staging `.appex` with PlugInKit by default. Build artifacts often live under source directories such as `~/Code`, and registering those paths can make Finder display the app icon against source-directory sidebar items.
- For local preview Finder Sync smoke tests only, `RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1` may explicitly register the just-built `.appex` path with `pluginkit -a` before applying `pluginkit -e use`; enabling by identifier alone only affects already-discovered extension records and may miss reinstalls.
- After a DMG install, the settings app must not assume build-time PlugInKit registration exists on the user's machine. On launch it should ask the embedded ActionRunner XPC service to register the bundled `.appex`, request enablement, and reload Finder once for the current packaged extension signature.
- The packaged extension setup signature must include filesystem resource identity for the physical `.appex`, `Info.plist`, extension executable, and host app bundle. Path, version, and modification time alone are not enough because same-version reinstall/overwrite can keep those values unchanged while Finder/PlugInKit still needs a fresh preload.
- Finder restart/repair controls should also run through the ActionRunner XPC maintenance path because the menu-bar app is sandboxed; direct `killall Finder` or `pluginkit` from the app can fail.
- When both `RIGHTCLICKPRO_XCODE_PROJECT` and `RIGHTCLICKPRO_XCODE_SCHEME` are configured, packaging must use `xcodebuild archive`.
- If only one Xcode variable is configured, packaging must fail instead of silently falling back to SwiftPM preview output.
- Zip artifacts are written to `dist/RightClick Pro-<version>-<arch>-preview.zip`.
- `RIGHTCLICKPRO_PACKAGE_DMG=1` creates an additional compressed read-only `UDZO` artifact at `dist/RightClick Pro-<version>-<arch>-preview.dmg`.
- DMG contents must include `RightClick Pro.app`, an `/Applications` alias, and `README.txt`.
- `README.txt` must cover drag-to-Applications installation, the non-Developer-ID/non-notarized warning, Finder Extension enablement, and the `killall Finder` fallback.
- `RIGHTCLICKPRO_PACKAGE_DMG=1` is supported only on the SwiftPM preview bundle path until the Xcode archive/export path has a concrete `.app` output contract.
- The current default artifacts are non-notarized test builds. Developer ID signing/notarization requires a separate secrets/keychain flow.

#### 4. Validation & Error Matrix

- Unsupported configuration argument -> exit 64.
- Unsupported `RIGHTCLICKPRO_PACKAGE_DMG` value -> exit 64.
- Unsupported `RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION` value -> exit 64.
- Only one of `RIGHTCLICKPRO_XCODE_PROJECT` / `RIGHTCLICKPRO_XCODE_SCHEME` is set -> exit 64.
- `RIGHTCLICKPRO_PACKAGE_DMG=1` with a configured Xcode archive path -> exit 64 before archive.
- `RIGHTCLICKPRO_XCODE_PROJECT` path is missing -> exit 66.
- No Xcode variables are set -> build SwiftPM preview bundle.
- `RIGHTCLICKPRO_PACKAGE_DMG=1` and `hdiutil` is unavailable -> exit 69.
- Preview Finder Sync binary is not `EXECUTE` -> exit 65.
- Preview Finder Sync extension point is not `com.apple.FinderSync` -> exit 65.
- Finder extension starts before config/bookmark files exist -> bootstrap creates defaults before assigning `directoryURLs`.
- Finder extension starts after a long idle period -> first `menu(for:)` must not synchronously run full bootstrap or repeated JSON/icon lookup work.
- Finder sidebar favorite for a configured directory such as `~/Code` shows the RightClick Pro app icon -> bug; do not register the exact favorite path as the Finder Sync root.
- Finder right-click outside configured monitored directories but inside a parent sync root -> return `nil` from `menu(for:)`.
- Existing bookmark path starts with the sandbox process home -> remap to the same relative path under the real user home.
- Existing bookmark path merely shares a similar prefix with the sandbox process home -> leave unchanged.
- Existing config/bookmark files omit an available default directory such as `~/Code` -> append that directory to bookmarks, `monitoredDirectoryIDs`, `commonDirectoryIDs`, and missing generated directory actions.
- Preview bundle is missing app or extension-local `RightClickProActionRunner.xpc` -> packaging fails before zip upload.
- Preview XPC service has app sandbox entitlement -> local smoke tests against auto-injected protected folders may fail.
- Preview deep code-sign verification fails -> packaging fails before zip upload.
- `pluginkit` unavailable during `RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1` -> skip registration/enablement without failing packaging.
- `pluginkit -a` or `pluginkit -e use` fails during opt-in local preview enablement -> do not fail packaging; the bundle validation remains the hard gate.
- Runtime maintenance cannot find bundled `RightClickProFinderExtension.appex` -> show a user-facing error that the app should be installed from the DMG into Applications.
- Runtime maintenance XPC is unavailable -> show a user-facing error and keep the manual System Settings fallback available.
- Direct sandboxed app `killall Finder` fails -> bug; restart should be delegated to the unsandboxed ActionRunner XPC maintenance service.
- Overview setup banner is visible after successful runtime setup -> UI noise; hide it until automatic setup fails or manual attention is needed.
- No `dist/*.zip` output in GitHub Actions -> artifact upload must fail.
- DMG smoke mount lacks `RightClick Pro.app`, `Applications`, or `README.txt` -> exit 65.

#### 5. Good/Base/Bad Cases

- Good: tag `v1.2.3` produces `RightClick Pro-1.2.3-<arch>-preview.zip` containing `RightClickProFinderExtension.appex` as an `_NSExtensionMain` executable, or an exported Xcode archive artifact.
- Good: `RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh debug` produces zip plus `RightClick Pro-<version>-<arch>-preview.dmg`, then mounts the DMG and verifies the app, Applications alias, and README.
- Good: Finder starts the extension before the app has opened; the extension bootstraps config/bookmarks and assigns parent sync roots derived from real-home Desktop/Downloads/Documents/Code URLs to `directoryURLs`.
- Good: `~/Code` is configured as a monitored directory; Finder Sync registers `~` as the sync root and returns menus only when the context is inside `~/Code`.
- Good: after Finder has unloaded the extension, the next right-click cold-start sets fallback monitored directories immediately, returns menu items from cached config once loaded, and refreshes repaired config asynchronously.
- Good: an older install has Desktop/Downloads/Documents only and `~/Code` exists; bootstrap appends the `code` bookmark, monitors it, and adds `open-directory-code`, `move-to-code`, and `copy-to-code`.
- Good: normal local packaging validates `RightClickProFinderExtension.appex` but does not register the `dist/staging` or `tmp` path into the user's PlugInKit database.
- Good: opt-in `RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1` local smoke packaging registers the new `RightClickProFinderExtension.appex` path, then enables `com.iheeleme.rightclickpro.FinderExtension`.
- Good: first app launch after dragging from the DMG registers `Contents/PlugIns/RightClickProFinderExtension.appex` through ActionRunner XPC and reloads Finder once, so PlugInKit can discover the right physical extension path on that machine without a slow first right-click wait.
- Good: reinstalling the same app version at the same `/Applications` path changes the packaged extension resource identity and triggers one fresh Finder preload instead of reusing the previous setup marker.
- Good: clicking "重启 Finder" asks ActionRunner XPC to register/enable the extension and then restart Finder; if `killall Finder` fails, the service tries an AppleScript fallback and reports diagnostics.
- Base: manual workflow dispatch with no Xcode env vars produces a SwiftPM preview bundle with App, app-local XPC service, extension-local XPC service, Finder extension, and shared core dylib.
- Base: manual workflow dispatch with `package_dmg=false` uploads only zip output in a clean runner workspace.
- Bad: bootstrap writes `~/Library/Containers/com.iheeleme.rightclickpro/Data/Desktop` as a monitored directory, so the Finder menu never appears on the user's real Desktop.
- Bad: `FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/Users/me/Code")])` for a visible sidebar favorite, causing Finder to render the folder with the extension app icon.
- Bad: `FinderSyncController.menu(for:)` reads `config.json`, reads `bookmarks.json`, resolves all app icons, and runs bootstrap synchronously on every right-click.
- Bad: every normal `scripts/package-macos.sh` run registers `dist/staging/.../RightClickProFinderExtension.appex`, causing Finder/PlugInKit state to point at source-tree build artifacts and display RightClick Pro icons beside directories such as `~/Code`.
- Bad: the packaging script only runs `pluginkit -e use -i com.iheeleme.rightclickpro.FinderExtension`; after reinstall, PlugInKit may still know only an old or missing physical extension path.
- Bad: the sandboxed menu-bar app directly runs `/usr/bin/killall Finder`, then reports failure even though the embedded unsandboxed XPC service could perform the repair.
- Bad: every normal launch restarts Finder even when the same bundled extension was already repaired successfully.
- Bad: workflow upload glob includes `.dmg` but the runner workspace contains a stale DMG from an unrelated previous build.
- Bad: `RIGHTCLICKPRO_XCODE_PROJECT` set without `RIGHTCLICKPRO_XCODE_SCHEME` silently falls back to preview bundling.
- Bad: preview bundle contains `Contents/PlugIns/RightClickProFinderExtension.appex` but the appex executable is a `DYLIB`.

#### 6. Tests Required

- Run shell syntax checks:
  ```bash
  bash -n scripts/ci-swift-check.sh scripts/package-macos.sh
  ```
- Run bootstrap regression tests:
  ```bash
  swift test --filter ConfigurationBootstrapperTests
  ```
- Parse the workflow YAML:
  ```bash
  ruby -e 'require "yaml"; YAML.load_file(".github/workflows/package-macos.yml")'
  ```
- Run preview package validation:
  ```bash
  scripts/package-macos.sh debug
  RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh debug
  codesign --verify --deep --strict --verbose=2 "dist/staging/RightClick Pro.app"
  otool -hv "dist/staging/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex/Contents/MacOS/RightClickProFinderExtension"
  test -x "dist/staging/RightClick Pro.app/Contents/XPCServices/RightClickProActionRunner.xpc/Contents/MacOS/RightClickProActionRunner"
  test -x "dist/staging/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex/Contents/XPCServices/RightClickProActionRunner.xpc/Contents/MacOS/RightClickProActionRunner"
  codesign -d --entitlements :- "dist/staging/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex/Contents/XPCServices/RightClickProActionRunner.xpc"
  hdiutil imageinfo "dist/RightClick Pro-<version>-<arch>-preview.dmg"
  ```
- Run Swift type checks or `swift test` where the local toolchain allows it.
- For future Xcode project work, run at least one GitHub Actions workflow dispatch before calling packaging complete.

#### 7. Wrong vs Correct

Wrong:
```yaml
runs-on: macos-latest
```

Correct:
```yaml
runs-on: macos-26
```

Wrong:
```bash
RIGHTCLICKPRO_XCODE_PROJECT=RightClickPro.xcodeproj scripts/package-macos.sh release
```

Correct:
```bash
RIGHTCLICKPRO_XCODE_PROJECT=RightClickPro.xcodeproj \
RIGHTCLICKPRO_XCODE_SCHEME=RightClickPro \
scripts/package-macos.sh release
```

Wrong:
```bash
RIGHTCLICKPRO_PACKAGE_DMG=true scripts/package-macos.sh debug
```

Correct:
```bash
RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh debug
```

Wrong:
```text
RightClickProFinderExtension.appex/Contents/MacOS/RightClickProFinderExtension: Mach-O ... dynamically linked shared library
```

Correct:
```text
RightClickProFinderExtension.appex/Contents/MacOS/RightClickProFinderExtension: Mach-O ... executable
```

Wrong:
```swift
let home = fileManager.homeDirectoryForCurrentUser
```
when building default monitored-directory bookmarks from a sandboxed app or extension process.

Correct:
```swift
let home = realUserHomeDirectory
```
where the real home bypasses sandbox container redirection and existing container paths are sanitized on bootstrap.

Wrong:
```bash
scripts/package-macos.sh debug
pluginkit -a "$PWD/dist/staging/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex"
```
as the default packaging behavior, because it persists build-artifact paths in the user's PlugInKit database.

Correct:
```bash
scripts/package-macos.sh debug
```
for normal packaging, with installed-app runtime repair handling `/Applications/RightClick Pro.app`.

Wrong:
```bash
pluginkit -e use -i "$FINDER_EXTENSION_BUNDLE_IDENTIFIER"
```
as the only opt-in local smoke registration step.

Correct:
```bash
RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
pluginkit -a "$appex_path"
pluginkit -e use -i "$FINDER_EXTENSION_BUNDLE_IDENTIFIER"
```
so the physical `.appex` path is registered before enablement when explicitly requested.

Wrong:
```swift
menuItem.representedObject = PendingMenuAction(actionID: item.actionID, context: context)
```

Correct:
```swift
menuItem.tag = tag
pendingMenuActions[tag] = PendingMenuAction(actionID: item.actionID, context: context)
```

Wrong:
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```
inside the preview ActionRunner XPC entitlement file.

Correct:
```xml
<key>com.apple.security.application-groups</key>
<array>
  <string>group.com.iheeleme.rightclickpro</string>
</array>
```
for the preview ActionRunner XPC entitlement file, with path authorization enforced in `ActionRunner`.

### Scenario: Finder Menu Icon Presentation

#### 1. Scope / Trigger

- Trigger: changes to `Sources/RightClickProCore/MenuBuilder.swift`, `Sources/RightClickProFinderExtension/FinderSyncController.swift`, `DeveloperEntrypoint`, `FileTemplate`, directory actions, or Finder menu presentation.
- This is a cross-layer contract because Core decides icon semantics while the Finder extension renders them as AppKit `NSImage` values.

#### 2. Signatures

- Menu presentation carries a semantic icon descriptor:
  ```swift
  public enum MenuIconDescriptor: Equatable {
      case systemSymbol(String)
      case appBundleIdentifier(String)
      case filePath(String)
      case fileExtension(String)
      case folder
  }
  ```
- Action-to-icon mapping lives in Core:
  ```swift
  public enum MenuIconResolver {
      public static func icon(
          for action: RightClickProAction,
          config: RightClickProConfig,
          bookmarks: DirectoryBookmarkCatalog = DirectoryBookmarkCatalog()
      ) -> MenuIconDescriptor
  }
  ```
- `MenuBuilder.buildMenu` must accept bookmarks so directory actions can resolve path icons:
  ```swift
  buildMenu(config: RightClickProConfig, context: FinderContext, bookmarks: DirectoryBookmarkCatalog)
  ```

#### 3. Contracts

- `.openInApp` actions must use `.appBundleIdentifier(entrypoint.bundleIdentifier)` when the entrypoint exists.
- `.createFile` actions must use `.fileExtension(template.defaultFileName.pathExtension)` when the template has an extension.
- Directory actions must use `.filePath(bookmark.path)` when the bookmark exists, otherwise `.folder`.
- Finder extension must render descriptors with `NSWorkspace.shared.icon(for:)`, `NSWorkspace.shared.icon(forFile:)`, or `NSImage(systemSymbolName:)`.
- Core must not import AppKit; it only emits semantic descriptors.
- Finder extension menus must not wrap submenu groups in a visible branded container such as `"RightClick Pro"`; root actions and functional group submenus should be added directly to the returned `NSMenu`.
- When both root actions and functional group submenus exist, do not insert a Finder Sync separator between those two blocks; Finder can render that separator as abnormal whitespace. Add root actions and functional group rows directly and compactly. When no actions are visible, return `nil` instead of an empty menu.
- Visible group names must describe the function, such as `"前往常用目录"`, `"新建文件"`, `"开发者工具"`, or `"文件操作"`, and settings previews should use matching labels.
- Any enabled action with `placement == .rootMenu` must remain in `MenuPresentation.rootItems`, even when other actions from the same `MenuGroup` are shown in functional group submenus. Presentation fixes must not silently rewrite user placement choices.

#### 4. Validation & Error Matrix

- Missing developer entrypoint -> fallback to `.systemSymbol("app")`.
- Missing template -> fallback to `.systemSymbol("doc.badge.plus")`.
- Missing bookmark -> fallback to `.folder`.
- Unknown file extension -> render the system `.data` type icon.
- Missing installed app for bundle identifier -> render the generic application icon.
- Finder menu contains a visible `"RightClick Pro"` submenu container -> presentation bug; show functional group submenus directly.
- No visible actions for the current Finder invocation -> return `nil` so Finder does not show an empty extension menu.
- Settings placement copy says `"RightClick Pro 子菜单"` -> copy drift; use `"功能分组菜单"` or another non-branded functional label.
- A visible root item and submenu items from the same `MenuGroup` coexist -> keep the root item in `rootItems`, keep submenu items in `groupedSubmenuItems`, and render the root/group rows compactly without a separator-caused gap.

#### 5. Good/Base/Bad Cases

- Good: Cursor action shows Cursor's installed app icon in the Finder menu.
- Good: `Note.md` template shows the system Markdown/document type icon.
- Good: Finder context menu shows `"新建文件"` and `"开发者工具"` group submenus directly, without an intermediate `"RightClick Pro"` submenu.
- Good: `"新建Markdown"` can stay as a root item while other create-file actions remain under `"新建文件"`; the root section and functional groups are rendered next to each other without abnormal whitespace.
- Base: a custom shell command shows a terminal symbol.
- Bad: Finder menu item hard-codes `"terminal"` for every `.openInApp` action.
- Bad: Finder extension rebuilds icon semantics independently from `MenuIconResolver`.
- Bad: Finder menu shows a top-level `"RightClick Pro"` submenu that only contains functional groups.
- Bad: a display-layer workaround moves a user-selected root item into a submenu group.

#### 6. Tests Required

- Unit-test `MenuBuilder` icon descriptors for developer, template, and directory actions.
- Unit-test root/submenu coexistence with one root create-file action and one submenu create-file action from the same group.
- Run:
  ```bash
  git diff --check
  scripts/package-macos.sh debug
  scripts/ci-swift-check.sh debug
  ```
- Manually smoke-test the installed Finder menu when local packaging succeeds.

#### 7. Wrong vs Correct

Wrong:
```swift
MenuItemPresentation(id: action.id, title: action.title, actionID: action.id, group: action.group, order: action.order)
```

Correct:
```swift
MenuItemPresentation(
    id: action.id,
    title: action.title,
    actionID: action.id,
    group: action.group,
    order: action.order,
    icon: MenuIconResolver.icon(for: action, config: config, bookmarks: bookmarks)
)
```

Wrong:
```swift
let rightClickProMenu = NSMenu(title: "RightClick Pro")
let container = NSMenuItem(title: "RightClick Pro", action: nil, keyEquivalent: "")
container.submenu = rightClickProMenu
menu.addItem(container)
```

Correct:
```swift
for group in MenuGroup.allCases {
    let groupItem = NSMenuItem(title: title(for: group), action: nil, keyEquivalent: "")
    groupItem.submenu = submenu
    menu.addItem(groupItem)
}
return menu.items.isEmpty ? nil : menu
```
