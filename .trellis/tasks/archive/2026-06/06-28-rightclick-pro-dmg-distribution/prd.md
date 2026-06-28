# RightClick Pro DMG Distribution Engineering

## Goal

把当前开发阶段的 macOS 分发链路工程化：在现有预览包构建基础上，增加可选的内测 DMG 产物，并把用户可见产品名改为 `RightClick Pro`。这条链路优先服务自用/内测稳定分发，不处理正式签名、公证、自动更新或旧 RightTool 数据迁移。

## What I Already Know

* 当前项目已有 `scripts/package-macos.sh`，可以构建 SwiftPM preview bundle、嵌入 Finder Sync extension、嵌入 ActionRunner XPC、ad-hoc 签名并输出 zip。
* 当前 GitHub Actions 工作流 `.github/workflows/package-macos.yml` 支持手动 dispatch、tag、PR packaging checks，并上传 `dist/*.zip`。
* 当前默认产品名和内部命名为 `RightTool`，默认 bundle/app group 为 `com.righttool.app` / `group.com.righttool.app`。
* 用户已确认：这是开发阶段，可以把 `RightClick Pro` 当作新 App，不迁移旧 RightTool 配置，也不处理旧版残留。
* 用户先前确认：Swift target/module/type 暂时保留 `RightTool*`，只改用户可见命名、bundle id、App Group、产物命名和分发文档。
* 范围变更：用户随后要求“优化代码中名字和项目名不一致的历史遗留问题”，并确认继续执行批量重命名。因此当前实现范围扩大为：Swift package、target、module、source/test 目录、public project types、脚本 env key、内部 appex/xpc/dylib 产物名统一改为 `RightClickPro*` / `rightclickpro-*` / `RIGHTCLICKPRO_*`。

## Requirements

* 分发阶段定位为内测/自用稳定分发。
* 新增内测可用 DMG 产物。
* DMG 构建集成进 `scripts/package-macos.sh`，不新增独立构建体系。
* DMG 必须显式开启：
  ```bash
  RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh release
  ```
* DMG 使用压缩只读 `UDZO` 格式。
* DMG 内容：
  * `RightClick Pro.app`
  * `/Applications` alias
  * `README.txt`
* DMG 命名规则：
  ```text
  RightClick Pro-<version>-<arch>-preview.dmg
  ```
* zip 命名和 app bundle 用户可见命名也应转为 `RightClick Pro`。
* 默认技术命名空间改为：
  ```text
  BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro
  XPC_BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro.ActionRunner
  FINDER_EXTENSION_BUNDLE_IDENTIFIER=com.iheeleme.rightclickpro.FinderExtension
  APP_GROUP_IDENTIFIER=group.com.iheeleme.rightclickpro
  ```
* 不做 Developer ID 签名和 notarization，继续使用 ad-hoc 签名。
* `README.txt` 必须说明：
  * 拖拽安装到 Applications。
  * 这是内测构建，未 Developer ID 签名/未公证。
  * 如果 macOS 拦截打开，如何通过系统设置/右键打开兜底。
  * 如何启用 Finder Extension。
  * Finder 右键菜单不出现时如何重启 Finder 或重新打开右键菜单。
* GitHub Actions 手动 dispatch 增加可选 `package_dmg` 输入；启用时设置 `RIGHTCLICKPRO_PACKAGE_DMG=1` 并上传 `.dmg`。
* App 首页/概览顶部增加 Finder 扩展启用提示入口：
  * 主按钮：打开扩展相关系统设置页。
  * 次级按钮：重启 Finder。
  * 重启 Finder 操作必须明确说明会短暂重启 Finder。
* 不检测 Finder Extension 启用状态。
* 打包脚本只产出 artifact，不自动安装到 `/Applications`。

## Acceptance Criteria

* [ ] `RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh debug` 产出 zip 和 DMG。
* [ ] DMG 文件名符合 `RightClick Pro-<version>-<arch>-preview.dmg`。
* [ ] DMG 可挂载，包含 `RightClick Pro.app`、`Applications` alias、`README.txt`。
* [ ] `RightClick Pro.app` 的用户可见 bundle name/window/menu bar 文案使用 `RightClick Pro`。
* [ ] App bundle id、XPC bundle id、Finder Extension bundle id、App Group 使用 `com.iheeleme.rightclickpro` 命名空间。
* [ ] `scripts/package-macos.sh debug` 在未开启 DMG 时仍产出原有 zip，并保持 Finder extension/XPC 校验。
* [ ] GitHub Actions 手动 dispatch 可选择是否产出 DMG。
* [ ] App 概览页有 Finder 扩展启用提示、打开系统设置按钮、重启 Finder 次级按钮。
* [ ] README 覆盖安装、未公证提示、启用 Finder Extension、菜单不出现时的处理。

## Definition of Done

* `git diff --check` passes.
* `bash -n scripts/ci-swift-check.sh scripts/package-macos.sh` passes.
* Workflow YAML can be parsed:
  ```bash
  ruby -e 'require "yaml"; YAML.load_file(".github/workflows/package-macos.yml")'
  ```
* `scripts/package-macos.sh debug` passes.
* `RIGHTCLICKPRO_PACKAGE_DMG=1 scripts/package-macos.sh debug` passes.
* `codesign --verify --deep --strict --verbose=2 dist/staging/RightClick Pro.app` or equivalent staged app validation passes.
* DMG mount smoke test passes locally with `hdiutil attach` / `hdiutil detach`.
* Swift compile/check runs as far as local toolchain allows; known SwiftPM manifest linker issue should be recorded separately if still present.
* Docs/spec updated if packaging contracts change.

## Technical Approach

Extend the existing packaging path instead of building a second distribution pipeline.

```text
scripts/package-macos.sh
  -> build staged RightClick Pro.app
  -> validate app / Finder extension / XPC / codesign
  -> zip preview artifact
  -> if RIGHTCLICKPRO_PACKAGE_DMG=1:
       create temporary DMG root
       copy RightClick Pro.app
       add Applications alias
       write README.txt
       hdiutil create -format UDZO
       hdiutil attach smoke check
```

App UI work should stay focused: add an overview callout with user guidance and two actions. Do not add extension state detection or automatic enablement.

## Decision (ADR-lite)

**Context**: The project needs a practical inner-loop distribution path before formal Developer ID signing/notarization is ready. At the same time, the product name should move from `RightTool` to `RightClick Pro`.

**Decision**: Build an opt-in internal DMG artifact in the existing macOS packaging script. Rename user-facing product and bundle identifiers to `RightClick Pro` / `com.iheeleme.rightclickpro`. After the later scope change, also rename Swift target/module/type names and internal package artifacts to the `RightClickPro*` family.

**Consequences**: Inner-loop distribution becomes easier and CI can produce a DMG on demand. Existing RightTool installs/configs are treated as unrelated development-era artifacts. Source-level naming is now aligned to `RightClickPro*`; a future task can still handle signing/notarization, auto-update, or install diagnostics.

## Out of Scope

* Developer ID signing.
* Notarization.
* Sparkle or any automatic update system.
* Migrating old `RightTool` config, bookmarks, operation logs, App Group data, or TCC permissions.
* Uninstalling or disabling old RightTool builds/extensions.
* Migrating old source-level compatibility aliases for `RightTool*` symbols.
* Finder Extension enabled-state detection.
* Automatic Finder Extension enablement.
* Auto-installing DMG/package output to `/Applications`.
* Product-grade branded DMG background/layout.

## Technical Notes

* Likely touched files:
  * `scripts/package-macos.sh`
  * `.github/workflows/package-macos.yml`
  * `docs/github-actions-packaging.md`
  * `docs/architecture.md`
  * `Sources/RightClickProCore/ActionModels.swift`
  * `Sources/RightClickProCore/Storage.swift`
  * `Sources/RightClickProAppPreview/RightClickProAppPreview.swift`
  * `.trellis/spec/backend/quality-guidelines.md`
  * `.trellis/spec/frontend/component-guidelines.md`
* Relevant specs:
  * `.trellis/spec/backend/index.md`
  * `.trellis/spec/backend/quality-guidelines.md`
  * `.trellis/spec/backend/directory-structure.md`
  * `.trellis/spec/backend/error-handling.md`
  * `.trellis/spec/frontend/index.md`
  * `.trellis/spec/frontend/component-guidelines.md`
  * `.trellis/spec/frontend/state-management.md`
  * `.trellis/spec/frontend/quality-guidelines.md`
* Important risks:
  * Product name contains a space; shell paths and artifact names must be quoted.
  * Changing App Group means development-era data will start clean by design.
  * Changing Finder Extension bundle id requires enabling the new extension in System Settings.
  * macOS System Settings deep links vary; README must include manual fallback instructions.
