import Foundation

public enum RightToolConstants {
    public static let currentSchemaVersion = 1
    public static let defaultAppGroupIdentifier = "group.com.iheeleme.rightclickpro"
    public static let defaultXPCServiceName = "com.iheeleme.rightclickpro.ActionRunner"
    public static let defaultMaxRootMenuActions = 5
}

public enum ActionKind: String, Codable, CaseIterable, Equatable {
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

public enum ActionVisibility: String, Codable, CaseIterable, Hashable {
    case selection
    case container
    case toolbar
}

public enum ActionPlacement: String, Codable, Equatable {
    case rootMenu
    case submenu
}

public enum MenuGroup: String, Codable, CaseIterable, Hashable {
    case commonDirectories
    case moveToCommonDirectory
    case copyToCommonDirectory
    case createFile
    case developerEntrypoints
    case commandTemplates
    case fileOperations
}

public struct ActionPayload: Codable, Equatable {
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

public enum CommandWorkingDirectoryMode: String, Codable, CaseIterable, Equatable {
    case currentDirectory
    case selectedItemDirectory
}

public struct CommandEnvironmentVariable: Codable, Equatable, Identifiable {
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

public struct CommandTemplate: Codable, Equatable, Identifiable {
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
        timeoutSeconds: Int = RightToolConstants.defaultCommandTimeoutSeconds,
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

public struct RightToolAction: Codable, Equatable, Identifiable {
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

public struct FileTemplate: Codable, Equatable, Identifiable {
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

public enum DeveloperTargetMode: String, Codable, Equatable {
    case dynamic
    case currentDirectory
    case selectedItem
    case selectedItemDirectory
}

public struct DeveloperEntrypoint: Codable, Equatable, Identifiable {
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

public struct RightToolConfig: Codable, Equatable {
    public var schemaVersion: Int
    public var maxRootMenuActions: Int
    public var monitoredDirectoryIDs: [String]
    public var commonDirectoryIDs: [String]
    public var actions: [RightToolAction]
    public var fileTemplates: [FileTemplate]
    public var developerEntrypoints: [DeveloperEntrypoint]
    public var commandTemplates: [CommandTemplate]

    public init(
        schemaVersion: Int = RightToolConstants.currentSchemaVersion,
        maxRootMenuActions: Int = RightToolConstants.defaultMaxRootMenuActions,
        monitoredDirectoryIDs: [String] = [],
        commonDirectoryIDs: [String] = [],
        actions: [RightToolAction] = RightToolConfig.defaultActions(),
        fileTemplates: [FileTemplate] = RightToolConfig.defaultFileTemplates(),
        developerEntrypoints: [DeveloperEntrypoint] = RightToolConfig.defaultDeveloperEntrypoints(),
        commandTemplates: [CommandTemplate] = RightToolConfig.defaultCommandTemplates()
    ) {
        self.schemaVersion = schemaVersion
        self.maxRootMenuActions = maxRootMenuActions
        self.monitoredDirectoryIDs = monitoredDirectoryIDs
        self.commonDirectoryIDs = commonDirectoryIDs
        self.actions = actions
        self.fileTemplates = fileTemplates
        self.developerEntrypoints = developerEntrypoints
        self.commandTemplates = commandTemplates
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case maxRootMenuActions
        case monitoredDirectoryIDs
        case commonDirectoryIDs
        case actions
        case fileTemplates
        case developerEntrypoints
        case commandTemplates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? RightToolConstants.currentSchemaVersion
        self.maxRootMenuActions = try container.decodeIfPresent(Int.self, forKey: .maxRootMenuActions) ?? RightToolConstants.defaultMaxRootMenuActions
        self.monitoredDirectoryIDs = try container.decodeIfPresent([String].self, forKey: .monitoredDirectoryIDs) ?? []
        self.commonDirectoryIDs = try container.decodeIfPresent([String].self, forKey: .commonDirectoryIDs) ?? []
        self.actions = try container.decodeIfPresent([RightToolAction].self, forKey: .actions) ?? RightToolConfig.defaultActions()
        self.fileTemplates = try container.decodeIfPresent([FileTemplate].self, forKey: .fileTemplates) ?? RightToolConfig.defaultFileTemplates()
        self.developerEntrypoints = try container.decodeIfPresent([DeveloperEntrypoint].self, forKey: .developerEntrypoints) ?? RightToolConfig.defaultDeveloperEntrypoints()
        self.commandTemplates = try container.decodeIfPresent([CommandTemplate].self, forKey: .commandTemplates) ?? RightToolConfig.defaultCommandTemplates()
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

    public static func defaultActions() -> [RightToolAction] {
        [
            RightToolAction(
                id: "paste-here",
                title: "粘贴到此处",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                group: .fileOperations,
                order: 10
            ),
            RightToolAction(
                id: "cut-selection",
                title: "剪切",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 20
            ),
            RightToolAction(
                id: "new-markdown",
                title: "新建 Markdown 文件",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: 30,
                payload: ActionPayload(templateID: "template-md")
            ),
            RightToolAction(
                id: "open-terminal",
                title: "在 Terminal 打开",
                kind: .openInApp,
                visibility: [.selection, .container, .toolbar],
                placement: .submenu,
                group: .developerEntrypoints,
                order: 40,
                payload: ActionPayload(developerEntrypointID: "developer-terminal")
            ),
            RightToolAction(
                id: "open-vscode",
                title: "在 VS Code 打开",
                kind: .openInApp,
                visibility: [.selection, .container, .toolbar],
                placement: .submenu,
                group: .developerEntrypoints,
                order: 50,
                payload: ActionPayload(developerEntrypointID: "developer-vscode")
            ),
            RightToolAction(
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
            RightToolAction(
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

public extension RightToolConstants {
    static let defaultCommandTimeoutSeconds = 60
    static let minimumCommandTimeoutSeconds = 5
    static let maximumCommandTimeoutSeconds = 600
    static let pendingCommandRunNotificationName = "com.iheeleme.rightclickpro.pending-command-run"
    static let mainAppBundleIdentifier = "com.iheeleme.rightclickpro"
    static let commandEnvironmentKeychainService = "com.iheeleme.rightclickpro.command-env"
}
