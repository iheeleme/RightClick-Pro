import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

enum AppMetadata {
    static let displayName = "RightClick Pro"
    static let releasesPageURL = URL(string: "https://github.com/iheeleme/RightClick-Pro/releases")!
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/iheeleme/RightClick-Pro/releases/latest")!

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "0.0.0-dev"
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = currentVersion
        let build = (info["CFBundleVersion"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        guard let build, build != version else {
            return "版本 \(version)"
        }
        return "版本 \(version) (\(build))"
    }
}

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "com.iheeleme.rightclickpro.settings.theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct RightClickProAppPreview: App {
    @NSApplicationDelegateAdaptor(RightClickProAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = SettingsViewModel.bootstrap()
    @AppStorage(AppThemePreference.storageKey) private var themeRawValue = AppThemePreference.system.rawValue

    private var themePreference: AppThemePreference {
        AppThemePreference(rawValue: themeRawValue) ?? .system
    }

    var body: some Scene {
        MenuBarExtra(AppMetadata.displayName, systemImage: "contextualmenu.and.cursorarrow") {
            MenuBarContentView(viewModel: viewModel)
        }

        Window("\(AppMetadata.displayName) 设置", id: "settings") {
            SettingsRootView(viewModel: viewModel)
                .frame(minWidth: 1180, idealWidth: 1448, maxWidth: .infinity, minHeight: 760, idealHeight: 980, maxHeight: .infinity)
                .preferredColorScheme(themePreference.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class RightClickProAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        applyApplicationMenuTitle()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyApplicationMenuTitle()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func applyApplicationMenuTitle() {
        NSApplication.shared.mainMenu?.items.first?.title = AppMetadata.displayName
    }
}
