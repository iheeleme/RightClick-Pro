# 闭环核心操作与运行状态

## Goal

修复审计中确认的核心功能断点，使文件操作、命令运行、配置持久化和错误反馈形成可恢复、可观察、可验证的闭环。

## Scope

* 文件批量移动/粘贴按项返回结果，失败后保留未完成项，支持重试。
* 剪切板或历史落盘失败不丢失已完成项和未完成项；配置第二个文件保存失败时恢复原书签内容。
* Finder/XPC 动作失败保留真实动作类型并可被设置页读取。
* 命令超时和服务重启后的遗留运行记录进入明确终态。
* 命令 stdout/stderr 支持 UTF-8 跨块增量解码。
* 默认目录只在首次注入或迁移时补齐，用户删除后重启不复活。
* 保存配置后通知 Finder 扩展刷新；未保存命令不可从设置页运行。
* 命令模板草稿不提前修改 Keychain，提交成功后再清理旧密钥。
* App/Finder 两份 XPC 服务通过运行文件锁区分活动任务和遗留快照，避免误恢复其他服务的运行。
* README 如实标明当前版本尚不支持文件撤销。

## Acceptance Criteria

* [x] 批量文件动作失败时，已完成项不重复重试，未完成项可继续执行。
* [x] 历史或剪切板写入失败仍返回准确批次结果；剪切板更新失败明确要求重新建立剪切选择。
* [x] 配置写入失败时恢复原书签字节、回收新密钥并保留重试草稿，解除故障后可保存。
* [x] 失败操作记录真实 `OperationKind`，保留在历史页的类型过滤范围内。
* [x] Finder/XPC 传输失败补写历史记录，并向主 App 发布错误通知；已完成源码链路检查和严格类型检查。
* [x] 超时后在限定时间内结束进程并标记 `timedOut`。
* [x] 服务重启后无运行所有者的 `running` 快照会变为明确错误终态。
* [x] 两个服务实例及独立进程同时存在时，不误恢复仍有所有者的命令；观察者可读取最终状态。
* [x] UTF-8 字符跨 stdout/stderr 数据块不会丢失，退出时排空尾部。
* [x] 用户删除默认 Desktop/Downloads 后，重启 bootstrap 不会重新添加。
* [x] 保存配置触发扩展刷新通知；未保存命令运行有明确提示。
* [x] 命令草稿不修改已生效密钥，保存失败可回收新密钥并重试；已使用内存密钥仓库验证。
* [x] Core 严格编译、App/Finder/XPC 类型检查和可运行回归探针通过。
* [x] 预览打包及 App/Finder/XPC ad-hoc 签名校验通过。
* [x] 完整 XCTest 在 GitHub Actions 的 arm64 与 x86_64 工具链上通过（run 34679649253）。
* [ ] 已安装 Finder 扩展的通知刷新、XPC 不可用反馈与权限错误完成实机验收。

## Out Of Scope

* 不在本任务实现完整的 `undoOperation`；只保留为后续独立任务。
* 不在本任务接入 Developer ID 签名和 notarization。
* 不重做当前未提交的设置界面视觉调整。

## Technical Notes

* Backend: `ActionRunner.swift`, `FileOperations.swift`, `CommandRunService.swift`, `OperationLogStore.swift`, `ConfigurationBootstrapper.swift`, `XPCAdapter.swift`.
* Frontend: `SettingsViewModel.swift`, `CommandTemplateSettingsViews.swift`, `OperationHistoryViews.swift`.
* Finder boundary: `FinderSyncController.swift`.
* Relevant specs: `.trellis/spec/backend/{quality-guidelines,error-handling,logging-guidelines}.md`, `.trellis/spec/frontend/{state-management,quality-guidelines}.md`.

## Verification

详细命令、探针结果、产物和待验边界见 [validation.md](./validation.md)。v0.2.0 已提交发布，双架构 CI 已通过；Finder 实机验收未完成，任务保持 `in_progress`。

## 2026-09-12 收尾补充

用户已授权修复剩余断点并优化收尾。

* [x] 命令请求按 ID 持久化，消费串行化，失败不静默丢弃。
* [x] Finder 排队和启动主 App 失败进入通知与操作历史。
* [x] 历史读改写使用跨进程锁，并验证并发追加无丢失。
* [x] 已启动观察者按需恢复后来失主的命令。
* [x] 命令终态保存失败明确反馈，保留结果并允许重试落盘。
* [x] 完成回归检查并校正旧任务验收记录；未实测项保持未完成。
