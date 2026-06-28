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
