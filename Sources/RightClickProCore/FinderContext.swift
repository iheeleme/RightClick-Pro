import Foundation

public enum FinderInvocation: String, Codable, Equatable, Sendable {
    case selection
    case container
    case toolbar

    public var visibility: ActionVisibility {
        switch self {
        case .selection:
            return .selection
        case .container:
            return .container
        case .toolbar:
            return .toolbar
        }
    }
}

public struct FinderContext: Codable, Equatable, Sendable {
    public var invocation: FinderInvocation
    public var targetDirectory: URL
    public var selectedItems: [URL]

    public init(
        invocation: FinderInvocation,
        targetDirectory: URL,
        selectedItems: [URL] = []
    ) {
        self.invocation = invocation
        self.targetDirectory = targetDirectory
        self.selectedItems = selectedItems
    }
}

public struct ActionRequest: Codable, Equatable, Sendable {
    public var id: UUID
    public var actionID: String
    public var context: FinderContext
    public var requestedAt: Date

    public init(
        id: UUID = UUID(),
        actionID: String,
        context: FinderContext,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.actionID = actionID
        self.context = context
        self.requestedAt = requestedAt
    }
}

public enum ActionResultStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
    case cancelled
}

public struct ActionResult: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var status: ActionResultStatus
    public var message: String
    public var affectedURLs: [URL]

    public init(
        requestID: UUID,
        status: ActionResultStatus,
        message: String,
        affectedURLs: [URL] = []
    ) {
        self.requestID = requestID
        self.status = status
        self.message = message
        self.affectedURLs = affectedURLs
    }
}
