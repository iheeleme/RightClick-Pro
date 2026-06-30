# SwiftUI State and Binding Guidelines

This project does not use React hooks. Treat this file as the SwiftUI equivalent: local view state, bindings, sheet triggers, and lifecycle callbacks.

## Local View State

Use `@State` for UI-only state that does not need to persist:

- Selected filters: `ActionManagementFilter`, `DeveloperEntrypointFilter`.
- Preview context: `ActionPreviewContext`.
- Grouping/sorting modes for action management.
- Sheet drafts: `TemplateDraft?`, `DeveloperEntrypointDraft?`.
- Hover/presentation flags in compact controls.

Reference files: `Sources/RightClickProAppPreview/SettingsRootViews.swift`, section view files, and `EditorSheetViews.swift`.

## Shared State

Use `@ObservedObject var viewModel: SettingsViewModel` in child views. The app root owns the model as `@StateObject`.

- `RightClickProAppPreview` creates `@StateObject private var viewModel = SettingsViewModel.bootstrap()`.
- Section views observe the same model so config edits, status messages, and recent operations stay in sync.
- Child views call `SettingsViewModel` commands instead of mutating persisted state independently.

## Bindings

Use explicit `Binding(get:set:)` when a UI control edits a model item inside an array:

```swift
Toggle("", isOn: Binding(
    get: { action.isEnabled },
    set: { viewModel.setActionEnabled($0, actionID: action.id) }
))
```

This pattern keeps array lookup and validation in `SettingsViewModel`.

## Sheet Triggers

- Use optional draft state for edit sheets.
- Use integer request counters (`templateAddRequest`, `developerEntrypointAddRequest`) when a header button outside the list should open a sheet in the list view.
- Draft save closures call `upsertTemplate` or `upsertDeveloperEntrypoint`; they do not write files.

## Lifecycle Callbacks

- Use `onChange` for local UI request signals only.
- Use `reloadRecentOperations()` for operation-log refreshes, not repeated direct reads inside view bodies.
- Avoid expensive filesystem reads in `body`; derive display data from `@Published` model values.
