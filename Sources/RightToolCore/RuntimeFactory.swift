import Foundation

public enum RightToolRuntimeFactory {
    public static func makeActionRunner(paths: RightToolStoragePaths) -> ActionRunner {
        let configProvider = FileBackedRightToolConfigProvider(paths: paths)
        let operationLog = JSONLineOperationLog(url: paths.operationLogURL)
        let cutClipboard = FileBackedCutClipboardStore(url: paths.cutClipboardURL)

        #if canImport(AppKit)
        let opener = NSWorkspaceURLOpener()
        #else
        let opener = RecordingURLOpener()
        #endif

        return ActionRunner(
            configProvider: configProvider,
            operationLog: operationLog,
            cutClipboard: cutClipboard,
            urlOpener: opener,
            developerAppOpener: opener
        )
    }
}
