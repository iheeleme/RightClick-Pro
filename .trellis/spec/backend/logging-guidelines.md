# Logging Guidelines

RightClick Pro has two logging surfaces: durable user operation history and process diagnostics.

## Durable Operation History

Use `OperationRecord` plus `JSONLineOperationLog` for user-visible history.

- Record the `actionID`, `OperationKind`, `OperationRecordStatus`, source paths, destination paths, and a short message.
- Successful actions are logged by `ActionRunner.log(action:request:result:)`.
- Failures caught by `ActionRunner.run(_:)` should append a failure record with `kind: .unsupported` when the exact kind is unavailable.
- Bootstrap writes an initial success record when creating `operation-log.jsonl`.
- Keep the log capped. The default cap is 500 records.

Reference files: `Sources/RightClickProCore/OperationLogStore.swift`, `ActionRunner.swift`, `ConfigurationBootstrapper.swift`, `Tests/RightClickProCoreTests/StorageTests.swift`.

## Process Diagnostics

Use `NSLog` only at AppKit/Finder process boundaries:

- Finder extension bootstrap failure.
- Finder menu action dispatch without a pending payload tag.
- XPC action success or failure from the Finder extension.

Reference file: `Sources/RightClickProFinderExtension/FinderSyncController.swift`.

## Shell Script Output

Packaging scripts should fail loudly for hard gates and stay best-effort for local PlugInKit enablement.

- Hard gates: unsupported config, invalid Xcode env pairing, missing icon source, invalid Finder extension binary, missing XPC service, deep codesign verification.
- Best effort: `pluginkit` unavailable or local `pluginkit -a` / `pluginkit -e use` failures.

Reference file: `scripts/package-macos.sh`.

## What Not To Log

- Do not log bookmark data or security-scoped bookmark base64 strings.
- Do not log full config JSON for normal success paths.
- Do not add noisy debug prints inside Core services; prefer XCTest assertions.
- Do not make operation history a debug log sink. It is a user-facing audit trail.
