# Quality Guidelines

> Code quality standards for backend development.

---

## Overview

<!--
Document your project's quality standards here.

Questions to answer:
- What patterns are forbidden?
- What linting rules do you enforce?
- What are your testing requirements?
- What code review standards apply?
-->

(To be filled by the team)

---

## Forbidden Patterns

<!-- Patterns that should never be used and why -->

(To be filled by the team)

---

## Required Patterns

<!-- Patterns that must always be used -->

(To be filled by the team)

---

## Testing Requirements

<!-- What level of testing is expected -->

(To be filled by the team)

---

## Code Review Checklist

<!-- What reviewers should check -->

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

#### 4. Validation & Error Matrix

- Missing developer entrypoint -> fallback to `.systemSymbol("app")`.
- Missing template -> fallback to `.systemSymbol("doc.badge.plus")`.
- Missing bookmark -> fallback to `.folder`.
- Unknown file extension -> render the system `.data` type icon.
- Missing installed app for bundle identifier -> render the generic application icon.

#### 5. Good/Base/Bad Cases

- Good: Cursor action shows Cursor's installed app icon in the Finder menu.
- Good: `Note.md` template shows the system Markdown/document type icon.
- Base: a custom shell command shows a terminal symbol.
- Bad: Finder menu item hard-codes `"terminal"` for every `.openInApp` action.
- Bad: Finder extension rebuilds icon semantics independently from `MenuIconResolver`.

#### 6. Tests Required

- Unit-test `MenuBuilder` icon descriptors for developer, template, and directory actions.
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
