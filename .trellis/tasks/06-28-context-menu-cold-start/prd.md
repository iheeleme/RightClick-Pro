# Fix delayed context menu registration

## Goal

修复 Finder 右键菜单在安装后首次使用、以及扩展长时间空闲后再次右键时，不能稳定直接显示 RightClick Pro 菜单的问题。目标是降低 Finder Sync 冷启动路径中的同步 IO 和图标解析成本，让首次菜单回调尽快返回可用菜单。

## What I Already Know

* 用户反馈：部分场景下右键没有直接加载出扩展菜单，安装后首次右键和长时间不右键后的首次右键都存在。
* `FinderSyncController` 在初始化时设置全局 scope、同步加载配置，并在后台修复配置。
* `menu(for:)` 当前会同步构建完整 `NSMenu`，并为每个菜单项解析图标。
* 冷启动时 `iconCache` 为空，应用图标会通过 `NSWorkspace.urlForApplication` 和 `NSWorkspace.icon` 同步解析。
* `docs/architecture.md` 已记录 Finder 可能在长时间空闲后冷启动 Finder Sync 扩展，菜单请求应依赖缓存而不是阻塞式磁盘/bootstrap 工作。
* 安装后 app 会通过 ActionRunner 注册/启用 Finder Extension，并重启 Finder 一次。

## Assumptions

* Finder 对 Finder Sync 菜单回调有较敏感的时延窗口，冷启动同步工作过多时本次菜单贡献可能被跳过。
* 右键菜单优先要“本次就出现”，真实应用图标可以异步加载；缓存未命中时必须立即显示默认占位图标。
* 自定义配置仍应尽量在首次菜单中生效；如果读取失败，应至少返回安全的默认菜单，而不是 `nil`。

## Requirements

* Finder Sync 冷启动路径必须尽量快，`menu(for:)` 不应同步解析昂贵的应用/文件图标。
* 首次菜单请求在缓存未完全刷新或磁盘读取失败时，应有可用的 fallback 配置。
* 后台刷新仍要保留，设置页保存后的配置应在下一次右键附近自动更新。
* 保持 Finder Extension 只渲染菜单，不执行文件变更的边界。
* 增加可测试的核心逻辑覆盖，避免菜单图标解析策略回退。
* 真实应用/文件路径图标使用 `NSWorkspace.shared.icon(forFile:)`，但只能在异步队列中解析并缓存，不能阻塞 Finder 菜单回调；缓存应同时覆盖内存和持久化 PNG，以便扩展重启后仍可异步恢复。

## Acceptance Criteria

* [ ] 安装并完成 Finder Extension 自动修复后，首次右键应能直接看到 RightClick Pro 菜单。
* [ ] Finder Sync 扩展长时间空闲后被冷启动，首次右键应能直接看到菜单。
* [x] `menu(for:)` 不再对应用 bundle、文件路径图标做冷路径同步解析。
* [x] 配置/书签读取失败时，扩展不会因为 `hasLoadedConfiguration == false` 直接返回 `nil`。
* [x] Swift 单元测试覆盖新增菜单图标策略或 fallback 行为。
* [ ] `scripts/ci-swift-check.sh debug` 通过，必要时补充 packaging 验证。
* [x] app 图标缓存未命中时显示默认缺省图标，并在后台异步解析真实图标。

## Definition of Done

* Tests added/updated where appropriate.
* Lint/typecheck/project check green.
* Architecture notes updated if Finder Sync cold-start contract changes.
* Rollback risk considered.

## Technical Approach

优先把冷路径从“同步解析所有图标”改为“快速返回菜单，使用轻量图标或延迟/后台预热”。同时让 `FinderSyncController` 在启动时总能落到默认配置，避免启动/bootstrap 失败导致本次右键直接没有菜单。

## Decision (ADR-lite)

**Context**: 安装后和长时间空闲后的首次右键都具有冷启动特征，缓存为空且 Finder Sync 回调必须快速返回。

**Decision**: 保持菜单数据缓存，但移除冷路径上的昂贵图标解析；应用/文件路径图标缓存未命中时先显示默认或轻量 placeholder，不在菜单回调内启动真实图标解析；等用户停止打开菜单一段时间后，再通过低优先级后台串行队列调用 `NSWorkspace.shared.icon(forFile:)` 解析真实图标并写入内存缓存；配置刷新也延后到菜单返回后执行；增加启动 fallback 配置；后台继续刷新真实配置。

**Follow-up Decision**: 真实图标预渲染成 16px 菜单 PNG 后写入 `icon-cache/v1`。扩展启动并加载配置后，后台异步读取这些 PNG 进入内存；菜单回调仍然只读取内存缓存，不做磁盘 IO。

**Consequences**: 首次菜单可能使用更保守的图标展示，但稳定性优先。真实图标可在后续右键或后台预热中恢复。

## Out of Scope

* 不重做 Finder Extension 注册/启用整体流程。
* 不新增用户可见的手动修复流程。
* 不改变菜单动作执行、XPC、Full Disk Access 权限模型。
* 不引入 npm 图标库或静态 SVG 资源作为运行时依赖。

## Technical Notes

* Relevant files:
  * `Sources/RightClickProFinderExtension/FinderSyncController.swift`
  * `Sources/RightClickProCore/MenuBuilder.swift`
  * `Sources/RightClickProCore/ConfigurationBootstrapper.swift`
  * `Sources/RightClickProCore/ActionModels.swift`
  * `Sources/RightClickProCore/SystemMaintenance.swift`
  * `docs/architecture.md`
* Relevant specs:
  * `.trellis/spec/backend/index.md`
  * `.trellis/spec/backend/quality-guidelines.md`
  * `.trellis/spec/backend/error-handling.md`
  * `.trellis/spec/backend/logging-guidelines.md`
* Verification notes:
  * Follow-up optimization after user still observed second-menu delay: moved startup config/bookmark reads off the Finder Sync extension `init()` cold path and changed menu icon rendering to cached-only. Missing icons are omitted; lightweight icons are prewarmed only after a no-menu idle window, and new menu requests cancel pending prewarm work.
  * Icon safety diagnosis: current Finder menu callback does not read real app icons, arbitrary file path icons, folder icons, or extension type icons from `NSWorkspace` on cache misses. It uses SF Symbol placeholders, then resolves real icons later on a low-priority background queue. The mode performs bounded metadata/resource reads and in-memory caching, so it should not meaningfully affect SSD/HDD wear.
  * Built-in icon mode was abandoned after visual validation issues. Current mode uses default/lightweight icons in the menu callback, then resolves real app/file icons asynchronously with `NSWorkspace.shared.icon(forFile:)` and in-memory caching.
  * Follow-up after user still observed slow loading: menu callback now does not start icon resolution or config refresh. It returns cached real icons or SF Symbol placeholders only; queued icon prewarm is canceled on each new menu request, then restarted after a longer no-menu idle window on a low-priority background queue.
  * Follow-up after user observed third open stalls when real icons appear: raw `NSWorkspace` icon `NSImage` objects are now rasterized into 16px menu-ready bitmap images before being cached. Later menus should not become the first AppKit/ICNS draw/decode point.
  * Follow-up persistent cache mode: prepared menu icons are written as PNG files under `icon-cache/v1` using hashed cache keys. Existing PNGs are loaded asynchronously into memory after config load; menu rendering never blocks on disk cache reads.
  * `scripts/package-macos.sh debug` passed via its direct `swiftc` fallback and validated the app, Finder appex, XPC, and Core dylib signatures.
  * Rebuilt with `RIGHTCLICKPRO_PACKAGE_DMG=1 RIGHTCLICKPRO_REGISTER_FINDER_EXTENSION=1`, replaced `/Applications/RightClick Pro.app`, registered `/Applications/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex`, enabled `com.iheeleme.rightclickpro.FinderExtension`, restarted Finder, and opened the app.
  * `pluginkit -m -i com.iheeleme.rightclickpro.FinderExtension` reports the extension enabled (`+`), and running processes point to `/Applications/RightClick Pro.app`.
  * `scripts/ci-swift-check.sh debug` and `swift test --filter MenuBuilderTests` are blocked by the local SwiftPM manifest linker issue in Command Line Tools (`PackageDescription.Package.__allocating_init` undefined symbol).
  * Direct `swiftc` typecheck passed for `RightClickProCore` and `FinderSyncController.swift`.
