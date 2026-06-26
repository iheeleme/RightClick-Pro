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
                return "常用目录"
            case .developer:
                return "开发者入口"
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
                return "管理开发者常用工具、仓库与目录的快捷入口。"
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
                    DirectoryListView(bookmarks: viewModel.bookmarks.bookmarks, storagePath: viewModel.storagePath)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SettingsTheme.brandGradient)
                    Image(systemName: "cursorarrow")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-18))
                }
                .frame(width: 44, height: 44)
                .shadow(color: SettingsTheme.accent.opacity(0.25), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text("右键菜单管理")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(SettingsTheme.ink)
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
            .padding(.top, section == .onboarding ? 22 : 28)
            .padding(.bottom, section == .onboarding ? 8 : 16)
            .background(.white.opacity(0.72))

            if section != .onboarding {
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
                .font(.system(size: section == .onboarding ? 22 : 28, weight: .bold))
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
            StatusBadge(
                message: viewModel.statusMessage,
                tone: viewModel.statusTone,
                isDirty: viewModel.hasUnsavedChanges
            )

            SaveConfigButton(viewModel: viewModel)
        }
        .frame(alignment: .trailing)
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
    let bookmarks: [DirectoryBookmark]
    let storagePath: String
    @State private var searchText = ""

    private var filteredBookmarks: [DirectoryBookmark] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.displayName.lowercased().contains(keyword) || $0.path.lowercased().contains(keyword)
        }
    }

    private var previewItems: [FinderMenuItem] {
        Array(bookmarks.prefix(7)).map {
            FinderMenuItem(title: $0.displayName, systemImage: directoryIcon(for: $0), tint: directoryTint(for: $0), id: $0.id)
        }
    }

    var body: some View {
        let rows = filteredBookmarks

        DesignPageScroll {
            PageToolbar {
                SearchField(placeholder: "搜索目录名称或路径", text: $searchText)
            } trailing: {
                Text("共 \(bookmarks.count) 个目录")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
            }

            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    DirectoryTableHeader()
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, bookmark in
                        DirectoryTableRow(bookmark: bookmark)
                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                    if rows.isEmpty {
                        EmptyStateRow(title: "没有匹配的目录", systemImage: "folder.badge.questionmark")
                    }
                }
            }

            PreviewSection(
                rootItems: [
                    FinderMenuItem(title: "新建文件夹"),
                    FinderMenuItem(title: "显示简介"),
                    FinderMenuItem(title: "常用目录", systemImage: "folder", tint: SettingsTheme.accent, isHighlighted: true, hasSubmenu: true),
                    FinderMenuItem(title: "快速操作", hasSubmenu: true),
                    FinderMenuItem(title: "服务", hasSubmenu: true)
                ],
                submenuItems: previewItems
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("右键菜单预览")
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text("启用的目录会出现在常用目录子菜单中，方便快速访问。")
                        .font(.callout)
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HintBanner(text: "配置目录：\(storagePath)")
                .textSelection(.enabled)
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

struct DirectoryTableHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("排序").frame(width: 46, alignment: .leading)
            Text("名称").frame(width: 230, alignment: .leading)
            Text("路径").frame(maxWidth: .infinity, alignment: .leading)
            Text("启用").frame(width: 72, alignment: .center)
            Text("操作").frame(width: 86, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color.black.opacity(0.015))
    }
}

struct DirectoryTableRow: View {
    let bookmark: DirectoryBookmark

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "grip.vertical")
                .foregroundStyle(SettingsTheme.muted.opacity(0.55))
                .frame(width: 46, alignment: .leading)

            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(bookmark.displayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
            }
            .frame(width: 230, alignment: .leading)

            Text(bookmark.path)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: .constant(true))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(true)
                .frame(width: 72)

            HStack(spacing: 16) {
                Image(systemName: "pencil")
                Image(systemName: "trash")
            }
            .font(.callout)
            .foregroundStyle(SettingsTheme.muted)
            .frame(width: 86)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
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
}

struct ActionListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""

    private var sortedActions: [RightToolAction] {
        viewModel.config.actions.sorted(by: { $0.order < $1.order })
    }

    private func filteredActions(from actions: [RightToolAction]) -> [RightToolAction] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return actions }
        return actions.filter { action in
            action.title.lowercased().contains(keyword)
                || action.kind.displayName.lowercased().contains(keyword)
                || (action.group?.displayName.lowercased().contains(keyword) ?? false)
        }
    }

    var body: some View {
        let actions = sortedActions
        let rows = filteredActions(from: actions)

        DesignPageScroll {
            PageToolbar {
                SearchField(placeholder: "筛选动作名称、类型或分组", text: $searchText)
            } trailing: {
                RootMenuCapacityBadge(viewModel: viewModel)
            }

            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    ActionTableHeader()
                    if rows.isEmpty {
                        EmptyStateRow(title: actions.isEmpty ? "暂无动作" : "没有匹配的动作", systemImage: "contextualmenu.and.cursorarrow")
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, action in
                            ActionEditorRow(action: action, viewModel: viewModel)
                            if index < rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            PreviewSection(
                    rootItems: previewRootItems(from: actions),
                    submenuTitle: "RightTool",
                    submenuItems: previewSubmenuItems(from: actions)
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("右键菜单预览")
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text("一级菜单动作会直接出现在 Finder 右键菜单中，其他动作收纳到 RightTool 子菜单。")
                        .font(.callout)
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("一级菜单最多 \(viewModel.config.maxRootMenuActions) 个动作。")
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.accent)
                }
            }
        }
    }

    private func previewRootItems(from actions: [RightToolAction]) -> [FinderMenuItem] {
        let defaultItems = [
            FinderMenuItem(title: "新建文件夹"),
            FinderMenuItem(title: "显示简介"),
            FinderMenuItem(title: "排序方式", hasSubmenu: true)
        ]
        let rootActions = actions
            .filter { $0.isEnabled && $0.placement == .rootMenu }
            .map { FinderMenuItem(title: $0.title, systemImage: $0.kind.rowIcon, tint: tint(for: $0), id: $0.id) }
        return defaultItems + rootActions + [FinderMenuItem(title: "服务", hasSubmenu: true)]
    }

    private func previewSubmenuItems(from actions: [RightToolAction]) -> [FinderMenuItem] {
        actions
            .filter { $0.isEnabled && $0.placement == .submenu }
            .prefix(8)
            .map { FinderMenuItem(title: $0.title, systemImage: $0.kind.rowIcon, tint: tint(for: $0), hasSubmenu: $0.group != nil, id: $0.id) }
    }

    private func tint(for action: RightToolAction) -> Color {
        switch action.group {
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
        HStack(spacing: 16) {
            Text("动作").frame(width: 260, alignment: .leading)
            Text("分组").frame(width: 150, alignment: .leading)
            Text("可见范围").frame(maxWidth: .infinity, alignment: .leading)
            Text("启用").frame(width: 64, alignment: .center)
            Text("菜单层级").frame(width: 220, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color.black.opacity(0.015))
    }
}

struct ActionEditorRow: View {
    let action: RightToolAction
    @ObservedObject var viewModel: SettingsViewModel

    private var groupTint: Color {
        switch action.group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile:
            return .pink
        case .developerEntrypoints:
            return .purple
        case .fileOperations:
            return .teal
        case .none:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: action.kind.rowIcon)
                    .font(.title3)
                    .foregroundStyle(action.isEnabled ? groupTint : Color.secondary.opacity(0.5))
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(action.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    Text(action.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.muted)
                }
            }
            .frame(width: 260, alignment: .leading)

            labelPill(action.group?.displayName ?? "未分组", systemImage: "tag", tint: groupTint)
                .frame(width: 150, alignment: .leading)

            Text(action.visibility.displayName)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("启用", isOn: Binding(
                get: { action.isEnabled },
                set: { viewModel.setActionEnabled($0, actionID: action.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(width: 64)

            Picker("菜单层级", selection: Binding(
                get: { action.placement },
                set: { viewModel.setActionPlacement($0, actionID: action.id) }
            )) {
                Text("RightTool 子菜单").tag(ActionPlacement.submenu)
                Text("Finder 一级菜单").tag(ActionPlacement.rootMenu)
            }
            .pickerStyle(.segmented)
            .disabled(!action.isEnabled)
            .frame(width: 220)
        }
        .padding(.horizontal, 18)
        .frame(height: 66)
        .opacity(action.isEnabled ? 1 : 0.6)
    }

    private func labelPill(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct TemplateListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: TemplateDraft?

    var body: some View {
        let templates = viewModel.config.fileTemplates

        DesignPageScroll {
            PageToolbar {
                Text("共 \(templates.count) 个模板")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
            } trailing: {
                Button {
                    editingDraft = TemplateDraft()
                } label: {
                    Label("添加模板", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    TemplateTableHeader()
                    if templates.isEmpty {
                        EmptyStateRow(title: "暂无模板", systemImage: "doc.badge.plus")
                    } else {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            TemplateTableRow(template: template, viewModel: viewModel) {
                                editingDraft = TemplateDraft(template: template)
                            }
                            if index < templates.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            PreviewSection(
                    rootItems: [
                        FinderMenuItem(title: "打开"),
                        FinderMenuItem(title: "打开方式", hasSubmenu: true),
                        FinderMenuItem(title: "快速查看"),
                        FinderMenuItem(title: "新建文件", systemImage: "doc", tint: SettingsTheme.accent, isHighlighted: true, hasSubmenu: true),
                        FinderMenuItem(title: "服务", hasSubmenu: true)
                    ],
                    submenuTitle: nil,
                    submenuItems: templatePreviewItems
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("右键菜单预览")
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text("在 Finder 中右键查看新建文件子菜单效果。")
                        .font(.callout)
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("右键菜单会按当前模板顺序显示。")
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.accent)
                }
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
    }

    private var templatePreviewItems: [FinderMenuItem] {
        viewModel.config.fileTemplates.prefix(8).map {
            FinderMenuItem(title: $0.title, systemImage: templateIcon(for: $0), tint: SettingsTheme.accent, id: $0.id)
        }
    }

    private func templateIcon(for template: FileTemplate) -> String {
        let ext = URL(fileURLWithPath: template.defaultFileName).pathExtension.lowercased()
        switch ext {
        case "md": return "doc.richtext"
        case "json": return "curlybraces"
        case "sh": return "terminal"
        case "swift": return "swift"
        case "txt": return "doc.text"
        default: return "doc"
        }
    }
}

struct TemplateTableHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("模板名称").frame(maxWidth: .infinity, alignment: .leading)
            Text("扩展名").frame(width: 120, alignment: .leading)
            Text("启用").frame(width: 72, alignment: .center)
            Text("排序").frame(width: 120, alignment: .center)
            Text("操作").frame(width: 72, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color.black.opacity(0.015))
    }
}

struct TemplateTableRow: View {
    let template: FileTemplate
    @ObservedObject var viewModel: SettingsViewModel
    let onEdit: () -> Void

    private var matchingAction: RightToolAction? {
        viewModel.config.actions.first {
            $0.kind == .createFile && $0.payload.templateID == template.id
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(SettingsTheme.ink)
                        Text(template.defaultFileName)
                            .font(.caption)
                            .foregroundStyle(SettingsTheme.muted)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(extensionText)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 120, alignment: .leading)

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
            .frame(width: 72)

            HStack(spacing: 20) {
                Image(systemName: "arrow.up")
                Image(systemName: "arrow.down")
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
        .frame(height: 58)
    }

    private var extensionText: String {
        let ext = URL(fileURLWithPath: template.defaultFileName).pathExtension
        return ext.isEmpty ? "—" : ".\(ext)"
    }

    private var iconName: String {
        switch extensionText.lowercased() {
        case ".md": return "doc.richtext"
        case ".json": return "curlybraces"
        case ".sh": return "terminal"
        case ".swift": return "swift"
        case ".txt": return "doc.text"
        default: return "doc"
        }
    }
}

struct DeveloperEntrypointListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: DeveloperEntrypointDraft?
    @State private var selectedFilter: DeveloperEntrypointFilter = .all

    private var filteredEntrypoints: [DeveloperEntrypoint] {
        switch selectedFilter {
        case .all:
            return viewModel.config.developerEntrypoints
        case .currentDirectory:
            return viewModel.config.developerEntrypoints.filter { $0.targetMode == .currentDirectory }
        case .selectedItem:
            return viewModel.config.developerEntrypoints.filter { $0.targetMode != .currentDirectory }
        }
    }

    var body: some View {
        let rows = filteredEntrypoints

        DesignPageScroll {
            PageToolbar {
                Picker("入口筛选", selection: $selectedFilter) {
                    ForEach(DeveloperEntrypointFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 240, maxWidth: 360)
            } trailing: {
                Button {
                    editingDraft = DeveloperEntrypointDraft()
                } label: {
                    Label("添加快捷入口", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    DeveloperTableHeader()
                    if rows.isEmpty {
                        EmptyStateRow(title: "暂无开发者入口", systemImage: "terminal")
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

            PreviewSection(
                    rootItems: [
                        FinderMenuItem(title: "新建文件夹"),
                        FinderMenuItem(title: "显示简介"),
                        FinderMenuItem(title: "开发者工具", systemImage: "chevron.left.forwardslash.chevron.right", tint: SettingsTheme.accent, isHighlighted: true, hasSubmenu: true),
                        FinderMenuItem(title: "快速操作", hasSubmenu: true),
                        FinderMenuItem(title: "拷贝")
                    ],
                    submenuTitle: nil,
                    submenuItems: developerPreviewItems
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("右键菜单预览")
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text("在 Finder 中右键任意位置，选择「开发者工具」即可看到这些入口。")
                        .font(.callout)
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    }

    private var developerPreviewItems: [FinderMenuItem] {
        viewModel.config.developerEntrypoints.prefix(10).map {
            FinderMenuItem(title: $0.title, systemImage: developerIcon(for: $0), tint: SettingsTheme.accent, id: $0.id)
        }
    }

    private func developerIcon(for entrypoint: DeveloperEntrypoint) -> String {
        let id = entrypoint.bundleIdentifier.lowercased()
        if id.contains("terminal") || id.contains("iterm") { return "terminal" }
        if id.contains("github") { return "globe" }
        if id.contains("docker") { return "shippingbox" }
        return "app"
    }
}

enum DeveloperEntrypointFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case currentDirectory = "当前目录"
    case selectedItem = "选中项目"

    var id: String { rawValue }
}

struct DeveloperTableHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("名称").frame(width: 210, alignment: .leading)
            Text("Bundle Identifier").frame(maxWidth: .infinity, alignment: .leading)
            Text("目标").frame(width: 120, alignment: .leading)
            Text("启用").frame(width: 72, alignment: .center)
            Text("操作").frame(width: 72, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Color.black.opacity(0.015))
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
        HStack(spacing: 16) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: 28)
                    Text(entrypoint.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 210, alignment: .leading)

            Text(entrypoint.bundleIdentifier)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(entrypoint.targetMode.displayName)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 120, alignment: .leading)

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
            .frame(width: 72)

            Menu {
                Button("编辑", action: onEdit)
                Button("删除", role: .destructive) {
                    viewModel.deleteDeveloperEntrypoint(entrypoint)
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
        .frame(height: 58)
    }

    private var iconName: String {
        let id = entrypoint.bundleIdentifier.lowercased()
        if id.contains("terminal") || id.contains("iterm") { return "terminal" }
        if id.contains("github") { return "globe" }
        if id.contains("docker") { return "shippingbox" }
        return "app"
    }
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
