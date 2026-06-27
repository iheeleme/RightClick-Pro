# Dynamic Developer Entrypoint Target

## Goal

让开发者快捷入口的目标路径支持动态判断：在 Finder 选中项目后右键时打开选中的项目；在 Finder 空白处右键时打开当前目录。这样 Terminal、VS Code、Cursor 等入口可以用一个默认模式同时覆盖文件/文件夹和目录空白处场景。

## What I Already Know

* 用户希望开发者快捷方式入口的“目标方式”改成动态行为。
* 现有 `DeveloperTargetMode` 有三种模式：`currentDirectory`、`selectedItem`、`selectedItemDirectory`。
* Finder Extension 已经区分 `FinderInvocation.selection` 和 `FinderInvocation.container`，并把 `targetDirectory` 与 `selectedItems` 放入 `FinderContext`。
* `ActionRunner` 当前在 `.openInApp` 中通过 `developerTargetURL(for:context:)` 统一解析目标 URL。
* 开发者入口默认 action 已覆盖 `.selection`、`.container`、`.toolbar`，因此动态逻辑可以在 Core 层完成，不需要 Finder Extension 绕过 XPC。

## Requirements

* 新增一个明确的动态目标模式，用于开发者快捷入口。
* 动态模式规则：
  * 当 `FinderContext.invocation == .selection` 且存在选中项时，目标为第一个选中项目。
  * 当 `FinderContext.invocation == .container` 或没有选中项时，目标为当前 Finder 目录。
  * 工具栏菜单没有明确“空白处/选中项”语义时，优先使用选中项；无选中项则使用当前目录。
* 新建开发者入口默认使用动态目标模式。
* 内置默认开发者入口默认使用动态目标模式。
* 已安装配置中的内置默认入口如果仍保持旧的 `currentDirectory` 默认值，应在启动自修复时迁移为动态模式。
* 设置页目标模式选择器展示“动态”模式，并用中文文案解释其行为。
* 保留已有三种模式，避免破坏用户已有配置。
* 对 Codex、VS Code、Cursor、JetBrains 系、Zed、Sublime Text、TextMate、Nova、Xcode 等开发工具，优先使用可打开工作区目录的 CLI 入口。
* 本机未安装的应用不能靠本地 bundle 检查确认时，候选入口必须来自官方文档、本机一手 CLI 帮助或常见 VS Code 派生应用包结构，并在运行时检测可执行文件存在后才调用。
* 如果识别到应用但候选 CLI 不存在，必须回退到原有 `NSWorkspace.open` 行为，避免新增适配导致应用完全打不开。

## Acceptance Criteria

* [x] 选中文件或文件夹后右键打开开发者入口时，应用收到选中项路径。
* [x] 在 Finder 空白处右键打开开发者入口时，应用收到当前目录路径。
* [x] 没有选中项时动态模式回退到当前目录，不失败。
* [x] 默认 Terminal / VS Code / Cursor 入口使用动态模式。
* [x] 已安装配置中的旧默认入口会自修复为动态模式。
* [x] 设置页新增/编辑入口时默认目标为动态模式，并可显式选择其他模式。
* [x] Core 单元测试覆盖 selection、container、toolbar/fallback 场景。
* [x] Codex 使用应用包内 `codex app <workspace>` 打开工作区目录。
* [x] VS Code / Cursor / Windsurf / Trae 使用各自应用包内 CLI 打开工作区目录。
* [x] JetBrains / Zed / Sublime Text / TextMate / Nova 入口在候选 CLI 存在时走命令打开目录。
* [x] 未识别或未找到 CLI 的应用回退到 `NSWorkspace.open`。

## Definition of Done

* Tests added/updated for Core target resolution behavior.
* Swift compile/check passes as far as local toolchain allows.
* `git diff --check` passes.
* `scripts/package-macos.sh debug` passes because this touches Finder/XPC/Core behavior.
* If behavior contracts become reusable knowledge, update `.trellis/spec/`.

## Technical Approach

Add a new `DeveloperTargetMode.dynamic` case in `RightToolCore`.

Data flow:

```text
Finder right click
  → FinderSyncController.finderContext(...)
  → ActionRequest(context)
  → XPC
  → ActionRunner.openInApp
  → developerTargetURL(for:context:)
  → DeveloperAppOpening.open(entrypoint, targetURL)
```

The dynamic decision belongs in `ActionRunner` because it is shared runtime behavior and is already the single Core path for resolving developer entrypoint target URLs.

## Decision (ADR-lite)

**Context**: The same developer shortcut should behave naturally in both Finder item and Finder background menus.

**Decision**: Add an explicit persisted enum case `dynamic` instead of changing `currentDirectory` or `selectedItem` semantics.

**Consequences**: Existing configs remain stable. New/default entries get the requested behavior. UI display helpers and exhaustive switches must be updated with the new enum case.

## Out of Scope

* Changing command template working directory behavior.
* Opening multiple selected items in one developer app invocation.
* Adding every known developer app as a built-in default entry.
* Changing Finder menu placement or visibility rules.

## Technical Notes

* Relevant files:
  * `Sources/RightToolCore/ActionModels.swift`
  * `Sources/RightToolCore/ActionRunner.swift`
  * `Sources/RightToolCore/AppOpening.swift`
  * `Sources/RightToolAppPreview/RightToolAppPreview.swift`
  * `Tests/RightToolCoreTests/ActionRunnerTests.swift`
  * `Tests/RightToolCoreTests/AppOpeningTests.swift`
* Research:
  * `.trellis/tasks/06-27-developer-entrypoint-dynamic-target/research/workspace-openers.md`
* Relevant specs:
  * `.trellis/spec/backend/directory-structure.md`
  * `.trellis/spec/backend/quality-guidelines.md`
  * `.trellis/spec/frontend/component-guidelines.md`
  * `.trellis/spec/frontend/type-safety.md`
  * `.trellis/spec/guides/cross-layer-thinking-guide.md`
