import Foundation

public enum RightClickProRuntimeFactory {
    public static func defaultStoragePaths() -> RightClickProStoragePaths {
        RightClickProStoragePaths.defaultForCurrentProcess()
    }

    public static func makeActionRunner(paths: RightClickProStoragePaths) -> ActionRunner {
        let configProvider = FileBackedRightClickProConfigProvider(paths: paths)
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
