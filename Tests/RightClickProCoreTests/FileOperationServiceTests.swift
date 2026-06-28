import XCTest
@testable import RightClickProCore

final class FileOperationServiceTests: XCTestCase {
    func testCreateFileKeepsBothWhenDestinationExists() throws {
        let directory = try temporaryDirectory()
        let existing = directory.appendingPathComponent("README.md")
        try "# Existing\n".write(to: existing, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: FixedConflictResolver(.keepBoth))
        let template = FileTemplate(id: "readme", title: "Readme", defaultFileName: "README.md", contents: "# New\n")

        let outcome = try service.createFile(template: template, in: directory)

        XCTAssertEqual(outcome.destinationURL.lastPathComponent, "README copy.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.destinationURL.path))
    }

    func testCopyKeepsBothWhenDestinationExists() throws {
        let sourceDirectory = try temporaryDirectory()
        let destinationDirectory = try temporaryDirectory()
        let source = sourceDirectory.appendingPathComponent("notes.txt")
        let existing = destinationDirectory.appendingPathComponent("notes.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: FixedConflictResolver(.keepBoth))

        let outcomes = try service.copy([source], to: destinationDirectory)

        XCTAssertEqual(outcomes.first?.destinationURL.lastPathComponent, "notes copy.txt")
    }
}
