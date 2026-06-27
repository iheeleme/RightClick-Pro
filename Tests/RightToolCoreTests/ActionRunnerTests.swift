import XCTest
@testable import RightToolCore

final class ActionRunnerTests: XCTestCase {
    func testCreateFileActionCreatesTemplateAndLogsOperation() throws {
        let directory = try temporaryDirectory()
        let bookmark = DirectoryBookmark(id: "workspace", displayName: "Workspace", path: directory.path)
        let action = RightToolAction(
            id: "new-md",
            title: "New Markdown",
            kind: .createFile,
            visibility: [.container],
            placement: .submenu,
            group: .createFile,
            order: 1,
            payload: ActionPayload(templateID: "markdown")
        )
        let config = RightToolConfig(
            monitoredDirectoryIDs: ["workspace"],
            commonDirectoryIDs: ["workspace"],
            actions: [action],
            fileTemplates: [FileTemplate(id: "markdown", title: "Markdown", defaultFileName: "Note.md", contents: "# Note\n")]
        )
        let log = InMemoryOperationLog()
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightToolConfigProvider(
                config: config,
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [bookmark])
            ),
            operationLog: log,
            cutClipboard: InMemoryCutClipboardStore(),
            urlOpener: opener,
            developerAppOpener: opener
        )
        let request = ActionRequest(
            actionID: "new-md",
            context: FinderContext(invocation: .container, targetDirectory: directory)
        )

        let result = runner.run(request)

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Note.md").path))
        XCTAssertEqual(try log.loadRecent().first?.kind, .createFile)
    }

    func testCutThenPasteMovesSelectionThroughInternalClipboard() throws {
        let directory = try temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("draft.txt")
        try "draft".write(to: file, atomically: true, encoding: .utf8)

        let bookmark = DirectoryBookmark(id: "workspace", displayName: "Workspace", path: directory.path)
        let actions = [
            RightToolAction(
                id: "cut",
                title: "Cut",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 1
            ),
            RightToolAction(
                id: "paste",
                title: "Paste",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                group: .fileOperations,
                order: 2
            )
        ]
        let config = RightToolConfig(
            monitoredDirectoryIDs: ["workspace"],
            commonDirectoryIDs: ["workspace"],
            actions: actions
        )
        let clipboard = InMemoryCutClipboardStore()
        let log = InMemoryOperationLog()
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightToolConfigProvider(
                config: config,
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [bookmark])
            ),
            operationLog: log,
            cutClipboard: clipboard,
            urlOpener: opener,
            developerAppOpener: opener
        )

        let cutResult = runner.run(
            ActionRequest(
                actionID: "cut",
                context: FinderContext(invocation: .selection, targetDirectory: directory, selectedItems: [file])
            )
        )
        let pasteResult = runner.run(
            ActionRequest(
                actionID: "paste",
                context: FinderContext(invocation: .container, targetDirectory: targetDirectory)
            )
        )

        XCTAssertEqual(cutResult.status, .success)
        XCTAssertEqual(pasteResult.status, .success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("draft.txt").path))
        XCTAssertNil(try clipboard.load())
    }

    func testOpenDirectoryUsesResolvedBookmarkURL() throws {
        let resolvedDirectory = try temporaryDirectory()
        let staleFallbackDirectory = URL(fileURLWithPath: "/RightToolTests/stale")
        let bookmark = DirectoryBookmark(id: "workspace", displayName: "Workspace", path: staleFallbackDirectory.path)
        let action = RightToolAction(
            id: "open-workspace",
            title: "Open Workspace",
            kind: .openDirectory,
            visibility: [.container],
            placement: .submenu,
            group: .commonDirectories,
            order: 1,
            payload: ActionPayload(directoryID: "workspace")
        )
        let config = RightToolConfig(
            monitoredDirectoryIDs: ["workspace"],
            commonDirectoryIDs: ["workspace"],
            actions: [action]
        )
        let log = InMemoryOperationLog()
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightToolConfigProvider(
                config: config,
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [bookmark])
            ),
            operationLog: log,
            cutClipboard: InMemoryCutClipboardStore(),
            urlOpener: opener,
            developerAppOpener: opener,
            bookmarkResolver: MappingBookmarkResolver(urlsByID: ["workspace": resolvedDirectory])
        )

        let result = runner.run(
            ActionRequest(
                actionID: "open-workspace",
                context: FinderContext(invocation: .container, targetDirectory: resolvedDirectory)
            )
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(opener.openedURLs, [resolvedDirectory])
        XCTAssertEqual(result.affectedURLs, [resolvedDirectory])
    }

    func testDynamicDeveloperEntrypointOpensSelectedItemForSelectionContext() throws {
        let directory = try temporaryDirectory()
        let selectedProject = directory.appendingPathComponent("SelectedProject")
        try FileManager.default.createDirectory(at: selectedProject, withIntermediateDirectories: true)

        let opener = try runDeveloperEntrypoint(
            targetMode: .dynamic,
            context: FinderContext(
                invocation: .selection,
                targetDirectory: directory,
                selectedItems: [selectedProject]
            ),
            authorizedDirectory: directory
        )

        XCTAssertEqual(opener.openedApps.map(\.1), [selectedProject])
    }

    func testDynamicDeveloperEntrypointOpensTargetDirectoryForContainerContext() throws {
        let directory = try temporaryDirectory()
        let selectedProject = directory.appendingPathComponent("SelectedProject")
        try FileManager.default.createDirectory(at: selectedProject, withIntermediateDirectories: true)

        let opener = try runDeveloperEntrypoint(
            targetMode: .dynamic,
            context: FinderContext(
                invocation: .container,
                targetDirectory: directory,
                selectedItems: [selectedProject]
            ),
            authorizedDirectory: directory
        )

        XCTAssertEqual(opener.openedApps.map(\.1), [directory])
    }

    func testDynamicDeveloperEntrypointFallsBackToTargetDirectoryWithoutSelection() throws {
        let directory = try temporaryDirectory()

        let opener = try runDeveloperEntrypoint(
            targetMode: .dynamic,
            context: FinderContext(invocation: .selection, targetDirectory: directory),
            authorizedDirectory: directory
        )

        XCTAssertEqual(opener.openedApps.map(\.1), [directory])
    }

    func testDynamicDeveloperEntrypointUsesSelectionForToolbarWhenAvailable() throws {
        let directory = try temporaryDirectory()
        let selectedProject = directory.appendingPathComponent("SelectedProject")
        try FileManager.default.createDirectory(at: selectedProject, withIntermediateDirectories: true)

        let opener = try runDeveloperEntrypoint(
            targetMode: .dynamic,
            context: FinderContext(
                invocation: .toolbar,
                targetDirectory: directory,
                selectedItems: [selectedProject]
            ),
            authorizedDirectory: directory
        )

        XCTAssertEqual(opener.openedApps.map(\.1), [selectedProject])
    }

    private func runDeveloperEntrypoint(
        targetMode: DeveloperTargetMode,
        context: FinderContext,
        authorizedDirectory: URL
    ) throws -> RecordingURLOpener {
        let bookmark = DirectoryBookmark(id: "workspace", displayName: "Workspace", path: authorizedDirectory.path)
        let entrypoint = DeveloperEntrypoint(
            id: "developer-test",
            title: "Open in Test App",
            bundleIdentifier: "com.example.TestApp",
            targetMode: targetMode
        )
        let action = RightToolAction(
            id: "open-test-app",
            title: "Open in Test App",
            kind: .openInApp,
            visibility: [.selection, .container, .toolbar],
            placement: .submenu,
            group: .developerEntrypoints,
            order: 1,
            payload: ActionPayload(developerEntrypointID: entrypoint.id)
        )
        let config = RightToolConfig(
            monitoredDirectoryIDs: ["workspace"],
            commonDirectoryIDs: ["workspace"],
            actions: [action],
            developerEntrypoints: [entrypoint]
        )
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightToolConfigProvider(
                config: config,
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [bookmark])
            ),
            operationLog: InMemoryOperationLog(),
            cutClipboard: InMemoryCutClipboardStore(),
            urlOpener: opener,
            developerAppOpener: opener
        )

        let result = runner.run(ActionRequest(actionID: action.id, context: context))

        XCTAssertEqual(result.status, .success)
        return opener
    }
}
