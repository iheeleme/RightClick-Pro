# Component Guidelines

> How components are built in this project.

---

## Overview

<!--
Document your project's component conventions here.

Questions to answer:
- What component patterns do you use?
- How are props defined?
- How do you handle composition?
- What accessibility standards apply?
-->

(To be filled by the team)

---

## Component Structure

<!-- Standard structure of a component file -->

(To be filled by the team)

---

## Props Conventions

<!-- How props should be defined and typed -->

(To be filled by the team)

---

## Styling Patterns

<!-- How styles are applied (CSS modules, styled-components, Tailwind, etc.) -->

(To be filled by the team)

---

## Accessibility

<!-- A11y requirements and patterns -->

(To be filled by the team)

---

## Common Mistakes

<!-- Component-related mistakes your team has made -->

### Scenario: SwiftUI Settings Editing Surfaces

#### 1. Scope / Trigger

- Trigger: changes to `Sources/RightToolAppPreview/RightToolAppPreview.swift` or future SwiftUI settings screens that edit `RightToolConfig`.
- This is a frontend contract with persistence consequences because the settings UI writes JSON config that Finder Sync and ActionRunner later consume.

#### 2. Signatures

- Settings screens should mutate config through `SettingsViewModel` methods, not by scattering persistence writes through child views:
  ```swift
  func saveConfig()
  func setActionEnabled(_ isEnabled: Bool, actionID: String)
  func setActionPlacement(_ placement: ActionPlacement, actionID: String)
  func upsertTemplate(_ template: FileTemplate, replacing originalID: String?)
  func deleteTemplate(_ template: FileTemplate)
  func upsertDeveloperEntrypoint(_ entrypoint: DeveloperEntrypoint, replacing originalID: String?)
  func deleteDeveloperEntrypoint(_ entrypoint: DeveloperEntrypoint)
  ```

#### 3. Contracts

- Child views may hold local draft state for sheets/forms.
- Child views call ViewModel commands on save/delete/toggle.
- `saveConfig()` is the only operation that persists `RightToolConfig` to disk.
- Adding a `FileTemplate` must also create or update its matching `.createFile` action.
- Adding a `DeveloperEntrypoint` must also create or update its matching `.openInApp` action.
- Deleting a template or developer entrypoint must remove its associated action so Finder menus do not reference missing payloads.
- Promoting actions to `rootMenu` must enforce `RightToolConfig.maxRootMenuActions`.

#### 4. Validation & Error Matrix

- More than `maxRootMenuActions` enabled root actions -> block promotion or fail save with a visible status message.
- Empty template ID/title/default filename -> fail save with a visible status message.
- Duplicate template or developer entrypoint ID -> fail save with a visible status message.
- Empty developer title or bundle identifier -> fail save with a visible status message.
- Operation log read failure -> show an empty history state and visible error status.

#### 5. Good/Base/Bad Cases

- Good: user adds a Markdown template, saves, and a submenu create-file action appears in the config.
- Base: user toggles an existing action off, saves, and Finder no longer shows that action on the next menu open.
- Bad: user adds a template but no action references it, making the template unreachable from Finder.
- Bad: child views write `config.json` directly, bypassing central validation.

#### 6. Tests Required

- Run preview packaging after SwiftUI settings changes:
  ```bash
  scripts/package-macos.sh debug
  ```
- Run `git diff --check`.
- Run SwiftPM checks where the local toolchain can compile the manifest:
  ```bash
  scripts/ci-swift-check.sh debug
  ```
- Manually open the settings window and smoke-test toggles, add/edit/delete sheets, save feedback, and recent-operation reload.

#### 7. Wrong vs Correct

Wrong:
```swift
config.fileTemplates.append(template)
```

Correct:
```swift
viewModel.upsertTemplate(template, replacing: originalID)
```

Wrong:
```swift
Button("保存") {
    try? JSONFileStore<RightToolConfig>(url: url).save(config)
}
```

Correct:
```swift
Button("保存配置") {
    viewModel.saveConfig()
}
```

### Scenario: SwiftUI Settings Presentation Refactors

#### 1. Scope / Trigger

- Trigger: redesigning or refactoring `Sources/RightToolAppPreview/RightToolAppPreview.swift` presentation components, especially dashboards, tables, menu previews, and section navigation.

#### 2. Signatures

- Keep persistence mutations behind `SettingsViewModel` commands already listed in the settings editing surface contract.
- Presentation-only helpers may accept read-only model values:
  ```swift
  FinderMenuItem(title: action.title, systemImage: action.kind.rowIcon)
  Toggle("", isOn: Binding(
      get: { action.isEnabled },
      set: { viewModel.setActionEnabled($0, actionID: action.id) }
  ))
  ```

#### 3. Contracts

- Menu previews must be derived from `RightToolConfig`, `DirectoryBookmarkCatalog`, `FileTemplate`, `DeveloperEntrypoint`, or `OperationRecord` values.
- Do not make a preview imply that an edit/add/delete operation is available unless there is a matching `SettingsViewModel` command.
- Read-only visual affordances such as disabled toggles or static edit icons are acceptable only when they reflect current model state.

#### 4. Validation & Error Matrix

- Preview shows an action as enabled but `RightToolAction.isEnabled == false` -> bug; derive enabled state from the action.
- Toggle changes a template/developer entrypoint but bypasses `setActionEnabled` or upsert/delete commands -> persistence contract violation.
- Table displays an edit/delete control with no backing command -> either wire it to a ViewModel command or render it as static/read-only.

#### 5. Good/Base/Bad Cases

- Good: template enable switches locate the matching `.createFile` action and call `setActionEnabled`.
- Base: a directory table renders bookmark rows as active because directory editing is not yet exposed by the ViewModel.
- Bad: a Finder menu preview hard-codes "VS Code" even when `config.developerEntrypoints` does not contain that entry.

#### 6. Tests Required

- Run `swift build --target RightToolAppPreview`.
- Run `scripts/ci-swift-check.sh debug`.
- Run `scripts/package-macos.sh debug` after SwiftUI settings changes.
- Run `git diff --check`.

#### 7. Wrong vs Correct

Wrong:
```swift
FinderMenuItem(title: "VS Code", systemImage: "app")
```

Correct:
```swift
config.developerEntrypoints.map {
    FinderMenuItem(title: $0.title, systemImage: developerIcon(for: $0))
}
```

### Common Mistake: Duplicating Native macOS Window Controls

**Symptom**: The settings window shows two sets of red/yellow/green controls in the upper-left corner.

**Cause**: A custom design mockup included traffic-light dots, but the real SwiftUI `Window` already renders native macOS window controls.

**Fix**: Do not render decorative window-control dots inside `SettingsRootView`, `SettingsSidebar`, or other content views that live inside a real macOS window.

Wrong:
```swift
VStack {
    WindowControlDots()
    SettingsSidebarContent()
}
```

Correct:
```swift
VStack {
    SettingsSidebarContent()
}
```

### Common Mistake: Slow Sidebar Selection

**Symptom**: Custom sidebar rows feel delayed because selection changes after mouse release and expensive detail views start rebuilding at the same time.

**Cause**: Using a default SwiftUI `Button` for navigation rows in a dense macOS settings sidebar can defer the action until mouseUp.

**Fix**: For custom sidebar navigation in `RightToolAppPreview.swift`, use a full-row hit target and select on mouseDown with `DragGesture(minimumDistance: 0)`. Keep accessibility traits so the row is still announced as a button.

Wrong:
```swift
Button(action: onSelect) {
    SidebarRowContent()
}
.buttonStyle(.plain)
```

Correct:
```swift
SidebarRowContent()
    .contentShape(Rectangle())
    .gesture(
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onSelect() }
    )
    .accessibilityAddTraits(.isButton)
```
