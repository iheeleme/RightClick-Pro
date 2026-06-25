import Foundation

public struct RightToolStoragePaths: Equatable {
    public var baseURL: URL
    public var configURL: URL
    public var bookmarksURL: URL
    public var cutClipboardURL: URL
    public var operationLogURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.configURL = baseURL.appendingPathComponent("config.json")
        self.bookmarksURL = baseURL.appendingPathComponent("bookmarks.json")
        self.cutClipboardURL = baseURL.appendingPathComponent("cut-clipboard.json")
        self.operationLogURL = baseURL.appendingPathComponent("operation-log.jsonl")
    }

    public static func appGroup(identifier: String = RightToolConstants.defaultAppGroupIdentifier) throws -> RightToolStoragePaths {
        guard let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw StorageError.appGroupContainerUnavailable(identifier)
        }
        return RightToolStoragePaths(baseURL: baseURL)
    }
}

public enum StorageError: Error, Equatable {
    case appGroupContainerUnavailable(String)
    case missingRequiredFile(URL)
}

public final class JSONFileStore<Value: Codable> {
    public let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load(default defaultValue: @autoclosure () -> Value) throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            return defaultValue()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    public func loadRequired() throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.missingRequiredFile(url)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

public protocol RightToolConfigProviding {
    func loadConfig() throws -> RightToolConfig
    func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog
}

public struct FileBackedRightToolConfigProvider: RightToolConfigProviding {
    private let configStore: JSONFileStore<RightToolConfig>
    private let bookmarkStore: JSONFileStore<DirectoryBookmarkCatalog>

    public init(paths: RightToolStoragePaths) {
        self.configStore = JSONFileStore<RightToolConfig>(url: paths.configURL)
        self.bookmarkStore = JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL)
    }

    public func loadConfig() throws -> RightToolConfig {
        try configStore.load(default: RightToolConfig())
    }

    public func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog {
        try bookmarkStore.load(default: DirectoryBookmarkCatalog())
    }
}

public struct StaticRightToolConfigProvider: RightToolConfigProviding {
    public var config: RightToolConfig
    public var bookmarkCatalog: DirectoryBookmarkCatalog

    public init(config: RightToolConfig, bookmarkCatalog: DirectoryBookmarkCatalog = DirectoryBookmarkCatalog()) {
        self.config = config
        self.bookmarkCatalog = bookmarkCatalog
    }

    public func loadConfig() throws -> RightToolConfig {
        config
    }

    public func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog {
        bookmarkCatalog
    }
}
