# Directory Structure

The settings frontend currently lives in one large SwiftUI file. That is the existing shape, but new work should preserve clear sections and be ready for later extraction.

## Current File Layout

- `Sources/RightClickProAppPreview/RightClickProAppPreview.swift`
  - App entry and scene definitions.
  - `SettingsViewModel` and validation error type.
  - Window/sidebar/detail shell components.
  - Section views for overview, directories, actions, templates, developer entrypoints, and operation history.
  - Shared visual primitives such as `DesignPanel`, `StatusBadge`, `RowIconButton`, `FinderMenuPreview`, and editor sheet controls.

Reference symbols: `RightClickProAppPreview`, `SettingsViewModel`, `SettingsRootView`, `ActionListView`, `TemplateListView`, `DeveloperEntrypointListView`, `OperationHistoryView`.

## Organization Rules

- Keep stateful persistence commands in `SettingsViewModel`.
- Keep child views focused on layout, bindings, and local sheet/filter state.
- Keep Core data contracts in `RightClickProCore`; do not redefine action/template/bookmark structs in the app target.
- Keep AppKit-specific visual resolution in app/extension UI code, not in Core.
- When extracting files later, split by view family:
  - `SettingsViewModel.swift`
  - `SettingsTheme.swift`
  - `ActionManagementViews.swift`
  - `TemplateSettingsViews.swift`
  - `DeveloperSettingsViews.swift`
  - `FinderMenuPreviewViews.swift`

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
