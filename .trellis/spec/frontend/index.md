# Frontend Development Guidelines

RightTool's frontend is a native macOS SwiftUI/AppKit settings surface, not a web UI. The current implementation is concentrated in `Sources/RightToolAppPreview/RightToolAppPreview.swift` and consumes contracts from `RightToolCore`.

## Source Boundaries

| Area | Files | Responsibility |
|------|-------|----------------|
| App shell | `RightToolAppPreview` | Menu bar extra, settings window, hidden title-bar chrome |
| State and commands | `SettingsViewModel` | Bootstrap/load/save config, edit actions/templates/directories/developer entries, expose derived counts/status |
| Settings screens | `SettingsRootView`, `SettingsSidebar`, section views | Present overview, action management, directories, templates, developer entries, operation history |
| Shared presentation | `DesignPanel`, `PageToolbar`, `PreviewSection`, `FinderMenuPreview`, `MenuIconView`, editor sheet controls | Consistent dense macOS tool UI |
| Core integration | `RightToolCore` imports | Reuse `RightToolConfig`, `MenuBuilder`, `MenuIconResolver`, `OperationRecord`, storage stores |

## Guidelines Index

| Guide | Use When |
|-------|----------|
| [Directory Structure](./directory-structure.md) | Splitting SwiftUI files, adding views, keeping Core/App boundaries |
| [Component Guidelines](./component-guidelines.md) | Building SwiftUI settings tables, forms, preview cards, icon controls |
| [Hook Guidelines](./hook-guidelines.md) | Using SwiftUI local state, bindings, sheets, `onChange` instead of React-style hooks |
| [State Management](./state-management.md) | Editing `RightToolConfig`, unsaved state, persistence, derived counts/status |
| [Quality Guidelines](./quality-guidelines.md) | Verifying settings changes, packaging, visual smoke tests |
| [Type Safety](./type-safety.md) | Keeping Codable Core models and draft/edit types safe |

## Required Checks

- Run `swift build --target RightToolAppPreview` for settings-only compile checks.
- Run `scripts/ci-swift-check.sh debug` before committing Swift changes.
- Run `scripts/package-macos.sh debug` after settings, Finder preview, icon, or packaging-adjacent changes.
- Manually open the settings window for interaction and layout smoke tests when UI changed.
