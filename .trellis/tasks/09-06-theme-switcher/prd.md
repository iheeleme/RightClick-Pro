# 设置主题切换

## 目标

在 RightClick Pro 设置窗口增加主题偏好，让用户可以选择跟随系统、浅色或深色模式，并在切换后立即看到界面变化。

## 需求

- 在概览页“应用设置”中提供三段式主题选择控件。
- 主题选项为“跟随系统”“浅色”“深色”，使用原生 SwiftUI 分段控件。
- 选择结果持久化到 `UserDefaults`，下次启动继续使用。
- 主题切换只影响设置窗口界面，不修改 RightClick Pro 配置 JSON，也不影响 Finder 扩展业务逻辑。
- 设置窗口的 SwiftUI `ColorScheme` 与 AppKit 窗口外观保持一致。
- 亮色、暗色主题继续使用现有 Kimi 中性表面和蓝色强调色。

## 验收

- [x] 三种主题可在概览页选择并即时切换。
- [x] 选择结果存入 `UserDefaults`，主题偏好可跨启动恢复。
- [x] 亮色和暗色下文字、控件、预览和侧栏均有足够对比度。
- [x] 严格 Swift 类型检查、预览打包和 `git diff --check` 通过。

## 范围

调整 `Sources/RightClickProAppPreview/RightClickProAppPreview.swift`、`SettingsRootViews.swift` 和 `OverviewViews.swift` 的呈现与界面偏好状态；不修改 Core 数据模型、Finder 扩展或 ActionRunner。

## 验证记录

- 严格 Swift 6 直接类型检查通过，目标为 `arm64-apple-macosx14.0`，启用完整并发检查和 warnings-as-errors。
- 备用预览打包通过，预览 App 的代码签名和 plist 校验通过。
- 隔离原生预览验证浅色 → 深色 → 浅色的即时切换，三种主题选项均出现在无障碍树中。
- `swift build --target RightClickProAppPreview` 仍受本机 `PackageDescription.Package` 缺少 `swiftLanguageVersions` 初始化符号的工具链链接错误阻塞。
