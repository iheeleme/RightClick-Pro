import XCTest
@testable import RightClickProCore

final class FinderExtensionInstallSignatureTests: XCTestCase {
    func testSignatureChangesWhenSameVersionExtensionIsReinstalledAtSamePath() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickProSignatureTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        let bundle = try makeFinderExtensionBundle(rootURL: rootURL)
        let fixedModifiedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedModifiedAt],
            ofItemAtPath: bundle.executableURL.path
        )

        let firstSignature = FinderExtensionInstallSignature.make(
            appexURL: bundle.appexURL,
            hostBundleURL: bundle.appURL
        )

        try FileManager.default.removeItem(at: bundle.executableURL)
        try Data("extension-binary".utf8).write(to: bundle.executableURL)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedModifiedAt],
            ofItemAtPath: bundle.executableURL.path
        )

        let secondSignature = FinderExtensionInstallSignature.make(
            appexURL: bundle.appexURL,
            hostBundleURL: bundle.appURL
        )

        XCTAssertNotEqual(firstSignature, secondSignature)
    }

    private func makeFinderExtensionBundle(rootURL: URL) throws -> (
        appURL: URL,
        appexURL: URL,
        executableURL: URL
    ) {
        let appURL = rootURL.appendingPathComponent("RightClick Pro.app", isDirectory: true)
        let appexURL = appURL
            .appendingPathComponent("Contents/PlugIns/RightClickProFinderExtension.appex", isDirectory: true)
        let contentsURL = appexURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let executableURL = macOSURL.appendingPathComponent("RightClickProFinderExtension")

        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleExecutable": "RightClickProFinderExtension",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "42"
        ]
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try Data("extension-binary".utf8).write(to: executableURL)

        return (appURL, appexURL, executableURL)
    }
}
