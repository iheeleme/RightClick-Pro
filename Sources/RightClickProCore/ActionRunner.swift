import Foundation

public enum ActionRunnerError: Error, Equatable, LocalizedError {
    case actionNotFound(String)
    case unsupportedAction(ActionKind)
    case missingPayload(String)
    case directoryNotFound(String)
    case templateNotFound(String)
    case developerEntrypointNotFound(String)
    case emptyClipboard

    public var errorDescription: String? {
        switch self {
        case .actionNotFound(let id):
            return "找不到动作：\(id)"
        case .unsupportedAction(let kind):
            return "暂不支持动作：\(kind.rawValue)"
        case .missingPayload(let field):
            return "动作缺少参数：\(field)"
        case .directoryNotFound(let id):
            return "找不到目录：\(id)"
        case .templateNotFound(let id):
            return "找不到模板：\(id)"
        case .developerEntrypointNotFound(let id):
            return "找不到开发者入口：\(id)"
        case .emptyClipboard:
            return "RightClick Pro 剪切板为空"
        }
    }
}

public final class ActionRunner {
    private let configProvider: RightClickProConfigProviding
    private let fileService: FileOperationService
    private let operationLog: OperationLogging
    private let cutClipboard: CutClipboardStoring
    private let urlOpener: URLOpening
    private let developerAppOpener: DeveloperAppOpening
    private let bookmarkResolver: BookmarkResolving

    public init(
        configProvider: RightClickProConfigProviding,
        fileService: FileOperationService = FileOperationService(),
        operationLog: OperationLogging,
        cutClipboard: CutClipboardStoring,
        urlOpener: URLOpening,
        developerAppOpener: DeveloperAppOpening,
        bookmarkResolver: BookmarkResolving = SecurityScopedBookmarkResolver()
    ) {
        self.configProvider = configProvider
        self.fileService = fileService
        self.operationLog = operationLog
        self.cutClipboard = cutClipboard
        self.urlOpener = urlOpener
        self.developerAppOpener = developerAppOpener
        self.bookmarkResolver = bookmarkResolver
    }

    public func run(_ request: ActionRequest) -> ActionResult {
        do {
            let config = try configProvider.loadConfig()
            let bookmarks = try configProvider.loadBookmarkCatalog()
            guard let action = config.actions.first(where: { $0.id == request.actionID }) else {
                throw ActionRunnerError.actionNotFound(request.actionID)
            }

            let bookmarkAccess = try AuthorizedBookmarkAccess(
                catalog: bookmarks,
                ids: config.monitoredDirectoryIDs + config.commonDirectoryIDs,
                resolver: bookmarkResolver
            )
            let validator = AuthorizedPathValidator(authorizedDirectories: bookmarkAccess.urls)
            let result = try execute(
                action,
                config: config,
                bookmarkAccess: bookmarkAccess,
                validator: validator,
                request: request
            )
            try log(action: action, request: request, result: result)
            return result
        } catch {
            let result = ActionResult(
                requestID: request.id,
                status: .failure,
                message: error.localizedDescription
            )
            try? operationLog.append(
                OperationRecord(
                    actionID: request.actionID,
                    kind: .unsupported,
                    status: .failure,
                    sourcePaths: request.context.selectedItems.map(\.path),
                    destinationPaths: [request.context.targetDirectory.path],
                    message: error.localizedDescription
                )
            )
            return result
        }
    }

    private func execute(
        _ action: RightClickProAction,
        config: RightClickProConfig,
        bookmarkAccess: AuthorizedBookmarkAccess,
        validator: AuthorizedPathValidator,
        request: ActionRequest
    ) throws -> ActionResult {
        switch action.kind {
        case .openDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            try validator.validate(directory)
            try urlOpener.open(directory)
            return ActionResult(requestID: request.id, status: .success, message: "已打开目录", affectedURLs: [directory])

        case .moveToDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            try validator.validate(request.context.selectedItems)
            try validator.validate(directory)
            let outcomes = try fileService.move(request.context.selectedItems, to: directory)
            return ActionResult(requestID: request.id, status: .success, message: "移动完成", affectedURLs: outcomes.map(\.destinationURL))

        case .copyToDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            try validator.validate(request.context.selectedItems)
            try validator.validate(directory)
            let outcomes = try fileService.copy(request.context.selectedItems, to: directory)
            return ActionResult(requestID: request.id, status: .success, message: "复制完成", affectedURLs: outcomes.map(\.destinationURL))

        case .cut:
            try validator.validate(request.context.selectedItems)
            try cutClipboard.save(CutClipboardRecord(sourceURLs: request.context.selectedItems))
            return ActionResult(requestID: request.id, status: .success, message: "已记录剪切项目", affectedURLs: request.context.selectedItems)

        case .paste:
            try validator.validate(request.context.targetDirectory)
            guard let record = try cutClipboard.load(), !record.sourceURLs.isEmpty else {
                throw ActionRunnerError.emptyClipboard
            }
            try validator.validate(record.sourceURLs)
            let outcomes = try fileService.move(record.sourceURLs, to: request.context.targetDirectory)
            try cutClipboard.clear()
            return ActionResult(requestID: request.id, status: .success, message: "粘贴完成", affectedURLs: outcomes.map(\.destinationURL))

        case .createFile:
            try validator.validate(request.context.targetDirectory)
            let template = try fileTemplate(from: action, config: config)
            let outcome = try fileService.createFile(template: template, in: request.context.targetDirectory)
            return ActionResult(requestID: request.id, status: .success, message: "文件已创建", affectedURLs: [outcome.destinationURL])

        case .openInApp:
            let entrypoint = try developerEntrypoint(from: action, config: config)
            let targetURL = developerTargetURL(for: entrypoint, context: request.context)
            try validator.validate(targetURL)
            try developerAppOpener.open(entrypoint, targetURL: targetURL)
            return ActionResult(requestID: request.id, status: .success, message: "已打开开发者入口", affectedURLs: [targetURL])

        case .runCommand, .undoOperation:
            throw ActionRunnerError.unsupportedAction(action.kind)
        }
    }

    private func directoryURL(from action: RightClickProAction, bookmarkAccess: AuthorizedBookmarkAccess) throws -> URL {
        guard let directoryID = action.payload.directoryID else {
            throw ActionRunnerError.missingPayload("directoryID")
        }
        do {
            return try bookmarkAccess.url(for: directoryID)
        } catch BookmarkError.missingBookmark(_) {
            throw ActionRunnerError.directoryNotFound(directoryID)
        } catch {
            throw error
        }
    }

    private func fileTemplate(from action: RightClickProAction, config: RightClickProConfig) throws -> FileTemplate {
        guard let templateID = action.payload.templateID else {
            throw ActionRunnerError.missingPayload("templateID")
        }
        guard let template = config.fileTemplates.first(where: { $0.id == templateID }) else {
            throw ActionRunnerError.templateNotFound(templateID)
        }
        return template
    }

    private func developerEntrypoint(from action: RightClickProAction, config: RightClickProConfig) throws -> DeveloperEntrypoint {
        guard let entrypointID = action.payload.developerEntrypointID else {
            throw ActionRunnerError.missingPayload("developerEntrypointID")
        }
        guard let entrypoint = config.developerEntrypoints.first(where: { $0.id == entrypointID }) else {
            throw ActionRunnerError.developerEntrypointNotFound(entrypointID)
        }
        return entrypoint
    }

    private func developerTargetURL(for entrypoint: DeveloperEntrypoint, context: FinderContext) -> URL {
        switch entrypoint.targetMode {
        case .dynamic:
            switch context.invocation {
            case .selection, .toolbar:
                return context.selectedItems.first ?? context.targetDirectory
            case .container:
                return context.targetDirectory
            }
        case .currentDirectory:
            return context.targetDirectory
        case .selectedItem:
            return context.selectedItems.first ?? context.targetDirectory
        case .selectedItemDirectory:
            return context.selectedItems.first?.deletingLastPathComponent() ?? context.targetDirectory
        }
    }

    private func log(action: RightClickProAction, request: ActionRequest, result: ActionResult) throws {
        try operationLog.append(
            OperationRecord(
                actionID: action.id,
                kind: operationKind(for: action.kind),
                status: recordStatus(for: result.status),
                sourcePaths: request.context.selectedItems.map(\.path),
                destinationPaths: result.affectedURLs.map(\.path),
                message: result.message
            )
        )
    }

    private func operationKind(for actionKind: ActionKind) -> OperationKind {
        switch actionKind {
        case .openDirectory:
            return .openDirectory
        case .moveToDirectory:
            return .move
        case .copyToDirectory:
            return .copy
        case .cut:
            return .cut
        case .paste:
            return .paste
        case .createFile:
            return .createFile
        case .openInApp:
            return .openInApp
        case .runCommand:
            return .runCommand
        case .undoOperation:
            return .unsupported
        }
    }

    private func recordStatus(for resultStatus: ActionResultStatus) -> OperationRecordStatus {
        switch resultStatus {
        case .success:
            return .success
        case .failure:
            return .failure
        case .cancelled:
            return .cancelled
        }
    }
}
