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

    func testMenuAssignsDeveloperAppIcon() {
        let entrypoint = DeveloperEntrypoint(
            id: "cursor",
            title: "Cursor",
            bundleIdentifier: "com.todesktop.230313mzl4w4u92"
        )
        let action = RightToolAction(
            id: "open-cursor",
            title: "Open Cursor",
            kind: .openInApp,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(developerEntrypointID: entrypoint.id)
        )
        let config = RightToolConfig(actions: [action], developerEntrypoints: [entrypoint])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.first?.icon, .appBundleIdentifier(entrypoint.bundleIdentifier))
    }

    func testMenuAssignsTemplateFileTypeIcon() {
        let template = FileTemplate(id: "markdown", title: "Markdown", defaultFileName: "Note.md")
        let action = RightToolAction(
            id: "new-markdown",
            title: "New Markdown",
            kind: .createFile,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(templateID: template.id)
        )
        let config = RightToolConfig(actions: [action], fileTemplates: [template])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.first?.icon, .fileExtension("md"))
    }

    func testMenuAssignsDirectoryPathIcon() {
        let bookmark = DirectoryBookmark(id: "code", displayName: "Code", path: "/Users/test/Code")
        let action = RightToolAction(
            id: "open-code",
            title: "Open Code",
            kind: .openDirectory,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(directoryID: bookmark.id)
        )
        let config = RightToolConfig(actions: [action])
        let bookmarks = DirectoryBookmarkCatalog(bookmarks: [bookmark])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context, bookmarks: bookmarks)

        XCTAssertEqual(menu.rootItems.first?.icon, .filePath(bookmark.path))
    }

    func testRootItemStaysRootWhenMatchingSubmenuGroupExists() {
        let actions = [
            RightToolAction(
                id: "new-markdown",
                title: "新建 Markdown",
                kind: .createFile,
                visibility: [.container],
                placement: .rootMenu,
                group: .createFile,
                order: 20,
                payload: ActionPayload(templateID: "template-md")
            ),
            RightToolAction(
                id: "new-json",
                title: "新建 JSON",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: 30,
                payload: ActionPayload(templateID: "template-json")
            )
        ]
        let config = RightToolConfig(actions: actions)
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.map(\.id), ["new-markdown"])
        XCTAssertEqual(menu.groupedSubmenuItems[.createFile]?.map(\.id), ["new-json"])
    }
}
