import XCTest
@testable import RightClickProCore

final class FinderSyncScopeTests: XCTestCase {
    func testSyncRootsUseGlobalRoot() {
        let roots = FinderSyncScope.syncRoots()

        XCTAssertEqual(roots.map(\.path), ["/"])
    }

    func testGlobalScopeAcceptsAnyFinderContext() {
        let context = FinderContext(
            invocation: .selection,
            targetDirectory: URL(fileURLWithPath: "/System"),
            selectedItems: [URL(fileURLWithPath: "/Users/test/Desktop/file.txt")]
        )

        XCTAssertTrue(FinderSyncScope.contextIsInGlobalScope(context))
    }
}
