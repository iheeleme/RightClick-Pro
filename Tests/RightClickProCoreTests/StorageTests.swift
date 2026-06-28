import XCTest
@testable import RightClickProCore

final class StorageTests: XCTestCase {
    func testJSONFileStoreRoundTripsConfig() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("config.json")
        let store = JSONFileStore<RightClickProConfig>(url: url)
        let config = RightClickProConfig(maxRootMenuActions: 3)

        try store.save(config)
        let loaded = try store.loadRequired()

        XCTAssertEqual(loaded.maxRootMenuActions, 3)
        XCTAssertEqual(loaded.schemaVersion, RightClickProConstants.currentSchemaVersion)
    }

    func testOperationLogCapsRecords() throws {
        let directory = try temporaryDirectory()
        let log = JSONLineOperationLog(url: directory.appendingPathComponent("operation-log.jsonl"), maxRecords: 2)

        try log.append(OperationRecord(actionID: "a", kind: .cut, status: .success))
        try log.append(OperationRecord(actionID: "b", kind: .paste, status: .success))
        try log.append(OperationRecord(actionID: "c", kind: .copy, status: .success))

        let records = try log.loadRecent()
        XCTAssertEqual(records.map(\.actionID), ["b", "c"])
    }

    func testConfigDecodesOldJSONWithDefaultCommandTemplates() throws {
        let json = """
        {
          "schemaVersion": 1,
          "maxRootMenuActions": 5,
          "monitoredDirectoryIDs": [],
          "commonDirectoryIDs": [],
          "actions": [],
          "fileTemplates": [],
          "developerEntrypoints": []
        }
        """

        let config = try JSONDecoder().decode(RightClickProConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.commandTemplates.map(\.id), RightClickProConfig.defaultCommandTemplates().map(\.id))
    }
}
