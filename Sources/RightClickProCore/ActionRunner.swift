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
        var selectedAction: RightClickProAction?
        do {
            let config = try configProvider.loadConfig()
            guard let action = config.actions.first(where: { $0.id == request.actionID }) else {
                throw ActionRunnerError.actionNotFound(request.actionID)
            }
            selectedAction = action
            let bookmarks = try configProvider.loadBookmarkCatalog()

            let bookmarkAccess = try AuthorizedBookmarkAccess(
                catalog: bookmarks,
                ids: try bookmarkIDs(for: action),
                resolver: bookmarkResolver
            )
            var result = try execute(
                action,
                config: config,
                bookmarkAccess: bookmarkAccess,
                request: request
            )
            do {
                try log(action: action, request: request, result: result)
            } catch {
                // 文件动作已经执行，历史落盘错误不能抹掉完成项和待重试项。
                result.status = .failure
                result.message += "\n操作历史保存失败：\(error.localizedDescription)"
            }
            return result
        } catch {
            let status: ActionResultStatus = (error as? FileOperationError) == .cancelled ? .cancelled : .failure
            let result = ActionResult(
                requestID: request.id,
                status: status,
                message: FullDiskAccessAdvisor.userFacingMessage(for: error)
            )
            try? operationLog.append(
                OperationRecord(
                    actionID: request.actionID,
                    kind: selectedAction.map { OperationKind(actionKind: $0.kind) } ?? .unsupported,
                    status: recordStatus(for: status),
                    sourcePaths: request.context.selectedItems.map(\.path),
                    destinationPaths: [request.context.targetDirectory.path],
                    message: result.message
                )
            )
            return result
        }
    }

    private func bookmarkIDs(for action: RightClickProAction) throws -> [String] {
        switch action.kind {
        case .openDirectory, .moveToDirectory, .copyToDirectory:
            guard let directoryID = action.payload.directoryID else {
                throw ActionRunnerError.missingPayload("directoryID")
            }
            return [directoryID]
        case .cut, .paste, .createFile, .openInApp, .runCommand, .undoOperation:
            return []
        }
    }

    private func execute(
        _ action: RightClickProAction,
        config: RightClickProConfig,
        bookmarkAccess: AuthorizedBookmarkAccess,
        request: ActionRequest
    ) throws -> ActionResult {
        switch action.kind {
        case .openDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            try urlOpener.open(directory)
            return ActionResult(requestID: request.id, status: .success, message: "已打开目录", affectedURLs: [directory])

        case .moveToDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            let batch = try fileService.moveBatch(request.context.selectedItems, to: directory)
            return actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "移动完成",
                failurePrefix: "移动未完全完成"
            )

        case .copyToDirectory:
            let directory = try directoryURL(from: action, bookmarkAccess: bookmarkAccess)
            let batch = try fileService.copyBatch(request.context.selectedItems, to: directory)
            return actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "复制完成",
                failurePrefix: "复制未完全完成"
            )

        case .cut:
            guard !request.context.selectedItems.isEmpty else {
                throw FileOperationError.missingSelection
            }
            try cutClipboard.save(CutClipboardRecord(sourceURLs: request.context.selectedItems))
            return ActionResult(requestID: request.id, status: .success, message: "已记录剪切项目", affectedURLs: request.context.selectedItems)

        case .paste:
            guard let record = try cutClipboard.load(), !record.sourceURLs.isEmpty else {
                throw ActionRunnerError.emptyClipboard
            }
            let batch = try fileService.moveBatch(record.sourceURLs, to: request.context.targetDirectory)
            var result = actionResult(
                requestID: request.id,
                batch: batch,
                successMessage: "粘贴完成",
                failurePrefix: "粘贴未完全完成"
            )
            do {
                if batch.remainingSourceURLs.isEmpty {
                    try cutClipboard.clear()
                } else {
                    // 只保留待处理项，再次粘贴不会重复移动已完成项目。
                    try cutClipboard.save(CutClipboardRecord(sourceURLs: batch.remainingSourceURLs))
                }
            } catch {
                result.status = .failure
                result.message += "\n剪切板更新失败：\(error.localizedDescription)。再次粘贴前，请重新剪切需要操作的文件。"
            }
            return result

        case .createFile:
            let template = try fileTemplate(from: action, config: config)
            let outcome = try fileService.createFile(template: template, in: request.context.targetDirectory)
            return ActionResult(requestID: request.id, status: .success, message: "文件已创建", affectedURLs: [outcome.destinationURL])

        case .openInApp:
            let entrypoint = try developerEntrypoint(from: action, config: config)
            let targetURL = developerTargetURL(for: entrypoint, context: request.context)
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
        var sourcePaths = request.context.selectedItems.map(\.path)
        for path in result.remainingURLs.map(\.path) where !sourcePaths.contains(path) {
            sourcePaths.append(path)
        }
        try operationLog.append(
            OperationRecord(
                actionID: action.id,
                kind: operationKind(for: action.kind),
                status: recordStatus(for: result.status),
                sourcePaths: sourcePaths,
                destinationPaths: result.affectedURLs.map(\.path),
                message: result.message
            )
        )
    }

    private func actionResult(
        requestID: UUID,
        batch: FileOperationBatchResult,
        successMessage: String,
        failurePrefix: String
    ) -> ActionResult {
        guard !batch.failures.isEmpty else {
            return ActionResult(
                requestID: requestID,
                status: .success,
                message: successMessage,
                affectedURLs: batch.completed.map(\.destinationURL)
            )
        }

        let details = batch.failures.map { failure in
            let message = FullDiskAccessAdvisor.userFacingMessage(for: failure.asNSError)
            return "\(failure.sourceURL.lastPathComponent)：\(message)"
        }.joined(separator: "；")
        let completedCount = batch.completed.count
        let pendingCount = batch.remainingSourceURLs.count
        let message = "\(failurePrefix)（已完成 \(completedCount) 项，待重试 \(pendingCount) 项）：\(details)"
        return ActionResult(
            requestID: requestID,
            status: batch.failures.allSatisfy(\.isCancellation) ? .cancelled : .failure,
            message: message,
            affectedURLs: batch.completed.map(\.destinationURL),
            remainingURLs: batch.remainingSourceURLs
        )
    }

    private func operationKind(for actionKind: ActionKind) -> OperationKind {
        OperationKind(actionKind: actionKind)
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
