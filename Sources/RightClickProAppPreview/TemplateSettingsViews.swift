import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

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
                icon: templateIconDescriptor(for: template),
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
        .background(SettingsTheme.pageOverlay)
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

    private var matchingAction: RightClickProAction? {
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

            SortStepControls(
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown
            )
            .frame(width: 120)

            HStack(spacing: 8) {
                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(templateDisplayTitle)",
                    helpText: "编辑模板"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(templateDisplayTitle)",
                    helpText: "删除模板",
                    tone: .destructive
                ) {
                    viewModel.deleteTemplate(template)
                }
            }
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
        MenuIconView(
            icon: templateIconDescriptor(for: template),
            tint: templateTint(for: template),
            size: 20,
            font: .system(size: 18, weight: .medium)
        )
            .frame(width: 28, height: 28)
            .background(templateTint(for: template).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct TemplateMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: rootMenuItems,
            submenuTitle: "新建文件",
            submenuItems: items.isEmpty ? [FinderMenuItem(title: "暂无启用模板")] : items
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("右键菜单预览")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("在 Finder 中右键时，启用的模板会出现在「新建文件」子菜单中。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        FinderPreviewRootMenu.standardContainerMenu(
            highlighting: FinderMenuItem(
                title: "新建文件",
                systemImage: "doc.badge.plus",
                tint: SettingsTheme.accent,
                isHighlighted: true,
                hasSubmenu: true
            )
        )
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

private func templateIconDescriptor(for template: FileTemplate) -> MenuIconDescriptor {
    let ext = templateExtensionText(for: template)
    return ext == "—" ? .systemSymbol("doc") : .fileExtension(ext)
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

