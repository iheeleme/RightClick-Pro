#if canImport(FinderSync) && canImport(AppKit)
import AppKit
import FinderSync
import RightToolCore
import UniformTypeIdentifiers

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
        let bookmarks = (try? configProvider.loadBookmarkCatalog()) ?? DirectoryBookmarkCatalog()

        pendingMenuActions.removeAll()
        nextMenuActionTag = 1

        let presentation = menuBuilder.buildMenu(config: config, context: context, bookmarks: bookmarks)
        let menu = NSMenu(title: "快捷操作")

        for item in presentation.rootItems {
            menu.addItem(nsMenuItem(for: item, context: context))
        }

        if !presentation.rootItems.isEmpty && !presentation.groupedSubmenuItems.isEmpty {
            menu.addItem(.separator())
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
        menuItem.image = nsImage(for: item.icon)
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

    private func icon(for group: MenuGroup) -> MenuIconDescriptor {
        switch group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .folder
        case .createFile:
            return .systemSymbol("doc.badge.plus")
        case .developerEntrypoints:
            return .systemSymbol("chevron.left.forwardslash.chevron.right")
        case .fileOperations:
            return .systemSymbol("scissors")
        }
    }

    private func nsImage(for icon: MenuIconDescriptor?) -> NSImage? {
        guard let icon else {
            return nil
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
        return image
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
