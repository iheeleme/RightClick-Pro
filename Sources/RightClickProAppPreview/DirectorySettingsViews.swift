import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

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

