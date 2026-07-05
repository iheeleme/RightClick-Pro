import AppKit
import RightClickProCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private enum FinderExtensionSetupDefaults {
    static let completedSignatureKey = "RightClickPro.completedFinderExtensionSetupSignature"
}

private enum MaintenanceResponse: Sendable {
    case success(SystemMaintenanceResult)
    case failure(String)

    init(_ response: Result<SystemMaintenanceResult, Error>) {
        switch response {
        case .success(let result):
            self = .success(result)
        case .failure(let error):
            self = .failure(error.localizedDescription)
        }
    }
}

private struct GitHubLatestRelease: Equatable, Sendable {
    var tagName: String
    var htmlURL: URL
    var publishedAt: Date?
}

private enum GitHubReleaseCheckResponse: Sendable {
    case success(GitHubLatestRelease)
    case noPublicRelease
    case failure(String)
}

private enum GitHubReleaseClient {
    static func fetchLatestRelease(from url: URL) async -> GitHubReleaseCheckResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("GitHub 返回了无法识别的响应")
            }

            switch httpResponse.statusCode {
            case 200:
                return decodeLatestRelease(data)
            case 404:
                return .noPublicRelease
            case 403:
                return .failure("GitHub 暂时拒绝了请求，可能触发了匿名访问频率限制")
            default:
                return .failure("GitHub 请求失败：HTTP \(httpResponse.statusCode)")
            }
        } catch {
            return .failure("无法连接 GitHub：\(error.localizedDescription)")
        }
    }

    private static func decodeLatestRelease(_ data: Data) -> GitHubReleaseCheckResponse {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(GitHubLatestReleasePayload.self, from: data)
            return .success(
                GitHubLatestRelease(
                    tagName: payload.tagName,
                    htmlURL: payload.htmlURL,
                    publishedAt: payload.publishedAt
                )
            )
        } catch {
            return .failure("GitHub 最新版本信息格式无法解析")
        }
    }
}

private struct GitHubLatestReleasePayload: Decodable {
    var tagName: String
    var htmlURL: URL
    var publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}


@MainActor
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

    enum FullDiskAccessStatus: Equatable {
        case unchecked
        case checking
        case granted
        case missing
        case unavailable(String)
    }

    enum LaunchAtLoginStatus: Equatable {
        case unchecked
        case disabled
        case enabled
        case requiresApproval
        case unavailable(String)
    }

    enum UpdateCheckStatus: Equatable {
        case unchecked
        case checking
        case upToDate(currentVersion: String, latestTag: String)
        case updateAvailable(currentVersion: String, latestTag: String, releaseURL: URL, publishedAt: Date?)
        case unavailable(String)
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
    @Published private(set) var fullDiskAccessStatus: FullDiskAccessStatus = .unchecked
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .unchecked
    @Published private(set) var updateCheckStatus: UpdateCheckStatus = .unchecked

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
            selector: #selector(handleApplicationDidBecomeActive),
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
        viewModel.refreshLaunchAtLoginStatus()
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

    var shouldShowFullDiskAccessBanner: Bool {
        fullDiskAccessStatus != .granted
    }

    var isCheckingFullDiskAccess: Bool {
        fullDiskAccessStatus == .checking
    }

    var fullDiskAccessStatusMessage: String {
        switch fullDiskAccessStatus {
        case .unchecked:
            return "macOS 不提供无弹窗授权检测；RightClick Pro 不会读取邮件、信息、Safari 或 TCC 数据来判断权限。"
        case .checking:
            return "正在通过 ActionRunner 检查完全磁盘访问权限..."
        case .granted:
            return "检测结果：已授予完全磁盘访问权限"
        case .missing:
            return "检测结果：可能尚未授予 ActionRunner 完全磁盘访问权限"
        case .unavailable(let message):
            return "无法通过 ActionRunner 检查权限：\(message)"
        }
    }

    var fullDiskAccessStatusTone: StatusTone {
        switch fullDiskAccessStatus {
        case .unchecked, .checking:
            return .neutral
        case .granted:
            return .success
        case .missing:
            return .warning
        case .unavailable:
            return .error
        }
    }

    var launchAtLoginToggleIsOn: Bool {
        switch launchAtLoginStatus {
        case .enabled, .requiresApproval:
            return true
        case .unchecked, .disabled, .unavailable:
            return false
        }
    }

    var launchAtLoginStatusMessage: String {
        switch launchAtLoginStatus {
        case .unchecked:
            return "尚未检查登录项状态"
        case .disabled:
            return "当前不会在登录时自动启动"
        case .enabled:
            return "已加入 macOS 登录项"
        case .requiresApproval:
            return "已提交登录项请求，需要在系统设置中允许"
        case .unavailable(let message):
            return "无法读取或更新登录项：\(message)"
        }
    }

    var launchAtLoginStatusTone: StatusTone {
        switch launchAtLoginStatus {
        case .unchecked:
            return .neutral
        case .disabled:
            return .neutral
        case .enabled:
            return .success
        case .requiresApproval:
            return .warning
        case .unavailable:
            return .error
        }
    }

    var isCheckingForUpdates: Bool {
        updateCheckStatus == .checking
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

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            setStatus("无法打开完全磁盘访问权限设置，请手动前往系统设置 > 隐私与安全性 > 完全磁盘访问权限", tone: .error)
            return
        }

        if NSWorkspace.shared.open(url) {
            setStatus("已打开完全磁盘访问权限设置，请允许 \(AppMetadata.displayName)。授权后若文件动作仍被拦截，会显示具体错误。", tone: .neutral)
        } else {
            setStatus("无法打开系统设置，请手动前往隐私与安全性 > 完全磁盘访问权限", tone: .warning)
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = mappedLaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()

            let tone: StatusTone = launchAtLoginStatus == .requiresApproval ? .warning : .success
            setStatus(
                isEnabled ? "已请求登录时自动启动 \(AppMetadata.displayName)" : "已关闭登录时自动启动",
                tone: tone
            )
        } catch {
            refreshLaunchAtLoginStatus()
            setStatus("更新登录项失败：\(error.localizedDescription)", tone: .error)
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            setStatus("无法打开登录项设置，请手动前往系统设置 > 通用 > 登录项", tone: .error)
            return
        }

        if NSWorkspace.shared.open(url) {
            setStatus("已打开登录项设置，请确认 \(AppMetadata.displayName) 是否允许后台运行", tone: .neutral)
        } else {
            setStatus("无法打开登录项设置，请手动前往系统设置 > 通用 > 登录项", tone: .warning)
        }
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates else {
            return
        }

        let currentVersion = AppMetadata.currentVersion
        updateCheckStatus = .checking
        setStatus("正在检查 GitHub 最新正式版本...", tone: .neutral)

        Task { [weak self, currentVersion] in
            let response = await GitHubReleaseClient.fetchLatestRelease(from: AppMetadata.latestReleaseAPIURL)
            await MainActor.run { [weak self, response, currentVersion] in
                self?.handleUpdateCheckResponse(response, currentVersion: currentVersion)
            }
        }
    }

    func openUpdateReleasePage() {
        let url: URL
        switch updateCheckStatus {
        case .updateAvailable(_, _, let releaseURL, _):
            url = releaseURL
        case .unchecked, .checking, .upToDate, .unavailable:
            url = AppMetadata.releasesPageURL
        }

        if NSWorkspace.shared.open(url) {
            setStatus("已打开 GitHub Releases 页面", tone: .neutral)
        } else {
            setStatus("无法打开 GitHub Releases 页面", tone: .warning)
        }
    }

    func checkFullDiskAccess(userInitiated: Bool = true) {
        guard userInitiated else {
            return
        }

        guard !isCheckingFullDiskAccess else {
            return
        }

        let previousStatus = fullDiskAccessStatus
        if previousStatus != .granted || userInitiated {
            fullDiskAccessStatus = .checking
        }
        if userInitiated {
            setStatus("正在检查完全磁盘访问权限...", tone: .neutral)
        }

        let request = SystemMaintenanceRequest(task: .checkFullDiskAccess)
        actionRunnerClient.performMaintenance(request) { [weak self] response in
            guard let viewModel = self else {
                return
            }
            let maintenanceResponse = MaintenanceResponse(response)
            DispatchQueue.main.async { [weak viewModel, maintenanceResponse] in
                viewModel?.handleFullDiskAccessResponse(
                    maintenanceResponse,
                    previousStatus: previousStatus,
                    userInitiated: userInitiated
                )
            }
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
            guard let viewModel = self else {
                return
            }
            let maintenanceResponse = MaintenanceResponse(response)
            DispatchQueue.main.async { [weak viewModel, maintenanceResponse] in
                viewModel?.isRepairingFinderMenu = false
                viewModel?.handleFinderMaintenanceResponse(
                    maintenanceResponse,
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

    @objc private func handleApplicationDidBecomeActive() {
        handlePendingCommandRunNotification()
        refreshLaunchAtLoginStatus()
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
        config.shortcutDirectoryIDs.removeAll { $0 == bookmarkID }
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
        let isReferenced = config.shortcutDirectoryIDs.contains(bookmarkID)
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
            appendUnique(bookmarkID, to: &config.shortcutDirectoryIDs)
            syncDirectoryActions(for: bookmark)
        } else {
            config.shortcutDirectoryIDs.removeAll { $0 == bookmarkID }
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
        _ response: MaintenanceResponse,
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
        case .failure(let errorMessage):
            let message = "ActionRunner XPC 服务不可用：\(errorMessage)"
            markFinderExtensionNeedsAttention(message)
            if userInitiated {
                setStatus("修复右键菜单失败：\(message)", tone: .error)
            }
        }
    }

    private func handleFullDiskAccessResponse(
        _ response: MaintenanceResponse,
        previousStatus: FullDiskAccessStatus,
        userInitiated: Bool
    ) {
        switch response {
        case .success(let result):
            guard let hasFullDiskAccess = result.hasFullDiskAccess else {
                fullDiskAccessStatus = .unavailable("ActionRunner 未返回权限检测结果")
                if userInitiated {
                    setStatus(fullDiskAccessStatusMessage, tone: .error)
                }
                return
            }

            fullDiskAccessStatus = hasFullDiskAccess ? .granted : .missing
            if userInitiated {
                let tone: StatusTone = hasFullDiskAccess ? .success : .warning
                let suffix = hasFullDiskAccess ? "" : "。文件动作仍会尝试执行，并在失败时提示。"
                setStatus("\(fullDiskAccessStatusMessage)\(suffix)", tone: tone)
            }
        case .failure(let errorMessage):
            if previousStatus == .granted && !userInitiated {
                fullDiskAccessStatus = previousStatus
                return
            }

            fullDiskAccessStatus = .unavailable(errorMessage)
            if userInitiated {
                setStatus(fullDiskAccessStatusMessage, tone: .error)
            }
        }
    }

    private func handleUpdateCheckResponse(_ response: GitHubReleaseCheckResponse, currentVersion: String) {
        switch response {
        case .success(let release):
            switch ReleaseVersionComparator.compare(currentVersion: currentVersion, latestTag: release.tagName) {
            case .updateAvailable:
                updateCheckStatus = .updateAvailable(
                    currentVersion: currentVersion,
                    latestTag: release.tagName,
                    releaseURL: release.htmlURL,
                    publishedAt: release.publishedAt
                )
                setStatus("发现新版本：\(release.tagName)", tone: .success)
            case .upToDate:
                updateCheckStatus = .upToDate(currentVersion: currentVersion, latestTag: release.tagName)
                setStatus("当前已是最新正式版本", tone: .success)
            case .unknown:
                let message = "已获取 GitHub 最新版本 \(release.tagName)，但无法与当前版本 \(currentVersion) 比较"
                updateCheckStatus = .unavailable(message)
                setStatus(message, tone: .warning)
            }
        case .noPublicRelease:
            let message = "GitHub 暂无公开正式版本"
            updateCheckStatus = .unavailable(message)
            setStatus(message, tone: .warning)
        case .failure(let message):
            updateCheckStatus = .unavailable(message)
            setStatus(message, tone: .error)
        }
    }

    private func mappedLaunchAtLoginStatus(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable("系统找不到当前 App 的登录项服务")
        @unknown default:
            return .unavailable("未知登录项状态")
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
            appendUnique(bookmarkID, to: &config.shortcutDirectoryIDs)
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
        appendUnique(bookmark.id, to: &config.shortcutDirectoryIDs)
        syncDirectoryActions(for: bookmark)
        saveDirectoryChanges("已添加目录：\(displayName)")
    }

    private func syncDirectoryActions(for bookmark: DirectoryBookmark) {
        let specs: [(kind: ActionKind, idPrefix: String, titlePrefix: String, visibility: Set<ActionVisibility>, group: MenuGroup)] = [
            (.openDirectory, "open-directory", "前往", [.container, .toolbar], .commonDirectories),
            (.moveToDirectory, "move-to", "移动到", [.selection], .moveToCommonDirectory),
            (.copyToDirectory, "copy-to", "复制到", [.selection], .copyToCommonDirectory)
        ]
        let isEnabled = config.shortcutDirectoryIDs.contains(bookmark.id)
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
        config.shortcutDirectoryIDs = orderedIDs.filter { config.shortcutDirectoryIDs.contains($0) }
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
