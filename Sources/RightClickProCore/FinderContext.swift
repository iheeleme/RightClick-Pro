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
    // 批量动作未完成的源项，重试时无需再次处理已完成项。
    public var remainingURLs: [URL]

    private enum CodingKeys: String, CodingKey {
        case requestID
        case status
        case message
        case affectedURLs
        case remainingURLs
    }

    public init(
        requestID: UUID,
        status: ActionResultStatus,
        message: String,
        affectedURLs: [URL] = [],
        remainingURLs: [URL] = []
    ) {
        self.requestID = requestID
        self.status = status
        self.message = message
        self.affectedURLs = affectedURLs
        self.remainingURLs = remainingURLs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.requestID = try container.decode(UUID.self, forKey: .requestID)
        self.status = try container.decode(ActionResultStatus.self, forKey: .status)
        self.message = try container.decode(String.self, forKey: .message)
        self.affectedURLs = try container.decodeIfPresent([URL].self, forKey: .affectedURLs) ?? []
        self.remainingURLs = try container.decodeIfPresent([URL].self, forKey: .remainingURLs) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(status, forKey: .status)
        try container.encode(message, forKey: .message)
        try container.encode(affectedURLs, forKey: .affectedURLs)
        try container.encode(remainingURLs, forKey: .remainingURLs)
    }
}
