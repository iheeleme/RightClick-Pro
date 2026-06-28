import Foundation

public enum SystemMaintenanceTask: String, Codable, Equatable {
    case installFinderExtension
    case restartFinder
    case repairFinderContextMenu
}

public struct SystemMaintenanceRequest: Codable, Equatable {
    public var task: SystemMaintenanceTask
    public var finderExtensionPath: String?
    public var finderExtensionBundleIdentifier: String

    public init(
        task: SystemMaintenanceTask,
        finderExtensionPath: String? = nil,
        finderExtensionBundleIdentifier: String = RightClickProConstants.finderExtensionBundleIdentifier
    ) {
        self.task = task
        self.finderExtensionPath = finderExtensionPath
        self.finderExtensionBundleIdentifier = finderExtensionBundleIdentifier
    }
}

public struct SystemMaintenanceResult: Codable, Equatable {
    public var didRegisterFinderExtension: Bool
    public var didEnableFinderExtension: Bool
    public var didRestartFinder: Bool
    public var messages: [String]
    public var errors: [String]

    public init(
        didRegisterFinderExtension: Bool = false,
        didEnableFinderExtension: Bool = false,
        didRestartFinder: Bool = false,
        messages: [String] = [],
        errors: [String] = []
    ) {
        self.didRegisterFinderExtension = didRegisterFinderExtension
        self.didEnableFinderExtension = didEnableFinderExtension
        self.didRestartFinder = didRestartFinder
        self.messages = messages
        self.errors = errors
    }

    public var isSuccess: Bool {
        errors.isEmpty
    }

    mutating func merge(_ other: SystemMaintenanceResult) {
        didRegisterFinderExtension = didRegisterFinderExtension || other.didRegisterFinderExtension
        didEnableFinderExtension = didEnableFinderExtension || other.didEnableFinderExtension
        didRestartFinder = didRestartFinder || other.didRestartFinder
        messages.append(contentsOf: other.messages)
        errors.append(contentsOf: other.errors)
    }
}

public struct SystemCommandResult: Equatable {
    public var terminationStatus: Int32
    public var standardOutput: String
    public var standardError: String

    public init(
        terminationStatus: Int32,
        standardOutput: String = "",
        standardError: String = ""
    ) {
        self.terminationStatus = terminationStatus
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool {
        terminationStatus == 0
    }
}

public protocol SystemCommandRunning {
    func run(_ executablePath: String, arguments: [String]) throws -> SystemCommandResult
}

public enum SystemMaintenanceError: Error, LocalizedError {
    case executableMissing(String)

    public var errorDescription: String? {
        switch self {
        case .executableMissing(let path):
            return "系统命令不存在：\(path)"
        }
    }
}

public struct ProcessSystemCommandRunner: SystemCommandRunning {
    public init() {}

    public func run(_ executablePath: String, arguments: [String]) throws -> SystemCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw SystemMaintenanceError.executableMissing(executablePath)
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return SystemCommandResult(
            terminationStatus: process.terminationStatus,
            standardOutput: output,
            standardError: error
        )
    }
}

public final class SystemMaintenanceService {
    private let commandRunner: SystemCommandRunning
    private let fileExists: (String) -> Bool

    public init(
        commandRunner: SystemCommandRunning = ProcessSystemCommandRunner(),
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.commandRunner = commandRunner
        self.fileExists = fileExists
    }

    public func perform(_ request: SystemMaintenanceRequest) -> SystemMaintenanceResult {
        switch request.task {
        case .installFinderExtension:
            return installFinderExtension(request)
        case .restartFinder:
            return restartFinder()
        case .repairFinderContextMenu:
            var result = installFinderExtension(request)
            guard result.isSuccess || result.didRegisterFinderExtension || result.didEnableFinderExtension else {
                return result
            }
            result.merge(restartFinder())
            return result
        }
    }

    private func installFinderExtension(_ request: SystemMaintenanceRequest) -> SystemMaintenanceResult {
        var result = SystemMaintenanceResult()

        guard let path = request.finderExtensionPath, fileExists(path) else {
            result.errors.append("找不到随 App 打包的 Finder Extension，请确认 App 已从 DMG 拖入 Applications 后再打开")
            return result
        }

        switch run("/usr/bin/pluginkit", arguments: ["-a", path]) {
        case .success(let outcome) where outcome.succeeded:
            result.didRegisterFinderExtension = true
            result.messages.append("Finder Extension 已注册到 PlugInKit")
        case .success(let outcome):
            result.errors.append("注册 Finder Extension 失败：\(diagnostic(from: outcome))")
            return result
        case .failure(let error):
            result.errors.append("注册 Finder Extension 失败：\(error.localizedDescription)")
            return result
        }

        switch run("/usr/bin/pluginkit", arguments: ["-e", "use", "-i", request.finderExtensionBundleIdentifier]) {
        case .success(let outcome) where outcome.succeeded:
            result.didEnableFinderExtension = true
            result.messages.append("Finder Extension 已请求启用")
        case .success(let outcome):
            result.errors.append("启用 Finder Extension 失败：\(diagnostic(from: outcome))")
        case .failure(let error):
            result.errors.append("启用 Finder Extension 失败：\(error.localizedDescription)")
        }

        return result
    }

    private func restartFinder() -> SystemMaintenanceResult {
        var result = SystemMaintenanceResult()

        switch run("/usr/bin/killall", arguments: ["Finder"]) {
        case .success(let outcome) where outcome.succeeded:
            Thread.sleep(forTimeInterval: 0.7)
            relaunchFinder(recordingInto: &result)
            result.didRestartFinder = true
            result.messages.append("Finder 已重启")
            return result
        case .success(let outcome):
            result.messages.append("killall Finder 未成功，尝试使用 AppleScript：\(diagnostic(from: outcome))")
        case .failure(let error):
            result.messages.append("killall Finder 不可用，尝试使用 AppleScript：\(error.localizedDescription)")
        }

        switch run("/usr/bin/osascript", arguments: ["-e", "tell application \"Finder\" to quit"]) {
        case .success(let outcome) where outcome.succeeded:
            Thread.sleep(forTimeInterval: 0.7)
            relaunchFinder(recordingInto: &result)
            result.didRestartFinder = true
            result.messages.append("Finder 已通过 AppleScript 重启")
        case .success(let outcome):
            result.errors.append("重启 Finder 失败：\(diagnostic(from: outcome))")
        case .failure(let error):
            result.errors.append("重启 Finder 失败：\(error.localizedDescription)")
        }

        return result
    }

    private func relaunchFinder(recordingInto result: inout SystemMaintenanceResult) {
        switch run("/usr/bin/open", arguments: ["-b", "com.apple.finder"]) {
        case .success(let outcome) where outcome.succeeded:
            result.messages.append("Finder 已重新打开")
        case .success(let outcome):
            result.messages.append("Finder 重启后自动拉起失败，可手动点 Dock 中的 Finder：\(diagnostic(from: outcome))")
        case .failure(let error):
            result.messages.append("Finder 重启后自动拉起失败，可手动点 Dock 中的 Finder：\(error.localizedDescription)")
        }
    }

    private func run(_ executablePath: String, arguments: [String]) -> Result<SystemCommandResult, Error> {
        do {
            return .success(try commandRunner.run(executablePath, arguments: arguments))
        } catch {
            return .failure(error)
        }
    }

    private func diagnostic(from result: SystemCommandResult) -> String {
        let detail = [result.standardError, result.standardOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        guard let detail else {
            return "退出码 \(result.terminationStatus)"
        }
        return "\(detail)（退出码 \(result.terminationStatus)）"
    }
}
