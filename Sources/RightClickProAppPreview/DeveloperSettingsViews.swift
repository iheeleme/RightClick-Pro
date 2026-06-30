import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

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

