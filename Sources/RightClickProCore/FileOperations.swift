import Foundation

public enum FileOperationType: String, Codable, Equatable, Sendable {
    case move
    case copy
    case createFile
}

public struct FileConflict: Equatable, Sendable {
    public var sourceURL: URL?
    public var proposedDestinationURL: URL
    public var operation: FileOperationType

    public init(sourceURL: URL?, proposedDestinationURL: URL, operation: FileOperationType) {
        self.sourceURL = sourceURL
        self.proposedDestinationURL = proposedDestinationURL
        self.operation = operation
    }
}

public enum FileConflictResolution: Equatable, Sendable {
    case replace
    case keepBoth
    case cancel
}

public protocol FileConflictResolving {
    func resolve(_ conflict: FileConflict) throws -> FileConflictResolution
}

public struct FixedConflictResolver: FileConflictResolving {
    private let resolution: FileConflictResolution

    public init(_ resolution: FileConflictResolution = .keepBoth) {
        self.resolution = resolution
    }

    public func resolve(_ conflict: FileConflict) throws -> FileConflictResolution {
        resolution
    }
}

public enum FileOperationError: Error, Equatable, LocalizedError, Sendable {
    case missingSelection
    case invalidFileName(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingSelection:
            return "没有选中文件或文件夹"
        case .invalidFileName(let name):
            return "文件名无效：\(name)"
        case .cancelled:
            return "操作已取消"
        }
    }
}

public struct FileOperationOutcome: Equatable, Sendable {
    public var sourceURL: URL?
    public var destinationURL: URL
    public var operation: FileOperationType

    public init(sourceURL: URL?, destinationURL: URL, operation: FileOperationType) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.operation = operation
    }
}

// 保留原始错误域和错误码，让调用方继续提供权限指引。
public struct FileOperationFailure: Error, Equatable, LocalizedError, Sendable {
    public var sourceURL: URL
    public var operation: FileOperationType
    public var message: String
    public var errorDomain: String
    public var errorCode: Int
    public var isCancellation: Bool

    public init(sourceURL: URL, operation: FileOperationType, error: Error) {
        let nsError = error as NSError
        self.sourceURL = sourceURL
        self.operation = operation
        self.message = nsError.localizedDescription
        self.errorDomain = nsError.domain
        self.errorCode = nsError.code
        self.isCancellation = (error as? FileOperationError) == .cancelled
    }

    public init(
        sourceURL: URL,
        operation: FileOperationType,
        message: String,
        errorDomain: String = NSCocoaErrorDomain,
        errorCode: Int = 0,
        isCancellation: Bool = false
    ) {
        self.sourceURL = sourceURL
        self.operation = operation
        self.message = message
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.isCancellation = isCancellation
    }

    public var errorDescription: String? { message }

    public var asNSError: NSError {
        NSError(
            domain: errorDomain,
            code: errorCode,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

public struct FileOperationBatchResult: Equatable, Sendable {
    public var completed: [FileOperationOutcome]
    public var remainingSourceURLs: [URL]
    public var failures: [FileOperationFailure]

    public init(
        completed: [FileOperationOutcome] = [],
        remainingSourceURLs: [URL] = [],
        failures: [FileOperationFailure] = []
    ) {
        self.completed = completed
        self.remainingSourceURLs = remainingSourceURLs
        self.failures = failures
    }

    public var succeeded: Bool { failures.isEmpty }
}

public final class FileOperationService {
    private let fileManager: FileManager
    private let conflictResolver: FileConflictResolving

    public init(
        fileManager: FileManager = .default,
        conflictResolver: FileConflictResolving = FixedConflictResolver(.keepBoth)
    ) {
        self.fileManager = fileManager
        self.conflictResolver = conflictResolver
    }

    public func move(_ sourceURLs: [URL], to destinationDirectory: URL) throws -> [FileOperationOutcome] {
        let result = try moveBatch(sourceURLs, to: destinationDirectory)
        if let failure = result.failures.first {
            if failure.isCancellation { throw FileOperationError.cancelled }
            throw failure.asNSError
        }
        return result.completed
    }

    public func copy(_ sourceURLs: [URL], to destinationDirectory: URL) throws -> [FileOperationOutcome] {
        let result = try copyBatch(sourceURLs, to: destinationDirectory)
        if let failure = result.failures.first {
            if failure.isCancellation { throw FileOperationError.cancelled }
            throw failure.asNSError
        }
        return result.completed
    }

    // 每项独立执行，调用方可以只重试未完成项。
    public func moveBatch(_ sourceURLs: [URL], to destinationDirectory: URL) throws -> FileOperationBatchResult {
        try performBatch(sourceURLs, to: destinationDirectory, operation: .move)
    }

    public func copyBatch(_ sourceURLs: [URL], to destinationDirectory: URL) throws -> FileOperationBatchResult {
        try performBatch(sourceURLs, to: destinationDirectory, operation: .copy)
    }

    private func performBatch(
        _ sourceURLs: [URL],
        to destinationDirectory: URL,
        operation: FileOperationType
    ) throws -> FileOperationBatchResult {
        guard !sourceURLs.isEmpty else {
            throw FileOperationError.missingSelection
        }

        var completed: [FileOperationOutcome] = []
        var remaining: [URL] = []
        var failures: [FileOperationFailure] = []

        for (index, sourceURL) in sourceURLs.enumerated() {
            do {
                let destinationURL = try preparedDestination(
                    sourceURL: sourceURL,
                    destinationDirectory: destinationDirectory,
                    operation: operation
                )
                switch operation {
                case .move:
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                case .copy:
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                case .createFile:
                    preconditionFailure("createFile is not a batch operation")
                }
                completed.append(FileOperationOutcome(sourceURL: sourceURL, destinationURL: destinationURL, operation: operation))
            } catch let failure as FileOperationError {
                failures.append(FileOperationFailure(sourceURL: sourceURL, operation: operation, error: failure))
                remaining.append(sourceURL)
                if case .cancelled = failure {
                    remaining.append(contentsOf: sourceURLs.dropFirst(index + 1))
                    break
                }
            } catch {
                failures.append(FileOperationFailure(sourceURL: sourceURL, operation: operation, error: error))
                remaining.append(sourceURL)
            }
        }

        return FileOperationBatchResult(
            completed: completed,
            remainingSourceURLs: remaining,
            failures: failures
        )
    }

    public func createFile(template: FileTemplate, in directory: URL) throws -> FileOperationOutcome {
        guard isValidFileName(template.defaultFileName) else {
            throw FileOperationError.invalidFileName(template.defaultFileName)
        }
        let proposedURL = directory.appendingPathComponent(template.defaultFileName)
        let destinationURL = try resolveConflictIfNeeded(
            sourceURL: nil,
            proposedDestinationURL: proposedURL,
            operation: .createFile
        )
        try Data(template.contents.utf8).write(to: destinationURL, options: [.atomic])
        return FileOperationOutcome(sourceURL: nil, destinationURL: destinationURL, operation: .createFile)
    }

    private func preparedDestination(
        sourceURL: URL,
        destinationDirectory: URL,
        operation: FileOperationType
    ) throws -> URL {
        let proposedURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        return try resolveConflictIfNeeded(
            sourceURL: sourceURL,
            proposedDestinationURL: proposedURL,
            operation: operation
        )
    }

    private func resolveConflictIfNeeded(
        sourceURL: URL?,
        proposedDestinationURL: URL,
        operation: FileOperationType
    ) throws -> URL {
        guard fileManager.fileExists(atPath: proposedDestinationURL.path) else {
            return proposedDestinationURL
        }

        let conflict = FileConflict(
            sourceURL: sourceURL,
            proposedDestinationURL: proposedDestinationURL,
            operation: operation
        )

        switch try conflictResolver.resolve(conflict) {
        case .replace:
            try fileManager.removeItem(at: proposedDestinationURL)
            return proposedDestinationURL
        case .keepBoth:
            return availableCopyURL(for: proposedDestinationURL)
        case .cancel:
            throw FileOperationError.cancelled
        }
    }

    private func availableCopyURL(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let parts = splitFilename(filename)
        let firstCandidate = directory.appendingPathComponent(parts.stem + " copy" + parts.suffix)
        if !fileManager.fileExists(atPath: firstCandidate.path) {
            return firstCandidate
        }

        var index = 2
        while true {
            let candidate = directory.appendingPathComponent(parts.stem + " \(index)" + parts.suffix)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func splitFilename(_ filename: String) -> (stem: String, suffix: String) {
        if filename.hasPrefix(".") {
            return (filename, "")
        }

        let url = URL(fileURLWithPath: filename)
        let pathExtension = url.pathExtension
        guard !pathExtension.isEmpty else {
            return (filename, "")
        }

        let stem = String(filename.dropLast(pathExtension.count + 1))
        return (stem, "." + pathExtension)
    }

    private func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/")
    }
}
