import Foundation
import RightToolCore

final class ActionRunnerServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject: RightToolActionRunnerXPCAdapter

    init(exportedObject: RightToolActionRunnerXPCAdapter) {
        self.exportedObject = exportedObject
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RightToolActionRunnerXPCProtocol.self)
        connection.exportedObject = exportedObject
        connection.resume()
        return true
    }
}

let paths: RightToolStoragePaths
if let override = ProcessInfo.processInfo.environment["RIGHTTOOL_STORAGE_PATH"] {
    paths = RightToolStoragePaths(baseURL: URL(fileURLWithPath: override))
} else {
    paths = (try? RightToolStoragePaths.appGroup()) ?? RightToolStoragePaths(
        baseURL: FileManager.default.temporaryDirectory.appendingPathComponent("RightTool")
    )
}

let runner = RightToolRuntimeFactory.makeActionRunner(paths: paths)
let adapter = RightToolActionRunnerXPCAdapter(runner: runner)
let delegate = ActionRunnerServiceDelegate(exportedObject: adapter)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
