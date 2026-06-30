import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

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

