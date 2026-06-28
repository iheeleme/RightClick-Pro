import XCTest
@testable import RightClickProCore

final class MenuBuilderTests: XCTestCase {
    func testExternalResourceIconsExposeLightweightFallbacks() {
        XCTAssertTrue(MenuIconDescriptor.appBundleIdentifier("com.apple.Terminal").requiresExternalResourceLookup)
        XCTAssertEqual(
            MenuIconDescriptor.appBundleIdentifier("com.apple.Terminal").lightweightFallback,
            .systemSymbol("app")
        )

        XCTAssertTrue(MenuIconDescriptor.filePath("/Users/test/Downloads").requiresExternalResourceLookup)
        XCTAssertEqual(
            MenuIconDescriptor.filePath("/Users/test/Downloads").lightweightFallback,
            .folder
        )
        XCTAssertEqual(
            MenuIconDescriptor.filePath("/Users/test/Notes/today.md").lightweightFallback,
            .fileExtension("md")
        )
    }

    func testIntrinsicIconsDoNotRequireExternalResourceLookup() {
        let icons: [MenuIconDescriptor] = [
            .systemSymbol("terminal"),
            .fileExtension("swift"),
            .folder
        ]

        for icon in icons {
            XCTAssertFalse(icon.requiresExternalResourceLookup)
            XCTAssertEqual(icon.lightweightFallback, icon)
        }
    }

    func testRootMenuItemsAreLimitedToConfiguredMaximum() {
        let actions = (0..<7).map { index in
            RightClickProAction(
                id: "root-\(index)",
                title: "Root \(index)",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                order: index
            )
        }
        let config = RightClickProConfig(maxRootMenuActions: 5, actions: actions)
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.map(\.id), ["root-0", "root-1", "root-2", "root-3", "root-4"])
    }

    func testMenuFiltersByFinderInvocation() {
        let actions = [
            RightClickProAction(
                id: "selection",
                title: "Selection",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 1
            ),
            RightClickProAction(
                id: "container",
                title: "Container",
                kind: .paste,
                visibility: [.container],
                placement: .submenu,
                group: .fileOperations,
                order: 2
            )
        ]
        let config = RightClickProConfig(actions: actions)
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
        let action = RightClickProAction(
            id: "open-cursor",
            title: "Open Cursor",
            kind: .openInApp,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(developerEntrypointID: entrypoint.id)
        )
        let config = RightClickProConfig(actions: [action], developerEntrypoints: [entrypoint])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.first?.icon, .appBundleIdentifier(entrypoint.bundleIdentifier))
    }

    func testMenuAssignsTemplateFileTypeIcon() {
        let template = FileTemplate(id: "markdown", title: "Markdown", defaultFileName: "Note.md")
        let action = RightClickProAction(
            id: "new-markdown",
            title: "New Markdown",
            kind: .createFile,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(templateID: template.id)
        )
        let config = RightClickProConfig(actions: [action], fileTemplates: [template])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.first?.icon, .fileExtension("md"))
    }

    func testMenuAssignsDirectoryPathIcon() {
        let bookmark = DirectoryBookmark(id: "code", displayName: "Code", path: "/Users/test/Code")
        let action = RightClickProAction(
            id: "open-code",
            title: "Open Code",
            kind: .openDirectory,
            visibility: [.container],
            placement: .rootMenu,
            order: 1,
            payload: ActionPayload(directoryID: bookmark.id)
        )
        let config = RightClickProConfig(actions: [action])
        let bookmarks = DirectoryBookmarkCatalog(bookmarks: [bookmark])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context, bookmarks: bookmarks)

        XCTAssertEqual(menu.rootItems.first?.icon, .filePath(bookmark.path))
    }

    func testRootItemStaysRootWhenMatchingSubmenuGroupExists() {
        let actions = [
            RightClickProAction(
                id: "new-markdown",
                title: "新建 Markdown",
                kind: .createFile,
                visibility: [.container],
                placement: .rootMenu,
                group: .createFile,
                order: 20,
                payload: ActionPayload(templateID: "template-md")
            ),
            RightClickProAction(
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
        let config = RightClickProConfig(actions: actions)
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.rootItems.map(\.id), ["new-markdown"])
        XCTAssertEqual(menu.groupedSubmenuItems[.createFile]?.map(\.id), ["new-json"])
    }

    func testMenuAssignsCommandTemplateIconAndGroup() {
        let template = CommandTemplate(id: "command-git-status", title: "Git Status", command: "git status --short")
        let action = RightClickProAction(
            id: "run-git-status",
            title: "Git Status",
            kind: .runCommand,
            visibility: [.container],
            placement: .submenu,
            group: .commandTemplates,
            order: 1,
            payload: ActionPayload(commandTemplateID: template.id)
        )
        let config = RightClickProConfig(actions: [action], commandTemplates: [template])
        let context = FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))

        let menu = MenuBuilder().buildMenu(config: config, context: context)

        XCTAssertEqual(menu.groupedSubmenuItems[.commandTemplates]?.first?.icon, .systemSymbol("terminal"))
        XCTAssertEqual(menu.groupedSubmenuItems[.commandTemplates]?.map(\.id), ["run-git-status"])
    }
}
