import Foundation

public struct DirectoryBookmark: Codable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var path: String
    public var bookmarkDataBase64: String?
    public var addedAt: Date

    public init(
        id: String,
        displayName: String,
        path: String,
        bookmarkDataBase64: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.bookmarkDataBase64 = bookmarkDataBase64
        self.addedAt = addedAt
    }

    public var fallbackURL: URL {
        URL(fileURLWithPath: path)
    }
}

public struct DirectoryBookmarkCatalog: Codable, Equatable {
    public var schemaVersion: Int
    public var bookmarks: [DirectoryBookmark]

    public init(
        schemaVersion: Int = RightToolConstants.currentSchemaVersion,
        bookmarks: [DirectoryBookmark] = []
    ) {
        self.schemaVersion = schemaVersion
        self.bookmarks = bookmarks
    }

    public func bookmark(id: String) -> DirectoryBookmark? {
        bookmarks.first { $0.id == id }
    }

    public func urls(for ids: [String]) -> [URL] {
        ids.compactMap { bookmark(id: $0)?.fallbackURL }
    }
}

public enum BookmarkError: Error, Equatable {
    case missingBookmark(String)
    case invalidBookmarkData(String)
}

public protocol BookmarkResolving {
    func resolve(_ bookmark: DirectoryBookmark) throws -> URL
}

public struct FallbackBookmarkResolver: BookmarkResolving {
    public init() {}

    public func resolve(_ bookmark: DirectoryBookmark) throws -> URL {
        bookmark.fallbackURL
    }
}

public struct SecurityScopedBookmarkResolver: BookmarkResolving {
    public init() {}

    public func resolve(_ bookmark: DirectoryBookmark) throws -> URL {
        guard let encoded = bookmark.bookmarkDataBase64 else {
            return bookmark.fallbackURL
        }

        guard let data = Data(base64Encoded: encoded) else {
            throw BookmarkError.invalidBookmarkData(bookmark.id)
        }

        var isStale = false
        return try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
