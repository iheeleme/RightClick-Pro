# Kimi 风格设置界面优化

## 目标

参考 Kimi 官网与 `kimi-design-spec`，优化 RightClick Pro 的原生 macOS 设置界面。用户已连续确认继续实施，按现有功能与 SwiftUI 组件边界直接完成视觉调整。

## 需求

- 统一亮色、暗色语义主题：中性色背景与文字、Kimi 蓝选中态、黑白主操作。
- 优化侧栏密度、标题层级、按钮、搜索焦点、筛选与表格行反馈。
- 概览采用简洁的功能入口和真实配置统计，减少装饰与无操作能力的开关。
- 保留现有配置命令、保存入口、编辑弹窗、菜单预览与已有工作区修改。
- 沿用 SF Symbols、AppKit 图标与本地品牌图片。

## 验收

- [x] 亮色/暗色主题协调，无紫蓝渐变大面积背景。
- [x] 设置页、搜索筛选、弹窗与保存状态布局清晰，无文字重叠。
- [x] Swift 备用编译、预览打包与 diff 检查通过。
- [x] 打开原生应用验证概览、菜单管理、模板、开发者入口、命令模板和编辑校验。

## 验证记录

- `DIST_DIR=dist/kimi-style-preview APP_NAME='RightClick Pro Kimi Preview' ... scripts/package-macos.sh debug` 通过；备用 `swiftc` 目标为 `arm64-apple-macosx14.0`。
- `codesign --verify --deep --strict` 通过；预览包为 ad-hoc 签名，包含 Finder Extension 与 ActionRunner。
- 原生隔离预览分别检查亮色、暗色、搜索清除、空模板名称校验、列表和 Finder 菜单预览。
- `swift build` / `scripts/ci-swift-check.sh debug` 仍受本机 SwiftPM manifest 链接错误阻塞，未修改项目清单；备用打包路径已完成同等应用目标编译。

## 技术决策

- 使用现有 `SettingsTheme` 与共享组件，避免引入依赖或网页重写。
- 主题适配 Kimi 的 `#1783FF` 品牌蓝、白/浅灰背景与分层文字；暗色模式使用中性灰。
- 保留 Finder 预览的 macOS 菜单形态；应用外壳使用扁平布局和细分割线。
- 以编译、现有测试和原生 UI 检查验证纯呈现调整，不新增镜像实现的样式单元测试。

## 范围

调整 `Sources/RightClickProAppPreview/` 的呈现层；不修改 Core 数据合约、权限、Finder 扩展或安装到系统应用目录。

## 参考

- https://www.kimi.com/（2026-09-05 实际访问：暗色中性基底、简洁工具栏、细边框输入区、黑白按钮）
- `/Users/iheeleme/.codex/skills/kimi-design-spec/SKILL.md`
- `.trellis/spec/frontend/component-guidelines.md`
- `.trellis/spec/frontend/quality-guidelines.md`
