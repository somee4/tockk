import XCTest

final class TockkCLITests: XCTestCase {
    func testSetupCreatesClaudeAndCodexConfigFiles() throws {
        let tempHome = try makeTempHome()
        let result = try runCLI(arguments: ["setup", "--claude", "--codex"], home: tempHome)

        XCTAssertEqual(result.status, 0, result.errorOutput)

        let claudeConfigURL = tempHome.appendingPathComponent(".claude/settings.json")
        let codexConfigURL = tempHome.appendingPathComponent(".codex/config.toml")
        let claudeConfig = try String(contentsOf: claudeConfigURL, encoding: .utf8)
        let codexConfig = try String(contentsOf: codexConfigURL, encoding: .utf8)

        XCTAssertTrue(claudeConfig.contains("claude-stop.sh"))
        XCTAssertTrue(codexConfig.contains("codex-notify.sh"))
    }

    func testSetupClaudeDoesNotRequireCodexHookScript() throws {
        let tempHome = try makeTempHome()
        let codexHookURL = scriptURL(named: "codex-notify.sh")
        let backupURL = codexHookURL.appendingPathExtension("bak-test")
        try FileManager.default.moveItem(at: codexHookURL, to: backupURL)
        defer {
            try? FileManager.default.moveItem(at: backupURL, to: codexHookURL)
        }

        let result = try runCLI(arguments: ["setup", "--claude"], home: tempHome)

        XCTAssertEqual(result.status, 0, result.errorOutput)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempHome.appendingPathComponent(".claude/settings.json").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempHome.appendingPathComponent(".codex/config.toml").path
            )
        )
    }

    func testSetupCodexDoesNotRequireClaudeHookScript() throws {
        let tempHome = try makeTempHome()
        let claudeHookURL = scriptURL(named: "claude-stop.sh")
        let backupURL = claudeHookURL.appendingPathExtension("bak-test")
        try FileManager.default.moveItem(at: claudeHookURL, to: backupURL)
        defer {
            try? FileManager.default.moveItem(at: backupURL, to: claudeHookURL)
        }

        let result = try runCLI(arguments: ["setup", "--codex"], home: tempHome)

        XCTAssertEqual(result.status, 0, result.errorOutput)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempHome.appendingPathComponent(".codex/config.toml").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempHome.appendingPathComponent(".claude/settings.json").path
            )
        )
    }

    func testSetupCodexReplacesMultilineNotifyWithoutBreakingTOML() throws {
        let tempHome = try makeTempHome()
        let codexDirectory = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
        let configURL = codexDirectory.appendingPathComponent("config.toml")
        try """
        approval_policy = "on-request"

        notify = [
          "terminal-notifier",
          "-title",
          "Codex ECC"
        ]

        [features]
        multi_agent = true
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let result = try runCLI(arguments: ["setup", "--codex"], home: tempHome)
        XCTAssertEqual(result.status, 0, result.errorOutput)

        let codexConfig = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(codexConfig.contains("codex-notify.sh"))
        XCTAssertTrue(codexConfig.contains("--previous-notify"))
        XCTAssertFalse(codexConfig.contains("\n  \"terminal-notifier\","))
        XCTAssertFalse(codexConfig.contains("\n  \"-title\","))
        XCTAssertTrue(codexConfig.contains("[features]"))
        XCTAssertTrue(codexConfig.contains("multi_agent = true"))
    }

    private func cliScriptURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("cli/tockk")
    }

    private func scriptURL(named name: String) -> URL {
        cliScriptURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/hooks")
            .appendingPathComponent(name)
    }

    private func makeTempHome() throws -> URL {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("TockkCLITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        return tempHome
    }

    private func runCLI(arguments: [String], home: URL) throws -> (status: Int32, errorOutput: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [cliScriptURL().path] + arguments
        process.environment = [
            "HOME": home.path,
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, errorOutput)
    }

}
