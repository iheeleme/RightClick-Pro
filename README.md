# RightClick Pro

[![GitHub stars](https://img.shields.io/github/stars/iheeleme/RightClick-Pro?style=flat-square)](https://github.com/iheeleme/RightClick-Pro/stargazers)
[![GitHub release](https://img.shields.io/github/v/release/iheeleme/RightClick-Pro?style=flat-square)](https://github.com/iheeleme/RightClick-Pro/releases)
[![GitHub issues](https://img.shields.io/github/issues/iheeleme/RightClick-Pro?style=flat-square)](https://github.com/iheeleme/RightClick-Pro/issues)
[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg?style=flat-square)](https://creativecommons.org/licenses/by-nc-sa/4.0/)

一款面向 macOS Finder 的右键菜单效率工具。RightClick Pro 通过 Finder Sync Extension 把常用目录、文件操作、开发工具入口、文件模板和命令模板放进 Finder 右键菜单，并用用户级 XPC ActionRunner 执行真实文件动作与命令运行。

> 当前状态：预览版。项目可以构建本地 App bundle 和 DMG 预览包，但尚未接入 Developer ID 签名与 notarization 公证。

功能：Finder 右键菜单 · 常用目录快捷入口 · 文件剪切/粘贴/移动/复制 · 新建文件模板 · 开发者工具入口 · 命令模板 · 实时命令输出 · 操作历史 · 登录时自动启动 · Finder Extension 修复

官方支持平台：macOS。

---

## 功能概览

### 1. Finder 右键菜单

将高频动作放到 Finder 当前目录、选中文件/文件夹、工具栏等上下文中：

- 全局 Finder Sync 作用域，菜单不再受固定目录白名单限制；
- 菜单项按“常用目录 / 文件操作 / 新建文件 / 开发者工具 / 命令模板”分组；
- 支持一级菜单与分组菜单两种摆放方式；
- Finder Extension 只负责渲染和派发，不直接修改文件。

### 2. 常用目录快捷入口

适合桌面、下载、项目目录、素材目录等高频位置：

- 快速打开指定目录；
- 将选中文件移动到指定目录；
- 将选中文件复制到指定目录；
- 支持通过设置页添加、替换、删除和排序。

### 3. 文件操作

把常用文件动作放进右键菜单：

- 剪切、粘贴；
- 移动、复制；
- 撤销最近一次操作；
- 操作记录写入本地 JSONL，方便回看执行结果。

### 4. 新建文件模板

在当前 Finder 目录快速创建起始文件：

- 内置文本、Markdown、JSON、`.gitignore`、Swift 文件模板；
- 支持自定义模板标题、默认文件名和内容；
- 文件冲突时默认“保留两者”，避免静默覆盖。

### 5. 开发者快捷入口

面向开发者工作流的 App 快速打开能力：

- 内置 Terminal、Visual Studio Code、Cursor 等入口；
- 支持自定义 macOS App；
- 可按当前目录、选中项或动态上下文打开目标；
- 对常见开发工具优先使用其 CLI 启动方式。

### 6. 命令模板

在当前 Finder 上下文执行预设命令：

- 支持当前目录或选中项所在目录作为工作目录；
- 命令输出窗口实时展示 stdout/stderr；
- 支持停止运行、超时处理和最终状态记录；
- 敏感环境变量存入 macOS Keychain。

### 7. 权限与修复入口

RightClick Pro 不安装特权 Helper，也不会静默请求系统权限：

- 文件动作以当前用户身份执行；
- macOS 拒绝访问时，会提示前往 Full Disk Access；
- 不通过读取 Mail、Messages、Safari、TCC 或 Group Containers 来探测权限；
- 设置页提供 Finder Extension 注册、修复和重启 Finder 的入口。

---

## 安装

### 选项 A：从 Releases 下载 DMG

前往 [GitHub Releases](https://github.com/iheeleme/RightClick-Pro/releases) 下载最新预览包。

1. 打开 DMG。
2. 将 `RightClick Pro.app` 拖到 `/Applications`。
3. 从 `/Applications` 启动 `RightClick Pro`。
4. 首次启动时，App 会自动注册随包附带的 Finder Extension，并可能重启 Finder 一次。
5. 如果系统要求手动确认，请前往“系统设置 > 隐私与安全性 > 扩展 > Finder 扩展”启用 RightClick Pro。

如果 macOS 提示应用无法打开或已损坏，可在本地测试时清理 quarantine：

```bash
xattr -cr "/Applications/RightClick Pro.app"
```

### 选项 B：本地开发安装

```bash
scripts/package-macos.sh debug
rm -rf "/Applications/RightClick Pro.app"
ditto "dist/staging/RightClick Pro.app" "/Applications/RightClick Pro.app"
xattr -cr "/Applications/RightClick Pro.app"
open "/Applications/RightClick Pro.app"
```

安装到 `/Applications` 后，由 App 在运行时注册内置 Finder Extension。默认不会注册 `dist/staging` 中的构建产物，避免 Finder 把源码目录里的临时 App 当作真实应用。

---

## 常见问题排查

### Finder 右键菜单没有出现？

1. 确认 App 位于 `/Applications/RightClick Pro.app`。
2. 打开系统设置中的 Finder 扩展页，确认 RightClick Pro Finder Extension 已启用。
3. 打开 RightClick Pro 设置页，在概览中使用“修复并重启 Finder”。
4. 仍未出现时，可手动运行：

```bash
killall Finder
```

### macOS 提示需要完全磁盘访问权限？

文件动作和命令模板由 macOS 权限系统决定是否能访问目标路径。请前往：

```text
系统设置 > 隐私与安全性 > 完全磁盘访问权限
```

允许 `RightClick Pro` 后重试。RightClick Pro 不会为了检测权限而主动读取其他 App 的数据目录。

### macOS 提示“想访问其他 App 的数据”？

新版运行时状态默认写入：

```text
~/Library/Application Support/com.iheeleme.rightclickpro
```

它不会默认读取 `~/Library/Group Containers`，也不会读取 Mail、Messages、Safari 或 TCC 数据。若你从旧版本升级后仍看到提示，请完全退出 RightClick Pro、重启 Finder 后再安装最新包。

### 应用提示未公证或无法验证开发者？

当前预览包尚未接入 Developer ID 签名和 notarization 公证。你可以在“系统设置 > 隐私与安全性”中选择仍要打开，或在本地测试时清理 quarantine。

---

## 开发与构建

### 前置要求

- macOS 14 Sonoma 或更新版本；
- Swift 6 工具链；
- 本地打包需要系统可用的 `codesign`、`sips`、`iconutil`。

### 运行检查

```bash
scripts/ci-swift-check.sh debug
```

### 构建设置 App target

```bash
swift build --target RightClickProAppPreview
```

### 构建本地预览 App bundle

```bash
scripts/package-macos.sh debug
```

### 构建本地预览 DMG

```bash
RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh release
```

### 本地 Finder Sync smoke test

```bash
RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1 scripts/package-macos.sh debug
```

---

## 架构

```text
Finder
  -> RightClickProFinderExtension
  -> NSXPCConnection
  -> RightClickProActionRunner.xpc
  -> RightClickProCore
```

项目主要分为四个 target：

- `RightClickProCore`：共享模型、菜单构建、存储、文件操作、命令执行、操作日志和 XPC 合约。
- `RightClickProFinderExtension`：读取配置并渲染 Finder 菜单，不直接修改文件。
- `RightClickProActionRunnerService`：XPC 服务入口，把请求交给 Core 层 ActionRunner。
- `RightClickProAppPreview`：菜单栏 App、设置窗口和命令运行窗口。

运行时状态默认写入真实用户目录：

```text
~/Library/Application Support/com.iheeleme.rightclickpro
├── config.json
├── bookmarks.json
├── cut-clipboard.json
├── operation-log.jsonl
├── pending-command-run.json
├── command-runs/
└── icon-cache/
    └── v1/
```

更多架构细节见 [docs/architecture.md](docs/architecture.md)，GitHub Actions 打包说明见 [docs/github-actions-packaging.md](docs/github-actions-packaging.md)。

---

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
design/
└── icon.png
```

---

## 贡献

欢迎提交 issue 和 pull request。改动时建议遵守现有边界：

- 共享模型和执行逻辑放在 `RightClickProCore`；
- Finder 菜单渲染放在 `RightClickProFinderExtension`；
- 设置 UI 和 AppKit/SwiftUI 表现层放在 `RightClickProAppPreview`；
- XPC service 入口保持轻量。

如果新增或修改一种 Finder action kind，通常需要同步更新模型、菜单投影、执行逻辑、设置页展示和测试。

提交前建议至少运行：

```bash
git diff --check
scripts/ci-swift-check.sh debug
```

如果改到 Finder Extension、XPC、entitlements 或打包逻辑，还需要运行：

```bash
scripts/package-macos.sh debug
```

---

## 致谢

感谢[LinuxDo](https://linux.do/)社区，真诚、友善、团结、专业，共建你我引以为荣之社区。

感谢 macOS Finder Sync、SwiftUI、Swift Package Manager 生态，以及所有为开发者效率工具提供思路的开源项目。

---

## 许可证

本项目默认采用 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/) 许可协议（署名-非商业性使用-相同方式共享）。

- 允许：个人学习、研究、非商业场景下的使用、修改与分享，需保留署名并遵循相同协议分享要求。
- 不允许：任何未获授权的商业使用，包括但不限于企业内部商业目的、对外商业服务、付费产品集成、二次分发售卖等。
- 商业授权：如需商业使用，请先联系项目维护者获取单独书面授权。

---

## 免责声明

本项目仅供个人学习、研究和非商业使用。使用本项目即表示你同意：

- 未获得维护者书面商业授权前，不将本项目用于任何商业用途；
- 自行承担安装、运行、修改和分发本项目产生的风险与责任；
- 遵守 macOS、Finder Extension、相关第三方服务条款和所在地法律法规。

项目维护者不对因使用本项目而产生的任何直接或间接损失承担责任。
