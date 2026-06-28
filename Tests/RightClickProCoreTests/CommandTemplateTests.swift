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
}
