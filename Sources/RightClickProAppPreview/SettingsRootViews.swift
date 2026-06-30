import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开设置") {
            openSettings()
        }
        Button("修复右键菜单...") {
            viewModel.repairFinderContextMenu(restartFinder: true, userInitiated: true)
            openSettings(section: .onboarding)
        }
        Divider()
        Button("退出 \(AppMetadata.displayName)") {
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
    @State private var visualSelection: SettingsViewModel.Section = .onboarding
    @State private var renderedSection: SettingsViewModel.Section = .onboarding
    @State private var selectionRevision = 0

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selectedSection: visualSelection,
                badges: sidebarBadges,
                onSelect: selectSection
            )
                .frame(width: 280)

            SettingsDetailShell(section: renderedSection, viewModel: viewModel) {
                switch renderedSection {
                case .onboarding:
                    OnboardingView(viewModel: viewModel)
                case .directories:
                    DirectoryListView(viewModel: viewModel)
                case .actions:
                    ActionListView(viewModel: viewModel)
                case .templates:
                    TemplateListView(viewModel: viewModel)
                case .developer:
                    DeveloperEntrypointListView(viewModel: viewModel)
                case .commands:
                    CommandTemplateListView(viewModel: viewModel)
                case .history:
                    OperationHistoryView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsTheme.windowBackground)
        .background(SettingsWindowChromeConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            visualSelection = viewModel.selectedSection
            renderedSection = viewModel.selectedSection
        }
        .onReceive(viewModel.$selectedSection) { section in
            guard section != renderedSection else { return }
            visualSelection = section
            renderedSection = section
        }
    }

    private var sidebarBadges: [SettingsViewModel.Section: String] {
        Dictionary(
            uniqueKeysWithValues: SettingsViewModel.Section.allCases.compactMap { section in
                viewModel.sectionBadge(for: section).map { (section, $0) }
            }
        )
    }

    private func selectSection(_ section: SettingsViewModel.Section) {
        guard visualSelection != section || renderedSection != section else {
            return
        }

        visualSelection = section
        selectionRevision += 1
        let revision = selectionRevision

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
            guard selectionRevision == revision, visualSelection == section else {
                return
            }

            renderedSection = section
            viewModel.selectedSection = section
        }
    }
}

private enum SettingsChromeMetrics {
    static let sidebarTopPadding: CGFloat = 64
    static let sidebarBottomPadding: CGFloat = 24
}

private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.backgroundColor = SettingsTheme.windowBackgroundColor
    }
}

enum SettingsTheme {
    static let accent = adaptiveColor(
        light: NSColor(calibratedRed: 0.24, green: 0.32, blue: 0.98, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.54, green: 0.62, blue: 1.0, alpha: 1.0)
    )
    static let accentSoft = adaptiveColor(
        light: NSColor(calibratedRed: 0.93, green: 0.92, blue: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.34, alpha: 1.0)
    )
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let hairline = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.08),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
    )
    static let windowBackgroundColor = adaptiveNSColor(
        light: NSColor(calibratedRed: 0.96, green: 0.97, blue: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1.0)
    )
    static let sidebarBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.58),
        dark: NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.12, alpha: 0.92)
    )
    static let headerBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedRed: 0.085, green: 0.095, blue: 0.13, alpha: 0.96)
    )
    static let pageOverlay = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.34),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.035)
    )
    static let surface = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.90),
        dark: NSColor(calibratedRed: 0.115, green: 0.13, blue: 0.17, alpha: 0.96)
    )
    static let surfaceSoft = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.055)
    )
    static let surfaceElevated = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.14, green: 0.155, blue: 0.20, alpha: 1.0)
    )
    static let controlBackground = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.62),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.07)
    )
    static let controlBackgroundHover = adaptiveColor(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.72),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.11)
    )
    static let subtleFill = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.035),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.065)
    )
    static let menuShadow = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.16),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.45)
    )
    static let commandOutputText = adaptiveColor(
        light: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.18, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.93, alpha: 1.0)
    )
    static let commandOutputBackground = adaptiveColor(
        light: NSColor(calibratedRed: 0.965, green: 0.972, blue: 0.985, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.10, alpha: 1.0)
    )

    static var windowBackground: LinearGradient {
        LinearGradient(
            colors: [
                adaptiveColor(
                    light: NSColor(calibratedRed: 0.96, green: 0.97, blue: 1.0, alpha: 1.0),
                    dark: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1.0)
                ),
                adaptiveColor(
                    light: NSColor(calibratedWhite: 1.0, alpha: 1.0),
                    dark: NSColor(calibratedRed: 0.09, green: 0.105, blue: 0.14, alpha: 1.0)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var menuBackground: LinearGradient {
        LinearGradient(
            colors: [
                adaptiveColor(
                    light: NSColor(calibratedWhite: 1.0, alpha: 0.96),
                    dark: NSColor(calibratedRed: 0.13, green: 0.145, blue: 0.18, alpha: 0.98)
                ),
                adaptiveColor(
                    light: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: 1.0),
                    dark: NSColor(calibratedRed: 0.09, green: 0.105, blue: 0.14, alpha: 1.0)
                )
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.45, green: 0.55, blue: 1.0),
                Color(red: 0.31, green: 0.22, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNSColor(light: light, dark: dark))
    }

    private static func adaptiveNSColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

private enum RightClickProIconAsset {
    static let resourceName = "RightClickProIcon"
    static let pngExtension = "png"
    static let sourceRelativePath = "design/icon.png"
    static let image = loadImage()

    private static func loadImage() -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: resourceName, withExtension: pngExtension),
           let image = NSImage(contentsOf: bundledURL) {
            return image
        }

        let fileManager = FileManager.default
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let packageRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidateURLs = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(sourceRelativePath),
            packageRootURL.appendingPathComponent(sourceRelativePath)
        ]

        for url in candidateURLs where fileManager.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }
}

struct RightClickProBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = RightClickProIconAsset.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(SettingsTheme.brandGradient)
            Image(systemName: "cursorarrow")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-18))
        }
    }
}

struct SettingsSidebar: View {
    let selectedSection: SettingsViewModel.Section
    let badges: [SettingsViewModel.Section: String]
    let onSelect: (SettingsViewModel.Section) -> Void

    private let sections = SettingsViewModel.SidebarGroup.allCases.flatMap { $0.sections }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                RightClickProBrandIcon(size: 44)
                    .shadow(color: SettingsTheme.accent.opacity(0.18), radius: 14, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppMetadata.displayName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text("Mac 右键效率工具")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsTheme.muted)
                    Text(AppMetadata.versionText)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.muted.opacity(0.82))
                        .monospacedDigit()
                }
            }

            VStack(spacing: 8) {
                ForEach(sections) { section in
                    SidebarNavigationRow(
                        section: section,
                        badge: badges[section],
                        isSelected: selectedSection == section
                    ) {
                        onSelect(section)
                    }
                }
            }

            Spacer(minLength: 16)

            SidebarHintCard()
        }
        .padding(.horizontal, 24)
        .padding(.top, SettingsChromeMetrics.sidebarTopPadding)
        .padding(.bottom, SettingsChromeMetrics.sidebarBottomPadding)
        .background(SettingsTheme.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsTheme.hairline)
                .frame(width: 1)
        }
    }
}

struct SidebarHintCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text("小提示")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                Text("使用排序箭头调整顺序，启用/禁用快速定制你的右键菜单。")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct SidebarNavigationRow: View {
    let section: SettingsViewModel.Section
    let badge: String?
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var didSelectDuringPress = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 22)
                .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.muted)

            Text(section.sidebarTitle)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? SettingsTheme.accent : SettingsTheme.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SettingsTheme.controlBackgroundHover, in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(
            isSelected ? SettingsTheme.accentSoft : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !didSelectDuringPress else { return }
                    didSelectDuringPress = true
                    onSelect()
                }
                .onEnded { _ in
                    didSelectDuringPress = false
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsDetailShell<Content: View>: View {
    let section: SettingsViewModel.Section
    @ObservedObject var viewModel: SettingsViewModel
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                    .layoutPriority(1)

                if section != .onboarding {
                    Spacer(minLength: 12)

                    headerActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, section == .directories ? 20 : (section == .onboarding ? 22 : 28))
            .padding(.bottom, section == .onboarding ? 8 : 16)
            .background(SettingsTheme.headerBackground)

            if section != .onboarding && section != .directories {
                Rectangle()
                    .fill(SettingsTheme.hairline)
                    .frame(height: 1)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.rawValue)
                .font(.system(size: titleSize, weight: .bold))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            if section == .onboarding {
                HStack(spacing: 0) {
                    Text("管理和自定义 ")
                    Text("Finder")
                        .foregroundStyle(SettingsTheme.accent)
                    Text(" 右键菜单，提升操作效率")
                }
                .font(.system(size: 14))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
            } else {
                Text(section.subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            if section == .directories {
                DirectoryHeaderAddButton {
                    viewModel.addDirectoryBookmarkFromPanel()
                }
            } else if section == .developer {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }
                DeveloperHeaderAddButton {
                    viewModel.requestAddDeveloperEntrypoint()
                }
            } else if section == .commands {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }
                CommandHeaderAddButton {
                    viewModel.requestAddCommandTemplate()
                }
            } else if section == .templates {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }
                TemplateHeaderAddButton {
                    viewModel.requestAddTemplate()
                }
            } else if section == .actions {
                if viewModel.hasUnsavedChanges {
                    StatusBadge(
                        message: viewModel.statusMessage,
                        tone: viewModel.statusTone,
                        isDirty: viewModel.hasUnsavedChanges
                    )
                    .frame(maxWidth: 92)

                    SaveConfigButton(viewModel: viewModel)
                        .fixedSize(horizontal: true, vertical: false)
                }

                SearchField(placeholder: "搜索菜单项或功能...", text: $viewModel.actionSearchText)
                    .frame(width: 270)

                ActionHeaderAddMenu(viewModel: viewModel)
            } else {
                StatusBadge(
                    message: viewModel.statusMessage,
                    tone: viewModel.statusTone,
                    isDirty: viewModel.hasUnsavedChanges
                )

                SaveConfigButton(viewModel: viewModel)
            }
        }
        .frame(alignment: .trailing)
        .layoutPriority((section == .actions || section == .developer || section == .templates) ? 2 : 0)
    }

    private var titleSize: CGFloat {
        switch section {
        case .onboarding, .directories:
            return 22
        case .actions:
            return 26
        default:
            return 28
        }
    }
}

struct ActionHeaderAddMenu: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Menu {
            Button {
                viewModel.addDirectoryBookmarkFromPanel()
            } label: {
                Label("添加常用目录", systemImage: "folder.badge.plus")
            }

            Button {
                viewModel.requestAddDeveloperEntrypoint()
            } label: {
                Label("添加开发者入口", systemImage: "terminal")
            }

            Button {
                viewModel.requestAddTemplate()
            } label: {
                Label("添加新建模板", systemImage: "doc.badge.plus")
            }

            Button {
                viewModel.requestAddCommandTemplate()
            } label: {
                Label("添加命令模板", systemImage: "terminal")
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("新增菜单项")
                    .font(.system(size: 14, weight: .semibold))
                Divider()
                    .frame(height: 18)
                    .overlay(.white.opacity(0.42))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("新增菜单项")
    }
}

struct DirectoryHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加目录", systemImage: "plus.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("添加常用目录")
    }
}

struct DeveloperHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加快捷入口", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 124, height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("添加开发者快捷入口")
    }
}

struct TemplateHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加模板", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 112, height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("添加新建文件模板")
    }
}

struct CommandHeaderAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("添加命令", systemImage: "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 112, height: 38)
                .background(SettingsTheme.accent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("添加命令模板")
    }
}

struct StatusBadge: View {
    let message: String
    let tone: SettingsViewModel.StatusTone
    let isDirty: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isDirty ? "circle.fill" : "checkmark.circle.fill")
                .font(.caption)
            Text(message.isEmpty ? "就绪" : message)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(tone.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tone.color.opacity(0.16)))
    }
}

struct SaveConfigButton: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        if viewModel.hasUnsavedChanges {
            Button {
                viewModel.saveConfig()
            } label: {
                Label("保存配置", systemImage: "square.and.arrow.down")
                    .frame(minWidth: 86)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: [.command])
        } else {
            Button {
                viewModel.saveConfig()
            } label: {
                Label("已保存", systemImage: "checkmark")
                    .frame(minWidth: 86)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(true)
        }
    }
}

struct DesignPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(SettingsTheme.pageOverlay)
    }
}

struct OverviewPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .background(SettingsTheme.pageOverlay)
    }
}

struct DirectoryPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(SettingsTheme.pageOverlay)
    }
}

struct DesignPanel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct HintBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.title3)
                .foregroundStyle(SettingsTheme.accent)
            Text("提示：")
                .font(.headline)
                .foregroundStyle(SettingsTheme.accent)
            Text(text)
                .foregroundStyle(SettingsTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(SettingsTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.accent.opacity(0.18)))
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SettingsTheme.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(SettingsTheme.ink)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 220, maxWidth: 360, minHeight: 36)
        .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
    }
}

struct PageToolbar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            leading
            Spacer(minLength: 16)
            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PreviewSection<Intro: View>: View {
    let rootItems: [FinderMenuItem]
    let submenuTitle: String?
    let submenuItems: [FinderMenuItem]
    @ViewBuilder var intro: Intro

    init(
        rootItems: [FinderMenuItem],
        submenuTitle: String? = nil,
        submenuItems: [FinderMenuItem],
        @ViewBuilder intro: () -> Intro
    ) {
        self.rootItems = rootItems
        self.submenuTitle = submenuTitle
        self.submenuItems = submenuItems
        self.intro = intro()
    }

    var body: some View {
        DesignPanel {
            VStack(alignment: .leading, spacing: 18) {
                intro
                FinderMenuPreview(
                    title: nil,
                    caption: nil,
                    rootItems: rootItems,
                    submenuTitle: submenuTitle,
                    submenuItems: submenuItems,
                    isFramed: false
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct IconBadge: View {
    let systemImage: String
    var tint: Color = SettingsTheme.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 46, height: 46)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum RowIconControlTone {
    case neutral
    case accent
    case destructive

    var foreground: Color {
        switch self {
        case .neutral:
            return SettingsTheme.muted
        case .accent:
            return SettingsTheme.accent
        case .destructive:
            return .red
        }
    }

    var hoverBackground: Color {
        switch self {
        case .neutral:
            return SettingsTheme.accent.opacity(0.08)
        case .accent:
            return SettingsTheme.accent.opacity(0.12)
        case .destructive:
            return Color.red.opacity(0.1)
        }
    }

    var hoverStroke: Color {
        switch self {
        case .neutral:
            return SettingsTheme.accent.opacity(0.18)
        case .accent:
            return SettingsTheme.accent.opacity(0.24)
        case .destructive:
            return Color.red.opacity(0.22)
        }
    }
}

struct RowIconControlLabel: View {
    let systemImage: String
    var tone: RowIconControlTone = .neutral
    var isDisabled = false
    var size: CGFloat = 28
    var iconSize: CGFloat = 13
    var cornerRadius: CGFloat = 7
    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(stroke)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onHover { hovering in
                guard !isDisabled else { return }
                isHovered = hovering
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var foreground: Color {
        isDisabled ? SettingsTheme.muted.opacity(0.36) : tone.foreground
    }

    private var background: Color {
        if isDisabled {
            return SettingsTheme.subtleFill.opacity(0.65)
        }
        return isHovered ? tone.hoverBackground : SettingsTheme.controlBackground
    }

    private var stroke: Color {
        if isDisabled {
            return SettingsTheme.hairline.opacity(0.65)
        }
        return isHovered ? tone.hoverStroke : SettingsTheme.hairline
    }
}

struct RowIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var helpText: String? = nil
    var tone: RowIconControlTone = .neutral
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RowIconControlLabel(
                systemImage: systemImage,
                tone: tone,
                isDisabled: isDisabled
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText ?? accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }
}

