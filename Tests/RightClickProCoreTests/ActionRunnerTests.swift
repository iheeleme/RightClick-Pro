import XCTest
@testable import RightClickProCore

final class ActionRunnerTests: XCTestCase {
    func testCreateFileActionCreatesTemplateAndLogsOperation() throws {
        let directory = try temporaryDirectory()
        let bookmark = DirectoryBookmark(id: "workspace", displayName: "Workspace", path: directory.path)
        let action = RightClickProAction(
            id: "new-md",
            title: "New Markdown",
            kind: .createFile,
            visibility: [.container],
            placement: .submenu,
            group: .createFile,
            order: 1,
            payload: ActionPayload(templateID: "markdown")
        )
        let config = RightClickProConfig(
            shortcutDirectoryIDs: ["workspace"],
            actions: [action],
            fileTemplates: [FileTemplate(id: "markdown", title: "Markdown", defaultFileName: "Note.md", contents: "# Note\n")]
        )
        let log = InMemoryOperationLog()
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
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

    func testFileActionsAreNotBoundedByShortcutDirectories() throws {
        let directory = try temporaryDirectory()
        let action = RightClickProAction(
            id: "new-md",
            title: "New Markdown",
            kind: .createFile,
            visibility: [.container],
            placement: .submenu,
            group: .createFile,
            order: 1,
            payload: ActionPayload(templateID: "markdown")
        )
        let config = RightClickProConfig(
            shortcutDirectoryIDs: [],
            actions: [action],
            fileTemplates: [FileTemplate(id: "markdown", title: "Markdown", defaultFileName: "Loose.md")]
        )
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(config: config),
            operationLog: InMemoryOperationLog(),
            cutClipboard: InMemoryCutClipboardStore(),
            urlOpener: RecordingURLOpener(),
            developerAppOpener: RecordingURLOpener()
        )

        let result = runner.run(
            ActionRequest(
                actionID: "new-md",
                context: FinderContext(invocation: .container, targetDirectory: directory)
            )
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Loose.md").path))
    }

    func testCutThenPasteMovesSelectionThroughInternalClipboard() throws {
        let directory = try temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("draft.txt")
        try "draft".write(to: file, atomically: true, encoding: .utf8)

        let bookmark = DirectoryBookmark(id: "workspace", displayName: "Workspace", path: directory.path)
        let actions = [
            RightClickProAction(
                id: "cut",
                title: "Cut",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 1
            ),
            RightClickProAction(
                id: "paste",
                title: "Paste",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                group: .fileOperations,
                order: 2
            )
        ]
        let config = RightClickProConfig(
            shortcutDirectoryIDs: ["workspace"],
            actions: actions
        )
        let clipboard = InMemoryCutClipboardStore()
        let log = InMemoryOperationLog()
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
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

    func testPasteRetainsOnlyFailedItemsAndRetriesWithoutRepeatingCompletedItems() throws {
        let directory = try temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let completedFile = directory.appendingPathComponent("done.txt")
        let pendingFile = directory.appendingPathComponent("pending.txt")
        try "done".write(to: completedFile, atomically: true, encoding: .utf8)

        let action = RightClickProAction(
            id: "paste",
            title: "Paste",
            kind: .paste,
            visibility: [.container],
            placement: .rootMenu,
            group: .fileOperations,
            order: 1
        )
        let config = RightClickProConfig(actions: [action])
        let clipboard = InMemoryCutClipboardStore(
            record: CutClipboardRecord(sourceURLs: [completedFile, pendingFile])
        )
        let log = InMemoryOperationLog()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(config: config),
            operationLog: log,
            cutClipboard: clipboard,
            urlOpener: RecordingURLOpener(),
            developerAppOpener: RecordingURLOpener()
        )
        let request = ActionRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: targetDirectory)
        )

        let firstResult = runner.run(request)

        XCTAssertEqual(firstResult.status, .failure)
        XCTAssertEqual(firstResult.affectedURLs, [targetDirectory.appendingPathComponent("done.txt")])
        XCTAssertEqual(firstResult.remainingURLs, [pendingFile])
        XCTAssertEqual(try clipboard.load()?.sourceURLs, [pendingFile])
        XCTAssertEqual(try log.loadRecent().last?.kind, .paste)

        try "pending".write(to: pendingFile, atomically: true, encoding: .utf8)
        let secondResult = runner.run(request)

        XCTAssertEqual(secondResult.status, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("done.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDirectory.appendingPathComponent("pending.txt").path))
        XCTAssertNil(try clipboard.load())
    }

    func testMoveFailureLogsTheActionOperationKind() throws {
        let directory = try temporaryDirectory()
        let targetDirectory = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let missingSource = directory.appendingPathComponent("missing.txt")
        let bookmark = DirectoryBookmark(id: "target", displayName: "Target", path: targetDirectory.path)
        let action = RightClickProAction(
            id: "move",
            title: "Move",
            kind: .moveToDirectory,
            visibility: [.selection],
            placement: .submenu,
            group: .moveToCommonDirectory,
            order: 1,
            payload: ActionPayload(directoryID: bookmark.id)
        )
        let log = InMemoryOperationLog()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
                config: RightClickProConfig(actions: [action]),
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [bookmark])
            ),
            operationLog: log,
            cutClipboard: InMemoryCutClipboardStore(),
            urlOpener: RecordingURLOpener(),
            developerAppOpener: RecordingURLOpener(),
            bookmarkResolver: MappingBookmarkResolver(urlsByID: [bookmark.id: targetDirectory])
        )

        let result = runner.run(
            ActionRequest(
                actionID: action.id,
                context: FinderContext(
                    invocation: .selection,
                    targetDirectory: directory,
                    selectedItems: [missingSource]
                )
            )
        )

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.remainingURLs, [missingSource])
        XCTAssertEqual(try log.loadRecent().first?.kind, .move)
    }

    func testPastePreservesBatchResultWhenHistoryCannotBeSaved() throws {
        let directory = try temporaryDirectory()
        let target = directory.appendingPathComponent("target")
        let logURL = directory.appendingPathComponent("blocked-log")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logURL, withIntermediateDirectories: true)
        let completed = directory.appendingPathComponent("completed.txt")
        let pending = directory.appendingPathComponent("pending.txt")
        try Data("completed".utf8).write(to: completed)
        let clipboard = InMemoryCutClipboardStore(record: CutClipboardRecord(sourceURLs: [completed, pending]))
        let action = RightClickProAction(
            id: "paste", title: "Paste", kind: .paste,
            visibility: [.container], placement: .submenu, order: 1
        )
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(config: RightClickProConfig(actions: [action])),
            operationLog: JSONLineOperationLog(url: logURL),
            cutClipboard: clipboard,
            urlOpener: RecordingURLOpener(),
            developerAppOpener: RecordingURLOpener()
        )

        let result = runner.run(ActionRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: target)
        ))

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.affectedURLs, [target.appendingPathComponent("completed.txt")])
        XCTAssertEqual(result.remainingURLs, [pending])
        XCTAssertEqual(try clipboard.load()?.sourceURLs, [pending])
        XCTAssertTrue(result.message.contains("操作历史保存失败"))
    }

    func testPastePreservesBatchResultWhenClipboardCannotBeSaved() throws {
        struct ReadOnlyClipboard: CutClipboardStoring {
            var record: CutClipboardRecord

            func load() throws -> CutClipboardRecord? { record }
            func save(_ record: CutClipboardRecord) throws {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
            func clear() throws {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        }

        let directory = try temporaryDirectory()
        let target = directory.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let completed = directory.appendingPathComponent("completed.txt")
        let pending = directory.appendingPathComponent("pending.txt")
        try Data("completed".utf8).write(to: completed)
        let action = RightClickProAction(
            id: "paste", title: "Paste", kind: .paste,
            visibility: [.container], placement: .submenu, order: 1
        )
        let log = InMemoryOperationLog()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(config: RightClickProConfig(actions: [action])),
            operationLog: log,
            cutClipboard: ReadOnlyClipboard(record: CutClipboardRecord(sourceURLs: [completed, pending])),
            urlOpener: RecordingURLOpener(),
            developerAppOpener: RecordingURLOpener()
        )

        let result = runner.run(ActionRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: target)
        ))

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.affectedURLs, [target.appendingPathComponent("completed.txt")])
        XCTAssertEqual(result.remainingURLs, [pending])
        XCTAssertTrue(result.message.contains("剪切板更新失败"))
        XCTAssertTrue(result.message.contains("重新剪切"))
        XCTAssertEqual(log.records.last?.destinationPaths, result.affectedURLs.map(\.path))
    }

    func testCutSucceedsWhenCatalogContainsInvalidUnrelatedBookmark() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("draft.txt")
        try "draft".write(to: file, atomically: true, encoding: .utf8)

        let invalidBookmark = DirectoryBookmark(
            id: "broken",
            displayName: "Broken",
            path: directory.appendingPathComponent("broken").path,
            bookmarkDataBase64: "not-valid-base64"
        )
        let action = RightClickProAction(
            id: "cut",
            title: "Cut",
            kind: .cut,
            visibility: [.selection],
            placement: .submenu,
            group: .fileOperations,
            order: 1
        )
        let config = RightClickProConfig(shortcutDirectoryIDs: ["broken"], actions: [action])
        let clipboard = InMemoryCutClipboardStore()
        let log = InMemoryOperationLog()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
                config: config,
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [invalidBookmark])
            ),
            operationLog: log,
            cutClipboard: clipboard,
            urlOpener: RecordingURLOpener(),
            developerAppOpener: RecordingURLOpener()
        )

        let result = runner.run(
            ActionRequest(
                actionID: action.id,
                context: FinderContext(
                    invocation: .selection,
                    targetDirectory: directory,
                    selectedItems: [file]
                )
            )
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(try clipboard.load()?.sourceURLs, [file])
        let record = try XCTUnwrap(log.loadRecent().first)
        XCTAssertEqual(record.kind, .cut)
        XCTAssertEqual(record.status, .success)
    }

    func testDirectoryActionMissingPayloadWinsOverInvalidUnrelatedBookmark() throws {
        let directory = try temporaryDirectory()
        let invalidBookmark = DirectoryBookmark(
            id: "broken",
            displayName: "Broken",
            path: directory.appendingPathComponent("broken").path,
            bookmarkDataBase64: "not-valid-base64"
        )
        let action = RightClickProAction(
            id: "open-directory",
            title: "Open Directory",
            kind: .openDirectory,
            visibility: [.container],
            placement: .submenu,
            group: .commonDirectories,
            order: 1
        )
        let log = InMemoryOperationLog()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
                config: RightClickProConfig(actions: [action]),
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [invalidBookmark])
            ),
            operationLog: log,
            cutClipboard: InMemoryCutClipboardStore(),
            urlOpener: RecordingURLOpener(),
            developerAppOpener: RecordingURLOpener()
        )

        let result = runner.run(
            ActionRequest(
                actionID: action.id,
                context: FinderContext(invocation: .container, targetDirectory: directory)
            )
        )

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.message, ActionRunnerError.missingPayload("directoryID").localizedDescription)
        let record = try XCTUnwrap(log.loadRecent().first)
        XCTAssertEqual(record.status, .failure)
        XCTAssertEqual(record.message, result.message)
    }

    func testDirectoryActionInvalidBookmarkPreservesFailureOperationLog() throws {
        let directory = try temporaryDirectory()
        let invalidBookmark = DirectoryBookmark(
            id: "broken",
            displayName: "Broken",
            path: directory.appendingPathComponent("broken").path,
            bookmarkDataBase64: "not-valid-base64"
        )
        let action = RightClickProAction(
            id: "open-directory",
            title: "Open Directory",
            kind: .openDirectory,
            visibility: [.container],
            placement: .submenu,
            group: .commonDirectories,
            order: 1,
            payload: ActionPayload(directoryID: invalidBookmark.id)
        )
        let log = InMemoryOperationLog()
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
                config: RightClickProConfig(actions: [action]),
                bookmarkCatalog: DirectoryBookmarkCatalog(bookmarks: [invalidBookmark])
            ),
            operationLog: log,
            cutClipboard: InMemoryCutClipboardStore(),
            urlOpener: opener,
            developerAppOpener: RecordingURLOpener()
        )

        let result = runner.run(
            ActionRequest(
                actionID: action.id,
                context: FinderContext(invocation: .container, targetDirectory: directory)
            )
        )

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.message, BookmarkError.invalidBookmarkData(invalidBookmark.id).localizedDescription)
        XCTAssertTrue(opener.openedURLs.isEmpty)
        let record = try XCTUnwrap(log.loadRecent().first)
        XCTAssertEqual(record.status, .failure)
        XCTAssertEqual(record.message, result.message)
    }

    func testOpenDirectoryUsesResolvedBookmarkURL() throws {
        let resolvedDirectory = try temporaryDirectory()
        let staleFallbackDirectory = URL(fileURLWithPath: "/RightClickProTests/stale")
        let bookmark = DirectoryBookmark(id: "workspace", displayName: "Workspace", path: staleFallbackDirectory.path)
        let action = RightClickProAction(
            id: "open-workspace",
            title: "Open Workspace",
            kind: .openDirectory,
            visibility: [.container],
            placement: .submenu,
            group: .commonDirectories,
            order: 1,
            payload: ActionPayload(directoryID: "workspace")
        )
        let config = RightClickProConfig(
            shortcutDirectoryIDs: ["workspace"],
            actions: [action]
        )
        let log = InMemoryOperationLog()
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
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
        let action = RightClickProAction(
            id: "open-test-app",
            title: "Open in Test App",
            kind: .openInApp,
            visibility: [.selection, .container, .toolbar],
            placement: .submenu,
            group: .developerEntrypoints,
            order: 1,
            payload: ActionPayload(developerEntrypointID: entrypoint.id)
        )
        let config = RightClickProConfig(
            shortcutDirectoryIDs: ["workspace"],
            actions: [action],
            developerEntrypoints: [entrypoint]
        )
        let opener = RecordingURLOpener()
        let runner = ActionRunner(
            configProvider: StaticRightClickProConfigProvider(
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
