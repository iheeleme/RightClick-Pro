import Foundation

public enum OperationKind: String, Codable, Equatable {
    case openDirectory
    case move
    case copy
    case cut
    case paste
    case createFile
    case openInApp
    case runCommand
    case unsupported
}

public enum OperationRecordStatus: String, Codable, Equatable {
    case success
    case failure
    case cancelled
}

public struct OperationRecord: Codable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var actionID: String
    public var kind: OperationKind
    public var status: OperationRecordStatus
    public var sourcePaths: [String]
    public var destinationPaths: [String]
    public var message: String?
    public var commandExitCode: Int?
    public var durationMilliseconds: Int?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        actionID: String,
        kind: OperationKind,
        status: OperationRecordStatus,
        sourcePaths: [String] = [],
        destinationPaths: [String] = [],
        message: String? = nil,
        commandExitCode: Int? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actionID = actionID
        self.kind = kind
        self.status = status
        self.sourcePaths = sourcePaths
        self.destinationPaths = destinationPaths
        self.message = message
        self.commandExitCode = commandExitCode
        self.durationMilliseconds = durationMilliseconds
    }
}

public protocol OperationLogging {
    func append(_ record: OperationRecord) throws
    func loadRecent() throws -> [OperationRecord]
}

public final class JSONLineOperationLog: OperationLogging {
    private let url: URL
    private let maxRecords: Int
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL, maxRecords: Int = 500, fileManager: FileManager = .default) {
        self.url = url
        self.maxRecords = maxRecords
        self.fileManager = fileManager
    }

    public func append(_ record: OperationRecord) throws {
        var records = try loadRecent()
        records.append(record)
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }
        try write(records)
    }

    public func loadRecent() throws -> [OperationRecord] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return []
        }
        return text
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(OperationRecord.self, from: Data(line.utf8))
            }
    }

    private func write(_ records: [OperationRecord]) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let lines = try records.map { record -> String in
            let data = try encoder.encode(record)
            return String(decoding: data, as: UTF8.self)
        }
        let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try Data(body.utf8).write(to: url, options: [.atomic])
    }
}

public final class InMemoryOperationLog: OperationLogging {
    public private(set) var records: [OperationRecord] = []

    public init() {}

    public func append(_ record: OperationRecord) throws {
        records.append(record)
    }

    public func loadRecent() throws -> [OperationRecord] {
        records
    }
}
