import Foundation
@testable import RightClickProCore

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("RightClickProTests")
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

struct MappingBookmarkResolver: BookmarkResolving {
    var urlsByID: [String: URL]

    func resolve(_ bookmark: DirectoryBookmark) throws -> URL {
        urlsByID[bookmark.id] ?? bookmark.fallbackURL
    }
}
