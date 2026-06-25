import Foundation

public struct ConfigurationBootstrapResult: Equatable {
    public var paths: RightToolStoragePaths
    public var config: RightToolConfig
    public var bookmarks: DirectoryBookmarkCatalog
    public var didCreateConfig: Bool
    public var didCreateBookmarks: Bool

    public init(
        paths: RightToolStoragePaths,
        config: RightToolConfig,
        bookmarks: DirectoryBookmarkCatalog,
        didCreateConfig: Bool,
        didCreateBookmarks: Bool
    ) {
        self.paths = paths
        self.config = config
        self.bookmarks = bookmarks
        self.didCreateConfig = didCreateConfig
        self.didCreateBookmarks = didCreateBookmarks
    }
}

public struct ConfigurationBootstrapper {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func bootstrap(paths: RightToolStoragePaths = .defaultForCurrentProcess()) throws -> ConfigurationBootstrapResult {
        let configStore = JSONFileStore<RightToolConfig>(url: paths.configURL, fileManager: fileManager)
        let bookmarkStore = JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL, fileManager: fileManager)
        let logStore = JSONLineOperationLog(url: paths.operationLogURL, fileManager: fileManager)

        let didCreateBookmarks = !fileManager.fileExists(atPath: paths.bookmarksURL.path)
        let bookmarks = try bookmarkStore.load(default: defaultBookmarks())
        if didCreateBookmarks {
            try bookmarkStore.save(bookmarks)
        }

        let didCreateConfig = !fileManager.fileExists(atPath: paths.configURL.path)
        let config = try configStore.load(default: defaultConfig(bookmarks: bookmarks))
        if didCreateConfig {
            try configStore.save(config)
        }

        if !fileManager.fileExists(atPath: paths.operationLogURL.path) {
            try logStore.append(
                OperationRecord(
                    actionID: "bootstrap",
                    kind: .unsupported,
                    status: .success,
                    destinationPaths: [paths.baseURL.path],
                    message: "RightTool 默认配置已自动注入"
                )
            )
        }

        return ConfigurationBootstrapResult(
            paths: paths,
            config: config,
            bookmarks: bookmarks,
            didCreateConfig: didCreateConfig,
            didCreateBookmarks: didCreateBookmarks
        )
    }

    public func defaultBookmarks() -> DirectoryBookmarkCatalog {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates: [(String, String, URL)] = [
            ("desktop", "桌面", home.appendingPathComponent("Desktop")),
            ("downloads", "下载", home.appendingPathComponent("Downloads")),
            ("documents", "文稿", home.appendingPathComponent("Documents")),
            ("code", "代码", home.appendingPathComponent("Code"))
        ]

        let bookmarks = candidates
            .filter { fileManager.fileExists(atPath: $0.2.path) }
            .map { id, displayName, url in
                DirectoryBookmark(id: id, displayName: displayName, path: url.path)
            }

        return DirectoryBookmarkCatalog(bookmarks: bookmarks)
    }

    public func defaultConfig(bookmarks: DirectoryBookmarkCatalog) -> RightToolConfig {
        let directoryIDs = bookmarks.bookmarks.map(\.id)
        return RightToolConfig(
            monitoredDirectoryIDs: directoryIDs,
            commonDirectoryIDs: directoryIDs,
            actions: defaultActions(bookmarks: bookmarks)
        )
    }

    private func defaultActions(bookmarks: DirectoryBookmarkCatalog) -> [RightToolAction] {
        var actions: [RightToolAction] = []
        var order = 10

        actions.append(
            RightToolAction(
                id: "paste-here",
                title: "粘贴到此处",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 10

        actions.append(
            RightToolAction(
                id: "cut-selection",
                title: "剪切",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 10

        for bookmark in bookmarks.bookmarks {
            actions.append(
                RightToolAction(
                    id: "open-directory-\(bookmark.id)",
                    title: "前往\(bookmark.displayName)",
                    kind: .openDirectory,
                    visibility: [.container, .toolbar],
                    placement: .submenu,
                    group: .commonDirectories,
                    order: order,
                    payload: ActionPayload(directoryID: bookmark.id)
                )
            )
            order += 10

            actions.append(
                RightToolAction(
                    id: "move-to-\(bookmark.id)",
                    title: "移动到\(bookmark.displayName)",
                    kind: .moveToDirectory,
                    visibility: [.selection],
                    placement: .submenu,
                    group: .moveToCommonDirectory,
                    order: order,
                    payload: ActionPayload(directoryID: bookmark.id)
                )
            )
            order += 10

            actions.append(
                RightToolAction(
                    id: "copy-to-\(bookmark.id)",
                    title: "复制到\(bookmark.displayName)",
                    kind: .copyToDirectory,
                    visibility: [.selection],
                    placement: .submenu,
                    group: .copyToCommonDirectory,
                    order: order,
                    payload: ActionPayload(directoryID: bookmark.id)
                )
            )
            order += 10
        }

        for template in RightToolConfig.defaultFileTemplates() {
            actions.append(
                RightToolAction(
                    id: "create-\(template.id)",
                    title: "新建\(template.title)",
                    kind: .createFile,
                    visibility: [.container],
                    placement: template.id == "template-md" ? .rootMenu : .submenu,
                    group: .createFile,
                    order: order,
                    payload: ActionPayload(templateID: template.id)
                )
            )
            order += 10
        }

        for entrypoint in RightToolConfig.defaultDeveloperEntrypoints() {
            actions.append(
                RightToolAction(
                    id: "open-\(entrypoint.id)",
                    title: entrypoint.title,
                    kind: .openInApp,
                    visibility: [.selection, .container, .toolbar],
                    placement: .submenu,
                    group: .developerEntrypoints,
                    order: order,
                    payload: ActionPayload(developerEntrypointID: entrypoint.id)
                )
            )
            order += 10
        }

        return actions
    }
}
