import AppKit
import RightClickProCore
import SwiftUI
import UniformTypeIdentifiers

let operationDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

extension RightClickProAction {
    var managementTint: Color {
        switch group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile:
            return SettingsTheme.accent
        case .developerEntrypoints:
            return SettingsTheme.accent
        case .commandTemplates:
            return SettingsTheme.accent
        case .fileOperations:
            return .cyan
        case .none:
            return SettingsTheme.muted
        }
    }

    var managementType: String {
        if kind == .createFile || group == .createFile {
            return "新建"
        }

        if group == .developerEntrypoints || group == .commandTemplates || kind == .openInApp || kind == .runCommand {
            return "工具"
        }

        return "操作"
    }

    var managementSubtitle: String {
        switch kind {
        case .openDirectory:
            return "快速访问常用位置"
        case .moveToDirectory:
            return "移动所选项目到指定目录"
        case .copyToDirectory:
            return "复制所选项目到指定目录"
        case .cut:
            return "剪切所选项目到剪贴板"
        case .paste:
            return "粘贴剪贴板中的文件"
        case .createFile:
            return "在当前目录创建 \(payload.templateID ?? "文件")"
        case .openInApp:
            return "快速打开开发者常用工具"
        case .runCommand:
            return "在当前路径执行命令"
        case .undoOperation:
            return "撤销最近一次文件操作"
        }
    }

    var visibilityPills: [String] {
        var labels: [String] = []
        if visibility.contains(.toolbar) {
            labels.append("Finder")
        }
        if visibility.contains(.selection) {
            labels.append("文件/文件夹")
        }
        if visibility.contains(.container) {
            labels.append("桌面空白处")
        }
        return labels.isEmpty ? ["未设置"] : labels
    }
}

extension ActionKind {
    var displayName: String {
        switch self {
        case .openDirectory:
            return "打开目录"
        case .moveToDirectory:
            return "移动到目录"
        case .copyToDirectory:
            return "复制到目录"
        case .cut:
            return "剪切"
        case .paste:
            return "粘贴"
        case .createFile:
            return "新建文件"
        case .openInApp:
            return "开发者入口"
        case .runCommand:
            return "运行命令"
        case .undoOperation:
            return "撤销操作"
        }
    }

}

extension CommandWorkingDirectoryMode {
    static var allCasesForSettings: [CommandWorkingDirectoryMode] {
        [.currentDirectory, .selectedItemDirectory]
    }

    var displayName: String {
        switch self {
        case .currentDirectory:
            return "当前 Finder 目录"
        case .selectedItemDirectory:
            return "选中项所在目录"
        }
    }
}

extension ActionPlacement {
    var displayName: String {
        switch self {
        case .rootMenu:
            return "一级菜单"
        case .submenu:
            return "分组菜单"
        }
    }

    var systemImage: String {
        switch self {
        case .rootMenu:
            return "menubar.rectangle"
        case .submenu:
            return "rectangle.3.group"
        }
    }
}

extension MenuGroup {
    var displayName: String {
        switch self {
        case .commonDirectories:
            return "前往常用目录"
        case .moveToCommonDirectory:
            return "移动到常用目录"
        case .copyToCommonDirectory:
            return "复制到常用目录"
        case .createFile:
            return "新建文件"
        case .developerEntrypoints:
            return "开发者工具"
        case .commandTemplates:
            return "命令模板"
        case .fileOperations:
            return "文件操作"
        }
    }

    var previewIcon: MenuIconDescriptor {
        switch self {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .folder
        case .createFile:
            return .systemSymbol("doc.badge.plus")
        case .developerEntrypoints:
            return .systemSymbol("chevron.left.forwardslash.chevron.right")
        case .commandTemplates:
            return .systemSymbol("terminal")
        case .fileOperations:
            return .systemSymbol("scissors")
        }
    }

    var previewTint: Color {
        switch self {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile, .developerEntrypoints, .commandTemplates:
            return SettingsTheme.accent
        case .fileOperations:
            return .cyan
        }
    }
}

extension Set where Element == ActionVisibility {
    var displayName: String {
        sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: " / ")
    }
}

extension ActionVisibility {
    var displayName: String {
        switch self {
        case .selection:
            return "选中文件"
        case .container:
            return "空白处"
        case .toolbar:
            return "工具栏"
        }
    }

    var systemImage: String {
        switch self {
        case .selection:
            return "checkmark.rectangle"
        case .container:
            return "rectangle.dashed"
        case .toolbar:
            return "sidebar.right"
        }
    }

    var helperText: String {
        switch self {
        case .selection:
            return "选中项目时显示"
        case .container:
            return "右键空白处时显示"
        case .toolbar:
            return "Finder 工具栏菜单中显示"
        }
    }
}

extension DeveloperTargetMode {
    static var allCasesForSettings: [DeveloperTargetMode] {
        [.dynamic, .currentDirectory, .selectedItem, .selectedItemDirectory]
    }

    var displayName: String {
        switch self {
        case .dynamic:
            return "动态"
        case .currentDirectory:
            return "当前目录"
        case .selectedItem:
            return "选中项目"
        case .selectedItemDirectory:
            return "选中项目所在目录"
        }
    }

    var helperText: String {
        switch self {
        case .dynamic:
            return "选中项目右键时传入选中项；空白处右键时传入当前 Finder 目录。"
        case .currentDirectory:
            return "始终把当前 Finder 目录传给目标应用。"
        case .selectedItem:
            return "优先把第一个选中项目传给目标应用，没有选中项时回退当前目录。"
        case .selectedItemDirectory:
            return "优先把第一个选中项目所在目录传给目标应用，没有选中项时回退当前目录。"
        }
    }
}

extension OperationKind {
    var displayName: String {
        switch self {
        case .openDirectory:
            return "打开目录"
        case .move:
            return "移动"
        case .copy:
            return "复制"
        case .cut:
            return "剪切"
        case .paste:
            return "粘贴"
        case .createFile:
            return "新建文件"
        case .openInApp:
            return "开发者入口"
        case .runCommand:
            return "运行命令"
        case .unsupported:
            return "未支持"
        }
    }
}

extension OperationRecordStatus {
    var displayName: String {
        switch self {
        case .success:
            return "成功"
        case .failure:
            return "失败"
        case .cancelled:
            return "取消"
        }
    }

    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle"
        case .failure:
            return "xmark.octagon"
        case .cancelled:
            return "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .success:
            return .primary
        case .failure:
            return .red
        case .cancelled:
            return .orange
        }
    }
}
