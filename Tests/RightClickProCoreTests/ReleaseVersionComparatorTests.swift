import XCTest
@testable import RightClickProCore

final class ReleaseVersionComparatorTests: XCTestCase {
    func testDetectsNewerLatestRelease() {
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2.3", latestTag: "v1.3.0"),
            .updateAvailable
        )
    }

    func testTreatsEqualVersionWithLeadingVAsUpToDate() {
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2.3", latestTag: "v1.2.3"),
            .upToDate
        )
    }

    func testTreatsOlderLatestReleaseAsUpToDate() {
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2.3", latestTag: "v1.2.2"),
            .upToDate
        )
    }

    func testPadsShortVersionsForComparison() {
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2", latestTag: "v1.2.0"),
            .upToDate
        )
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2.3", latestTag: "v1.2.3.0"),
            .upToDate
        )
    }

    func testIgnoresLocalDevSuffixForNumericComparison() {
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2.3-dev", latestTag: "v1.2.4"),
            .updateAvailable
        )
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2.3-dev", latestTag: "v1.2.3"),
            .upToDate
        )
    }

    func testReturnsUnknownForMalformedVersions() {
        XCTAssertEqual(
            ReleaseVersionComparator.compare(currentVersion: "1.2.3", latestTag: "release-v1.2.4"),
            .unknown
        )
    }
}
