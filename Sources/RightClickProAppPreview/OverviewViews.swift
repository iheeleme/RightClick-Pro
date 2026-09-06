import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isPreviewExpanded = false

    var body: some View {
        DesignPageScroll {
            OverviewMetricStrip(viewModel: viewModel)

            if viewModel.shouldShowFinderExtensionSetupBanner {
                FinderExtensionSetupBanner(viewModel: viewModel)
            }

            if viewModel.shouldShowFullDiskAccessBanner {
                FullDiskAccessBanner(viewModel: viewModel)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("快捷入口")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    OverviewFeatureRow(
                        systemImage: "folder",
                        title: "常用目录",
                        meta: "\(viewModel.bookmarks.bookmarks.count) 个目录"
                    ) {
                        viewModel.selectedSection = .directories
                    }

                    OverviewFeatureRow(
                        systemImage: "chevron.left.forwardslash.chevron.right",
                        title: "开发者快捷入口",
                        meta: "\(enabledDeveloperCount) 个已启用入口"
                    ) {
                        viewModel.selectedSection = .developer
                    }

                    OverviewFeatureRow(
                        systemImage: "scissors",
                        title: "文件操作",
                        meta: "\(fileOperationActionCount) 个已启用操作"
                    ) {
                        viewModel.selectedSection = .history
                    }

                    OverviewFeatureRow(
                        systemImage: "doc.badge.plus",
                        title: "新建文件",
                        meta: "\(enabledTemplateCount) 个已启用模板"
                    ) {
                        viewModel.selectedSection = .templates
                    }
                }
            }
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 0) {
                Text("应用设置")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                    .padding(.vertical, 14)

                LaunchAtLoginPanel(viewModel: viewModel)
                Divider()
                UpdateCheckPanel(viewModel: viewModel)
            }

            Divider()

            DisclosureGroup(isExpanded: $isPreviewExpanded) {
                FinderContextMenuMock(
                    selectedContext: .desktop,
                    actions: viewModel.config.actions,
                    config: viewModel.config,
                    bookmarks: viewModel.bookmarks
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
            } label: {
                Label("Finder 菜单预览", systemImage: "contextualmenu.and.cursorarrow")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsTheme.ink)
            }
            .tint(SettingsTheme.muted)
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

}

struct UpdateCheckPanel: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(systemImage: panelState.systemImage, tint: panelState.tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(panelState.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text(panelState.message)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button {
                        viewModel.openUpdateReleasePage()
                    } label: {
                        Label(panelState.releaseButtonTitle, systemImage: "safari")
                            .frame(minWidth: 108)
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .controlSize(.large)
                    .help("打开 GitHub Releases 页面")

                    Button {
                        viewModel.checkForUpdates()
                    } label: {
                        Label(viewModel.isCheckingForUpdates ? "检查中..." : "检查更新", systemImage: "arrow.clockwise")
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(SettingsButtonStyle(isPrimary: true))
                    .controlSize(.large)
                    .disabled(viewModel.isCheckingForUpdates)
                    .help("从 GitHub 获取最新正式版本")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var panelState: UpdateCheckPanelState {
        switch viewModel.updateCheckStatus {
        case .unchecked:
            return UpdateCheckPanelState(
                title: "版本更新",
                message: "当前 \(AppMetadata.versionText)。手动检查 GitHub 最新正式版本；预发布版本不会计入更新提醒。",
                systemImage: "arrow.down.circle",
                tint: SettingsTheme.accent,
                releaseButtonTitle: "发布页"
            )
        case .checking:
            return UpdateCheckPanelState(
                title: "正在检查更新",
                message: "正在连接 GitHub Releases，获取最新公开正式版本。",
                systemImage: "arrow.triangle.2.circlepath",
                tint: SettingsTheme.accent,
                releaseButtonTitle: "发布页"
            )
        case .upToDate(let currentVersion, let latestTag):
            return UpdateCheckPanelState(
                title: "当前已是最新版本",
                message: "当前版本 \(currentVersion)，GitHub 最新正式版本 \(latestTag)。",
                systemImage: "checkmark.seal",
                tint: .green,
                releaseButtonTitle: "发布页"
            )
        case .updateAvailable(let currentVersion, let latestTag, _, let publishedAt):
            let publishedText = publishedAt.map { "，发布时间 \(operationDateFormatter.string(from: $0))" } ?? ""
            return UpdateCheckPanelState(
                title: "发现新版本 \(latestTag)",
                message: "当前版本 \(currentVersion)，GitHub 已发布 \(latestTag)\(publishedText)。",
                systemImage: "sparkles",
                tint: .orange,
                releaseButtonTitle: "查看版本"
            )
        case .unavailable(let message):
            return UpdateCheckPanelState(
                title: "暂时无法确认更新",
                message: "\(message)。当前 \(AppMetadata.versionText)。",
                systemImage: "exclamationmark.triangle",
                tint: .orange,
                releaseButtonTitle: "发布页"
            )
        }
    }
}

private struct UpdateCheckPanelState {
    var title: String
    var message: String
    var systemImage: String
    var tint: Color
    var releaseButtonTitle: String
}

struct LaunchAtLoginPanel: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(systemImage: "power.circle", tint: launchAtLoginTint)

                VStack(alignment: .leading, spacing: 6) {
                    Text("登录时自动启动")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text("开机登录后自动启动菜单栏应用，让 Finder 右键菜单和命令窗口随时可用。\(viewModel.launchAtLoginStatusMessage)")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 12) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.launchAtLoginToggleIsOn },
                            set: { viewModel.setLaunchAtLoginEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("将 \(AppMetadata.displayName) 加入或移出 macOS 登录项")

                    Button {
                        viewModel.openLoginItemsSettings()
                    } label: {
                        Label("打开登录项", systemImage: "gearshape")
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .controlSize(.large)
                    .help("打开系统设置中的登录项页面")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var launchAtLoginTint: Color {
        switch viewModel.launchAtLoginStatusTone {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .neutral:
            return SettingsTheme.accent
        }
    }
}

struct FinderExtensionSetupBanner: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(systemImage: "puzzlepiece.extension", tint: .orange)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Finder 右键菜单需要处理")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text(viewModel.finderExtensionSetupMessage.isEmpty ? "\(AppMetadata.displayName) 未完成 Finder Extension 自动注入，请手动修复后重新打开右键菜单。" : viewModel.finderExtensionSetupMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button {
                        viewModel.openFinderExtensionSettings()
                    } label: {
                        Label("打开扩展设置", systemImage: "gearshape")
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(SettingsButtonStyle(isPrimary: true))
                    .controlSize(.large)
                    .help("打开系统设置中的 Finder 扩展页面")

                    Button {
                        viewModel.restartFinder()
                    } label: {
                        Label(viewModel.isRepairingFinderMenu ? "修复中..." : "修复并重启 Finder", systemImage: "arrow.clockwise")
                            .frame(minWidth: 136)
                    }
                    .buttonStyle(SettingsButtonStyle())
                    .controlSize(.large)
                    .disabled(viewModel.isRepairingFinderMenu)
                    .help("会短暂关闭并重新打开 Finder 窗口")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

struct FullDiskAccessBanner: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(systemImage: "lock.shield", tint: fullDiskAccessTint)

                VStack(alignment: .leading, spacing: 6) {
                    Text("完全磁盘访问权限")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text("Finder 菜单会全局显示；文件动作和命令模板执行时依赖 macOS 的完全磁盘访问权限。请通过下方按钮打开系统设置统一授权；实际执行被拦截时会显示具体错误。\(viewModel.fullDiskAccessStatusMessage)")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    Button {
                        viewModel.openFullDiskAccessSettings()
                    } label: {
                        Label("打开权限设置", systemImage: "gearshape")
                            .frame(minWidth: 124)
                    }
                    .buttonStyle(SettingsButtonStyle(isPrimary: true))
                    .controlSize(.large)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var fullDiskAccessTint: Color {
        switch viewModel.fullDiskAccessStatusTone {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .neutral:
            return SettingsTheme.accent
        }
    }
}

struct OverviewFeatureRow: View {
    let systemImage: String
    let title: String
    let meta: String
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                IconBadge(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsTheme.muted)
                    .frame(width: 14)

            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(
                isHovered ? SettingsTheme.controlBackgroundHover : SettingsTheme.surfaceSoft,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
    }
}

struct OverviewMetricStrip: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 0) {
            OverviewMetric(title: "已启用菜单", value: viewModel.enabledActionCount)
            metricDivider
            OverviewMetric(title: "常用目录", value: viewModel.bookmarks.bookmarks.count)
            metricDivider
            OverviewMetric(title: "文件模板", value: viewModel.config.fileTemplates.count)
            metricDivider
            OverviewMetric(title: "命令模板", value: viewModel.config.commandTemplates.count)
        }
        .padding(.vertical, 12)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SettingsTheme.hairline).frame(height: 0.5)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SettingsTheme.hairline)
            .frame(width: 0.5, height: 34)
    }
}

struct OverviewMetric: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
            Text(value, format: .number)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(SettingsTheme.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }
}
