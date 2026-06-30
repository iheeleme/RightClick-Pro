import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorSheetHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = SettingsTheme.accent

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(SettingsTheme.headerBackground)
    }
}

struct EditorTextField: View {
    let title: String
    let placeholder: String
    var helper: String? = nil
    var systemImage: String? = nil
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsTheme.ink)

            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.muted)
                        .frame(width: 16)
                }

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))

            if let helper {
                Text(helper)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(2)
            }
        }
    }
}

struct EditorTextArea: View {
    let title: String
    let helper: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                Text(helper)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
            }

            TextEditor(text: $text)
                .font(.body.monospaced())
                .foregroundStyle(SettingsTheme.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 176)
                .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))
        }
    }
}

struct EditorSheetFooter: View {
    let validationMessage: String?
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(
                validationMessage ?? "保存后需点击主界面的保存配置才会写入本地配置",
                systemImage: validationMessage == nil ? "info.circle" : "exclamationmark.circle"
            )
            .font(.system(size: 12))
            .foregroundStyle(validationMessage == nil ? SettingsTheme.muted : .orange)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Button("取消", role: .cancel) {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                onSave()
            } label: {
                Label("保存", systemImage: "checkmark")
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(SettingsTheme.headerBackground)
    }
}

struct TemplateDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var templateID: String
    var title: String
    var defaultFileName: String
    var contents: String

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        templateID = "template-custom-\(suffix)"
        title = "自定义模板"
        defaultFileName = "Untitled.txt"
        contents = ""
    }

    init(template: FileTemplate) {
        originalID = template.id
        templateID = template.id
        title = template.title
        defaultFileName = template.defaultFileName
        contents = template.contents
    }

    func makeTemplate() -> FileTemplate {
        FileTemplate(
            id: templateID.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultFileName: defaultFileName.trimmingCharacters(in: .whitespacesAndNewlines),
            contents: contents
        )
    }
}

struct TemplateEditorSheet: View {
    @State private var draft: TemplateDraft
    let onSave: (TemplateDraft) -> Void
    let onCancel: () -> Void

    init(draft: TemplateDraft, onSave: @escaping (TemplateDraft) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(
                title: draft.originalID == nil ? "新增模板" : "编辑模板",
                subtitle: "配置 Finder 右键菜单中的新建文件入口。",
                systemImage: "doc.badge.plus"
            )

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    EditorTextField(
                        title: "模板 ID",
                        placeholder: "template-custom",
                        helper: "用于关联菜单动作，建议保持英文短横线命名。",
                        systemImage: "number",
                        text: $draft.templateID
                    )

                    EditorTextField(
                        title: "模板名称",
                        placeholder: "Markdown 文件",
                        helper: "显示在设置页和右键菜单中的名称。",
                        systemImage: "textformat",
                        text: $draft.title
                    )
                }

                EditorTextField(
                    title: "默认文件名",
                    placeholder: "Untitled.md",
                    helper: "扩展名会影响菜单图标与新建文件类型。",
                    systemImage: "doc",
                    text: $draft.defaultFileName
                )

                EditorTextArea(
                    title: "文本内容",
                    helper: "支持空内容；保存后作为新建文件的初始内容。",
                    text: $draft.contents
                )
            }
            .padding(22)

            Divider()

            EditorSheetFooter(
                validationMessage: validationMessage,
                canSave: canSave,
                onCancel: onCancel
            ) {
                onSave(draft)
            }
        }
        .background(SettingsTheme.windowBackground)
        .frame(width: 560)
        .frame(minHeight: 520)
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if draft.templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板 ID"
        }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板名称"
        }
        if draft.defaultFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写默认文件名"
        }
        return nil
    }
}

struct CommandTemplateDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var templateID: String
    var title: String
    var command: String
    var workingDirectoryMode: CommandWorkingDirectoryMode
    var timeoutSecondsText: String
    var environmentText: String
    private var existingEnvironment: [CommandEnvironmentVariable]

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        templateID = "command-custom-\(suffix)"
        title = "自定义命令"
        command = "pwd"
        workingDirectoryMode = .currentDirectory
        timeoutSecondsText = "\(RightClickProConstants.defaultCommandTimeoutSeconds)"
        environmentText = ""
        existingEnvironment = []
    }

    init(template: CommandTemplate) {
        originalID = template.id
        templateID = template.id
        title = template.title
        command = template.command
        workingDirectoryMode = template.workingDirectoryMode
        timeoutSecondsText = "\(template.timeoutSeconds)"
        existingEnvironment = template.environment
        environmentText = template.environment
            .map { variable in
                if variable.isSensitive {
                    return "\(variable.name)!="
                }
                return "\(variable.name)=\(variable.value ?? "")"
            }
            .joined(separator: "\n")
    }

    func makeTemplate(secretStore: CommandSecretStoring) throws -> CommandTemplate {
        let trimmedID = templateID.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeout = Int(timeoutSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? RightClickProConstants.defaultCommandTimeoutSeconds
        let environment = try makeEnvironment(templateID: trimmedID, secretStore: secretStore)

        return CommandTemplate(
            id: trimmedID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            workingDirectoryMode: workingDirectoryMode,
            timeoutSeconds: timeout,
            environment: environment
        )
    }

    private func makeEnvironment(templateID: String, secretStore: CommandSecretStoring) throws -> [CommandEnvironmentVariable] {
        var variables: [CommandEnvironmentVariable] = []
        for rawLine in environmentText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let rawName = String(parts.first ?? "")
            let value = parts.count > 1 ? String(parts[1]) : ""
            let isSensitive = rawName.hasSuffix("!")
            let name = String((isSensitive ? rawName.dropLast() : Substring(rawName))).trimmingCharacters(in: .whitespacesAndNewlines)

            guard CommandTemplateVariableResolver.validateEnvironmentName(name) else {
                throw CommandTemplateError.invalidEnvironmentName(name)
            }

            if isSensitive {
                let existing = existingEnvironment.first { $0.name == name && $0.isSensitive }
                let reference = existing?.secretReference ?? "command-env-\(templateID)-\(name)-\(UUID().uuidString)"
                if !value.isEmpty {
                    try secretStore.save(secret: value, reference: reference)
                } else if existing?.secretReference == nil {
                    throw CommandTemplateError.missingSecret(name)
                }
                variables.append(
                    CommandEnvironmentVariable(
                        id: existing?.id ?? "env-\(name.lowercased())-\(UUID().uuidString.prefix(6))",
                        name: name,
                        value: nil,
                        isSensitive: true,
                        secretReference: reference
                    )
                )
            } else {
                let existing = existingEnvironment.first { $0.name == name && !$0.isSensitive }
                variables.append(
                    CommandEnvironmentVariable(
                        id: existing?.id ?? "env-\(name.lowercased())-\(UUID().uuidString.prefix(6))",
                        name: name,
                        value: value,
                        isSensitive: false
                    )
                )
            }
        }
        return variables
    }
}

struct CommandTemplateEditorSheet: View {
    @State private var draft: CommandTemplateDraft
    let onSave: (CommandTemplateDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: CommandTemplateDraft,
        onSave: @escaping (CommandTemplateDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(
                title: draft.originalID == nil ? "新增命令模板" : "编辑命令模板",
                subtitle: "保存常用开发命令，Finder 右键触发后会打开实时输出窗口。",
                systemImage: "terminal"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        EditorTextField(
                            title: "模板 ID",
                            placeholder: "command-git-status",
                            helper: "用于关联菜单动作，建议保持英文短横线命名。",
                            systemImage: "number",
                            text: $draft.templateID
                        )

                        EditorTextField(
                            title: "显示名称",
                            placeholder: "Git Status",
                            helper: "显示在设置页、右键菜单和实时输出窗口。",
                            systemImage: "textformat",
                            text: $draft.title
                        )
                    }

                    EditorTextArea(
                        title: "命令",
                        helper: "支持 {{currentDirectory}} / {{selectedPath}} / {{selectedPaths}}。",
                        text: $draft.command
                    )

                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("工作目录")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SettingsTheme.ink)

                            Picker("工作目录", selection: $draft.workingDirectoryMode) {
                                ForEach(CommandWorkingDirectoryMode.allCasesForSettings, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()

                            Text("命令只会在已授权目录内运行。")
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        EditorTextField(
                            title: "超时秒数",
                            placeholder: "60",
                            helper: "允许 5-600 秒，超时会先终止再强制停止。",
                            systemImage: "timer",
                            text: $draft.timeoutSecondsText
                        )
                    }

                    EditorTextArea(
                        title: "环境变量",
                        helper: "一行一个 KEY=value；敏感值写 KEY!=value，保存后进入 Keychain。",
                        text: $draft.environmentText
                    )
                }
                .padding(22)
            }
            .frame(maxHeight: 620)

            Divider()

            EditorSheetFooter(
                validationMessage: validationMessage,
                canSave: canSave,
                onCancel: onCancel
            ) {
                onSave(draft)
            }
        }
        .background(SettingsTheme.windowBackground)
        .frame(width: 640)
        .frame(minHeight: 680)
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if draft.templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板 ID"
        }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写显示名称"
        }
        if draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写命令"
        }
        guard let timeout = Int(draft.timeoutSecondsText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "超时必须是数字"
        }
        if !(RightClickProConstants.minimumCommandTimeoutSeconds...RightClickProConstants.maximumCommandTimeoutSeconds).contains(timeout) {
            return "超时必须在 5-600 秒之间"
        }
        return nil
    }
}

struct DeveloperApplicationSelection {
    var displayName: String
    var bundleIdentifier: String
    var url: URL
}

struct DeveloperEntrypointDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var entrypointID: String
    var title: String
    var bundleIdentifier: String
    var applicationPath: String?
    var targetMode: DeveloperTargetMode

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        entrypointID = "developer-custom-\(suffix)"
        title = ""
        bundleIdentifier = ""
        applicationPath = nil
        targetMode = .dynamic
    }

    init(application: DeveloperApplicationSelection, entrypointID: String) {
        originalID = nil
        self.entrypointID = entrypointID
        title = application.displayName
        bundleIdentifier = application.bundleIdentifier
        applicationPath = application.url.path
        targetMode = .dynamic
    }

    init(entrypoint: DeveloperEntrypoint) {
        originalID = entrypoint.id
        entrypointID = entrypoint.id
        title = entrypoint.title
        bundleIdentifier = entrypoint.bundleIdentifier
        applicationPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entrypoint.bundleIdentifier)?.path
        targetMode = entrypoint.targetMode
    }

    mutating func apply(application: DeveloperApplicationSelection) {
        title = application.displayName
        bundleIdentifier = application.bundleIdentifier
        applicationPath = application.url.path
    }

    func makeEntrypoint() -> DeveloperEntrypoint {
        DeveloperEntrypoint(
            id: entrypointID.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            targetMode: targetMode
        )
    }
}

struct DeveloperEntrypointEditorSheet: View {
    @State private var draft: DeveloperEntrypointDraft
    @State private var didAttemptInitialApplicationSelection = false
    let existingEntrypoints: [DeveloperEntrypoint]
    let onSelectApplication: (DeveloperEntrypointDraft) -> DeveloperEntrypointDraft?
    let onSave: (DeveloperEntrypointDraft) -> Void
    let onCancel: () -> Void

    init(
        draft: DeveloperEntrypointDraft,
        existingEntrypoints: [DeveloperEntrypoint],
        onSelectApplication: @escaping (DeveloperEntrypointDraft) -> DeveloperEntrypointDraft?,
        onSave: @escaping (DeveloperEntrypointDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        self.existingEntrypoints = existingEntrypoints
        self.onSelectApplication = onSelectApplication
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(
                title: draft.originalID == nil ? "新增开发者入口" : "编辑开发者入口",
                subtitle: "从本地应用生成快捷入口，Finder 右键菜单会优先显示真实应用图标。",
                systemImage: "terminal"
            )

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    EditorTextField(
                        title: "入口 ID",
                        placeholder: "developer-custom",
                        helper: "用于关联动作，保存后会同步到菜单项。",
                        systemImage: "number",
                        text: $draft.entrypointID
                    )

                    EditorTextField(
                        title: "显示名称",
                        placeholder: "Visual Studio Code",
                        helper: "显示在右键菜单和预览列表中。",
                        systemImage: "textformat",
                        text: $draft.title
                    )
                }

                DeveloperApplicationPickerCard(draft: draft) {
                    if let updatedDraft = onSelectApplication(draft) {
                        draft = updatedDraft
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("目标模式")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)

                    Picker("目标模式", selection: $draft.targetMode) {
                        ForEach(DeveloperTargetMode.allCasesForSettings, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    Text(draft.targetMode.helperText)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.muted)
                }
            }
            .padding(22)

            Divider()

            EditorSheetFooter(
                validationMessage: validationMessage,
                canSave: canSave,
                onCancel: onCancel
            ) {
                onSave(draft)
            }
        }
        .background(SettingsTheme.windowBackground)
        .frame(width: 560)
        .frame(minHeight: 430)
        .onAppear {
            requestInitialApplicationSelectionIfNeeded()
        }
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if draft.entrypointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写入口 ID"
        }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写显示名称"
        }
        if draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先选择本地应用"
        }
        if let duplicate = existingEntrypoints.first(where: { entrypoint in
            entrypoint.id != draft.originalID &&
                entrypoint.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(
                    draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                ) == .orderedSame
        }) {
            return "这个应用已存在：\(duplicate.title)"
        }
        return nil
    }

    private func requestInitialApplicationSelectionIfNeeded() {
        guard
            !didAttemptInitialApplicationSelection,
            draft.originalID == nil,
            draft.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        didAttemptInitialApplicationSelection = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let updatedDraft = onSelectApplication(draft) {
                draft = updatedDraft
            }
        }
    }
}

struct DeveloperApplicationPickerCard: View {
    let draft: DeveloperEntrypointDraft
    let onSelectApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地应用")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SettingsTheme.ink)

            HStack(alignment: .center, spacing: 12) {
                MenuIconView(
                    icon: appIcon,
                    tint: SettingsTheme.accent,
                    size: 30,
                    font: .system(size: 18, weight: .semibold)
                )
                .frame(width: 38, height: 38)
                .background(SettingsTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未选择应用" : draft.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)

                    Text(draft.bundleIdentifier.isEmpty ? "请选择一个 .app 应用" : draft.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsTheme.muted)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    if let path = draft.applicationPath, !path.isEmpty {
                        Text(path)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    onSelectApplication()
                } label: {
                    Label(draft.bundleIdentifier.isEmpty ? "选择应用" : "更换应用", systemImage: "app.badge")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(12)
            .background(SettingsTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsTheme.hairline))

            Text("Bundle Identifier 会从所选应用自动读取，不需要手动填写。")
                .font(.system(size: 11))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(2)
        }
    }

    private var appIcon: MenuIconDescriptor {
        draft.bundleIdentifier.isEmpty ? .systemSymbol("app") : .appBundleIdentifier(draft.bundleIdentifier)
    }
}

