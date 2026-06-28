import XCTest
@testable import RightClickProCore

final class SystemMaintenanceTests: XCTestCase {
    func testRepairFinderContextMenuRegistersEnablesAndRestartsFinder() {
        let runner = RecordingCommandRunner(results: [
            "/usr/bin/pluginkit -a /Applications/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex": .success(),
            "/usr/bin/pluginkit -e use -i com.iheeleme.rightclickpro.FinderExtension": .success(),
            "/usr/bin/killall Finder": .success(),
            "/usr/bin/open -b com.apple.finder": .success()
        ])
        let service = SystemMaintenanceService(commandRunner: runner, fileExists: { _ in true })

        let result = service.perform(
            SystemMaintenanceRequest(
                task: .repairFinderContextMenu,
                finderExtensionPath: "/Applications/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex"
            )
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.didRegisterFinderExtension)
        XCTAssertTrue(result.didEnableFinderExtension)
        XCTAssertTrue(result.didRestartFinder)
        XCTAssertEqual(runner.calls, [
            "/usr/bin/pluginkit -a /Applications/RightClick Pro.app/Contents/PlugIns/RightClickProFinderExtension.appex",
            "/usr/bin/pluginkit -e use -i com.iheeleme.rightclickpro.FinderExtension",
            "/usr/bin/killall Finder",
            "/usr/bin/open -b com.apple.finder"
        ])
    }

    func testInstallFinderExtensionRequiresBundledAppexPath() {
        let runner = RecordingCommandRunner(results: [:])
        let service = SystemMaintenanceService(commandRunner: runner, fileExists: { _ in false })

        let result = service.perform(
            SystemMaintenanceRequest(
                task: .installFinderExtension,
                finderExtensionPath: "/missing/RightClickProFinderExtension.appex"
            )
        )

        XCTAssertFalse(result.isSuccess)
        XCTAssertFalse(result.didRegisterFinderExtension)
        XCTAssertTrue(result.errors.first?.contains("找不到随 App 打包的 Finder Extension") == true)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testRestartFinderFallsBackToAppleScriptWhenKillallFails() {
        let runner = RecordingCommandRunner(results: [
            "/usr/bin/killall Finder": .failure(status: 1, stderr: "Operation not permitted"),
            "/usr/bin/osascript -e tell application \"Finder\" to quit": .success(),
            "/usr/bin/open -b com.apple.finder": .success()
        ])
        let service = SystemMaintenanceService(commandRunner: runner)

        let result = service.perform(SystemMaintenanceRequest(task: .restartFinder))

        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.didRestartFinder)
        XCTAssertEqual(runner.calls, [
            "/usr/bin/killall Finder",
            "/usr/bin/osascript -e tell application \"Finder\" to quit",
            "/usr/bin/open -b com.apple.finder"
        ])
    }
}

private final class RecordingCommandRunner: SystemCommandRunning {
    typealias ResultMap = [String: SystemCommandResult]

    private let results: ResultMap
    private(set) var calls: [String] = []

    init(results: ResultMap) {
        self.results = results
    }

    func run(_ executablePath: String, arguments: [String]) throws -> SystemCommandResult {
        let key = ([executablePath] + arguments).joined(separator: " ")
        calls.append(key)
        return results[key] ?? .failure(status: 127, stderr: "missing fake result")
    }
}

private extension SystemCommandResult {
    static func success(stdout: String = "") -> SystemCommandResult {
        SystemCommandResult(terminationStatus: 0, standardOutput: stdout)
    }

    static func failure(status: Int32, stderr: String) -> SystemCommandResult {
        SystemCommandResult(terminationStatus: status, standardError: stderr)
    }
}
