import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum CommandRunStatus: String, Codable, Equatable, Sendable {
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

public enum CommandRunOutputStream: String, Codable, Equatable, Hashable, Sendable {
    case system
    case stdout
    case stderr
}

public struct CommandRunOutputChunk: Codable, Equatable, Identifiable, Sendable {
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

public struct CommandRunSnapshot: Codable, Equatable, Identifiable, Sendable {
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

public enum CommandRunServiceError: Error, Equatable, LocalizedError, Sendable {
    case runNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .runNotFound(let id):
            return "找不到命令运行记录：\(id.uuidString)"
        }
    }
}

// 运行状态由 lock 保护；outputLock 串行化 pipe 读取与退出时的排空，避免并发消费同一句柄。
public final class CommandRunService: @unchecked Sendable {
    private let paths: RightClickProStoragePaths
    private let configProvider: RightClickProConfigProviding
    private let operationLog: OperationLogging
    private let secretStore: CommandSecretStoring
    private let bookmarkResolver: BookmarkResolving
    private let fileManager: FileManager
    private let lock = NSLock()
    private let outputLock = NSLock()

    private var snapshots: [UUID: CommandRunSnapshot] = [:]
    private var pendingTerminalWrites = Set<UUID>()
    private var processes: [UUID: Process] = [:]
    private var timeoutWorkItems: [UUID: DispatchWorkItem] = [:]
    private var stopRequestedRunIDs = Set<UUID>()
    private var timedOutRunIDs = Set<UUID>()
    private var scopedAccessURLs: [UUID: [URL]] = [:]
    private var outputBuffers: [UUID: [CommandRunOutputStream: Data]] = [:]
    private var processGroupIDs: [UUID: Int32] = [:]
    private var runOwnershipHandles: [UUID: FileHandle] = [:]

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
        recoverInterruptedRuns()
    }

    public func start(_ request: PendingCommandRunRequest) -> CommandRunSnapshot {
        if withLock({ snapshots[request.id] != nil }) || fileManager.fileExists(atPath: snapshotStore(for: request.id).url.path) {
            do { return try status(for: request.id) }
            catch {
                return CommandRunSnapshot(id: request.id, actionID: request.actionID, status: .error,
                                          errorMessage: "读取已有运行结果失败：\(error.localizedDescription)")
            }
        }

        do {
            // App 和 Finder 各有一份 XPC 服务，文件锁标识真正持有本次运行的实例。
            guard let ownership = try acquireRunOwnership(request.id) else {
                return (try? status(for: request.id)) ?? CommandRunSnapshot(
                    id: request.id, actionID: request.actionID, status: .preparing
                )
            }
            withLock { runOwnershipHandles[request.id] = ownership }
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
                self?.finishOutputAndRun(
                    runID: request.id,
                    stdout: stdout.fileHandleForReading,
                    stderr: stderr.fileHandleForReading,
                    exitCode: process.terminationStatus
                )
            }

            try withLock {
                snapshots[request.id] = snapshot
                processes[request.id] = process
                scopedAccessURLs[request.id] = prepared.scopedAccessURLs
                try saveSnapshot(snapshot)
            }

            do {
                try process.run()
                let processGroupID = configureProcessGroup(process)
                withLock {
                    processGroupIDs[request.id] = processGroupID
                }
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
            if let snapshot = snapshots[runID], snapshot.status.isTerminal || runOwnershipHandles[runID] != nil {
                return snapshot
            }
            var snapshot = try snapshotStore(for: runID).loadRequired()
            if !snapshot.status.isTerminal, let ownership = try acquireRunOwnership(runID) {
                defer { try? ownership.close() }
                // 锁获取前所有者可能刚好结束；重读后再决定是否恢复。
                snapshot = try snapshotStore(for: runID).loadRequired()
                if !snapshot.status.isTerminal {
                    snapshot = interruptedSnapshot(snapshot)
                    try saveSnapshot(snapshot)
                    logCompletion(snapshot)
                }
            }
            snapshots[runID] = snapshot
            return snapshot
        }
    }

    public func stop(runID: UUID) throws -> CommandRunSnapshot {
        let processToStop: Process? = withLock {
            guard let process = processes[runID] else {
                return nil
            }
            stopRequestedRunIDs.insert(runID)
            return process
        }
        guard let processToStop else {
            return try status(for: runID)
        }

        appendOutput("\n用户请求停止命令...\n", runID: runID, stream: .system)
        processToStop.terminate()
        scheduleForceTermination(runID: runID, process: processToStop, after: 2)

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
        outputLock.lock()
        defer { outputLock.unlock() }
        guard withLock({ processes[runID] != nil }), let data = availableOutputData(from: handle) else {
            return
        }
        if data.isEmpty {
            handle.readabilityHandler = nil
            flushOutput(runID: runID, stream: stream)
            return
        }
        consumeOutputData(data, runID: runID, stream: stream)
    }

    private func finishOutputAndRun(runID: UUID, stdout: FileHandle, stderr: FileHandle, exitCode: Int32) {
        outputLock.lock()
        defer { outputLock.unlock() }
        stdout.readabilityHandler = nil
        stderr.readabilityHandler = nil
        drainOutput(from: stdout, runID: runID, stream: .stdout)
        drainOutput(from: stderr, runID: runID, stream: .stderr)
        finish(runID: runID, exitCode: exitCode)
    }

    private func drainOutput(from handle: FileHandle, runID: UUID, stream: CommandRunOutputStream) {
        while let data = availableOutputData(from: handle), !data.isEmpty {
            consumeOutputData(data, runID: runID, stream: stream)
        }
        flushOutput(runID: runID, stream: stream)
    }

    private func availableOutputData(from handle: FileHandle) -> Data? {
        #if canImport(Darwin)
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 0) > 0 else {
            return nil
        }
        #endif
        return handle.availableData
    }

    private func consumeOutputData(_ data: Data, runID: UUID, stream: CommandRunOutputStream) {
        guard !data.isEmpty else {
            return
        }

        let text: String? = withLock {
            var buffers = outputBuffers[runID] ?? [:]
            var buffer = buffers[stream] ?? Data()
            buffer.append(data)

            let completeLength = completeUTF8PrefixLength(in: buffer)
            guard completeLength > 0 else {
                buffers[stream] = buffer
                outputBuffers[runID] = buffers
                return nil
            }

            let completeData = Data(buffer.prefix(completeLength))
            buffer.removeFirst(completeLength)
            buffers[stream] = buffer
            outputBuffers[runID] = buffers
            return String(decoding: completeData, as: UTF8.self)
        }

        if let text, !text.isEmpty {
            appendOutput(text, runID: runID, stream: stream)
        }
    }

    private func flushOutput(runID: UUID, stream: CommandRunOutputStream) {
        let data: Data? = withLock {
            guard var buffers = outputBuffers[runID], let buffer = buffers.removeValue(forKey: stream) else {
                return nil
            }
            outputBuffers[runID] = buffers.isEmpty ? nil : buffers
            return buffer.isEmpty ? nil : buffer
        }
        guard let data else {
            return
        }
        appendOutput(String(decoding: data, as: UTF8.self), runID: runID, stream: stream)
    }

    private func completeUTF8PrefixLength(in data: Data) -> Int {
        let bytes = Array(data)
        guard !bytes.isEmpty else {
            return 0
        }

        var index = bytes.count - 1
        var continuationCount = 0
        while index >= 0, bytes[index] & 0xC0 == 0x80 {
            continuationCount += 1
            index -= 1
        }

        guard index >= 0 else {
            return bytes.count
        }

        let lead = bytes[index]
        let expectedContinuationCount: Int
        switch lead {
        case 0xC2...0xDF:
            expectedContinuationCount = 1
        case 0xE0...0xEF:
            expectedContinuationCount = 2
        case 0xF0...0xF4:
            expectedContinuationCount = 3
        default:
            expectedContinuationCount = 0
        }

        if expectedContinuationCount > continuationCount {
            return index
        }
        return bytes.count
    }

    private func appendOutput(_ text: String, runID: UUID, stream: CommandRunOutputStream) {
        do {
            try withLock {
                guard var snapshot = try? loadSnapshotForMutation(runID) else {
                    return
                }
                guard !snapshot.status.isTerminal else {
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
            self.scheduleForceTermination(runID: runID, process: processToStop, after: 1)
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

    private func configureProcessGroup(_ process: Process) -> Int32? {
        #if canImport(Darwin)
        let processID = process.processIdentifier
        if getpgid(processID) == processID || setpgid(processID, processID) == 0 {
            return processID
        }
        #endif
        return nil
    }

    private func scheduleForceTermination(runID: UUID, process: Process, after seconds: Int) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self, weak process] in
            guard let self, let process else {
                return
            }
            self.withLock {
                guard self.processes[runID] === process, process.isRunning else {
                    return
                }
                #if canImport(Darwin)
                if let groupID = self.processGroupIDs[runID], groupID > 1 {
                    kill(-groupID, SIGKILL)
                } else {
                    kill(process.processIdentifier, SIGKILL)
                }
                #endif
            }
        }
    }

    private func recoverInterruptedRuns() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: paths.commandRunStateDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where url.pathExtension == "json" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            // 初始化尽力恢复；读取失败仍由后续 status 调用向客户端报告。
            _ = try? status(for: id)
        }
    }

    private func interruptedSnapshot(_ saved: CommandRunSnapshot) -> CommandRunSnapshot {
        var snapshot = saved
        let finishedAt = Date()
        let message = "命令运行服务已中断，原进程状态无法恢复，运行结果未知。"
        snapshot.status = .error
        snapshot.finishedAt = finishedAt
        snapshot.durationMilliseconds = durationMilliseconds(startedAt: snapshot.startedAt, finishedAt: finishedAt)
        snapshot.errorMessage = message
        snapshot.outputChunks.append(CommandRunOutputChunk(
            id: (snapshot.outputChunks.map(\.id).max() ?? 0) + 1,
            stream: .system, text: "\n运行中断：\(message)\n", createdAt: finishedAt
        ))
        return snapshot
    }

    private func acquireRunOwnership(_ runID: UUID) throws -> FileHandle? {
        try fileManager.createDirectory(at: paths.commandRunStateDirectoryURL, withIntermediateDirectories: true)
        let lockURL = paths.commandRunStateDirectoryURL.appendingPathComponent("\(runID.uuidString).lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            if code == EWOULDBLOCK {
                return nil
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private func releaseRunOwnership(_ runID: UUID) {
        let handle = withLock { () -> FileHandle? in
            guard !pendingTerminalWrites.contains(runID) else { return nil }
            return runOwnershipHandles.removeValue(forKey: runID)
        }
        try? handle?.close()
    }

    private func finish(runID: UUID, exitCode: Int32) {
        defer { cleanupRun(runID: runID) }
        let snapshot: CommandRunSnapshot? = withLock {
            timeoutWorkItems[runID]?.cancel()
            timeoutWorkItems[runID] = nil
            processes[runID] = nil
            processGroupIDs[runID] = nil
            outputBuffers[runID] = nil

            guard var snapshot = try? loadSnapshotForMutation(runID) else {
                return nil
            }

            let finishedAt = Date()
            snapshot.exitCode = exitCode
            snapshot.finishedAt = finishedAt
            snapshot.durationMilliseconds = durationMilliseconds(startedAt: snapshot.startedAt, finishedAt: finishedAt)

            let timedOut = timedOutRunIDs.remove(runID) != nil
            let stopped = stopRequestedRunIDs.remove(runID) != nil
            if timedOut {
                snapshot.status = .timedOut
            } else if stopped {
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
            persistTerminalSnapshot(&snapshot)
            return snapshot
        }

        if let snapshot {
            logCompletion(snapshot)
        }
    }

    // 调用者持有 lock。保存失败保留真实终态和运行锁，防止其他实例误判为遗留 running。
    private func persistTerminalSnapshot(_ snapshot: inout CommandRunSnapshot) {
        do {
            try saveSnapshot(snapshot)
        } catch {
            let message = "运行结果保存失败，将自动重试：\(error.localizedDescription)"
            snapshot.errorMessage = [snapshot.errorMessage, message].compactMap { $0 }.joined(separator: "\n")
            snapshot.outputChunks.append(CommandRunOutputChunk(
                id: (snapshot.outputChunks.map(\.id).max() ?? 0) + 1,
                stream: .system, text: "\n\(message)\n"
            ))
            snapshots[snapshot.id] = snapshot
            if pendingTerminalWrites.insert(snapshot.id).inserted {
                scheduleTerminalWriteRetry(snapshot.id)
            }
        }
    }

    private func scheduleTerminalWriteRetry(_ runID: UUID) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            let retry = self.withLock { () -> Bool in
                guard self.pendingTerminalWrites.contains(runID), let snapshot = self.snapshots[runID] else { return false }
                do {
                    try self.saveSnapshot(snapshot)
                    self.pendingTerminalWrites.remove(runID)
                    try? self.runOwnershipHandles.removeValue(forKey: runID)?.close()
                    return false
                } catch {
                    return true
                }
            }
            if retry { self.scheduleTerminalWriteRetry(runID) }
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

        withLock {
            snapshots[request.id] = snapshot
            persistTerminalSnapshot(&snapshot)
        }

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
            processGroupIDs[runID] = nil
            timeoutWorkItems[runID]?.cancel()
            timeoutWorkItems[runID] = nil
            stopRequestedRunIDs.remove(runID)
            timedOutRunIDs.remove(runID)
            outputBuffers[runID] = nil
            let urls = scopedAccessURLs[runID] ?? []
            scopedAccessURLs[runID] = nil
            return urls
        }
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
        releaseRunOwnership(runID)
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
