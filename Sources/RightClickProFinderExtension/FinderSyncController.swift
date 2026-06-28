#if canImport(FinderSync) && canImport(AppKit)
import AppKit
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
    private var cachedConfig = RightClickProConfig(actions: [])
    private var cachedBookmarks = DirectoryBookmarkCatalog()
    private var hasLoadedConfiguration = false
    private var lastCacheRefresh = Date.distantPast
    private var isRefreshingCache = false
    private var iconCache: [String: NSImage] = [:]
    private var pendingMenuActions: [Int: PendingMenuAction] = [:]
    private var nextMenuActionTag = 1

    override init() {
        let paths = RightClickProStoragePaths.defaultForCurrentProcess()
        self.paths = paths
        self.configProvider = FileBackedRightClickProConfigProvider(paths: paths)
        super.init()
        installFastMonitoredDirectoryFallback(paths: paths)
        loadConfigurationForStartup(paths: paths)
        reloadMonitoredDirectoriesFromCache()
        repairConfigurationInBackground(paths: paths)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let context = finderContext(menuKind: menuKind)
        refreshConfigurationFromDiskIfNeeded()

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
            groupItem.image = nsImage(for: icon(for: group))
            let submenu = NSMenu(title: title(for: group))
            items.forEach { submenu.addItem(nsMenuItem(for: $0, context: context)) }
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func loadConfigurationForStartup(paths: RightClickProStoragePaths) {
        if
            FileManager.default.fileExists(atPath: paths.configURL.path),
            FileManager.default.fileExists(atPath: paths.bookmarksURL.path),
            let config = try? configProvider.loadConfig(),
            let bookmarks = try? configProvider.loadBookmarkCatalog()
        {
            applyCachedConfiguration(config: config, bookmarks: bookmarks)
            return
        }

        do {
            let result = try ConfigurationBootstrapper().bootstrap(paths: paths)
            applyCachedConfiguration(config: result.config, bookmarks: result.bookmarks)
        } catch {
            NSLog("RightClick Pro Finder extension bootstrap failed: \(error.localizedDescription)")
        }
    }

    private func installFastMonitoredDirectoryFallback(paths: RightClickProStoragePaths) {
        if
            FileManager.default.fileExists(atPath: paths.bookmarksURL.path),
            let bookmarks = try? configProvider.loadBookmarkCatalog()
        {
            let urls = bookmarks.bookmarks.map { URL(fileURLWithPath: $0.path) }
            if !urls.isEmpty {
                FIFinderSyncController.default().directoryURLs = Set(urls)
                return
            }
        }

        let defaultURLs = ConfigurationBootstrapper()
            .defaultBookmarks()
            .bookmarks
            .map { URL(fileURLWithPath: $0.path) }
        if !defaultURLs.isEmpty {
            FIFinderSyncController.default().directoryURLs = Set(defaultURLs)
        }
    }

    private func repairConfigurationInBackground(paths: RightClickProStoragePaths) {
        cacheRefreshQueue.async { [weak self] in
            do {
                let result = try ConfigurationBootstrapper().bootstrap(paths: paths)
                DispatchQueue.main.async {
                    self?.applyCachedConfiguration(config: result.config, bookmarks: result.bookmarks)
                    self?.reloadMonitoredDirectoriesFromCache()
                }
            } catch {
                NSLog("RightClick Pro Finder extension background bootstrap failed: \(error.localizedDescription)")
            }
        }
    }

    private func refreshConfigurationFromDiskIfNeeded() {
        guard !isRefreshingCache, abs(lastCacheRefresh.timeIntervalSinceNow) > 2 else {
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
                    self.reloadMonitoredDirectoriesFromCache()
                } else {
                    self.lastCacheRefresh = Date()
                }
            }
        }
    }

    private func applyCachedConfiguration(config: RightClickProConfig, bookmarks: DirectoryBookmarkCatalog) {
        cachedConfig = config
        cachedBookmarks = bookmarks
        hasLoadedConfiguration = true
        lastCacheRefresh = Date()
    }

    private func reloadMonitoredDirectoriesFromCache() {
        guard hasLoadedConfiguration else {
            return
        }
        let urls = cachedBookmarks.urls(for: cachedConfig.monitoredDirectoryIDs)
        FIFinderSyncController.default().directoryURLs = Set(urls)
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
        menuItem.image = nsImage(for: item.icon)
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

    private func nsImage(for icon: MenuIconDescriptor?) -> NSImage? {
        guard let icon else {
            return nil
        }

        let key = cacheKey(for: icon)
        if let cached = iconCache[key] {
            return cached
        }

        let image: NSImage?
        switch icon {
        case .systemSymbol(let name):
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .appBundleIdentifier(let bundleIdentifier):
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                image = NSWorkspace.shared.icon(forFile: appURL.path)
            } else {
                image = NSWorkspace.shared.icon(for: .applicationBundle)
            }
        case .filePath(let path):
            if FileManager.default.fileExists(atPath: path) {
                image = NSWorkspace.shared.icon(forFile: path)
            } else if !URL(fileURLWithPath: path).pathExtension.isEmpty {
                image = nsImageForFileExtension(URL(fileURLWithPath: path).pathExtension)
            } else {
                image = NSWorkspace.shared.icon(for: .folder)
            }
        case .fileExtension(let fileExtension):
            image = nsImageForFileExtension(fileExtension)
        case .folder:
            image = NSWorkspace.shared.icon(for: .folder)
        }

        image?.size = NSSize(width: 16, height: 16)
        if let image {
            iconCache[key] = image
        }
        return image
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
#endif
