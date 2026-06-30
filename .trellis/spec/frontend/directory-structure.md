# Directory Structure

The settings frontend is split across focused SwiftUI/AppKit files under `Sources/RightClickProAppPreview/`. Keep new work inside the existing file family that owns the behavior instead of growing the app entry file again.

## Current File Layout

- `Sources/RightClickProAppPreview/RightClickProAppPreview.swift`
  - App entry and scene definitions.
- `SettingsViewModel.swift`
  - `SettingsViewModel` and validation error type.
- `CommandRunWindow.swift`
  - Command run view model, AppKit window coordinator, and realtime output window.
- `SettingsRootViews.swift`
  - Window/sidebar/detail shell components.
  - Shared visual primitives such as `DesignPanel`, `StatusBadge`, `RowIconButton`, `FinderMenuPreview`, and editor sheet controls.
- `OverviewViews.swift`, `DirectorySettingsViews.swift`, `ActionManagementViews.swift`, `TemplateSettingsViews.swift`, `CommandTemplateSettingsViews.swift`, `DeveloperSettingsViews.swift`, `OperationHistoryViews.swift`
  - Section views for overview, directories, actions, templates, command templates, developer entrypoints, and operation history.
- `FinderMenuPreviewViews.swift`
  - Shared Finder menu preview types and menu icon rendering.
- `EditorSheetViews.swift`
  - Add/edit sheet shells and draft structs.
- `DisplayExtensions.swift`
  - UI labels, icons, tint helpers, date formatting, and enum display extensions.

Reference symbols: `RightClickProAppPreview`, `SettingsViewModel`, `SettingsRootView`, `ActionListView`, `TemplateListView`, `DeveloperEntrypointListView`, `OperationHistoryView`.

## Organization Rules

- Keep stateful persistence commands in `SettingsViewModel`.
- Keep child views focused on layout, bindings, and local sheet/filter state.
- Keep Core data contracts in `RightClickProCore`; do not redefine action/template/bookmark structs in the app target.
- Keep AppKit-specific visual resolution in app/extension UI code, not in Core.
- Add new setting screens as `<Domain>SettingsViews.swift` when they are screen-level.
- Put shared visual controls in `SettingsRootViews.swift`, shared menu preview controls in `FinderMenuPreviewViews.swift`, and sheet/draft controls in `EditorSheetViews.swift`.
- Put display-only enum extensions in `DisplayExtensions.swift`; do not hide persisted schema changes there.

## Naming Conventions

- Screen-level views end in `View`: `ActionListView`, `OperationHistoryView`.
- Reusable visual shells use descriptive nouns: `DesignPanel`, `PageToolbar`, `PreviewSection`.
- Table pieces are named by role: `ActionTableHeader`, `ActionEditorRow`, `TemplateTableRow`.
- Draft structs for sheets end in `Draft`: `TemplateDraft`, `DeveloperEntrypointDraft`.
- UI-only enums describe the editing surface: `ActionManagementFilter`, `ActionSortingMode`, `DeveloperEntrypointFilter`.

## Anti-Patterns

- Do not place persistence writes directly in table rows or sheets.
- Do not duplicate Core icon resolution in individual views; use `MenuIconResolver` plus `MenuIconView`.
- Do not add marketing-style landing sections to settings. This is a dense macOS tool surface.
- Do not create page-specific menu preview implementations when `PreviewSection` and `FinderMenuPreview` can represent the same thing.
