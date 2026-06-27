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
- Rule controls that visually look clickable, such as menu rows or toggles in settings cards, must have backing state and update the visible table or preview they describe.
- Settings menu rows must render `MenuIconDescriptor` through `MenuIconView`; application actions use installed app icons, templates use file type icons, directories use path/folder icons, and unsupported cases fall back to semantic SF Symbols.
- Sorting controls must call `SettingsViewModel` commands that update `RightToolAction.order`, `fileTemplates`, `developerEntrypoints`, or bookmark order as appropriate; sorting UI must update the table and the Finder preview in the same interaction.
- Display-condition controls must mutate `RightToolAction.visibility` through `SettingsViewModel` and must prevent leaving an action with no visible invocation.
- Display-condition controls must show selected and unselected visibility states distinctly; do not rely only on native menu checkmarks for this editing surface.
- Action-management rows must expose the `ActionPlacement` choice as a visible table control, such as `"一级菜单"` / `"分组菜单"`, not only behind an unlabeled icon-only menu.
- Placement controls must keep the compact row label readable and must show the current placement with a selected state that is visually distinct from hover/highlight state.
- Finder menu previews for the action-management surface should render `MenuBuilder` output instead of flat action rows, so root items and functional group submenus match the real Finder extension.
- Preview layouts that show a long Finder menu next to a short submenu must top-align the menu boxes and avoid fixed oversized minimum heights that make a single item appear to have large blank space below it.
- Preview layouts must not insert an extra divider between root actions and functional group submenu rows when the real Finder extension renders those rows compactly.

#### 4. Validation & Error Matrix

- Preview shows an action as enabled but `RightToolAction.isEnabled == false` -> bug; derive enabled state from the action.
- Toggle changes a template/developer entrypoint but bypasses `setActionEnabled` or upsert/delete commands -> persistence contract violation.
- Table displays an edit/delete control with no backing command -> either wire it to a ViewModel command or render it as static/read-only.
- A grouping/sorting card renders chevrons or switches but does not change the action table -> wire it to local state and the table's filtered/sorted data pipeline.
- Developer, template, or directory rows hard-code SF Symbols instead of using `MenuIconResolver` / `MenuIconView` -> icons drift from the real Finder menu and app icons disappear.
- Table shows a drag handle or arrow controls but does not update persisted ordering -> bug; wire it to an explicit move command and normalize associated action orders.
- Visibility pills are rendered as inert labels -> bug when the surface claims display-condition editing; expose a menu or remove the edit affordance.
- Visibility selection relies only on a tiny native checkmark and gives no clear selected/unselected card state -> display polish bug.
- Preview shows root actions and group submenu rows as one flat action list -> bug; use `MenuBuilder` presentation and compact/top-aligned preview boxes.
- Placement switching is hidden behind an unlabeled icon-only control -> discoverability bug; use a labeled placement control in the action row.
- Placement row text truncates common labels such as `"分组菜单"` or selected state relies only on native blue hover highlight -> display polish bug.

#### 5. Good/Base/Bad Cases

- Good: template enable switches locate the matching `.createFile` action and call `setActionEnabled`.
- Good: action preview can show `"新建Markdown"` as a root item and `"新建文件"` as a submenu row at the same time, matching the user's placement choices.
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
    FinderMenuItem(title: $0.title, icon: .appBundleIdentifier($0.bundleIdentifier))
}
```

Wrong:
```swift
Image(systemName: "grip.vertical")
```
for a sortable row with no move or drag handler.

Correct:
```swift
SortStepControls(
    canMoveUp: index > 0,
    canMoveDown: index < rows.count - 1,
    onMoveUp: { viewModel.moveAction(actionID: action.id, visibleActionIDs: visibleIDs, offset: -1) },
    onMoveDown: { viewModel.moveAction(actionID: action.id, visibleActionIDs: visibleIDs, offset: 1) }
)
```

### Scenario: SwiftUI Settings Sheets and Icon Controls

#### 1. Scope / Trigger

- Trigger: changing add/edit sheets, row action buttons, sort controls, overflow menus, or other icon-only controls in `Sources/RightToolAppPreview/RightToolAppPreview.swift`.
- This is a frontend interaction contract because icon-only controls can otherwise look clickable while lacking hover, disabled, help, or accessibility feedback.

#### 2. Signatures

- Reuse these local presentation components for settings editing sheets and icon controls:
  ```swift
  EditorSheetHeader(title:subtitle:systemImage:tint:)
  EditorTextField(title:placeholder:helper:systemImage:text:)
  EditorTextArea(title:helper:text:)
  EditorSheetFooter(validationMessage:canSave:onCancel:onSave:)
  RowIconControlLabel(systemImage:tone:isDisabled:size:iconSize:cornerRadius:)
  RowIconButton(systemImage:accessibilityLabel:helpText:tone:isDisabled:action:)
  ```

#### 3. Contracts

- Add/edit sheets must show a semantic header icon, short subtitle, grouped input fields, and a persistent footer with cancel/save actions.
- Sheet save buttons must be disabled when required draft fields are empty; the footer must show the current validation message.
- Sheet save actions still call the existing `SettingsViewModel` upsert/delete/toggle commands through their parent view; sheets must not write config files directly.
- Icon-only buttons must use `RowIconControlLabel` or `RowIconButton` so hover, disabled, border, and help states stay consistent.
- If a control opens a menu, the label should still use `RowIconControlLabel`, and menu items should use `Label` with semantic SF Symbols.
- Destructive or hiding actions must use a destructive tone and a semantic icon such as `trash` or `eye.slash`; do not use `trash` for non-delete behavior.

#### 4. Validation & Error Matrix

- Required sheet draft field is empty -> keep Save disabled and show an inline footer warning.
- Icon-only button lacks `.help` or `.accessibilityLabel` -> accessibility regression.
- Disabled icon control still renders with active hover/accent state -> misleading affordance.
- Menu label uses a plain `Image` while row buttons use `RowIconControlLabel` -> inconsistent interaction feedback.
- A button icon implies delete but only disables/hides an item -> semantic mismatch.

#### 5. Good/Base/Bad Cases

- Good: a template editor sheet disables Save until ID, title, and default filename are present.
- Base: an overflow menu uses `RowIconControlLabel(systemImage: "ellipsis")` and `Label("删除", systemImage: "trash")` for destructive items.
- Bad: a sheet allows saving an empty title and relies only on later config validation.
- Bad: an action row uses a bare pencil image for a placement menu, making it look like a direct edit button.

#### 6. Tests Required

- Run:
  ```bash
  git diff --check
  scripts/package-macos.sh debug
  scripts/ci-swift-check.sh debug
  ```
- Manually smoke-test opening add/edit sheets, empty-field Save disabled states, cancel/default keyboard shortcuts, icon-button hover states, disabled states, and overflow menus.

#### 7. Wrong vs Correct

Wrong:
```swift
Button {
    viewModel.setActionEnabled(false, actionID: action.id)
} label: {
    Image(systemName: "trash")
}
```

Correct:
```swift
RowIconButton(
    systemImage: "eye.slash",
    accessibilityLabel: "禁用 \(action.title)",
    helpText: "从右键菜单中隐藏",
    tone: .destructive,
    isDisabled: !action.isEnabled
) {
    viewModel.setActionEnabled(false, actionID: action.id)
}
```

Wrong:
```swift
Button("保存") {
    onSave(draft)
}
```

Correct:
```swift
EditorSheetFooter(
    validationMessage: validationMessage,
    canSave: validationMessage == nil,
    onCancel: onCancel
) {
    onSave(draft)
}
```

### Scenario: SwiftUI App Icon and Settings Brand Icon

#### 1. Scope / Trigger

- Trigger: changing the macOS app icon, `design/icon.png`, or the settings sidebar brand mark in `Sources/RightToolAppPreview/RightToolAppPreview.swift`.
- This is both a frontend and packaging contract because the settings UI reads the runtime PNG while the `.app` bundle uses the generated `.icns`.

#### 2. Signatures

- `scripts/package-macos.sh` exposes these environment overrides:
  ```bash
  APP_ICON_SOURCE="${APP_ICON_SOURCE:-design/icon.png}"
  APP_ICON_NAME="${APP_ICON_NAME:-RightToolIcon}"
  ```
- The app `Info.plist` must set:
  ```xml
  <key>CFBundleIconFile</key>
  <string>RightToolIcon</string>
  ```
- SwiftUI settings should load the same base asset through `RightToolIconAsset` and render it with `RightToolBrandIcon`.

#### 3. Contracts

- `design/icon.png` is the source of truth for the product icon.
- Packaging must copy it to `Contents/Resources/RightToolIcon.png` for the settings page.
- Packaging must generate `Contents/Resources/RightToolIcon.icns` with `sips` + `iconutil` for the app icon.
- Local development may fall back to the repository `design/icon.png`; packaged app rendering must not depend on repository paths.

#### 4. Validation & Error Matrix

- Missing `APP_ICON_SOURCE` -> packaging exits before producing an app bundle.
- Missing `sips` or `iconutil` -> packaging exits because the `.icns` cannot be generated.
- `CFBundleIconFile` does not match `APP_ICON_NAME` -> bundle validation fails.
- Packaged app lacks `RightToolIcon.png` -> settings page brand icon falls back to the system symbol and should be treated as a packaging bug.

#### 5. Good/Base/Bad Cases

- Good: update `design/icon.png`, run packaging, and both `RightToolIcon.png` and `RightToolIcon.icns` are regenerated in the bundle.
- Base: run the settings preview from the repository and the UI loads `design/icon.png` directly.
- Bad: add a separate copied icon under `Sources/` and let it drift from `design/icon.png`.
- Bad: set `CFBundleIconFile` without validating that the referenced `.icns` exists in `Contents/Resources`.

#### 6. Tests Required

- Run:
  ```bash
  git diff --check
  bash -n scripts/package-macos.sh
  scripts/package-macos.sh debug
  ```
- Verify:
  ```bash
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/staging/RightTool.app/Contents/Info.plist
  test -f dist/staging/RightTool.app/Contents/Resources/RightToolIcon.icns
  test -f dist/staging/RightTool.app/Contents/Resources/RightToolIcon.png
  ```
- Run `scripts/ci-swift-check.sh debug` when the local SwiftPM manifest toolchain is healthy.

#### 7. Wrong vs Correct

Wrong:
```swift
Image(systemName: "cursorarrow")
```

Correct:
```swift
RightToolBrandIcon(size: 44)
```

Wrong:
```bash
cp design/icon.png "$app_path/Contents/Resources/AppIcon.png"
```

Correct:
```bash
copy_app_icon_resources "$app_path/Contents/Resources"
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

**Fix**: For custom sidebar navigation in `RightToolAppPreview.swift`, use a full-row hit target and select on mouseDown with `DragGesture(minimumDistance: 0)`. Keep accessibility traits so the row is still announced as a button. If the detail view is heavy, split selection into `visualSelection` for immediate sidebar highlight and `renderedSection` for the delayed detail rebuild.

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

For heavy detail views:
```swift
visualSelection = section
DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
    renderedSection = section
    viewModel.selectedSection = section
}
```

### Common Mistake: Heavy Settings Detail Rendering

**Symptom**: The sidebar highlight responds quickly, but the right settings content still feels laggy while switching sections or scrolling.

**Cause**: Detail pages rebuild too much work at once: repeated menu preview rows use fresh `UUID` identities, `ViewThatFits` builds multiple complete layout branches, large panel shadows force expensive repainting, and table rows are placed in eager `VStack`s inside a scroll view.

**Fix**: Keep preview item identities stable, use `LazyVStack` for scroll-page and table rows, prefer one deterministic preview layout over nested `ViewThatFits`, and avoid large decorative shadows in repeated detail panels.

Wrong:
```swift
struct FinderMenuItem: Identifiable {
    let id = UUID()
    let title: String
}

ViewThatFits(in: .horizontal) {
    HorizontalPreview()
    VerticalPreview()
}
```

Correct:
```swift
struct FinderMenuItem: Identifiable {
    let id: String
    let title: String
}

LazyVStack(spacing: 0) {
    ForEach(items) { item in
        SettingsTableRow(item: item)
    }
}
```

### Common Mistake: Unbounded Settings Layouts Inside ScrollView

**Symptom**: A settings page looks correct in code but renders with columns squeezed, titles missing, or a right-side preview panel pushed outside the visible window.

**Cause**: A vertical `ScrollView` can give child content a loose width proposal. Combining that with `HStack`, `.frame(maxWidth: .infinity)`, and fixed-width trailing columns lets the primary table consume too much width or collapse its flexible title column.

**Fix**: Use `GeometryReader` at the page boundary to calculate a deterministic content width, then assign explicit widths to the main table and optional preview panel. Give the title/name column higher `layoutPriority`, and keep fixed trailing columns compact.

Wrong:
```swift
ScrollView {
    HStack {
        SettingsTable()
            .frame(maxWidth: .infinity)
        SettingsPreview()
            .frame(width: 292)
    }
}
```

Correct:
```swift
GeometryReader { proxy in
    let contentWidth = min(max(proxy.size.width - 56, 760), 1220)
    let previewWidth: CGFloat = contentWidth >= 1050 ? 286 : 0
    let tableWidth = contentWidth - previewWidth - (previewWidth > 0 ? 18 : 0)

    ScrollView {
        HStack(spacing: previewWidth > 0 ? 18 : 0) {
            SettingsTable()
                .frame(width: tableWidth)
            if previewWidth > 0 {
                SettingsPreview()
                    .frame(width: previewWidth)
            }
        }
        .frame(width: contentWidth + 56, alignment: .topLeading)
    }
}
```
