# Optimize settings page interaction

## Goal

优化 RightTool 原生 macOS 设置窗口的交互体验，让当前预览版设置页从“能展示配置”提升到“能帮助用户理解状态、快速定位配置、明确执行操作反馈”的工具型界面。

## What I already know

* 用户要求“优化设置页面交互效果”。
* 当前设置页位于 `Sources/RightToolAppPreview/RightToolAppPreview.swift`。
* 当前 App 形态是菜单栏 App + `Window("RightTool 设置", id: "settings")`。
* 当前设置页使用 `NavigationSplitView`，左侧为 6 个分区：
  * 首次引导
  * 生效目录
  * 菜单动作
  * 新建文件模板
  * 开发者入口
  * 最近操作
* 当前详情页以静态展示为主：
  * 引导页展示 4 个步骤和“重新注入默认设置”按钮。
  * 目录页展示 bookmarks 和配置路径。
  * 动作、模板、开发者入口页都是基础 `List`。
  * 最近操作仍是 placeholder。
* 本项目最低支持 macOS 14，技术栈是原生 Swift / SwiftUI / AppKit。
* 之前已打通 Finder 右键菜单、XPC ActionRunner 和操作日志。

## Assumptions

* 本任务聚焦设置页交互和展示，不改变 Finder 右键执行链路。
* 先优化当前 SwiftUI 预览设置页，不引入第三方 UI 框架。
* 以开发者/高级用户的工具效率为优先：信息密度适中、状态明确、操作路径短。

## Open Questions

* 已锁定：本轮采用 **C1：配置编辑核心**，不纳入目录授权添加/移除。

## Requirements (evolving)

* 设置页应保留现有 6 个分区和菜单栏入口打开设置的能力。
* 本轮方向锁定为 **C：配置编辑型**。
* MVP 范围锁定为 **C1**：
  * 菜单动作：启用/停用、一级菜单/子菜单切换。
  * 新建文件模板：新增/编辑/删除文本模板。
  * 开发者入口：新增/编辑/删除入口。
  * 最近操作：读取真实操作日志并展示。
  * 保存/删除/重置提供明确反馈。
* 设置页视觉效果需要更丰富：
  * 侧边栏和列表行增加相关图标。
  * 页面顶部增加状态摘要、数量统计或关键状态提示。
  * 空状态、状态标签和操作按钮要比纯文本列表更清晰。
  * 整体保持原生 macOS 工具感，不做营销式大横幅。
* 设置页应不只是展示配置，还要允许用户修改核心配置并保存到本地配置文件。
* 设置页应更清楚展示当前配置状态，例如目录数量、动作数量、模板数量、最近操作状态。
* 关键操作应有反馈，例如保存成功、保存失败、重新注入默认设置后的明显状态变化。
* 列表类页面应更容易扫描，展示启用状态、分组、路径、类型等关键信息。
* 动作配置应至少支持启用/停用、一级菜单/子菜单切换，并遵守最多 5 个一级菜单项限制。
* 模板配置应至少支持新增/编辑/删除文本模板，包含模板名称、默认文件名和文本内容。
* 开发者入口配置应至少支持新增/编辑/删除入口，包含标题、Bundle Identifier 和目标模式。
* “最近操作”不应继续只是占位；至少应读取并展示最近操作日志的基础信息。
* 交互优化应避免影响 Finder Sync Extension 和 XPC ActionRunner 的职责边界。

## Acceptance Criteria (evolving)

* [x] 设置窗口打开后，用户能在首屏看到 RightTool 当前配置是否已加载、右键功能是否已有基础配置。
* [x] 用户能更快切换和理解各设置分区。
* [x] 目录、菜单动作、模板、开发者入口列表比当前纯文本列表更易扫描。
* [x] 用户能在设置页修改并保存菜单动作启用状态和菜单层级。
* [x] 用户能在设置页新增/编辑/删除文本模板。
* [x] 用户能在设置页新增/编辑/删除开发者入口。
* [x] 最近操作页能展示真实 `operation-log.jsonl` 数据。
* [x] 保存、删除、重新注入默认设置都有明确的即时反馈。
* [x] 设置页主要分区包含合适图标、状态标签和更丰富的信息层次。
* [x] 本地预览包能构建通过。

## Definition of Done

* SwiftUI 设置页代码结构清晰，不把复杂逻辑塞进单个 View。
* 关键状态和列表展示有基础测试或可验证路径。
* `scripts/package-macos.sh debug` 通过。
* 如果本机 SwiftPM manifest 仍因工具链失败，需要明确记录失败原因。
* 手动打开设置窗口验证主要交互。

## Out of Scope

* 不做完整偏好设置持久化编辑器。
* 不做复杂动画或花哨视觉改版。
* 不引入第三方 UI 组件库。
* 不修改 Finder 右键菜单执行链路。
* 暂不实现动作拖拽排序；可以用显式字段或当前顺序保留。
* 暂不实现复杂命令模板、二进制模板、多文件模板。
* 目录安全书签添加/移除不纳入本轮，后续单独做。

## Technical Notes

* 主要候选文件：
  * `Sources/RightToolAppPreview/RightToolAppPreview.swift`
  * `Sources/RightToolCore/OperationLogStore.swift`
  * `Sources/RightToolCore/Storage.swift`
* 现有 `SettingsViewModel` 已持有：
  * `config`
  * `bookmarks`
  * `storagePath`
  * `bootstrapMessage`
* 可以优先扩展 `SettingsViewModel` 读取最近操作，并派生统计信息供 UI 展示。
* `RightToolConfig` 已包含可编辑字段：
  * `actions`
  * `fileTemplates`
  * `developerEntrypoints`
  * `monitoredDirectoryIDs`
  * `commonDirectoryIDs`
  * `maxRootMenuActions`
* `JSONFileStore.save` 已支持原子写入，可用于设置页保存配置。
* `DirectoryBookmark` 支持 `bookmarkDataBase64`，但真实添加目录需要 `NSOpenPanel` + security-scoped bookmark 生成，复杂度高于普通配置编辑。
* 项目 frontend spec 仍是通用占位，具体 SwiftUI 约定可在本任务后补充。

## Verification Notes

* 2026-06-27 自动验证通过：
  * `git diff --check`
  * `swift build --target RightToolAppPreview`
  * `scripts/ci-swift-check.sh debug`
  * `scripts/package-macos.sh debug`
  * 预览包中 `RightToolIcon.icns` / `RightToolIcon.png` 存在。
  * Finder Sync `.appex` 二进制为 Mach-O `EXECUTE`。
* 手动打开设置窗口验证主要交互：待用户在本机窗口中确认。
