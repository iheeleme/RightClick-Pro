import XCTest
@testable import RightClickProCore

final class FinderSyncScopeTests: XCTestCase {
    func testSyncRootsUseParentDirectoryToAvoidMarkingSidebarFavoriteItself() {
        let codeURL = URL(fileURLWithPath: "/Users/test/Code")
        let downloadsURL = URL(fileURLWithPath: "/Users/test/Downloads")

        let roots = FinderSyncScope.syncRoots(for: [codeURL, downloadsURL])

        XCTAssertEqual(roots.map(\.path), ["/Users/test"])
    }

    func testContextFilterKeepsMenuScopedToConfiguredDirectory() {
        let codeURL = URL(fileURLWithPath: "/Users/test/Code")
        let insideCode = FinderContext(
            invocation: .container,
            targetDirectory: URL(fileURLWithPath: "/Users/test/Code/Project")
        )
        let outsideCode = FinderContext(
            invocation: .container,
            targetDirectory: URL(fileURLWithPath: "/Users/test/Desktop")
        )
        let selectedCode = FinderContext(
            invocation: .selection,
            targetDirectory: URL(fileURLWithPath: "/Users/test"),
            selectedItems: [codeURL]
        )

        XCTAssertTrue(FinderSyncScope.contextIsInsideMonitoredDirectories(insideCode, monitoredURLs: [codeURL]))
        XCTAssertTrue(FinderSyncScope.contextIsInsideMonitoredDirectories(selectedCode, monitoredURLs: [codeURL]))
        XCTAssertFalse(FinderSyncScope.contextIsInsideMonitoredDirectories(outsideCode, monitoredURLs: [codeURL]))
    }
}
