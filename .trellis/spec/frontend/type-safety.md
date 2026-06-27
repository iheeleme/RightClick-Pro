# Type Safety

RightTool uses Swift types and Codable models as the safety boundary between the settings UI, Finder extension, XPC service, and storage files.

## Core Types

Settings UI should import and reuse Core types:

- `RightToolConfig`
- `RightToolAction`
- `ActionKind`, `ActionVisibility`, `ActionPlacement`, `MenuGroup`
- `FileTemplate`
- `DeveloperEntrypoint`, `DeveloperTargetMode`
- `DirectoryBookmark`, `DirectoryBookmarkCatalog`
- `OperationRecord`
- `MenuIconDescriptor`

Do not create parallel UI-only copies of these models.

## Draft Types

Use draft structs for sheets where users can edit invalid intermediate values:

- `TemplateDraft`
- `DeveloperEntrypointDraft`

Drafts trim strings and produce Core models through `makeTemplate()` / `makeEntrypoint()`. Validation happens before save.

## Identifiers

- Model IDs are stable strings because they are persisted and referenced by actions.
- When creating custom IDs, generate a unique base with a UUID suffix, then let ViewModel validation catch duplicates.
- When editing IDs, update back references in existing actions.
- Do not use display titles as persistent identifiers.

## Codable Boundaries

- Only Core models should define stored JSON shape.
- XPC requests and results use `ActionRequest` and `ActionResult`, encoded as JSON data in `RightToolActionRunnerXPCAdapter`.
- Adding a persisted field requires considering default values and old JSON files.

## Exhaustive Switches

Keep UI labels/icons/tints exhaustive over Core enums:

- `ActionKind.displayName`, row icons, management type/tint.
- `ActionPlacement.displayName/systemImage`.
- `MenuGroup.displayName`.
- `ActionVisibility.displayName/systemImage/helperText`.
- `OperationKind` and `OperationRecordStatus` display helpers.

When adding an enum case, update display helpers, menu building, ActionRunner, and tests in the same change.

## Anti-Patterns

- Do not use raw string comparisons for action kind or placement when enum values are available.
- Do not force unwrap model lookups in rows; missing references should degrade gracefully or be validated before save.
- Do not hide schema changes inside SwiftUI code. Persisted shape belongs in Core.
