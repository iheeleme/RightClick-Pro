import XCTest
@testable import RightToolCore

final class MenuBuilderTests: XCTestCase {
    func testRootMenuItemsAreLimitedToConfiguredMaximum() {
        let actions = (0..<7).map { index in
            RightToolAction(
                id: "root-\(index)",
                title: "Root \(index)",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                order: index
            )
        }
        let config = RightToolConfig(maxRootMenuActions: 5, actions: actions)
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.map(\.id), ["root-0", "root-1", "root-2", "root-3", "root-4"])
    }

    func testMenuFiltersByFinderInvocation() {
        let actions = [
            RightToolAction(
                id: "selection",
                title: "Selection",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 1
            ),
            RightToolAction(
                id: "container",
                title: "Container",
                kind: .paste,
                visibility: [.container],
                placement: .submenu,
                group: .fileOperations,
                order: 2
            )
        ]
        let config = RightToolConfig(actions: actions)
        let context = FinderContext(invocation: .selection, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.groupedSubmenuItems[.fileOperations]?.map(\.id), ["selection"])
    }
}
