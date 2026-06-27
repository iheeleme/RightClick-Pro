# Optimize Developer Entrypoint App Picker

## Goal

Improve the "开发者快捷入口" add flow so users add a local macOS application by selecting it, instead of manually typing the app's bundle identifier. The goal is to reduce configuration friction and prevent invalid bundle IDs while preserving existing Finder menu behavior.

## What I Already Know

- User explicitly wants the add flow to use local app selection, not manual text entry.
- Current settings UI is native SwiftUI/AppKit in `Sources/RightToolAppPreview/RightToolAppPreview.swift`.
- Current `DeveloperEntrypointDraft` stores `entrypointID`, `title`, `bundleIdentifier`, and `targetMode`.
- Current editor sheet asks users to type "Bundle Identifier" manually.
- Existing app icons are resolved from `MenuIconDescriptor.appBundleIdentifier` via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`.
- Existing data model stores `DeveloperEntrypoint.bundleIdentifier`; this can likely remain unchanged if the picker extracts the bundle identifier from the selected `.app`.
- Existing save path is `SettingsViewModel.upsertDeveloperEntrypoint`, which also syncs the associated `.openInApp` action.

## Assumptions (Temporary)

- The MVP should keep the persisted `DeveloperEntrypoint` schema unchanged.
- The picker should probably use `NSOpenPanel` filtered to `.app` bundles and derive title / bundle identifier from the selected bundle.
- Existing entries should remain editable and backward compatible.

## Open Questions

- None for MVP.

## Requirements (Evolving)

- Add developer shortcut entries by selecting a local macOS application first.
- After selecting an app, show a confirmation editor so users can adjust display name and target mode before saving.
- Avoid requiring the user to manually type a bundle identifier during normal add flow.
- Derive the bundle identifier from the selected app bundle.
- Existing entries should also use app selection for changing the app; the bundle identifier should not be manually editable.
- Duplicate app selections should be blocked when adding a new entry.
- Preserve target mode selection.
- Keep existing Finder menu and open-in-app execution behavior.

## Acceptance Criteria

- [x] Clicking "添加快捷入口" opens a local app selection flow before the confirmation editor.
- [x] Selecting a valid `.app` fills the display name and bundle identifier automatically.
- [x] The confirmation editor lets users adjust display name and target mode before saving.
- [x] Editing an existing entry shows current app information and a "更换应用" style action instead of a bundle identifier text field.
- [x] Adding an app whose bundle identifier already exists shows a user-facing duplicate message and does not save a second entry.
- [x] Saving creates or updates the associated `.openInApp` action.
- [x] Invalid selections show a user-facing validation message instead of saving broken config.
- [x] Existing developer entrypoints still load and can be edited.

## Decisions

- Add flow: use "select local `.app` first, then confirm" rather than making users type a bundle identifier or saving immediately.
- Edit flow: do not expose manual bundle identifier editing; show current app information and let users replace it via app selection.
- Duplicate handling: block duplicate app entries on add; editing the current entry remains allowed.

## Definition of Done

- Tests added or updated where practical.
- Swift type checks / package fallback checks pass.
- `scripts/package-macos.sh debug` passes if packaging-adjacent code changes.
- `git diff --check` passes.
- Behavior change is documented if it creates a reusable convention.

## Out of Scope (Explicit)

- No change to Finder menu execution semantics unless a later decision requires it.
- No broad redesign of the developer tools page.
- No removal of existing persisted developer entrypoint data.

## Technical Notes

- Existing editor: `DeveloperEntrypointEditorSheet`.
- Existing draft: `DeveloperEntrypointDraft`.
- Existing list trigger: `DeveloperEntrypointListView.onChange(of: developerEntrypointAddRequest)`.
- Existing validation currently rejects empty `bundleIdentifier`.
- Relevant specs: `.trellis/spec/frontend/index.md`, `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/component-guidelines.md`, `.trellis/spec/frontend/type-safety.md`, `.trellis/spec/backend/quality-guidelines.md`.
