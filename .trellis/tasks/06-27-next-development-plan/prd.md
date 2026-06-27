# Custom Command Template MVP

## Goal

实现 RightTool 自定义命令模板 MVP，让开发者可以在设置页配置可重复执行的命令，并从 Finder 右键触发后自动拉起 RightTool 主 App，打开内置实时输出窗口查看 stdout / stderr、退出状态、耗时和停止控制。该任务要在保持授权目录安全边界的前提下，补齐 `runCommand` 预留能力，形成面向开发者的高价值右键工作流。

## What I already know

* 用户要求使用 `grill-me` 根据当前状态制定下一步开发计划任务，后续已确认进入开发阶段。
* 当前 Trellis 状态已清理，创建了本规划任务：`.trellis/tasks/06-27-next-development-plan`。
* 当前没有其他 active task。
* Git 当前只有一个未跟踪文件：`design/design6.png`。
* 近期归档任务显示：
  * `macos-righttool-mvp` 已完成核心右键菜单、XPC ActionRunner、文件动作、操作日志、配置存储和预览包。
  * `settings-page-interaction` 已完成设置页信息层次、配置编辑、最近操作展示和本地预览验证。
* `docs/architecture.md` 说明当前仍是 SwiftPM preview bundle，不是完整 Xcode 项目；正式公开分发仍需要 Xcode project、Developer ID signing、notarization。
* 当前源码已经具备目录添加、替换、删除、启停、排序、`NSOpenPanel` 选择目录和 security-scoped bookmark 写入能力。
* `ActionKind` 已预留 `runCommand` 和 `undoOperation`。
* `ActionRunner` 当前对 `runCommand` / `undoOperation` 明确返回 unsupported。
* `OperationLogStore` 记录了 move/copy/cut/paste/create/open 等历史，但没有足够结构化的 undo payload。
* `FileOperationService` 当前冲突策略默认 `keepBoth`，还没有用户级冲突确认 UI。
* `.github/workflows/package-macos.yml` 已能构建并上传非 notarized 的预览 artifact。

## Assumptions (temporary)

* 下一步应优先服务“开发者/高级用户”的真实试用闭环，而不是先做营销页或大规模重构。
* 短期仍以本地预览版验证为主，不急着进入正式签名分发。
* 安全边界必须保持：所有文件动作仍限制在授权目录内。
* 新能力最好能复用现有 Action 模型、设置页编辑器、Finder 菜单和操作日志。

## Candidate Directions

### A. 自定义命令模板（推荐）

让用户在设置页创建命令模板，并从 Finder 右键对当前目录或选中文件运行命令。它直接服务开发者用户，且模型层已经预留 `runCommand` / `commandTemplateID`。

这里的“命令模板”不是已有的“新建文件模板”。新建文件模板负责生成文件内容；命令模板负责保存一条可重复执行的开发命令，例如对当前目录运行测试、格式化、打开本地服务脚本等。

核心风险是命令执行安全：必须限定工作目录、参数插值、超时、日志脱敏和用户确认，不做任意 shell 自由输入的失控版本。

### B. 有限撤销

基于操作历史支持撤销最近一次移动/复制/新建。它能提升文件操作信任感，但需要重新设计 OperationRecord 以保存可逆操作上下文，且删除/覆盖/批量冲突的边界复杂。

### C. 冲突确认 UI

把当前默认 `keepBoth` 升级为用户确认。它补齐 MVP PRD 原始要求，但涉及 ActionRunner 与主 App/Extension 的交互边界，需要决定弹窗由谁触发、如何等待结果。

### D. 分发工程化

补 Xcode project、Developer ID signing、notarization 和下载包体验。它提高交付成熟度，但对当前产品功能验证帮助不如 A/B/C 直接。

## Recommended Next Task

推荐下一步先做 **A：自定义命令模板 MVP**。

推荐理由：

* 与开发者/高级用户定位最贴合。
* `ActionKind.runCommand` 和 `ActionPayload.commandTemplateID` 已预留，说明架构方向已经为它留了口。
* 设置页已经具备可编辑列表、表单、保存反馈、菜单预览等模式，可以延展到命令模板。
* 命令模板能形成新的高价值右键场景：格式化、打开项目脚本、快速执行 repo 工具命令。
* 相比撤销和冲突确认，它更容易切成安全可控 MVP：只支持预定义模板，不支持从 Finder 临时输入任意命令。

## Open Questions

* 已锁定：下一步做 **自定义命令模板 MVP**。
* 已锁定：MVP 支持少量安全变量插值，不支持 Finder 右键时临时输入任意命令。
* 已锁定：命令执行需要有实时终端窗口，而不是只写后台操作日志。
* 已锁定：实时终端窗口采用“内置实时输出窗口”，MVP 不做完整交互式 TTY。
* 已锁定：从 Finder 右键触发命令时，必须自动拉起 RightTool 主 App，并显示运行窗口。
* 已锁定：命令模板 MVP 允许配置环境变量。
* 已锁定：环境变量按单个命令模板单独配置。
* 已锁定：MVP 提供 3 个安全默认命令模板：`Git Status`、`List Files`、`Print Working Directory`。
* 已锁定：默认超时 60 秒，单个模板可配置 5-600 秒；停止/超时先 terminate，仍未退出再 kill。
* 已锁定：敏感环境变量存入 macOS Keychain，普通环境变量存入配置 JSON。
* 已锁定：本规划任务已收敛为实现任务，并进入开发阶段。

## Requirements (evolving)

* 新任务需要明确一个主方向，不把 A/B/C/D 混在一次实现里。
* 下一步主方向已锁定为 **自定义命令模板 MVP**。
* 如果选择自定义命令模板，MVP 应偏保守：
  * 只运行用户在设置页保存过的模板。
  * 支持少量安全变量插值：`{{currentDirectory}}`、`{{selectedPath}}`、`{{selectedPaths}}`。
  * 不支持 Finder 右键时临时输入任意命令。
  * 工作目录必须来自已授权目录或选中项所在的已授权目录。
  * 命令执行需要超时。
  * 命令执行需要打开实时终端窗口，让用户看到 stdout / stderr 的持续输出。
  * 实时终端窗口 MVP 是只读输出控制台：显示运行状态、stdout / stderr、退出码、耗时，并提供停止按钮。
  * MVP 不支持交互式输入、PTY、`vim` / `ssh` / `npm login` 等需要终端输入的命令。
  * Finder 右键触发命令时，应自动拉起 / 前置 RightTool 主 App，由主 App 打开运行窗口并执行命令。
  * 命令模板执行不复用现有一次性 ActionRunner 请求/响应路径；文件操作继续由 ActionRunner 执行。
  * 命令模板允许配置环境变量。
  * 环境变量按单个命令模板单独配置，不做全局环境变量。
  * 环境变量需要支持敏感值标记；敏感值不进入操作日志、实时窗口标题或普通摘要。
  * 普通环境变量可以存入配置 JSON。
  * 敏感环境变量真值必须存入 macOS Keychain；配置 JSON 只保存引用 ID / 元数据。
  * Keychain MVP 只需要支持保存、读取、更新、删除，不做复杂共享、导入导出或跨设备同步。
  * 默认提供 3 个安全命令模板：
    * `Git Status`：`git status --short`
    * `List Files`：`ls -la`
    * `Print Working Directory`：`pwd`
  * 命令超时策略：
    * 默认 60 秒。
    * 单个命令模板可配置 5-600 秒。
    * 超时先 terminate。
    * 短暂等待后仍未退出，再 kill。
    * 用户点击停止也采用同样策略。
  * 操作日志记录命令标题、工作目录、退出状态、耗时和输出摘要。
  * 不把完整敏感环境变量写入日志。
* 如果选择撤销，必须先补 OperationRecord 的可逆信息设计。
* 如果选择冲突确认，必须先明确弹窗/等待交互跨进程方案。
* 如果选择分发工程化，必须先明确是否已有 Apple Developer ID、证书和 notarization 条件。

## Acceptance Criteria

* [x] 明确锁定一个下一步开发方向。
* [x] PRD 说明为什么现在做它，而不是做其他候选方向。
* [x] PRD 定义 MVP 范围、非目标、关键风险和验收标准。
* [x] 设置页可以新增、编辑、删除命令模板。
* [x] 命令模板包含标题、命令文本、工作目录策略、超时秒数、环境变量配置和菜单展示配置。
* [x] 默认配置包含 `Git Status`、`List Files`、`Print Working Directory` 三个安全命令模板。
* [x] 命令模板支持 `{{currentDirectory}}`、`{{selectedPath}}`、`{{selectedPaths}}` 变量插值。
* [x] Finder 右键触发命令模板时，自动拉起 RightTool 主 App。
* [x] 主 App 打开内置实时输出窗口，流式展示 stdout / stderr。
* [x] 实时输出窗口展示运行状态、退出码、耗时，并提供停止按钮。
* [x] 命令默认超时 60 秒，单个模板可配置 5-600 秒。
* [x] 超时和停止都先 terminate，短暂等待后仍未退出再 kill。
* [x] 命令只在授权目录或授权目录内选中项上下文中运行。
* [x] 普通环境变量存入配置 JSON。
* [x] 敏感环境变量真值存入 macOS Keychain，配置 JSON 只保存引用 ID / 元数据。
* [x] 操作历史记录命令标题、工作目录、退出状态、耗时和输出摘要，不记录敏感变量真值。
* [x] 不支持完整交互式 TTY / PTY，不支持需要用户输入的命令。
* [ ] `swift build --target RightToolAppPreview` 通过。
* [ ] `scripts/ci-swift-check.sh debug` 通过。

## Definition of Done (team quality bar)

* Swift / SwiftUI / AppKit 代码结构清晰，命令模板模型、命令运行器、待运行请求、实时窗口和设置页职责分离。
* 关键命令解析、变量插值、授权目录校验、超时/停止、Keychain 存取有单元测试或可验证路径。
* `swift build --target RightToolAppPreview` 通过。
* `scripts/ci-swift-check.sh debug` 通过。
* 手动验证：从设置页触发默认命令、从 Finder 右键触发命令并打开实时输出窗口。

## Out of Scope (explicit)

* 不同时推进多个大功能。
* 不做无限制任意 shell 执行。
* 不做右键时临时命令输入。
* 不做完整交互式 TTY / PTY。
* 不支持需要用户输入的交互命令。
* 不做全局环境变量管理。
* 不把敏感环境变量明文存入 App Group JSON 配置。
* 不做环境变量导入导出。
* 不做复杂条件判断、管道拼接编辑器、`.env` 自动加载或后台长期运行服务管理。
* 不承诺本轮完成正式签名和 notarization。

## Technical Notes

* 参考文件：
  * `docs/architecture.md`
  * `docs/github-actions-packaging.md`
  * `Sources/RightToolCore/ActionModels.swift`
  * `Sources/RightToolCore/ActionRunner.swift`
  * `Sources/RightToolCore/OperationLogStore.swift`
  * `Sources/RightToolAppPreview/RightToolAppPreview.swift`
  * `.github/workflows/package-macos.yml`
* 当前目录管理能力已在 `SettingsViewModel` / `DirectoryListView` 中存在，不应再把“目录授权添加/移除”误判为下一步主任务。
* 当前 Finder 调用链是 `FinderSyncController → RightToolActionRunnerXPCClient.perform → ActionRunner.run → ActionResult`，属于一次性请求/响应，不支持 stdout / stderr 实时流式输出。
* Finder Sync Extension 不适合承载 SwiftUI 实时窗口；实时输出窗口应由主 App 负责展示。
* 预期命令链路：
  * Finder Extension 写入/发送一条待运行命令请求。
  * Finder Extension 唤起 RightTool 主 App。
  * 主 App 读取待运行请求，打开实时输出窗口。
  * 主 App 执行命令，流式显示 stdout / stderr。
  * 执行结束后写入 `operation-log.jsonl`。
* 如果选择命令模板，需要进一步研究 macOS 上安全执行子进程的约束、超时处理和输出捕获策略。

## Implementation Notes

* 新增 Core 命令模板模型、环境变量模型、待运行命令请求和 Keychain secret store。
* `RightToolConfig` 增加 `commandTemplates`，并提供旧 JSON 兼容解码默认值。
* `ConfigurationBootstrapper` 会为命令模板补齐 `.runCommand` 菜单动作。
* Finder Extension 对 `.runCommand` 不再走一次性 ActionRunner XPC，而是写入 `pending-command-run.json`、发分布式通知并拉起主 App。
* 主 App 监听待运行请求，打开内置实时输出窗口，用 `Process + Pipe` 流式展示 stdout / stderr。
* 命令窗口持有 `AuthorizedBookmarkAccess` 直到进程结束，确保安全书签访问覆盖整个命令生命周期。
* 停止/超时策略为先 `terminate`，2 秒后仍运行则 `SIGKILL`。

## Verification Notes

* 2026-06-27 通过：
  * `git diff --check`
  * `swiftc -target arm64-apple-macosx14.0 -parse-as-library -typecheck Sources/RightToolCore/*.swift`
  * 临时 `RightToolCore` module + `swiftc -typecheck` 检查 `RightToolAppPreview.swift`
  * 临时 `RightToolCore` module + `swiftc -typecheck` 检查 `FinderSyncController.swift`
  * 临时 `RightToolCore` module + `swiftc -typecheck` 检查 `RightToolActionRunnerService/main.swift`
  * `scripts/package-macos.sh debug`
* 2026-06-27 未通过：
  * `swift build --target RightToolAppPreview`
  * `scripts/ci-swift-check.sh debug`
* 失败原因：本机 SwiftPM manifest 链接失败，报 `PackageDescription.Package.__allocating_init` undefined symbol，源码尚未进入 SwiftPM 编译阶段；packaging 脚本已自动 fallback 到 direct `swiftc` preview compilation 并成功。
* 未执行手动 UI smoke test；需要打开预览包验证设置页命令模板编辑和 Finder 右键触发实时窗口。
