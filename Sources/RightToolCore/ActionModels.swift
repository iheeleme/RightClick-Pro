import Foundation

public enum RightToolConstants {
    public static let currentSchemaVersion = 1
    public static let defaultAppGroupIdentifier = "group.com.righttool.app"
    public static let defaultXPCServiceName = "com.righttool.app.ActionRunner"
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
        targetMode: DeveloperTargetMode = .currentDirectory
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

    public init(
        schemaVersion: Int = RightToolConstants.currentSchemaVersion,
        maxRootMenuActions: Int = RightToolConstants.defaultMaxRootMenuActions,
        monitoredDirectoryIDs: [String] = [],
        commonDirectoryIDs: [String] = [],
        actions: [RightToolAction] = RightToolConfig.defaultActions(),
        fileTemplates: [FileTemplate] = RightToolConfig.defaultFileTemplates(),
        developerEntrypoints: [DeveloperEntrypoint] = RightToolConfig.defaultDeveloperEntrypoints()
    ) {
        self.schemaVersion = schemaVersion
        self.maxRootMenuActions = maxRootMenuActions
        self.monitoredDirectoryIDs = monitoredDirectoryIDs
        self.commonDirectoryIDs = commonDirectoryIDs
        self.actions = actions
        self.fileTemplates = fileTemplates
        self.developerEntrypoints = developerEntrypoints
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
        ]
    }
}
