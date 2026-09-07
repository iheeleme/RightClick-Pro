import XCTest
import RightClickProCore
@testable import RightClickProAppPreview

final class SettingsViewModelTests: XCTestCase {
    @MainActor
    func testCommandSecretChangesOnlyAfterConfigurationSave() async throws {
        let (viewModel, paths, secrets) = try fixture()
        var draft = CommandTemplateDraft(template: viewModel.config.commandTemplates[0])
        draft.environmentText = "TOKEN!=new-value"

        viewModel.upsertCommandTemplate(draft)

        XCTAssertEqual(secrets.secrets, ["saved-reference": "saved-value"])
        XCTAssertEqual(try savedTemplate(paths).environment[0].secretReference, "saved-reference")

        viewModel.saveConfig()

        let reference = try XCTUnwrap(savedTemplate(paths).environment[0].secretReference)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertNotEqual(reference, "saved-reference")
        XCTAssertEqual(secrets.secrets, [reference: "new-value"])
    }

    @MainActor
    func testFailedSaveRollsBackNewSecretsAndCanBeRetried() async throws {
        let (viewModel, paths, secrets) = try fixture()
        var draft = CommandTemplateDraft(template: viewModel.config.commandTemplates[0])
        draft.environmentText = "TOKEN!=new-value"
        viewModel.upsertCommandTemplate(draft)
        try FileManager.default.removeItem(at: paths.bookmarksURL)
        try FileManager.default.createDirectory(at: paths.bookmarksURL, withIntermediateDirectories: true)

        viewModel.saveConfig()

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(secrets.secrets, ["saved-reference": "saved-value"])
        XCTAssertEqual(try savedTemplate(paths).environment[0].secretReference, "saved-reference")

        try FileManager.default.removeItem(at: paths.bookmarksURL)
        viewModel.saveConfig()

        let reference = try XCTUnwrap(savedTemplate(paths).environment[0].secretReference)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(secrets.secrets, [reference: "new-value"])
    }

    @MainActor
    func testConfigurationWriteFailureRestoresPreviousBookmarks() async throws {
        let (originalModel, paths, secrets) = try fixture()
        var blockedPaths = paths
        blockedPaths.configURL = paths.baseURL.appendingPathComponent("blocked-config")
        try FileManager.default.createDirectory(at: blockedPaths.configURL, withIntermediateDirectories: true)
        let previousBookmarks = try Data(contentsOf: paths.bookmarksURL)
        let viewModel = SettingsViewModel(paths: blockedPaths, commandSecretStore: secrets)
        viewModel.config = originalModel.config
        viewModel.bookmarks = DirectoryBookmarkCatalog(bookmarks: [
            DirectoryBookmark(id: "new", displayName: "New", path: paths.baseURL.path)
        ])
        var draft = CommandTemplateDraft(template: viewModel.config.commandTemplates[0])
        draft.environmentText = "TOKEN!=new-value"
        viewModel.upsertCommandTemplate(draft)

        viewModel.saveConfig()

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: paths.bookmarksURL), previousBookmarks)
        XCTAssertEqual(secrets.secrets, ["saved-reference": "saved-value"])

        try FileManager.default.removeItem(at: blockedPaths.configURL)
        try JSONFileStore<RightClickProConfig>(url: blockedPaths.configURL).save(originalModel.config)
        viewModel.saveConfig()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(
            try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).loadRequired(),
            viewModel.bookmarks
        )
        let reference = try XCTUnwrap(savedTemplate(blockedPaths).environment[0].secretReference)
        XCTAssertEqual(secrets.secrets, [reference: "new-value"])
    }

    @MainActor
    func testDeletingCommandKeepsSavedSecretUntilCommit() async throws {
        let (viewModel, paths, secrets) = try fixture()

        viewModel.deleteCommandTemplate(viewModel.config.commandTemplates[0])

        XCTAssertEqual(secrets.secrets, ["saved-reference": "saved-value"])
        XCTAssertEqual(try savedTemplate(paths).id, "command")

        viewModel.saveConfig()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertTrue(secrets.secrets.isEmpty)
        XCTAssertTrue(try JSONFileStore<RightClickProConfig>(url: paths.configURL).loadRequired().commandTemplates.isEmpty)
    }

    @MainActor
    func testReloadDiscardsPendingSecretChanges() async throws {
        let (viewModel, paths, secrets) = try fixture()
        var draft = CommandTemplateDraft(template: viewModel.config.commandTemplates[0])
        draft.environmentText = "TOKEN!=discarded-value"
        viewModel.upsertCommandTemplate(draft)

        viewModel.loadOrBootstrap()
        viewModel.saveConfig()

        XCTAssertEqual(secrets.secrets, ["saved-reference": "saved-value"])
        XCTAssertEqual(try savedTemplate(paths).environment[0].secretReference, "saved-reference")
    }

    @MainActor
    func testResetCanRepairMalformedConfiguration() async throws {
        let (viewModel, paths, secrets) = try fixture()
        try Data("invalid JSON".utf8).write(to: paths.configURL)

        viewModel.resetToDefaults()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(try JSONFileStore<RightClickProConfig>(url: paths.configURL).loadRequired().actions.isEmpty)
        XCTAssertTrue(secrets.secrets.isEmpty)
    }

    @MainActor
    func testUnsavedCommandIsBlockedBeforeOpeningRunWindow() async throws {
        let (viewModel, _, _) = try fixture()
        var draft = CommandTemplateDraft(template: viewModel.config.commandTemplates[0])
        draft.command = "printf changed"
        viewModel.upsertCommandTemplate(draft)

        viewModel.runCommandTemplateFromSettings(viewModel.config.commandTemplates[0])

        XCTAssertTrue(viewModel.statusMessage.contains("请先保存配置后再运行"))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    @MainActor
    private func fixture() throws -> (SettingsViewModel, RightClickProStoragePaths, InMemoryCommandSecretStore) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickProSettingsTests")
            .appendingPathComponent(UUID().uuidString)
        let paths = RightClickProStoragePaths(baseURL: directory)
        let secrets = InMemoryCommandSecretStore()
        try secrets.save(secret: "saved-value", reference: "saved-reference")
        let template = CommandTemplate(
            id: "command", title: "Command", command: "printf saved",
            environment: [CommandEnvironmentVariable(
                id: "token", name: "TOKEN", isSensitive: true, secretReference: "saved-reference"
            )]
        )
        let config = RightClickProConfig(actions: [], commandTemplates: [template])
        try JSONFileStore<RightClickProConfig>(url: paths.configURL).save(config)
        try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(DirectoryBookmarkCatalog())
        let viewModel = SettingsViewModel(paths: paths, commandSecretStore: secrets)
        viewModel.config = config
        return (viewModel, paths, secrets)
    }

    private func savedTemplate(_ paths: RightClickProStoragePaths) throws -> CommandTemplate {
        try XCTUnwrap(JSONFileStore<RightClickProConfig>(url: paths.configURL).loadRequired().commandTemplates.first)
    }
}
