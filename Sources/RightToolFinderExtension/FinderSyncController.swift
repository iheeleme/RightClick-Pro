#if canImport(FinderSync) && canImport(AppKit)
import AppKit
import FinderSync
import RightToolCore

@objc(FinderSyncController)
final class FinderSyncController: FIFinderSync {
    private let menuBuilder = MenuBuilder()
    private let configProvider: RightToolConfigProviding
    private let xpcClient = RightToolActionRunnerXPCClient()
    private var pendingMenuActions: [Int: PendingMenuAction] = [:]
    private var nextMenuActionTag = 1

    override init() {
        let paths = RightToolStoragePaths.defaultForCurrentProcess()
        self.configProvider = FileBackedRightToolConfigProvider(paths: paths)
        super.init()
        bootstrapConfiguration(paths: paths)
        reloadMonitoredDirectories()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let context = finderContext(menuKind: menuKind)
        guard let config = try? configProvider.loadConfig() else {
            return nil
        }

        pendingMenuActions.removeAll()
        nextMenuActionTag = 1

        let presentation = menuBuilder.buildMenu(config: config, context: context)
        let menu = NSMenu(title: "RightTool")

        for item in presentation.rootItems {
            menu.addItem(nsMenuItem(for: item, context: context))
        }

        if !presentation.rootItems.isEmpty && !presentation.groupedSubmenuItems.isEmpty {
            menu.addItem(.separator())
        }

        let rightToolMenu = NSMenu(title: "RightTool")
        for group in MenuGroup.allCases {
            guard let items = presentation.groupedSubmenuItems[group], !items.isEmpty else {
                continue
            }
            let groupItem = NSMenuItem(title: title(for: group), action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title(for: group))
            items.forEach { submenu.addItem(nsMenuItem(for: $0, context: context)) }
            groupItem.submenu = submenu
            rightToolMenu.addItem(groupItem)
        }

        if !rightToolMenu.items.isEmpty {
            let container = NSMenuItem(title: "RightTool", action: nil, keyEquivalent: "")
            container.submenu = rightToolMenu
            menu.addItem(container)
        }

        return menu
    }

    private func bootstrapConfiguration(paths: RightToolStoragePaths) {
        do {
            _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
        } catch {
            NSLog("RightTool Finder extension bootstrap failed: \(error.localizedDescription)")
        }
    }

    private func reloadMonitoredDirectories() {
        guard
            let config = try? configProvider.loadConfig(),
            let bookmarks = try? configProvider.loadBookmarkCatalog()
        else {
            return
        }
        let urls = bookmarks.urls(for: config.monitoredDirectoryIDs)
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

        let menuItem = NSMenuItem(title: item.title, action: #selector(performRightToolAction(_:)), keyEquivalent: "")
        menuItem.target = self
        // Finder Sync does not reliably preserve representedObject when
        // dispatching the copied menu item back to the extension process.
        menuItem.tag = tag
        return menuItem
    }

    @objc(performRightToolAction:)
    func performRightToolAction(_ sender: NSMenuItem) {
        guard let pending = pendingMenuActions[sender.tag] else {
            NSLog("RightTool Finder extension received menu action without pending payload for tag: \(sender.tag)")
            return
        }
        NSLog("RightTool Finder extension performing action: \(pending.actionID)")
        let request = ActionRequest(actionID: pending.actionID, context: pending.context)
        sendToActionRunner(request)
    }

    private func sendToActionRunner(_ request: ActionRequest) {
        xpcClient.perform(request) { result in
            switch result {
            case .success(let actionResult):
                NSLog("RightTool ActionRunner result for \(request.actionID): \(actionResult.status.rawValue) \(actionResult.message)")
            case .failure(let error):
                NSLog("RightTool ActionRunner failed for \(request.actionID): \(error.localizedDescription)")
            }
        }
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
            return "开发者入口"
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
