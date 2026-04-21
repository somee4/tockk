import XCTest
@testable import Tockk

final class HookSetupManagerTests: XCTestCase {
    func testConfigureClaudeAddsStopHookCommand() throws {
        let tempHome = makeTempHome(testName: #function)
        let hookPath = tempHome.appendingPathComponent("hooks/claude-stop.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: hookPath,
            codexHookURL: tempHome.appendingPathComponent("hooks/codex-notify.sh"),
            geminiHookURL: tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        )

        try manager.configureClaudeCode()

        let settingsURL = tempHome.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let stopHooks = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])

        XCTAssertEqual(stopHooks.count, 1)
        let entry = try XCTUnwrap(stopHooks.first)
        XCTAssertEqual(entry["matcher"] as? String, "*")
        let nested = try XCTUnwrap(entry["hooks"] as? [[String: Any]])
        XCTAssertEqual(nested.count, 1)
        XCTAssertEqual(nested.first?["type"] as? String, "command")
        XCTAssertEqual(nested.first?["command"] as? String, "/bin/bash \(hookPath.path)")
    }

    func testConfigureClaudeMigratesLegacyFlatStopHookEntry() throws {
        let tempHome = makeTempHome(testName: #function)
        let hookPath = tempHome.appendingPathComponent("hooks/claude-stop.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let settingsDirectory = tempHome.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
        let settingsURL = settingsDirectory.appendingPathComponent("settings.json")

        // Seed with the legacy broken shape that silently disables the Stop hook.
        let legacy: [String: Any] = [
            "hooks": [
                "Stop": [
                    ["command": "/bin/bash /stale/path/claude-stop.sh"]
                ]
            ]
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacy, options: [.prettyPrinted])
        try legacyData.write(to: settingsURL, options: .atomic)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: hookPath,
            codexHookURL: tempHome.appendingPathComponent("hooks/codex-notify.sh"),
            geminiHookURL: tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        )

        try manager.configureClaudeCode()

        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let stopHooks = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])

        XCTAssertEqual(stopHooks.count, 1, "Legacy flat entry should be purged, replaced with schema-valid entry")
        let entry = try XCTUnwrap(stopHooks.first)
        XCTAssertNotNil(entry["hooks"], "Migrated entry must use nested hooks array")
        XCTAssertNil(entry["command"], "Migrated entry must not carry a top-level command")
    }

    func testConfigureCodexAddsNotifyCommand() throws {
        let tempHome = makeTempHome(testName: #function)
        let hookPath = tempHome.appendingPathComponent("hooks/codex-notify.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: hookPath,
            geminiHookURL: tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        )

        try manager.configureCodexCLI()

        let configURL = tempHome.appendingPathComponent(".codex/config.toml")
        let config = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertTrue(config.contains("notify = [\"/bin/bash\", \"\(hookPath.path)\"]"))
    }

    func testConfigureCodexWrapsExistingNotifyCommand() throws {
        let tempHome = makeTempHome(testName: #function)
        let configDirectory = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        let configURL = configDirectory.appendingPathComponent("config.toml")
        try """
        [features]
        multi_agent = true

        notify = ["/tmp/old.sh"]
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let hookPath = tempHome.appendingPathComponent("hooks/codex-notify.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: hookPath,
            geminiHookURL: tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        )

        try manager.configureCodexCLI()

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(config.contains("[features]"))
        XCTAssertTrue(config.contains("multi_agent = true"))
        XCTAssertTrue(config.contains("notify = [\"/bin/bash\", \"\(hookPath.path)\""))
        XCTAssertTrue(config.contains("--previous-notify"))
        XCTAssertTrue(config.contains("/tmp/old.sh"))
    }

    func testConfigureCodexReplacesMultilineNotifyCommand() throws {
        let tempHome = makeTempHome(testName: #function)
        let configDirectory = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        let configURL = configDirectory.appendingPathComponent("config.toml")
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

        let hookPath = tempHome.appendingPathComponent("hooks/codex-notify.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: hookPath,
            geminiHookURL: tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        )

        try manager.configureCodexCLI()

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(config.contains("notify = [\"/bin/bash\", \"\(hookPath.path)\""))
        XCTAssertTrue(config.contains("--previous-notify"))
        XCTAssertTrue(config.contains("[features]"))
        XCTAssertTrue(config.contains("multi_agent = true"))
    }

    func testConfigureCodexPreservesLegacyNotificationsSection() throws {
        let tempHome = makeTempHome(testName: #function)
        let configDirectory = tempHome.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        let configURL = configDirectory.appendingPathComponent("config.toml")
        try """
        [features]
        multi_agent = true

        [notifications]
        command = ["/tmp/old.sh"]
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let hookPath = tempHome.appendingPathComponent("hooks/codex-notify.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: hookPath,
            geminiHookURL: tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        )

        try manager.configureCodexCLI()

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(config.contains("[notifications]"))
        XCTAssertTrue(config.contains(#"command = ["/tmp/old.sh"]"#))
        XCTAssertTrue(config.contains("notify = [\"/bin/bash\", \"\(hookPath.path)\""))
    }

    func testConfigureGeminiAddsAfterAgentHookCommand() throws {
        let tempHome = makeTempHome(testName: #function)
        let hookPath = tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: tempHome.appendingPathComponent("hooks/codex-notify.sh"),
            geminiHookURL: hookPath
        )

        try manager.configureGeminiCLI()

        let settingsURL = tempHome.appendingPathComponent(".gemini/settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let afterAgent = try XCTUnwrap(hooks["AfterAgent"] as? [[String: Any]])

        XCTAssertEqual(afterAgent.count, 1)
        let entry = try XCTUnwrap(afterAgent.first)
        XCTAssertEqual(entry["matcher"] as? String, "*")
        let nested = try XCTUnwrap(entry["hooks"] as? [[String: Any]])
        XCTAssertEqual(nested.count, 1)
        XCTAssertEqual(nested.first?["type"] as? String, "command")
        XCTAssertEqual(nested.first?["command"] as? String, "/bin/bash \(hookPath.path)")
    }

    func testConfigureGeminiIsIdempotent() throws {
        let tempHome = makeTempHome(testName: #function)
        let hookPath = tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: tempHome.appendingPathComponent("hooks/codex-notify.sh"),
            geminiHookURL: hookPath
        )

        try manager.configureGeminiCLI()
        try manager.configureGeminiCLI()

        let settingsURL = tempHome.appendingPathComponent(".gemini/settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try XCTUnwrap(json["hooks"] as? [String: Any])
        let afterAgent = try XCTUnwrap(hooks["AfterAgent"] as? [[String: Any]])

        XCTAssertEqual(afterAgent.count, 1, "Re-running configure must not duplicate the hook entry")
    }

    func testIsGeminiConfiguredReflectsOnDiskState() throws {
        let tempHome = makeTempHome(testName: #function)
        let hookPath = tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: tempHome.appendingPathComponent("hooks/codex-notify.sh"),
            geminiHookURL: hookPath
        )

        XCTAssertFalse(manager.isGeminiConfigured(), "Reports false before configure runs")

        try manager.configureGeminiCLI()

        XCTAssertTrue(manager.isGeminiConfigured(), "Reports true after configure runs")
    }

    func testConfigureGeminiAcceptsJSONCInputWithCommentsAndTrailingCommas() throws {
        let tempHome = makeTempHome(testName: #function)
        let hookPath = tempHome.appendingPathComponent("hooks/gemini-stop.sh")
        try FileManager.default.createDirectory(
            at: hookPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\n".write(to: hookPath, atomically: true, encoding: .utf8)

        // Real-world Gemini CLI settings.json shape: line comments documenting
        // commented-out backup config, trailing commas in arrays, and an
        // unrelated top-level key that must be preserved.
        let settingsDirectory = tempHome.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
        let settingsURL = settingsDirectory.appendingPathComponent("settings.json")
        try """
        {
          "mcpServers": {
            //    "context7-https": {
            //      "httpUrl": "https://mcp.context7.com/mcp"
            //    },
            "context7": {
              "command": "npx",
              "args": [
                "-y",
                "@upstash/context7-mcp",
              ]
            }
          },
          /* block comment */
          "ide": { "enabled": true }
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let manager = HookSetupManager(
            homeDirectoryURL: tempHome,
            claudeHookURL: tempHome.appendingPathComponent("hooks/claude-stop.sh"),
            codexHookURL: tempHome.appendingPathComponent("hooks/codex-notify.sh"),
            geminiHookURL: hookPath
        )

        try manager.configureGeminiCLI()

        // Configure must succeed (no NSCocoaErrorDomain 3840) and the resulting
        // file is now strict JSON with the AfterAgent hook plus the user's
        // unrelated top-level keys preserved.
        let written = try Data(contentsOf: settingsURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertNotNil(json["hooks"], "AfterAgent hook should be written")
        XCTAssertNotNil(json["mcpServers"], "Existing mcpServers key must be preserved")
        XCTAssertNotNil(json["ide"], "Existing ide key must be preserved")

        // A backup of the original JSONC source must sit alongside the file
        // so the user can recover anything that comment-stripping wiped.
        let backupURL = settingsURL.deletingPathExtension()
            .appendingPathExtension("json.tockk.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path),
                      "Original JSONC content must be backed up to .tockk.bak")
        let backupContent = try String(contentsOf: backupURL, encoding: .utf8)
        XCTAssertTrue(backupContent.contains("//    \"context7-https\""),
                      "Backup must preserve original comments verbatim")
    }

    func testStripJSONCArtifactsRemovesCommentsTrailingCommasButKeepsStringContents() {
        let input = """
        {
          // line comment
          "url": "http://example.com/path", /* inline block */
          "list": [1, 2, 3,],
          /* multi
             line */
          "quote": "with // and /* inside */ string"
        }
        """
        let stripped = HookSetupManager.stripJSONCArtifacts(input)

        // Strict JSON must parse the result.
        let data = try! XCTUnwrap(stripped.data(using: .utf8))
        let json = try! XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["url"] as? String, "http://example.com/path",
                       "URLs containing // must not be treated as comments")
        XCTAssertEqual(json["list"] as? [Int], [1, 2, 3],
                       "Trailing commas in arrays must be stripped")
        XCTAssertEqual(json["quote"] as? String, "with // and /* inside */ string",
                       "Comment markers inside string literals must be preserved")
    }
}

private func makeTempHome(testName: String) -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HookSetupManagerTests-\(testName)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
