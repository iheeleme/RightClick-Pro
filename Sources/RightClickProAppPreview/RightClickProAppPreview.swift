import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

private enum AppMetadata {
    static let displayName = "RightClick Pro"

    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "0.0.0-dev"
        let build = (info["CFBundleVersion"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        guard let build, build != version else {
            return "版本 \(version)"
        }
        return "版本 \(version) (\(build))"
    }
}

private enum FinderExtensionSetupDefaults {
    static let completedSignatureKey = "RightClickPro.completedFinderExtensionSetupSignature"
}

@main
struct RightClickProAppPreview: App {
    @NSApplicationDelegateAdaptor(RightClickProAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = SettingsViewModel.bootstrap()

    var body: some Scene {
        MenuBarExtra(AppMetadata.displayName, systemImage: "contextualmenu.and.cursorarrow") {
            MenuBarContentView(viewModel: viewModel)
        }

        Window("\(AppMetadata.displayName) 设置", id: "settings") {
            SettingsRootView(viewModel: viewModel)
                .frame(minWidth: 1180, idealWidth: 1448, maxWidth: .infinity, minHeight: 760, idealHeight: 980, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class RightClickProAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyApplicationMenuTitle()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyApplicationMenuTitle()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func applyApplicationMenuTitle() {
        NSApplication.shared.mainMenu?.items.first?.title = AppMetadata.displayName
    }
}

final class SettingsViewModel: NSObject, ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case onboarding = "概览"
        case actions = "右键菜单管理"
        case directories = "常用目录快捷直达"
        case developer = "开发者快捷入口"
        case commands = "命令模板"
        case history = "剪切 / 粘贴文件"
        case templates = "新建文件模板"

        var id: String { rawValue }

        var sidebarTitle: String {
            switch self {
            case .onboarding:
                return "概览"
            case .actions:
                return "右键菜单管理"
            case .directories:
                return "常用目录快捷直达"
            case .developer:
                return "开发者快捷入口"
            case .commands:
                return "命令模板"
            case .history:
                return "文件操作"
            case .templates:
                return "新建文件"
            }
        }

        var systemImage: String {
            switch self {
            case .onboarding:
                return "house"
            case .actions:
                return "list.bullet.indent"
            case .directories:
                return "folder"
            case .developer:
                return "chevron.left.forwardslash.chevron.right"
            case .commands:
                return "terminal"
            case .history:
                return "scissors"
            case .templates:
                return "doc"
            }
        }

        var subtitle: String {
            switch self {
            case .onboarding:
                return "管理和自定义 Finder 右键菜单，提升操作效率。"
            case .actions:
                return "管理 Finder 右键菜单项的显示、排序与可用范围。"
            case .directories:
                return "管理常用目录，快速访问，提高工作效率。"
            case .developer:
                return "管理开发者常用工具、仓库与目录的快捷入口，支持在 Finder 右键菜单中快速打开。"
            case .commands:
                return "配置可重复执行的命令模板，并用实时输出窗口观察运行结果。"
            case .history:
                return "查看剪切、复制、粘贴等文件操作记录与菜单入口。"
            case .templates:
                return "管理 Finder 右键菜单中的新建文件类型、排序与启用状态。"
            }
        }
    }

    enum StatusTone {
        case neutral
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .neutral:
                return .secondary
            case .success:
                return .green
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }
    }

    @Published var selectedSection: Section = .onboarding
    @Published var config = RightClickProConfig()
    @Published var bookmarks = DirectoryBookmarkCatalog()
    @Published var storagePath = ""
    @Published var statusMessage = ""
    @Published var statusTone: StatusTone = .neutral
    @Published var hasUnsavedChanges = false
    @Published var recentOperations: [OperationRecord] = []
    @Published var developerEntrypointAddRequest = 0
    @Published var templateAddRequest = 0
    @Published var commandTemplateAddRequest = 0
    @Published var actionSearchText = ""
    @Published var isRepairingFinderMenu = false
    @Published var finderExtensionNeedsAttention = false
    @Published var finderExtensionSetupMessage = ""

    private var paths = RightClickProStoragePaths.defaultForCurrentProcess()
    private let commandSecretStore = KeychainCommandSecretStore()
    private let actionRunnerClient = RightClickProActionRunnerXPCClient()

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handlePendingCommandRunNotification),
            name: Notification.Name(RightClickProConstants.pendingCommandRunNotificationName),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePendingCommandRunNotification),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    static func bootstrap() -> SettingsViewModel {
        let viewModel = SettingsViewModel()
        viewModel.loadOrBootstrap()
        viewModel.scheduleFinderExtensionRegistration()
        return viewModel
    }

    var enabledActionCount: Int {
        config.actions.filter(\.isEnabled).count
    }

    var rootMenuActionCount: Int {
        config.actions.filter { $0.isEnabled && $0.placement == .rootMenu }.count
    }

    var disabledActionCount: Int {
        config.actions.filter { !$0.isEnabled }.count
    }

    var rootMenuActionProgress: Double {
        guard config.maxRootMenuActions > 0 else { return 0 }
        let ratio = Double(rootMenuActionCount) / Double(config.maxRootMenuActions)
        return min(max(ratio, 0), 1)
    }

    var shouldShowFinderExtensionSetupBanner: Bool {
        finderExtensionNeedsAttention
    }

    /// Section-level count shown as a sidebar badge.
    func sectionBadge(for section: Section) -> String? {
        let count: Int
        switch section {
        case .directories: count = bookmarks.bookmarks.count
        case .actions: count = enabledActionCount
        case .templates: count = config.fileTemplates.count
        case .developer: count = config.developerEntrypoints.count
        case .commands: count = config.commandTemplates.count
        case .history: count = recentOperations.count
        default: return nil
        }
        return count > 0 ? "\(count)" : nil
    }

    /// Sidebar groupings for visual scanning.
    enum SidebarGroup: String, CaseIterable, Identifiable {
        case guided = "概览"
        case editing = "配置"
        case records = "记录"

        var id: String { rawValue }
        var sections: [Section] {
            switch self {
            case .guided: return [.onboarding]
            case .editing: return [.actions, .directories, .developer, .commands, .templates]
            case .records: return [.history]
            }
        }
    }

    func loadOrBootstrap() {
        do {
            let result = try ConfigurationBootstrapper().bootstrap()
            apply(result: result)

            if result.didCreateConfig || result.didCreateBookmarks {
                setStatus("默认配置已自动注入", tone: .success)
            } else {
                setStatus("已加载本地配置", tone: .neutral)
            }
            checkForPendingCommandRun()
        } catch {
            setStatus("配置加载失败：\(error.localizedDescription)", tone: .error)
        }
    }

    func resetToDefaults() {
        do {
            let bootstrapper = ConfigurationBootstrapper()
            let defaultBookmarks = bootstrapper.defaultBookmarks()
            let defaultConfig = bootstrapper.defaultConfig(bookmarks: defaultBookmarks)

            try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(defaultBookmarks)
            try JSONFileStore<RightClickProConfig>(url: paths.configURL).save(defaultConfig)

            bookmarks = defaultBookmarks
            config = defaultConfig
            hasUnsavedChanges = false
            reloadRecentOperations()
            setStatus("已恢复默认预览配置", tone: .success)
        } catch {
            setStatus("恢复默认配置失败：\(error.localizedDescription)", tone: .error)
        }
    }

    func saveConfig() {
        do {
            try validateConfig()
            try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(bookmarks)
            try JSONFileStore<RightClickProConfig>(url: paths.configURL).save(config)
            hasUnsavedChanges = false
            setStatus("配置已保存，重新打开 Finder 右键菜单后生效", tone: .success)
        } catch {
            setStatus("保存失败：\(error.localizedDescription)", tone: .error)
        }
    }

    func openFinderExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.FinderSync") else {
            setStatus("无法打开 Finder 扩展设置，请手动前往系统设置 > 隐私与安全性 > 扩展", tone: .error)
            return
        }

        if NSWorkspace.shared.open(url) {
            setStatus("已打开系统设置，请启用 \(AppMetadata.displayName) Finder Extension", tone: .neutral)
        } else {
            setStatus("无法打开系统设置，请手动前往隐私与安全性 > 扩展 > Finder 扩展", tone: .warning)
        }
    }

    func restartFinder() {
        repairFinderContextMenu(restartFinder: true, userInitiated: true)
    }

    func repairFinderContextMenu(restartFinder: Bool = true, userInitiated: Bool = true) {
        guard !isRepairingFinderMenu else {
            return
        }

        guard let appexURL = bundledFinderExtensionURL() else {
            markFinderExtensionNeedsAttention(
                "找不到随 App 打包的 Finder Extension，请确认已从 DMG 拖入 Applications 后再打开"
            )
            setStatusIfUserInitiated(
                userInitiated,
                "找不到随 App 打包的 Finder Extension，请确认已从 DMG 拖入 Applications 后再打开",
                tone: .error
            )
            return
        }

        isRepairingFinderMenu = true
        if userInitiated {
            setStatus(
                restartFinder ? "正在修复右键菜单并重启 Finder..." : "正在注册 Finder Extension...",
                tone: .warning
            )
        }

        let task: SystemMaintenanceTask = restartFinder ? .repairFinderContextMenu : .installFinderExtension
        let request = SystemMaintenanceRequest(task: task, finderExtensionPath: appexURL.path)

        actionRunnerClient.performMaintenance(request) { [weak self] response in
            DispatchQueue.main.async {
                self?.isRepairingFinderMenu = false
                self?.handleFinderMaintenanceResponse(
                    response,
                    didRequestRestart: restartFinder,
                    userInitiated: userInitiated
                )
            }
        }
    }

    func reloadRecentOperations() {
        do {
            recentOperations = try JSONLineOperationLog(url: paths.operationLogURL)
                .loadRecent()
                .suffix(80)
                .reversed()
            setStatus("最近操作已刷新", tone: .neutral)
        } catch {
            recentOperations = []
            setStatus("读取最近操作失败：\(error.localizedDescription)", tone: .error)
        }
    }

    @objc private func handlePendingCommandRunNotification() {
        DispatchQueue.main.async { [weak self] in
            self?.checkForPendingCommandRun()
        }
    }

    func setActionEnabled(_ isEnabled: Bool, actionID: String) {
        updateAction(actionID) { action in
            action.isEnabled = isEnabled
        }
    }

    func setActionPlacement(_ placement: ActionPlacement, actionID: String) {
        guard let index = config.actions.firstIndex(where: { $0.id == actionID }) else {
            return
        }

        let current = config.actions[index]
        if placement == .rootMenu,
           current.placement != .rootMenu,
           rootMenuActionCount >= config.maxRootMenuActions {
            setStatus("一级菜单最多只能放 \(config.maxRootMenuActions) 个动作", tone: .warning)
            return
        }

        config.actions[index].placement = placement
        markUnsaved()
    }

    func toggleActionVisibility(_ visibility: ActionVisibility, actionID: String) {
        guard let index = config.actions.firstIndex(where: { $0.id == actionID }) else {
            return
        }

        if config.actions[index].visibility.contains(visibility) {
            guard config.actions[index].visibility.count > 1 else {
                setStatus("至少保留一个显示位置", tone: .warning)
                return
            }
            config.actions[index].visibility.remove(visibility)
        } else {
            config.actions[index].visibility.insert(visibility)
        }

        markUnsaved("菜单项显示范围已更新")
    }

    func moveAction(actionID: String, visibleActionIDs: [String], offset: Int) {
        guard
            let sourceVisibleIndex = visibleActionIDs.firstIndex(of: actionID)
        else {
            return
        }

        let targetVisibleIndex = sourceVisibleIndex + offset
        guard visibleActionIDs.indices.contains(targetVisibleIndex) else {
            return
        }

        let targetActionID = visibleActionIDs[targetVisibleIndex]
        guard
            let sourceIndex = config.actions.firstIndex(where: { $0.id == actionID }),
            let targetIndex = config.actions.firstIndex(where: { $0.id == targetActionID })
        else {
            return
        }

        let sourceOrder = config.actions[sourceIndex].order
        config.actions[sourceIndex].order = config.actions[targetIndex].order
        config.actions[targetIndex].order = sourceOrder
        markUnsaved("菜单项顺序已更新")
    }

    func upsertTemplate(_ template: FileTemplate, replacing originalID: String?) {
        if let originalID, let index = config.fileTemplates.firstIndex(where: { $0.id == originalID }) {
            config.fileTemplates[index] = template
            updateTemplateBackReferences(from: originalID, to: template.id)
        } else {
            config.fileTemplates.append(template)
        }
        syncTemplateAction(for: template, originalID: originalID)
        markUnsaved()
    }

    func deleteTemplate(_ template: FileTemplate) {
        config.fileTemplates.removeAll { $0.id == template.id }
        config.actions.removeAll { action in
            action.kind == .createFile && action.payload.templateID == template.id
        }
        markUnsaved("模板已删除，关联动作已移除")
    }

    func requestAddTemplate() {
        templateAddRequest += 1
    }

    func moveTemplate(_ template: FileTemplate, offset: Int) {
        guard
            let sourceIndex = config.fileTemplates.firstIndex(where: { $0.id == template.id })
        else {
            return
        }

        let targetIndex = sourceIndex + offset
        guard config.fileTemplates.indices.contains(targetIndex) else {
            return
        }

        config.fileTemplates.swapAt(sourceIndex, targetIndex)
        normalizeCreateFileActionOrder()
        markUnsaved("模板顺序已更新")
    }

    func upsertDeveloperEntrypoint(_ entrypoint: DeveloperEntrypoint, replacing originalID: String?) {
        if let duplicate = duplicateDeveloperEntrypoint(bundleIdentifier: entrypoint.bundleIdentifier, excluding: originalID) {
            setStatus("应用已存在：\(duplicate.title)", tone: .warning)
            return
        }

        if let originalID, let index = config.developerEntrypoints.firstIndex(where: { $0.id == originalID }) {
            config.developerEntrypoints[index] = entrypoint
            updateDeveloperBackReferences(from: originalID, to: entrypoint.id)
        } else {
            config.developerEntrypoints.append(entrypoint)
        }
        syncDeveloperAction(for: entrypoint, originalID: originalID)
        markUnsaved()
    }

    func deleteDeveloperEntrypoint(_ entrypoint: DeveloperEntrypoint) {
        config.developerEntrypoints.removeAll { $0.id == entrypoint.id }
        config.actions.removeAll { action in
            action.kind == .openInApp && action.payload.developerEntrypointID == entrypoint.id
        }
        markUnsaved("开发者入口已删除，关联动作已移除")
    }

    func requestAddDeveloperEntrypoint() {
        developerEntrypointAddRequest += 1
    }

    @MainActor
    func makeDeveloperEntrypointDraftFromSelectedApplication(
        replacing draft: DeveloperEntrypointDraft? = nil
    ) -> DeveloperEntrypointDraft? {
        guard let application = selectDeveloperApplication() else {
            return nil
        }

        if let duplicate = duplicateDeveloperEntrypoint(
            bundleIdentifier: application.bundleIdentifier,
            excluding: draft?.originalID
        ) {
            setStatus("应用已存在：\(duplicate.title)", tone: .warning)
            return nil
        }

        if var draft {
            draft.apply(application: application)
            return draft
        }

        let entrypointID = uniqueDeveloperEntrypointID(base: "developer-\(slug(for: application.displayName))")
        return DeveloperEntrypointDraft(application: application, entrypointID: entrypointID)
    }

    func moveDeveloperEntrypoint(_ entrypoint: DeveloperEntrypoint, visibleEntrypointIDs: [String], offset: Int) {
        guard
            let sourceVisibleIndex = visibleEntrypointIDs.firstIndex(of: entrypoint.id)
        else {
            return
        }

        let targetVisibleIndex = sourceVisibleIndex + offset
        guard visibleEntrypointIDs.indices.contains(targetVisibleIndex) else {
            return
        }

        let targetID = visibleEntrypointIDs[targetVisibleIndex]
        guard
            let sourceIndex = config.developerEntrypoints.firstIndex(where: { $0.id == entrypoint.id }),
            let targetIndex = config.developerEntrypoints.firstIndex(where: { $0.id == targetID })
        else {
            return
        }

        config.developerEntrypoints.swapAt(sourceIndex, targetIndex)
        normalizeDeveloperActionOrder()
        markUnsaved("开发者入口顺序已更新")
    }

    func upsertCommandTemplate(_ draft: CommandTemplateDraft) {
        do {
            let template = try draft.makeTemplate(secretStore: commandSecretStore)
            if let originalID = draft.originalID, let index = config.commandTemplates.firstIndex(where: { $0.id == originalID }) {
                deleteRemovedCommandSecrets(oldTemplate: config.commandTemplates[index], newTemplate: template)
                config.commandTemplates[index] = template
                updateCommandBackReferences(from: originalID, to: template.id)
            } else {
                config.commandTemplates.append(template)
            }
            syncCommandAction(for: template, originalID: draft.originalID)
            markUnsaved("命令模板已更新")
        } catch {
            setStatus("保存命令模板失败：\(error.localizedDescription)", tone: .error)
        }
    }

    func deleteCommandTemplate(_ template: CommandTemplate) {
        for variable in template.environment where variable.isSensitive {
            if let reference = variable.secretReference {
                try? commandSecretStore.delete(reference: reference)
            }
        }
        config.commandTemplates.removeAll { $0.id == template.id }
        config.actions.removeAll { action in
            action.kind == .runCommand && action.payload.commandTemplateID == template.id
        }
        markUnsaved("命令模板已删除，关联动作已移除")
    }

    func requestAddCommandTemplate() {
        commandTemplateAddRequest += 1
    }

    func moveCommandTemplate(_ template: CommandTemplate, offset: Int) {
        guard
            let sourceIndex = config.commandTemplates.firstIndex(where: { $0.id == template.id })
        else {
            return
        }

        let targetIndex = sourceIndex + offset
        guard config.commandTemplates.indices.contains(targetIndex) else {
            return
        }

        config.commandTemplates.swapAt(sourceIndex, targetIndex)
        normalizeCommandActionOrder()
        markUnsaved("命令模板顺序已更新")
    }

    func runCommandTemplateFromSettings(_ template: CommandTemplate) {
        guard let action = config.actions.first(where: { $0.kind == .runCommand && $0.payload.commandTemplateID == template.id }) else {
            setStatus("找不到命令模板对应菜单动作", tone: .warning)
            return
        }
        let targetBookmark = bookmarks.bookmarks.first
        let targetDirectory = targetBookmark.map { URL(fileURLWithPath: $0.path) } ?? URL(fileURLWithPath: NSHomeDirectory())
        let request = PendingCommandRunRequest(
            actionID: action.id,
            context: FinderContext(invocation: .container, targetDirectory: targetDirectory)
        )
        CommandRunWindowCoordinator.shared.open(
            request: request,
            paths: paths,
            onFinish: { [weak self] in self?.reloadRecentOperations() }
        )
    }

    @MainActor
    func addDirectoryBookmarkFromPanel() {
        guard let url = selectDirectoryURL() else {
            return
        }

        upsertDirectoryBookmark(url: url, replacing: nil)
    }

    @MainActor
    func replaceDirectoryBookmarkFromPanel(bookmarkID: String) {
        guard let bookmark = bookmarks.bookmark(id: bookmarkID) else {
            setStatus("找不到要编辑的目录", tone: .warning)
            return
        }

        let initialURL = URL(fileURLWithPath: bookmark.path)
        guard let url = selectDirectoryURL(initialURL: initialURL) else {
            return
        }

        upsertDirectoryBookmark(url: url, replacing: bookmarkID)
    }

    func deleteDirectoryBookmark(bookmarkID: String) {
        guard let bookmark = bookmarks.bookmark(id: bookmarkID) else {
            setStatus("找不到要删除的目录", tone: .warning)
            return
        }

        bookmarks.bookmarks.removeAll { $0.id == bookmarkID }
        config.commonDirectoryIDs.removeAll { $0 == bookmarkID }
        config.monitoredDirectoryIDs.removeAll { $0 == bookmarkID }
        config.actions.removeAll { action in
            directoryActionKinds.contains(action.kind) && action.payload.directoryID == bookmarkID
        }

        saveDirectoryChanges("已删除目录：\(bookmark.displayName)")
    }

    func moveDirectoryBookmark(bookmarkID: String, visibleBookmarkIDs: [String], offset: Int) {
        guard
            let sourceVisibleIndex = visibleBookmarkIDs.firstIndex(of: bookmarkID)
        else {
            return
        }

        let targetVisibleIndex = sourceVisibleIndex + offset
        guard visibleBookmarkIDs.indices.contains(targetVisibleIndex) else {
            return
        }

        let targetID = visibleBookmarkIDs[targetVisibleIndex]
        guard
            let sourceIndex = bookmarks.bookmarks.firstIndex(where: { $0.id == bookmarkID }),
            let targetIndex = bookmarks.bookmarks.firstIndex(where: { $0.id == targetID })
        else {
            return
        }

        bookmarks.bookmarks.swapAt(sourceIndex, targetIndex)
        reorderDirectoryIDReferences()
        normalizeDirectoryActionOrder()
        saveDirectoryChanges("目录顺序已更新")
    }

    func isDirectoryBookmarkEnabled(_ bookmarkID: String) -> Bool {
        let isReferenced = config.commonDirectoryIDs.contains(bookmarkID) && config.monitoredDirectoryIDs.contains(bookmarkID)
        let openAction = config.actions.first { action in
            action.kind == .openDirectory && action.payload.directoryID == bookmarkID
        }
        return isReferenced && (openAction?.isEnabled ?? true)
    }

    func setDirectoryBookmarkEnabled(_ isEnabled: Bool, bookmarkID: String) {
        guard let bookmark = bookmarks.bookmark(id: bookmarkID) else {
            setStatus("找不到要更新的目录", tone: .warning)
            return
        }

        if isEnabled {
            appendUnique(bookmarkID, to: &config.commonDirectoryIDs)
            appendUnique(bookmarkID, to: &config.monitoredDirectoryIDs)
            syncDirectoryActions(for: bookmark)
        } else {
            config.commonDirectoryIDs.removeAll { $0 == bookmarkID }
            config.monitoredDirectoryIDs.removeAll { $0 == bookmarkID }
        }

        for index in config.actions.indices where directoryActionKinds.contains(config.actions[index].kind) && config.actions[index].payload.directoryID == bookmarkID {
            config.actions[index].isEnabled = isEnabled
        }

        saveDirectoryChanges(isEnabled ? "已启用目录：\(bookmark.displayName)" : "已停用目录：\(bookmark.displayName)")
    }

    private func apply(result: ConfigurationBootstrapResult) {
        paths = result.paths
        config = result.config
        bookmarks = result.bookmarks
        storagePath = result.paths.baseURL.path
        hasUnsavedChanges = false
        recentOperations = (try? JSONLineOperationLog(url: result.paths.operationLogURL).loadRecent().suffix(80).reversed()) ?? []
    }

    private func scheduleFinderExtensionRegistration() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else {
                return
            }

            guard let appexURL = bundledFinderExtensionURL() else {
                markFinderExtensionNeedsAttention(
                    "找不到随 App 打包的 Finder Extension，请确认已从 DMG 拖入 Applications 后再打开"
                )
                return
            }

            if hasCompletedFinderExtensionSetup(for: appexURL) {
                markFinderExtensionReady()
                return
            }

            repairFinderContextMenu(restartFinder: true, userInitiated: false)
        }
    }

    private func bundledFinderExtensionURL() -> URL? {
        let pluginName = "RightClickProFinderExtension.appex"
        let candidates = [
            Bundle.main.builtInPlugInsURL?.appendingPathComponent(pluginName),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("PlugIns")
                .appendingPathComponent(pluginName)
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func handleFinderMaintenanceResponse(
        _ response: Result<SystemMaintenanceResult, Error>,
        didRequestRestart: Bool,
        userInitiated: Bool
    ) {
        switch response {
        case .success(let result):
            if result.isSuccess {
                if let appexURL = bundledFinderExtensionURL() {
                    markFinderExtensionSetupCompleted(for: appexURL)
                }
                markFinderExtensionReady()
                if didRequestRestart {
                    setStatusIfUserInitiated(
                        userInitiated,
                        "右键菜单已修复：Finder Extension 已注册并已重启 Finder",
                        tone: .success
                    )
                } else if userInitiated {
                    setStatus("Finder Extension 已注册，请重新打开右键菜单检查入口", tone: .success)
                }
                return
            }

            let detail = result.errors.first ?? "未知错误"
            markFinderExtensionNeedsAttention(detail)
            if result.didRegisterFinderExtension || result.didEnableFinderExtension || result.didRestartFinder {
                setStatusIfUserInitiated(
                    userInitiated,
                    "右键菜单部分修复完成，但仍需手动确认：\(detail)",
                    tone: .warning
                )
            } else if userInitiated {
                setStatus("修复右键菜单失败：\(detail)", tone: .error)
            }
        case .failure(let error):
            let message = "ActionRunner XPC 服务不可用：\(error.localizedDescription)"
            markFinderExtensionNeedsAttention(message)
            if userInitiated {
                setStatus("修复右键菜单失败：\(message)", tone: .error)
            }
        }
    }

    private func setStatusIfUserInitiated(_ userInitiated: Bool, _ message: String, tone: StatusTone) {
        guard userInitiated else {
            return
        }
        setStatus(message, tone: tone)
    }

    private func markFinderExtensionNeedsAttention(_ message: String) {
        finderExtensionNeedsAttention = true
        finderExtensionSetupMessage = message
    }

    private func markFinderExtensionReady() {
        finderExtensionNeedsAttention = false
        finderExtensionSetupMessage = ""
    }

    private func hasCompletedFinderExtensionSetup(for appexURL: URL) -> Bool {
        UserDefaults.standard.string(forKey: FinderExtensionSetupDefaults.completedSignatureKey) == finderExtensionSetupSignature(for: appexURL)
    }

    private func markFinderExtensionSetupCompleted(for appexURL: URL) {
        UserDefaults.standard.set(finderExtensionSetupSignature(for: appexURL), forKey: FinderExtensionSetupDefaults.completedSignatureKey)
    }

    private func finderExtensionSetupSignature(for appexURL: URL) -> String {
        FinderExtensionInstallSignature.make(
            appexURL: appexURL,
            hostBundleURL: Bundle.main.bundleURL
        )
    }

    private func updateAction(_ actionID: String, mutate: (inout RightClickProAction) -> Void) {
        guard let index = config.actions.firstIndex(where: { $0.id == actionID }) else {
            return
        }
        mutate(&config.actions[index])
        markUnsaved()
    }

    private func updateTemplateBackReferences(from oldID: String, to newID: String) {
        guard oldID != newID else {
            return
        }
        for index in config.actions.indices where config.actions[index].payload.templateID == oldID {
            config.actions[index].payload.templateID = newID
        }
    }

    private func updateDeveloperBackReferences(from oldID: String, to newID: String) {
        guard oldID != newID else {
            return
        }
        for index in config.actions.indices where config.actions[index].payload.developerEntrypointID == oldID {
            config.actions[index].payload.developerEntrypointID = newID
        }
    }

    private func updateCommandBackReferences(from oldID: String, to newID: String) {
        guard oldID != newID else {
            return
        }
        for index in config.actions.indices where config.actions[index].payload.commandTemplateID == oldID {
            config.actions[index].payload.commandTemplateID = newID
        }
    }

    private func syncTemplateAction(for template: FileTemplate, originalID: String?) {
        if let index = config.actions.firstIndex(where: { action in
            action.kind == .createFile && (action.payload.templateID == template.id || action.payload.templateID == originalID)
        }) {
            config.actions[index].title = "新建\(template.title)"
            config.actions[index].payload.templateID = template.id
            return
        }

        config.actions.append(
            RightClickProAction(
                id: uniqueActionID(base: "create-\(template.id)"),
                title: "新建\(template.title)",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: nextActionOrder,
                payload: ActionPayload(templateID: template.id)
            )
        )
    }

    private func normalizeCreateFileActionOrder() {
        let baseOrder = config.actions
            .filter { $0.kind == .createFile }
            .map(\.order)
            .min() ?? nextActionOrder

        for (index, template) in config.fileTemplates.enumerated() {
            guard let actionIndex = config.actions.firstIndex(where: {
                $0.kind == .createFile && $0.payload.templateID == template.id
            }) else {
                continue
            }
            config.actions[actionIndex].order = baseOrder + index * 10
        }
    }

    private func normalizeDeveloperActionOrder() {
        let baseOrder = config.actions
            .filter { $0.kind == .openInApp }
            .map(\.order)
            .min() ?? nextActionOrder

        for (index, entrypoint) in config.developerEntrypoints.enumerated() {
            guard let actionIndex = config.actions.firstIndex(where: {
                $0.kind == .openInApp && $0.payload.developerEntrypointID == entrypoint.id
            }) else {
                continue
            }
            config.actions[actionIndex].order = baseOrder + index * 10
        }
    }

    private func normalizeCommandActionOrder() {
        let baseOrder = config.actions
            .filter { $0.kind == .runCommand }
            .map(\.order)
            .min() ?? nextActionOrder

        for (index, template) in config.commandTemplates.enumerated() {
            guard let actionIndex = config.actions.firstIndex(where: {
                $0.kind == .runCommand && $0.payload.commandTemplateID == template.id
            }) else {
                continue
            }
            config.actions[actionIndex].order = baseOrder + index * 10
        }
    }

    private func syncDeveloperAction(for entrypoint: DeveloperEntrypoint, originalID: String?) {
        if let index = config.actions.firstIndex(where: { action in
            action.kind == .openInApp && (
                action.payload.developerEntrypointID == entrypoint.id ||
                    action.payload.developerEntrypointID == originalID
            )
        }) {
            config.actions[index].title = entrypoint.title
            config.actions[index].payload.developerEntrypointID = entrypoint.id
            return
        }

        config.actions.append(
            RightClickProAction(
                id: uniqueActionID(base: "open-\(entrypoint.id)"),
                title: entrypoint.title,
                kind: .openInApp,
                visibility: [.selection, .container, .toolbar],
                placement: .submenu,
                group: .developerEntrypoints,
                order: nextActionOrder,
                payload: ActionPayload(developerEntrypointID: entrypoint.id)
            )
        )
    }

    private func syncCommandAction(for template: CommandTemplate, originalID: String?) {
        if let index = config.actions.firstIndex(where: { action in
            action.kind == .runCommand && (
                action.payload.commandTemplateID == template.id ||
                    action.payload.commandTemplateID == originalID
            )
        }) {
            config.actions[index].title = template.title
            config.actions[index].payload.commandTemplateID = template.id
            config.actions[index].group = .commandTemplates
            return
        }

        config.actions.append(
            RightClickProAction(
                id: uniqueActionID(base: "run-\(template.id)"),
                title: template.title,
                kind: .runCommand,
                visibility: [.selection, .container],
                placement: .submenu,
                group: .commandTemplates,
                order: nextActionOrder,
                payload: ActionPayload(commandTemplateID: template.id)
            )
        )
    }

    private func deleteRemovedCommandSecrets(oldTemplate: CommandTemplate, newTemplate: CommandTemplate) {
        let newReferences = Set(newTemplate.environment.compactMap(\.secretReference))
        for variable in oldTemplate.environment where variable.isSensitive {
            guard
                let reference = variable.secretReference,
                !newReferences.contains(reference)
            else {
                continue
            }
            try? commandSecretStore.delete(reference: reference)
        }
    }

    private func checkForPendingCommandRun() {
        let store = JSONFileStore<PendingCommandRunRequest>(url: paths.pendingCommandRunURL)
        guard let request = try? store.loadRequired() else {
            return
        }
        try? FileManager.default.removeItem(at: paths.pendingCommandRunURL)
        NSApplication.shared.activate(ignoringOtherApps: true)
        CommandRunWindowCoordinator.shared.open(
            request: request,
            paths: paths,
            onFinish: { [weak self] in self?.reloadRecentOperations() }
        )
    }

    private var directoryActionKinds: Set<ActionKind> {
        [.openDirectory, .moveToDirectory, .copyToDirectory]
    }

    private func upsertDirectoryBookmark(url: URL, replacing bookmarkID: String?) {
        let path = normalizedDirectoryPath(for: url)
        if let duplicate = bookmarks.bookmarks.first(where: { $0.id != bookmarkID && normalizedDirectoryPath($0.path) == path }) {
            setStatus("目录已存在：\(duplicate.displayName)", tone: .warning)
            return
        }

        let displayName = directoryDisplayName(for: url)
        let bookmarkDataBase64 = securityBookmarkDataBase64(for: url)

        if let bookmarkID {
            guard let index = bookmarks.bookmarks.firstIndex(where: { $0.id == bookmarkID }) else {
                setStatus("找不到要编辑的目录", tone: .warning)
                return
            }

            let updated = DirectoryBookmark(
                id: bookmarkID,
                displayName: displayName,
                path: path,
                bookmarkDataBase64: bookmarkDataBase64,
                addedAt: bookmarks.bookmarks[index].addedAt
            )
            bookmarks.bookmarks[index] = updated
            appendUnique(bookmarkID, to: &config.commonDirectoryIDs)
            appendUnique(bookmarkID, to: &config.monitoredDirectoryIDs)
            syncDirectoryActions(for: updated)
            saveDirectoryChanges("已更新目录：\(displayName)")
            return
        }

        let bookmark = DirectoryBookmark(
            id: uniqueBookmarkID(base: "directory-\(slug(for: displayName))"),
            displayName: displayName,
            path: path,
            bookmarkDataBase64: bookmarkDataBase64
        )
        bookmarks.bookmarks.append(bookmark)
        appendUnique(bookmark.id, to: &config.commonDirectoryIDs)
        appendUnique(bookmark.id, to: &config.monitoredDirectoryIDs)
        syncDirectoryActions(for: bookmark)
        saveDirectoryChanges("已添加目录：\(displayName)")
    }

    private func syncDirectoryActions(for bookmark: DirectoryBookmark) {
        let specs: [(kind: ActionKind, idPrefix: String, titlePrefix: String, visibility: Set<ActionVisibility>, group: MenuGroup)] = [
            (.openDirectory, "open-directory", "前往", [.container, .toolbar], .commonDirectories),
            (.moveToDirectory, "move-to", "移动到", [.selection], .moveToCommonDirectory),
            (.copyToDirectory, "copy-to", "复制到", [.selection], .copyToCommonDirectory)
        ]
        let isEnabled = config.commonDirectoryIDs.contains(bookmark.id) && config.monitoredDirectoryIDs.contains(bookmark.id)
        var order = nextActionOrder

        for spec in specs {
            if let index = config.actions.firstIndex(where: { action in
                action.kind == spec.kind && action.payload.directoryID == bookmark.id
            }) {
                config.actions[index].title = "\(spec.titlePrefix)\(bookmark.displayName)"
                config.actions[index].payload.directoryID = bookmark.id
                continue
            }

            config.actions.append(
                RightClickProAction(
                    id: uniqueActionID(base: "\(spec.idPrefix)-\(bookmark.id)"),
                    title: "\(spec.titlePrefix)\(bookmark.displayName)",
                    kind: spec.kind,
                    visibility: spec.visibility,
                    placement: .submenu,
                    group: spec.group,
                    isEnabled: isEnabled,
                    order: order,
                    payload: ActionPayload(directoryID: bookmark.id)
                )
            )
            order += 10
        }
    }

    private func reorderDirectoryIDReferences() {
        let orderedIDs = bookmarks.bookmarks.map(\.id)
        config.commonDirectoryIDs = orderedIDs.filter { config.commonDirectoryIDs.contains($0) }
        config.monitoredDirectoryIDs = orderedIDs.filter { config.monitoredDirectoryIDs.contains($0) }
    }

    private func normalizeDirectoryActionOrder() {
        let baseOrder = config.actions
            .filter { directoryActionKinds.contains($0.kind) }
            .map(\.order)
            .min() ?? nextActionOrder
        let specs: [(kind: ActionKind, offset: Int)] = [
            (.openDirectory, 0),
            (.moveToDirectory, 10),
            (.copyToDirectory, 20)
        ]

        for (bookmarkIndex, bookmark) in bookmarks.bookmarks.enumerated() {
            for spec in specs {
                guard let actionIndex = config.actions.firstIndex(where: {
                    $0.kind == spec.kind && $0.payload.directoryID == bookmark.id
                }) else {
                    continue
                }
                config.actions[actionIndex].order = baseOrder + bookmarkIndex * 30 + spec.offset
            }
        }
    }

    @MainActor
    private func selectDirectoryURL(initialURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择常用目录"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = initialURL

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    private func securityBookmarkDataBase64(for url: URL) -> String? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private func saveDirectoryChanges(_ message: String) {
        do {
            try validateConfig()
            try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(bookmarks)
            try JSONFileStore<RightClickProConfig>(url: paths.configURL).save(config)
            hasUnsavedChanges = false
            setStatus(message, tone: .success)
        } catch {
            hasUnsavedChanges = true
            setStatus("保存目录配置失败：\(error.localizedDescription)", tone: .error)
        }
    }

    private func appendUnique(_ id: String, to ids: inout [String]) {
        guard !ids.contains(id) else {
            return
        }
        ids.append(id)
    }

    private func uniqueBookmarkID(base: String) -> String {
        let fallback = base == "directory-" ? "directory" : base
        if !bookmarks.bookmarks.contains(where: { $0.id == fallback }) {
            return fallback
        }

        var index = 2
        while bookmarks.bookmarks.contains(where: { $0.id == "\(fallback)-\(index)" }) {
            index += 1
        }
        return "\(fallback)-\(index)"
    }

    private func uniqueDeveloperEntrypointID(base: String) -> String {
        let fallback = base == "developer-" ? "developer" : base
        if !config.developerEntrypoints.contains(where: { $0.id == fallback }) {
            return fallback
        }

        var index = 2
        while config.developerEntrypoints.contains(where: { $0.id == "\(fallback)-\(index)" }) {
            index += 1
        }
        return "\(fallback)-\(index)"
    }

    private func normalizedDirectoryPath(for url: URL) -> String {
        normalizedDirectoryPath(url.path)
    }

    private func normalizedDirectoryPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private func directoryDisplayName(for url: URL) -> String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? url.path : name
    }

    @MainActor
    private func selectDeveloperApplication() -> DeveloperApplicationSelection? {
        let panel = NSOpenPanel()
        panel.title = "选择本地应用"
        panel.message = "请选择要加入 Finder 右键菜单的 macOS 应用。"
        panel.prompt = "选择应用"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return developerApplicationSelection(for: url.standardizedFileURL)
    }

    private func developerApplicationSelection(for url: URL) -> DeveloperApplicationSelection? {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) else {
            setStatus("请选择有效的 macOS 应用", tone: .warning)
            return nil
        }

        guard
            let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleIdentifier.isEmpty
        else {
            setStatus("无法读取应用的 Bundle Identifier", tone: .warning)
            return nil
        }

        let displayName = [
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            url.deletingPathExtension().lastPathComponent
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? bundleIdentifier

        return DeveloperApplicationSelection(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            url: url
        )
    }

    private func duplicateDeveloperEntrypoint(
        bundleIdentifier: String,
        excluding originalID: String?
    ) -> DeveloperEntrypoint? {
        let normalized = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return nil
        }

        return config.developerEntrypoints.first { entrypoint in
            entrypoint.id != originalID &&
                entrypoint.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    private func slug(for value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let characters = folded.lowercased().unicodeScalars.map { scalar -> String in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let collapsed = characters.joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "directory" : collapsed
    }

    private var nextActionOrder: Int {
        (config.actions.map(\.order).max() ?? 0) + 10
    }

    private func uniqueActionID(base: String) -> String {
        if !config.actions.contains(where: { $0.id == base }) {
            return base
        }

        var index = 2
        while config.actions.contains(where: { $0.id == "\(base)-\(index)" }) {
            index += 1
        }
        return "\(base)-\(index)"
    }

    private func validateConfig() throws {
        let rootCount = config.actions.filter { $0.isEnabled && $0.placement == .rootMenu }.count
        if rootCount > config.maxRootMenuActions {
            throw SettingsValidationError.tooManyRootActions(config.maxRootMenuActions)
        }

        var templateIDs = Set<String>()
        for template in config.fileTemplates {
            guard !template.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyTemplateID
            }
            guard templateIDs.insert(template.id).inserted else {
                throw SettingsValidationError.duplicateID(template.id)
            }
            guard !template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyTemplateTitle
            }
            guard isValidFileName(template.defaultFileName) else {
                throw SettingsValidationError.invalidFileName(template.defaultFileName)
            }
        }

        var developerIDs = Set<String>()
        for entrypoint in config.developerEntrypoints {
            guard !entrypoint.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyDeveloperID
            }
            guard developerIDs.insert(entrypoint.id).inserted else {
                throw SettingsValidationError.duplicateID(entrypoint.id)
            }
            guard !entrypoint.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyDeveloperTitle
            }
            guard !entrypoint.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyBundleIdentifier
            }
        }

        var commandIDs = Set<String>()
        for template in config.commandTemplates {
            guard !template.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyCommandTemplateID
            }
            guard commandIDs.insert(template.id).inserted else {
                throw SettingsValidationError.duplicateID(template.id)
            }
            guard !template.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyCommandTemplateTitle
            }
            guard !template.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SettingsValidationError.emptyCommand
            }
            guard (RightClickProConstants.minimumCommandTimeoutSeconds...RightClickProConstants.maximumCommandTimeoutSeconds).contains(template.timeoutSeconds) else {
                throw SettingsValidationError.invalidCommandTimeout(template.timeoutSeconds)
            }

            var environmentNames = Set<String>()
            for variable in template.environment {
                guard CommandTemplateVariableResolver.validateEnvironmentName(variable.name) else {
                    throw SettingsValidationError.invalidEnvironmentName(variable.name)
                }
                guard environmentNames.insert(variable.name).inserted else {
                    throw SettingsValidationError.duplicateEnvironmentName(variable.name)
                }
                if variable.isSensitive, variable.secretReference == nil {
                    throw SettingsValidationError.missingSecretReference(variable.name)
                }
            }
        }
    }

    private func isValidFileName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/")
    }

    private func markUnsaved(_ message: String = "有未保存的配置更改") {
        hasUnsavedChanges = true
        setStatus(message, tone: .warning)
    }

    private func setStatus(_ message: String, tone: StatusTone) {
        statusMessage = message
        statusTone = tone
    }
}

enum SettingsValidationError: Error, LocalizedError {
    case tooManyRootActions(Int)
    case emptyTemplateID
    case emptyTemplateTitle
    case invalidFileName(String)
    case emptyDeveloperID
    case emptyDeveloperTitle
    case emptyBundleIdentifier
    case emptyCommandTemplateID
    case emptyCommandTemplateTitle
    case emptyCommand
    case invalidCommandTimeout(Int)
    case invalidEnvironmentName(String)
    case duplicateEnvironmentName(String)
    case missingSecretReference(String)
    case duplicateID(String)

    var errorDescription: String? {
        switch self {
        case .tooManyRootActions(let max):
            return "一级菜单动作不能超过 \(max) 个"
        case .emptyTemplateID:
            return "模板 ID 不能为空"
        case .emptyTemplateTitle:
            return "模板名称不能为空"
        case .invalidFileName(let name):
            return "默认文件名无效：\(name)"
        case .emptyDeveloperID:
            return "开发者入口 ID 不能为空"
        case .emptyDeveloperTitle:
            return "开发者入口名称不能为空"
        case .emptyBundleIdentifier:
            return "Bundle Identifier 不能为空"
        case .emptyCommandTemplateID:
            return "命令模板 ID 不能为空"
        case .emptyCommandTemplateTitle:
            return "命令模板名称不能为空"
        case .emptyCommand:
            return "命令内容不能为空"
        case .invalidCommandTimeout(let timeout):
            return "命令超时必须在 5-600 秒之间：\(timeout)"
        case .invalidEnvironmentName(let name):
            return "环境变量名称无效：\(name)"
        case .duplicateEnvironmentName(let name):
            return "环境变量名称重复：\(name)"
        case .missingSecretReference(let name):
            return "敏感环境变量缺少 Keychain 引用：\(name)"
        case .duplicateID(let id):
            return "ID 重复：\(id)"
        }
    }
}

final class CommandRunViewModel: ObservableObject {
    enum RunStatus: Equatable {
        case preparing
        case running
        case succeeded(Int32)
        case failed(Int32)
        case timedOut
        case stopped
        case error(String)

        var title: String {
            switch self {
            case .preparing:
                return "准备中"
            case .running:
                return "运行中"
            case .succeeded:
                return "已完成"
            case .failed:
                return "失败"
            case .timedOut:
                return "已超时"
            case .stopped:
                return "已停止"
            case .error:
                return "错误"
            }
        }

        var color: Color {
            switch self {
            case .preparing, .running:
                return SettingsTheme.accent
            case .succeeded:
                return .green
            case .failed, .timedOut, .error:
                return .red
            case .stopped:
                return .orange
            }
        }
    }

    @Published var title = "命令运行"
    @Published var command = ""
    @Published var workingDirectory = ""
    @Published var output = ""
    @Published var status: RunStatus = .preparing
    @Published var exitCode: Int32?
    @Published var durationText = "—"

    private let request: PendingCommandRunRequest
    private let paths: RightClickProStoragePaths
    private let onFinish: () -> Void
    private let secretStore = KeychainCommandSecretStore()
    private var process: Process?
    private var startedAt: Date?
    private var timeoutWorkItem: DispatchWorkItem?
    private var didRequestStop = false
    private var didTimeout = false
    private var outputSummary = ""
    private var bookmarkAccess: AuthorizedBookmarkAccess?
    private var commandScopedAccessURLs: [URL] = []

    init(
        request: PendingCommandRunRequest,
        paths: RightClickProStoragePaths,
        onFinish: @escaping () -> Void
    ) {
        self.request = request
        self.paths = paths
        self.onFinish = onFinish
    }

    func start() {
        guard process == nil else {
            return
        }

        do {
            let configProvider = FileBackedRightClickProConfigProvider(paths: paths)
            let config = try configProvider.loadConfig()
            let bookmarks = try configProvider.loadBookmarkCatalog()
            guard
                let action = config.actions.first(where: { $0.id == request.actionID }),
                let templateID = action.payload.commandTemplateID,
                let template = config.commandTemplates.first(where: { $0.id == templateID })
            else {
                throw CommandTemplateError.missingCommandTemplate(request.actionID)
            }

            let bookmarkAccess = try AuthorizedBookmarkAccess(
                catalog: bookmarks,
                ids: config.monitoredDirectoryIDs + config.commonDirectoryIDs
            )
            self.bookmarkAccess = bookmarkAccess
            let validator = AuthorizedPathValidator(authorizedDirectories: bookmarkAccess.urls)
            let directory = CommandTemplateVariableResolver.workingDirectory(for: template, context: request.context)
            guard validator.isAuthorized(directory) else {
                throw CommandTemplateError.unauthorizedWorkingDirectory(directory.path)
            }
            try ensureReadableWorkingDirectory(directory, bookmarks: bookmarks)

            let resolvedCommand = try CommandTemplateVariableResolver.interpolatedCommand(template: template, context: request.context)
            let environment = try commandEnvironment(for: template)

            title = template.title
            command = resolvedCommand
            workingDirectory = directory.path
            appendOutput("$ cd \(directory.path)\n$ \(resolvedCommand)\n\n")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", resolvedCommand]
            process.currentDirectoryURL = directory
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.readAvailableOutput(from: handle)
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.readAvailableOutput(from: handle)
            }

            process.terminationHandler = { [weak self] process in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    self?.finish(exitCode: process.terminationStatus)
                }
            }

            self.process = process
            startedAt = Date()
            status = .running
            try process.run()
            scheduleTimeout(seconds: template.timeoutSeconds)
        } catch {
            status = .error(error.localizedDescription)
            appendOutput("运行失败：\(error.localizedDescription)\n")
            logFailure(message: error.localizedDescription)
            releaseCommandScopedBookmarks()
            bookmarkAccess = nil
            onFinish()
        }
    }

    func stop() {
        didRequestStop = true
        appendOutput("\n用户请求停止命令...\n")
        terminateThenKillIfNeeded()
    }

    private func commandEnvironment(for template: CommandTemplate) throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(path):\(defaultPath)"
        } else {
            environment["PATH"] = defaultPath
        }

        for variable in template.environment {
            guard CommandTemplateVariableResolver.validateEnvironmentName(variable.name) else {
                throw CommandTemplateError.invalidEnvironmentName(variable.name)
            }

            if variable.isSensitive {
                guard
                    let reference = variable.secretReference,
                    let value = try secretStore.load(reference: reference)
                else {
                    throw CommandTemplateError.missingSecret(variable.name)
                }
                environment[variable.name] = value
            } else {
                environment[variable.name] = variable.value ?? ""
            }
        }
        return environment
    }

    private func ensureReadableWorkingDirectory(_ directory: URL, bookmarks: DirectoryBookmarkCatalog) throws {
        if isReadableDirectory(directory) {
            return
        }

        guard let authorizedURL = requestWorkingDirectoryAuthorization(for: directory) else {
            throw CommandTemplateError.inaccessibleWorkingDirectory(directory.path)
        }

        let didAccess = authorizedURL.startAccessingSecurityScopedResource()
        if didAccess {
            commandScopedAccessURLs.append(authorizedURL)
        }

        if let data = try? authorizedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            persistWorkingDirectoryAuthorization(
                directory: directory,
                authorizedURL: authorizedURL,
                bookmarkDataBase64: data.base64EncodedString(),
                bookmarks: bookmarks
            )
        }

        guard isReadableDirectory(directory) else {
            throw CommandTemplateError.inaccessibleWorkingDirectory(directory.path)
        }
    }

    private func isReadableDirectory(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            return true
        } catch {
            return false
        }
    }

    private func requestWorkingDirectoryAuthorization(for directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "授权命令工作目录"
        panel.message = "\(AppMetadata.displayName) 需要访问该目录后才能在里面运行命令：\(directory.path)"
        panel.prompt = "授权并运行"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else {
            return nil
        }

        let selectedPath = normalizedPath(url)
        let directoryPath = normalizedPath(directory)
        guard directoryPath == selectedPath || directoryPath.hasPrefix(selectedPath + "/") else {
            return nil
        }
        return url
    }

    private func persistWorkingDirectoryAuthorization(
        directory: URL,
        authorizedURL: URL,
        bookmarkDataBase64: String,
        bookmarks: DirectoryBookmarkCatalog
    ) {
        let directoryPath = normalizedPath(directory)
        let authorizedPath = normalizedPath(authorizedURL)
        guard directoryPath == authorizedPath || directoryPath.hasPrefix(authorizedPath + "/") else {
            return
        }

        do {
            var catalog = (try? JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).loadRequired()) ?? bookmarks
            guard let index = catalog.bookmarks.firstIndex(where: {
                normalizedPath(URL(fileURLWithPath: $0.path)) == authorizedPath
            }) else {
                return
            }
            catalog.bookmarks[index].bookmarkDataBase64 = bookmarkDataBase64
            try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(catalog)
        } catch {
            appendOutput("目录授权已生效，但保存授权失败：\(error.localizedDescription)\n")
        }
    }

    private func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func releaseCommandScopedBookmarks() {
        for url in commandScopedAccessURLs {
            url.stopAccessingSecurityScopedResource()
        }
        commandScopedAccessURLs.removeAll()
    }

    private func readAvailableOutput(from handle: FileHandle) {
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.appendOutput(text)
        }
    }

    private func appendOutput(_ text: String) {
        output += text
        outputSummary += text
        if outputSummary.count > 4000 {
            outputSummary = String(outputSummary.suffix(4000))
        }
    }

    private func scheduleTimeout(seconds: Int) {
        let workItem = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.process?.isRunning == true else {
                    return
                }
                self.didTimeout = true
                self.appendOutput("\n命令超过 \(seconds) 秒，正在停止...\n")
                self.terminateThenKillIfNeeded()
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds), execute: workItem)
    }

    private func terminateThenKillIfNeeded() {
        guard let process, process.isRunning else {
            return
        }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak process] in
            guard let process, process.isRunning else {
                return
            }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func finish(exitCode: Int32) {
        timeoutWorkItem?.cancel()
        self.exitCode = exitCode
        durationText = formattedDuration()

        if didTimeout {
            status = .timedOut
        } else if didRequestStop {
            status = .stopped
        } else if exitCode == 0 {
            status = .succeeded(exitCode)
        } else {
            status = .failed(exitCode)
        }

        appendOutput("\n退出码：\(exitCode) · 耗时：\(durationText)\n")
        logCompletion(exitCode: exitCode)
        releaseCommandScopedBookmarks()
        bookmarkAccess = nil
        onFinish()
    }

    private func formattedDuration() -> String {
        guard let startedAt else {
            return "—"
        }
        let interval = Date().timeIntervalSince(startedAt)
        return String(format: "%.1fs", interval)
    }

    private func durationMilliseconds() -> Int? {
        guard let startedAt else {
            return nil
        }
        return Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    private func logCompletion(exitCode: Int32) {
        let recordStatus: OperationRecordStatus
        switch status {
        case .succeeded:
            recordStatus = .success
        case .stopped:
            recordStatus = .cancelled
        default:
            recordStatus = .failure
        }
        try? JSONLineOperationLog(url: paths.operationLogURL).append(
            OperationRecord(
                actionID: request.actionID,
                kind: .runCommand,
                status: recordStatus,
                sourcePaths: request.context.selectedItems.map(\.path),
                destinationPaths: [workingDirectory],
                message: outputSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                commandExitCode: Int(exitCode),
                durationMilliseconds: durationMilliseconds()
            )
        )
    }

    private func logFailure(message: String) {
        try? JSONLineOperationLog(url: paths.operationLogURL).append(
            OperationRecord(
                actionID: request.actionID,
                kind: .runCommand,
                status: .failure,
                sourcePaths: request.context.selectedItems.map(\.path),
                destinationPaths: [request.context.targetDirectory.path],
                message: message
            )
        )
    }
}

final class CommandRunWindowCoordinator {
    static let shared = CommandRunWindowCoordinator()
    private var windows: [UUID: NSWindow] = [:]

    func open(
        request: PendingCommandRunRequest,
        paths: RightClickProStoragePaths,
        onFinish: @escaping () -> Void
    ) {
        let viewModel = CommandRunViewModel(request: request, paths: paths, onFinish: onFinish)
        let view = CommandRunWindow(viewModel: viewModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppMetadata.displayName) 命令运行"
        window.isReleasedWhenClosed = false
        window.backgroundColor = SettingsTheme.windowBackgroundColor
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows[request.id] = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.windows[request.id] = nil
        }

        viewModel.start()
    }
}

struct CommandRunWindow: View {
    @ObservedObject var viewModel: CommandRunViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "terminal")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.title)
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text(viewModel.workingDirectory.isEmpty ? "准备工作目录..." : viewModel.workingDirectory)
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Text(viewModel.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.status.color)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(viewModel.status.color.opacity(0.1), in: Capsule())

                Text(viewModel.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(SettingsTheme.muted)
                    .frame(width: 64, alignment: .trailing)

                Button {
                    viewModel.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!isRunning)
            }
            .padding(18)
            .background(SettingsTheme.windowBackground)

            Divider()

            ScrollView {
                Text(viewModel.output.isEmpty ? "等待命令输出..." : viewModel.output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(SettingsTheme.commandOutputText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(SettingsTheme.commandOutputBackground)
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var isRunning: Bool {
        if case .running = viewModel.status {
            return true
        }
        return false
    }
}

struct MenuBarContentView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开设置") {
            openSettings()
        }
        Button("修复右键菜单...") {
            viewModel.repairFinderContextMenu(restartFinder: true, userInitiated: true)
            openSettings(section: .onboarding)
        }
        Divider()
        Button("退出 \(AppMetadata.displayName)") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func openSettings(section: SettingsViewModel.Section? = nil) {
        if let section {
            viewModel.selectedSection = section
        }

        openWindow(id: "settings")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct SettingsRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var visualSelection: SettingsViewModel.Section = .onboarding
    @State private var renderedSection: SettingsViewModel.Section = .onboarding
    @State private var selectionRevision = 0

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selectedSection: visualSelection,
                badges: sidebarBadges,
                onSelect: selectSection
            )
                .frame(width: 280)

            SettingsDetailShell(section: renderedSection, viewModel: viewModel) {
                switch renderedSection {
                case .onboarding:
                    OnboardingView(viewModel: viewModel)
                case .directories:
                    DirectoryListView(viewModel: viewModel)
                case .actions:
                    ActionListView(viewModel: viewModel)
                case .templates:
                    TemplateListView(viewModel: viewModel)
                case .developer:
                    DeveloperEntrypointListView(viewModel: viewModel)
                case .commands:
                    CommandTemplateListView(viewModel: viewModel)
                case .history:
                    OperationHistoryView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsTheme.windowBackground)
        .background(SettingsWindowChromeConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            visualSelection = viewModel.selectedSection
            renderedSection = viewModel.selectedSection
        }
        .onReceive(viewModel.$selectedSection) { section in
            guard section != renderedSection else { return }
            visualSelection = section
            renderedSection = section
        }
    }

    private var sidebarBadges: [SettingsViewModel.Section: String] {
        Dictionary(
            uniqueKeysWithValues: SettingsViewModel.Section.allCases.compactMap { section in
                viewModel.sectionBadge(for: section).map { (section, $0) }
            }
        )
    }

    private func selectSection(_ section: SettingsViewModel.Section) {
        guard visualSelection != section || renderedSection != section else {
            return
        }

        visualSelection = section
        selectionRevision += 1
        let revision = selectionRevision

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            guard selectionRevision == revision, visualSelection == section else {
                return
            }

            renderedSection = section
            viewModel.selectedSection = section
        }
    }
}

private enum SettingsChromeMetrics {
    static let sidebarTopPadding: CGFloat = 64
    static let sidebarBottomPadding: CGFloat = 24
}

private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.backgroundColor = SettingsTheme.windowBackgroundColor
    }
}

private enum SettingsTheme {
    static let accent = adaptiveColor(
        light: NSColor(calibratedRed: 0.24, green: 0.32, blue: 0.98, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.54, green: 0.62, blue: 1.0, alpha: 1.0)
    )
    static let accentSoft = adaptiveColor(
        light: NSColor(calibratedRed: 0.93, green: 0.92, blue: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.34, alpha: 1.0)
    )
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let hairline = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
    )
    static let windowBackgroundColor = adaptiveNSColor(
        light: NSColor(calibratedRed: 0.96, green: 0.97, blue: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1.0)
    )
    static let sidebarBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.58),
        dark: NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.12, alpha: 0.92)
    )
    static let headerBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.085, green: 0.095, blue: 0.13, alpha: 0.96)
    )
    static let pageOverlay = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.34),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.035)
    )
    static let surface = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.90),
        dark: NSColor(calibratedRed: 0.115, green: 0.13, blue: 0.17, alpha: 0.96)
    )
    static let surfaceSoft = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.055)
    )
    static let surfaceElevated = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.14, green: 0.155, blue: 0.20, alpha: 1.0)
    )
    static let controlBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.07)
    )
    static let controlBackgroundHover = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.11)
    )
    static let subtleFill = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.035),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.065)
    )
    static let menuShadow = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.16),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.45)
    )
    static let commandOutputText = adaptiveColor(
        light: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.18, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.93, alpha: 1.0)
    )
    static let commandOutputBackground = adaptiveColor(
        light: NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.985, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.10, alpha: 1.0)
    )

    static var windowBackground: LinearGradient {
        LinearGradient(
            colors: [
                adaptiveColor(
                    light: NSColor(calibratedRed: 0.96, green: 0.97, blue: 1.0, alpha: 1.0),
                    dark: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1.0)
                ),
                adaptiveColor(
                    light: NSColor(calibratedWhite: 1.0, alpha: 1.0),
                    dark: NSColor(calibratedRed: 0.09, green: 0.105, blue: 0.14, alpha: 1.0)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var menuBackground: LinearGradient {
        LinearGradient(
            colors: [
                adaptiveColor(
                    light: NSColor(calibratedWhite: 1.0, alpha: 0.96),
                    dark: NSColor(calibratedRed: 0.13, green: 0.145, blue: 0.18, alpha: 0.98)
                ),
                adaptiveColor(
                    light: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: 1.0),
                    dark: NSColor(calibratedRed: 0.09, green: 0.105, blue: 0.14, alpha: 1.0)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.45, green: 0.55, blue: 1.0),
                Color(red: 0.31, green: 0.22, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNSColor(light: light, dark: dark))
    }

    private static func adaptiveNSColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

private enum RightClickProIconAsset {
    static let resourceName = "RightClickProIcon"
    static let pngExtension = "png"
    static let sourceRelativePath = "design/icon.png"
    static let image = loadImage()

    private static func loadImage() -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: pngExtension),
           let image = NSImage(contentsOf: bundledURL) {
            return image
        }

        let fileManager = FileManager.default
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let packageRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidateURLs = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(sourceRelativePath),
            packageRootURL.appendingPathComponent(sourceRelativePath)
        ]

        for url in candidateURLs where fileManager.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }
}

struct RightClickProBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = RightClickProIconAsset.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(SettingsTheme.brandGradient)
            Image(systemName: "cursorarrow")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-18))
        }
    }
}

struct SettingsSidebar: View {
    let selectedSection: SettingsViewModel.Section
    let badges: [SettingsViewModel.Section: String]
    let onSelect: (SettingsViewModel.Section) -> Void

    private let sections = SettingsViewModel.SidebarGroup.allCases.flatMap { $0.sections }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                RightClickProBrandIcon(size: 44)
                    .shadow(color: SettingsTheme.accent.opacity(0.18), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppMetadata.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text("Mac 右键效率工具")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                    Text(AppMetadata.versionText)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.muted.opacity(0.82))
                        .monospacedDigit()
                }
            }

            VStack(spacing: 8) {
                ForEach(sections) { section in
                    SidebarNavigationRow(
                        section: section,
                        badge: badges[section],
                        isSelected: selectedSection == section
                    ) {
                        onSelect(section)
                    }
                }
            }

            Spacer(minLength: 16)

            SidebarHintCard()
        }
        .padding(.horizontal, 24)
        .padding(.top, SettingsChromeMetrics.sidebarTopPadding)
        .padding(.bottom, SettingsChromeMetrics.sidebarBottomPadding)
        .background(SettingsTheme.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsTheme.hairline)
                .frame(width: 1)
        }
    }
}

struct SidebarHintCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text("小提示")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                Text("使用排序箭头调整顺序，启用/禁用快速定制你的右键菜单。")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct SidebarNavigationRow: View {
    let section: SettingsViewModel.Section
    let badge: String?
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var didSelectDuringPress = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 22)
                .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.muted)

            Text(section.sidebarTitle)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SettingsTheme.controlBackgroundHover, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(
            isSelected ? SettingsTheme.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !didSelectDuringPress else { return }
                    didSelectDuringPress = true
                    onSelect()
                }
                .onEnded { _ in
                    didSelectDuringPress = false
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsDetailShell<Content: View>: View {
    let section: SettingsViewModel.Section
    @ObservedObject var viewModel: SettingsViewModel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                    .layoutPriority(1)

                if section != .onboarding {
                    Spacer(minLength: 12)

                    headerActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, section == .directories ? 20 : (section == .onboarding ? 22 : 28))
            .padding(.bottom, section == .onboarding ? 8 : 16)
            .background(SettingsTheme.headerBackground)

            if section != .onboarding && section != .directories {
                Rectangle()
                    .fill(SettingsTheme.hairline)
                    .frame(height: 1)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.rawValue)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            if section == .onboarding {
                HStack(spacing: 0) {
                    Text("管理和自定义 ")
                    Text("Finder")
                        .foregroundStyle(SettingsTheme.accent)
                    Text(" 右键菜单，提升操作效率")
                }
                .font(.system(size: 14))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
            } else {
                Text(section.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            if section == .directories {
                DirectoryHeaderAddButton {
                    viewModel.addDirectoryBookmarkFromPanel()
                }
            } else if section == .developer {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }
                DeveloperHeaderAddButton {
                    viewModel.requestAddDeveloperEntrypoint()
                }
            } else if section == .commands {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }
                CommandHeaderAddButton {
                    viewModel.requestAddCommandTemplate()
                }
            } else if section == .templates {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }
                TemplateHeaderAddButton {
                    viewModel.requestAddTemplate()
                }
            } else if section == .actions {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }

                SearchField(placeholder: "搜索菜单项或功能...", text: $viewModel.actionSearchText)
                    .frame(width: 270)

                ActionHeaderAddMenu(viewModel: viewModel)
            } else {
                StatusBadge(
                    message: viewModel.statusMessage,
                    tone: viewModel.statusTone,
                    isDirty: viewModel.hasUnsavedChanges
                )

                SaveConfigButton(viewModel: viewModel)
            }
        }
        .frame(alignment: .trailing)
        .layoutPriority((section == .actions || section == .developer || section == .templates) ? 2 : 0)
    }

    private var titleSize: CGFloat {
        switch section {
        case .onboarding, .directories:
            return 22
        case .actions:
            return 26
        default:
            return 28
        }
    }
}

struct ActionHeaderAddMenu: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Menu {
            Button {
                viewModel.addDirectoryBookmarkFromPanel()
            } label: {
                Label("添加常用目录", systemImage: "folder.badge.plus")
            }

            Button {
                viewModel.requestAddDeveloperEntrypoint()
            } label: {
                Label("添加开发者入口", systemImage: "terminal")
            }

            Button {
                viewModel.requestAddTemplate()
            } label: {
                Label("添加新建模板", systemImage: "doc.badge.plus")
            }

            Button {
                viewModel.requestAddCommandTemplate()
            } label: {
                Label("添加命令模板", systemImage: "terminal")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("新增菜单项")
                    .font(.system(size: 14, weight: .semibold))
                Divider()
                    .frame(height: 18)
                    .overlay(.white.opacity(0.42))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("新增菜单项")
    }
}

struct DirectoryHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加目录", systemImage: "plus.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加常用目录")
    }
}

struct DeveloperHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加快捷入口", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 124, height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("添加开发者快捷入口")
    }
}

struct TemplateHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加模板", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 112, height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("添加新建文件模板")
    }
}

struct CommandHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加命令", systemImage: "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 112, height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("添加命令模板")
    }
}

struct StatusBadge: View {
    let message: String
    let tone: SettingsViewModel.StatusTone
    let isDirty: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isDirty ? "circle.fill" : "checkmark.circle.fill")
                .font(.caption)
            Text(message.isEmpty ? "就绪" : message)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(tone.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tone.color.opacity(0.16)))
    }
}

struct SaveConfigButton: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        if viewModel.hasUnsavedChanges {
            Button {
                viewModel.saveConfig()
            } label: {
                Label("保存配置", systemImage: "square.and.arrow.down")
                    .frame(minWidth: 86)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: [.command])
        } else {
            Button {
                viewModel.saveConfig()
            } label: {
                Label("已保存", systemImage: "checkmark")
                    .frame(minWidth: 86)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(true)
        }
    }
}

struct DesignPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(SettingsTheme.pageOverlay)
    }
}

struct OverviewPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .background(SettingsTheme.pageOverlay)
    }
}

struct DirectoryPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(SettingsTheme.pageOverlay)
    }
}

struct DesignPanel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct HintBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.title3)
                .foregroundStyle(SettingsTheme.accent)
            Text("提示：")
                .font(.headline)
                .foregroundStyle(SettingsTheme.accent)
            Text(text)
                .foregroundStyle(SettingsTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(SettingsTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.accent.opacity(0.18)))
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SettingsTheme.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(SettingsTheme.ink)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 220, maxWidth: 360, minHeight: 36)
        .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct PageToolbar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            leading
            Spacer(minLength: 16)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PreviewSection<Intro: View>: View {
    let rootItems: [FinderMenuItem]
    let submenuTitle: String?
    let submenuItems: [FinderMenuItem]
    @ViewBuilder var intro: Intro

    init(
        rootItems: [FinderMenuItem],
        submenuTitle: String? = nil,
        submenuItems: [FinderMenuItem],
        @ViewBuilder intro: () -> Intro
    ) {
        self.rootItems = rootItems
        self.submenuTitle = submenuTitle
        self.submenuItems = submenuItems
        self.intro = intro()
    }

    var body: some View {
        DesignPanel {
            VStack(alignment: .leading, spacing: 18) {
                intro
                FinderMenuPreview(
                    title: nil,
                    caption: nil,
                    rootItems: rootItems,
                    submenuTitle: submenuTitle,
                    submenuItems: submenuItems,
                    isFramed: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct IconBadge: View {
    let systemImage: String
    var tint: Color = SettingsTheme.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum RowIconControlTone {
    case neutral
    case accent
    case destructive

    var foreground: Color {
        switch self {
        case .neutral:
            return SettingsTheme.muted
        case .accent:
            return SettingsTheme.accent
        case .destructive:
            return .red
        }
    }

    var hoverBackground: Color {
        switch self {
        case .neutral:
            return SettingsTheme.accent.opacity(0.08)
        case .accent:
            return SettingsTheme.accent.opacity(0.12)
        case .destructive:
            return Color.red.opacity(0.1)
        }
    }

    var hoverStroke: Color {
        switch self {
        case .neutral:
            return SettingsTheme.accent.opacity(0.18)
        case .accent:
            return SettingsTheme.accent.opacity(0.24)
        case .destructive:
            return Color.red.opacity(0.22)
        }
    }
}

struct RowIconControlLabel: View {
    let systemImage: String
    var tone: RowIconControlTone = .neutral
    var isDisabled = false
    var size: CGFloat = 28
    var iconSize: CGFloat = 13
    var cornerRadius: CGFloat = 7
    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering in
                guard !isDisabled else { return }
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var foreground: Color {
        isDisabled ? SettingsTheme.muted.opacity(0.36) : tone.foreground
    }

    private var background: Color {
        if isDisabled {
            return SettingsTheme.subtleFill.opacity(0.65)
        }
        return isHovered ? tone.hoverBackground : SettingsTheme.controlBackground
    }

    private var stroke: Color {
        if isDisabled {
            return SettingsTheme.hairline.opacity(0.65)
        }
        return isHovered ? tone.hoverStroke : SettingsTheme.hairline
    }
}

struct RowIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var helpText: String? = nil
    var tone: RowIconControlTone = .neutral
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RowIconControlLabel(
                systemImage: systemImage,
                tone: tone,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText ?? accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        OverviewPageScroll {
            if viewModel.shouldShowFinderExtensionSetupBanner {
                FinderExtensionSetupBanner(viewModel: viewModel)
            }

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("功能总览")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)

                    VStack(spacing: 14) {
                        OverviewFeatureRow(
                            systemImage: "folder",
                            title: "常用目录快捷直达",
                            detail: "在右键菜单中快速打开常用目录和文件夹",
                            meta: "已启用 \(viewModel.bookmarks.bookmarks.count) 个目录",
                            isOn: !viewModel.bookmarks.bookmarks.isEmpty
                        ) {
                            viewModel.selectedSection = .directories
                        }

                        OverviewFeatureRow(
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            title: "开发者快捷入口",
                            detail: "快速打开常用开发工具和项目",
                            meta: "已启用 \(enabledDeveloperCount) 个入口",
                            isOn: enabledDeveloperCount > 0
                        ) {
                            viewModel.selectedSection = .developer
                        }

                        OverviewFeatureRow(
                            systemImage: "scissors",
                            title: "剪切 / 粘贴文件",
                            detail: "增强版剪切、粘贴与历史记录",
                            meta: "剪贴板中有 \(fileOperationActionCount) 项内容",
                            isOn: fileOperationActionCount > 0
                        ) {
                            viewModel.selectedSection = .history
                        }

                        OverviewFeatureRow(
                            systemImage: "doc.badge.plus",
                            title: "右键新建文件",
                            detail: "在右键菜单中新建常用文件类型",
                            meta: "已启用 \(enabledTemplateCount) 个模板",
                            isOn: enabledTemplateCount > 0
                        ) {
                            viewModel.selectedSection = .templates
                        }
                    }

                    OverviewHintBanner()
                        .padding(.top, 2)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                OverviewFinderMenuCallout(items: overviewSubmenuItems)
                    .frame(width: 262)
            }

            OverviewMetricStrip(viewModel: viewModel)
        }
    }

    private var enabledDeveloperCount: Int {
        viewModel.config.actions.filter {
            $0.group == .developerEntrypoints && $0.isEnabled
        }.count
    }

    private var enabledTemplateCount: Int {
        viewModel.config.actions.filter {
            $0.kind == .createFile && $0.isEnabled
        }.count
    }

    private var fileOperationActionCount: Int {
        viewModel.config.actions.filter {
            $0.group == .fileOperations && $0.isEnabled
        }.count
    }

    private var overviewRootMenuItems: [FinderMenuItem] {
        [
            FinderMenuItem(title: "新建文件夹", systemImage: nil, hasSubmenu: true),
            FinderMenuItem(title: "显示简介", systemImage: nil),
            FinderMenuItem(title: "排序方式", systemImage: nil, hasSubmenu: true),
            FinderMenuItem(title: "整理方式", systemImage: nil, hasSubmenu: true)
        ]
    }

    private var overviewSubmenuItems: [FinderMenuItem] {
        [
            FinderMenuItem(title: "常用目录", systemImage: "folder", tint: .blue, hasSubmenu: true),
            FinderMenuItem(title: "开发者入口", systemImage: "chevron.left.forwardslash.chevron.right", tint: SettingsTheme.accent, hasSubmenu: true),
            FinderMenuItem(title: "剪切 / 粘贴文件", systemImage: "scissors", tint: SettingsTheme.accent, hasSubmenu: true),
            FinderMenuItem(title: "新建文件", systemImage: "doc", tint: SettingsTheme.accent, hasSubmenu: true)
        ]
    }
}

struct FinderExtensionSetupBanner: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(systemImage: "puzzlepiece.extension", tint: .orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Finder 右键菜单需要处理")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text(viewModel.finderExtensionSetupMessage.isEmpty ? "\(AppMetadata.displayName) 未完成 Finder Extension 自动注入，请手动修复后重新打开右键菜单。" : viewModel.finderExtensionSetupMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button {
                        viewModel.openFinderExtensionSettings()
                    } label: {
                        Label("打开扩展设置", systemImage: "gearshape")
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("打开系统设置中的 Finder 扩展页面")

                    Button {
                        viewModel.restartFinder()
                    } label: {
                        Label(viewModel.isRepairingFinderMenu ? "修复中..." : "修复并重启 Finder", systemImage: "arrow.clockwise")
                            .frame(minWidth: 136)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(viewModel.isRepairingFinderMenu)
                    .help("会短暂关闭并重新打开 Finder 窗口")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

struct OverviewFeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let meta: String
    let isOn: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(width: 112, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsTheme.muted)
                    .frame(width: 14)

                Toggle("", isOn: .constant(isOn))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(SettingsTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

struct OverviewHintBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "lightbulb")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 32)

            Text("提示")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)

            Text("所有功能均可在右键菜单中使用，支持箭头排序与自定义设置。")
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(SettingsTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.accent.opacity(0.18)))
    }
}

struct OverviewFinderMenuCallout: View {
    let items: [FinderMenuItem]

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            OverviewContextMenu(items: items)

            HStack(alignment: .top, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    OverviewCalloutArrow()
                        .stroke(
                            SettingsTheme.accent,
                            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, dash: [5, 5])
                        )
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.accent)
                        .rotationEffect(.degrees(28))
                        .offset(x: 4, y: -3)
                }
                .frame(width: 40, height: 52)
                .padding(.top, 0)

                Text("在 Finder 右键菜单中\n快速访问常用功能")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsTheme.accent)
                    .lineSpacing(5)
                    .rotationEffect(.degrees(-2))
                    .padding(.top, 28)
            }
            .padding(.trailing, 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct OverviewCalloutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 4))
        path.addCurve(
            to: CGPoint(x: rect.minX + 8, y: rect.maxY - 8),
            control1: CGPoint(x: rect.midX + 4, y: rect.midY - 6),
            control2: CGPoint(x: rect.minX + 2, y: rect.midY + 22)
        )
        return path
    }
}

struct OverviewContextMenu: View {
    let items: [FinderMenuItem]

    var body: some View {
        VStack(spacing: 0) {
            OverviewContextMenuRow(item: FinderMenuItem(title: "新建文件夹", hasSubmenu: true))
            Divider().padding(.horizontal, 12)
            OverviewContextMenuRow(item: FinderMenuItem(title: "显示简介"))
            OverviewContextMenuRow(item: FinderMenuItem(title: "更改桌面背景..."))
            Divider().padding(.horizontal, 12)
            OverviewContextMenuRow(item: FinderMenuItem(title: "使用叠放"))
            OverviewContextMenuRow(item: FinderMenuItem(title: "排序方式", hasSubmenu: true))
            OverviewContextMenuRow(item: FinderMenuItem(title: "整理"))
            OverviewContextMenuRow(item: FinderMenuItem(title: "整理方式", hasSubmenu: true))
            OverviewContextMenuRow(item: FinderMenuItem(title: "查看显示选项"))
            Divider().padding(.horizontal, 12)

            ForEach(items) { item in
                OverviewContextMenuRow(item: item)
            }

            Divider().padding(.horizontal, 12)
            OverviewContextMenuRow(item: FinderMenuItem(title: "服务", hasSubmenu: true))
        }
        .padding(.vertical, 8)
        .frame(width: 228)
        .background(SettingsTheme.menuBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SettingsTheme.hairline))
        .shadow(color: SettingsTheme.menuShadow, radius: 18, x: 0, y: 12)
    }
}

struct OverviewContextMenuRow: View {
    let item: FinderMenuItem

    var body: some View {
        HStack(spacing: 10) {
            if let icon = item.icon {
                MenuIconView(
                    icon: icon,
                    tint: item.tint,
                    isHighlighted: item.isHighlighted,
                    size: 17,
                    font: .system(size: 13, weight: .medium)
                )
            }

            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if item.hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SettingsTheme.muted)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }
}

struct OverviewMetricStrip: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel(padding: 0) {
            HStack(spacing: 0) {
                OverviewMetric(systemImage: "clock", title: "高效便捷", subtitle: "常用功能一步直达")
                metricDivider
                OverviewMetric(systemImage: "shield.checkered", title: "安全可靠", subtitle: "本地运行，保护隐私")
                metricDivider
                OverviewMetric(systemImage: "bolt", title: "轻量稳定", subtitle: "占用资源少，运行流畅")
                metricDivider
                OverviewMetric(systemImage: "slider.horizontal.3", title: "高度可自定义", subtitle: "按需启用，自由配置")
            }
            .frame(height: 70)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SettingsTheme.hairline)
            .frame(width: 1, height: 38)
    }
}

struct OverviewMetric: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 14)
    }
}

struct DirectoryListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""

    private var bookmarks: [DirectoryBookmark] {
        viewModel.bookmarks.bookmarks
    }

    private var filteredBookmarks: [DirectoryBookmark] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.displayName.lowercased().contains(keyword) || $0.path.lowercased().contains(keyword)
        }
    }

    private var previewItems: [FinderMenuItem] {
        let enabledBookmarks = bookmarks.filter { viewModel.isDirectoryBookmarkEnabled($0.id) }
        return Array(enabledBookmarks.prefix(7)).map {
            FinderMenuItem(title: $0.displayName, icon: .filePath($0.path), tint: directoryTint(for: $0), id: $0.id)
        }
    }

    var body: some View {
        let rows = filteredBookmarks
        let visibleBookmarkIDs = rows.map(\.id)

        DirectoryPageScroll {
            SearchField(placeholder: "搜索目录名称或路径", text: $searchText)
                .frame(width: 360, alignment: .leading)

            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    DirectoryTableHeader()
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, bookmark in
                        DirectoryTableRow(
                            bookmark: bookmark,
                            isEnabled: viewModel.isDirectoryBookmarkEnabled(bookmark.id),
                            canMoveUp: index > 0,
                            canMoveDown: index < rows.count - 1,
                            onToggle: { isEnabled in
                                viewModel.setDirectoryBookmarkEnabled(isEnabled, bookmarkID: bookmark.id)
                            },
                            onMoveUp: {
                                viewModel.moveDirectoryBookmark(bookmarkID: bookmark.id, visibleBookmarkIDs: visibleBookmarkIDs, offset: -1)
                            },
                            onMoveDown: {
                                viewModel.moveDirectoryBookmark(bookmarkID: bookmark.id, visibleBookmarkIDs: visibleBookmarkIDs, offset: 1)
                            },
                            onEdit: {
                                viewModel.replaceDirectoryBookmarkFromPanel(bookmarkID: bookmark.id)
                            },
                            onDelete: {
                                viewModel.deleteDirectoryBookmark(bookmarkID: bookmark.id)
                            }
                        )
                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                    if rows.isEmpty {
                        EmptyStateRow(title: "没有匹配的目录", systemImage: "folder.badge.questionmark")
                    }
                }
            }

            DirectoryMenuPreviewPanel(items: previewItems)

            DirectoryHintBanner()
        }
    }

    private func directoryTint(for bookmark: DirectoryBookmark) -> Color {
        let lowercased = bookmark.path.lowercased()
        if lowercased.contains("workspace") || lowercased.contains("project") { return .orange }
        if lowercased.contains("server") || lowercased.contains("smb://") { return SettingsTheme.accent }
        return .blue
    }
}

struct DirectoryMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: rootMenuItems,
            submenuTitle: "常用目录",
            submenuItems: items.isEmpty ? [FinderMenuItem(title: "暂无启用目录")] : items
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("右键菜单预览")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("在 Finder 中右键时，启用的目录会出现在「常用目录」子菜单中。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        FinderPreviewRootMenu.standardContainerMenu(
            highlighting: FinderMenuItem(
                title: "常用目录",
                systemImage: "folder",
                tint: .blue,
                isHighlighted: true,
                hasSubmenu: true
            )
        )
    }
}

struct DirectoryHintBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 24)

            Text("提示：")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)

            Text("将最常用的目录放在前面位置，访问更高效。")
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(SettingsTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.accent.opacity(0.18)))
    }
}

struct DirectoryTableHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("排序").frame(width: 58, alignment: .center)
            Text("名称").frame(width: 260, alignment: .leading)
            Text("路径").frame(maxWidth: .infinity, alignment: .leading)
            Text("启用").frame(width: 90, alignment: .center)
            Text("操作").frame(width: 104, alignment: .center)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(SettingsTheme.ink)
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(SettingsTheme.pageOverlay)
    }
}

struct DirectoryTableRow: View {
    let bookmark: DirectoryBookmark
    let isEnabled: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: (Bool) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            SortStepControls(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .frame(width: 58, alignment: .center)

            HStack(spacing: 12) {
                MenuIconView(
                    icon: .filePath(bookmark.path),
                    tint: tint,
                    size: 24,
                    font: .system(size: 20, weight: .regular)
                )
                .frame(width: 28)
                Text(bookmark.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
            }
            .frame(width: 260, alignment: .leading)
            .opacity(isEnabled ? 1 : 0.48)

            Text(displayPath)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { isEnabled in
                    onToggle(isEnabled)
                }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(width: 90)

            HStack(spacing: 10) {
                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(bookmark.displayName)",
                    helpText: "编辑目录"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(bookmark.displayName)",
                    helpText: "删除目录",
                    tone: .destructive
                ) {
                    onDelete()
                }
            }
            .frame(width: 104)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    private var tint: Color {
        let lowercased = bookmark.path.lowercased()
        if lowercased.contains("workspace") || lowercased.contains("project") { return .orange }
        if lowercased.contains("server") || lowercased.contains("smb://") { return SettingsTheme.accent }
        return .blue
    }

    private var displayPath: String {
        let homeCandidates = [
            "/Users/\(NSUserName())",
            FileManager.default.homeDirectoryForCurrentUser.path
        ]

        for home in homeCandidates where bookmark.path.hasPrefix(home) {
            let suffix = bookmark.path.dropFirst(home.count)
            return "~\(suffix)"
        }

        return bookmark.path
    }
}

enum ActionManagementFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case create = "新建"
    case operations = "操作"
    case tools = "工具"

    var id: String { rawValue }

    func matches(_ action: RightClickProAction) -> Bool {
        switch self {
        case .all:
            return true
        case .create:
            return action.kind == .createFile || action.group == .createFile
        case .operations:
            return [
                .commonDirectories,
                .moveToCommonDirectory,
                .copyToCommonDirectory,
                .fileOperations
            ].contains(action.group)
        case .tools:
            return action.group == .developerEntrypoints || action.kind == .openInApp || action.kind == .runCommand
        }
    }
}

enum ActionPreviewContext: String, CaseIterable, Identifiable {
    case fileFolder = "文件/文件夹"
    case desktop = "桌面空白处"
    case disk = "磁盘"

    var id: String { rawValue }

    var finderInvocation: FinderInvocation {
        switch self {
        case .fileFolder:
            return .selection
        case .desktop:
            return .container
        case .disk:
            return .toolbar
        }
    }
}

enum ActionGroupingMode: String, CaseIterable, Identifiable {
    case type = "按类型分组"
    case placement = "按菜单层级"
    case visibility = "按适用范围"
    case status = "按启用状态"
    case none = "不分组"

    var id: String { rawValue }
}

enum ActionSortingMode: String, CaseIterable, Identifiable {
    case custom = "自定义排序"
    case name = "按名称排序"
    case type = "按类型排序"
    case status = "启用优先"

    var id: String { rawValue }
}

struct ActionGroupSection: Identifiable {
    let id: String
    let title: String
    var rows: [RightClickProAction]
}

struct ActionListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedFilter: ActionManagementFilter = .all
    @State private var previewContext: ActionPreviewContext = .fileFolder
    @State private var groupingMode: ActionGroupingMode = .type
    @State private var sortingMode: ActionSortingMode = .custom
    @State private var showsGroupSeparators = true

    private var sortedActions: [RightClickProAction] {
        viewModel.config.actions.sorted(by: { $0.order < $1.order })
    }

    private var actionCounts: [ActionManagementFilter: Int] {
        Dictionary(
            uniqueKeysWithValues: ActionManagementFilter.allCases.map { filter in
                (filter, sortedActions.filter { filter.matches($0) }.count)
            }
        )
    }

    private func filteredActions(from actions: [RightClickProAction]) -> [RightClickProAction] {
        let categoryRows = actions.filter { selectedFilter.matches($0) }
        let keyword = viewModel.actionSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return categoryRows }
        return categoryRows.filter { action in
            action.title.lowercased().contains(keyword)
                || action.kind.displayName.lowercased().contains(keyword)
                || (action.group?.displayName.lowercased().contains(keyword) ?? false)
                || action.visibility.displayName.lowercased().contains(keyword)
        }
    }

    private func arrangedActions(from actions: [RightClickProAction]) -> [RightClickProAction] {
        let rows = filteredActions(from: actions)

        switch sortingMode {
        case .custom:
            return rows.sorted { $0.order < $1.order }
        case .name:
            return rows.sorted {
                let comparison = $0.title.localizedStandardCompare($1.title)
                return comparison == .orderedSame ? $0.order < $1.order : comparison == .orderedAscending
            }
        case .type:
            return rows.sorted {
                let comparison = $0.managementType.localizedStandardCompare($1.managementType)
                return comparison == .orderedSame ? $0.order < $1.order : comparison == .orderedAscending
            }
        case .status:
            return rows.sorted {
                if $0.isEnabled != $1.isEnabled {
                    return $0.isEnabled && !$1.isEnabled
                }
                return $0.order < $1.order
            }
        }
    }

    private func actionSections(from rows: [RightClickProAction]) -> [ActionGroupSection] {
        guard groupingMode != .none else {
            return [ActionGroupSection(id: "all", title: "全部菜单项", rows: rows)]
        }

        var sections: [ActionGroupSection] = []
        var sectionIndexes: [String: Int] = [:]

        for action in rows {
            let title = groupTitle(for: action)
            if let index = sectionIndexes[title] {
                sections[index].rows.append(action)
            } else {
                sectionIndexes[title] = sections.count
                sections.append(ActionGroupSection(id: "\(groupingMode.id)-\(title)", title: title, rows: [action]))
            }
        }

        return sections
    }

    private func groupTitle(for action: RightClickProAction) -> String {
        switch groupingMode {
        case .type:
            return action.managementType
        case .placement:
            return action.placement.displayName
        case .visibility:
            let displayName = action.visibility.displayName
            return displayName.isEmpty ? "未设置" : displayName
        case .status:
            return action.isEnabled ? "已启用" : "已禁用"
        case .none:
            return "全部菜单项"
        }
    }

    var body: some View {
        let actions = sortedActions
        let rows = arrangedActions(from: actions)
        let sections = actionSections(from: rows)

        GeometryReader { proxy in
            let metrics = layoutMetrics(for: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: metrics.previewWidth > 0 ? 18 : 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            ActionManagementTable(
                                sections: sections,
                                allActions: actions,
                                showsGroupSeparators: showsGroupSeparators,
                                allowsCustomOrdering: sortingMode == .custom,
                                selectedFilter: $selectedFilter,
                                counts: actionCounts,
                                viewModel: viewModel
                            )

                            ActionManagementRuleGrid(
                                viewModel: viewModel,
                                groupingMode: $groupingMode,
                                sortingMode: $sortingMode,
                                showsGroupSeparators: $showsGroupSeparators
                            )

                            ActionManagementHintBar()
                        }
                        .frame(width: metrics.tableWidth, alignment: .topLeading)

                        if metrics.previewWidth > 0 {
                            ActionMenuPreviewCard(
                                selectedContext: $previewContext,
                                actions: rows,
                                config: viewModel.config,
                                bookmarks: viewModel.bookmarks
                            )
                            .frame(width: metrics.previewWidth)
                        }
                    }

                    if metrics.previewWidth == 0 {
                        ActionMenuPreviewCard(
                            selectedContext: $previewContext,
                            actions: rows,
                            config: viewModel.config,
                            bookmarks: viewModel.bookmarks
                        )
                        .frame(width: metrics.contentWidth)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(width: metrics.contentWidth + 56, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(SettingsTheme.pageOverlay)
        }
    }

    private func layoutMetrics(for availableWidth: CGFloat) -> (contentWidth: CGFloat, tableWidth: CGFloat, previewWidth: CGFloat) {
        let contentWidth = max(availableWidth - 56, 760)
        let previewWidth: CGFloat = contentWidth >= 980 ? 322 : 0
        let spacing: CGFloat = previewWidth > 0 ? 22 : 0
        let tableWidth = max(690, contentWidth - previewWidth - spacing)
        return (contentWidth, tableWidth, previewWidth)
    }
}

struct ActionManagementTable: View {
    let sections: [ActionGroupSection]
    let allActions: [RightClickProAction]
    let showsGroupSeparators: Bool
    let allowsCustomOrdering: Bool
    @Binding var selectedFilter: ActionManagementFilter
    let counts: [ActionManagementFilter: Int]
    @ObservedObject var viewModel: SettingsViewModel

    private var enabledCount: Int {
        allActions.filter(\.isEnabled).count
    }

    private var disabledCount: Int {
        allActions.filter { !$0.isEnabled }.count
    }

    private var rows: [RightClickProAction] {
        sections.flatMap(\.rows)
    }

    private var shouldShowGroupHeaders: Bool {
        showsGroupSeparators && sections.count > 1
    }

    var body: some View {
        let visibleActionIDs = rows.map(\.id)

        DesignPanel(padding: 0) {
            VStack(spacing: 0) {
                ActionFilterTabs(
                    selectedFilter: $selectedFilter,
                    counts: counts
                )

                Divider()

                ActionTableHeader()

                if rows.isEmpty {
                    EmptyStateRow(
                        title: allActions.isEmpty ? "暂无菜单项" : "没有匹配的菜单项",
                        systemImage: "contextualmenu.and.cursorarrow"
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                            if shouldShowGroupHeaders {
                                ActionGroupHeader(title: section.title, count: section.rows.count)
                                Divider()
                                    .padding(.leading, 18)
                            }

                            ForEach(Array(section.rows.enumerated()), id: \.element.id) { rowIndex, action in
                                let orderIndex = visibleActionIDs.firstIndex(of: action.id) ?? 0
                                ActionEditorRow(
                                    action: action,
                                    viewModel: viewModel,
                                    canMoveUp: allowsCustomOrdering && orderIndex > 0,
                                    canMoveDown: allowsCustomOrdering && orderIndex < visibleActionIDs.count - 1,
                                    orderingHelp: allowsCustomOrdering ? nil : "切换到自定义排序后可调整顺序",
                                    onMoveUp: {
                                        viewModel.moveAction(actionID: action.id, visibleActionIDs: visibleActionIDs, offset: -1)
                                    },
                                    onMoveDown: {
                                        viewModel.moveAction(actionID: action.id, visibleActionIDs: visibleActionIDs, offset: 1)
                                    }
                                )
                                if rowIndex < section.rows.count - 1 {
                                    Divider()
                                        .padding(.leading, 26)
                                }
                            }

                            if sectionIndex < sections.count - 1 {
                                Divider()
                                    .padding(.leading, shouldShowGroupHeaders ? 0 : 26)
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Label("自定义排序下可用箭头调整菜单顺序", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(SettingsTheme.accent)

                    Spacer()

                    Text("已启用 \(enabledCount) 项，禁用 \(disabledCount) 项")
                        .foregroundStyle(SettingsTheme.muted)
                }
                .font(.caption)
                .padding(.horizontal, 18)
                .frame(height: 42)
            }
        }
    }
}

struct ActionGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsTheme.ink)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(SettingsTheme.accent.opacity(0.1), in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(SettingsTheme.accent.opacity(0.04))
    }
}

struct SortStepControls: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    var disabledHelp: String? = nil
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onMoveUp) {
                RowIconControlLabel(
                    systemImage: "chevron.up",
                    isDisabled: !canMoveUp,
                    size: 24,
                    iconSize: 10,
                    cornerRadius: 6
                )
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)
            .help(canMoveUp ? "上移" : (disabledHelp ?? "已经在最前"))
            .accessibilityLabel("上移")

            Button(action: onMoveDown) {
                RowIconControlLabel(
                    systemImage: "chevron.down",
                    isDisabled: !canMoveDown,
                    size: 24,
                    iconSize: 10,
                    cornerRadius: 6
                )
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
            .help(canMoveDown ? "下移" : (disabledHelp ?? "已经在最后"))
            .accessibilityLabel("下移")
        }
    }
}

struct ActionFilterTabs: View {
    @Binding var selectedFilter: ActionManagementFilter
    let counts: [ActionManagementFilter: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ActionManagementFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text("\(filter.rawValue) (\(counts[filter, default: 0]))")
                        .font(.system(size: 13, weight: selectedFilter == filter ? .semibold : .medium))
                        .foregroundStyle(selectedFilter == filter ? .white : SettingsTheme.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            selectedFilter == filter ? SettingsTheme.accent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct ActionTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("排序").frame(width: 54, alignment: .center)
            Text("菜单项").frame(maxWidth: .infinity, alignment: .leading)
            Text("状态").frame(width: 56, alignment: .center)
            Text("适用范围").frame(width: 130, alignment: .leading)
            Text("菜单层级").frame(width: 112, alignment: .leading)
            Text("类型").frame(width: 58, alignment: .leading)
            Text("操作").frame(width: 40, alignment: .center)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(SettingsTheme.subtleFill)
    }
}

struct ActionEditorRow: View {
    let action: RightClickProAction
    @ObservedObject var viewModel: SettingsViewModel
    let canMoveUp: Bool
    let canMoveDown: Bool
    let orderingHelp: String?
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SortStepControls(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                disabledHelp: orderingHelp,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .frame(width: 54)

            HStack(spacing: 12) {
                MenuIconView(
                    icon: MenuIconResolver.icon(for: action, config: viewModel.config, bookmarks: viewModel.bookmarks),
                    tint: action.isEnabled ? action.managementTint : Color.secondary.opacity(0.5),
                    size: 24,
                    font: .system(size: 22, weight: .semibold)
                )
                .frame(width: 30, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(action.isEnabled ? SettingsTheme.ink : .secondary)
                        .lineLimit(1)
                    Text(action.managementSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                }
                .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(3)

            Toggle("启用", isOn: Binding(
                get: { action.isEnabled },
                set: { viewModel.setActionEnabled($0, actionID: action.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.86)
            .frame(width: 56)

            ActionVisibilityMenu(action: action, viewModel: viewModel)
                .frame(width: 130, alignment: .leading)

            ActionPlacementMenu(action: action, viewModel: viewModel)
                .frame(width: 112, alignment: .leading)

            ActionTypeBadge(action: action)
                .frame(width: 58, alignment: .leading)

            HStack(spacing: 0) {
                RowIconButton(
                    systemImage: "eye.slash",
                    accessibilityLabel: "禁用 \(action.title)",
                    helpText: "从右键菜单中隐藏",
                    tone: .destructive,
                    isDisabled: !action.isEnabled
                ) {
                    viewModel.setActionEnabled(false, actionID: action.id)
                }
            }
            .frame(width: 40, alignment: .center)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .opacity(action.isEnabled ? 1 : 0.6)
    }
}

struct FlowPillGroup: View {
    let items: [String]

    var body: some View {
        let visibleItems = Array(items.prefix(2))
        let remainingCount = max(0, items.count - visibleItems.count)

        HStack(spacing: 6) {
            ForEach(visibleItems, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsTheme.muted)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(SettingsTheme.subtleFill, in: RoundedRectangle(cornerRadius: 5))
            }

            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SettingsTheme.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(SettingsTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .lineLimit(1)
    }
}

struct ActionVisibilityMenu: View {
    let action: RightClickProAction
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isHovered = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                FlowPillGroup(items: action.visibilityPills)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SettingsTheme.muted)
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? SettingsTheme.accent.opacity(0.07) : SettingsTheme.controlBackground,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isHovered ? SettingsTheme.accent.opacity(0.18) : SettingsTheme.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering in
                isHovered = action.isEnabled && hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .help("调整 \(action.title) 的显示位置")
        .accessibilityLabel("调整 \(action.title) 的显示位置")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ActionVisibility.allCases, id: \.self) { visibility in
                    let isSelected = action.visibility.contains(visibility)
                    ActionVisibilityOptionRow(
                        visibility: visibility,
                        isSelected: isSelected,
                        isOnlySelection: isSelected && action.visibility.count == 1
                    ) {
                        viewModel.toggleActionVisibility(visibility, actionID: action.id)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("至少保留一个显示位置，可多选。")
                        .font(.system(size: 10))
                }
                .foregroundStyle(SettingsTheme.muted)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .padding(8)
            .frame(width: 238)
        }
    }
}

struct ActionVisibilityOptionRow: View {
    let visibility: ActionVisibility
    let isSelected: Bool
    let isOnlySelection: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: visibility.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, height: 20)
                    .background(iconColor.opacity(isSelected ? 0.13 : 0.08), in: RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(visibility.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.ink)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isOnlySelection ? .orange : SettingsTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: trailingSystemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(trailingColor)
                    .frame(width: 16)
            }
            .padding(.horizontal, 9)
            .frame(height: 48)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(rowStroke)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var subtitle: String {
        if isOnlySelection {
            return "至少保留一个显示位置"
        }
        return isSelected ? "当前已启用" : visibility.helperText
    }

    private var iconColor: Color {
        isSelected ? SettingsTheme.accent : SettingsTheme.muted
    }

    private var trailingSystemImage: String {
        isSelected ? "checkmark.circle.fill" : "circle"
    }

    private var trailingColor: Color {
        isSelected ? SettingsTheme.accent : SettingsTheme.hairline.opacity(0.85)
    }

    private var rowBackground: Color {
        if isSelected {
            return SettingsTheme.accent.opacity(0.09)
        }
        return isHovered ? SettingsTheme.accent.opacity(0.05) : SettingsTheme.controlBackground
    }

    private var rowStroke: Color {
        if isSelected {
            return SettingsTheme.accent.opacity(0.22)
        }
        return isHovered ? SettingsTheme.accent.opacity(0.16) : SettingsTheme.hairline
    }
}

struct ActionPlacementMenu: View {
    let action: RightClickProAction
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isHovered = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.placement.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(placementTint)
                    .frame(width: 13)

                Text(action.placement.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(placementTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SettingsTheme.muted)
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? placementTint.opacity(0.08) : SettingsTheme.controlBackground,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isHovered ? placementTint.opacity(0.22) : SettingsTheme.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovering in
                isHovered = action.isEnabled && hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .help("设置 \(action.title) 的菜单层级")
        .accessibilityLabel("设置 \(action.title) 的菜单层级")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 6) {
                ActionPlacementOptionRow(
                    placement: .rootMenu,
                    title: "显示在 Finder 一级菜单",
                    subtitle: "直接出现在右键菜单中",
                    isSelected: action.placement == .rootMenu
                ) {
                    select(.rootMenu)
                }

                ActionPlacementOptionRow(
                    placement: .submenu,
                    title: "放入功能分组菜单",
                    subtitle: "归入新建文件、开发者工具等分组",
                    isSelected: action.placement == .submenu
                ) {
                    select(.submenu)
                }
            }
            .padding(8)
            .frame(width: 252)
        }
    }

    private var placementTint: Color {
        switch action.placement {
        case .rootMenu:
            return SettingsTheme.accent
        case .submenu:
            return SettingsTheme.muted
        }
    }

    private func select(_ placement: ActionPlacement) {
        guard action.placement != placement else {
            isPresented = false
            return
        }
        viewModel.setActionPlacement(placement, actionID: action.id)
        isPresented = false
    }
}

struct ActionPlacementOptionRow: View {
    let placement: ActionPlacement
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: placement.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, height: 20)
                    .background(iconColor.opacity(isSelected ? 0.13 : 0.08), in: RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.ink)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.hairline.opacity(0.85))
                    .frame(width: 16)
            }
            .padding(.horizontal, 9)
            .frame(height: 48)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(rowStroke)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var iconColor: Color {
        isSelected ? SettingsTheme.accent : SettingsTheme.muted
    }

    private var rowBackground: Color {
        if isSelected {
            return SettingsTheme.accent.opacity(0.09)
        }
        return isHovered ? SettingsTheme.accent.opacity(0.05) : SettingsTheme.controlBackground
    }

    private var rowStroke: Color {
        if isSelected {
            return SettingsTheme.accent.opacity(0.22)
        }
        return isHovered ? SettingsTheme.accent.opacity(0.16) : SettingsTheme.hairline
    }
}

struct ActionTypeBadge: View {
    let action: RightClickProAction

    var body: some View {
        Text(action.managementType)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(action.managementTint)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(action.managementTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct ActionManagementRuleGrid: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var groupingMode: ActionGroupingMode
    @Binding var sortingMode: ActionSortingMode
    @Binding var showsGroupSeparators: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ActionRuleCard(title: "分组与排序规则", subtitle: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    ActionGroupingMenu(selection: $groupingMode)
                    ActionSortingMenu(selection: $sortingMode)

                    HStack(spacing: 10) {
                        Text("按分隔线分组显示")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.muted)
                        Spacer()
                        Toggle("", isOn: $showsGroupSeparators)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
            }

            ActionRuleCard(title: "右键新建模板", subtitle: "在右键菜单中快速创建文件") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        viewModel.selectedSection = .templates
                    } label: {
                        HStack {
                            Text("管理新建模板 (\(viewModel.config.fileTemplates.count))")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(SettingsTheme.subtleFill, in: RoundedRectangle(cornerRadius: 7))

                    ActionInfoChip(title: "模板顺序会同步到新建文件菜单", systemImage: "arrow.up.arrow.down")
                }
            }

            ActionRuleCard(title: "显示条件", subtitle: "精确控制菜单项何时显示") {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        viewModel.selectedSection = .actions
                    } label: {
                        HStack {
                            Text("管理显示条件 (\(viewModel.config.actions.count))")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(SettingsTheme.subtleFill, in: RoundedRectangle(cornerRadius: 7))

                    ActionInfoChip(title: "点击表格中的适用范围标签可调整显示位置", systemImage: "eye")
                }
            }
        }
    }
}

struct ActionRuleCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        DesignPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.muted)
                    }
                }

                content
            }
        }
    }
}

struct ActionRuleMenuButton<MenuContent: View>: View {
    let title: String
    let value: String
    @ViewBuilder var menuContent: MenuContent

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
            Spacer()
            Menu {
                menuContent
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SettingsTheme.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SettingsTheme.muted)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(SettingsTheme.hairline))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }
}

struct ActionGroupingMenu: View {
    @Binding var selection: ActionGroupingMode

    var body: some View {
        ActionRuleMenuButton(title: "分组方式", value: selection.rawValue) {
            ForEach(ActionGroupingMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.rawValue, systemImage: selection == mode ? "checkmark" : "rectangle")
                }
            }
        }
    }
}

struct ActionSortingMenu: View {
    @Binding var selection: ActionSortingMode

    var body: some View {
        ActionRuleMenuButton(title: "排序方式", value: selection.rawValue) {
            ForEach(ActionSortingMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Label(mode.rawValue, systemImage: selection == mode ? "checkmark" : "rectangle")
                }
            }
        }
    }
}

struct ActionInfoChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SettingsTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(SettingsTheme.subtleFill, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(SettingsTheme.hairline))
    }
}

struct ActionManagementHintBar: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)
            Text("提示：使用左侧箭头")
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SettingsTheme.muted.opacity(0.7))
            Text("调整菜单顺序，控制右键菜单的展示位置。")
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(SettingsTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.accent.opacity(0.14)))
    }
}

struct ActionMenuPreviewCard: View {
    @Binding var selectedContext: ActionPreviewContext
    let actions: [RightClickProAction]
    let config: RightClickProConfig
    let bookmarks: DirectoryBookmarkCatalog

    var body: some View {
        DesignPanel(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("右键菜单预览")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SettingsTheme.ink)
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SettingsTheme.muted)
                    }

                    Text("在不同位置右键时的菜单效果预览。")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                }

                ActionPreviewContextPicker(selectedContext: $selectedContext)

                FinderContextMenuMock(
                    selectedContext: selectedContext,
                    actions: actions,
                    config: config,
                    bookmarks: bookmarks
                )
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)

                Text("提示：预览仅供参考，实际效果以系统为准。")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .padding(.top, 6)
            }
        }
    }
}

struct ActionPreviewContextPicker: View {
    @Binding var selectedContext: ActionPreviewContext

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ActionPreviewContext.allCases) { context in
                Button {
                    selectedContext = context
                } label: {
                    Text(context.rawValue)
                        .font(.system(size: 11, weight: selectedContext == context ? .semibold : .medium))
                        .foregroundStyle(selectedContext == context ? SettingsTheme.accent : SettingsTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            selectedContext == context ? SettingsTheme.surfaceElevated : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedContext == context ? SettingsTheme.accent.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(SettingsTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct FinderContextMenuMock: View {
    let selectedContext: ActionPreviewContext
    let actions: [RightClickProAction]
    let config: RightClickProConfig
    let bookmarks: DirectoryBookmarkCatalog

    var body: some View {
        let presentation = menuPresentation
        let groups = visibleGroups(in: presentation)

        VStack(spacing: 0) {
            FinderContextMenuStaticRow(title: "打开")
            FinderContextMenuStaticRow(title: "打开方式", hasSubmenu: true)
            menuDivider
            FinderContextMenuStaticRow(title: "移到废纸篓")
            menuDivider
            FinderContextMenuStaticRow(title: "显示简介")
            FinderContextMenuStaticRow(title: "重新命名")
            FinderContextMenuStaticRow(title: "压缩 “示例文件夹”")
            FinderContextMenuStaticRow(title: "复制")
            FinderContextMenuStaticRow(title: "制作替身")
            FinderContextMenuStaticRow(title: "快速查看")
            menuDivider

            if presentation.rootItems.isEmpty && groups.isEmpty {
                FinderContextMenuStaticRow(title: "暂无启用菜单项")
            } else {
                ForEach(presentation.rootItems) { item in
                    FinderContextMenuItemRow(item: item)
                }

                ForEach(groups, id: \.self) { group in
                    FinderContextMenuGroupRow(group: group)
                }
            }

            menuDivider
            FinderContextMenuStaticRow(title: "服务", hasSubmenu: true)
        }
        .padding(.vertical, 8)
        .frame(width: 228)
        .background(SettingsTheme.menuBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SettingsTheme.hairline))
        .shadow(color: SettingsTheme.menuShadow, radius: 18, x: 0, y: 12)
    }

    private var menuPresentation: MenuPresentation {
        var previewConfig = config
        previewConfig.actions = actions
        return MenuBuilder().buildMenu(
            config: previewConfig,
            context: FinderContext(
                invocation: selectedContext.finderInvocation,
                targetDirectory: URL(fileURLWithPath: "/tmp")
            ),
            bookmarks: bookmarks
        )
    }

    private func visibleGroups(in presentation: MenuPresentation) -> [MenuGroup] {
        MenuGroup.allCases.filter { group in
            !(presentation.groupedSubmenuItems[group]?.isEmpty ?? true)
        }
    }

    private var menuDivider: some View {
        Divider()
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

struct FinderContextMenuStaticRow: View {
    let title: String
    var hasSubmenu = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SettingsTheme.muted)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 24)
    }
}

struct FinderContextMenuItemRow: View {
    let item: MenuItemPresentation

    var body: some View {
        HStack(spacing: 9) {
            if let icon = item.icon {
                MenuIconView(
                    icon: icon,
                    tint: SettingsTheme.accent,
                    size: 16,
                    font: .system(size: 13, weight: .semibold)
                )
            }
            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }
}

struct FinderContextMenuGroupRow: View {
    let group: MenuGroup

    var body: some View {
        HStack(spacing: 9) {
            MenuIconView(
                icon: group.previewIcon,
                tint: group.previewTint,
                size: 16,
                font: .system(size: 13, weight: .semibold)
            )
            Text(group.displayName)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SettingsTheme.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }
}

struct TemplateListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: TemplateDraft?

    var body: some View {
        let templates = viewModel.config.fileTemplates

        DesignPageScroll {
            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    TemplateTableHeader()
                    if templates.isEmpty {
                        EmptyStateRow(title: "暂无模板", systemImage: "doc.badge.plus")
                    } else {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            TemplateTableRow(
                                template: template,
                                viewModel: viewModel,
                                canMoveUp: index > 0,
                                canMoveDown: index < templates.count - 1,
                                onEdit: {
                                    editingDraft = TemplateDraft(template: template)
                                },
                                onMoveUp: {
                                    viewModel.moveTemplate(template, offset: -1)
                                },
                                onMoveDown: {
                                    viewModel.moveTemplate(template, offset: 1)
                                }
                            )
                            if index < templates.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 20) {
                TemplateMenuPreviewPanel(items: templatePreviewItems)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                TemplateHintCard()
                    .frame(width: 240)
            }
        }
        .sheet(item: $editingDraft) { draft in
            TemplateEditorSheet(draft: draft) { savedDraft in
                viewModel.upsertTemplate(savedDraft.makeTemplate(), replacing: savedDraft.originalID)
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .onChange(of: viewModel.templateAddRequest) { _, _ in
            editingDraft = TemplateDraft()
        }
    }

    private var templatePreviewItems: [FinderMenuItem] {
        let enabledActions = viewModel.config.actions
            .filter { $0.kind == .createFile && $0.isEnabled }
            .sorted { $0.order < $1.order }

        return enabledActions.compactMap { action -> FinderMenuItem? in
            guard
                let templateID = action.payload.templateID,
                let template = viewModel.config.fileTemplates.first(where: { $0.id == templateID })
            else {
                return nil
            }

            return FinderMenuItem(
                title: action.title,
                icon: templateIconDescriptor(for: template),
                tint: templateTint(for: template),
                id: action.id
            )
        }
    }
}

struct TemplateTableHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("模板名称").frame(maxWidth: .infinity, alignment: .leading)
            Text("扩展名").frame(width: 150, alignment: .leading)
            Text("启用").frame(width: 84, alignment: .center)
            Text("排序").frame(width: 120, alignment: .center)
            Text("操作").frame(width: 72, alignment: .center)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 38)
        .background(SettingsTheme.pageOverlay)
    }
}

struct TemplateTableRow: View {
    let template: FileTemplate
    @ObservedObject var viewModel: SettingsViewModel
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    private var matchingAction: RightClickProAction? {
        viewModel.config.actions.first {
            $0.kind == .createFile && $0.payload.templateID == template.id
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    TemplateIconTile(template: template)
                    Text(templateDisplayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(extensionText)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 150, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { matchingAction?.isEnabled ?? false },
                set: { isEnabled in
                    guard let actionID = matchingAction?.id else { return }
                    viewModel.setActionEnabled(isEnabled, actionID: actionID)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(matchingAction == nil)
            .frame(width: 84)

            SortStepControls(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .frame(width: 120)

            HStack(spacing: 8) {
                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(templateDisplayTitle)",
                    helpText: "编辑模板"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(templateDisplayTitle)",
                    helpText: "删除模板",
                    tone: .destructive
                ) {
                    viewModel.deleteTemplate(template)
                }
            }
            .frame(width: 72)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .opacity((matchingAction?.isEnabled ?? true) ? 1 : 0.55)
    }

    private var extensionText: String {
        templateExtensionText(for: template)
    }

    private var templateDisplayTitle: String {
        matchingAction?.title ?? template.title
    }
}

struct TemplateIconTile: View {
    let template: FileTemplate

    var body: some View {
        MenuIconView(
            icon: templateIconDescriptor(for: template),
            tint: templateTint(for: template),
            size: 20,
            font: .system(size: 18, weight: .medium)
        )
            .frame(width: 28, height: 28)
            .background(templateTint(for: template).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct TemplateMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: rootMenuItems,
            submenuTitle: "新建文件",
            submenuItems: items.isEmpty ? [FinderMenuItem(title: "暂无启用模板")] : items
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("右键菜单预览")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("在 Finder 中右键时，启用的模板会出现在「新建文件」子菜单中。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        FinderPreviewRootMenu.standardContainerMenu(
            highlighting: FinderMenuItem(
                title: "新建文件",
                systemImage: "doc.badge.plus",
                tint: SettingsTheme.accent,
                isHighlighted: true,
                hasSubmenu: true
            )
        )
    }
}

struct TemplateHintCard: View {
    var body: some View {
        DesignPanel(padding: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(SettingsTheme.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 12) {
                    Text("提示")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.accent)
                    Text("可通过箭头调整顺序，右键菜单将按此顺序显示。")
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(SettingsTheme.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private func templateExtensionText(for template: FileTemplate) -> String {
    let ext = URL(fileURLWithPath: template.defaultFileName).pathExtension
    return ext.isEmpty ? "—" : ".\(ext)"
}

private func templateIconDescriptor(for template: FileTemplate) -> MenuIconDescriptor {
    let ext = templateExtensionText(for: template)
    return ext == "—" ? .systemSymbol("doc") : .fileExtension(ext)
}

private func templateTint(for template: FileTemplate) -> Color {
    switch templateExtensionText(for: template).lowercased() {
    case ".json": return .green
    case ".sh": return SettingsTheme.ink
    case ".swift": return .orange
    case ".py": return .blue
    default: return SettingsTheme.accent
    }
}

struct CommandTemplateListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: CommandTemplateDraft?

    var body: some View {
        let templates = viewModel.config.commandTemplates

        DesignPageScroll {
            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    CommandTemplateTableHeader()
                    if templates.isEmpty {
                        EmptyStateRow(title: "暂无命令模板", systemImage: "terminal")
                    } else {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            CommandTemplateTableRow(
                                template: template,
                                viewModel: viewModel,
                                canMoveUp: index > 0,
                                canMoveDown: index < templates.count - 1,
                                onEdit: {
                                    editingDraft = CommandTemplateDraft(template: template)
                                },
                                onMoveUp: {
                                    viewModel.moveCommandTemplate(template, offset: -1)
                                },
                                onMoveDown: {
                                    viewModel.moveCommandTemplate(template, offset: 1)
                                }
                            )
                            if index < templates.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            CommandMenuPreviewPanel(items: commandPreviewItems)

            CommandHintBanner()
        }
        .sheet(item: $editingDraft) { draft in
            CommandTemplateEditorSheet(draft: draft) { savedDraft in
                viewModel.upsertCommandTemplate(savedDraft)
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .onChange(of: viewModel.commandTemplateAddRequest) { _, _ in
            editingDraft = CommandTemplateDraft()
        }
    }

    private var commandPreviewItems: [FinderMenuItem] {
        let enabledActions = viewModel.config.actions
            .filter { $0.kind == .runCommand && $0.isEnabled }
            .sorted { $0.order < $1.order }

        return enabledActions.compactMap { action -> FinderMenuItem? in
            guard
                let templateID = action.payload.commandTemplateID,
                viewModel.config.commandTemplates.contains(where: { $0.id == templateID })
            else {
                return nil
            }

            return FinderMenuItem(
                title: action.title,
                icon: .systemSymbol("terminal"),
                tint: SettingsTheme.accent,
                id: action.id
            )
        }
    }
}

struct CommandTemplateTableHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("排序").frame(width: 58, alignment: .center)
            Text("名称").frame(width: 170, alignment: .leading)
            Text("命令").frame(maxWidth: .infinity, alignment: .leading)
            Text("超时").frame(width: 70, alignment: .leading)
            Text("环境").frame(width: 72, alignment: .leading)
            Text("启用").frame(width: 64, alignment: .center)
            Text("操作").frame(width: 116, alignment: .center)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(SettingsTheme.pageOverlay)
    }
}

struct CommandTemplateTableRow: View {
    let template: CommandTemplate
    @ObservedObject var viewModel: SettingsViewModel
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    private var matchingAction: RightClickProAction? {
        viewModel.config.actions.first {
            $0.kind == .runCommand && $0.payload.commandTemplateID == template.id
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            SortStepControls(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .frame(width: 58, alignment: .center)

            Button(action: onEdit) {
                HStack(spacing: 10) {
                    MenuIconView(
                        icon: .systemSymbol("terminal"),
                        tint: SettingsTheme.accent,
                        size: 22,
                        font: .system(size: 17, weight: .semibold)
                    )
                    .frame(width: 28, height: 28)
                    .background(SettingsTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                    Text(template.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 170, alignment: .leading)

            Text(template.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(template.timeoutSeconds)s")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 70, alignment: .leading)

            Text(environmentSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(template.environment.contains(where: \.isSensitive) ? .orange : SettingsTheme.muted)
                .frame(width: 72, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { matchingAction?.isEnabled ?? false },
                set: { isEnabled in
                    guard let actionID = matchingAction?.id else { return }
                    viewModel.setActionEnabled(isEnabled, actionID: actionID)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(matchingAction == nil)
            .frame(width: 64)

            HStack(spacing: 8) {
                RowIconButton(
                    systemImage: "play.fill",
                    accessibilityLabel: "运行 \(template.title)",
                    helpText: "打开实时输出窗口"
                ) {
                    viewModel.runCommandTemplateFromSettings(template)
                }

                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(template.title)",
                    helpText: "编辑命令"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(template.title)",
                    helpText: "删除命令",
                    tone: .destructive
                ) {
                    viewModel.deleteCommandTemplate(template)
                }
            }
            .frame(width: 116)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .opacity((matchingAction?.isEnabled ?? true) ? 1 : 0.55)
    }

    private var environmentSummary: String {
        guard !template.environment.isEmpty else {
            return "—"
        }
        let sensitiveCount = template.environment.filter(\.isSensitive).count
        return sensitiveCount > 0 ? "\(template.environment.count) 个 / \(sensitiveCount) 密" : "\(template.environment.count) 个"
    }
}

struct CommandMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: FinderPreviewRootMenu.standardContainerMenu(
                highlighting: FinderMenuItem(
                    title: "命令模板",
                    systemImage: "terminal",
                    tint: SettingsTheme.accent,
                    isHighlighted: true,
                    hasSubmenu: true
                )
            ),
            submenuTitle: "命令模板",
            submenuItems: items.isEmpty ? [FinderMenuItem(title: "暂无启用命令")] : items
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("实时命令窗口")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("从 Finder 右键触发后，\(AppMetadata.displayName) 会自动打开实时输出窗口。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CommandHintBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.orange)
                .frame(width: 24)

            Text("安全边界：")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text("命令只在已授权目录内运行；敏感环境变量存入 Keychain，不写入配置 JSON。")
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.18)))
    }
}

struct DeveloperEntrypointListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: DeveloperEntrypointDraft?
    @State private var selectedFilter: DeveloperEntrypointFilter = .all

    private var filteredEntrypoints: [DeveloperEntrypoint] {
        viewModel.config.developerEntrypoints.filter { selectedFilter.matches($0) }
    }

    var body: some View {
        let rows = filteredEntrypoints
        let visibleEntrypointIDs = rows.map(\.id)

        DesignPageScroll {
            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    DeveloperFilterTabs(selectedFilter: $selectedFilter)
                    Divider()
                    DeveloperTableHeader()

                    if rows.isEmpty {
                        EmptyStateRow(title: "暂无匹配的开发者入口", systemImage: "terminal")
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entrypoint in
                            DeveloperTableRow(
                                entrypoint: entrypoint,
                                viewModel: viewModel,
                                canMoveUp: index > 0,
                                canMoveDown: index < rows.count - 1,
                                onMoveUp: {
                                    viewModel.moveDeveloperEntrypoint(entrypoint, visibleEntrypointIDs: visibleEntrypointIDs, offset: -1)
                                },
                                onMoveDown: {
                                    viewModel.moveDeveloperEntrypoint(entrypoint, visibleEntrypointIDs: visibleEntrypointIDs, offset: 1)
                                },
                                onEdit: {
                                    editingDraft = DeveloperEntrypointDraft(entrypoint: entrypoint)
                                }
                            )
                            if index < rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            DeveloperMenuPreviewCard(items: developerPreviewItems)

            DeveloperHintBanner()
        }
        .sheet(item: $editingDraft) { draft in
            DeveloperEntrypointEditorSheet(
                draft: draft,
                existingEntrypoints: viewModel.config.developerEntrypoints,
                onSelectApplication: { currentDraft in
                    viewModel.makeDeveloperEntrypointDraftFromSelectedApplication(replacing: currentDraft)
                }
            ) { savedDraft in
                viewModel.upsertDeveloperEntrypoint(savedDraft.makeEntrypoint(), replacing: savedDraft.originalID)
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .onChange(of: viewModel.developerEntrypointAddRequest) { _, _ in
            editingDraft = DeveloperEntrypointDraft()
        }
    }

    private var developerPreviewItems: [FinderMenuItem] {
        let enabledActions = viewModel.config.actions
            .filter { $0.kind == .openInApp && $0.isEnabled }
            .sorted { $0.order < $1.order }

        let items = enabledActions.compactMap { action -> FinderMenuItem? in
            guard
                let entrypointID = action.payload.developerEntrypointID,
                let entrypoint = viewModel.config.developerEntrypoints.first(where: { $0.id == entrypointID })
            else {
                return nil
            }
            return FinderMenuItem(
                title: entrypoint.title,
                icon: .appBundleIdentifier(entrypoint.bundleIdentifier),
                tint: developerEntryTint(for: entrypoint),
                id: action.id
            )
        }

        guard items.count > 9 else {
            return items
        }
        return Array(items.prefix(9)) + [FinderMenuItem(title: "更多...")]
    }
}

enum DeveloperEntrypointFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case ide = "IDE"
    case terminal = "终端"
    case repository = "仓库"
    case service = "服务"
    case directory = "目录"

    var id: String { rawValue }

    func matches(_ entrypoint: DeveloperEntrypoint) -> Bool {
        guard self != .all else {
            return true
        }

        let value = "\(entrypoint.id) \(entrypoint.title) \(entrypoint.bundleIdentifier)".lowercased()
        switch self {
        case .all:
            return true
        case .ide:
            return ["vscode", "visual studio", "code", "cursor", "webstorm", "xcode", "idea", "intellij", "zed"].contains { value.contains($0) }
        case .terminal:
            return ["terminal", "iterm", "warp", "alacritty", "kitty"].contains { value.contains($0) }
        case .repository:
            return ["github", "gitlab", "repo", "repository", "projects", "仓库"].contains { value.contains($0) }
        case .service:
            return ["docker", "postman", "service", "api", "服务"].contains { value.contains($0) }
        case .directory:
            return value.hasPrefix("/") || value.hasPrefix("~") || ["folder", "directory", "logs", "config", "目录"].contains { value.contains($0) }
        }
    }
}

struct DeveloperFilterTabs: View {
    @Binding var selectedFilter: DeveloperEntrypointFilter

    var body: some View {
        HStack(spacing: 12) {
            ForEach(DeveloperEntrypointFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.system(size: 13, weight: selectedFilter == filter ? .semibold : .regular))
                        .foregroundStyle(selectedFilter == filter ? .white : SettingsTheme.ink)
                        .frame(minWidth: filter == .all ? 42 : 48)
                        .frame(height: 32)
                        .background(
                            selectedFilter == filter ? SettingsTheme.accent : SettingsTheme.controlBackgroundHover,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(selectedFilter == filter ? Color.clear : SettingsTheme.hairline)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeveloperTableHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("排序").frame(width: 56, alignment: .center)
            Text("名称").frame(width: 136, alignment: .leading)
            Text("目标方式").frame(maxWidth: .infinity, alignment: .leading)
            Text("快捷键").frame(width: 64, alignment: .leading)
            Text("启用").frame(width: 60, alignment: .center)
            Text("操作").frame(width: 76, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(SettingsTheme.subtleFill)
    }
}

struct DeveloperTableRow: View {
    let entrypoint: DeveloperEntrypoint
    @ObservedObject var viewModel: SettingsViewModel
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void

    private var matchingAction: RightClickProAction? {
        viewModel.config.actions.first {
            $0.kind == .openInApp && $0.payload.developerEntrypointID == entrypoint.id
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            SortStepControls(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .frame(width: 56)

            Button(action: onEdit) {
                HStack(spacing: 10) {
                    DeveloperEntryIcon(entrypoint: entrypoint)

                    Text(entrypoint.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 136, alignment: .leading)

            Text(entrypoint.targetMode.displayName)
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(developerEntryHotkey(for: entrypoint))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { matchingAction?.isEnabled ?? false },
                set: { isEnabled in
                    guard let actionID = matchingAction?.id else { return }
                    viewModel.setActionEnabled(isEnabled, actionID: actionID)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(matchingAction == nil)
            .frame(width: 60)

            HStack(spacing: 8) {
                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(entrypoint.title)",
                    helpText: "编辑入口"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(entrypoint.title)",
                    helpText: "删除入口",
                    tone: .destructive
                ) {
                    viewModel.deleteDeveloperEntrypoint(entrypoint)
                }
            }
            .frame(width: 76)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .opacity((matchingAction?.isEnabled ?? true) ? 1 : 0.52)
    }
}

struct DeveloperEntryIcon: View {
    let entrypoint: DeveloperEntrypoint

    var body: some View {
        MenuIconView(
            icon: .appBundleIdentifier(entrypoint.bundleIdentifier),
            tint: developerEntryTint(for: entrypoint),
            size: 22,
            font: .system(size: 16, weight: .semibold)
        )
            .frame(width: 28, height: 28)
            .background(developerEntryTint(for: entrypoint).opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct DeveloperMenuPreviewCard: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: rootMenuItems,
            submenuTitle: "开发者工具",
            submenuItems: submenuItems
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("右键菜单预览")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("在 Finder 中右键时，启用的入口会出现在「开发者工具」子菜单中。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        FinderPreviewRootMenu.standardContainerMenu(
            highlighting: FinderMenuItem(
                title: "开发者工具",
                systemImage: "chevron.left.forwardslash.chevron.right",
                tint: SettingsTheme.accent,
                isHighlighted: true,
                hasSubmenu: true
            )
        )
    }

    private var submenuItems: [FinderMenuItem] {
        items.isEmpty ? [FinderMenuItem(title: "暂无启用入口")] : items
    }
}

struct DeveloperHintBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 24)

            Text("提示：")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)

            Text("在 Finder 中右键任意位置，选择「开发者工具」即可看到以上快捷入口。")
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(SettingsTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.accent.opacity(0.18)))
    }
}

private func developerEntryTint(for entrypoint: DeveloperEntrypoint) -> Color {
    let value = "\(entrypoint.title) \(entrypoint.bundleIdentifier)".lowercased()
    if value.contains("terminal") || value.contains("iterm") { return .green }
    if value.contains("github") { return SettingsTheme.ink }
    if value.contains("docker") { return .blue }
    if value.contains("postman") { return .orange }
    if value.contains("folder") || value.contains("目录") { return .blue }
    return SettingsTheme.accent
}

private func developerEntryHotkey(for entrypoint: DeveloperEntrypoint) -> String {
    let value = "\(entrypoint.title) \(entrypoint.bundleIdentifier)".lowercased()
    if value.contains("vscode") || value.contains("visual studio") { return "⌥⌘ V" }
    if value.contains("cursor") { return "⌥⌘ C" }
    if value.contains("webstorm") { return "⌥⌘ W" }
    if value.contains("terminal") || value.contains("iterm") { return "⌥⌘ T" }
    if value.contains("github") { return "⌥⌘ G" }
    if value.contains("docker") { return "⌥⌘ D" }
    if value.contains("postman") { return "⌥⌘ P" }
    if value.contains("logs") { return "⌥⌘ L" }
    if value.contains("config") { return "⌥⌘ E" }
    return "⌥⌘ \(entrypoint.title.prefix(1).uppercased())"
}

struct OperationHistoryView: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var fileOperationRecords: [OperationRecord] {
        viewModel.recentOperations.filter {
            [.move, .copy, .cut, .paste].contains($0.kind)
        }
    }

    private var fileOperationActions: [RightClickProAction] {
        viewModel.config.actions
            .filter { $0.group == .fileOperations || [.cut, .paste, .moveToDirectory, .copyToDirectory].contains($0.kind) }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        let allRecords = fileOperationRecords
        let records = Array(allRecords.prefix(8))
        let actions = fileOperationActions
        let quickActions = Array(actions.prefix(4))
        let previewActions = Array(actions.prefix(8))

        DesignPageScroll {
            PageToolbar {
                Text("最近 \(allRecords.count) 条文件操作")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
            } trailing: {
                Button {
                    viewModel.reloadRecentOperations()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    ClipboardHistoryHeader()
                    if records.isEmpty {
                        EmptyStateRow(title: "暂无剪切或粘贴记录", systemImage: "clock")
                    } else {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            ClipboardHistoryRow(record: record)
                            if index < records.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(quickActions) { action in
                    FileOperationQuickAction(action: action, viewModel: viewModel)
                }
            }

            PreviewSection(
                    rootItems: FinderPreviewRootMenu.standardContainerMenu(
                        highlighting: FinderMenuItem(
                            title: "文件操作",
                            systemImage: "scissors",
                            tint: SettingsTheme.accent,
                            isHighlighted: true,
                            hasSubmenu: true
                        )
                    ),
                    submenuTitle: nil,
                    submenuItems: previewActions.map {
                        FinderMenuItem(
                            title: $0.title,
                            icon: MenuIconResolver.icon(for: $0, config: viewModel.config, bookmarks: viewModel.bookmarks),
                            tint: SettingsTheme.accent,
                            id: $0.id
                        )
                    }
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("右键菜单预览")
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text("在 Finder 中右键即可使用这些文件操作。")
                        .font(.callout)
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("支持剪切、复制文件与文件夹，并记录最近操作历史。")
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.accent)
                }
            }
        }
    }
}

struct ClipboardHistoryHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("文件名称").frame(width: 220, alignment: .leading)
            Text("来源路径").frame(maxWidth: .infinity, alignment: .leading)
            Text("状态").frame(width: 80, alignment: .leading)
            Text("时间").frame(width: 130, alignment: .leading)
            Text("操作").frame(width: 130, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(SettingsTheme.subtleFill)
    }
}

struct ClipboardHistoryRow: View {
    let record: OperationRecord

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                MenuIconView(
                    icon: iconDescriptor,
                    tint: record.status.color,
                    size: 24,
                    font: .title3
                )
                .frame(width: 28)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
            }
            .frame(width: 220, alignment: .leading)

            Text(sourcePath)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.status.displayName)
                .font(.callout)
                .foregroundStyle(record.status.color)
                .frame(width: 80, alignment: .leading)

            Text(operationDateFormatter.string(from: record.createdAt))
                .font(.caption)
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 130, alignment: .leading)

            HStack(spacing: 18) {
                Image(systemName: "scissors")
                Image(systemName: "doc.on.doc")
                Image(systemName: "doc.on.clipboard")
                Image(systemName: "ellipsis")
            }
            .foregroundStyle(SettingsTheme.muted)
            .frame(width: 130)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var title: String {
        if let message = record.message, !message.isEmpty {
            return message
        }
        if let path = record.sourcePaths.first {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return record.kind.displayName
    }

    private var sourcePath: String {
        record.sourcePaths.first ?? record.destinationPaths.first ?? "—"
    }

    private var iconName: String {
        switch record.kind {
        case .move:
            return "folder"
        case .copy:
            return "doc.on.doc"
        case .cut:
            return "scissors"
        case .paste:
            return "doc.on.clipboard"
        default:
            return "doc"
        }
    }

    private var iconDescriptor: MenuIconDescriptor {
        if let path = record.sourcePaths.first ?? record.destinationPaths.first {
            return .filePath(path)
        }
        return .systemSymbol(iconName)
    }
}

struct FileOperationQuickAction: View {
    let action: RightClickProAction
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel {
            HStack(spacing: 12) {
                MenuIconView(
                    icon: MenuIconResolver.icon(for: action, config: viewModel.config, bookmarks: viewModel.bookmarks),
                    tint: SettingsTheme.accent,
                    size: 24,
                    font: .title3
                )
                .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text(action.placement.displayName)
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.muted)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { action.isEnabled },
                    set: { viewModel.setActionEnabled($0, actionID: action.id) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }
}

struct EmptyStateRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(SettingsTheme.muted)
            Text(title)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }
}

struct MenuIconView: View {
    let icon: MenuIconDescriptor
    var tint: Color = SettingsTheme.muted
    var isHighlighted = false
    var size: CGFloat = 16
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        Group {
            if case let .systemSymbol(systemImage) = icon {
                Image(systemName: systemImage)
                    .font(font)
                    .foregroundStyle(isHighlighted ? .white : tint)
            } else if let image = icon.resolvedNSImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: icon.fallbackSystemImage)
                    .font(font)
                    .foregroundStyle(isHighlighted ? .white : tint)
            }
        }
        .frame(width: size, height: size)
    }
}

struct FinderMenuItem: Identifiable {
    let id: String
    let title: String
    var icon: MenuIconDescriptor? = nil
    var tint: Color = SettingsTheme.muted
    var isHighlighted = false
    var hasSubmenu = false
    var startsSection = false

    init(
        title: String,
        systemImage: String? = nil,
        icon: MenuIconDescriptor? = nil,
        tint: Color = SettingsTheme.muted,
        isHighlighted: Bool = false,
        hasSubmenu: Bool = false,
        startsSection: Bool = false,
        id: String? = nil
    ) {
        self.title = title
        self.icon = icon ?? systemImage.map(MenuIconDescriptor.systemSymbol)
        self.tint = tint
        self.isHighlighted = isHighlighted
        self.hasSubmenu = hasSubmenu
        self.startsSection = startsSection
        self.id = id ?? "\(title)|\(Self.iconIdentity(self.icon))|\(isHighlighted)|\(hasSubmenu)|\(startsSection)"
    }

    private static func iconIdentity(_ icon: MenuIconDescriptor?) -> String {
        guard let icon else {
            return "none"
        }
        switch icon {
        case .systemSymbol(let name):
            return "system:\(name)"
        case .appBundleIdentifier(let bundleIdentifier):
            return "app:\(bundleIdentifier)"
        case .filePath(let path):
            return "path:\(path)"
        case .fileExtension(let fileExtension):
            return "extension:\(fileExtension)"
        case .folder:
            return "folder"
        }
    }
}

private enum FinderPreviewRootMenu {
    static func standardContainerMenu(highlighting item: FinderMenuItem) -> [FinderMenuItem] {
        var highlightedItem = item
        highlightedItem.startsSection = true

        return [
            FinderMenuItem(title: "打开"),
            FinderMenuItem(title: "打开方式", hasSubmenu: true),
            FinderMenuItem(title: "移到废纸篓", startsSection: true),
            FinderMenuItem(title: "显示简介", startsSection: true),
            FinderMenuItem(title: "重新命名"),
            FinderMenuItem(title: "压缩 “示例文件夹”"),
            FinderMenuItem(title: "复制"),
            FinderMenuItem(title: "制作替身"),
            FinderMenuItem(title: "快速查看"),
            highlightedItem,
            FinderMenuItem(title: "服务", hasSubmenu: true, startsSection: true)
        ]
    }
}

private extension MenuIconDescriptor {
    var fallbackSystemImage: String {
        switch self {
        case .systemSymbol(let name):
            return name
        case .appBundleIdentifier:
            return "app.fill"
        case .filePath:
            return "folder.fill"
        case .fileExtension:
            return "doc"
        case .folder:
            return "folder.fill"
        }
    }

    var resolvedNSImage: NSImage? {
        let image: NSImage?
        switch self {
        case .systemSymbol:
            return nil
        case .appBundleIdentifier(let bundleIdentifier):
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                image = NSWorkspace.shared.icon(forFile: appURL.path)
            } else {
                image = NSWorkspace.shared.icon(for: .applicationBundle)
            }
        case .filePath(let path):
            if FileManager.default.fileExists(atPath: path) {
                image = NSWorkspace.shared.icon(forFile: path)
            } else if !URL(fileURLWithPath: path).pathExtension.isEmpty {
                image = nsImageForFileExtension(URL(fileURLWithPath: path).pathExtension)
            } else {
                image = NSWorkspace.shared.icon(for: .folder)
            }
        case .fileExtension(let fileExtension):
            image = nsImageForFileExtension(fileExtension)
        case .folder:
            image = NSWorkspace.shared.icon(for: .folder)
        }
        image?.size = NSSize(width: 48, height: 48)
        return image
    }

    private func nsImageForFileExtension(_ fileExtension: String) -> NSImage {
        let normalized = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let contentType = UTType(filenameExtension: normalized) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }
}

struct FinderMenuPreview: View {
    let title: String?
    let caption: String?
    let rootItems: [FinderMenuItem]
    let submenuTitle: String?
    let submenuItems: [FinderMenuItem]
    var isFramed = true

    var body: some View {
        if isFramed {
            DesignPanel {
                previewBody
            }
        } else {
            previewBody
        }
    }

    private var previewBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || caption != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(SettingsTheme.ink)
                    }
                    if let caption {
                        Text(caption)
                            .font(.callout)
                            .foregroundStyle(SettingsTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                FinderMenuBox(items: rootItems)

                if !submenuItems.isEmpty {
                    FinderMenuBox(title: submenuTitle, items: submenuItems)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct FinderMenuBox: View {
    var title: String?
    let items: [FinderMenuItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if item.startsSection && index > 0 {
                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                FinderMenuRow(item: item)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 228)
        .background(SettingsTheme.menuBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SettingsTheme.hairline))
        .shadow(color: SettingsTheme.menuShadow, radius: 18, x: 0, y: 12)
    }
}

struct FinderMenuRow: View {
    let item: FinderMenuItem

    var body: some View {
        HStack(spacing: 9) {
            if let icon = item.icon {
                MenuIconView(
                    icon: icon,
                    tint: item.tint,
                    isHighlighted: item.isHighlighted,
                    size: 17,
                    font: .system(size: 13, weight: .semibold)
                )
            }

            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(item.isHighlighted ? .white : SettingsTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if item.hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.isHighlighted ? .white : SettingsTheme.muted)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(
            item.isHighlighted ? SettingsTheme.accent : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(.horizontal, item.isHighlighted ? 5 : 0)
    }
}

struct EditorSheetHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = SettingsTheme.accent

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(SettingsTheme.headerBackground)
    }
}

struct EditorTextField: View {
    let title: String
    let placeholder: String
    var helper: String? = nil
    var systemImage: String? = nil
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsTheme.ink)

            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.muted)
                        .frame(width: 16)
                }

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))

            if let helper {
                Text(helper)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(2)
            }
        }
    }
}

struct EditorTextArea: View {
    let title: String
    let helper: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                Text(helper)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
            }

            TextEditor(text: $text)
                .font(.body.monospaced())
                .foregroundStyle(SettingsTheme.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 176)
                .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
        }
    }
}

struct EditorSheetFooter: View {
    let validationMessage: String?
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(
                validationMessage ?? "保存后需点击主界面的保存配置才会写入本地配置",
                systemImage: validationMessage == nil ? "info.circle" : "exclamationmark.circle"
            )
            .font(.system(size: 12))
            .foregroundStyle(validationMessage == nil ? SettingsTheme.muted : .orange)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button("取消", role: .cancel) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                onSave()
            } label: {
                Label("保存", systemImage: "checkmark")
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(SettingsTheme.headerBackground)
    }
}

struct TemplateDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var templateID: String
    var title: String
    var defaultFileName: String
    var contents: String

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        templateID = "template-custom-\(suffix)"
        title = "自定义模板"
        defaultFileName = "Untitled.txt"
        contents = ""
    }

    init(template: FileTemplate) {
        originalID = template.id
        templateID = template.id
        title = template.title
        defaultFileName = template.defaultFileName
        contents = template.contents
    }

    func makeTemplate() -> FileTemplate {
        FileTemplate(
            id: templateID.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultFileName: defaultFileName.trimmingCharacters(in: .whitespacesAndNewlines),
            contents: contents
        )
    }
}

struct TemplateEditorSheet: View {
    @State private var draft: TemplateDraft
    let onSave: (TemplateDraft) -> Void
    let onCancel: () -> Void

    init(draft: TemplateDraft, onSave: @escaping (TemplateDraft) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(
                title: draft.originalID == nil ? "新增模板" : "编辑模板",
                subtitle: "配置 Finder 右键菜单中的新建文件入口。",
                systemImage: "doc.badge.plus"
            )

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    EditorTextField(
                        title: "模板 ID",
                        placeholder: "template-custom",
                        helper: "用于关联菜单动作，建议保持英文短横线命名。",
                        systemImage: "number",
                        text: $draft.templateID
                    )

                    EditorTextField(
                        title: "模板名称",
                        placeholder: "Markdown 文件",
                        helper: "显示在设置页和右键菜单中的名称。",
                        systemImage: "textformat",
                        text: $draft.title
                    )
                }

                EditorTextField(
                    title: "默认文件名",
                    placeholder: "Untitled.md",
                    helper: "扩展名会影响菜单图标与新建文件类型。",
                    systemImage: "doc",
                    text: $draft.defaultFileName
                )

                EditorTextArea(
                    title: "文本内容",
                    helper: "支持空内容；保存后作为新建文件的初始内容。",
                    text: $draft.contents
                )
            }
            .padding(22)

            Divider()

            EditorSheetFooter(
                validationMessage: validationMessage,
                canSave: canSave,
                onCancel: onCancel
            ) {
                onSave(draft)
            }
        }
        .background(SettingsTheme.windowBackground)
        .frame(width: 560)
        .frame(minHeight: 520)
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if draft.templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板 ID"
        }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板名称"
        }
        if draft.defaultFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写默认文件名"
        }
        return nil
    }
}

struct CommandTemplateDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var templateID: String
    var title: String
    var command: String
    var workingDirectoryMode: CommandWorkingDirectoryMode
    var timeoutSecondsText: String
    var environmentText: String
    private var existingEnvironment: [CommandEnvironmentVariable]

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        templateID = "command-custom-\(suffix)"
        title = "自定义命令"
        command = "pwd"
        workingDirectoryMode = .currentDirectory
        timeoutSecondsText = "\(RightClickProConstants.defaultCommandTimeoutSeconds)"
        environmentText = ""
        existingEnvironment = []
    }

    init(template: CommandTemplate) {
        originalID = template.id
        templateID = template.id
        title = template.title
        command = template.command
        workingDirectoryMode = template.workingDirectoryMode
        timeoutSecondsText = "\(template.timeoutSeconds)"
        existingEnvironment = template.environment
        environmentText = template.environment
            .map { variable in
                if variable.isSensitive {
                    return "\(variable.name)!="
                }
                return "\(variable.name)=\(variable.value ?? "")"
            }
            .joined(separator: "\n")
    }

    func makeTemplate(secretStore: CommandSecretStoring) throws -> CommandTemplate {
        let trimmedID = templateID.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeout = Int(timeoutSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? RightClickProConstants.defaultCommandTimeoutSeconds
        let environment = try makeEnvironment(templateID: trimmedID, secretStore: secretStore)

        return CommandTemplate(
            id: trimmedID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            workingDirectoryMode: workingDirectoryMode,
            timeoutSeconds: timeout,
            environment: environment
        )
    }

    private func makeEnvironment(templateID: String, secretStore: CommandSecretStoring) throws -> [CommandEnvironmentVariable] {
        var variables: [CommandEnvironmentVariable] = []
        for rawLine in environmentText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawName = String(parts.first ?? "")
            let value = parts.count > 1 ? String(parts[1]) : ""
            let isSensitive = rawName.hasSuffix("!")
            let name = String((isSensitive ? rawName.dropLast() : Substring(rawName))).trimmingCharacters(in: .whitespacesAndNewlines)

            guard CommandTemplateVariableResolver.validateEnvironmentName(name) else {
                throw CommandTemplateError.invalidEnvironmentName(name)
            }

            if isSensitive {
                let existing = existingEnvironment.first { $0.name == name && $0.isSensitive }
                let reference = existing?.secretReference ?? "command-env-\(templateID)-\(name)-\(UUID().uuidString)"
                if !value.isEmpty {
                    try secretStore.save(secret: value, reference: reference)
                } else if existing?.secretReference == nil {
                    throw CommandTemplateError.missingSecret(name)
                }
                variables.append(
                    CommandEnvironmentVariable(
                        id: existing?.id ?? "env-\(name.lowercased())-\(UUID().uuidString.prefix(6))",
                        name: name,
                        value: nil,
                        isSensitive: true,
                        secretReference: reference
                    )
                )
            } else {
                let existing = existingEnvironment.first { $0.name == name && !$0.isSensitive }
                variables.append(
                    CommandEnvironmentVariable(
                        id: existing?.id ?? "env-\(name.lowercased())-\(UUID().uuidString.prefix(6))",
                        name: name,
                        value: value,
                        isSensitive: false
                    )
                )
            }
        }
        return variables
    }
}

struct CommandTemplateEditorSheet: View {
    @State private var draft: CommandTemplateDraft
    let onSave: (CommandTemplateDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: CommandTemplateDraft,
        onSave: @escaping (CommandTemplateDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(
                title: draft.originalID == nil ? "新增命令模板" : "编辑命令模板",
                subtitle: "保存常用开发命令，Finder 右键触发后会打开实时输出窗口。",
                systemImage: "terminal"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        EditorTextField(
                            title: "模板 ID",
                            placeholder: "command-git-status",
                            helper: "用于关联菜单动作，建议保持英文短横线命名。",
                            systemImage: "number",
                            text: $draft.templateID
                        )

                        EditorTextField(
                            title: "显示名称",
                            placeholder: "Git Status",
                            helper: "显示在设置页、右键菜单和实时输出窗口。",
                            systemImage: "textformat",
                            text: $draft.title
                        )
                    }

                    EditorTextArea(
                        title: "命令",
                        helper: "支持 {{currentDirectory}} / {{selectedPath}} / {{selectedPaths}}。",
                        text: $draft.command
                    )

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("工作目录")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SettingsTheme.ink)

                            Picker("工作目录", selection: $draft.workingDirectoryMode) {
                                ForEach(CommandWorkingDirectoryMode.allCasesForSettings, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()

                            Text("命令只会在已授权目录内运行。")
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        EditorTextField(
                            title: "超时秒数",
                            placeholder: "60",
                            helper: "允许 5-600 秒，超时会先终止再强制停止。",
                            systemImage: "timer",
                            text: $draft.timeoutSecondsText
                        )
                    }

                    EditorTextArea(
                        title: "环境变量",
                        helper: "一行一个 KEY=value；敏感值写 KEY!=value，保存后进入 Keychain。",
                        text: $draft.environmentText
                    )
                }
                .padding(22)
            }
            .frame(maxHeight: 620)

            Divider()

            EditorSheetFooter(
                validationMessage: validationMessage,
                canSave: canSave,
                onCancel: onCancel
            ) {
                onSave(draft)
            }
        }
        .background(SettingsTheme.windowBackground)
        .frame(width: 640)
        .frame(minHeight: 680)
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if draft.templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板 ID"
        }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写显示名称"
        }
        if draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写命令"
        }
        guard let timeout = Int(draft.timeoutSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "超时必须是数字"
        }
        if !(RightClickProConstants.minimumCommandTimeoutSeconds...RightClickProConstants.maximumCommandTimeoutSeconds).contains(timeout) {
            return "超时必须在 5-600 秒之间"
        }
        return nil
    }
}

struct DeveloperApplicationSelection {
    var displayName: String
    var bundleIdentifier: String
    var url: URL
}

struct DeveloperEntrypointDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var entrypointID: String
    var title: String
    var bundleIdentifier: String
    var applicationPath: String?
    var targetMode: DeveloperTargetMode

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        entrypointID = "developer-custom-\(suffix)"
        title = ""
        bundleIdentifier = ""
        applicationPath = nil
        targetMode = .dynamic
    }

    init(application: DeveloperApplicationSelection, entrypointID: String) {
        originalID = nil
        self.entrypointID = entrypointID
        title = application.displayName
        bundleIdentifier = application.bundleIdentifier
        applicationPath = application.url.path
        targetMode = .dynamic
    }

    init(entrypoint: DeveloperEntrypoint) {
        originalID = entrypoint.id
        entrypointID = entrypoint.id
        title = entrypoint.title
        bundleIdentifier = entrypoint.bundleIdentifier
        applicationPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entrypoint.bundleIdentifier)?.path
        targetMode = entrypoint.targetMode
    }

    mutating func apply(application: DeveloperApplicationSelection) {
        title = application.displayName
        bundleIdentifier = application.bundleIdentifier
        applicationPath = application.url.path
    }

    func makeEntrypoint() -> DeveloperEntrypoint {
        DeveloperEntrypoint(
            id: entrypointID.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            targetMode: targetMode
        )
    }
}

struct DeveloperEntrypointEditorSheet: View {
    @State private var draft: DeveloperEntrypointDraft
    @State private var didAttemptInitialApplicationSelection = false
    let existingEntrypoints: [DeveloperEntrypoint]
    let onSelectApplication: (DeveloperEntrypointDraft) -> DeveloperEntrypointDraft?
    let onSave: (DeveloperEntrypointDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: DeveloperEntrypointDraft,
        existingEntrypoints: [DeveloperEntrypoint],
        onSelectApplication: @escaping (DeveloperEntrypointDraft) -> DeveloperEntrypointDraft?,
        onSave: @escaping (DeveloperEntrypointDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.existingEntrypoints = existingEntrypoints
        self.onSelectApplication = onSelectApplication
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(
                title: draft.originalID == nil ? "新增开发者入口" : "编辑开发者入口",
                subtitle: "从本地应用生成快捷入口，Finder 右键菜单会优先显示真实应用图标。",
                systemImage: "terminal"
            )

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    EditorTextField(
                        title: "入口 ID",
                        placeholder: "developer-custom",
                        helper: "用于关联动作，保存后会同步到菜单项。",
                        systemImage: "number",
                        text: $draft.entrypointID
                    )

                    EditorTextField(
                        title: "显示名称",
                        placeholder: "Visual Studio Code",
                        helper: "显示在右键菜单和预览列表中。",
                        systemImage: "textformat",
                        text: $draft.title
                    )
                }

                DeveloperApplicationPickerCard(draft: draft) {
                    if let updatedDraft = onSelectApplication(draft) {
                        draft = updatedDraft
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("目标模式")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)

                    Picker("目标模式", selection: $draft.targetMode) {
                        ForEach(DeveloperTargetMode.allCasesForSettings, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    Text(draft.targetMode.helperText)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.muted)
                }
            }
            .padding(22)

            Divider()

            EditorSheetFooter(
                validationMessage: validationMessage,
                canSave: canSave,
                onCancel: onCancel
            ) {
                onSave(draft)
            }
        }
        .background(SettingsTheme.windowBackground)
        .frame(width: 560)
        .frame(minHeight: 430)
        .onAppear {
            requestInitialApplicationSelectionIfNeeded()
        }
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if draft.entrypointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写入口 ID"
        }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写显示名称"
        }
        if draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先选择本地应用"
        }
        if let duplicate = existingEntrypoints.first(where: { entrypoint in
            entrypoint.id != draft.originalID &&
                entrypoint.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
                    draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                ) == .orderedSame
        }) {
            return "这个应用已存在：\(duplicate.title)"
        }
        return nil
    }

    private func requestInitialApplicationSelectionIfNeeded() {
        guard
            !didAttemptInitialApplicationSelection,
            draft.originalID == nil,
            draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        didAttemptInitialApplicationSelection = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let updatedDraft = onSelectApplication(draft) {
                draft = updatedDraft
            }
        }
    }
}

struct DeveloperApplicationPickerCard: View {
    let draft: DeveloperEntrypointDraft
    let onSelectApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地应用")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsTheme.ink)

            HStack(alignment: .center, spacing: 12) {
                MenuIconView(
                    icon: appIcon,
                    tint: SettingsTheme.accent,
                    size: 30,
                    font: .system(size: 18, weight: .semibold)
                )
                .frame(width: 38, height: 38)
                .background(SettingsTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未选择应用" : draft.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)

                    Text(draft.bundleIdentifier.isEmpty ? "请选择一个 .app 应用" : draft.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    if let path = draft.applicationPath, !path.isEmpty {
                        Text(path)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onSelectApplication()
                } label: {
                    Label(draft.bundleIdentifier.isEmpty ? "选择应用" : "更换应用", systemImage: "app.badge")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(12)
            .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))

            Text("Bundle Identifier 会从所选应用自动读取，不需要手动填写。")
                .font(.system(size: 11))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(2)
        }
    }

    private var appIcon: MenuIconDescriptor {
        draft.bundleIdentifier.isEmpty ? .systemSymbol("app") : .appBundleIdentifier(draft.bundleIdentifier)
    }
}

private let operationDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

private extension RightClickProAction {
    var managementTint: Color {
        switch group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile:
            return SettingsTheme.accent
        case .developerEntrypoints:
            return SettingsTheme.accent
        case .commandTemplates:
            return SettingsTheme.accent
        case .fileOperations:
            return .cyan
        case .none:
            return SettingsTheme.muted
        }
    }

    var managementType: String {
        if kind == .createFile || group == .createFile {
            return "新建"
        }

        if group == .developerEntrypoints || group == .commandTemplates || kind == .openInApp || kind == .runCommand {
            return "工具"
        }

        return "操作"
    }

    var managementSubtitle: String {
        switch kind {
        case .openDirectory:
            return "快速访问常用位置"
        case .moveToDirectory:
            return "移动所选项目到指定目录"
        case .copyToDirectory:
            return "复制所选项目到指定目录"
        case .cut:
            return "剪切所选项目到剪贴板"
        case .paste:
            return "粘贴剪贴板中的文件"
        case .createFile:
            return "在当前目录创建 \(payload.templateID ?? "文件")"
        case .openInApp:
            return "快速打开开发者常用工具"
        case .runCommand:
            return "在当前路径执行命令"
        case .undoOperation:
            return "撤销最近一次文件操作"
        }
    }

    var visibilityPills: [String] {
        var labels: [String] = []
        if visibility.contains(.toolbar) {
            labels.append("Finder")
        }
        if visibility.contains(.selection) {
            labels.append("文件/文件夹")
        }
        if visibility.contains(.container) {
            labels.append("桌面空白处")
        }
        return labels.isEmpty ? ["未设置"] : labels
    }
}

private extension ActionKind {
    var displayName: String {
        switch self {
        case .openDirectory:
            return "打开目录"
        case .moveToDirectory:
            return "移动到目录"
        case .copyToDirectory:
            return "复制到目录"
        case .cut:
            return "剪切"
        case .paste:
            return "粘贴"
        case .createFile:
            return "新建文件"
        case .openInApp:
            return "开发者入口"
        case .runCommand:
            return "运行命令"
        case .undoOperation:
            return "撤销操作"
        }
    }

}

private extension CommandWorkingDirectoryMode {
    static var allCasesForSettings: [CommandWorkingDirectoryMode] {
        [.currentDirectory, .selectedItemDirectory]
    }

    var displayName: String {
        switch self {
        case .currentDirectory:
            return "当前 Finder 目录"
        case .selectedItemDirectory:
            return "选中项所在目录"
        }
    }
}

private extension ActionPlacement {
    var displayName: String {
        switch self {
        case .rootMenu:
            return "一级菜单"
        case .submenu:
            return "分组菜单"
        }
    }

    var systemImage: String {
        switch self {
        case .rootMenu:
            return "menubar.rectangle"
        case .submenu:
            return "rectangle.3.group"
        }
    }
}

private extension MenuGroup {
    var displayName: String {
        switch self {
        case .commonDirectories:
            return "前往常用目录"
        case .moveToCommonDirectory:
            return "移动到常用目录"
        case .copyToCommonDirectory:
            return "复制到常用目录"
        case .createFile:
            return "新建文件"
        case .developerEntrypoints:
            return "开发者工具"
        case .commandTemplates:
            return "命令模板"
        case .fileOperations:
            return "文件操作"
        }
    }

    var previewIcon: MenuIconDescriptor {
        switch self {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .folder
        case .createFile:
            return .systemSymbol("doc.badge.plus")
        case .developerEntrypoints:
            return .systemSymbol("chevron.left.forwardslash.chevron.right")
        case .commandTemplates:
            return .systemSymbol("terminal")
        case .fileOperations:
            return .systemSymbol("scissors")
        }
    }

    var previewTint: Color {
        switch self {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile, .developerEntrypoints, .commandTemplates:
            return SettingsTheme.accent
        case .fileOperations:
            return .cyan
        }
    }
}

private extension Set where Element == ActionVisibility {
    var displayName: String {
        sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: " / ")
    }
}

private extension ActionVisibility {
    var displayName: String {
        switch self {
        case .selection:
            return "选中文件"
        case .container:
            return "空白处"
        case .toolbar:
            return "工具栏"
        }
    }

    var systemImage: String {
        switch self {
        case .selection:
            return "checkmark.rectangle"
        case .container:
            return "rectangle.dashed"
        case .toolbar:
            return "sidebar.right"
        }
    }

    var helperText: String {
        switch self {
        case .selection:
            return "选中项目时显示"
        case .container:
            return "右键空白处时显示"
        case .toolbar:
            return "Finder 工具栏菜单中显示"
        }
    }
}

private extension DeveloperTargetMode {
    static var allCasesForSettings: [DeveloperTargetMode] {
        [.dynamic, .currentDirectory, .selectedItem, .selectedItemDirectory]
    }

    var displayName: String {
        switch self {
        case .dynamic:
            return "动态"
        case .currentDirectory:
            return "当前目录"
        case .selectedItem:
            return "选中项目"
        case .selectedItemDirectory:
            return "选中项目所在目录"
        }
    }

    var helperText: String {
        switch self {
        case .dynamic:
            return "选中项目右键时传入选中项；空白处右键时传入当前 Finder 目录。"
        case .currentDirectory:
            return "始终把当前 Finder 目录传给目标应用。"
        case .selectedItem:
            return "优先把第一个选中项目传给目标应用，没有选中项时回退当前目录。"
        case .selectedItemDirectory:
            return "优先把第一个选中项目所在目录传给目标应用，没有选中项时回退当前目录。"
        }
    }
}

private extension OperationKind {
    var displayName: String {
        switch self {
        case .openDirectory:
            return "打开目录"
        case .move:
            return "移动"
        case .copy:
            return "复制"
        case .cut:
            return "剪切"
        case .paste:
            return "粘贴"
        case .createFile:
            return "新建文件"
        case .openInApp:
            return "开发者入口"
        case .runCommand:
            return "运行命令"
        case .unsupported:
            return "未支持"
        }
    }
}

private extension OperationRecordStatus {
    var displayName: String {
        switch self {
        case .success:
            return "成功"
        case .failure:
            return "失败"
        case .cancelled:
            return "取消"
        }
    }

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle"
        case .failure:
            return "xmark.octagon"
        case .cancelled:
            return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .success:
            return .primary
        case .failure:
            return .red
        case .cancelled:
            return .orange
        }
    }
}
