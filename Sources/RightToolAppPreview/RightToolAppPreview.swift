import AppKit
import RightToolCore
import SwiftUI

@main
struct RightToolAppPreview: App {
    @StateObject private var viewModel = SettingsViewModel.bootstrap()

    var body: some Scene {
        MenuBarExtra("RightTool", systemImage: "contextualmenu.and.cursorarrow") {
            MenuBarContentView(viewModel: viewModel)
        }

        Window("RightTool 设置", id: "settings") {
            SettingsRootView(viewModel: viewModel)
                .frame(minWidth: 1180, minHeight: 760)
        }
    }
}

final class SettingsViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case onboarding = "概览"
        case actions = "右键菜单管理"
        case directories = "常用目录快捷直达"
        case developer = "开发者快捷入口"
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
            case .history:
                return "剪贴板助手"
            case .templates:
                return "新建文件模板"
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
                return "控制动作是否启用，以及显示在一级菜单还是 RightTool 子菜单中。"
            case .directories:
                return "管理常用目录，快速访问，提高工作效率。"
            case .developer:
                return "管理开发者常用工具、仓库与目录的快捷入口，支持在 Finder 右键菜单中快速打开。"
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
    @Published var config = RightToolConfig()
    @Published var bookmarks = DirectoryBookmarkCatalog()
    @Published var storagePath = ""
    @Published var statusMessage = ""
    @Published var statusTone: StatusTone = .neutral
    @Published var hasUnsavedChanges = false
    @Published var recentOperations: [OperationRecord] = []
    @Published var developerEntrypointAddRequest = 0
    @Published var templateAddRequest = 0

    private var paths = RightToolStoragePaths.defaultForCurrentProcess()

    static func bootstrap() -> SettingsViewModel {
        let viewModel = SettingsViewModel()
        viewModel.loadOrBootstrap()
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

    /// Section-level count shown as a sidebar badge.
    func sectionBadge(for section: Section) -> String? {
        let count: Int
        switch section {
        case .directories: count = bookmarks.bookmarks.count
        case .actions: count = enabledActionCount
        case .templates: count = config.fileTemplates.count
        case .developer: count = config.developerEntrypoints.count
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
            case .editing: return [.actions, .directories, .developer, .history, .templates]
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
            try JSONFileStore<RightToolConfig>(url: paths.configURL).save(defaultConfig)

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
            try JSONFileStore<RightToolConfig>(url: paths.configURL).save(config)
            hasUnsavedChanges = false
            setStatus("配置已保存，重新打开 Finder 右键菜单后生效", tone: .success)
        } catch {
            setStatus("保存失败：\(error.localizedDescription)", tone: .error)
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

    private func updateAction(_ actionID: String, mutate: (inout RightToolAction) -> Void) {
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

    private func syncTemplateAction(for template: FileTemplate, originalID: String?) {
        if let index = config.actions.firstIndex(where: { action in
            action.kind == .createFile && (action.payload.templateID == template.id || action.payload.templateID == originalID)
        }) {
            config.actions[index].title = "新建\(template.title)"
            config.actions[index].payload.templateID = template.id
            return
        }

        config.actions.append(
            RightToolAction(
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
            RightToolAction(
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
                RightToolAction(
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
            try JSONFileStore<RightToolConfig>(url: paths.configURL).save(config)
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
        case .duplicateID(let id):
            return "ID 重复：\(id)"
        }
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
            openSettings(section: .onboarding)
        }
        Divider()
        Button("退出 RightTool") {
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
                enabledActionCount: viewModel.enabledActionCount,
                rootMenuActionCount: viewModel.rootMenuActionCount,
                maxRootMenuActions: viewModel.config.maxRootMenuActions,
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
                case .history:
                    OperationHistoryView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsTheme.windowBackground)
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

private enum SettingsTheme {
    static let accent = Color(red: 0.24, green: 0.32, blue: 0.98)
    static let accentSoft = Color(red: 0.93, green: 0.92, blue: 1.0)
    static let ink = Color(red: 0.07, green: 0.09, blue: 0.16)
    static let muted = Color(red: 0.36, green: 0.40, blue: 0.52)
    static let hairline = Color.black.opacity(0.08)

    static var windowBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.97, blue: 1.0),
                Color.white
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
}

private enum RightToolIconAsset {
    static let resourceName = "RightToolIcon"
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

struct RightToolBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = RightToolIconAsset.image {
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
    let enabledActionCount: Int
    let rootMenuActionCount: Int
    let maxRootMenuActions: Int
    let onSelect: (SettingsViewModel.Section) -> Void

    private let sections: [SettingsViewModel.Section] = [
        .onboarding,
        .actions,
        .directories,
        .developer,
        .history,
        .templates
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                RightToolBrandIcon(size: 44)
                    .shadow(color: SettingsTheme.accent.opacity(0.18), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text("RightClick Pro")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text("Mac 右键效率工具")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
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

            VStack(alignment: .leading, spacing: 8) {
                Label("\(enabledActionCount) 个动作启用", systemImage: "checkmark.circle")
                Label("\(rootMenuActionCount)/\(maxRootMenuActions) 个一级菜单", systemImage: "menubar.rectangle")
            }
            .font(.caption)
            .foregroundStyle(SettingsTheme.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(.white.opacity(0.58))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsTheme.hairline)
                .frame(width: 1)
        }
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
                    .background(.white.opacity(0.72), in: Capsule())
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
            .background(.white.opacity(0.72))

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
        .layoutPriority((section == .developer || section == .templates) ? 2 : 0)
    }

    private var titleSize: CGFloat {
        switch section {
        case .onboarding, .directories:
            return 22
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
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.white.opacity(0.34))
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
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .background(.white.opacity(0.34))
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
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.white.opacity(0.34))
    }
}

struct DesignPanel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
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
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
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

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        OverviewPageScroll {
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
            .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
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

            Text("所有功能均可在右键菜单中使用，支持拖动排序与自定义设置。")
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
        .padding(.vertical, 6)
        .frame(width: 238)
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 7)
    }
}

struct OverviewContextMenuRow: View {
    let item: FinderMenuItem

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.tint)
                    .frame(width: 17)
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
            FinderMenuItem(title: $0.displayName, systemImage: directoryIcon(for: $0), tint: directoryTint(for: $0), id: $0.id)
        }
    }

    var body: some View {
        let rows = filteredBookmarks

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
                            onToggle: { isEnabled in
                                viewModel.setDirectoryBookmarkEnabled(isEnabled, bookmarkID: bookmark.id)
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

    private func directoryIcon(for bookmark: DirectoryBookmark) -> String {
        let lowercased = bookmark.path.lowercased()
        if lowercased.contains("download") { return "arrow.down.to.line.compact" }
        if lowercased.contains("desktop") { return "display" }
        if lowercased.contains("document") { return "doc.text" }
        if lowercased.contains("picture") { return "photo" }
        if lowercased.contains("server") || lowercased.contains("smb://") { return "server.rack" }
        return "folder"
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
        DesignPanel(padding: 0) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("右键菜单预览")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text("在 Finder 中右键时，启用的目录将出现在右键菜单中，方便快速访问。")
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 220, alignment: .leading)

                Spacer(minLength: 12)

                HStack(alignment: .center, spacing: 22) {
                    FinderMenuBox(items: rootMenuItems)
                    FinderMenuBox(items: items)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        [
            FinderMenuItem(title: "新建文件夹"),
            FinderMenuItem(title: "显示简介"),
            FinderMenuItem(title: "常用目录", tint: SettingsTheme.accent, isHighlighted: true, hasSubmenu: true),
            FinderMenuItem(title: "快速操作", hasSubmenu: true),
            FinderMenuItem(title: "服务", hasSubmenu: true)
        ]
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
        .background(.white.opacity(0.4))
    }
}

struct DirectoryTableRow: View {
    let bookmark: DirectoryBookmark
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "grip.vertical")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SettingsTheme.muted.opacity(0.7))
                .frame(width: 58, alignment: .center)

            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(tint)
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

            HStack(spacing: 16) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑 \(bookmark.displayName)")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除 \(bookmark.displayName)")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(SettingsTheme.muted)
            .frame(width: 104)
        }
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    private var iconName: String {
        let lowercased = bookmark.path.lowercased()
        if lowercased.contains("download") { return "arrow.down.to.line.compact" }
        if lowercased.contains("desktop") { return "display" }
        if lowercased.contains("document") { return "doc.text" }
        if lowercased.contains("picture") { return "photo" }
        if lowercased.contains("server") || lowercased.contains("smb://") { return "server.rack" }
        return "folder"
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

    func matches(_ action: RightToolAction) -> Bool {
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

    func matches(_ visibility: Set<ActionVisibility>) -> Bool {
        switch self {
        case .fileFolder:
            return visibility.contains(.selection)
        case .desktop:
            return visibility.contains(.container)
        case .disk:
            return visibility.contains(.toolbar)
        }
    }
}

struct ActionManagementPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: 1120, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(.white.opacity(0.34))
    }
}

struct ActionListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""
    @State private var selectedFilter: ActionManagementFilter = .all
    @State private var previewContext: ActionPreviewContext = .fileFolder

    private var sortedActions: [RightToolAction] {
        viewModel.config.actions.sorted(by: { $0.order < $1.order })
    }

    private var actionCounts: [ActionManagementFilter: Int] {
        Dictionary(
            uniqueKeysWithValues: ActionManagementFilter.allCases.map { filter in
                (filter, sortedActions.filter { filter.matches($0) }.count)
            }
        )
    }

    private func filteredActions(from actions: [RightToolAction]) -> [RightToolAction] {
        let categoryRows = actions.filter { selectedFilter.matches($0) }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return categoryRows }
        return categoryRows.filter { action in
            action.title.lowercased().contains(keyword)
                || action.kind.displayName.lowercased().contains(keyword)
                || (action.group?.displayName.lowercased().contains(keyword) ?? false)
                || action.visibility.displayName.lowercased().contains(keyword)
        }
    }

    var body: some View {
        let actions = sortedActions
        let rows = filteredActions(from: actions)

        ActionManagementPageScroll {
            PageToolbar {
                SearchField(placeholder: "搜索菜单项或功能...", text: $searchText)
            } trailing: {
                RootMenuCapacityBadge(viewModel: viewModel)
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    ActionManagementTable(
                        rows: rows,
                        allActions: actions,
                        selectedFilter: $selectedFilter,
                        counts: actionCounts,
                        viewModel: viewModel
                    )

                    ActionManagementRuleGrid(viewModel: viewModel)

                    ActionManagementHintBar()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                ActionMenuPreviewCard(
                    selectedContext: $previewContext,
                    actions: actions
                )
                .frame(width: 292)
            }
        }
    }
}

struct ActionManagementTable: View {
    let rows: [RightToolAction]
    let allActions: [RightToolAction]
    @Binding var selectedFilter: ActionManagementFilter
    let counts: [ActionManagementFilter: Int]
    @ObservedObject var viewModel: SettingsViewModel

    private var enabledCount: Int {
        allActions.filter(\.isEnabled).count
    }

    private var disabledCount: Int {
        allActions.filter { !$0.isEnabled }.count
    }

    var body: some View {
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
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, action in
                            ActionEditorRow(action: action, viewModel: viewModel)
                            if index < rows.count - 1 {
                                Divider()
                                    .padding(.leading, 26)
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Label("添加分隔线", systemImage: "plus")
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

struct RootMenuCapacityBadge: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel(padding: 14) {
            HStack(spacing: 14) {
                Image(systemName: "menubar.rectangle")
                    .font(.title3)
                    .foregroundStyle(SettingsTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("一级菜单容量")
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.muted)
                    HStack(spacing: 8) {
                        Text("\(viewModel.rootMenuActionCount)/\(viewModel.config.maxRootMenuActions)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(SettingsTheme.ink)
                        ProgressView(value: viewModel.rootMenuActionProgress)
                            .frame(width: 110)
                            .tint(viewModel.rootMenuActionCount >= viewModel.config.maxRootMenuActions ? .orange : SettingsTheme.accent)
                    }
                }
            }
        }
        .frame(width: 250)
    }
}

struct ActionTableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("").frame(width: 20)
            Text("菜单项").frame(maxWidth: .infinity, alignment: .leading)
            Text("状态").frame(width: 70, alignment: .center)
            Text("适用范围").frame(width: 152, alignment: .leading)
            Text("类型").frame(width: 72, alignment: .leading)
            Text("操作").frame(width: 76, alignment: .center)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(Color.black.opacity(0.015))
    }
}

struct ActionEditorRow: View {
    let action: RightToolAction
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SettingsTheme.muted.opacity(0.58))
                .frame(width: 20)

            HStack(spacing: 12) {
                Image(systemName: action.kind.rowIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(action.isEnabled ? action.managementTint : Color.secondary.opacity(0.5))
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("启用", isOn: Binding(
                get: { action.isEnabled },
                set: { viewModel.setActionEnabled($0, actionID: action.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(width: 70)

            FlowPillGroup(items: action.visibilityPills)
                .frame(width: 152, alignment: .leading)

            ActionTypeBadge(action: action)
                .frame(width: 72, alignment: .leading)

            HStack(spacing: 12) {
                Menu {
                    Button {
                        viewModel.setActionPlacement(.submenu, actionID: action.id)
                    } label: {
                        Label("放入 RightTool 子菜单", systemImage: action.placement == .submenu ? "checkmark" : "rectangle")
                    }

                    Button {
                        viewModel.setActionPlacement(.rootMenu, actionID: action.id)
                    } label: {
                        Label("显示在 Finder 一级菜单", systemImage: action.placement == .rootMenu ? "checkmark" : "menubar.rectangle")
                    }
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
                .accessibilityLabel("调整 \(action.title) 的菜单层级")

                Button {
                    viewModel.setActionEnabled(false, actionID: action.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(!action.isEnabled)
                .accessibilityLabel("禁用 \(action.title)")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(SettingsTheme.muted)
            .frame(width: 76, alignment: .center)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .opacity(action.isEnabled ? 1 : 0.6)
    }
}

struct FlowPillGroup: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.prefix(2), id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsTheme.muted)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .lineLimit(1)
    }
}

struct ActionTypeBadge: View {
    let action: RightToolAction

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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ActionRuleCard(title: "分组与排序规则", subtitle: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    ActionRuleLine(title: "分组方式", value: "按类型分组", systemImage: "chevron.down")
                    ActionRuleLine(title: "排序方式", value: "自定义排序", systemImage: "chevron.down")

                    HStack(spacing: 10) {
                        Text("按分隔线分组显示")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.muted)
                        Spacer()
                        Toggle("", isOn: .constant(true))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .allowsHitTesting(false)
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
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))

                    HStack(spacing: 8) {
                        ActionGhostButton(title: "导入模板", systemImage: "square.and.arrow.down")
                        ActionGhostButton(title: "导出模板", systemImage: "square.and.arrow.up")
                    }
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
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))

                    HStack(spacing: 10) {
                        Text("隐藏系统默认菜单项")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.muted)
                        Spacer()
                        Toggle("", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .allowsHitTesting(false)
                    }
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

struct ActionRuleLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
            Spacer()
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.ink)
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SettingsTheme.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(SettingsTheme.hairline))
        }
    }
}

struct ActionGhostButton: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SettingsTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(.white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(SettingsTheme.hairline))
    }
}

struct ActionManagementHintBar: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)
            Text("提示：拖拽左侧")
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
    let actions: [RightToolAction]

    private var visibleActions: [RightToolAction] {
        actions
            .filter { $0.isEnabled && selectedContext.matches($0.visibility) }
            .prefix(8)
            .map { $0 }
    }

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

                FinderContextMenuMock(actions: visibleActions)
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
                            selectedContext == context ? .white : Color.clear,
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
        .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct FinderContextMenuMock: View {
    let actions: [RightToolAction]

    var body: some View {
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

            if actions.isEmpty {
                FinderContextMenuStaticRow(title: "暂无启用菜单项")
            } else {
                ForEach(actions) { action in
                    FinderContextActionRow(action: action)
                }
            }

            menuDivider
            FinderContextMenuStaticRow(title: "服务", hasSubmenu: true)
        }
        .padding(.vertical, 8)
        .frame(width: 228)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.96), Color(red: 0.95, green: 0.96, blue: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.08)))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 12)
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

struct FinderContextActionRow: View {
    let action: RightToolAction

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: action.kind.rowIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(action.managementTint)
                .frame(width: 16)
            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if action.group != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SettingsTheme.muted)
            }
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
                systemImage: templateSystemIcon(for: template),
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
        .background(.white.opacity(0.44))
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

    private var matchingAction: RightToolAction? {
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

            HStack(spacing: 20) {
                Button(action: onMoveUp) {
                    Image(systemName: "arrow.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveUp)

                Button(action: onMoveDown) {
                    Image(systemName: "arrow.down")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!canMoveDown)
            }
            .foregroundStyle(SettingsTheme.muted)
            .frame(width: 120)

            Menu {
                Button("编辑", action: onEdit)
                Button("删除", role: .destructive) {
                    viewModel.deleteTemplate(template)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
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
        Image(systemName: templateSystemIcon(for: template))
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(templateTint(for: template))
            .frame(width: 28, height: 28)
            .background(templateTint(for: template).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct TemplateMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        DesignPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("右键菜单预览（在 Finder 中右键查看效果）")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)

                HStack(alignment: .center, spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.blue.opacity(0.82))
                            .frame(width: 72, height: 58)
                        Text("示例文件夹")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.muted)
                    }
                    .frame(width: 92)

                    HStack(alignment: .center, spacing: 14) {
                        FinderMenuBox(items: rootMenuItems)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(SettingsTheme.accent)
                        FinderMenuBox(items: items.isEmpty ? [FinderMenuItem(title: "暂无启用模板")] : items)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, minHeight: 222, alignment: .center)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        [
            FinderMenuItem(title: "打开"),
            FinderMenuItem(title: "打开方式", hasSubmenu: true),
            FinderMenuItem(title: "移动到废纸篓"),
            FinderMenuItem(title: "显示简介"),
            FinderMenuItem(title: "重新命名"),
            FinderMenuItem(title: "压缩“示例文件夹”"),
            FinderMenuItem(title: "复制"),
            FinderMenuItem(title: "制作替身"),
            FinderMenuItem(title: "快速查看"),
            FinderMenuItem(title: "新建文件", tint: SettingsTheme.accent, isHighlighted: true, hasSubmenu: true),
            FinderMenuItem(title: "服务", hasSubmenu: true)
        ]
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

private func templateSystemIcon(for template: FileTemplate) -> String {
    switch templateExtensionText(for: template).lowercased() {
    case ".md": return "m.square.fill"
    case ".json": return "curlybraces.square"
    case ".sh": return "terminal.fill"
    case ".swift": return "swift"
    case ".py": return "chevron.left.forwardslash.chevron.right"
    case ".txt": return "doc.text"
    default: return "doc"
    }
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

struct DeveloperEntrypointListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: DeveloperEntrypointDraft?
    @State private var selectedFilter: DeveloperEntrypointFilter = .all

    private var filteredEntrypoints: [DeveloperEntrypoint] {
        viewModel.config.developerEntrypoints.filter { selectedFilter.matches($0) }
    }

    var body: some View {
        let rows = filteredEntrypoints

        DesignPageScroll {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    DesignPanel(padding: 0) {
                        LazyVStack(spacing: 0) {
                            DeveloperFilterTabs(selectedFilter: $selectedFilter)
                            Divider()
                            DeveloperTableHeader()

                            if rows.isEmpty {
                                EmptyStateRow(title: "暂无匹配的开发者入口", systemImage: "terminal")
                            } else {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, entrypoint in
                                    DeveloperTableRow(entrypoint: entrypoint, viewModel: viewModel) {
                                        editingDraft = DeveloperEntrypointDraft(entrypoint: entrypoint)
                                    }
                                    if index < rows.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    DeveloperHintBanner()
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                DeveloperMenuPreviewCard(items: developerPreviewItems)
                    .frame(width: 276)
            }
        }
        .sheet(item: $editingDraft) { draft in
            DeveloperEntrypointEditorSheet(draft: draft) { savedDraft in
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
                systemImage: developerEntryIcon(for: entrypoint),
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
                            selectedFilter == filter ? SettingsTheme.accent : Color.white.opacity(0.72),
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
            Text("名称").frame(width: 144, alignment: .leading)
            Text("目标路径 / 地址").frame(maxWidth: .infinity, alignment: .leading)
            Text("快捷键").frame(width: 64, alignment: .leading)
            Text("启用").frame(width: 60, alignment: .center)
            Text("操作").frame(width: 76, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.black.opacity(0.012))
    }
}

struct DeveloperTableRow: View {
    let entrypoint: DeveloperEntrypoint
    @ObservedObject var viewModel: SettingsViewModel
    let onEdit: () -> Void

    private var matchingAction: RightToolAction? {
        viewModel.config.actions.first {
            $0.kind == .openInApp && $0.payload.developerEntrypointID == entrypoint.id
        }
    }

    var body: some View {
        HStack(spacing: 10) {
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
            .frame(width: 144, alignment: .leading)

            Text(developerEntryTargetPath(for: entrypoint))
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
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(SettingsTheme.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑 \(entrypoint.title)")

                Menu {
                    Button("编辑", action: onEdit)
                    Button("删除", role: .destructive) {
                        viewModel.deleteDeveloperEntrypoint(entrypoint)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(SettingsTheme.hairline))
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
            }
            .foregroundStyle(SettingsTheme.ink)
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
        Image(systemName: developerEntryIcon(for: entrypoint))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(developerEntryTint(for: entrypoint))
            .frame(width: 28, height: 28)
            .background(developerEntryTint(for: entrypoint).opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct DeveloperMenuPreviewCard: View {
    let items: [FinderMenuItem]

    var body: some View {
        DesignPanel(padding: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Text("右键菜单预览")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.muted)
                }

                Text("在 Finder 中右键时，将在「开发者工具」子菜单中显示以下内容：")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .topLeading) {
                    FinderMenuBox(items: rootMenuItems)
                        .offset(x: 0, y: 0)

                    FinderMenuBox(items: submenuItems)
                        .offset(x: 112, y: 82)
                }
                .scaleEffect(0.94, anchor: .topLeading)
                .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        [
            FinderMenuItem(title: "新建文件夹"),
            FinderMenuItem(title: "显示简介"),
            FinderMenuItem(title: "开发者工具", systemImage: "chevron.left.forwardslash.chevron.right", tint: SettingsTheme.accent, isHighlighted: true, hasSubmenu: true),
            FinderMenuItem(title: "快速操作", hasSubmenu: true),
            FinderMenuItem(title: "拷贝"),
            FinderMenuItem(title: "粘贴"),
            FinderMenuItem(title: "显示查看选项"),
            FinderMenuItem(title: "标签..."),
            FinderMenuItem(title: "服务", hasSubmenu: true)
        ]
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

private func developerEntryIcon(for entrypoint: DeveloperEntrypoint) -> String {
    let value = "\(entrypoint.title) \(entrypoint.bundleIdentifier)".lowercased()
    if value.contains("terminal") || value.contains("iterm") || value.contains("warp") { return "terminal.fill" }
    if value.contains("github") || value.contains("gitlab") { return "globe" }
    if value.contains("docker") { return "shippingbox.fill" }
    if value.contains("postman") { return "paperplane.fill" }
    if value.hasPrefix("/") || value.hasPrefix("~") || value.contains("folder") || value.contains("目录") { return "folder.fill" }
    if value.contains("vscode") || value.contains("webstorm") || value.contains("cursor") || value.contains("xcode") || value.contains("code") {
        return "chevron.left.forwardslash.chevron.right"
    }
    return "app.fill"
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

private func developerEntryTargetPath(for entrypoint: DeveloperEntrypoint) -> String {
    let value = "\(entrypoint.title) \(entrypoint.bundleIdentifier)".lowercased()
    if value.contains("visual studio") || value.contains("vscode") { return "/Applications/Visual Studio Code.app" }
    if value.contains("webstorm") { return "/Applications/WebStorm.app" }
    if value.contains("cursor") { return "/Applications/Cursor.app" }
    if value.contains("iterm") { return "/Applications/iTerm.app" }
    if value.contains("terminal") { return "/Applications/Utilities/Terminal.app" }
    if value.contains("github") { return "https://github.com" }
    if value.contains("docker") { return "/Applications/Docker.app" }
    if value.contains("postman") { return "/Applications/Postman.app" }
    return entrypoint.bundleIdentifier
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

    private var fileOperationActions: [RightToolAction] {
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
                    rootItems: [
                        FinderMenuItem(title: "打开"),
                        FinderMenuItem(title: "打开方式", hasSubmenu: true),
                        FinderMenuItem(title: "移动到废纸篓"),
                        FinderMenuItem(title: "文件操作", systemImage: "folder", tint: SettingsTheme.accent, isHighlighted: true, hasSubmenu: true),
                        FinderMenuItem(title: "服务", hasSubmenu: true)
                    ],
                    submenuTitle: nil,
                    submenuItems: previewActions.map {
                        FinderMenuItem(title: $0.title, systemImage: $0.kind.rowIcon, tint: SettingsTheme.accent, id: $0.id)
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
        .background(Color.black.opacity(0.015))
    }
}

struct ClipboardHistoryRow: View {
    let record: OperationRecord

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(record.status.color)
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
}

struct FileOperationQuickAction: View {
    let action: RightToolAction
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel {
            HStack(spacing: 12) {
                Image(systemName: action.kind.rowIcon)
                    .font(.title3)
                    .foregroundStyle(SettingsTheme.accent)
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

struct FinderMenuItem: Identifiable {
    let id: String
    let title: String
    var systemImage: String? = nil
    var tint: Color = SettingsTheme.muted
    var isHighlighted = false
    var hasSubmenu = false

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color = SettingsTheme.muted,
        isHighlighted: Bool = false,
        hasSubmenu: Bool = false,
        id: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isHighlighted = isHighlighted
        self.hasSubmenu = hasSubmenu
        self.id = id ?? "\(title)|\(systemImage ?? "none")|\(isHighlighted)|\(hasSubmenu)"
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

            HStack(alignment: .center, spacing: 12) {
                FinderMenuBox(items: rootItems)

                if !submenuItems.isEmpty {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.accent)
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
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsTheme.muted)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                Divider()
            }

            ForEach(items) { item in
                FinderMenuRow(item: item)
                if item.id != items.last?.id {
                    Divider()
                        .padding(.leading, item.systemImage == nil ? 0 : 32)
                }
            }
        }
        .frame(width: 166)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
        .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
    }
}

struct FinderMenuRow: View {
    let item: FinderMenuItem

    var body: some View {
        HStack(spacing: 9) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isHighlighted ? .white : item.tint)
                    .frame(width: 16)
            }

            Text(item.title)
                .font(.caption)
                .foregroundStyle(item.isHighlighted ? .white : SettingsTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if item.hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.isHighlighted ? .white : SettingsTheme.muted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(
            item.isHighlighted ? SettingsTheme.accent : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(.horizontal, item.isHighlighted ? 5 : 0)
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
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.originalID == nil ? "新增模板" : "编辑模板")
                .font(.title2.bold())

            Form {
                TextField("模板 ID", text: $draft.templateID)
                TextField("模板名称", text: $draft.title)
                TextField("默认文件名", text: $draft.defaultFileName)
                VStack(alignment: .leading, spacing: 8) {
                    Text("文本内容")
                    TextEditor(text: $draft.contents)
                        .font(.body.monospaced())
                        .frame(minHeight: 180)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        )
                }
            }

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                Button("保存") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 430)
    }
}

struct DeveloperEntrypointDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var entrypointID: String
    var title: String
    var bundleIdentifier: String
    var targetMode: DeveloperTargetMode

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        entrypointID = "developer-custom-\(suffix)"
        title = "自定义入口"
        bundleIdentifier = ""
        targetMode = .currentDirectory
    }

    init(entrypoint: DeveloperEntrypoint) {
        originalID = entrypoint.id
        entrypointID = entrypoint.id
        title = entrypoint.title
        bundleIdentifier = entrypoint.bundleIdentifier
        targetMode = entrypoint.targetMode
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
    let onSave: (DeveloperEntrypointDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: DeveloperEntrypointDraft,
        onSave: @escaping (DeveloperEntrypointDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.originalID == nil ? "新增开发者入口" : "编辑开发者入口")
                .font(.title2.bold())

            Form {
                TextField("入口 ID", text: $draft.entrypointID)
                TextField("显示名称", text: $draft.title)
                TextField("Bundle Identifier", text: $draft.bundleIdentifier)
                Picker("目标模式", selection: $draft.targetMode) {
                    ForEach(DeveloperTargetMode.allCasesForSettings, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            HStack {
                Spacer()
                Button("取消") {
                    onCancel()
                }
                Button("保存") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .frame(minHeight: 300)
    }
}

private let operationDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

private extension RightToolAction {
    var managementTint: Color {
        switch group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile:
            return SettingsTheme.accent
        case .developerEntrypoints:
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

        if group == .developerEntrypoints || kind == .openInApp || kind == .runCommand {
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

    var rowIcon: String {
        switch self {
        case .openDirectory:
            return "folder"
        case .moveToDirectory:
            return "tray.and.arrow.up"
        case .copyToDirectory:
            return "tray.and.arrow.down"
        case .cut:
            return "scissors"
        case .paste:
            return "doc.on.clipboard"
        case .createFile:
            return "doc.badge.plus"
        case .openInApp:
            return "terminal"
        case .runCommand:
            return "terminal"
        case .undoOperation:
            return "arrow.uturn.backward"
        }
    }
}

private extension ActionPlacement {
    var displayName: String {
        switch self {
        case .rootMenu:
            return "一级菜单"
        case .submenu:
            return "子菜单"
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
            return "开发者入口"
        case .fileOperations:
            return "文件操作"
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
}

private extension DeveloperTargetMode {
    static var allCasesForSettings: [DeveloperTargetMode] {
        [.currentDirectory, .selectedItem, .selectedItemDirectory]
    }

    var displayName: String {
        switch self {
        case .currentDirectory:
            return "当前目录"
        case .selectedItem:
            return "选中项目"
        case .selectedItemDirectory:
            return "选中项目所在目录"
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
