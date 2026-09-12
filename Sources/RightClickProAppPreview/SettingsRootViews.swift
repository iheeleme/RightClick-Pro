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
                .frame(width: 248)

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
        .accentColor(SettingsTheme.accent)
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
    static let sidebarTopPadding: CGFloat = 56
    static let sidebarBottomPadding: CGFloat = 24
}

private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window, colorScheme: colorScheme)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window, colorScheme: colorScheme)
        }
    }

    private func configure(window: NSWindow?, colorScheme: ColorScheme) {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        window.backgroundColor = SettingsTheme.windowBackgroundColor
    }
}

enum SettingsTheme {
    // Kimi 的中性表面与语义蓝共用一套亮暗色令牌。
    static let accent = color(0x1783FF, dark: 0x469DFF)
    static let ink = color(0x1A1A1A, dark: 0xE8E8E8)
    static let muted = color(0x666666, dark: 0xA3A3A3)
    static let tertiary = color(0x8C8C8C, dark: 0x858585)
    static let selectionFill = color(0xE9E9E9, dark: 0x303030)
    static let primaryAction = color(0x1A1A1A, dark: 0xE8E8E8)
    static let primaryActionHover = color(0x303030, dark: 0xFFFFFF)
    static let primaryActionPressed = color(0x000000, dark: 0xCBCBCB)
    static let primaryActionLabel = color(0xFFFFFF, dark: 0x171717)
    static let hairline = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.13),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.13)
    )
    static let windowBackgroundColor = adaptiveNSColor(
        light: nsColor(0xFFFFFF),
        dark: nsColor(0x141414)
    )
    static let windowBackground = Color(nsColor: windowBackgroundColor)
    static let sidebarBackground = color(0xF5F5F5, dark: 0x1A1A1A)
    static let headerBackground = windowBackground
    static let pageOverlay = windowBackground
    static let surface = windowBackground
    static let surfaceSoft = color(0xF5F5F5, dark: 0x202020)
    static let surfaceElevated = color(0xFFFFFF, dark: 0x262626)
    static let controlBackground = color(0xF5F5F5, dark: 0x262626)
    static let controlBackgroundHover = color(0xEBEBEB, dark: 0x323232)
    static let subtleFill = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.03),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.045)
    )
    static let menuShadow = adaptiveColor(
        light: NSColor(calibratedWhite: 0.0, alpha: 0.16),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.45)
    )
    static let commandOutputText = ink
    static let commandOutputBackground = color(0xF5F5F5, dark: 0x1A1A1A)

    static var menuBackground: LinearGradient {
        LinearGradient(
            colors: [
                color(0xFFFFFF, dark: 0x2B2B2B),
                color(0xF5F5F5, dark: 0x252525)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func color(_ light: UInt32, dark: UInt32) -> Color {
        adaptiveColor(light: nsColor(light), dark: nsColor(dark))
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
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

@MainActor
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
                .fill(SettingsTheme.accent)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                RightClickProBrandIcon(size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(AppMetadata.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                    Text("Finder")
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.tertiary)
                }
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(SettingsViewModel.SidebarGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        if group != .guided {
                            Text(group.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SettingsTheme.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 4)
                        }

                        ForEach(group.sections) { section in
                            SidebarNavigationRow(
                                section: section,
                                badge: badges[section],
                                isSelected: selectedSection == section
                            ) {
                                onSelect(section)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 16)

            Text(AppMetadata.versionText)
                .font(.system(size: 11))
                .foregroundStyle(SettingsTheme.tertiary)
                .monospacedDigit()
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, SettingsChromeMetrics.sidebarTopPadding)
        .padding(.bottom, SettingsChromeMetrics.sidebarBottomPadding)
        .background(SettingsTheme.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(SettingsTheme.hairline)
                .frame(width: 0.5)
        }
    }
}

struct SidebarNavigationRow: View {
    let section: SettingsViewModel.Section
    let badge: String?
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var didSelectDuringPress = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 18)
                .foregroundStyle(isSelected ? SettingsTheme.ink : SettingsTheme.muted)

            Text(section.sidebarTitle)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(SettingsTheme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(SettingsTheme.tertiary)
                    .frame(minWidth: 18)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(
            isSelected ? SettingsTheme.selectionFill : (isHovered ? SettingsTheme.subtleFill : Color.clear),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
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
        .accessibilityAction { onSelect() }
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

                Spacer(minLength: 12)
                headerActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 36)
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 20)
            .background(SettingsTheme.headerBackground)

            Rectangle()
                .fill(SettingsTheme.hairline)
                .frame(height: 0.5)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var titleBlock: some View {
        Text(section.rawValue)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(SettingsTheme.ink)
            .lineLimit(1)
            .help(section.subtitle)
    }

    @ViewBuilder
    private var headerActions: some View {
        switch section {
        case .directories:
            HStack(spacing: 12) {
                headerStatusCluster
                HeaderActionButton(title: "添加目录") {
                    viewModel.addDirectoryBookmarkFromPanel()
                }
            }
        case .developer:
            HStack(spacing: 12) {
                headerStatusCluster
                HeaderActionButton(title: "添加快捷入口") {
                    viewModel.requestAddDeveloperEntrypoint()
                }
            }
        case .commands:
            HStack(spacing: 12) {
                headerStatusCluster
                HeaderActionButton(title: "添加命令") {
                    viewModel.requestAddCommandTemplate()
                }
            }
        case .templates:
            HStack(spacing: 12) {
                headerStatusCluster
                HeaderActionButton(title: "添加模板") {
                    viewModel.requestAddTemplate()
                }
            }
        case .actions:
            HStack(spacing: 12) {
                headerStatusCluster
                SearchField(placeholder: "搜索菜单项或功能...", text: $viewModel.actionSearchText)
                    .frame(width: 240)
                ActionHeaderAddMenu(viewModel: viewModel)
            }
        case .onboarding, .history:
            headerStatusCluster
        }
    }

    private var headerStatusCluster: some View {
        HStack(spacing: 12) {
            StatusBadge(
                message: viewModel.statusMessage,
                tone: viewModel.statusTone,
                isDirty: viewModel.hasUnsavedChanges
            )
            .frame(maxWidth: 120)

            if viewModel.hasUnsavedChanges {
                SaveConfigButton(viewModel: viewModel)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

struct ActionHeaderAddMenu: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var isHovered = false

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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("新增菜单项")
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(SettingsTheme.primaryActionLabel)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                isHovered ? SettingsTheme.primaryActionHover : SettingsTheme.primaryAction,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("新增菜单项")
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var isPrimary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isPrimary ? SettingsTheme.primaryActionLabel : SettingsTheme.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(background(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovered)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
    }

    private func background(isPressed: Bool) -> Color {
        if isPrimary {
            if isPressed && isEnabled { return SettingsTheme.primaryActionPressed }
            return isHovered && isEnabled ? SettingsTheme.primaryActionHover : SettingsTheme.primaryAction
        }
        if isPressed && isEnabled { return SettingsTheme.selectionFill }
        return isHovered && isEnabled ? SettingsTheme.controlBackgroundHover : SettingsTheme.controlBackground
    }
}

struct HeaderActionButton: View {
    let title: String
    var systemImage: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
        }
        .buttonStyle(SettingsButtonStyle(isPrimary: true))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(title)
    }
}

struct StatusBadge: View {
    let message: String
    let tone: SettingsViewModel.StatusTone
    let isDirty: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusIcon)
                .font(.caption)
            Text(message.isEmpty ? (isDirty ? "未保存" : "就绪") : message)
                .lineLimit(1)
                .foregroundStyle(statusTextColor)
        }
        .font(.caption)
        .foregroundStyle(tone.color)
        .help(message.isEmpty ? "就绪" : message)
    }

    private var statusIcon: String {
        switch tone {
        case .error: return "exclamationmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .success: return isDirty ? "circle.fill" : "checkmark.circle"
        case .neutral: return isDirty ? "circle.fill" : "circle.dotted"
        }
    }

    private var statusTextColor: Color {
        switch tone {
        case .neutral, .success: return SettingsTheme.muted
        case .warning, .error: return tone.color
        }
    }
}

struct SaveConfigButton: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Button {
            viewModel.saveConfig()
        } label: {
            Label("保存配置", systemImage: "square.and.arrow.down")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(SettingsButtonStyle(isPrimary: true))
        .accessibilityLabel("保存配置")
        .keyboardShortcut("s", modifiers: [.command])
        .help("保存配置到磁盘（⌘S）")
    }
}

struct DesignPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
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
            .background(SettingsTheme.surface)
    }
}

struct SettingsHintBanner: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = SettingsTheme.accent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsTheme.ink)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(SettingsTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SettingsTheme.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(SettingsTheme.ink)
                .focused($isFocused)
                .accessibilityLabel(placeholder)
            Button {
                text = ""
                isFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(SettingsTheme.tertiary)
                    .frame(width: 16, height: 20)
            }
            .buttonStyle(.plain)
            .opacity(text.isEmpty ? 0 : 1)
            .disabled(text.isEmpty)
            .accessibilityHidden(text.isEmpty)
            .accessibilityLabel("清除搜索")
            .help("清除搜索")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(minWidth: 220, maxWidth: 360, minHeight: 36)
        .background(SettingsTheme.controlBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? SettingsTheme.accent : Color.clear, lineWidth: 1)
        )
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

struct SettingsTableHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SettingsTheme.muted)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(SettingsTheme.subtleFill)
    }
}

extension View {
    func settingsTableHeaderStyle() -> some View {
        modifier(SettingsTableHeaderStyle())
    }
}

struct FilterTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? SettingsTheme.ink : SettingsTheme.muted)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(
                    isSelected ? SettingsTheme.selectionFill : (isHovered ? SettingsTheme.subtleFill : Color.clear),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HoverableRowBackground: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? SettingsTheme.subtleFill : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    func hoverRowBackground() -> some View {
        modifier(HoverableRowBackground())
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
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(SettingsTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
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
            return SettingsTheme.controlBackgroundHover
        case .accent:
            return SettingsTheme.accent.opacity(0.12)
        case .destructive:
            return Color.red.opacity(0.1)
        }
    }

    var hoverStroke: Color {
        switch self {
        case .neutral:
            return Color.clear
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
                    .strokeBorder(stroke, lineWidth: 0.5)
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
            return Color.clear
        }
        return isHovered ? tone.hoverStroke : Color.clear
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
