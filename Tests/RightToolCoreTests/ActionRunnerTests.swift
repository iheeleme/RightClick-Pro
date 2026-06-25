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
}
