import XCTest
@testable import RightToolCore

final class ConfigurationBootstrapperTests: XCTestCase {
    func testBootstrapCreatesConfigBookmarksAndDirectoryActions() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightToolStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let bootstrapper = ConfigurationBootstrapper()

        let result = try bootstrapper.bootstrap(paths: paths)

        XCTAssertTrue(result.didCreateConfig)
        XCTAssertTrue(result.didCreateBookmarks)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.bookmarksURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.operationLogURL.path))
        XCTAssertFalse(result.config.actions.isEmpty)
        XCTAssertTrue(result.config.actions.contains { $0.kind == .createFile })
        XCTAssertTrue(result.config.actions.contains { $0.kind == .openInApp })

        if !result.bookmarks.bookmarks.isEmpty {
            XCTAssertTrue(result.config.actions.contains { $0.kind == .openDirectory })
            XCTAssertEqual(result.config.monitoredDirectoryIDs, result.bookmarks.bookmarks.map(\.id))
            XCTAssertEqual(result.config.commonDirectoryIDs, result.bookmarks.bookmarks.map(\.id))
        }
    }
}
