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
- Action failures retain `OperationKind(actionKind:)`. A transport failure is recorded by Finder before publishing `actionFailureNotificationName`; an encoded failure result is already recorded by ActionRunner and must not be logged again by Finder.
- Batch move/copy results retain completed destinations, pending source URLs, and per-item errors. Paste updates its clipboard to only pending sources, and cancellation preserves all unprocessed items.
- Settings UI should catch persistence/validation errors and surface them via `statusMessage` and `statusTone`.

### ActionRunner Authorization Scope

`ActionRunner.run(_:)` must resolve only the security-scoped bookmarks required by the selected action. Directory actions (`openDirectory`, `moveToDirectory`, and `copyToDirectory`) resolve their `payload.directoryID`; `cut`, `paste`, `createFile`, `openInApp`, `runCommand`, and `undoOperation` must not eagerly resolve the entire bookmark catalog. An invalid unrelated bookmark must not turn an otherwise independent action into a failure before execution. Add a regression test whenever a new action kind starts depending on directory authorization.

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

## Scenario: Partial File Actions and Persistence Failures

### 1. Scope / Trigger

- Changes to batch file actions, paste progress, `ActionResult`, or operation-history writes.

### 2. Signatures

```swift
moveBatch(_:to:) throws -> FileOperationBatchResult
copyBatch(_:to:) throws -> FileOperationBatchResult
ActionResult.affectedURLs: [URL]
ActionResult.remainingURLs: [URL]
```

### 3. Contracts

- `affectedURLs` contains completed destinations; `remainingURLs` contains unfinished sources.
- Paste stores only remaining sources. Cancellation retains the conflicting item and every unprocessed item.
- Legacy result JSON without `remainingURLs` decodes to an empty array.
- Errors after execution preserve both URL arrays and the original action outcome in the message.

### 4. Validation & Error Matrix

- Individual file failure -> continue other items and return the failed source for retry.
- Clipboard write failure -> return `.failure` with the batch result and tell the user to rebuild the cut selection before pasting again; the old clipboard may still contain completed items.
- History write failure -> return `.failure` with the original result plus a history-persistence explanation. Do not route it through the pre-execution catch or attempt duplicate logging.
- Finder transport failure -> append one record with the captured `OperationKind`; an encoded failure already has its ActionRunner record.

### 5. Good/Base/Bad Cases

- Good: the first file moves, the second is missing, and the response preserves one completed destination plus one pending source even when history storage is unavailable.
- Base: all files succeed and paste clears its clipboard.
- Bad: a log-write error replaces a completed batch with a new result whose URL arrays are empty.

### 6. Tests Required

- `ActionRunnerTests`: partial paste retry, failed history writes, failed clipboard writes, and exact operation kind.
- `FileOperationServiceTests`: continue after a missing source and retain unprocessed items after cancellation.
- `StorageTests`: legacy decoding and remaining-URL round trip.

### 7. Wrong vs Correct

```swift
// Wrong: discards completed work after a persistence error.
return ActionResult(requestID: request.id, status: .failure, message: error.localizedDescription)

// Correct: annotate the existing execution result.
result.status = .failure
result.message += persistenceFailureMessage
return result
```
