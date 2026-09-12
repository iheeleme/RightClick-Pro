# File-Backed Storage Guidelines

RightClick Pro has no database layer. Durable state is file-backed JSON/JSONL under `~/Library/Application Support/com.iheeleme.rightclickpro` by default so first launch does not touch `~/Library/Group Containers` and trigger macOS "access data from other apps" prompts.

## Storage Layout

`RightClickProStoragePaths` defines the complete storage contract:

```text
baseURL/
├── config.json
├── bookmarks.json
├── cut-clipboard.json
├── operation-log.jsonl
├── pending-command-runs/
├── command-runs/
└── icon-cache/
    └── v1/
```

Reference files: `Sources/RightClickProCore/Storage.swift`, `OperationLogStore.swift`, `CutClipboardStore.swift`, `docs/architecture.md`.

## JSON Stores

- Use `JSONFileStore<Value: Codable>` for structured JSON files.
- Writes must be atomic via `Data.write(..., .atomic)`.
- Use `load(default:)` for optional/defaulted state and `loadRequired()` only when absence is a hard failure.
- Keep JSON output pretty-printed and sorted through the existing `JSONFileStore` encoder.
- Do not hand-roll ad hoc JSON parsing or string replacement for `config.json` or `bookmarks.json`.

## Operation Log

- Use `JSONLineOperationLog` for `operation-log.jsonl`.
- Hold `operation-log.jsonl.lock` across loading, appending, capping and atomic rewrite. Keep the lock file in place; locking the replaced JSON inode does not serialize other processes.
- The default cap is 500 records. Settings UI currently displays the latest 80 in reverse chronological order.
- Invalid JSONL lines are ignored by `loadRecent()` through `try?`; do not make the UI fail just because one historical line is corrupt.

Reference tests: `Tests/RightClickProCoreTests/StorageTests.swift`.

## Finder Icon Cache

Finder menu icon cache files live under `icon-cache/v1/` as small PNG files
generated from already-rasterized menu images.

- Finder menu callbacks must not read or write this directory.
- Disk reads and writes must happen asynchronously on a background queue.
- Cache keys should be hashed into filenames; do not use raw app bundle IDs or file paths as filenames.
- The disk cache is best-effort. Read/write failures should keep placeholder icons available and must not crash Finder.

## App Group and Fallback Rules

- Prefer `RightClickProStoragePaths.defaultForCurrentProcess()` for production paths; it must resolve to the real-user Application Support directory, not the sandbox container home and not the App Group container.
- Use `RightClickProStoragePaths.appGroup(identifier:)` only for explicit compatibility or diagnostics where absence should be reported as `StorageError.appGroupContainerUnavailable`.
- Use `RIGHTCLICKPRO_STORAGE_PATH` only for the ActionRunner process/testing override in `Sources/RightClickProActionRunnerService/main.swift`.
- Default preview configuration may be created by either the app or Finder extension; both must use the same storage path resolution.
- Sandboxed App/Finder extension builds need a home-relative read-write entitlement only for `/Library/Application Support/com.iheeleme.rightclickpro/`.

## Config Repair Rules

`ConfigurationBootstrapper` is the only place that creates or repairs default config/bookmark state.

- Bootstrap must preserve unrelated user configuration.
- Missing available default bookmarks may be appended only on first creation or the one-time `.default-directory-bootstrap-v1` migration. Write the marker after bookmarks/config save successfully; subsequent bootstrap runs preserve user-deleted defaults.
- Missing monitored/common IDs for available defaults may be appended.
- Missing generated directory actions may be appended.
- Existing sandbox-container bookmark paths must be remapped to the real user home.
- Bookmark IDs, display names, bookmark data, and timestamps must be preserved during path sanitization.

Reference tests: `Tests/RightClickProCoreTests/ConfigurationBootstrapperTests.swift`.

## Anti-Patterns

- Do not use `FileManager.homeDirectoryForCurrentUser` as the source of default monitored directories from sandboxed processes; use the bootstrapper's real-home resolution.
- Do not write storage files directly from child SwiftUI views.
- Do not remove or reorder unrelated user actions while repairing defaults.
- Do not introduce a database or migration framework until the JSON contract is proven insufficient.

## Scenario: Command Handoff and Orphan Recovery

### 1. Scope / Trigger
- Finder command dispatch, App queue consumption, or command state persistence changes.

### 2. Signatures
- `PendingCommandRunQueue.enqueue(_:)` and `consumeNext(_:) throws -> Bool`.
- `CommandRunService.status(for:) throws -> CommandRunSnapshot`.

### 3. Contracts
- Each pending request owns `<UUID>.json`; queue lock covers delivery and acknowledgement.
- Delivery failure retains the request. Corrupt files are retained and reported after healthy requests are delivered.
- Window activation must not reenter queue consumption. Repeated delivery of an ID focuses the existing window; an existing run ID must not start another process.
- Status queries acquire nonblocking ownership and re-read before recovering a nonterminal orphan; initialization alone is insufficient.
- Terminal write failure preserves actual exit status, appends a visible warning, retains ownership and retries every two seconds while the service lives.

### 4. Validation & Error Matrix
- Queue write/App launch failure -> Finder failure history and notification; queued launch failures retain requests.
- Recovery save failure -> throw from status, no success cache or completion log.
- Terminal write failure -> keep in-memory result and ownership until a retry saves it; service loss still means recovery reports an unknown result.

### 5. Good/Base/Bad Cases
- Good: concurrent requests survive and concurrent log writers retain every record up to the cap.
- Base: one request delivers once and its terminal state persists normally.
- Bad: atomic replacement treated as a cross-process transaction, or every terminal read automatically reruns a command.

### 6. Tests Required
- Storage tests: concurrent queue producers/consumers, failed delivery retry, corrupt-file isolation, concurrent history writers.
- Command tests: late orphan recovery, active owner preservation, failed terminal save with recovery and same-ID deduplication.

### 7. Wrong vs Correct
- Wrong: overwrite `pending-command-run.json`; recover only in service initialization.
- Correct: use `PendingCommandRunQueue`; check ownership during status reads as well as startup.
