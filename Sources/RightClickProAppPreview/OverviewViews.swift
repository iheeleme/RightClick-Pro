import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        OverviewPageScroll {
            if viewModel.shouldShowFinderExtensionSetupBanner {
                FinderExtensionSetupBanner(viewModel: viewModel)
            }

            if viewModel.shouldShowFullDiskAccessBanner {
                FullDiskAccessBanner(viewModel: viewModel)
            }

            LaunchAtLoginPanel(viewModel: viewModel)
            UpdateCheckPanel(viewModel: viewModel)

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("功能总览")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)

                    VStack(spacing: 14) {
                        OverviewFeatureRow(
                            systemImage: "folder",
                            title: "常用目录快捷直达",
                            detail: "在右键菜单中快速打开常用目录和文件夹",
                            meta: "已启用 \(viewModel.bookmarks.bookmarks.count) 个目录",
                            isOn: !viewModel.bookmarks.bookmarks.isEmpty
                        ) {
                            viewModel.selectedSection = .directories
                        }

                        OverviewFeatureRow(
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            title: "开发者快捷入口",
                            detail: "快速打开常用开发工具和项目",
                            meta: "已启用 \(enabledDeveloperCount) 个入口",
                            isOn: enabledDeveloperCount > 0
                        ) {
                            viewModel.selectedSection = .developer
                        }

                        OverviewFeatureRow(
                            systemImage: "scissors",
                            title: "剪切 / 粘贴文件",
                            detail: "增强版剪切、粘贴与历史记录",
                            meta: "剪贴板中有 \(fileOperationActionCount) 项内容",
                            isOn: fileOperationActionCount > 0
                        ) {
                            viewModel.selectedSection = .history
                        }

                        OverviewFeatureRow(
                            systemImage: "doc.badge.plus",
                            title: "右键新建文件",
                            detail: "在右键菜单中新建常用文件类型",
                            meta: "已启用 \(enabledTemplateCount) 个模板",
                            isOn: enabledTemplateCount > 0
                        ) {
                            viewModel.selectedSection = .templates
                        }
                    }

                    OverviewHintBanner()
                        .padding(.top, 2)
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                OverviewFinderMenuCallout(items: overviewSubmenuItems)
                    .frame(width: 262)
            }

            OverviewMetricStrip(viewModel: viewModel)
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

    private var overviewRootMenuItems: [FinderMenuItem] {
        [
            FinderMenuItem(title: "新建文件夹", systemImage: nil, hasSubmenu: true),
            FinderMenuItem(title: "显示简介", systemImage: nil),
            FinderMenuItem(title: "排序方式", systemImage: nil, hasSubmenu: true),
            FinderMenuItem(title: "整理方式", systemImage: nil, hasSubmenu: true)
        ]
    }

    private var overviewSubmenuItems: [FinderMenuItem] {
        [
            FinderMenuItem(title: "常用目录", systemImage: "folder", tint: .blue, hasSubmenu: true),
            FinderMenuItem(title: "开发者入口", systemImage: "chevron.left.forwardslash.chevron.right", tint: SettingsTheme.accent, hasSubmenu: true),
            FinderMenuItem(title: "剪切 / 粘贴文件", systemImage: "scissors", tint: SettingsTheme.accent, hasSubmenu: true),
            FinderMenuItem(title: "新建文件", systemImage: "doc", tint: SettingsTheme.accent, hasSubmenu: true)
        ]
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
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("打开 GitHub Releases 页面")

                    Button {
                        viewModel.checkForUpdates()
                    } label: {
                        Label(viewModel.isCheckingForUpdates ? "检查中..." : "检查更新", systemImage: "arrow.clockwise")
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(.borderedProminent)
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
                    .buttonStyle(.bordered)
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("打开系统设置中的 Finder 扩展页面")

                    Button {
                        viewModel.restartFinder()
                    } label: {
                        Label(viewModel.isRepairingFinderMenu ? "修复中..." : "修复并重启 Finder", systemImage: "arrow.clockwise")
                            .frame(minWidth: 136)
                    }
                    .buttonStyle(.bordered)
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
                    .buttonStyle(.borderedProminent)
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
    let detail: String
    let meta: String
    let isOn: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(width: 112, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SettingsTheme.muted)
                    .frame(width: 14)

                Toggle("", isOn: .constant(isOn))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(SettingsTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
        }
        .buttonStyle(.plain)
    }
}

struct OverviewHintBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "lightbulb")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 32)

            Text("提示")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SettingsTheme.accent)

            Text("所有功能均可在右键菜单中使用，支持箭头排序与自定义设置。")
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(SettingsTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.accent.opacity(0.18)))
    }
}

struct OverviewFinderMenuCallout: View {
    let items: [FinderMenuItem]

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            OverviewContextMenu(items: items)

            HStack(alignment: .top, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    OverviewCalloutArrow()
                        .stroke(
                            SettingsTheme.accent,
                            style: StrokeStyle(lineWidth: 1.35, lineCap: .round, dash: [5, 5])
                        )
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.accent)
                        .rotationEffect(.degrees(28))
                        .offset(x: 4, y: -3)
                }
                .frame(width: 40, height: 52)
                .padding(.top, 0)

                Text("在 Finder 右键菜单中\n快速访问常用功能")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsTheme.accent)
                    .lineSpacing(5)
                    .rotationEffect(.degrees(-2))
                    .padding(.top, 28)
            }
            .padding(.trailing, 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct OverviewCalloutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 4))
        path.addCurve(
            to: CGPoint(x: rect.minX + 8, y: rect.maxY - 8),
            control1: CGPoint(x: rect.midX + 4, y: rect.midY - 6),
            control2: CGPoint(x: rect.minX + 2, y: rect.midY + 22)
        )
        return path
    }
}

struct OverviewContextMenu: View {
    let items: [FinderMenuItem]

    var body: some View {
        VStack(spacing: 0) {
            OverviewContextMenuRow(item: FinderMenuItem(title: "新建文件夹", hasSubmenu: true))
            Divider().padding(.horizontal, 12)
            OverviewContextMenuRow(item: FinderMenuItem(title: "显示简介"))
            OverviewContextMenuRow(item: FinderMenuItem(title: "更改桌面背景..."))
            Divider().padding(.horizontal, 12)
            OverviewContextMenuRow(item: FinderMenuItem(title: "使用叠放"))
            OverviewContextMenuRow(item: FinderMenuItem(title: "排序方式", hasSubmenu: true))
            OverviewContextMenuRow(item: FinderMenuItem(title: "整理"))
            OverviewContextMenuRow(item: FinderMenuItem(title: "整理方式", hasSubmenu: true))
            OverviewContextMenuRow(item: FinderMenuItem(title: "查看显示选项"))
            Divider().padding(.horizontal, 12)

            ForEach(items) { item in
                OverviewContextMenuRow(item: item)
            }

            Divider().padding(.horizontal, 12)
            OverviewContextMenuRow(item: FinderMenuItem(title: "服务", hasSubmenu: true))
        }
        .padding(.vertical, 8)
        .frame(width: 228)
        .background(SettingsTheme.menuBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SettingsTheme.hairline))
        .shadow(color: SettingsTheme.menuShadow, radius: 18, x: 0, y: 12)
    }
}

struct OverviewContextMenuRow: View {
    let item: FinderMenuItem

    var body: some View {
        HStack(spacing: 10) {
            if let icon = item.icon {
                MenuIconView(
                    icon: icon,
                    tint: item.tint,
                    isHighlighted: item.isHighlighted,
                    size: 17,
                    font: .system(size: 13, weight: .medium)
                )
            }

            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if item.hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SettingsTheme.muted)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
    }
}

struct OverviewMetricStrip: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        DesignPanel(padding: 0) {
            HStack(spacing: 0) {
                OverviewMetric(systemImage: "clock", title: "高效便捷", subtitle: "常用功能一步直达")
                metricDivider
                OverviewMetric(systemImage: "shield.checkered", title: "安全可靠", subtitle: "本地运行，保护隐私")
                metricDivider
                OverviewMetric(systemImage: "bolt", title: "轻量稳定", subtitle: "占用资源少，运行流畅")
                metricDivider
                OverviewMetric(systemImage: "slider.horizontal.3", title: "高度可自定义", subtitle: "按需启用，自由配置")
            }
            .frame(height: 70)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SettingsTheme.hairline)
            .frame(width: 1, height: 38)
    }
}

struct OverviewMetric: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(SettingsTheme.accent)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 14)
    }
}
