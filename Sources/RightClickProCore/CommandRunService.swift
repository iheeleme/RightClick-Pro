import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum CommandRunStatus: String, Codable, Equatable {
    case preparing
    case running
    case succeeded
    case failed
    case timedOut
    case stopped
    case error

    public var isTerminal: Bool {
        switch self {
        case .preparing, .running:
            return false
        case .succeeded, .failed, .timedOut, .stopped, .error:
            return true
        }
    }
}

public enum CommandRunOutputStream: String, Codable, Equatable {
    case system
    case stdout
    case stderr
}

public struct CommandRunOutputChunk: Codable, Equatable, Identifiable {
    public var id: Int
    public var stream: CommandRunOutputStream
    public var text: String
    public var createdAt: Date

    public init(id: Int, stream: CommandRunOutputStream, text: String, createdAt: Date = Date()) {
        self.id = id
        self.stream = stream
        self.text = text
        self.createdAt = createdAt
    }
}

public struct CommandRunSnapshot: Codable, Equatable, Identifiable {
    public var id: UUID
    public var actionID: String
    public var title: String
    public var command: String
    public var workingDirectory: String
    public var sourcePaths: [String]
    public var status: CommandRunStatus
    public var outputChunks: [CommandRunOutputChunk]
    public var exitCode: Int32?
    public var startedAt: Date?
    public var finishedAt: Date?
    public var durationMilliseconds: Int?
    public var errorMessage: String?

    public init(
        id: UUID,
        actionID: String,
        title: String = "命令运行",
        command: String = "",
        workingDirectory: String = "",
        sourcePaths: [String] = [],
        status: CommandRunStatus = .preparing,
        outputChunks: [CommandRunOutputChunk] = [],
        exitCode: Int32? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        durationMilliseconds: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.actionID = actionID
        self.title = title
        self.command = command
        self.workingDirectory = workingDirectory
        self.sourcePaths = sourcePaths
        self.status = status
        self.outputChunks = outputChunks
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMilliseconds = durationMilliseconds
        self.errorMessage = errorMessage
    }

    public var combinedOutput: String {
        outputChunks.map(\.text).joined()
    }
}

public enum CommandRunServiceError: Error, Equatable, LocalizedError {
    case runNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .runNotFound(let id):
            return "找不到命令运行记录：\(id.uuidString)"
        }
    }
}

public final class CommandRunService {
    private let paths: RightClickProStoragePaths
    private let configProvider: RightClickProConfigProviding
    private let operationLog: OperationLogging
    private let secretStore: CommandSecretStoring
    private let bookmarkResolver: BookmarkResolving
    private let fileManager: FileManager
    private let lock = NSLock()

    private var snapshots: [UUID: CommandRunSnapshot] = [:]
    private var processes: [UUID: Process] = [:]
    private var timeoutWorkItems: [UUID: DispatchWorkItem] = [:]
    private var stopRequestedRunIDs = Set<UUID>()
    private var timedOutRunIDs = Set<UUID>()
    private var scopedAccessURLs: [UUID: [URL]] = [:]

    public init(
        paths: RightClickProStoragePaths,
        configProvider: RightClickProConfigProviding? = nil,
        operationLog: OperationLogging? = nil,
        secretStore: CommandSecretStoring = KeychainCommandSecretStore(),
        bookmarkResolver: BookmarkResolving = SecurityScopedBookmarkResolver(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.configProvider = configProvider ?? FileBackedRightClickProConfigProvider(paths: paths)
        self.operationLog = operationLog ?? JSONLineOperationLog(url: paths.operationLogURL, fileManager: fileManager)
        self.secretStore = secretStore
        self.bookmarkResolver = bookmarkResolver
        self.fileManager = fileManager
    }

    public func start(_ request: PendingCommandRunRequest) -> CommandRunSnapshot {
        if let existing = try? status(for: request.id), !existing.status.isTerminal {
            return existing
        }

        do {
            let prepared = try prepareCommandRun(request)
            let startedAt = Date()
            var snapshot = CommandRunSnapshot(
                id: request.id,
                actionID: request.actionID,
                title: prepared.template.title,
                command: prepared.command,
                workingDirectory: prepared.workingDirectory.path,
                sourcePaths: request.context.selectedItems.map(\.path),
                status: .running,
                startedAt: startedAt
            )
            snapshot.outputChunks.append(
                CommandRunOutputChunk(
                    id: 1,
                    stream: .system,
                    text: "$ cd \(prepared.workingDirectory.path)\n$ \(prepared.command)\n\n",
                    createdAt: startedAt
                )
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", prepared.command]
            process.currentDirectoryURL = prepared.workingDirectory
            process.environment = prepared.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.readAvailableOutput(from: handle, runID: request.id, stream: .stdout)
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.readAvailableOutput(from: handle, runID: request.id, stream: .stderr)
            }

            process.terminationHandler = { [weak self] process in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                self?.finish(runID: request.id, exitCode: process.terminationStatus)
            }

            try withLock {
                snapshots[request.id] = snapshot
                processes[request.id] = process
                scopedAccessURLs[request.id] = prepared.scopedAccessURLs
                try saveSnapshot(snapshot)
            }

            do {
                try process.run()
                scheduleTimeout(runID: request.id, seconds: prepared.template.timeoutSeconds)
                return snapshot
            } catch {
                cleanupRun(runID: request.id)
                throw error
            }
        } catch {
            return failToStart(request, error: error)
        }
    }

    public func status(for runID: UUID) throws -> CommandRunSnapshot {
        try withLock {
            if let snapshot = snapshots[runID] {
                return snapshot
            }
            let snapshot = try snapshotStore(for: runID).loadRequired()
            snapshots[runID] = snapshot
            return snapshot
        }
    }

    public func stop(runID: UUID) throws -> CommandRunSnapshot {
        var processToStop: Process?
        withLock {
            stopRequestedRunIDs.insert(runID)
            processToStop = processes[runID]
        }

        appendOutput("\n用户请求停止命令...\n", runID: runID, stream: .system)
        processToStop?.terminate()

        if let processToStop {
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak processToStop] in
                guard let processToStop, processToStop.isRunning else {
                    return
                }
                #if canImport(Darwin)
                kill(processToStop.processIdentifier, SIGKILL)
                #endif
            }
        }

        return try status(for: runID)
    }

    private struct PreparedCommandRun {
        var template: CommandTemplate
        var command: String
        var workingDirectory: URL
        var environment: [String: String]
        var scopedAccessURLs: [URL]
    }

    private func prepareCommandRun(_ request: PendingCommandRunRequest) throws -> PreparedCommandRun {
        let config = try configProvider.loadConfig()
        let bookmarks = try configProvider.loadBookmarkCatalog()
        guard
            let action = config.actions.first(where: { $0.id == request.actionID }),
            let templateID = action.payload.commandTemplateID,
            let template = config.commandTemplates.first(where: { $0.id == templateID })
        else {
            throw CommandTemplateError.missingCommandTemplate(request.actionID)
        }

        let workingDirectory = CommandTemplateVariableResolver.workingDirectory(for: template, context: request.context)
        let command = try CommandTemplateVariableResolver.interpolatedCommand(template: template, context: request.context)
        let environment = try commandEnvironment(for: template)
        let scopedURLs = scopedAccessURLs(for: workingDirectory, bookmarks: bookmarks)

        do {
            guard isReadableDirectory(workingDirectory) else {
                throw CommandTemplateError.inaccessibleWorkingDirectory(workingDirectory.path)
            }

            return PreparedCommandRun(
                template: template,
                command: command,
                workingDirectory: workingDirectory,
                environment: environment,
                scopedAccessURLs: scopedURLs
            )
        } catch {
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func commandEnvironment(for template: CommandTemplate) throws -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(path):\(defaultPath)"
        } else {
            environment["PATH"] = defaultPath
        }

        for variable in template.environment {
            guard CommandTemplateVariableResolver.validateEnvironmentName(variable.name) else {
                throw CommandTemplateError.invalidEnvironmentName(variable.name)
            }

            if variable.isSensitive {
                guard
                    let reference = variable.secretReference,
                    let value = try secretStore.load(reference: reference)
                else {
                    throw CommandTemplateError.missingSecret(variable.name)
                }
                environment[variable.name] = value
            } else {
                environment[variable.name] = variable.value ?? ""
            }
        }
        return environment
    }

    private func scopedAccessURLs(for workingDirectory: URL, bookmarks: DirectoryBookmarkCatalog) -> [URL] {
        bookmarks.bookmarks.compactMap { bookmark in
            guard let url = try? bookmarkResolver.resolve(bookmark),
                  contains(workingDirectory, in: url),
                  url.startAccessingSecurityScopedResource()
            else {
                return nil
            }
            return url
        }
    }

    private func isReadableDirectory(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        do {
            _ = try fileManager.contentsOfDirectory(atPath: directory.path)
            return true
        } catch {
            return false
        }
    }

    private func readAvailableOutput(from handle: FileHandle, runID: UUID, stream: CommandRunOutputStream) {
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return
        }
        appendOutput(text, runID: runID, stream: stream)
    }

    private func appendOutput(_ text: String, runID: UUID, stream: CommandRunOutputStream) {
        do {
            try withLock {
                guard var snapshot = try? loadSnapshotForMutation(runID) else {
                    return
                }
                snapshot.outputChunks.append(
                    CommandRunOutputChunk(
                        id: (snapshot.outputChunks.map(\.id).max() ?? 0) + 1,
                        stream: stream,
                        text: text
                    )
                )
                snapshots[runID] = snapshot
                try saveSnapshot(snapshot)
            }
        } catch {
            // Output persistence is best effort; the process lifecycle still finishes.
        }
    }

    private func scheduleTimeout(runID: UUID, seconds: Int) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var processToStop: Process?
            self.withLock {
                processToStop = self.processes[runID]
                if processToStop == nil {
                    self.timeoutWorkItems[runID] = nil
                }
                if processToStop?.isRunning == true {
                    self.timedOutRunIDs.insert(runID)
                }
            }
            guard let processToStop, processToStop.isRunning else {
                return
            }
            self.appendOutput("\n命令超过 \(seconds) 秒，正在停止...\n", runID: runID, stream: .system)
            processToStop.terminate()
        }

        let shouldSchedule = withLock {
            guard processes[runID] != nil else {
                return false
            }
            timeoutWorkItems[runID] = workItem
            return true
        }
        guard shouldSchedule else {
            return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds), execute: workItem)
    }

    private func finish(runID: UUID, exitCode: Int32) {
        let snapshot: CommandRunSnapshot?
        let scopedURLs: [URL]

        do {
            snapshot = try withLock {
                timeoutWorkItems[runID]?.cancel()
                timeoutWorkItems[runID] = nil
                processes[runID] = nil

                guard var snapshot = try? loadSnapshotForMutation(runID) else {
                    return nil
                }

                let finishedAt = Date()
                snapshot.exitCode = exitCode
                snapshot.finishedAt = finishedAt
                snapshot.durationMilliseconds = durationMilliseconds(startedAt: snapshot.startedAt, finishedAt: finishedAt)

                if timedOutRunIDs.remove(runID) != nil {
                    snapshot.status = .timedOut
                } else if stopRequestedRunIDs.remove(runID) != nil {
                    snapshot.status = .stopped
                } else if exitCode == 0 {
                    snapshot.status = .succeeded
                } else {
                    snapshot.status = .failed
                }

                let durationText = formattedDuration(milliseconds: snapshot.durationMilliseconds)
                snapshot.outputChunks.append(
                    CommandRunOutputChunk(
                        id: (snapshot.outputChunks.map(\.id).max() ?? 0) + 1,
                        stream: .system,
                        text: "\n退出码：\(exitCode) · 耗时：\(durationText)\n",
                        createdAt: finishedAt
                    )
                )
                snapshots[runID] = snapshot
                try saveSnapshot(snapshot)
                return snapshot
            }
        } catch {
            return
        }

        scopedURLs = withLock {
            let urls = scopedAccessURLs[runID] ?? []
            scopedAccessURLs[runID] = nil
            return urls
        }
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }

        if let snapshot {
            logCompletion(snapshot)
        }
    }

    private func failToStart(_ request: PendingCommandRunRequest, error: Error) -> CommandRunSnapshot {
        let message = FullDiskAccessAdvisor.userFacingMessage(for: error)
        let finishedAt = Date()
        var snapshot = CommandRunSnapshot(
            id: request.id,
            actionID: request.actionID,
            workingDirectory: request.context.targetDirectory.path,
            sourcePaths: request.context.selectedItems.map(\.path),
            status: .error,
            finishedAt: finishedAt,
            errorMessage: message
        )
        snapshot.outputChunks = [
            CommandRunOutputChunk(
                id: 1,
                stream: .system,
                text: "运行失败：\(message)\n",
                createdAt: finishedAt
            )
        ]

        do {
            try withLock {
                snapshots[request.id] = snapshot
                try saveSnapshot(snapshot)
            }
        } catch {}

        try? operationLog.append(
            OperationRecord(
                actionID: request.actionID,
                kind: .runCommand,
                status: .failure,
                sourcePaths: request.context.selectedItems.map(\.path),
                destinationPaths: [request.context.targetDirectory.path],
                message: message
            )
        )
        cleanupRun(runID: request.id)
        return snapshot
    }

    private func logCompletion(_ snapshot: CommandRunSnapshot) {
        let recordStatus: OperationRecordStatus
        switch snapshot.status {
        case .succeeded:
            recordStatus = .success
        case .stopped:
            recordStatus = .cancelled
        default:
            recordStatus = .failure
        }

        try? operationLog.append(
            OperationRecord(
                actionID: snapshot.actionID,
                kind: .runCommand,
                status: recordStatus,
                sourcePaths: snapshot.sourcePaths,
                destinationPaths: [snapshot.workingDirectory],
                message: String(snapshot.combinedOutput.suffix(4000)).trimmingCharacters(in: .whitespacesAndNewlines),
                commandExitCode: snapshot.exitCode.map(Int.init),
                durationMilliseconds: snapshot.durationMilliseconds
            )
        )
    }

    private func cleanupRun(runID: UUID) {
        let urls = withLock { () -> [URL] in
            processes[runID] = nil
            timeoutWorkItems[runID]?.cancel()
            timeoutWorkItems[runID] = nil
            stopRequestedRunIDs.remove(runID)
            timedOutRunIDs.remove(runID)
            let urls = scopedAccessURLs[runID] ?? []
            scopedAccessURLs[runID] = nil
            return urls
        }
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    private func loadSnapshotForMutation(_ runID: UUID) throws -> CommandRunSnapshot {
        if let snapshot = snapshots[runID] {
            return snapshot
        }
        let snapshot = try snapshotStore(for: runID).loadRequired()
        snapshots[runID] = snapshot
        return snapshot
    }

    private func saveSnapshot(_ snapshot: CommandRunSnapshot) throws {
        try snapshotStore(for: snapshot.id).save(snapshot)
    }

    private func snapshotStore(for runID: UUID) -> JSONFileStore<CommandRunSnapshot> {
        JSONFileStore<CommandRunSnapshot>(
            url: paths.commandRunStateDirectoryURL.appendingPathComponent("\(runID.uuidString).json"),
            fileManager: fileManager
        )
    }

    private func durationMilliseconds(startedAt: Date?, finishedAt: Date) -> Int? {
        guard let startedAt else {
            return nil
        }
        return Int(finishedAt.timeIntervalSince(startedAt) * 1000)
    }

    private func formattedDuration(milliseconds: Int?) -> String {
        guard let milliseconds else {
            return "—"
        }
        return String(format: "%.1fs", Double(milliseconds) / 1000)
    }

    private func contains(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = normalizedPath(candidate)
        let rootPath = normalizedPath(root)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.count > 1 else {
            return path
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
