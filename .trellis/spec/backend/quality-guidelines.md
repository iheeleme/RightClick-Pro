# Quality Guidelines

> Code quality standards for backend development.

---

## Overview

RightTool quality checks center on SwiftPM compilation/tests, Finder extension packaging validation, and source-backed contracts. The project currently has no lint tool beyond Swift compiler checks and `git diff --check`.

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

- Shared behavior belongs in `RightToolCore`.
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

#### 3. Contracts

- `.dynamic` is the default `DeveloperEntrypoint.targetMode` for new and built-in developer entries.
- `.dynamic` target resolution:
  - `.selection` with a selected item -> first selected item.
  - `.container` -> `context.targetDirectory`, even if Finder reports stale selected items.
  - `.toolbar` with a selected item -> first selected item; otherwise `context.targetDirectory`.
- The Finder extension must keep passing the raw `FinderContext` through XPC; it must not resolve developer target URLs itself.
- `ActionRunner` owns target resolution so validation and operation logging use the same final URL.
- `ConfigurationBootstrapper` may repair built-in Terminal / VS Code / Cursor entries from old `.currentDirectory` defaults to `.dynamic` only when ID, title, and bundle identifier still match the built-in entry.

#### 4. Validation & Error Matrix

- Dynamic mode with no selected items -> fall back to `targetDirectory`.
- Dynamic container invocation with non-empty `selectedItems` -> use `targetDirectory`.
- Resolved target outside authorized monitored/common directories -> existing `AuthorizedPathValidator` failure.
- Existing user-customized developer entrypoint -> do not force target mode migration unless it still matches a built-in entry exactly.
- Unknown future enum raw value in stored JSON -> config decode fails until a migration is added; add Codable compatibility tests if introducing such migration.

#### 5. Good/Base/Bad Cases

- Good: selecting `~/Code/App` and choosing "在 Cursor 打开" opens Cursor with `~/Code/App`.
- Good: right-clicking blank space in `~/Code` and choosing the same entry opens Cursor with `~/Code`.
- Good: Finder toolbar action opens the selected item when Finder has an active selection, otherwise the current directory.
- Base: existing custom entry with `.selectedItemDirectory` keeps that explicit behavior.
- Bad: Finder Sync rewrites `.container` requests into selected-item paths before sending XPC.
- Bad: changing `.currentDirectory` semantics to mean dynamic, breaking explicit old configurations.

#### 6. Tests Required

- Unit-test `ActionRunner` dynamic target resolution for selection, container, no-selection fallback, and toolbar fallback.
- Unit-test bootstrap repair for built-in developer entries previously saved with `.currentDirectory`.
- Run:
  ```bash
  git diff --check
  swift test --filter ActionRunnerTests
  swift test --filter ConfigurationBootstrapperTests
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
  ```
- Finder extension bootstrap before monitored-directory registration:
  ```swift
  _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
  FIFinderSyncController.default().directoryURLs = Set(urls)
  ```
- Local preview PlugInKit registration order:
  ```bash
  pluginkit -a "$appex_path"
  pluginkit -e use -i "$FINDER_EXTENSION_BUNDLE_IDENTIFIER"
  ```
- Optional Xcode archive inputs:
  ```text
  RIGHTTOOL_XCODE_PROJECT=<path-to-xcodeproj>
  RIGHTTOOL_XCODE_SCHEME=<scheme-name>
  RIGHTTOOL_EXPORT_OPTIONS_PLIST=<optional-export-options-plist>
  ```
- Preview bundle identifiers and entitlements:
  ```text
  BUNDLE_IDENTIFIER=com.righttool.app
  XPC_BUNDLE_IDENTIFIER=com.righttool.app.ActionRunner
  FINDER_EXTENSION_BUNDLE_IDENTIFIER=com.righttool.app.FinderExtension
  APP_GROUP_IDENTIFIER=group.com.righttool.app
  CODE_SIGN_IDENTITY=-
  ```
- Preview app and Finder extension entitlements include app sandbox, App Group, user-selected read/write, and app-scope bookmarks.
- Preview ActionRunner XPC entitlements include App Group but intentionally omit app sandbox for local smoke tests against auto-injected Desktop/Documents/Downloads/Code paths. Runtime authorization must still validate all file mutations against configured monitored/common directories.

#### 3. Contracts

- GitHub workflow must use explicit macOS runner labels, not `macos-latest`, to avoid packaging drift when GitHub changes aliases.
- The default packaging path is SwiftPM preview bundling while no complete Xcode project exists.
- The SwiftPM preview bundle must still include `Contents/PlugIns/RightToolFinderExtension.appex`.
- The preview bundle must place `RightToolActionRunner.xpc` in `Contents/XPCServices/` and also inside `RightToolFinderExtension.appex/Contents/XPCServices/` so `NSXPCConnection(serviceName:)` can resolve the service from the main app and the Finder extension process.
- The preview Finder Sync `.appex` must be a Mach-O `EXECUTE` binary linked with `_NSExtensionMain`; a Swift dylib inside an `.appex` is not a valid Finder Sync extension bundle for PlugInKit discovery.
- The preview `.appex` Info.plist must contain `NSExtensionPointIdentifier=com.apple.FinderSync`.
- Finder Sync extension startup must not assume the menu-bar app launched first. It must run `ConfigurationBootstrapper.bootstrap(paths:)` before loading config and assigning `FIFinderSyncController.default().directoryURLs`.
- Default injected Desktop/Downloads/Documents/Code bookmarks must use the real user home directory, not the sandbox container home returned by `FileManager.homeDirectoryForCurrentUser` inside sandboxed app/extension processes.
- Bootstrap must self-heal existing bookmark paths under the sandbox process home by remapping them to the real user home while preserving bookmark IDs, display names, bookmark data, and timestamps.
- Bootstrap must also repair older existing configs that are missing an available default directory. Append the missing default bookmark, monitored/common directory IDs, and generated directory actions while preserving unrelated custom actions, templates, developer entries, and user ordering as much as possible.
- Finder Sync menu leaf items must not rely on `representedObject` for action payloads after Finder copies menu items. Use a stable `tag` or another Finder-preserved primitive to map selected menu items back to pending actions.
- The ActionRunner must resolve directory bookmarks and hold security-scoped access during request execution before creating the authorized-path validator.
- The preview app, XPC service, Finder extension, and their embedded `libRightToolCore.dylib` copies must be signed before zipping. Ad-hoc signing is acceptable for local test artifacts; public distribution still requires Developer ID signing and notarization.
- The packaging script must validate the preview bundle before upload so CI cannot publish an artifact that lacks a discoverable Finder Sync extension.
- For local preview smoke tests, the packaging script should explicitly register the just-built `.appex` path with `pluginkit -a` before applying `pluginkit -e use`; enabling by identifier alone only affects already-discovered extension records and may miss reinstalls.
- When both `RIGHTTOOL_XCODE_PROJECT` and `RIGHTTOOL_XCODE_SCHEME` are configured, packaging must use `xcodebuild archive`.
- If only one Xcode variable is configured, packaging must fail instead of silently falling back to SwiftPM preview output.
- Artifacts are written to `dist/*.zip`.
- The current default artifacts are non-notarized test builds. Developer ID signing/notarization requires a separate secrets/keychain flow.

#### 4. Validation & Error Matrix

- Unsupported configuration argument -> exit 64.
- Only one of `RIGHTTOOL_XCODE_PROJECT` / `RIGHTTOOL_XCODE_SCHEME` is set -> exit 64.
- `RIGHTTOOL_XCODE_PROJECT` path is missing -> exit 66.
- No Xcode variables are set -> build SwiftPM preview bundle.
- Preview Finder Sync binary is not `EXECUTE` -> exit 65.
- Preview Finder Sync extension point is not `com.apple.FinderSync` -> exit 65.
- Finder extension starts before config/bookmark files exist -> bootstrap creates defaults before assigning `directoryURLs`.
- Existing bookmark path starts with the sandbox process home -> remap to the same relative path under the real user home.
- Existing bookmark path merely shares a similar prefix with the sandbox process home -> leave unchanged.
- Existing config/bookmark files omit an available default directory such as `~/Code` -> append that directory to bookmarks, `monitoredDirectoryIDs`, `commonDirectoryIDs`, and missing generated directory actions.
- Preview bundle is missing app or extension-local `RightToolActionRunner.xpc` -> packaging fails before zip upload.
- Preview XPC service has app sandbox entitlement -> local smoke tests against auto-injected protected folders may fail.
- Preview deep code-sign verification fails -> packaging fails before zip upload.
- `pluginkit` unavailable on the runner -> skip registration/enablement without failing packaging.
- `pluginkit -a` or `pluginkit -e use` fails during local preview enablement -> do not fail packaging; the bundle validation remains the hard gate.
- No `dist/*.zip` output in GitHub Actions -> artifact upload must fail.

#### 5. Good/Base/Bad Cases

- Good: tag `v1.2.3` produces `RightTool-1.2.3-<arch>-preview.zip` containing `RightToolFinderExtension.appex` as an `_NSExtensionMain` executable, or an exported Xcode archive artifact.
- Good: Finder starts the extension before the app has opened; the extension bootstraps config/bookmarks and assigns real-home Desktop/Downloads/Documents/Code URLs to `directoryURLs`.
- Good: an older install has Desktop/Downloads/Documents only and `~/Code` exists; bootstrap appends the `code` bookmark, monitors it, and adds `open-directory-code`, `move-to-code`, and `copy-to-code`.
- Good: rebuilding/reinstalling a local preview registers the new `RightToolFinderExtension.appex` path, then enables `com.righttool.app.FinderExtension`.
- Base: manual workflow dispatch with no Xcode env vars produces a SwiftPM preview bundle with App, app-local XPC service, extension-local XPC service, Finder extension, and shared core dylib.
- Bad: bootstrap writes `~/Library/Containers/com.righttool.app/Data/Desktop` as a monitored directory, so the Finder menu never appears on the user's real Desktop.
- Bad: the packaging script only runs `pluginkit -e use -i com.righttool.app.FinderExtension`; after reinstall, PlugInKit may still know only an old or missing physical extension path.
- Bad: `RIGHTTOOL_XCODE_PROJECT` set without `RIGHTTOOL_XCODE_SCHEME` silently falls back to preview bundling.
- Bad: preview bundle contains `Contents/PlugIns/RightToolFinderExtension.appex` but the appex executable is a `DYLIB`.

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
  codesign --verify --deep --strict --verbose=2 dist/staging/RightTool.app
  otool -hv dist/staging/RightTool.app/Contents/PlugIns/RightToolFinderExtension.appex/Contents/MacOS/RightToolFinderExtension
  test -x dist/staging/RightTool.app/Contents/XPCServices/RightToolActionRunner.xpc/Contents/MacOS/RightToolActionRunner
  test -x dist/staging/RightTool.app/Contents/PlugIns/RightToolFinderExtension.appex/Contents/XPCServices/RightToolActionRunner.xpc/Contents/MacOS/RightToolActionRunner
  codesign -d --entitlements :- dist/staging/RightTool.app/Contents/PlugIns/RightToolFinderExtension.appex/Contents/XPCServices/RightToolActionRunner.xpc
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
RIGHTTOOL_XCODE_PROJECT=RightTool.xcodeproj scripts/package-macos.sh release
```

Correct:
```bash
RIGHTTOOL_XCODE_PROJECT=RightTool.xcodeproj \
RIGHTTOOL_XCODE_SCHEME=RightTool \
scripts/package-macos.sh release
```

Wrong:
```text
RightToolFinderExtension.appex/Contents/MacOS/RightToolFinderExtension: Mach-O ... dynamically linked shared library
```

Correct:
```text
RightToolFinderExtension.appex/Contents/MacOS/RightToolFinderExtension: Mach-O ... executable
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
pluginkit -e use -i "$FINDER_EXTENSION_BUNDLE_IDENTIFIER"
```
as the only local reinstall step.

Correct:
```bash
pluginkit -a "$appex_path"
pluginkit -e use -i "$FINDER_EXTENSION_BUNDLE_IDENTIFIER"
```
so the physical `.appex` path is registered before enablement.

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
  <string>group.com.righttool.app</string>
</array>
```
for the preview ActionRunner XPC entitlement file, with path authorization enforced in `ActionRunner`.

### Scenario: Finder Menu Icon Presentation

#### 1. Scope / Trigger

- Trigger: changes to `Sources/RightToolCore/MenuBuilder.swift`, `Sources/RightToolFinderExtension/FinderSyncController.swift`, `DeveloperEntrypoint`, `FileTemplate`, directory actions, or Finder menu presentation.
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
          for action: RightToolAction,
          config: RightToolConfig,
          bookmarks: DirectoryBookmarkCatalog = DirectoryBookmarkCatalog()
      ) -> MenuIconDescriptor
  }
  ```
- `MenuBuilder.buildMenu` must accept bookmarks so directory actions can resolve path icons:
  ```swift
  buildMenu(config: RightToolConfig, context: FinderContext, bookmarks: DirectoryBookmarkCatalog)
  ```

#### 3. Contracts

- `.openInApp` actions must use `.appBundleIdentifier(entrypoint.bundleIdentifier)` when the entrypoint exists.
- `.createFile` actions must use `.fileExtension(template.defaultFileName.pathExtension)` when the template has an extension.
- Directory actions must use `.filePath(bookmark.path)` when the bookmark exists, otherwise `.folder`.
- Finder extension must render descriptors with `NSWorkspace.shared.icon(for:)`, `NSWorkspace.shared.icon(forFile:)`, or `NSImage(systemSymbolName:)`.
- Core must not import AppKit; it only emits semantic descriptors.
- Finder extension menus must not wrap submenu groups in a visible branded container such as `"RightTool"`; root actions and functional group submenus should be added directly to the returned `NSMenu`.
- When both root actions and functional group submenus exist, do not insert a Finder Sync separator between those two blocks; Finder can render that separator as abnormal whitespace. Add root actions and functional group rows directly and compactly. When no actions are visible, return `nil` instead of an empty menu.
- Visible group names must describe the function, such as `"前往常用目录"`, `"新建文件"`, `"开发者工具"`, or `"文件操作"`, and settings previews should use matching labels.
- Any enabled action with `placement == .rootMenu` must remain in `MenuPresentation.rootItems`, even when other actions from the same `MenuGroup` are shown in functional group submenus. Presentation fixes must not silently rewrite user placement choices.

#### 4. Validation & Error Matrix

- Missing developer entrypoint -> fallback to `.systemSymbol("app")`.
- Missing template -> fallback to `.systemSymbol("doc.badge.plus")`.
- Missing bookmark -> fallback to `.folder`.
- Unknown file extension -> render the system `.data` type icon.
- Missing installed app for bundle identifier -> render the generic application icon.
- Finder menu contains a visible `"RightTool"` submenu container -> presentation bug; show functional group submenus directly.
- No visible actions for the current Finder invocation -> return `nil` so Finder does not show an empty extension menu.
- Settings placement copy says `"RightTool 子菜单"` -> copy drift; use `"功能分组菜单"` or another non-branded functional label.
- A visible root item and submenu items from the same `MenuGroup` coexist -> keep the root item in `rootItems`, keep submenu items in `groupedSubmenuItems`, and render the root/group rows compactly without a separator-caused gap.

#### 5. Good/Base/Bad Cases

- Good: Cursor action shows Cursor's installed app icon in the Finder menu.
- Good: `Note.md` template shows the system Markdown/document type icon.
- Good: Finder context menu shows `"新建文件"` and `"开发者工具"` group submenus directly, without an intermediate `"RightTool"` submenu.
- Good: `"新建Markdown"` can stay as a root item while other create-file actions remain under `"新建文件"`; the root section and functional groups are rendered next to each other without abnormal whitespace.
- Base: a custom shell command shows a terminal symbol.
- Bad: Finder menu item hard-codes `"terminal"` for every `.openInApp` action.
- Bad: Finder extension rebuilds icon semantics independently from `MenuIconResolver`.
- Bad: Finder menu shows a top-level `"RightTool"` submenu that only contains functional groups.
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
let rightToolMenu = NSMenu(title: "RightTool")
let container = NSMenuItem(title: "RightTool", action: nil, keyEquivalent: "")
container.submenu = rightToolMenu
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
