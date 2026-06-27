import Foundation

public enum MenuIconDescriptor: Equatable {
    case systemSymbol(String)
    case appBundleIdentifier(String)
    case filePath(String)
    case fileExtension(String)
    case folder
}

public enum MenuIconResolver {
    public static func icon(
        for action: RightToolAction,
        config: RightToolConfig,
        bookmarks: DirectoryBookmarkCatalog = DirectoryBookmarkCatalog()
    ) -> MenuIconDescriptor {
        switch action.kind {
        case .openDirectory, .moveToDirectory, .copyToDirectory:
            if
                let directoryID = action.payload.directoryID,
                let bookmark = bookmarks.bookmark(id: directoryID)
            {
                return .filePath(bookmark.path)
            }
            return .folder
        case .cut:
            return .systemSymbol("scissors")
        case .paste:
            return .systemSymbol("doc.on.clipboard")
        case .createFile:
            if
                let templateID = action.payload.templateID,
                let template = config.fileTemplates.first(where: { $0.id == templateID })
            {
                let fileExtension = URL(fileURLWithPath: template.defaultFileName).pathExtension
                return fileExtension.isEmpty ? .systemSymbol("doc") : .fileExtension(fileExtension)
            }
            return .systemSymbol("doc.badge.plus")
        case .openInApp:
            if
                let entrypointID = action.payload.developerEntrypointID,
                let entrypoint = config.developerEntrypoints.first(where: { $0.id == entrypointID })
            {
                return .appBundleIdentifier(entrypoint.bundleIdentifier)
            }
            return .systemSymbol("app")
        case .runCommand:
            return .systemSymbol("terminal")
        case .undoOperation:
            return .systemSymbol("arrow.uturn.backward")
        }
    }
}

public struct MenuItemPresentation: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var actionID: String
    public var group: MenuGroup?
    public var order: Int
    public var icon: MenuIconDescriptor?

    public init(
        id: String,
        title: String,
        actionID: String,
        group: MenuGroup?,
        order: Int,
        icon: MenuIconDescriptor? = nil
    ) {
        self.id = id
        self.title = title
        self.actionID = actionID
        self.group = group
        self.order = order
        self.icon = icon
    }
}

public struct MenuPresentation: Equatable {
    public var rootItems: [MenuItemPresentation]
    public var groupedSubmenuItems: [MenuGroup: [MenuItemPresentation]]

    public init(
        rootItems: [MenuItemPresentation] = [],
        groupedSubmenuItems: [MenuGroup: [MenuItemPresentation]] = [:]
    ) {
        self.rootItems = rootItems
        self.groupedSubmenuItems = groupedSubmenuItems
    }
}

public struct MenuBuilder {
    public init() {}

    public func buildMenu(
        config: RightToolConfig,
        context: FinderContext,
        bookmarks: DirectoryBookmarkCatalog = DirectoryBookmarkCatalog()
    ) -> MenuPresentation {
        let visibleActions = config.actions
            .filter { $0.isEnabled }
            .filter { $0.visibility.contains(context.invocation.visibility) }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.order < rhs.order
            }

        let rootCandidates = visibleActions
            .filter { $0.placement == .rootMenu }
            .prefix(max(0, config.maxRootMenuActions))
            .map { makePresentation($0, config: config, bookmarks: bookmarks) }

        var grouped: [MenuGroup: [MenuItemPresentation]] = [:]
        visibleActions
            .filter { $0.placement == .submenu }
            .forEach { action in
                let group = action.group ?? .fileOperations
                grouped[group, default: []].append(makePresentation(action, config: config, bookmarks: bookmarks))
            }

        let rootItems = displayRootItems(from: Array(rootCandidates), grouped: &grouped)

        for group in Array(grouped.keys) {
            grouped[group]?.sort(by: menuItemSort)
        }

        return MenuPresentation(rootItems: rootItems, groupedSubmenuItems: grouped)
    }

    private func displayRootItems(
        from rootCandidates: [MenuItemPresentation],
        grouped: inout [MenuGroup: [MenuItemPresentation]]
    ) -> [MenuItemPresentation] {
        guard
            rootCandidates.count == 1,
            let group = rootCandidates[0].group,
            grouped[group]?.isEmpty == false
        else {
            return rootCandidates
        }

        grouped[group, default: []].append(rootCandidates[0])
        return []
    }

    private func makePresentation(
        _ action: RightToolAction,
        config: RightToolConfig,
        bookmarks: DirectoryBookmarkCatalog
    ) -> MenuItemPresentation {
        MenuItemPresentation(
            id: action.id,
            title: action.title,
            actionID: action.id,
            group: action.group,
            order: action.order,
            icon: MenuIconResolver.icon(for: action, config: config, bookmarks: bookmarks)
        )
    }

    private func menuItemSort(_ lhs: MenuItemPresentation, _ rhs: MenuItemPresentation) -> Bool {
        if lhs.order == rhs.order {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.order < rhs.order
    }
}
