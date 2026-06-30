import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

struct CommandTemplateListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: CommandTemplateDraft?

    var body: some View {
        let templates = viewModel.config.commandTemplates

        DesignPageScroll {
            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    CommandTemplateTableHeader()
                    if templates.isEmpty {
                        EmptyStateRow(title: "暂无命令模板", systemImage: "terminal")
                    } else {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            CommandTemplateTableRow(
                                template: template,
                                viewModel: viewModel,
                                canMoveUp: index > 0,
                                canMoveDown: index < templates.count - 1,
                                onEdit: {
                                    editingDraft = CommandTemplateDraft(template: template)
                                },
                                onMoveUp: {
                                    viewModel.moveCommandTemplate(template, offset: -1)
                                },
                                onMoveDown: {
                                    viewModel.moveCommandTemplate(template, offset: 1)
                                }
                            )
                            if index < templates.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }

            CommandMenuPreviewPanel(items: commandPreviewItems)

            CommandHintBanner()
        }
        .sheet(item: $editingDraft) { draft in
            CommandTemplateEditorSheet(draft: draft) { savedDraft in
                viewModel.upsertCommandTemplate(savedDraft)
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .onChange(of: viewModel.commandTemplateAddRequest) { _, _ in
            editingDraft = CommandTemplateDraft()
        }
    }

    private var commandPreviewItems: [FinderMenuItem] {
        let enabledActions = viewModel.config.actions
            .filter { $0.kind == .runCommand && $0.isEnabled }
            .sorted { $0.order < $1.order }

        return enabledActions.compactMap { action -> FinderMenuItem? in
            guard
                let templateID = action.payload.commandTemplateID,
                viewModel.config.commandTemplates.contains(where: { $0.id == templateID })
            else {
                return nil
            }

            return FinderMenuItem(
                title: action.title,
                icon: .systemSymbol("terminal"),
                tint: SettingsTheme.accent,
                id: action.id
            )
        }
    }
}

struct CommandTemplateTableHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            Text("排序").frame(width: 58, alignment: .center)
            Text("名称").frame(width: 170, alignment: .leading)
            Text("命令").frame(maxWidth: .infinity, alignment: .leading)
            Text("超时").frame(width: 70, alignment: .leading)
            Text("环境").frame(width: 72, alignment: .leading)
            Text("启用").frame(width: 64, alignment: .center)
            Text("操作").frame(width: 116, alignment: .center)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(SettingsTheme.muted)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(SettingsTheme.pageOverlay)
    }
}

struct CommandTemplateTableRow: View {
    let template: CommandTemplate
    @ObservedObject var viewModel: SettingsViewModel
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    private var matchingAction: RightClickProAction? {
        viewModel.config.actions.first {
            $0.kind == .runCommand && $0.payload.commandTemplateID == template.id
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            SortStepControls(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .frame(width: 58, alignment: .center)

            Button(action: onEdit) {
                HStack(spacing: 10) {
                    MenuIconView(
                        icon: .systemSymbol("terminal"),
                        tint: SettingsTheme.accent,
                        size: 22,
                        font: .system(size: 17, weight: .semibold)
                    )
                    .frame(width: 28, height: 28)
                    .background(SettingsTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                    Text(template.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 170, alignment: .leading)

            Text(template.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(template.timeoutSeconds)s")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 70, alignment: .leading)

            Text(environmentSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(template.environment.contains(where: \.isSensitive) ? .orange : SettingsTheme.muted)
                .frame(width: 72, alignment: .leading)

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
            .frame(width: 64)

            HStack(spacing: 8) {
                RowIconButton(
                    systemImage: "play.fill",
                    accessibilityLabel: "运行 \(template.title)",
                    helpText: "打开实时输出窗口"
                ) {
                    viewModel.runCommandTemplateFromSettings(template)
                }

                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(template.title)",
                    helpText: "编辑命令"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(template.title)",
                    helpText: "删除命令",
                    tone: .destructive
                ) {
                    viewModel.deleteCommandTemplate(template)
                }
            }
            .frame(width: 116)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .opacity((matchingAction?.isEnabled ?? true) ? 1 : 0.55)
    }

    private var environmentSummary: String {
        guard !template.environment.isEmpty else {
            return "—"
        }
        let sensitiveCount = template.environment.filter(\.isSensitive).count
        return sensitiveCount > 0 ? "\(template.environment.count) 个 / \(sensitiveCount) 密" : "\(template.environment.count) 个"
    }
}

struct CommandMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: FinderPreviewRootMenu.standardContainerMenu(
                highlighting: FinderMenuItem(
                    title: "命令模板",
                    systemImage: "terminal",
                    tint: SettingsTheme.accent,
                    isHighlighted: true,
                    hasSubmenu: true
                )
            ),
            submenuTitle: "命令模板",
            submenuItems: items.isEmpty ? [FinderMenuItem(title: "暂无启用命令")] : items
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("实时命令窗口")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("从 Finder 右键触发后，\(AppMetadata.displayName) 会自动打开实时输出窗口。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CommandHintBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.orange)
                .frame(width: 24)

            Text("安全边界：")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)

            Text("命令由 ActionRunner.xpc 执行；访问受 macOS 完全磁盘访问权限控制，敏感环境变量存入 Keychain。")
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.18)))
    }
}

