import Foundation

public struct RightClickProStoragePaths: Equatable {
    public var baseURL: URL
    public var configURL: URL
    public var bookmarksURL: URL
    public var cutClipboardURL: URL
    public var operationLogURL: URL
    public var pendingCommandRunURL: URL
    public var commandRunStateDirectoryURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.configURL = baseURL.appendingPathComponent("config.json")
        self.bookmarksURL = baseURL.appendingPathComponent("bookmarks.json")
        self.cutClipboardURL = baseURL.appendingPathComponent("cut-clipboard.json")
        self.operationLogURL = baseURL.appendingPathComponent("operation-log.jsonl")
        self.pendingCommandRunURL = baseURL.appendingPathComponent("pending-command-run.json")
        self.commandRunStateDirectoryURL = baseURL.appendingPathComponent("command-runs", isDirectory: true)
    }

    public static func appGroup(identifier: String = RightClickProConstants.defaultAppGroupIdentifier) throws -> RightClickProStoragePaths {
        guard let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw StorageError.appGroupContainerUnavailable(identifier)
        }
        return RightClickProStoragePaths(baseURL: baseURL)
    }

    public static func applicationSupport(
        fileManager: FileManager = .default,
        bundleIdentifier: String = RightClickProConstants.mainAppBundleIdentifier
    ) -> RightClickProStoragePaths {
        let baseURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent(bundleIdentifier)
        return RightClickProStoragePaths(baseURL: baseURL)
    }

    public static func defaultForCurrentProcess(
        appGroupIdentifier: String = RightClickProConstants.defaultAppGroupIdentifier,
        fileManager: FileManager = .default
    ) -> RightClickProStoragePaths {
        if let appGroupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return RightClickProStoragePaths(baseURL: appGroupURL)
        }

        return applicationSupport(fileManager: fileManager)
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

public protocol RightClickProConfigProviding {
    func loadConfig() throws -> RightClickProConfig
    func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog
}

public struct FileBackedRightClickProConfigProvider: RightClickProConfigProviding {
    private let configStore: JSONFileStore<RightClickProConfig>
    private let bookmarkStore: JSONFileStore<DirectoryBookmarkCatalog>

    public init(paths: RightClickProStoragePaths) {
        self.configStore = JSONFileStore<RightClickProConfig>(url: paths.configURL)
        self.bookmarkStore = JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL)
    }

    public func loadConfig() throws -> RightClickProConfig {
        try configStore.load(default: RightClickProConfig())
    }

    public func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog {
        try bookmarkStore.load(default: DirectoryBookmarkCatalog())
    }
}

public struct StaticRightClickProConfigProvider: RightClickProConfigProviding {
    public var config: RightClickProConfig
    public var bookmarkCatalog: DirectoryBookmarkCatalog

    public init(config: RightClickProConfig, bookmarkCatalog: DirectoryBookmarkCatalog = DirectoryBookmarkCatalog()) {
        self.config = config
        self.bookmarkCatalog = bookmarkCatalog
    }

    public func loadConfig() throws -> RightClickProConfig {
        config
    }

    public func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog {
        bookmarkCatalog
    }
}
