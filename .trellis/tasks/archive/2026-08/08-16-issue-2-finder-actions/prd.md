# 修复 Finder 菜单点击无响应

## Goal

修复 GitHub Issue #2：Finder 右键菜单能显示，但点击动作没有可见结果。确保一个损坏或过期的目录 bookmark 不会阻断不依赖目录授权的动作，并保留目录动作对目标 bookmark 的按需授权；失败结果继续通过现有 `ActionResult` / operation log / Finder 日志链路传递。

## What I already know

* Issue #2 原文：权限、扩展都显示 ok，但实际右键菜单中的内容不可用，点击无反应。
* Finder extension 只负责构造菜单和发送 `ActionRequest`，实际动作由 `ActionRunner.xpc` 执行。
* `ActionRunner.run` 当前在执行具体 action 前，用 `bookmarks.bookmarks.map(\.id)` 创建 `AuthorizedBookmarkAccess`，会尝试解析目录目录中的每一个 bookmark。
* `SecurityScopedBookmarkResolver` 对无效 Base64 bookmark 会抛出 `BookmarkError.invalidBookmarkData`；这会在动作分派前短路所有动作。
* XPC/Finder 端对失败只写 `NSLog`，不显示 Finder 内反馈，因此运行时失败容易表现为“点击无反应”。
* 在本机已安装的 0.1.1 上，`前往下载` 的真实 Finder 菜单动作可以成功，说明问题需要用损坏 bookmark 的最小回归场景锁定，而不是假设所有环境都必现。

## Assumptions (temporary)

* #2 的核心修复范围是 ActionRunner 的按需 bookmark 解析，不改变 Finder 菜单结构、XPC 协议字段或权限模型。
* 目录相关 action 仍必须解析并使用 `payload.directoryID` 对应的 bookmark；其他 action 不应因为无关 bookmark 损坏而失败。
* 本轮不把 Finder UI 提示系统扩展为新通知权限或弹窗；先保证动作链路正确、失败可通过现有日志与 operation log 诊断。

## Open Questions

* 无阻塞问题。当前代码和 issue 描述足以实现并验证最小修复。

## Requirements

* 仅对 `.openDirectory`、`.moveToDirectory`、`.copyToDirectory` 解析 action 所需的目录 bookmark。
* `.cut`、`.paste`、`.createFile`、`.openInApp` 以及当前不支持的 action 不得解析无关目录 bookmark。
* 缺少目录 payload 时仍返回现有 `ActionRunnerError.missingPayload`，不能静默跳过。
* 目录 bookmark 缺失、无效或解析失败时，目录 action 保持现有失败语义和 operation log 记录。
* 增加一个回归测试：catalog 中包含无效 bookmark 时，剪切动作仍成功并写入剪切 clipboard。
* 保持 Core / Finder extension / XPC 的现有边界，不在 Finder extension 内直接执行文件操作。

## Acceptance Criteria

* [x] 新增的无效 bookmark 回归 harness 在旧逻辑上失败，在修复逻辑上通过。
* [x] `ActionRunner` 的目录授权解析集合只包含当前 action 真正需要的 directory ID。
* [x] 目录 action 的现有代码路径保持按需解析；严格 Core 编译通过。
* [x] `swift test --filter ActionRunnerTests` 已尝试；因本机 SwiftPM manifest 链接异常未进入 XCTest，使用严格 `swiftc` + 临时 harness 替代验证。
* [x] `git diff --check` 通过；`scripts/ci-swift-check.sh debug` 同样被本机 `PackageDescription` 链接异常阻塞。

## Verification Notes

* HEAD 基线临时 harness 输出 bookmark resolver 错误，证明旧逻辑会被无关坏 bookmark 短路。
* 修复后同一 harness 输出 `regression passed`；Core 使用 Swift 6 严格并发、warnings-as-errors、macOS 14 target 独立编译通过。
* 当前 CommandLineTools 的 SwiftPM manifest 缺少 `PackageDescription.Package` arm64 符号；XCTest 模块也无法由该工具链直接加载。
* 未运行会清理 `dist/staging` 和 `dist/manual-build` 的打包脚本；本次变更不涉及 Finder/XPC 包装结构。
* 本机已安装 0.1.1 的 Finder 菜单“前往下载”真实点击 smoke test 成功；未在用户的具体坏 bookmark 数据上运行生产动作。

## Definition of Done

* 变更限定在 Core ActionRunner 和对应测试/规范记录。
* 有最小回归测试覆盖损坏 bookmark 不阻断无关 action。
* 完成 targeted tests、Swift 编译检查和差异检查。
* 记录当前环境无法进行的人工 Finder smoke test（如有）。

## Out of Scope

* 不修改 `RightClickProActionRunnerXPCProtocol` 的签名或 JSON schema。
* 不修改 Finder 菜单排序、图标、可见性和全局 Finder Sync scope。
* 不新增通知权限、弹窗或改变错误文案展示方式。
* 不清理或重写用户现有 bookmark 数据；过期 bookmark 仍由目录 action 的错误路径处理。

## Technical Approach

在 `ActionRunner` 内增加一个小型 action-to-bookmark-ID 映射 helper：目录动作读取 `payload.directoryID`，其他动作返回空集合。`AuthorizedBookmarkAccess` 仍复用现有解析、security-scoped 生命周期和错误类型，只把输入 ID 集合从“整个 catalog”缩小为“当前动作需要的 ID”。用一个无效 bookmark + `.cut` action 的 XCTest 先建立红灯，再实现修复。

## Decision (ADR-lite)

**Context**: 所有 action 预先解析整个 bookmark catalog，导致一个坏 bookmark 形成全局故障；XPC 失败在 Finder 端没有明显 UI 反馈。

**Decision**: 在 ActionRunner 入口按 action kind 计算最小授权集合，目录 bookmark 只按需解析；不改变授权模型或 XPC contract。

**Consequences**: 不相关动作的可用性不再受坏 bookmark 影响；目录 action 仍会在真正使用时暴露 bookmark 错误。未来若新增依赖 bookmark 的 action，必须同步加入 helper 和回归测试。

## Technical Notes

* 相关代码：`Sources/RightClickProCore/ActionRunner.swift`、`BookmarkModels.swift`、`XPCAdapter.swift`、`Sources/RightClickProFinderExtension/FinderSyncController.swift`。
* 相关测试：`Tests/RightClickProCoreTests/ActionRunnerTests.swift`、`TestSupport.swift`。
* 规范：`.trellis/spec/backend/error-handling.md`、`quality-guidelines.md`、`.trellis/spec/guides/cross-layer-thinking-guide.md`。
