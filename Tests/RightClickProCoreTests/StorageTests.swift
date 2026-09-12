import XCTest
@testable import RightClickProCore

final class StorageTests: XCTestCase {
    func testActionResultSupportsLegacyPayloadAndRemainingURLsRoundTrip() throws {
        let result = ActionResult(
            requestID: UUID(), status: .failure, message: "Partial failure",
            affectedURLs: [URL(fileURLWithPath: "/tmp/completed.txt")],
            remainingURLs: [URL(fileURLWithPath: "/tmp/pending.txt")]
        )
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(ActionResult.self, from: data), result)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "remainingURLs")
        let decoded = try JSONDecoder().decode(
            ActionResult.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertEqual(decoded.affectedURLs, result.affectedURLs)
        XCTAssertEqual(decoded.remainingURLs, [])
    }

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

    func testConcurrentOperationLogWritersPreserveEveryRecord() throws {
        let url = try temporaryDirectory().appendingPathComponent("history.jsonl")
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            do {
                try JSONLineOperationLog(url: url).append(
                    OperationRecord(actionID: String(index), kind: .runCommand, status: .success)
                )
            } catch { XCTFail("Concurrent append failed: \(error)") }
        }
        let records = try JSONLineOperationLog(url: url).loadRecent()
        XCTAssertEqual(records.count, 100)
        XCTAssertEqual(Set(records.map(\.actionID)).count, 100)
    }

    func testPendingQueuePreservesConcurrentRequestsAndConsumesOnce() throws {
        let paths = RightClickProStoragePaths(baseURL: try temporaryDirectory())
        DispatchQueue.concurrentPerform(iterations: 50) { index in
            do {
                try PendingCommandRunQueue(paths: paths).enqueue(PendingCommandRunRequest(
                    actionID: String(index), context: FinderContext(invocation: .container, targetDirectory: paths.baseURL)
                ))
            } catch { XCTFail("Enqueue failed: \(error)") }
        }
        let delivered = paths.baseURL.appendingPathComponent("delivered")
        try FileManager.default.createDirectory(at: delivered, withIntermediateDirectories: true)
        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            do {
                while try PendingCommandRunQueue(paths: paths).consumeNext({ request in
                    let url = delivered.appendingPathComponent(request.actionID)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
                    try Data().write(to: url)
                }) {}
            } catch { XCTFail("Consume failed: \(error)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: delivered.path).count, 50)
    }

    func testCorruptPendingRequestDoesNotBlockHealthyRequests() throws {
        let paths = RightClickProStoragePaths(baseURL: try temporaryDirectory())
        let queue = PendingCommandRunQueue(paths: paths)
        let request = PendingCommandRunRequest(actionID: "healthy", context: FinderContext(invocation: .container, targetDirectory: paths.baseURL))
        try queue.enqueue(request)
        let corrupt = paths.baseURL.appendingPathComponent("pending-command-runs/broken.json")
        try Data("broken".utf8).write(to: corrupt)
        XCTAssertTrue(try queue.consumeNext { XCTAssertEqual($0, request) })
        XCTAssertThrowsError(try queue.consumeNext { _ in XCTFail("Unexpected delivery") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
    }

    func testPendingQueueRetainsRequestWhenDeliveryFails() throws {
        let paths = RightClickProStoragePaths(baseURL: try temporaryDirectory())
        let queue = PendingCommandRunQueue(paths: paths)
        let request = PendingCommandRunRequest(
            actionID: "retry", context: FinderContext(invocation: .container, targetDirectory: paths.baseURL)
        )
        try queue.enqueue(request)
        XCTAssertThrowsError(try queue.consumeNext { _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertTrue(try queue.consumeNext { XCTAssertEqual($0, request) })
        XCTAssertFalse(try queue.consumeNext { _ in XCTFail("Duplicate delivery") })
    }

    func testDefaultStoragePrefersApplicationSupportOverAppGroupContainer() throws {
        let directory = try temporaryDirectory()
        let homeDirectory = directory.appendingPathComponent("home")
        let appGroupDirectory = directory
            .appendingPathComponent("home")
            .appendingPathComponent("Library")
            .appendingPathComponent("Group Containers")
            .appendingPathComponent(RightClickProConstants.defaultAppGroupIdentifier)
        let fileManager = StoragePathFileManager(
            homeDirectory: homeDirectory,
            appGroupDirectory: appGroupDirectory
        )

        let paths = RightClickProStoragePaths.defaultForCurrentProcess(
            fileManager: fileManager,
            realUserHomeDirectory: homeDirectory
        )

        XCTAssertEqual(
            paths.baseURL.path,
            homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent(RightClickProConstants.mainAppBundleIdentifier)
                .path
        )
        XCTAssertFalse(paths.baseURL.path.contains("Group Containers"))
        XCTAssertFalse(fileManager.didRequestAppGroupContainer)
    }

    func testConfigDecodesV1JSONIntoShortcutDirectoriesAndDefaultCommandTemplates() throws {
        let json = """
        {
          "schemaVersion": 1,
          "maxRootMenuActions": 5,
          "monitoredDirectoryIDs": ["legacy-scope"],
          "commonDirectoryIDs": ["desktop", "downloads"],
          "actions": [],
          "fileTemplates": [],
          "developerEntrypoints": []
        }
        """

        let config = try JSONDecoder().decode(RightClickProConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.schemaVersion, 2)
        XCTAssertEqual(config.shortcutDirectoryIDs, ["desktop", "downloads"])
        XCTAssertEqual(config.commandTemplates.map(\.id), RightClickProConfig.defaultCommandTemplates().map(\.id))
    }

    func testConfigEncodesV2ShortcutDirectoriesOnly() throws {
        let config = RightClickProConfig(shortcutDirectoryIDs: ["desktop"])

        let data = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(object["shortcutDirectoryIDs"] as? [String], ["desktop"])
        XCTAssertNil(object["monitoredDirectoryIDs"])
        XCTAssertNil(object["commonDirectoryIDs"])
    }
}

private final class StoragePathFileManager: FileManager {
    private let providedHomeDirectory: URL
    private let appGroupDirectory: URL
    private(set) var didRequestAppGroupContainer = false

    init(homeDirectory: URL, appGroupDirectory: URL) {
        self.providedHomeDirectory = homeDirectory
        self.appGroupDirectory = appGroupDirectory
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        providedHomeDirectory
    }

    override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        didRequestAppGroupContainer = true
        return appGroupDirectory
    }
}
