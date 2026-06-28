import XCTest
@testable import RightClickProCore

final class AppOpeningTests: XCTestCase {
    func testCodexUsesBundledAppCLIWithWorkspaceDirectory() throws {
        let appURL = try fakeApp(named: "Codex", executablePaths: ["Contents/Resources/codex"])
        let workspaceURL = try temporaryDirectory()
        let entrypoint = DeveloperEntrypoint(
            id: "developer-codex",
            title: "在 Codex 打开",
            bundleIdentifier: "com.openai.codex"
        )

        let plan = DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: workspaceURL, appURL: appURL)

        XCTAssertEqual(
            plan,
            .workspaceCommand(
                DeveloperWorkspaceOpenPlan(
                    executableURL: appURL.appendingPathComponent("Contents/Resources/codex"),
                    arguments: ["app", workspaceURL.path]
                )
            )
        )
    }

    func testWorkspaceOpenersUseParentDirectoryForFileTargets() throws {
        let appURL = try fakeApp(named: "Codex", executablePaths: ["Contents/Resources/codex"])
        let workspaceURL = try temporaryDirectory()
        let fileURL = workspaceURL.appendingPathComponent("README.md")
        try "# Test\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let entrypoint = DeveloperEntrypoint(
            id: "developer-codex",
            title: "在 Codex 打开",
            bundleIdentifier: "com.openai.codex"
        )

        let plan = DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: fileURL, appURL: appURL)

        XCTAssertEqual(
            plan,
            .workspaceCommand(
                DeveloperWorkspaceOpenPlan(
                    executableURL: appURL.appendingPathComponent("Contents/Resources/codex"),
                    arguments: ["app", workspaceURL.path]
                )
            )
        )
    }

    func testTerminalUsesParentDirectoryForFileTargets() throws {
        let appURL = try fakeApp(named: "Terminal", executablePaths: [])
        let workspaceURL = try temporaryDirectory()
        let fileURL = workspaceURL.appendingPathComponent("README.md")
        try "# Test\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let entrypoint = DeveloperEntrypoint(
            id: "developer-terminal",
            title: "在 Terminal 打开",
            bundleIdentifier: "com.apple.Terminal"
        )

        let plan = DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: fileURL, appURL: appURL)

        XCTAssertEqual(plan, .application(appURL: appURL, targetURL: workspaceURL))
    }

    func testVSCodeFamilyAppsUseBundledEditorCLI() throws {
        let cases: [(String, String, String)] = [
            ("Visual Studio Code", "com.microsoft.VSCode", "Contents/Resources/app/bin/code"),
            ("Cursor", "com.todesktop.230313mzl4w4u92", "Contents/Resources/app/bin/cursor"),
            ("Windsurf", "com.exafunction.windsurf", "Contents/Resources/app/bin/windsurf"),
            ("Trae", "com.trae.app", "Contents/Resources/app/bin/trae")
        ]

        for (appName, bundleIdentifier, executablePath) in cases {
            let appURL = try fakeApp(named: appName, executablePaths: [executablePath])
            let workspaceURL = try temporaryDirectory()
            let entrypoint = DeveloperEntrypoint(
                id: "developer-\(appName.lowercased())",
                title: "在 \(appName) 打开",
                bundleIdentifier: bundleIdentifier
            )

            let plan = DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: workspaceURL, appURL: appURL)

            XCTAssertEqual(
                plan,
                .workspaceCommand(
                    DeveloperWorkspaceOpenPlan(
                        executableURL: appURL.appendingPathComponent(executablePath),
                        arguments: [workspaceURL.path]
                    )
                ),
                appName
            )
        }
    }

    func testJetBrainsAppsUseProductSpecificLauncher() throws {
        let cases: [(String, String, String)] = [
            ("IntelliJ IDEA", "com.jetbrains.intellij", "Contents/MacOS/idea"),
            ("WebStorm", "com.jetbrains.WebStorm", "Contents/MacOS/webstorm"),
            ("PyCharm", "com.jetbrains.PyCharm", "Contents/MacOS/pycharm")
        ]

        for (appName, bundleIdentifier, executablePath) in cases {
            let appURL = try fakeApp(named: appName, executablePaths: [executablePath])
            let workspaceURL = try temporaryDirectory()
            let entrypoint = DeveloperEntrypoint(
                id: "developer-\(appName.lowercased())",
                title: "在 \(appName) 打开",
                bundleIdentifier: bundleIdentifier
            )

            let plan = DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: workspaceURL, appURL: appURL)

            XCTAssertEqual(
                plan,
                .workspaceCommand(
                    DeveloperWorkspaceOpenPlan(
                        executableURL: appURL.appendingPathComponent(executablePath),
                        arguments: [workspaceURL.path]
                    )
                ),
                appName
            )
        }
    }

    func testSublimeUsesBundledCLIAndUnknownAppsFallBackToNSWorkspace() throws {
        let sublimeURL = try fakeApp(named: "Sublime Text", executablePaths: ["Contents/SharedSupport/bin/subl"])
        let workspaceURL = try temporaryDirectory()
        let sublimeEntrypoint = DeveloperEntrypoint(
            id: "developer-sublime",
            title: "在 Sublime Text 打开",
            bundleIdentifier: "com.sublimetext.4"
        )

        let sublimePlan = DeveloperAppOpenPlanner.plan(for: sublimeEntrypoint, targetURL: workspaceURL, appURL: sublimeURL)

        XCTAssertEqual(
            sublimePlan,
            .workspaceCommand(
                DeveloperWorkspaceOpenPlan(
                    executableURL: sublimeURL.appendingPathComponent("Contents/SharedSupport/bin/subl"),
                    arguments: [workspaceURL.path]
                )
            )
        )

        let unknownURL = try fakeApp(named: "Unknown Editor", executablePaths: [])
        let unknownEntrypoint = DeveloperEntrypoint(
            id: "developer-unknown",
            title: "在 Unknown 打开",
            bundleIdentifier: "com.example.Unknown"
        )

        XCTAssertEqual(
            DeveloperAppOpenPlanner.plan(for: unknownEntrypoint, targetURL: workspaceURL, appURL: unknownURL),
            .application(appURL: unknownURL, targetURL: workspaceURL)
        )
    }

    func testOtherDocumentedEditorCLIsUseKnownLaunchers() throws {
        let cases: [(String, String, String)] = [
            ("Zed", "dev.zed.zed", "Contents/MacOS/cli"),
            ("TextMate", "com.macromates.TextMate", "Contents/Resources/mate"),
            ("Nova", "com.panic.Nova", "Contents/SharedSupport/bin/nova")
        ]

        for (appName, bundleIdentifier, executablePath) in cases {
            let appURL = try fakeApp(named: appName, executablePaths: [executablePath])
            let workspaceURL = try temporaryDirectory()
            let entrypoint = DeveloperEntrypoint(
                id: "developer-\(appName.lowercased())",
                title: "在 \(appName) 打开",
                bundleIdentifier: bundleIdentifier
            )

            let plan = DeveloperAppOpenPlanner.plan(for: entrypoint, targetURL: workspaceURL, appURL: appURL)

            XCTAssertEqual(
                plan,
                .workspaceCommand(
                    DeveloperWorkspaceOpenPlan(
                        executableURL: appURL.appendingPathComponent(executablePath),
                        arguments: [workspaceURL.path]
                    )
                ),
                appName
            )
        }
    }

    private func fakeApp(named name: String, executablePaths: [String]) throws -> URL {
        let appURL = try temporaryDirectory().appendingPathComponent("\(name).app")
        for executablePath in executablePaths {
            let executableURL = appURL.appendingPathComponent(executablePath)
            try FileManager.default.createDirectory(
                at: executableURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        }
        return appURL
    }
}
