# RightClick Pro

RightClick Pro 是一款原生 macOS Finder 右键菜单效率工具，面向开发者和高频文件操作用户。它通过 Finder Sync Extension 在 Finder 右键菜单里提供可配置动作，并把真正的文件操作、命令执行和日志记录交给用户级 XPC ActionRunner 处理。

> 当前状态：预览版。项目已经可以生成本地和 GitHub Actions 的 DMG 产物，但尚未完成 Developer ID 签名和 notarization 公证。

## 功能特性

- 全局 Finder 右键菜单，基于 Finder Sync Extension。
- 常用目录快捷入口，支持快速打开、移动到、复制到。
- 文件操作：剪切、粘贴、复制、移动、新建文本文件。
- 内置文件模板：文本、Markdown、JSON、`.gitignore`、Swift 文件。
- 开发者快捷入口：Terminal、VS Code、Cursor，以及自定义 macOS App。
- 命令模板：支持实时 stdout/stderr 输出、停止控制、超时处理和操作历史。
- 敏感命令环境变量存入 macOS Keychain。
- 操作历史以 JSONL 存储在本机。
- 支持“登录时自动启动”。
- 设置页内置 Full Disk Access 引导和 Finder Extension 修复入口。

## 为什么做这个项目

Finder 自带右键菜单很好用，但并不围绕开发者的重复工作流设计。RightClick Pro 想把这些常见动作放到离手最近的位置：

- 在当前目录打开开发工具；
- 把选中文件移动或复制到常用目录；
- 在当前目录快速创建一个起始文件；
- 对当前目录或选中文件运行预设命令；
- 操作失败后查看最近文件动作和命令历史。

## 系统要求

- macOS 14 Sonoma 或更新版本。
- 开发构建需要 Swift 6 工具链。
- 文件动作和命令模板建议授予 Full Disk Access。
- 需要在系统设置中启用 Finder Extension。

## 安装

### 通过 DMG 安装

GitHub Actions 打包产物目前是 DMG-only 预览包。

1. 打开 DMG。
2. 将 `RightClick Pro.app` 拖到 `/Applications`。
3. 从 `/Applications` 启动 `RightClick Pro`。
4. 如果 macOS 因为未公证而阻止打开，本地测试时可以清理 quarantine：

```bash
xattr -cr "/Applications/RightClick Pro.app"
```

5. 再次打开 App。App 会尝试注册随包附带的 Finder Extension，并在首次设置时重启 Finder 一次。
6. 如果 Finder 右键菜单没有出现，打开 RightClick Pro 设置页，使用 Finder Extension 修复入口。

### 本地开发安装

```bash
scripts/package-macos.sh debug
rm -rf "/Applications/RightClick Pro.app"
ditto "dist/staging/RightClick Pro.app" "/Applications/RightClick Pro.app"
xattr -cr "/Applications/RightClick Pro.app"
open "/Applications/RightClick Pro.app"
```

安装到 `/Applications` 后，App 自己负责运行时 Finder Extension 注册。默认不会注册 `dist/staging` 里的构建产物，避免 Finder 把源码目录里的 staging app 当作真实应用显示。

## 从源码构建

运行核心检查：

```bash
scripts/ci-swift-check.sh debug
```

构建预览 App target：

```bash
swift build --target RightClickProAppPreview
```

构建本地预览 App bundle：

```bash
scripts/package-macos.sh debug
```

构建本地预览 DMG：

```bash
RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh release
```

## 架构

```text
Finder
  -> RightClickProFinderExtension
  -> NSXPCConnection
  -> RightClickProActionRunner.xpc
  -> RightClickProCore
```

项目主要分成四个 target：

- `RightClickProCore`：共享模型、菜单构建、存储、文件操作、命令执行、操作日志和 XPC 合约。
- `RightClickProFinderExtension`：读取共享配置并渲染 Finder 菜单，不直接修改文件。
- `RightClickProActionRunnerService`：XPC 服务入口，把请求交给 Core 层 ActionRunner。
- `RightClickProAppPreview`：菜单栏 App、设置窗口，以及命令运行窗口。

运行时状态优先写入 App Group 容器；未签名或本地预览构建无法使用 App Group 时，会回退到 Application Support：

```text
App Group Container
├── config.json
├── bookmarks.json
├── cut-clipboard.json
├── operation-log.jsonl
├── pending-command-run.json
├── command-runs/
└── icon-cache/
    └── v1/
```

更多架构细节见 [docs/architecture.md](docs/architecture.md)。

## 安全与权限

RightClick Pro 不安装特权 Helper。文件操作和命令模板通过随 App 打包的 XPC service 以当前用户身份执行。

Finder 菜单全局可见，但真实执行仍受 macOS 权限控制。若 macOS 拒绝访问，RightClick Pro 会提示 Full Disk Access，而不是用自定义目录白名单假装拥有权限。

命令模板采用“预先保存模板”的方式，不支持在 Finder 右键菜单里临时输入任意命令。

## 打包说明

当前预览包由 Swift Package 手动组装，还不是完整 Xcode App 工程。打包结构大致如下：

```text
RightClick Pro.app
├── Contents/PlugIns/RightClickProFinderExtension.appex
│   └── Contents/XPCServices/RightClickProActionRunner.xpc
└── Contents/XPCServices/RightClickProActionRunner.xpc
```

如果系统存在 `codesign`，预览包会进行 ad-hoc 签名。公开分发前仍需要补齐完整 Xcode project、Developer ID 签名和 notarization 公证。

CI 打包细节见 [docs/github-actions-packaging.md](docs/github-actions-packaging.md)。

## 仓库结构

```text
Sources/
├── RightClickProCore/
├── RightClickProFinderExtension/
├── RightClickProActionRunnerService/
└── RightClickProAppPreview/
Tests/
└── RightClickProCoreTests/
scripts/
├── ci-swift-check.sh
└── package-macos.sh
docs/
├── architecture.md
└── github-actions-packaging.md
```

## 开发流程

提交改动前至少运行：

```bash
git diff --check
scripts/ci-swift-check.sh debug
```

如果改到设置 UI、Finder Extension、XPC、entitlements 或打包逻辑，还需要运行：

```bash
scripts/package-macos.sh debug
```

如果想对 staging bundle 做一次本地 Finder Sync smoke test：

```bash
RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
```

## 已知限制

- 预览构建尚未 Developer ID 签名或 notarization 公证。
- 项目目前仍是 SwiftPM-first，尚未加入完整 Xcode App 工程。
- Finder Sync 可能需要用户在系统设置中手动启用。
- Full Disk Access 是用户控制的系统权限，App 可以引导和检测，但不能静默为自己授权。
- 当前文件冲突策略默认“保留两者”，更完整的冲突确认 UI 还在后续计划中。
- 仓库还没有补充开源许可证文件。

## 参与贡献

欢迎提交 issue 和 pull request。改动时请尽量遵守现有 target 边界：

- 共享合约和执行逻辑放在 `RightClickProCore`；
- Finder 菜单渲染放在 `RightClickProFinderExtension`；
- 设置 UI 和 SwiftUI/AppKit 表现层放在 `RightClickProAppPreview`；
- XPC service 入口保持轻薄。

如果新增或修改一种 Finder action kind，通常需要同时更新模型、菜单投影、执行逻辑、设置页展示和测试。

## 许可证

当前仓库还没有 `LICENSE` 文件。在正式添加许可证之前，可以把源码视为可阅读、可评审、可协作，但尚未明确授权再分发或商业复用。
