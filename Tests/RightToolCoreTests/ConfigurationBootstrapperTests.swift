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
        XCTAssertTrue(result.config.actions.contains { $0.kind == .runCommand })

        if !result.bookmarks.bookmarks.isEmpty {
            XCTAssertTrue(result.config.actions.contains { $0.kind == .openDirectory })
            XCTAssertEqual(result.config.monitoredDirectoryIDs, result.bookmarks.bookmarks.map(\.id))
            XCTAssertEqual(result.config.commonDirectoryIDs, result.bookmarks.bookmarks.map(\.id))
        }
    }

    func testDefaultBookmarksUseRealHomeWhenProcessHomeIsSandboxContainer() throws {
        let baseDirectory = try temporaryDirectory()
        let processHome = baseDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(RightToolConstants.mainAppBundleIdentifier)
            .appendingPathComponent("Data")
        let realHome = baseDirectory.appendingPathComponent("real-home")
        try FileManager.default.createDirectory(
            at: realHome.appendingPathComponent("Desktop"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: realHome.appendingPathComponent("Downloads"),
            withIntermediateDirectories: true
        )

        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: processHome,
            realUserHomeDirectory: realHome
        )

        let bookmarks = bootstrapper.defaultBookmarks().bookmarks

        XCTAssertEqual(bookmarks.map(\.path).sorted(), [
            realHome.appendingPathComponent("Desktop").path,
            realHome.appendingPathComponent("Downloads").path
        ].sorted())
        XCTAssertFalse(bookmarks.contains { $0.path.hasPrefix(processHome.path) })
    }

    func testBootstrapSanitizesExistingSandboxContainerBookmarks() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightToolStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let processHome = baseDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(RightToolConstants.mainAppBundleIdentifier)
            .appendingPathComponent("Data")
        let realHome = baseDirectory.appendingPathComponent("real-home")
        let createdAt = Date(timeIntervalSince1970: 100)
        let unchangedPath = processHome
            .deletingLastPathComponent()
            .appendingPathComponent("DataBackup")
            .appendingPathComponent("Desktop")
            .path
        let existingBookmarks = DirectoryBookmarkCatalog(bookmarks: [
            DirectoryBookmark(
                id: "desktop",
                displayName: "桌面",
                path: processHome.appendingPathComponent("Desktop").path,
                bookmarkDataBase64: "bookmark-data",
                addedAt: createdAt
            ),
            DirectoryBookmark(
                id: "backup",
                displayName: "Backup",
                path: unchangedPath,
                addedAt: createdAt
            )
        ])
        try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(existingBookmarks)
        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: processHome,
            realUserHomeDirectory: realHome
        )

        let result = try bootstrapper.bootstrap(paths: paths)
        let savedBookmarks = try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).loadRequired()

        XCTAssertFalse(result.didCreateBookmarks)
        XCTAssertEqual(
            savedBookmarks.bookmark(id: "desktop")?.path,
            realHome.appendingPathComponent("Desktop").path
        )
        XCTAssertEqual(savedBookmarks.bookmark(id: "desktop")?.bookmarkDataBase64, "bookmark-data")
        XCTAssertEqual(savedBookmarks.bookmark(id: "desktop")?.addedAt, createdAt)
        XCTAssertEqual(savedBookmarks.bookmark(id: "backup")?.path, unchangedPath)
        XCTAssertEqual(result.config.monitoredDirectoryIDs, ["desktop", "backup"])
    }

    func testBootstrapRepairsMissingDefaultDirectoryInjection() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightToolStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let processHome = baseDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(RightToolConstants.mainAppBundleIdentifier)
            .appendingPathComponent("Data")
        let realHome = baseDirectory.appendingPathComponent("real-home")
        let desktop = realHome.appendingPathComponent("Desktop")
        let code = realHome.appendingPathComponent("Code")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)

        let existingBookmarks = DirectoryBookmarkCatalog(bookmarks: [
            DirectoryBookmark(id: "desktop", displayName: "桌面", path: desktop.path)
        ])
        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: processHome,
            realUserHomeDirectory: realHome
        )
        var existingConfig = bootstrapper.defaultConfig(bookmarks: existingBookmarks)
        existingConfig.actions.append(
            RightToolAction(
                id: "custom-action",
                title: "Custom",
                kind: .paste,
                visibility: [.container],
                placement: .submenu,
                order: 999
            )
        )
        try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(existingBookmarks)
        try JSONFileStore<RightToolConfig>(url: paths.configURL).save(existingConfig)

        let result = try bootstrapper.bootstrap(paths: paths)
        let savedBookmarks = try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).loadRequired()
        let savedConfig = try JSONFileStore<RightToolConfig>(url: paths.configURL).loadRequired()

        XCTAssertFalse(result.didCreateBookmarks)
        XCTAssertFalse(result.didCreateConfig)
        XCTAssertEqual(savedBookmarks.bookmark(id: "code")?.path, code.path)
        XCTAssertEqual(savedConfig.monitoredDirectoryIDs, ["desktop", "code"])
        XCTAssertEqual(savedConfig.commonDirectoryIDs, ["desktop", "code"])
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "custom-action" })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "open-directory-code" })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "move-to-code" })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "copy-to-code" })
    }

    func testBootstrapRepairsMissingCommandActionsForExistingTemplates() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightToolStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        var config = RightToolConfig(actions: [], commandTemplates: [
            CommandTemplate(id: "command-custom", title: "Custom Command", command: "pwd")
        ])
        config.fileTemplates = []
        config.developerEntrypoints = []
        try JSONFileStore<RightToolConfig>(url: paths.configURL).save(config)

        _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
        let savedConfig = try JSONFileStore<RightToolConfig>(url: paths.configURL).loadRequired()

        XCTAssertTrue(savedConfig.actions.contains { action in
            action.kind == .runCommand && action.payload.commandTemplateID == "command-custom"
        })
    }

    func testBootstrapRepairsBuiltInDeveloperEntrypointsToDynamicTarget() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightToolStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        var config = RightToolConfig()
        config.developerEntrypoints = RightToolConfig.defaultDeveloperEntrypoints().map { entrypoint in
            DeveloperEntrypoint(
                id: entrypoint.id,
                title: entrypoint.title,
                bundleIdentifier: entrypoint.bundleIdentifier,
                targetMode: .currentDirectory
            )
        }
        try JSONFileStore<RightToolConfig>(url: paths.configURL).save(config)

        let result = try ConfigurationBootstrapper().bootstrap(paths: paths)

        XCTAssertTrue(result.config.developerEntrypoints.allSatisfy { $0.targetMode == .dynamic })
    }
}
