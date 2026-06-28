import Foundation

public enum FinderSyncScope {
    public static func syncRoots(for monitoredURLs: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var roots: [URL] = []

        for url in monitoredURLs {
            let root = syncRoot(for: url)
            let path = normalizedPath(root)
            guard seenPaths.insert(path).inserted else {
                continue
            }
            roots.append(root)
        }

        return roots
    }

    public static func contextIsInsideMonitoredDirectories(
        _ context: FinderContext,
        monitoredURLs: [URL]
    ) -> Bool {
        guard !monitoredURLs.isEmpty else {
            return false
        }

        let candidates = [context.targetDirectory] + context.selectedItems
        return candidates.contains { candidate in
            monitoredURLs.contains { monitoredURL in
                contains(candidate, in: monitoredURL)
            }
        }
    }

    public static func contains(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = normalizedPath(candidate)
        let rootPath = normalizedPath(root)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func syncRoot(for url: URL) -> URL {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().standardizedFileURL

        guard parent.path != "/", parent.path != standardized.path else {
            return standardized
        }

        return parent
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        guard path.count > 1 else {
            return path
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
