import Foundation

public protocol URLOpening {
    func open(_ url: URL) throws
}

public protocol DeveloperAppOpening {
    func open(_ entrypoint: DeveloperEntrypoint, targetURL: URL) throws
}

public enum AppOpeningError: Error, Equatable, LocalizedError {
    case appKitUnavailable
    case cannotOpen(String)

    public var errorDescription: String? {
        switch self {
        case .appKitUnavailable:
            return "当前环境不支持 AppKit 打开动作"
        case .cannotOpen(let target):
            return "无法打开：\(target)"
        }
    }
}

struct DeveloperWorkspaceOpenPlan: Equatable {
    var executableURL: URL
    var arguments: [String]
}

enum DeveloperAppOpenPlan: Equatable {
    case application(appURL: URL, targetURL: URL)
    case workspaceCommand(DeveloperWorkspaceOpenPlan)
}

enum DeveloperAppOpenPlanner {
    static func plan(
        for entrypoint: DeveloperEntrypoint,
        targetURL: URL,
        appURL: URL,
        fileManager: FileManager = .default
    ) -> DeveloperAppOpenPlan {
        let workspaceURL = workspaceURL(for: targetURL, fileManager: fileManager)
        if isTerminalApp(entrypoint: entrypoint, appURL: appURL) {
            return .application(appURL: appURL, targetURL: workspaceURL)
        }

        if let command = workspaceCommand(
            for: entrypoint,
            appURL: appURL,
            workspaceURL: workspaceURL,
            fileManager: fileManager
        ) {
            return .workspaceCommand(command)
        }
        return .application(appURL: appURL, targetURL: targetURL)
    }

    private static func workspaceURL(for targetURL: URL, fileManager: FileManager) -> URL {
        // 开发工具入口偏向打开工作区；选中文件时用父目录作为项目目录。
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return targetURL.deletingLastPathComponent()
        }
        return targetURL
    }

    private static func workspaceCommand(
        for entrypoint: DeveloperEntrypoint,
        appURL: URL,
        workspaceURL: URL,
        fileManager: FileManager
    ) -> DeveloperWorkspaceOpenPlan? {
        for candidate in workspaceCommandCandidates(for: entrypoint, appURL: appURL, workspaceURL: workspaceURL) {
            let executableURL = candidate.executableURL(relativeTo: appURL)
            guard fileManager.isExecutableFile(atPath: executableURL.path) else {
                continue
            }
            return DeveloperWorkspaceOpenPlan(executableURL: executableURL, arguments: candidate.arguments)
        }
        return nil
    }

    private static func workspaceCommandCandidates(
        for entrypoint: DeveloperEntrypoint,
        appURL: URL,
        workspaceURL: URL
    ) -> [DeveloperWorkspaceCommandCandidate] {
        let bundleIdentifier = entrypoint.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let appName = appURL.deletingPathExtension().lastPathComponent.lowercased()
        let title = entrypoint.title.lowercased()
        let identity = "\(bundleIdentifier) \(appName) \(title)"
        let workspacePath = workspaceURL.path

        // 候选命令来自公开 CLI 文档和常见 macOS app bundle 结构；运行时存在才使用。
        if bundleIdentifier == "com.openai.codex" || identity.contains("codex") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/codex", arguments: ["app", workspacePath])
            ]
        }

        if bundleIdentifier == "com.microsoft.vscode" || identity.contains("visual studio code") || identity.contains("vscode") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/app/bin/code", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier == "com.microsoft.vscodeinsiders" || identity.contains("code - insiders") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/app/bin/code-insiders", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier == "com.vscodium" || identity.contains("vscodium") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/app/bin/codium", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier == "com.todesktop.230313mzl4w4u92" || identity.contains("cursor") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/app/bin/cursor", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier == "com.exafunction.windsurf" || identity.contains("windsurf") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/app/bin/windsurf", arguments: [workspacePath])
            ]
        }

        if identity.contains("trae") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/app/bin/trae", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier == "dev.zed.zed" || identity.contains("zed") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/MacOS/cli", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/SharedSupport/bin/zed", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/MacOS/Zed", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "/usr/local/bin/zed", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "/opt/homebrew/bin/zed", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier.hasPrefix("com.jetbrains.") || isJetBrainsApp(identity) {
            return jetBrainsCommandCandidates(identity: identity, workspacePath: workspacePath)
        }

        if bundleIdentifier == "com.apple.dt.xcode" || identity.contains("xcode") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "/usr/bin/xed", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/MacOS/Xcode", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier.hasPrefix("com.sublimetext.") || identity.contains("sublime text") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/SharedSupport/bin/subl", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier == "com.macromates.textmate" || identity.contains("textmate") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/Resources/mate", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "/usr/local/bin/mate", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "/opt/homebrew/bin/mate", arguments: [workspacePath])
            ]
        }

        if bundleIdentifier == "com.panic.nova" || identity.contains("nova") {
            return [
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/SharedSupport/bin/nova", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "Contents/MacOS/Nova", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "/usr/local/bin/nova", arguments: [workspacePath]),
                DeveloperWorkspaceCommandCandidate(executablePath: "/opt/homebrew/bin/nova", arguments: [workspacePath])
            ]
        }

        return []
    }

    private static func isTerminalApp(entrypoint: DeveloperEntrypoint, appURL: URL) -> Bool {
        let bundleIdentifier = entrypoint.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let appName = appURL.deletingPathExtension().lastPathComponent.lowercased()
        let title = entrypoint.title.lowercased()
        let identity = "\(bundleIdentifier) \(appName) \(title)"
        return [
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "terminal",
            "iterm",
            "warp",
            "alacritty",
            "kitty"
        ].contains { identity.contains($0) }
    }

    private static func isJetBrainsApp(_ identity: String) -> Bool {
        [
            "intellij", "webstorm", "pycharm", "goland", "clion", "datagrip",
            "rider", "rubymine", "phpstorm", "appcode", "jetbrains"
        ].contains { identity.contains($0) }
    }

    private static func jetBrainsCommandCandidates(identity: String, workspacePath: String) -> [DeveloperWorkspaceCommandCandidate] {
        let commandNames: [(String, String)] = [
            ("webstorm", "webstorm"),
            ("pycharm", "pycharm"),
            ("goland", "goland"),
            ("clion", "clion"),
            ("datagrip", "datagrip"),
            ("rider", "rider"),
            ("rubymine", "rubymine"),
            ("phpstorm", "phpstorm"),
            ("appcode", "appcode"),
            ("rustrover", "rustrover"),
            ("fleet", "fleet"),
            ("intellij", "idea"),
            ("idea", "idea")
        ]
        var candidates = commandNames.compactMap { keyword, commandName -> DeveloperWorkspaceCommandCandidate? in
            guard identity.contains(keyword) else { return nil }
            return DeveloperWorkspaceCommandCandidate(
                executablePath: "Contents/MacOS/\(commandName)",
                arguments: [workspacePath]
            )
        }

        candidates.append(contentsOf: [
            DeveloperWorkspaceCommandCandidate(executablePath: "Contents/MacOS/idea", arguments: [workspacePath]),
            DeveloperWorkspaceCommandCandidate(executablePath: "Contents/MacOS/webstorm", arguments: [workspacePath]),
            DeveloperWorkspaceCommandCandidate(executablePath: "Contents/MacOS/pycharm", arguments: [workspacePath])
        ])
        candidates.append(
            contentsOf: commandNames.flatMap { _, commandName in
                [
                    DeveloperWorkspaceCommandCandidate(executablePath: "Contents/bin/\(commandName)", arguments: [workspacePath]),
                    DeveloperWorkspaceCommandCandidate(executablePath: "Contents/bin/\(commandName).sh", arguments: [workspacePath])
                ]
            }
        )
        return candidates
    }
}

private struct DeveloperWorkspaceCommandCandidate {
    var executablePath: String
    var arguments: [String]

    func executableURL(relativeTo appURL: URL) -> URL {
        executablePath.hasPrefix("/")
            ? URL(fileURLWithPath: executablePath)
            : appURL.appendingPathComponent(executablePath)
    }
}

public final class RecordingURLOpener: URLOpening, DeveloperAppOpening {
    public private(set) var openedURLs: [URL] = []
    public private(set) var openedApps: [(DeveloperEntrypoint, URL)] = []

    public init() {}

    public func open(_ url: URL) throws {
        openedURLs.append(url)
    }

    public func open(_ entrypoint: DeveloperEntrypoint, targetURL: URL) throws {
        openedApps.append((entrypoint, targetURL))
    }
}

#if canImport(AppKit)
import AppKit

public struct NSWorkspaceURLOpener: URLOpening, DeveloperAppOpening {
    public init() {}

    public func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw AppOpeningError.cannotOpen(url.path)
        }
    }

    public func open(_ entrypoint: DeveloperEntrypoint, targetURL: URL) throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entrypoint.bundleIdentifier) else {
            throw AppOpeningError.cannotOpen(entrypoint.bundleIdentifier)
        }

        switch DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: targetURL, appURL: appURL) {
        case .application(let appURL, let targetURL):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(
                [targetURL],
                withApplicationAt: appURL,
                configuration: configuration
            ) { _, _ in }
        case .workspaceCommand(let command):
            try runWorkspaceCommand(command)
        }
    }

    private func runWorkspaceCommand(_ command: DeveloperWorkspaceOpenPlan) throws {
        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw AppOpeningError.cannotOpen(command.executableURL.path)
        }
    }
}
#endif
