import Foundation

public enum AuthorizationError: Error, Equatable, LocalizedError {
    case unauthorizedPath(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorizedPath(let path):
            return "未授权目录：\(path)"
        }
    }
}

public struct AuthorizedPathValidator {
    private let authorizedDirectories: [URL]

    public init(authorizedDirectories: [URL]) {
        self.authorizedDirectories = authorizedDirectories.map(Self.normalizedDirectory)
    }

    public func validate(_ url: URL) throws {
        guard isAuthorized(url) else {
            throw AuthorizationError.unauthorizedPath(url.path)
        }
    }

    public func validate(_ urls: [URL]) throws {
        for url in urls {
            try validate(url)
        }
    }

    public func isAuthorized(_ url: URL) -> Bool {
        let candidatePath = Self.normalizedURL(url).path
        return authorizedDirectories.contains { directory in
            let basePath = directory.path
            return candidatePath == basePath || candidatePath.hasPrefix(basePath + "/")
        }
    }

    private static func normalizedDirectory(_ url: URL) -> URL {
        normalizedURL(url)
    }

    private static func normalizedURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
