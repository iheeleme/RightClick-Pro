import Foundation
import Security

public struct PendingCommandRunRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var actionID: String
    public var context: FinderContext
    public var securityScopedBookmarks: [PendingCommandScopedBookmark]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        actionID: String,
        context: FinderContext,
        securityScopedBookmarks: [PendingCommandScopedBookmark] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.actionID = actionID
        self.context = context
        self.securityScopedBookmarks = securityScopedBookmarks
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case actionID
        case context
        case securityScopedBookmarks
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        actionID = try container.decode(String.self, forKey: .actionID)
        context = try container.decode(FinderContext.self, forKey: .context)
        securityScopedBookmarks = try container.decodeIfPresent([PendingCommandScopedBookmark].self, forKey: .securityScopedBookmarks) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(actionID, forKey: .actionID)
        try container.encode(context, forKey: .context)
        if !securityScopedBookmarks.isEmpty {
            try container.encode(securityScopedBookmarks, forKey: .securityScopedBookmarks)
        }
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public struct PendingCommandScopedBookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var bookmarkDataBase64: String

    public init(path: String, bookmarkDataBase64: String) {
        self.path = path
        self.bookmarkDataBase64 = bookmarkDataBase64
    }
}

public enum CommandTemplateError: Error, Equatable, LocalizedError, Sendable {
    case missingCommandTemplate(String)
    case unauthorizedWorkingDirectory(String)
    case inaccessibleWorkingDirectory(String)
    case invalidScopedBookmark(String)
    case invalidEnvironmentName(String)
    case missingSecret(String)
    case unsupportedVariable(String)

    public var errorDescription: String? {
        switch self {
        case .missingCommandTemplate(let id):
            return "找不到命令模板：\(id)"
        case .unauthorizedWorkingDirectory(let path):
            return "命令工作目录无法访问：\(path)。\(FullDiskAccessAdvisor.guidance)"
        case .inaccessibleWorkingDirectory(let path):
            return "命令工作目录无法访问：\(path)。\(FullDiskAccessAdvisor.guidance)"
        case .invalidScopedBookmark(let path):
            return "命令目录授权已失效：\(path)。请重新授权后再运行。"
        case .invalidEnvironmentName(let name):
            return "环境变量名称无效：\(name)"
        case .missingSecret(let reference):
            return "找不到敏感环境变量：\(reference)"
        case .unsupportedVariable(let name):
            return "不支持的命令变量：\(name)"
        }
    }
}

public enum CommandTemplateVariableResolver {
    public static func workingDirectory(for template: CommandTemplate, context: FinderContext) -> URL {
        switch template.workingDirectoryMode {
        case .currentDirectory:
            return context.targetDirectory
        case .selectedItemDirectory:
            return context.selectedItems.first?.deletingLastPathComponent() ?? context.targetDirectory
        }
    }

    public static func interpolatedCommand(template: CommandTemplate, context: FinderContext) throws -> String {
        var command = template.command
        let replacements: [String: String] = [
            "currentDirectory": shellQuoted(context.targetDirectory.path),
            "selectedPath": shellQuoted(context.selectedItems.first?.path ?? context.targetDirectory.path),
            "selectedPaths": context.selectedItems.map { shellQuoted($0.path) }.joined(separator: " ")
        ]

        let names = variableNames(in: command)
        for name in names {
            guard let value = replacements[name] else {
                throw CommandTemplateError.unsupportedVariable(name)
            }
            command = command.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return command
    }

    public static func validateEnvironmentName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else {
            return false
        }
        let firstSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_")
        let restSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        return firstSet.contains(first) && name.unicodeScalars.dropFirst().allSatisfy { restSet.contains($0) }
    }

    private static func variableNames(in command: String) -> [String] {
        let pattern = #"\{\{([A-Za-z][A-Za-z0-9]*)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(command.startIndex..<command.endIndex, in: command)
        return regex.matches(in: command, range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: command) else {
                return nil
            }
            return String(command[range])
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public protocol CommandSecretStoring {
    func save(secret: String, reference: String) throws
    func load(reference: String) throws -> String?
    func delete(reference: String) throws
}

public final class KeychainCommandSecretStore: CommandSecretStoring {
    private let service: String

    public init(service: String = RightClickProConstants.commandEnvironmentKeychainService) {
        self.service = service
    }

    public func save(secret: String, reference: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(reference: reference)
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainCommandSecretError.unhandledStatus(status)
        }
    }

    public func load(reference: String) throws -> String? {
        var query = baseQuery(reference: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCommandSecretError.unhandledStatus(status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func delete(reference: String) throws {
        let status = SecItemDelete(baseQuery(reference: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCommandSecretError.unhandledStatus(status)
        }
    }

    private func baseQuery(reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
    }
}

public enum KeychainCommandSecretError: Error, Equatable, LocalizedError {
    case unhandledStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain 操作失败：\(status)"
        }
    }
}

public final class InMemoryCommandSecretStore: CommandSecretStoring {
    public private(set) var secrets: [String: String] = [:]

    public init() {}

    public func save(secret: String, reference: String) throws {
        secrets[reference] = secret
    }

    public func load(reference: String) throws -> String? {
        secrets[reference]
    }

    public func delete(reference: String) throws {
        secrets.removeValue(forKey: reference)
    }
}
