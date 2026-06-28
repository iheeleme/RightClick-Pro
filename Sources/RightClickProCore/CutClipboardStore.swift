import Foundation

public struct CutClipboardRecord: Codable, Equatable {
    public var sourceURLs: [URL]
    public var createdAt: Date

    public init(sourceURLs: [URL], createdAt: Date = Date()) {
        self.sourceURLs = sourceURLs
        self.createdAt = createdAt
    }
}

public protocol CutClipboardStoring {
    func load() throws -> CutClipboardRecord?
    func save(_ record: CutClipboardRecord) throws
    func clear() throws
}

public final class FileBackedCutClipboardStore: CutClipboardStoring {
    private let store: JSONFileStore<CutClipboardRecord?>

    public init(url: URL) {
        self.store = JSONFileStore<CutClipboardRecord?>(url: url)
    }

    public func load() throws -> CutClipboardRecord? {
        try store.load(default: nil)
    }

    public func save(_ record: CutClipboardRecord) throws {
        try store.save(record)
    }

    public func clear() throws {
        try store.save(nil)
    }
}

public final class InMemoryCutClipboardStore: CutClipboardStoring {
    public private(set) var record: CutClipboardRecord?

    public init(record: CutClipboardRecord? = nil) {
        self.record = record
    }

    public func load() throws -> CutClipboardRecord? {
        record
    }

    public func save(_ record: CutClipboardRecord) throws {
        self.record = record
    }

    public func clear() throws {
        record = nil
    }
}
