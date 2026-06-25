import Foundation

public struct MenuItemPresentation: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var actionID: String
    public var group: MenuGroup?
    public var order: Int

    public init(id: String, title: String, actionID: String, group: MenuGroup?, order: Int) {
        self.id = id
        self.title = title
        self.actionID = actionID
        self.group = group
        self.order = order
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

    public func buildMenu(config: RightToolConfig, context: FinderContext) -> MenuPresentation {
        let visibleActions = config.actions
            .filter { $0.isEnabled }
            .filter { $0.visibility.contains(context.invocation.visibility) }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.order < rhs.order
            }

        let rootItems = visibleActions
            .filter { $0.placement == .rootMenu }
            .prefix(max(0, config.maxRootMenuActions))
            .map(makePresentation)

        var grouped: [MenuGroup: [MenuItemPresentation]] = [:]
        visibleActions
            .filter { $0.placement == .submenu }
            .forEach { action in
                let group = action.group ?? .fileOperations
                grouped[group, default: []].append(makePresentation(action))
            }

        return MenuPresentation(rootItems: Array(rootItems), groupedSubmenuItems: grouped)
    }

    private func makePresentation(_ action: RightToolAction) -> MenuItemPresentation {
        MenuItemPresentation(
            id: action.id,
            title: action.title,
            actionID: action.id,
            group: action.group,
            order: action.order
        )
    }
}
