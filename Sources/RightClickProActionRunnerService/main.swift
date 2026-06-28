import Foundation
import RightClickProCore

final class ActionRunnerServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject: RightClickProActionRunnerXPCAdapter

    init(exportedObject: RightClickProActionRunnerXPCAdapter) {
        self.exportedObject = exportedObject
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RightClickProActionRunnerXPCProtocol.self)
        connection.exportedObject = exportedObject
        connection.resume()
        return true
    }
}

let paths: RightClickProStoragePaths
if let override = ProcessInfo.processInfo.environment["RIGHTCLICKPRO_STORAGE_PATH"] {
    paths = RightClickProStoragePaths(baseURL: URL(fileURLWithPath: override))
} else {
    paths = RightClickProStoragePaths.defaultForCurrentProcess()
}

let runner = RightClickProRuntimeFactory.makeActionRunner(paths: paths)
let commandRunService = CommandRunService(paths: paths)
let adapter = RightClickProActionRunnerXPCAdapter(runner: runner, commandRunService: commandRunService)
let delegate = ActionRunnerServiceDelegate(exportedObject: adapter)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
