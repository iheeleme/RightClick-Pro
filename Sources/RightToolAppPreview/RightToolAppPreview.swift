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
                .frame(minWidth: 760, minHeight: 520)
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
    }

    @Published var selectedSection: Section = .onboarding
    @Published var config = RightToolConfig()
    @Published var bookmarks = DirectoryBookmarkCatalog()
    @Published var storagePath = ""
    @Published var bootstrapMessage = ""

    static func bootstrap() -> SettingsViewModel {
        let viewModel = SettingsViewModel()
        viewModel.injectDefaultSettings()
        return viewModel
    }

    func injectDefaultSettings() {
        do {
            let result = try ConfigurationBootstrapper().bootstrap()
            config = result.config
            bookmarks = result.bookmarks
            storagePath = result.paths.baseURL.path

            if result.didCreateConfig || result.didCreateBookmarks {
                bootstrapMessage = "默认配置已自动注入"
            } else {
                bootstrapMessage = "已加载本地配置"
            }
        } catch {
            bootstrapMessage = "配置注入失败：\(error.localizedDescription)"
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
                Text(section.rawValue).tag(section)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch viewModel.selectedSection {
            case .onboarding:
                OnboardingView(viewModel: viewModel)
            case .directories:
                DirectoryListView(bookmarks: viewModel.bookmarks.bookmarks, storagePath: viewModel.storagePath)
            case .actions:
                ActionListView(actions: viewModel.config.actions)
            case .templates:
                TemplateListView(templates: viewModel.config.fileTemplates)
            case .developer:
                DeveloperEntrypointListView(entrypoints: viewModel.config.developerEntrypoints)
            case .history:
                PlaceholderSettingsSection(title: "最近操作", subtitle: "这里会展示最近 500 条操作记录。")
            }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("欢迎使用 RightTool").font(.largeTitle.bold())
            Text(viewModel.bootstrapMessage)
                .font(.headline)
                .foregroundStyle(.secondary)
            OnboardingStep(index: 1, title: "启用 Finder 扩展", detail: "在系统设置中启用 RightTool Finder Extension。")
            OnboardingStep(index: 2, title: "添加生效目录", detail: "预览版会自动注入桌面、下载、文稿和代码目录中存在的项目。")
            OnboardingStep(index: 3, title: "配置常用目录", detail: "自动注入的目录会同时用于前往、移动和复制。")
            OnboardingStep(index: 4, title: "试用右键菜单", detail: "打开授权目录，在 Finder 中右键查看 RightTool 菜单。")
            Button("重新注入默认设置") {
                viewModel.injectDefaultSettings()
            }
            Spacer()
        }
        .padding(28)
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

struct PlaceholderSettingsSection: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(28)
    }
}

struct DirectoryListView: View {
    let bookmarks: [DirectoryBookmark]
    let storagePath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("生效目录").font(.title.bold())
            Text("预览版已自动注入以下目录作为 Finder 右键菜单生效目录和常用目录。")
                .foregroundStyle(.secondary)

            List(bookmarks) { bookmark in
                VStack(alignment: .leading, spacing: 4) {
                    Text(bookmark.displayName)
                    Text(bookmark.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("配置位置").font(.headline)
                Text(storagePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(28)
    }
}

struct ActionListView: View {
    let actions: [RightToolAction]

    var body: some View {
        List(actions) { action in
            VStack(alignment: .leading) {
                Text(action.title)
                Text("\(action.kind.rawValue) · \(action.placement.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("菜单动作")
    }
}

struct TemplateListView: View {
    let templates: [FileTemplate]

    var body: some View {
        List(templates) { template in
            VStack(alignment: .leading) {
                Text(template.title)
                Text(template.defaultFileName).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("新建文件模板")
    }
}

struct DeveloperEntrypointListView: View {
    let entrypoints: [DeveloperEntrypoint]

    var body: some View {
        List(entrypoints) { entrypoint in
            VStack(alignment: .leading) {
                Text(entrypoint.title)
                Text(entrypoint.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开发者入口")
    }
}
