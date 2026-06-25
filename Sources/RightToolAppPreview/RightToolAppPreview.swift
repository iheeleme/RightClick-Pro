import RightToolCore
import SwiftUI

@main
struct RightToolAppPreview: App {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some Scene {
        MenuBarExtra("RightTool", systemImage: "contextualmenu.and.cursorarrow") {
            Button("打开设置") {
                viewModel.isSettingsPresented = true
            }
            Button("修复右键菜单...") {
                viewModel.selectedSection = .onboarding
                viewModel.isSettingsPresented = true
            }
            Divider()
            Button("退出 RightTool") {
                NSApplication.shared.terminate(nil)
            }
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
    @Published var isSettingsPresented = false
    @Published var config = RightToolConfig()
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
                OnboardingView()
            case .directories:
                PlaceholderSettingsSection(title: "生效目录", subtitle: "添加 Finder 右键菜单生效的授权目录。")
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
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("欢迎使用 RightTool").font(.largeTitle.bold())
            OnboardingStep(index: 1, title: "启用 Finder 扩展", detail: "在系统设置中启用 RightTool Finder Extension。")
            OnboardingStep(index: 2, title: "添加生效目录", detail: "选择桌面、下载或项目目录，并授权访问。")
            OnboardingStep(index: 3, title: "配置常用目录", detail: "用于前往、移动和复制文件。")
            OnboardingStep(index: 4, title: "试用右键菜单", detail: "打开授权目录，在 Finder 中右键查看 RightTool 菜单。")
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
