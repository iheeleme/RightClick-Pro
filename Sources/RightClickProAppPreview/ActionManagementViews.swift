import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

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

