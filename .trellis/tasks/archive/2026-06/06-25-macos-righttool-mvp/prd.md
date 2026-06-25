# Develop macOS RightTool MVP

## Goal

开发一个原生 macOS 右键管理工具 RightTool，面向开发者和高级用户，在用户显式授权的 Finder 目录内提供高频文件操作、常用目录直达、开发者入口和新建文件能力。MVP 目标是先打通稳定可信的“右键菜单 → XPC ActionRunner → 文件动作 → 操作历史”闭环，为后续自定义命令、撤销、自动更新等能力预留扩展点。

## What I Already Know

* 当前仓库尚未包含 macOS App 源码，适合先从产品需求、架构和工程骨架开始。
* 产品形态采用菜单栏常驻 App + 设置窗口 + Finder Sync Extension。
* MVP 只在 Finder 中、且只在用户配置并授权的目录内生效。
* 技术栈采用原生 Swift / SwiftUI / AppKit，不使用 Electron 或 Tauri。
* 最低支持 macOS 14 Sonoma。
* 第一阶段定位开发者/高级用户工具，优先非 App Store 分发。
* Finder Sync Extension 只负责读取配置并生成菜单，实际动作由 XPC ActionRunner 执行。
* ActionRunner 是非特权用户级服务，不安装管理员权限 Helper。
* 配置和操作历史使用 App Group 共享容器内的 JSON / JSONL 文件。

## Requirements

### Product Shape

* 提供菜单栏常驻入口，用于打开设置、查看最近操作、重新运行引导和退出应用。
* 提供原生风格设置窗口，包含 4 个分区：
  * 生效目录：添加目录、移除目录、重新授权。
  * 菜单动作：启用/停用、排序、是否置顶一级菜单、适用场景。
  * 新建文件模板：内置模板、自定义文本模板。
  * 开发者入口：Terminal / VS Code / Cursor 等预置入口。
* 提供首次启动引导，指导用户启用 Finder 扩展、添加授权目录、配置常用目录并试用右键菜单。
* 菜单栏保留“修复右键菜单...”诊断入口，用于重新打开引导或排查 Finder 扩展未生效问题。

### Finder Menu Scope

* Finder Sync Extension 只注册用户已授权的生效目录。
* 右键菜单在授权目录及其子目录内出现。
* Finder 空白处、选中文件/文件夹、工具栏菜单应按场景显示不同 Action。
* 默认提供 `RightTool` 子菜单。
* 支持将单个高频 Action 置顶到 Finder 一级右键菜单。
* MVP 限制最多 5 个一级菜单项，避免污染 Finder 菜单。

### Action Model

* 从 MVP 起使用统一 Action 模型，而不是按功能硬编码菜单。
* Action 至少包含：
  * `id`
  * `title`
  * `kind`
  * `visibility`
  * `placement`
  * `enabled`
  * `order`
  * `payload`
* MVP 需要支持的 `kind`：
  * `openDirectory`
  * `moveToDirectory`
  * `copyToDirectory`
  * `cut`
  * `paste`
  * `createFile`
  * `openInApp`
* 预留但 MVP 不实现的 `kind`：
  * `runCommand`
  * `undoOperation`

### Common Directories

* 区分“前往常用目录”和“移动/复制到常用目录”。
* 右键空白处时显示：
  * 前往常用目录
  * 粘贴到此处
  * 新建文件
* 右键选中文件/文件夹时显示：
  * 移动到常用目录
  * 复制到常用目录
  * 剪切
  * 开发者入口
* Finder 工具栏菜单可显示全局“前往常用目录”和开发者入口。

### Cut / Paste

* MVP 使用 RightTool 工具内剪切板，不打通系统剪贴板。
* 剪切动作记录：
  * 源路径列表
  * 操作类型：move
  * 时间戳
* 粘贴动作在目标目录执行移动。
* 源文件不存在时，跳过对应项目并记录失败原因。
* 粘贴完成后清空成功移动的剪切记录。

### New File

* MVP 支持空文件和文本模板，不做复杂脚手架。
* 内置模板至少包括：
  * 空白文本 `.txt`
  * Markdown `.md`
  * JSON `.json`
  * Git Ignore `.gitignore`
  * Swift 文件 `.swift`
* 用户可配置自定义文本模板：
  * 模板名称
  * 默认文件名
  * 扩展名
  * 文本内容
  * 是否置顶一级菜单
* 暂不支持二进制模板、多文件模板和项目脚手架。

### Developer Entrypoints

* MVP 提供预置开发者入口：
  * Terminal
  * VS Code
  * Cursor
* 入口行为基于当前 Finder 上下文：
  * 选中文件夹时打开该文件夹。
  * 选中文件时打开其所在目录，或按入口能力打开文件。
  * 右键空白处时打开当前目录。
* 自定义命令模板延后到 v1.1。

### File Conflict Handling

* 文件移动、复制、新建遇到同名冲突时弹窗确认。
* 单文件冲突支持：
  * 替换
  * 保留两者
  * 取消
* 默认选项为“保留两者”。
* 多文件冲突的“对后续冲突使用相同选择”延后到 v1.1。

### Operation History

* MVP 记录操作历史，但不实现撤销。
* 每条记录至少包含：
  * 时间
  * 动作类型
  * 源路径
  * 目标路径
  * 成功/失败状态
  * 错误原因
* 菜单栏 App 可查看最近操作。
* 操作历史最多保留最近 500 条。

### Storage

* 使用 App Group 共享容器存储配置和日志。
* MVP 文件结构：

```text
App Group Container
├── config.json
├── bookmarks.json
└── operation-log.jsonl
```

* `config.json` 必须包含 `schemaVersion`。
* 配置写入必须采用原子写入，避免 Finder 扩展读到半截文件。
* Finder Sync Extension 只读配置，不写复杂状态。
* ActionRunner 负责写操作日志。

### Permissions

* MVP 采用用户显式授权目录 + Security-Scoped Bookmark。
* 文件操作只允许发生在已授权目录之间，或已授权目录内部。
* 不要求全盘访问。
* 不执行需要 `sudo` 或管理员权限的动作。
* 不修改系统目录。

## Acceptance Criteria

* [ ] 首次启动时展示引导，并能打开系统设置中的 Finder 扩展启用位置或提供明确步骤。
* [ ] 用户可以添加至少一个生效目录，并保存可恢复的安全书签。
* [ ] Finder Sync Extension 只在授权目录内显示 RightTool 菜单。
* [ ] Finder 空白处和选中文件/文件夹时显示符合场景的菜单项。
* [ ] 用户可以将最多 5 个 Action 置顶到 Finder 一级菜单。
* [ ] 用户可以前往常用目录。
* [ ] 用户可以将选中文件/文件夹移动到常用目录。
* [ ] 用户可以将选中文件/文件夹复制到常用目录。
* [ ] 用户可以剪切文件/文件夹，并粘贴到授权目标目录。
* [ ] 用户可以通过内置模板新建文本文件。
* [ ] Terminal / VS Code / Cursor 入口可以从当前 Finder 上下文打开目标位置。
* [ ] 文件冲突时弹窗确认，默认选择“保留两者”。
* [ ] 所有实际动作通过 XPC ActionRunner 执行，而不是由 Finder Sync Extension 直接执行。
* [ ] 成功和失败动作都写入 `operation-log.jsonl`。
* [ ] 配置文件包含 `schemaVersion`，写入过程为原子写入。
* [ ] App 能展示最近操作历史。

## Definition of Done

* Swift / SwiftUI / AppKit 代码结构清晰，Finder 扩展、主 App、ActionRunner 职责分离。
* 关键文件操作、Action 解析、配置读写、冲突策略有单元测试覆盖。
* 至少完成一次本地构建验证。
* 右键菜单、授权目录、XPC 调用链路经过手动验证。
* 错误提示覆盖未授权目录、源文件不存在、目标冲突、XPC 不可用等关键失败路径。
* 文档或任务记录说明已知限制和后续计划。

## Technical Approach

```text
RightTool.app
├── SwiftUI 设置窗口
├── AppKit 菜单栏入口
├── App Group 配置读写
├── 非特权 XPC ActionRunner
└── FinderSyncExtension.appex
    ├── 注册用户授权目录
    ├── 读取共享配置
    ├── 渲染 Finder 菜单
    └── 通过 XPC 发送 ActionRequest
```

核心链路：

```text
Finder 右键
  → FinderSyncExtension 解析 Finder 上下文
  → 根据 Action 配置生成菜单
  → 用户点击菜单项
  → Extension 通过 XPC 发送 ActionRequest
  → ActionRunner 校验权限和参数
  → 执行文件动作 / 打开开发入口
  → 写入 operation-log.jsonl
  → 必要时通知主 App 展示结果或冲突弹窗
```

## Decision (ADR-lite)

### 1. Finder Integration

**Context**: RightTool 需要在 Finder 右键菜单中提供操作。Apple Finder Sync Extension 原生支持对被监控目录添加上下文菜单，但不是通用 Finder UI 注入机制。

**Decision**: MVP 使用 Finder Sync Extension，并限定在用户配置和授权的目录内生效。

**Consequences**: 方案更符合 macOS 安全模型和分发要求，但不能承诺任意 Finder 位置都有菜单。

### 2. Process Boundary

**Context**: Finder 扩展生命周期和资源约束更严格，不适合承载复杂文件操作、冲突弹窗、日志和权限恢复。

**Decision**: Finder Sync Extension 只负责菜单生成，动作通过 XPC 交给非特权 ActionRunner 执行。

**Consequences**: 工程复杂度高于 URL Scheme 方案，但进程职责更清晰，后续扩展更稳。

### 3. Storage

**Context**: 主 App、Finder 扩展、ActionRunner 都需要共享配置和操作历史。

**Decision**: MVP 使用 App Group 共享容器中的版本化 JSON 配置和 JSONL 操作日志。

**Consequences**: 调试简单、依赖少，但需要严格做好原子写入和 schema 迁移预留。

### 4. MVP Boundary

**Context**: 完整愿景包含自定义命令、撤销、自动更新等能力，但第一版必须先验证核心右键体验。

**Decision**: MVP 聚焦核心右键闭环；自定义命令模板、有限撤销、更多开发 App、多文件冲突批处理和自动更新延后到 v1.1 或后续版本。

**Consequences**: 第一版范围更可控，但 Action 模型需要为后续能力预留扩展点。

## Out of Scope

* 任意 Finder 位置全局生效。
* 全盘访问模式。
* App Store 分发。
* Electron / Tauri 主 App。
* 特权 Helper 或管理员权限操作。
* 系统剪贴板级别的剪切/粘贴打通。
* 自定义命令模板。
* 有限撤销。
* 二进制模板、多文件模板、项目脚手架。
* 多文件冲突“应用到全部”。
* 自动更新。
* 云同步、多工作区配置、复杂规则引擎。

## v1.1 Candidates

* 自定义命令模板，执行前默认确认。
* 对可信命令支持“不再确认”。
* 有限撤销：
  * 移动/剪切粘贴：移回原位置。
  * 新建文件：删除刚创建的文件。
  * 复制文件：删除复制出来的目标文件。
* 更多预置开发 App：iTerm2、Xcode、GitHub Desktop。
* 多文件冲突“对后续冲突使用相同选择”。
* 菜单图标和分组个性化。
* 自动更新。

## Research References

* [`research/apple-platform-constraints.md`](research/apple-platform-constraints.md) — Finder Sync、XPC、App Group 和安全边界的关键平台约束。

## Technical Notes

* Apple Finder Sync 文档强调扩展应注册一个或多个目录，并为这些被监控目录中的项目提供上下文菜单。
* Finder Sync 可以区分选中项目菜单、目录背景菜单、侧边栏菜单和工具栏菜单。
* Finder Sync 扩展可能存在较长生命周期，也可能在 Open/Save 面板中出现额外实例，因此扩展内逻辑应保持轻量。
* XPC 是 macOS 推荐的进程间通信机制之一，适合将执行逻辑隔离到 helper/service。
* 当前 Trellis spec 仍是通用占位说明，后续实现前需要按 Swift/macOS 项目实际结构补充更具体规范。
