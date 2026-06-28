import Foundation

public enum RightClickProConstants {
    public static let currentSchemaVersion = 2
    public static let defaultAppGroupIdentifier = "group.com.iheeleme.rightclickpro"
    public static let defaultXPCServiceName = "com.iheeleme.rightclickpro.ActionRunner"
    public static let finderExtensionBundleIdentifier = "com.iheeleme.rightclickpro.FinderExtension"
    public static let defaultMaxRootMenuActions = 5
}

public enum ActionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case openDirectory
    case moveToDirectory
    case copyToDirectory
    case cut
    case paste
    case createFile
    case openInApp
    case runCommand
    case undoOperation
}

public enum ActionVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case selection
    case container
    case toolbar
}

public enum ActionPlacement: String, Codable, Equatable, Sendable {
    case rootMenu
    case submenu
}

public enum MenuGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case commonDirectories
    case moveToCommonDirectory
    case copyToCommonDirectory
    case createFile
    case developerEntrypoints
    case commandTemplates
    case fileOperations
}

public struct ActionPayload: Codable, Equatable, Sendable {
    public var directoryID: String?
    public var templateID: String?
    public var developerEntrypointID: String?
    public var commandTemplateID: String?

    public init(
        directoryID: String? = nil,
        templateID: String? = nil,
        developerEntrypointID: String? = nil,
        commandTemplateID: String? = nil
    ) {
        self.directoryID = directoryID
        self.templateID = templateID
        self.developerEntrypointID = developerEntrypointID
        self.commandTemplateID = commandTemplateID
    }
}

public enum CommandWorkingDirectoryMode: String, Codable, CaseIterable, Equatable, Sendable {
    case currentDirectory
    case selectedItemDirectory
}

public struct CommandEnvironmentVariable: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var value: String?
    public var isSensitive: Bool
    public var secretReference: String?

    public init(
        id: String,
        name: String,
        value: String? = nil,
        isSensitive: Bool = false,
        secretReference: String? = nil
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.isSensitive = isSensitive
        self.secretReference = secretReference
    }
}

public struct CommandTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var command: String
    public var workingDirectoryMode: CommandWorkingDirectoryMode
    public var timeoutSeconds: Int
    public var environment: [CommandEnvironmentVariable]

    public init(
        id: String,
        title: String,
        command: String,
        workingDirectoryMode: CommandWorkingDirectoryMode = .currentDirectory,
        timeoutSeconds: Int = RightClickProConstants.defaultCommandTimeoutSeconds,
        environment: [CommandEnvironmentVariable] = []
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.workingDirectoryMode = workingDirectoryMode
        self.timeoutSeconds = timeoutSeconds
        self.environment = environment
    }
}

public struct RightClickProAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var kind: ActionKind
    public var visibility: Set<ActionVisibility>
    public var placement: ActionPlacement
    public var group: MenuGroup?
    public var isEnabled: Bool
    public var order: Int
    public var payload: ActionPayload

    public init(
        id: String,
        title: String,
        kind: ActionKind,
        visibility: Set<ActionVisibility>,
        placement: ActionPlacement,
        group: MenuGroup? = nil,
        isEnabled: Bool = true,
        order: Int,
        payload: ActionPayload = ActionPayload()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.visibility = visibility
        self.placement = placement
        self.group = group
        self.isEnabled = isEnabled
        self.order = order
        self.payload = payload
    }
}

public struct FileTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var defaultFileName: String
    public var contents: String

    public init(id: String, title: String, defaultFileName: String, contents: String = "") {
        self.id = id
        self.title = title
        self.defaultFileName = defaultFileName
        self.contents = contents
    }
}

public enum DeveloperTargetMode: String, Codable, Equatable, Sendable {
    case dynamic
    case currentDirectory
    case selectedItem
    case selectedItemDirectory
}

public struct DeveloperEntrypoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var bundleIdentifier: String
    public var targetMode: DeveloperTargetMode

    public init(
        id: String,
        title: String,
        bundleIdentifier: String,
        targetMode: DeveloperTargetMode = .dynamic
    ) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.targetMode = targetMode
    }
}

public struct RightClickProConfig: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var maxRootMenuActions: Int
    public var shortcutDirectoryIDs: [String]
    public var actions: [RightClickProAction]
    public var fileTemplates: [FileTemplate]
    public var developerEntrypoints: [DeveloperEntrypoint]
    public var commandTemplates: [CommandTemplate]

    public init(
        schemaVersion: Int = RightClickProConstants.currentSchemaVersion,
        maxRootMenuActions: Int = RightClickProConstants.defaultMaxRootMenuActions,
        shortcutDirectoryIDs: [String] = [],
        actions: [RightClickProAction] = RightClickProConfig.defaultActions(),
        fileTemplates: [FileTemplate] = RightClickProConfig.defaultFileTemplates(),
        developerEntrypoints: [DeveloperEntrypoint] = RightClickProConfig.defaultDeveloperEntrypoints(),
        commandTemplates: [CommandTemplate] = RightClickProConfig.defaultCommandTemplates()
    ) {
        self.schemaVersion = schemaVersion
        self.maxRootMenuActions = maxRootMenuActions
        self.shortcutDirectoryIDs = shortcutDirectoryIDs
        self.actions = actions
        self.fileTemplates = fileTemplates
        self.developerEntrypoints = developerEntrypoints
        self.commandTemplates = commandTemplates
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case maxRootMenuActions
        case shortcutDirectoryIDs
        case monitoredDirectoryIDs
        case commonDirectoryIDs
        case actions
        case fileTemplates
        case developerEntrypoints
        case commandTemplates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? RightClickProConstants.currentSchemaVersion
        self.maxRootMenuActions = try container.decodeIfPresent(Int.self, forKey: .maxRootMenuActions) ?? RightClickProConstants.defaultMaxRootMenuActions
        self.shortcutDirectoryIDs = try container.decodeIfPresent([String].self, forKey: .shortcutDirectoryIDs)
            ?? container.decodeIfPresent([String].self, forKey: .commonDirectoryIDs)
            ?? []
        self.actions = try container.decodeIfPresent([RightClickProAction].self, forKey: .actions) ?? RightClickProConfig.defaultActions()
        self.fileTemplates = try container.decodeIfPresent([FileTemplate].self, forKey: .fileTemplates) ?? RightClickProConfig.defaultFileTemplates()
        self.developerEntrypoints = try container.decodeIfPresent([DeveloperEntrypoint].self, forKey: .developerEntrypoints) ?? RightClickProConfig.defaultDeveloperEntrypoints()
        self.commandTemplates = try container.decodeIfPresent([CommandTemplate].self, forKey: .commandTemplates) ?? RightClickProConfig.defaultCommandTemplates()
        if self.schemaVersion < RightClickProConstants.currentSchemaVersion {
            self.schemaVersion = RightClickProConstants.currentSchemaVersion
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(RightClickProConstants.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(maxRootMenuActions, forKey: .maxRootMenuActions)
        try container.encode(shortcutDirectoryIDs, forKey: .shortcutDirectoryIDs)
        try container.encode(actions, forKey: .actions)
        try container.encode(fileTemplates, forKey: .fileTemplates)
        try container.encode(developerEntrypoints, forKey: .developerEntrypoints)
        try container.encode(commandTemplates, forKey: .commandTemplates)
    }

    public static func defaultFileTemplates() -> [FileTemplate] {
        [
            FileTemplate(id: "template-txt", title: "空白文本", defaultFileName: "Untitled.txt"),
            FileTemplate(id: "template-md", title: "Markdown", defaultFileName: "Untitled.md", contents: "# Untitled\n"),
            FileTemplate(id: "template-json", title: "JSON", defaultFileName: "Untitled.json", contents: "{\n  \n}\n"),
            FileTemplate(id: "template-gitignore", title: "Git Ignore", defaultFileName: ".gitignore"),
            FileTemplate(id: "template-swift", title: "Swift 文件", defaultFileName: "Untitled.swift", contents: "import Foundation\n\n")
        ]
    }

    public static func defaultDeveloperEntrypoints() -> [DeveloperEntrypoint] {
        [
            DeveloperEntrypoint(id: "developer-terminal", title: "在 Terminal 打开", bundleIdentifier: "com.apple.Terminal"),
            DeveloperEntrypoint(id: "developer-vscode", title: "在 VS Code 打开", bundleIdentifier: "com.microsoft.VSCode"),
            DeveloperEntrypoint(id: "developer-cursor", title: "在 Cursor 打开", bundleIdentifier: "com.todesktop.230313mzl4w4u92")
        ]
    }

    public static func defaultCommandTemplates() -> [CommandTemplate] {
        [
            CommandTemplate(id: "command-git-status", title: "Git Status", command: "git status --short"),
            CommandTemplate(id: "command-list-files", title: "List Files", command: "ls -la"),
            CommandTemplate(id: "command-print-working-directory", title: "Print Working Directory", command: "pwd")
        ]
    }

    public static func defaultActions() -> [RightClickProAction] {
        [
            RightClickProAction(
                id: "paste-here",
                title: "粘贴到此处",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                group: .fileOperations,
                order: 10
            ),
            RightClickProAction(
                id: "cut-selection",
                title: "剪切",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 20
            ),
            RightClickProAction(
                id: "new-markdown",
                title: "新建 Markdown 文件",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: 30,
                payload: ActionPayload(templateID: "template-md")
            ),
            RightClickProAction(
                id: "open-terminal",
                title: "在 Terminal 打开",
                kind: .openInApp,
                visibility: [.selection, .container, .toolbar],
                placement: .submenu,
                group: .developerEntrypoints,
                order: 40,
                payload: ActionPayload(developerEntrypointID: "developer-terminal")
            ),
            RightClickProAction(
                id: "open-vscode",
                title: "在 VS Code 打开",
                kind: .openInApp,
                visibility: [.selection, .container, .toolbar],
                placement: .submenu,
                group: .developerEntrypoints,
                order: 50,
                payload: ActionPayload(developerEntrypointID: "developer-vscode")
            ),
            RightClickProAction(
                id: "open-cursor",
                title: "在 Cursor 打开",
                kind: .openInApp,
                visibility: [.selection, .container, .toolbar],
                placement: .submenu,
                group: .developerEntrypoints,
                order: 60,
                payload: ActionPayload(developerEntrypointID: "developer-cursor")
            )
        ] + defaultCommandTemplates().enumerated().map { index, template in
            RightClickProAction(
                id: "run-\(template.id)",
                title: template.title,
                kind: .runCommand,
                visibility: [.selection, .container],
                placement: .submenu,
                group: .commandTemplates,
                order: 70 + index * 10,
                payload: ActionPayload(commandTemplateID: template.id)
            )
        }
    }
}

public extension RightClickProConstants {
    static let defaultCommandTimeoutSeconds = 60
    static let minimumCommandTimeoutSeconds = 5
    static let maximumCommandTimeoutSeconds = 600
    static let pendingCommandRunNotificationName = "com.iheeleme.rightclickpro.pending-command-run"
    static let mainAppBundleIdentifier = "com.iheeleme.rightclickpro"
    static let commandEnvironmentKeychainService = "com.iheeleme.rightclickpro.command-env"
}
