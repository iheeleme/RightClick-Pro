# Backend Development Guidelines

RightTool's "backend" layer is the Swift code that owns durable state, Finder menu data, file mutations, XPC transport, packaging, and tests. It is not a server backend and has no database, API routes, or web framework.

## Source Boundaries

| Area | Files | Responsibility |
|------|-------|----------------|
| Core models and actions | `Sources/RightToolCore/ActionModels.swift`, `FinderContext.swift` | Stable Codable contracts shared by app, Finder extension, XPC service, tests |
| Storage and bootstrap | `Storage.swift`, `OperationLogStore.swift`, `CutClipboardStore.swift`, `ConfigurationBootstrapper.swift` | App Group/Application Support JSON state, JSONL operation history, default config self-healing |
| File execution | `ActionRunner.swift`, `FileOperations.swift`, `Authorization.swift`, `AppOpening.swift`, `RuntimeFactory.swift` | Resolve bookmarks, validate paths, run file/app actions, log results |
| Menu projection | `MenuBuilder.swift` | Convert config into semantic menu presentation and icon descriptors |
| Process adapters | `Sources/RightToolFinderExtension/FinderSyncController.swift`, `Sources/RightToolActionRunnerService/main.swift`, `XPCAdapter.swift` | Render Finder menus, map menu clicks to XPC requests, expose ActionRunner |
| Packaging | `scripts/ci-swift-check.sh`, `scripts/package-macos.sh`, `.github/workflows/package-macos.yml` | Swift checks, preview bundle assembly, Finder extension validation |

## Guidelines Index

| Guide | Use When |
|-------|----------|
| [Directory Structure](./directory-structure.md) | Adding files, deciding target ownership, separating Core/App/extension/script work |
| [Database Guidelines](./database-guidelines.md) | Changing file-backed JSON, JSONL, cut clipboard, App Group/Application Support storage |
| [Error Handling](./error-handling.md) | Adding errors, XPC result mapping, validation failures, Finder extension logging |
| [Quality Guidelines](./quality-guidelines.md) | Running tests, changing packaging, Finder extension behavior, menu presentation contracts |
| [Logging Guidelines](./logging-guidelines.md) | Operation history, bootstrap records, Finder extension diagnostics, shell script output |

## Required Checks

- Run `scripts/ci-swift-check.sh debug` after Swift code changes.
- Run `scripts/package-macos.sh debug` after Finder extension, XPC, entitlements, or packaging changes.
- Run targeted XCTest filters for changed behavior, such as `swift test --filter ConfigurationBootstrapperTests`.
- Run `git diff --check` before committing.
