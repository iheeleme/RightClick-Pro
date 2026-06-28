# File-Backed Storage Guidelines

RightClick Pro has no database layer. Durable state is file-backed JSON/JSONL in an App Group container when available, with an Application Support fallback for unsigned/local preview builds.

## Storage Layout

`RightClickProStoragePaths` defines the complete storage contract:

```text
baseURL/
├── config.json
├── bookmarks.json
├── cut-clipboard.json
├── operation-log.jsonl
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
- Append by loading existing records, adding the new record, capping to `maxRecords`, and atomically rewriting the file.
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

- Prefer `RightClickProStoragePaths.defaultForCurrentProcess()` for production paths.
- Use `RightClickProStoragePaths.appGroup(identifier:)` only when absence should be reported as `StorageError.appGroupContainerUnavailable`.
- Use `RIGHTCLICKPRO_STORAGE_PATH` only for the ActionRunner process/testing override in `Sources/RightClickProActionRunnerService/main.swift`.
- Default preview configuration may be created by either the app or Finder extension; both must use the same storage path resolution.

## Config Repair Rules

`ConfigurationBootstrapper` is the only place that creates or repairs default config/bookmark state.

- Bootstrap must preserve unrelated user configuration.
- Missing available default bookmarks may be appended.
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
