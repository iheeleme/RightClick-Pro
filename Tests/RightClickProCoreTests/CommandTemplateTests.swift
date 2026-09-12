import XCTest
@testable import RightClickProCore

final class CommandTemplateTests: XCTestCase {
    func testCommandVariableInterpolationShellQuotesPaths() throws {
        let template = CommandTemplate(
            id: "command-echo",
            title: "Echo",
            command: "echo {{currentDirectory}} {{selectedPath}} {{selectedPaths}}"
        )
        let context = FinderContext(
            invocation: .selection,
            targetDirectory: URL(fileURLWithPath: "/tmp/Right Tool"),
            selectedItems: [
                URL(fileURLWithPath: "/tmp/Right Tool/a file.txt"),
                URL(fileURLWithPath: "/tmp/Right Tool/b.txt")
            ]
        )

        let command = try CommandTemplateVariableResolver.interpolatedCommand(template: template, context: context)

        XCTAssertEqual(
            command,
            "echo '/tmp/Right Tool' '/tmp/Right Tool/a file.txt' '/tmp/Right Tool/a file.txt' '/tmp/Right Tool/b.txt'"
        )
    }

    func testEnvironmentNameValidation() {
        XCTAssertTrue(CommandTemplateVariableResolver.validateEnvironmentName("API_KEY"))
        XCTAssertTrue(CommandTemplateVariableResolver.validateEnvironmentName("_TOKEN2"))
        XCTAssertFalse(CommandTemplateVariableResolver.validateEnvironmentName("2BAD"))
        XCTAssertFalse(CommandTemplateVariableResolver.validateEnvironmentName("BAD-NAME"))
    }

    func testInMemoryCommandSecretStoreRoundTripsSecret() throws {
        let store = InMemoryCommandSecretStore()

        try store.save(secret: "secret", reference: "ref")

        XCTAssertEqual(try store.load(reference: "ref"), "secret")
        try store.delete(reference: "ref")
        XCTAssertNil(try store.load(reference: "ref"))
    }

    func testPendingCommandRunRequestDecodesLegacyPayloadWithoutScopedBookmarks() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "actionID": "run-command",
          "context": {
            "invocation": "container",
            "targetDirectory": "/tmp",
            "selectedItems": []
          },
          "createdAt": 1782518400
        }
        """
        let decoder = JSONDecoder()

        let request = try decoder.decode(PendingCommandRunRequest.self, from: Data(json.utf8))

        XCTAssertEqual(request.actionID, "run-command")
        XCTAssertEqual(request.securityScopedBookmarks, [])
    }

    func testPendingCommandRunRequestOmitsEmptyScopedBookmarksWhenEncoded() throws {
        let request = PendingCommandRunRequest(
            actionID: "run-command",
            context: FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp"))
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(object["securityScopedBookmarks"])
    }

    func testPendingCommandRunRequestRoundTripsScopedBookmarks() throws {
        let request = PendingCommandRunRequest(
            actionID: "run-command",
            context: FinderContext(invocation: .container, targetDirectory: URL(fileURLWithPath: "/tmp")),
            securityScopedBookmarks: [
                PendingCommandScopedBookmark(path: "/tmp", bookmarkDataBase64: "Ym9va21hcms=")
            ]
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(PendingCommandRunRequest.self, from: data)

        XCTAssertEqual(decoded.securityScopedBookmarks, request.securityScopedBookmarks)
    }

    func testCommandRunServiceWritesRealtimeSnapshotAndLogsCompletion() throws {
        let directory = try temporaryDirectory()
        let action = RightClickProAction(
            id: "run-command-echo",
            title: "Echo",
            kind: .runCommand,
            visibility: [.container],
            placement: .submenu,
            group: .commandTemplates,
            order: 1,
            payload: ActionPayload(commandTemplateID: "command-echo")
        )
        let template = CommandTemplate(
            id: "command-echo",
            title: "Echo",
            command: "printf hello"
        )
        let log = InMemoryOperationLog()
        let service = CommandRunService(
            paths: RightClickProStoragePaths(baseURL: directory.appendingPathComponent("state")),
            configProvider: StaticRightClickProConfigProvider(
                config: RightClickProConfig(actions: [action], commandTemplates: [template])
            ),
            operationLog: log,
            secretStore: InMemoryCommandSecretStore()
        )
        let request = PendingCommandRunRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: directory)
        )

        let finalSnapshot = try waitForCommandRunToFinish(service.start(request), service: service)

        XCTAssertEqual(finalSnapshot.status, .succeeded)
        XCTAssertTrue(finalSnapshot.combinedOutput.contains("hello"))
        XCTAssertEqual(try log.loadRecent().first?.status, .success)
    }

    func testCommandRunServiceStopsRunningCommand() throws {
        let directory = try temporaryDirectory()
        let action = RightClickProAction(
            id: "run-command-sleep",
            title: "Sleep",
            kind: .runCommand,
            visibility: [.container],
            placement: .submenu,
            group: .commandTemplates,
            order: 1,
            payload: ActionPayload(commandTemplateID: "command-sleep")
        )
        let template = CommandTemplate(
            id: "command-sleep",
            title: "Sleep",
            command: "sleep 5",
            timeoutSeconds: 10
        )
        let service = CommandRunService(
            paths: RightClickProStoragePaths(baseURL: directory.appendingPathComponent("state")),
            configProvider: StaticRightClickProConfigProvider(
                config: RightClickProConfig(actions: [action], commandTemplates: [template])
            ),
            operationLog: InMemoryOperationLog(),
            secretStore: InMemoryCommandSecretStore()
        )
        let request = PendingCommandRunRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: directory)
        )

        let initialSnapshot = service.start(request)
        _ = try service.stop(runID: initialSnapshot.id)
        let finalSnapshot = try waitForCommandRunToFinish(initialSnapshot, service: service)

        XCTAssertEqual(finalSnapshot.status, .stopped)
    }

    func testTimeoutForceTerminatesCommandIgnoringSIGTERM() throws {
        let (service, request) = try commandRunFixture(
            command: "trap '' TERM; while :; do sleep 1; done",
            timeoutSeconds: 5
        )
        defer { _ = try? service.stop(runID: request.id) }

        let snapshot = try waitForCommandRunToFinish(service.start(request), service: service, timeout: 10)

        XCTAssertEqual(snapshot.status, .timedOut)
        XCTAssertNotNil(snapshot.finishedAt)
        XCTAssertLessThan(try XCTUnwrap(snapshot.durationMilliseconds), 9000)
    }

    func testCommandOutputPreservesSplitUTF8AndFlushesIncompleteTail() throws {
        let (service, request) = try commandRunFixture(
            command: "printf '\\344'; sleep 0.1; printf '\\270\\255'; printf '\\360\\237' >&2; sleep 0.1; printf '\\230\\200' >&2; printf '\\342'"
        )

        let snapshot = try waitForCommandRunToFinish(service.start(request), service: service)

        XCTAssertEqual(snapshot.status, .succeeded)
        XCTAssertEqual(snapshot.outputChunks.filter { $0.stream == .stdout }.map(\.text).joined(), "\u{4e2d}\u{fffd}")
        XCTAssertEqual(snapshot.outputChunks.filter { $0.stream == .stderr }.map(\.text).joined(), "\u{1f600}")
    }

    func testServiceRestartFinalizesInterruptedSnapshotsOnce() throws {
        let paths = RightClickProStoragePaths(baseURL: try temporaryDirectory())
        let interrupted = CommandRunSnapshot(
            id: UUID(), actionID: "interrupted", status: .running,
            startedAt: Date().addingTimeInterval(-10)
        )
        let completed = CommandRunSnapshot(id: UUID(), actionID: "completed", status: .succeeded)
        for snapshot in [interrupted, completed] {
            try JSONFileStore<CommandRunSnapshot>(
                url: paths.commandRunStateDirectoryURL.appendingPathComponent("\(snapshot.id.uuidString).json")
            ).save(snapshot)
        }
        let log = InMemoryOperationLog()

        let service = CommandRunService(paths: paths, operationLog: log, secretStore: InMemoryCommandSecretStore())
        let recovered = try service.status(for: interrupted.id)
        XCTAssertEqual(recovered.status, .error)
        XCTAssertNotNil(recovered.finishedAt)
        XCTAssertNotNil(recovered.errorMessage)
        XCTAssertEqual(try service.stop(runID: interrupted.id).status, .error)
        XCTAssertEqual(try service.status(for: completed.id), completed)
        XCTAssertEqual(log.records.map(\.kind), [.runCommand])
        XCTAssertEqual(log.records.map(\.status), [.failure])

        _ = CommandRunService(paths: paths, operationLog: log, secretStore: InMemoryCommandSecretStore())
        XCTAssertEqual(log.records.count, 1)
    }

    func testSecondServiceDoesNotRecoverAnotherServicesActiveRun() throws {
        let directory = try temporaryDirectory()
        let paths = RightClickProStoragePaths(baseURL: directory.appendingPathComponent("state"))
        let template = CommandTemplate(id: "active", title: "Active", command: "sleep 1; printf completed")
        let action = RightClickProAction(
            id: "active", title: "Active", kind: .runCommand,
            visibility: [.container], placement: .submenu, order: 1,
            payload: ActionPayload(commandTemplateID: template.id)
        )
        let owner = CommandRunService(
            paths: paths,
            configProvider: StaticRightClickProConfigProvider(
                config: RightClickProConfig(actions: [action], commandTemplates: [template])
            ),
            secretStore: InMemoryCommandSecretStore()
        )
        let request = PendingCommandRunRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: directory)
        )
        let initial = owner.start(request)

        let observer = CommandRunService(paths: paths, secretStore: InMemoryCommandSecretStore())

        XCTAssertEqual(try observer.status(for: request.id).status, .running)
        XCTAssertEqual(try waitForCommandRunToFinish(initial, service: owner).status, .succeeded)
        XCTAssertEqual(try observer.status(for: request.id).status, .succeeded)
    }

    func testExistingObserverRecoversNewlyOrphanedSnapshot() throws {
        let paths = RightClickProStoragePaths(baseURL: try temporaryDirectory())
        let log = InMemoryOperationLog()
        let observer = CommandRunService(paths: paths, operationLog: log, secretStore: InMemoryCommandSecretStore())
        let snapshot = CommandRunSnapshot(id: UUID(), actionID: "late-orphan", status: .running, startedAt: Date())
        try JSONFileStore<CommandRunSnapshot>(
            url: paths.commandRunStateDirectoryURL.appendingPathComponent("\(snapshot.id.uuidString).json")
        ).save(snapshot)
        XCTAssertEqual(try observer.status(for: snapshot.id).status, .error)
        XCTAssertEqual(try observer.stop(runID: snapshot.id).status, .error)
        XCTAssertEqual(log.records.count, 1)
    }

    func testTerminalPersistenceFailureRetainsResultAndRetries() throws {
        let directory = try temporaryDirectory()
        let paths = RightClickProStoragePaths(baseURL: directory)
        let template = CommandTemplate(id: "persist", title: "Persist", command: "sleep 1; printf done")
        let action = RightClickProAction(
            id: "persist", title: "Persist", kind: .runCommand,
            visibility: [.container], placement: .submenu, order: 1,
            payload: ActionPayload(commandTemplateID: template.id)
        )
        let service = CommandRunService(
            paths: paths,
            configProvider: StaticRightClickProConfigProvider(config: RightClickProConfig(actions: [action], commandTemplates: [template])),
            secretStore: InMemoryCommandSecretStore()
        )
        let request = PendingCommandRunRequest(actionID: action.id, context: FinderContext(invocation: .container, targetDirectory: directory))
        let initial = service.start(request)
        let backup = directory.appendingPathComponent("saved-runs")
        try FileManager.default.moveItem(at: paths.commandRunStateDirectoryURL, to: backup)
        try Data().write(to: paths.commandRunStateDirectoryURL)
        let terminal = try waitForCommandRunToFinish(initial, service: service)
        XCTAssertEqual(terminal.status, .succeeded)
        XCTAssertTrue(terminal.combinedOutput.contains("运行结果保存失败"))
        XCTAssertEqual(try JSONLineOperationLog(url: paths.operationLogURL).loadRecent().count, 1)
        try FileManager.default.removeItem(at: paths.commandRunStateDirectoryURL)
        try FileManager.default.moveItem(at: backup, to: paths.commandRunStateDirectoryURL)
        let store = JSONFileStore<CommandRunSnapshot>(url: paths.commandRunStateDirectoryURL.appendingPathComponent("\(request.id.uuidString).json"))
        let deadline = Date().addingTimeInterval(5)
        while !(try store.loadRequired()).status.isTerminal && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertEqual(try store.loadRequired().status, .succeeded)
        XCTAssertEqual(service.start(request).status, .succeeded)
    }

    private func commandRunFixture(
        command: String,
        timeoutSeconds: Int = 5
    ) throws -> (CommandRunService, PendingCommandRunRequest) {
        let directory = try temporaryDirectory()
        let template = CommandTemplate(id: "command", title: "Command", command: command, timeoutSeconds: timeoutSeconds)
        let action = RightClickProAction(
            id: "run-command", title: "Command", kind: .runCommand,
            visibility: [.container], placement: .submenu, order: 1,
            payload: ActionPayload(commandTemplateID: template.id)
        )
        let service = CommandRunService(
            paths: RightClickProStoragePaths(baseURL: directory.appendingPathComponent("state")),
            configProvider: StaticRightClickProConfigProvider(
                config: RightClickProConfig(actions: [action], commandTemplates: [template])
            ),
            secretStore: InMemoryCommandSecretStore()
        )
        let request = PendingCommandRunRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: directory)
        )
        return (service, request)
    }

    private func waitForCommandRunToFinish(
        _ initialSnapshot: CommandRunSnapshot,
        service: CommandRunService,
        timeout: TimeInterval = 5
    ) throws -> CommandRunSnapshot {
        var snapshot = initialSnapshot
        let deadline = Date().addingTimeInterval(timeout)
        while !snapshot.status.isTerminal && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
            snapshot = try service.status(for: snapshot.id)
        }
        return snapshot
    }
}
