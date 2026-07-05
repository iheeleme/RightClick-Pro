# Add Project Screenshots to README

## Goal

在 README 中加入真实的本地项目截图，让访问者在阅读功能说明前先看到 RightClick Pro 的实际界面状态。

## What I already know

* 用户要求“增加项目截图到 README 中”，并明确要求使用 Computer Use 进行本地项目截图。
* README 当前以项目介绍、功能列表和功能概览开头，适合在简介和“功能概览”之间插入截图区域。
* 仓库已有 `design/` 图片，但本任务要求使用本地项目截图，因此不复用旧设计图作为 README 主截图。

## Assumptions

* MVP 只添加一张主界面截图，避免 README 过长。
* 截图资源放在 `docs/assets/`，便于文档资源集中管理。
* 截图以 PNG 保存，README 使用相对路径引用，保证 GitHub 可直接渲染。

## Requirements

* 使用 Computer Use 打开或读取本地 RightClick Pro 界面状态。
* 保存一张真实项目截图到仓库文档资源目录。
* 在 README 的项目介绍和功能概览之间新增截图展示区域。
* 截图说明文字保持简洁，和当前中文 README 风格一致。

## Acceptance Criteria

* [ ] README 中可以看到项目截图 Markdown 引用。
* [ ] 被引用的截图文件存在于仓库中。
* [ ] 截图来自本地运行的项目界面，而不是占位图或旧设计图。
* [ ] README 链接路径有效。
* [ ] 工作区最终只包含本任务相关变更。

## Definition of Done

* README 和截图资源完成更新。
* 通过本地命令验证 README 引用的图片文件存在。
* 检查 git diff，确认变更范围清晰。

## Technical Approach

1. 构建或打开本地 `RightClick Pro.app`。
2. 使用 Computer Use 读取应用窗口并确认截图内容。
3. 保存截图到 `docs/assets/rightclick-pro-overview.png`。
4. 修改 README，在简介后插入“项目截图”小节。

## Decision (ADR-lite)

**Context**: README 需要更直观地展示项目，但仓库当前只有设计图，没有 README 中引用的真实运行截图。

**Decision**: 添加一张本地运行的设置主界面截图作为 README 主截图。

**Consequences**: README 更直观；后续 UI 大改时需要同步更新截图。

## Out of Scope

* 不添加多图画廊。
* 不重新设计 README 结构。
* 不修改应用代码或截图专用 UI。

## Technical Notes

* README: `README.md`
* 目标资源目录: `docs/assets/`
* 本地应用 target: `RightClickProAppPreview`
