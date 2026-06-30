# Error Handling

RightClick Pro favors typed errors at Core boundaries, user-facing Chinese `LocalizedError` messages for action/settings failures, and best-effort diagnostics at process adapters.

## Error Types

Use focused `Error` enums near the owning domain:

- `StorageError` for missing App Group or required storage files.
- `BookmarkError` for missing or invalid bookmark resolution.
- `AuthorizationError` for paths outside configured monitored/common directories.
- `FileOperationError` for invalid file operations, conflicts, and cancellation.
- `ActionRunnerError` for action lookup, unsupported kinds, missing payloads, and missing related config.
- `RightClickProXPCClientError` for unavailable XPC service or missing replies.
- `SettingsValidationError` for settings UI save validation.

Reference files: `Sources/RightClickProCore/Storage.swift`, `BookmarkModels.swift`, `Authorization.swift`, `FileOperations.swift`, `ActionRunner.swift`, `XPCAdapter.swift`, `Sources/RightClickProAppPreview/SettingsViewModel.swift`, `EditorSheetViews.swift`.

## Propagation Rules

- Core service methods should throw typed errors when callers can recover or record a failure.
- `ActionRunner.run(_:)` is the fault boundary for file/app actions. It catches errors, returns `ActionResult(status: .failure, message: error.localizedDescription)`, and appends a failure `OperationRecord`.
- XPC adapter decode/encode failures should reply with `NSError`; successful runner failures are still encoded as `ActionResult`.
- Finder extension should log failures with `NSLog` and avoid crashing Finder.
- Settings UI should catch persistence/validation errors and surface them via `statusMessage` and `statusTone`.

## Validation Patterns

- Validate authorized paths before file mutations in `ActionRunner`.
- Validate `RightClickProConfig` before saving from settings UI.
- Validate root-menu count against `config.maxRootMenuActions` both when promoting an action and on save.
- Validate template and developer IDs for emptiness and duplicates before persisting.
- Validate filenames by rejecting empty strings and `/`.

Reference files: `Sources/RightClickProCore/ActionRunner.swift`, `FileOperations.swift`, `Sources/RightClickProAppPreview/SettingsViewModel.swift`, `EditorSheetViews.swift`.

## Cancellation

Use explicit cancellation states when a user or resolver cancels an operation:

- `FileConflictResolution.cancel` throws `FileOperationError.cancelled`.
- `ActionResultStatus.cancelled` and `OperationRecordStatus.cancelled` exist for future UI flows.
- Current fixed conflict resolver defaults to `.keepBoth`; do not silently replace files.

## Anti-Patterns

- Do not ignore errors in Core services that mutate files or storage.
- Do not crash the Finder extension for config/bootstrap/XPC failures.
- Do not return `nil` for missing action payloads; throw `ActionRunnerError.missingPayload`.
- Do not convert all failures to strings before the process boundary; keep typed errors until the UI/XPC/log boundary.
