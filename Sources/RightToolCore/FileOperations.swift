import Foundation

public enum FileOperationType: String, Codable, Equatable {
    case move
    case copy
    case createFile
}

public struct FileConflict: Equatable {
    public var sourceURL: URL?
    public var proposedDestinationURL: URL
    public var operation: FileOperationType

    public init(sourceURL: URL?, proposedDestinationURL: URL, operation: FileOperationType) {
        self.sourceURL = sourceURL
        self.proposedDestinationURL = proposedDestinationURL
        self.operation = operation
    }
}

public enum FileConflictResolution: Equatable {
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

public enum FileOperationError: Error, Equatable, LocalizedError {
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

public struct FileOperationOutcome: Equatable {
    public var sourceURL: URL?
    public var destinationURL: URL
    public var operation: FileOperationType

    public init(sourceURL: URL?, destinationURL: URL, operation: FileOperationType) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.operation = operation
    }
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
        guard !sourceURLs.isEmpty else {
            throw FileOperationError.missingSelection
        }
        return try sourceURLs.map { sourceURL in
            let destinationURL = try preparedDestination(
                sourceURL: sourceURL,
                destinationDirectory: destinationDirectory,
                operation: .move
            )
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            return FileOperationOutcome(sourceURL: sourceURL, destinationURL: destinationURL, operation: .move)
        }
    }

    public func copy(_ sourceURLs: [URL], to destinationDirectory: URL) throws -> [FileOperationOutcome] {
        guard !sourceURLs.isEmpty else {
            throw FileOperationError.missingSelection
        }
        return try sourceURLs.map { sourceURL in
            let destinationURL = try preparedDestination(
                sourceURL: sourceURL,
                destinationDirectory: destinationDirectory,
                operation: .copy
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return FileOperationOutcome(sourceURL: sourceURL, destinationURL: destinationURL, operation: .copy)
        }
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
