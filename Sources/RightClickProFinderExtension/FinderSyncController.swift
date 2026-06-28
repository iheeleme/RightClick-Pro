#if canImport(FinderSync) && canImport(AppKit)
import AppKit
import CryptoKit
import FinderSync
import RightClickProCore
import UniformTypeIdentifiers

@objc(FinderSyncController)
final class FinderSyncController: FIFinderSync {
    private let menuBuilder = MenuBuilder()
    private let paths: RightClickProStoragePaths
    private let configProvider: RightClickProConfigProviding
    private let xpcClient = RightClickProActionRunnerXPCClient()
    private let cacheRefreshQueue = DispatchQueue(label: "com.iheeleme.rightclickpro.finder-extension.cache")
    private let iconResolutionQueue = DispatchQueue(label: "com.iheeleme.rightclickpro.finder-extension.icons", qos: .background)
    private let cacheRefreshInterval: TimeInterval = 8
    private let startupConfigLoadDelay: TimeInterval = 0.6
    private let postMenuRefreshDelay: TimeInterval = 1.0
    private let backgroundRepairDelay: TimeInterval = 8
    private let persistedIconCacheLoadDelay: TimeInterval = 1.2
    private let iconPrewarmIdleDelay: TimeInterval = 3
    private let iconPrewarmStepDelay: TimeInterval = 0.35
    private let slowMenuLogThreshold: TimeInterval = 0.2
    private let menuIconSize = NSSize(width: 16, height: 16)
    private let menuIconBackingScale: CGFloat = 2
    private let persistedIconCacheVersion = "v1"
    private var cachedConfig = RightClickProConfig(actions: [])
    private var cachedBookmarks = DirectoryBookmarkCatalog()
    private var hasLoadedConfiguration = false
    private var lastCacheRefresh = Date.distantPast
    private var isRefreshingCache = false
    private var iconCache: [String: NSImage] = [:]
    private var placeholderIconCache: [String: NSImage] = [:]
    private var pendingIconResolutionKeys: Set<String> = []
    private var deferredIconRequests: [DeferredIconRequest] = []
    private var isResolvingDeferredIcon = false
    private var iconPrewarmGeneration = 0
    private var configRefreshGeneration = 0
    private var pendingMenuActions: [Int: PendingMenuAction] = [:]
    private var nextMenuActionTag = 1

    override init() {
        let paths = RightClickProStoragePaths.defaultForCurrentProcess()
        self.paths = paths
        self.configProvider = FileBackedRightClickProConfigProvider(paths: paths)
        super.init()
        applyFallbackConfiguration()
        installGlobalFinderSyncScope()
        loadConfigurationForStartupInBackground()
        repairConfigurationInBackground(paths: paths)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        cancelIconPrewarmingForMenuRequest()
        cancelConfigurationRefreshForMenuRequest()
        let menuStart = Date()
        let context = finderContext(menuKind: menuKind)

        guard hasLoadedConfiguration else {
            return nil
        }

        let config = cachedConfig
        let bookmarks = cachedBookmarks

        pendingMenuActions.removeAll()
        nextMenuActionTag = 1

        let presentation = menuBuilder.buildMenu(config: config, context: context, bookmarks: bookmarks)
        let menu = NSMenu(title: "快捷操作")

        for item in presentation.rootItems {
            menu.addItem(nsMenuItem(for: item, context: context))
        }

        for group in MenuGroup.allCases {
            guard let items = presentation.groupedSubmenuItems[group], !items.isEmpty else {
                continue
            }
            let groupItem = NSMenuItem(title: title(for: group), action: nil, keyEquivalent: "")
            groupItem.image = cachedMenuImage(for: icon(for: group))
            let submenu = NSMenu(title: title(for: group))
            items.forEach { submenu.addItem(nsMenuItem(for: $0, context: context)) }
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }

        scheduleIconPrewarming(for: presentation)
        scheduleConfigurationRefreshAfterMenu()
        logSlowMenuIfNeeded(startedAt: menuStart, itemCount: menu.items.count)

        return menu.items.isEmpty ? nil : menu
    }

    private func loadConfigurationForStartupInBackground() {
        cacheRefreshQueue.asyncAfter(deadline: .now() + startupConfigLoadDelay) { [weak self] in
            guard let self else { return }
            do {
                let config = try self.configProvider.loadConfig()
                let bookmarks = try self.configProvider.loadBookmarkCatalog()
                DispatchQueue.main.async {
                    self.applyCachedConfiguration(config: config, bookmarks: bookmarks)
                }
            } catch {
                NSLog("RightClick Pro Finder extension startup config load failed, using fallback menu: \(error.localizedDescription)")
            }
        }
    }

    private func installGlobalFinderSyncScope() {
        FIFinderSyncController.default().directoryURLs = Set(FinderSyncScope.syncRoots())
    }

    private func repairConfigurationInBackground(paths: RightClickProStoragePaths) {
        cacheRefreshQueue.asyncAfter(deadline: .now() + backgroundRepairDelay) { [weak self] in
            do {
                let result = try ConfigurationBootstrapper().bootstrap(paths: paths)
                DispatchQueue.main.async {
                    self?.applyCachedConfiguration(config: result.config, bookmarks: result.bookmarks)
                    self?.installGlobalFinderSyncScope()
                }
            } catch {
                NSLog("RightClick Pro Finder extension background bootstrap failed: \(error.localizedDescription)")
            }
        }
    }

    private func refreshConfigurationFromDiskIfNeeded() {
        guard !isRefreshingCache, abs(lastCacheRefresh.timeIntervalSinceNow) > cacheRefreshInterval else {
            return
        }

        isRefreshingCache = true
        cacheRefreshQueue.async { [weak self] in
            guard let self else { return }
            let loadedConfig = try? self.configProvider.loadConfig()
            let loadedBookmarks = try? self.configProvider.loadBookmarkCatalog()

            DispatchQueue.main.async {
                self.isRefreshingCache = false
                guard let loadedConfig, let loadedBookmarks else {
                    return
                }
                if loadedConfig != self.cachedConfig || loadedBookmarks != self.cachedBookmarks {
                    self.applyCachedConfiguration(config: loadedConfig, bookmarks: loadedBookmarks)
                    self.installGlobalFinderSyncScope()
                } else {
                    self.lastCacheRefresh = Date()
                }
            }
        }
    }

    private func applyFallbackConfiguration() {
        applyCachedConfiguration(config: RightClickProConfig(), bookmarks: DirectoryBookmarkCatalog())
    }

    private func applyCachedConfiguration(config: RightClickProConfig, bookmarks: DirectoryBookmarkCatalog) {
        cachedConfig = config
        cachedBookmarks = bookmarks
        hasLoadedConfiguration = true
        lastCacheRefresh = Date()
        loadPersistedIconCacheInBackground(config: config, bookmarks: bookmarks)
    }

    private func scheduleConfigurationRefreshAfterMenu() {
        configRefreshGeneration += 1
        let generation = configRefreshGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + postMenuRefreshDelay) { [weak self] in
            guard let self else { return }
            guard generation == self.configRefreshGeneration else {
                return
            }
            self.refreshConfigurationFromDiskIfNeeded()
        }
    }

    private func cancelConfigurationRefreshForMenuRequest() {
        configRefreshGeneration += 1
    }

    private func scheduleIconPrewarming(for presentation: MenuPresentation) {
        iconPrewarmGeneration += 1
        let generation = iconPrewarmGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + iconPrewarmIdleDelay) { [weak self] in
            guard let self else { return }
            guard generation == self.iconPrewarmGeneration else {
                return
            }
            self.enqueueIconsForPrewarming(presentation)
        }
    }

    private func cancelIconPrewarmingForMenuRequest() {
        iconPrewarmGeneration += 1
        let queuedKeys = deferredIconRequests.map(\.key)
        deferredIconRequests.removeAll()
        pendingIconResolutionKeys.subtract(queuedKeys)
    }

    private func enqueueIconsForPrewarming(_ presentation: MenuPresentation) {
        var descriptors = Set<String>()
        let icons = presentation.rootItems.compactMap(\.icon)
            + presentation.groupedSubmenuItems.values.flatMap { $0.compactMap(\.icon) }
            + MenuGroup.allCases.map { icon(for: $0) }

        for icon in icons {
            guard icon.requiresExternalResourceLookup else {
                continue
            }
            let key = cacheKey(for: icon)
            guard descriptors.insert(key).inserted else {
                continue
            }
            scheduleDeferredIconResolution(icon, cacheKey: key)
        }
    }

    private func loadPersistedIconCacheInBackground(
        config: RightClickProConfig,
        bookmarks: DirectoryBookmarkCatalog
    ) {
        let icons = config.actions
            .filter(\.isEnabled)
            .map { MenuIconResolver.icon(for: $0, config: config, bookmarks: bookmarks) }

        var cacheKeys = Set<String>()
        let iconKeys = icons
            .filter(\.requiresExternalResourceLookup)
            .map { cacheKey(for: $0) }
            .filter { cacheKeys.insert($0).inserted }

        guard !iconKeys.isEmpty else {
            return
        }

        iconResolutionQueue.asyncAfter(deadline: .now() + persistedIconCacheLoadDelay) { [weak self] in
            guard let self else {
                return
            }

            let loadedImages: [(key: String, image: NSImage)] = iconKeys.compactMap { key in
                guard let image = autoreleasepool(invoking: { self.persistedPreparedMenuIcon(forKey: key) }) else {
                    return nil
                }
                return (key, image)
            }

            guard !loadedImages.isEmpty else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                for loadedImage in loadedImages where self.iconCache[loadedImage.key] == nil {
                    self.cachePreparedMenuIcon(loadedImage.image, forKey: loadedImage.key)
                }
            }
        }
    }

    private func finderContext(menuKind: FIMenuKind) -> FinderContext {
        let controller = FIFinderSyncController.default()
        let selectedItems = controller.selectedItemURLs() ?? []
        let targetDirectory = controller.targetedURL() ?? selectedItems.first?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())

        switch menuKind {
        case .contextualMenuForItems:
            return FinderContext(invocation: .selection, targetDirectory: targetDirectory, selectedItems: selectedItems)
        case .contextualMenuForContainer:
            return FinderContext(invocation: .container, targetDirectory: targetDirectory, selectedItems: [])
        case .toolbarItemMenu:
            return FinderContext(invocation: .toolbar, targetDirectory: targetDirectory, selectedItems: selectedItems)
        default:
            return FinderContext(invocation: .container, targetDirectory: targetDirectory, selectedItems: selectedItems)
        }
    }

    private func nsMenuItem(for item: MenuItemPresentation, context: FinderContext) -> NSMenuItem {
        let tag = nextMenuActionTag
        nextMenuActionTag += 1
        pendingMenuActions[tag] = PendingMenuAction(actionID: item.actionID, context: context)

        let menuItem = NSMenuItem(title: item.title, action: #selector(performRightClickProAction(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.image = cachedMenuImage(for: item.icon)
        // Finder Sync does not reliably preserve representedObject when
        // dispatching the copied menu item back to the extension process.
        menuItem.tag = tag
        return menuItem
    }

    @objc(performRightClickProAction:)
    func performRightClickProAction(_ sender: NSMenuItem) {
        guard let pending = pendingMenuActions[sender.tag] else {
            NSLog("RightClick Pro Finder extension received menu action without pending payload for tag: \(sender.tag)")
            return
        }
        NSLog("RightClick Pro Finder extension performing action: \(pending.actionID)")
        let request = ActionRequest(actionID: pending.actionID, context: pending.context)
        sendToActionRunner(request)
    }

    private func sendToActionRunner(_ request: ActionRequest) {
        if routeCommandTemplateToMainApp(request) {
            return
        }

        xpcClient.perform(request) { result in
            switch result {
            case .success(let actionResult):
                NSLog("RightClick Pro ActionRunner result for \(request.actionID): \(actionResult.status.rawValue) \(actionResult.message)")
            case .failure(let error):
                NSLog("RightClick Pro ActionRunner failed for \(request.actionID): \(error.localizedDescription)")
            }
        }
    }

    private func routeCommandTemplateToMainApp(_ request: ActionRequest) -> Bool {
        guard let action = cachedConfig.actions.first(where: { $0.id == request.actionID }),
              action.kind == .runCommand else {
            return false
        }

        do {
            let pendingRequest = PendingCommandRunRequest(
                actionID: request.actionID,
                context: request.context
            )
            try JSONFileStore<PendingCommandRunRequest>(url: paths.pendingCommandRunURL).save(pendingRequest)
            DistributedNotificationCenter.default().post(
                name: Notification.Name(RightClickProConstants.pendingCommandRunNotificationName),
                object: nil
            )
            launchMainAppForCommandWindow()
            NSLog("RightClick Pro queued command template for main app: \(request.actionID)")
        } catch {
            NSLog("RightClick Pro failed to queue command template \(request.actionID): \(error.localizedDescription)")
        }
        return true
    }

    private func launchMainAppForCommandWindow() {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: RightClickProConstants.mainAppBundleIdentifier) else {
            NSLog("RightClick Pro main app bundle not found: \(RightClickProConstants.mainAppBundleIdentifier)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("RightClick Pro failed to open main app: \(error.localizedDescription)")
            }
        }
    }

    private func icon(for group: MenuGroup) -> MenuIconDescriptor {
        switch group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .folder
        case .createFile:
            return .systemSymbol("doc.badge.plus")
        case .developerEntrypoints:
            return .systemSymbol("chevron.left.forwardslash.chevron.right")
        case .commandTemplates:
            return .systemSymbol("terminal")
        case .fileOperations:
            return .systemSymbol("scissors")
        }
    }

    private func cachedMenuImage(for icon: MenuIconDescriptor?) -> NSImage? {
        guard let icon else {
            return nil
        }

        // 菜单回调只走缓存/占位图标，真实 app/file 图标交给空闲后的后台队列解析。
        let key = cacheKey(for: icon)
        if let cached = iconCache[key] {
            return cached
        }

        return placeholderMenuImage(for: icon)
    }

    private func placeholderMenuImage(for icon: MenuIconDescriptor) -> NSImage? {
        switch icon {
        case .appBundleIdentifier:
            return defaultAppIcon()
        case .filePath:
            return placeholderMenuImage(for: icon.lightweightFallback)
        case .systemSymbol(let name):
            return cachedPlaceholderSystemSymbol(name: name, cacheKey: "symbol:\(name)")
        case .fileExtension:
            return cachedPlaceholderSystemSymbol(name: "doc", cacheKey: "file-extension")
        case .folder:
            return cachedPlaceholderSystemSymbol(name: "folder", cacheKey: "folder")
        }
    }

    private func scheduleDeferredIconResolution(_ icon: MenuIconDescriptor, cacheKey: String) {
        guard iconCache[cacheKey] == nil else {
            return
        }
        guard pendingIconResolutionKeys.insert(cacheKey).inserted else {
            return
        }

        deferredIconRequests.append(DeferredIconRequest(key: cacheKey, icon: icon))
        processNextDeferredIconIfNeeded()
    }

    private func processNextDeferredIconIfNeeded() {
        guard !isResolvingDeferredIcon, !deferredIconRequests.isEmpty else {
            return
        }

        isResolvingDeferredIcon = true
        let request = deferredIconRequests.removeFirst()

        iconResolutionQueue.asyncAfter(deadline: .now() + iconPrewarmStepDelay) { [weak self] in
            guard let self else {
                return
            }

            let image: NSImage? = autoreleasepool {
                if let persistedImage = self.persistedPreparedMenuIcon(forKey: request.key) {
                    return persistedImage
                }

                guard
                    let resolvedImage = self.resolvedImage(for: request.icon),
                    let preparedImage = self.preparedMenuImage(from: resolvedImage)
                else {
                    return nil
                }

                self.persistPreparedMenuIcon(preparedImage, forKey: request.key)
                return preparedImage
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                if self.iconCache[request.key] == nil, let image {
                    self.cachePreparedMenuIcon(image, forKey: request.key)
                }
                self.pendingIconResolutionKeys.remove(request.key)
                self.isResolvingDeferredIcon = false
                self.processNextDeferredIconIfNeeded()
            }
        }
    }

    private func defaultAppIcon() -> NSImage? {
        let key = "app:__default__"
        return cachedPlaceholderSystemSymbol(name: "app", cacheKey: key)
    }

    private func cachedPlaceholderSystemSymbol(name: String, cacheKey: String) -> NSImage? {
        if let cached = placeholderIconCache[cacheKey] {
            return cached
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        cachePlaceholder(image, forKey: cacheKey)
        return placeholderIconCache[cacheKey]
    }

    private func resolvedAppIcon(bundleIdentifier: String) -> NSImage? {
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleIdentifier.isEmpty else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: normalizedBundleIdentifier) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }

        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func resolvedFilePathIcon(path: String) -> NSImage? {
        let normalizedPath = NSString(string: path).expandingTildeInPath
        guard !normalizedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: normalizedPath)
    }

    private func resolvedImage(for icon: MenuIconDescriptor) -> NSImage? {
        let image: NSImage?
        switch icon {
        case .systemSymbol(let name):
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .appBundleIdentifier(let bundleIdentifier):
            image = resolvedAppIcon(bundleIdentifier: bundleIdentifier)
        case .filePath(let path):
            image = resolvedFilePathIcon(path: path)
        case .fileExtension(let fileExtension):
            image = nsImageForFileExtension(fileExtension)
        case .folder:
            image = NSWorkspace.shared.icon(for: .folder)
        }

        return image
    }

    private func preparedMenuImage(from image: NSImage) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelWidth = max(1, Int(menuIconSize.width * menuIconBackingScale))
        let pixelHeight = max(1, Int(menuIconSize.height * menuIconBackingScale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        let targetRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.clear(targetRect)
        context.interpolationQuality = .high
        context.draw(sourceImage, in: targetRect)

        guard let renderedImage = context.makeImage() else {
            return nil
        }

        let representation = NSBitmapImageRep(cgImage: renderedImage)
        representation.size = menuIconSize
        let menuImage = NSImage(size: menuIconSize)
        menuImage.addRepresentation(representation)
        return menuImage
    }

    private func persistedPreparedMenuIcon(forKey key: String) -> NSImage? {
        let url = persistedIconCacheURL(forKey: key)
        guard
            let image = NSImage(contentsOf: url),
            let preparedImage = preparedMenuImage(from: image)
        else {
            return nil
        }
        return preparedImage
    }

    private func persistPreparedMenuIcon(_ image: NSImage, forKey key: String) {
        guard let pngData = pngData(forPreparedMenuImage: image) else {
            return
        }

        let url = persistedIconCacheURL(forKey: key)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: url, options: [.atomic])
        } catch {
            NSLog("RightClick Pro icon cache write failed: \(error.localizedDescription)")
        }
    }

    private func pngData(forPreparedMenuImage image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func persistedIconCacheURL(forKey key: String) -> URL {
        paths.baseURL
            .appendingPathComponent("icon-cache", isDirectory: true)
            .appendingPathComponent(persistedIconCacheVersion, isDirectory: true)
            .appendingPathComponent("\(persistedIconCacheFileName(forKey: key)).png")
    }

    private func persistedIconCacheFileName(forKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cachePreparedMenuIcon(_ image: NSImage, forKey key: String) {
        image.size = menuIconSize
        iconCache[key] = image
    }

    private func cachePlaceholder(_ image: NSImage, forKey key: String) {
        if let copiedImage = image.copy() as? NSImage {
            copiedImage.size = menuIconSize
            placeholderIconCache[key] = copiedImage
            return
        }
        image.size = menuIconSize
        placeholderIconCache[key] = image
    }

    private func cacheKey(for icon: MenuIconDescriptor) -> String {
        switch icon {
        case .systemSymbol(let name):
            return "symbol:\(name)"
        case .appBundleIdentifier(let bundleIdentifier):
            return "app:\(bundleIdentifier)"
        case .filePath(let path):
            return "path:\(path)"
        case .fileExtension(let fileExtension):
            return "extension:\(normalizedFileExtension(fileExtension))"
        case .folder:
            return "folder"
        }
    }

    private func normalizedFileExtension(_ fileExtension: String) -> String {
        fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func nsImageForFileExtension(_ fileExtension: String) -> NSImage {
        let normalized = normalizedFileExtension(fileExtension)
        let contentType = UTType(filenameExtension: normalized) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }

    private func logSlowMenuIfNeeded(startedAt: Date, itemCount: Int) {
        let duration = Date().timeIntervalSince(startedAt)
        guard duration > slowMenuLogThreshold else {
            return
        }
        NSLog("RightClick Pro Finder menu slow render: \(String(format: "%.3f", duration))s, items=\(itemCount)")
    }

    private func title(for group: MenuGroup) -> String {
        switch group {
        case .commonDirectories:
            return "前往常用目录"
        case .moveToCommonDirectory:
            return "移动到常用目录"
        case .copyToCommonDirectory:
            return "复制到常用目录"
        case .createFile:
            return "新建文件"
        case .developerEntrypoints:
            return "开发者工具"
        case .commandTemplates:
            return "命令模板"
        case .fileOperations:
            return "文件操作"
        }
    }
}

private final class PendingMenuAction: NSObject {
    let actionID: String
    let context: FinderContext

    init(actionID: String, context: FinderContext) {
        self.actionID = actionID
        self.context = context
    }
}

private struct DeferredIconRequest {
    let key: String
    let icon: MenuIconDescriptor
}
#endif
