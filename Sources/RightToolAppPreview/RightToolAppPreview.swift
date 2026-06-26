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
                .frame(minWidth: 940, minHeight: 640)
        }
    }
}

final class SettingsViewModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case onboarding = "首次引导"
        case directories = "生效目录"
        case actions = "菜单动作"
        case templates = "新建文件模板"
        case developer = "开发者入口"
        case history = "最近操作"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .onboarding:
                return "wand.and.stars"
            case .directories:
                return "folder"
            case .actions:
                return "contextualmenu.and.cursorarrow"
            case .templates:
                return "doc.badge.plus"
            case .developer:
                return "terminal"
            case .history:
                return "clock.arrow.circlepath"
            }
        }

        var subtitle: String {
            switch self {
            case .onboarding:
                return "检查当前配置，并在需要时恢复默认预览配置。"
            case .directories:
                return "查看 Finder 右键菜单当前生效的目录范围。"
            case .actions:
                return "控制动作是否启用，以及显示在一级菜单还是 RightTool 子菜单中。"
            case .templates:
                return "维护右键新建文件使用的文本模板。"
            case .developer:
                return "维护从 Finder 上下文打开开发者工具的入口。"
            case .history:
                return "查看 ActionRunner 写入的最近操作记录。"
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

    var body: some View {
        NavigationSplitView {
            List(SettingsViewModel.Section.allCases, selection: $viewModel.selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            SettingsDetailShell(viewModel: viewModel) {
                switch viewModel.selectedSection {
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
        }
    }
}

struct SettingsDetailShell<Content: View>: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedSection.rawValue)
                        .font(.title2.bold())
                    Text(viewModel.selectedSection.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadge(
                    message: viewModel.statusMessage,
                    tone: viewModel.statusTone,
                    isDirty: viewModel.hasUnsavedChanges
                )

                Button {
                    viewModel.saveConfig()
                } label: {
                    Label("保存配置", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!viewModel.hasUnsavedChanges)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.regularMaterial)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isShowingResetConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSummaryGrid(viewModel: viewModel)

                VStack(alignment: .leading, spacing: 12) {
                    OnboardingStep(index: 1, title: "启用 Finder 扩展", detail: "在系统设置中启用 RightTool Finder Extension。")
                    OnboardingStep(index: 2, title: "检查生效目录", detail: "预览版会自动注入桌面、下载、文稿和代码目录中存在的项目。")
                    OnboardingStep(index: 3, title: "编辑动作和模板", detail: "在菜单动作、模板和开发者入口分区调整右键菜单内容。")
                    OnboardingStep(index: 4, title: "保存并试用", detail: "保存配置后重新打开 Finder 右键菜单即可看到变化。")
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Button {
                        isShowingResetConfirmation = true
                    } label: {
                        Label("恢复默认预览配置", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.reloadRecentOperations()
                        viewModel.selectedSection = .history
                    } label: {
                        Label("查看最近操作", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
        .confirmationDialog("恢复默认预览配置？", isPresented: $isShowingResetConfirmation) {
            Button("恢复默认配置", role: .destructive) {
                viewModel.resetToDefaults()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会覆盖当前菜单动作、模板、开发者入口和自动注入目录配置。")
        }
    }
}

struct SettingsSummaryGrid: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            SummaryTile(title: "生效目录", value: "\(viewModel.bookmarks.bookmarks.count)", systemImage: "folder")
            SummaryTile(title: "启用动作", value: "\(viewModel.enabledActionCount)", systemImage: "switch.2")
            SummaryTile(title: "一级菜单", value: "\(viewModel.rootMenuActionCount)/\(viewModel.config.maxRootMenuActions)", systemImage: "menubar.rectangle")
            SummaryTile(title: "模板", value: "\(viewModel.config.fileTemplates.count)", systemImage: "doc.badge.plus")
            SummaryTile(title: "开发入口", value: "\(viewModel.config.developerEntrypoints.count)", systemImage: "terminal")
            SummaryTile(title: "操作记录", value: "\(viewModel.recentOperations.count)", systemImage: "clock")
        }
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct OnboardingStep: View {
    let index: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

struct DirectoryListView: View {
    let bookmarks: [DirectoryBookmark]
    let storagePath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            List {
                Section("当前目录") {
                    ForEach(bookmarks) { bookmark in
                        SettingsRow(
                            systemImage: "folder",
                            title: bookmark.displayName,
                            subtitle: bookmark.path,
                            trailing: bookmark.bookmarkDataBase64 == nil ? "路径模式" : "书签模式"
                        )
                    }
                }

                Section("配置位置") {
                    Text(storagePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct ActionListView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Label("一级菜单容量", systemImage: "menubar.rectangle")
                    Spacer()
                    Text("\(viewModel.rootMenuActionCount)/\(viewModel.config.maxRootMenuActions)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(viewModel.rootMenuActionCount >= viewModel.config.maxRootMenuActions ? .orange : .secondary)
                }
            }

            Section("动作") {
                ForEach(viewModel.config.actions.sorted(by: { $0.order < $1.order })) { action in
                    ActionEditorRow(action: action, viewModel: viewModel)
                }
            }
        }
    }
}

struct ActionEditorRow: View {
    let action: RightToolAction
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.headline)
                    Text("\(action.kind.displayName) · \(action.group?.displayName ?? "未分组") · \(action.visibility.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("启用", isOn: Binding(
                    get: { action.isEnabled },
                    set: { viewModel.setActionEnabled($0, actionID: action.id) }
                ))
                .toggleStyle(.switch)
            }

            Picker("菜单层级", selection: Binding(
                get: { action.placement },
                set: { viewModel.setActionPlacement($0, actionID: action.id) }
            )) {
                Text("RightTool 子菜单").tag(ActionPlacement.submenu)
                Text("Finder 一级菜单").tag(ActionPlacement.rootMenu)
            }
            .pickerStyle(.segmented)
            .disabled(!action.isEnabled)
        }
        .padding(.vertical, 6)
    }
}

struct TemplateListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: TemplateDraft?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("共 \(viewModel.config.fileTemplates.count) 个模板")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editingDraft = TemplateDraft()
                } label: {
                    Label("新增模板", systemImage: "plus")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            List {
                ForEach(viewModel.config.fileTemplates) { template in
                    SettingsRow(
                        systemImage: "doc.text",
                        title: template.title,
                        subtitle: template.defaultFileName,
                        trailing: template.contents.isEmpty ? "空文件" : "\(template.contents.count) 字符"
                    )
                    .contextMenu {
                        Button("编辑") {
                            editingDraft = TemplateDraft(template: template)
                        }
                        Button("删除", role: .destructive) {
                            viewModel.deleteTemplate(template)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            viewModel.deleteTemplate(template)
                        }
                    }
                    .onTapGesture {
                        editingDraft = TemplateDraft(template: template)
                    }
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
}

struct DeveloperEntrypointListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: DeveloperEntrypointDraft?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("共 \(viewModel.config.developerEntrypoints.count) 个入口")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    editingDraft = DeveloperEntrypointDraft()
                } label: {
                    Label("新增入口", systemImage: "plus")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            List {
                ForEach(viewModel.config.developerEntrypoints) { entrypoint in
                    SettingsRow(
                        systemImage: "terminal",
                        title: entrypoint.title,
                        subtitle: entrypoint.bundleIdentifier,
                        trailing: entrypoint.targetMode.displayName
                    )
                    .contextMenu {
                        Button("编辑") {
                            editingDraft = DeveloperEntrypointDraft(entrypoint: entrypoint)
                        }
                        Button("删除", role: .destructive) {
                            viewModel.deleteDeveloperEntrypoint(entrypoint)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            viewModel.deleteDeveloperEntrypoint(entrypoint)
                        }
                    }
                    .onTapGesture {
                        editingDraft = DeveloperEntrypointDraft(entrypoint: entrypoint)
                    }
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
}

struct OperationHistoryView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("最近 \(viewModel.recentOperations.count) 条")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    viewModel.reloadRecentOperations()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if viewModel.recentOperations.isEmpty {
                ContentUnavailableView("暂无操作记录", systemImage: "clock", description: Text("执行右键动作后会在这里出现记录。"))
            } else {
                List(viewModel.recentOperations) { record in
                    SettingsRow(
                        systemImage: record.status.systemImage,
                        title: record.message ?? record.kind.displayName,
                        subtitle: "\(record.kind.displayName) · \(operationDateFormatter.string(from: record.createdAt))",
                        trailing: record.status.displayName
                    )
                    .foregroundStyle(record.status.color)
                }
            }
        }
    }
}

struct SettingsRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let trailing: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 16)

            Text(trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 5)
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
