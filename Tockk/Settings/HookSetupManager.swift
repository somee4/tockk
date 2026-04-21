import Foundation

struct HookSetupManager {
    enum HookSetupError: LocalizedError {
        case missingClaudeHook
        case missingCodexHook
        case missingGeminiHook

        var errorDescription: String? {
            switch self {
            case .missingClaudeHook:
                return String(localized: "Claude Code hook script not found.")
            case .missingCodexHook:
                return String(localized: "Codex CLI hook script not found.")
            case .missingGeminiHook:
                return String(localized: "Gemini CLI hook script not found.")
            }
        }
    }

    let homeDirectoryURL: URL
    let claudeHookURL: URL?
    let codexHookURL: URL?
    let geminiHookURL: URL?

    init(
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        claudeHookURL: URL? = Bundle.main.url(forResource: "claude-stop", withExtension: "sh"),
        codexHookURL: URL? = Bundle.main.url(forResource: "codex-notify", withExtension: "sh"),
        geminiHookURL: URL? = Bundle.main.url(forResource: "gemini-stop", withExtension: "sh")
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        self.claudeHookURL = claudeHookURL
        self.codexHookURL = codexHookURL
        self.geminiHookURL = geminiHookURL
    }

    func configureAll() throws {
        try configureClaudeCode()
        try configureCodexCLI()
        try configureGeminiCLI()
    }

    // MARK: - Introspection
    //
    // `configure*` methods *write* the hook into the agent's config. The
    // `is*Configured` accessors *read* it back, so the Settings UI can
    // show an honest "연결됨 / 미설치" pill instead of a hard-coded default.
    // Failures here (missing file, unreadable JSON) degrade to `false`
    // rather than throwing — a Settings pane should not crash because a
    // user's config file is malformed.

    /// Whether `~/.claude/settings.json` currently contains a Stop hook that
    /// invokes our bundled `claude-stop.sh` script. Returns `false` if the
    /// bundle's hook script is missing (edge case — unit tests inject a
    /// `nil` URL), the settings file doesn't exist, or the hook array does
    /// not reference our script.
    func isClaudeConfigured() -> Bool {
        guard let claudeHookURL else { return false }
        let settingsURL = homeDirectoryURL
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        guard let root = try? loadJSONSettings(from: settingsURL),
              let hooks = root["hooks"] as? [String: Any],
              let stopHooks = hooks["Stop"] as? [[String: Any]] else {
            return false
        }
        let expected = "/bin/bash \(claudeHookURL.path)"
        return stopHooks.contains { entry in
            guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
            return nested.contains { ($0["command"] as? String) == expected }
        }
    }

    /// Whether `~/.codex/config.toml` currently contains a top-level
    /// `notify = [...]` entry that invokes our bundled `codex-notify.sh`.
    /// This matches the current Codex config schema. Legacy
    /// `[notifications]` blocks are ignored because modern Codex releases do
    /// not read them.
    func isCodexConfigured() -> Bool {
        guard let codexHookURL else { return false }
        let configURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return false
        }
        guard let assignment = findNotifyAssignment(in: contents) else {
            return false
        }
        return assignment.value.contains(codexHookURL.path)
    }

    /// Whether `~/.gemini/settings.json` currently contains an AfterAgent hook
    /// entry pointing at our bundled `gemini-stop.sh`. Mirrors
    /// `isClaudeConfigured()` — Gemini's config schema is structurally
    /// identical to Claude's, so the lookup walks the same nested shape.
    func isGeminiConfigured() -> Bool {
        guard let geminiHookURL else { return false }
        let settingsURL = homeDirectoryURL
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("settings.json")
        guard let root = try? loadJSONSettings(from: settingsURL),
              let hooks = root["hooks"] as? [String: Any],
              let afterAgentHooks = hooks["AfterAgent"] as? [[String: Any]] else {
            return false
        }
        let expected = "/bin/bash \(geminiHookURL.path)"
        return afterAgentHooks.contains { entry in
            guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
            return nested.contains { ($0["command"] as? String) == expected }
        }
    }

    func configureClaudeCode() throws {
        guard let claudeHookURL else {
            throw HookSetupError.missingClaudeHook
        }

        let settingsURL = homeDirectoryURL
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")

        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var rootObject = try loadJSONSettings(from: settingsURL)
        var hooks = rootObject["hooks"] as? [String: Any] ?? [:]
        var stopHooks = hooks["Stop"] as? [[String: Any]] ?? []
        let command = "/bin/bash \(claudeHookURL.path)"

        // Purge legacy entries that used the flat {"command": ...} shape — it is
        // invalid per Claude Code's hook schema and prevents the Stop hook from firing.
        stopHooks.removeAll { entry in
            entry["hooks"] == nil
                && (entry["command"] as? String)?.contains("claude-stop.sh") == true
        }

        let alreadyPresent = stopHooks.contains { entry in
            guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
            return nested.contains { ($0["command"] as? String) == command }
        }

        if !alreadyPresent {
            let hookEntry: [String: Any] = [
                "matcher": "*",
                "hooks": [
                    ["type": "command", "command": command]
                ]
            ]
            stopHooks.append(hookEntry)
        }

        hooks["Stop"] = stopHooks
        rootObject["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    func configureCodexCLI() throws {
        guard let codexHookURL else {
            throw HookSetupError.missingCodexHook
        }

        let configURL = homeDirectoryURL
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("config.toml")

        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let commandLine = codexNotifyCommandLine(existing: existing, hookPath: codexHookURL.path)
        let updated = updateCodexConfig(existing, commandLine: commandLine)

        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func configureGeminiCLI() throws {
        guard let geminiHookURL else {
            throw HookSetupError.missingGeminiHook
        }

        let settingsURL = homeDirectoryURL
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("settings.json")

        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var rootObject = try loadJSONSettings(from: settingsURL)
        var hooks = rootObject["hooks"] as? [String: Any] ?? [:]
        var afterAgentHooks = hooks["AfterAgent"] as? [[String: Any]] ?? []
        let command = "/bin/bash \(geminiHookURL.path)"

        let alreadyPresent = afterAgentHooks.contains { entry in
            guard let nested = entry["hooks"] as? [[String: Any]] else { return false }
            return nested.contains { ($0["command"] as? String) == command }
        }

        if alreadyPresent {
            return  // No-op: don't rewrite the file (preserves any user JSONC comments).
        }

        let hookEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [
                ["type": "command", "command": command]
            ]
        ]
        afterAgentHooks.append(hookEntry)
        hooks["AfterAgent"] = afterAgentHooks
        rootObject["hooks"] = hooks

        // Gemini's settings.json is JSONC — users often keep documentation
        // comments and commented-out config (e.g. backup MCP servers, OAuth
        // keys). Re-serializing strips those. Snapshot the original to a
        // sibling `.tockk.bak` so the user can recover anything they care
        // about. Best-effort: a missing/unreadable source is not a hard
        // failure (the next step will create the file from scratch anyway).
        let backupURL = settingsURL.deletingPathExtension()
            .appendingPathExtension("json.tockk.bak")
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        }

        let data = try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Reads a JSON-with-comments settings file. Tolerates `// line` and
    /// `/* block */` comments and trailing commas because Claude Code and
    /// Gemini CLI both write JSONC by default — `JSONSerialization` itself
    /// rejects either, which would otherwise crash the installer with a
    /// useless `NSCocoaErrorDomain 3840`.
    private func loadJSONSettings(from url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            return [:]
        }

        let raw = String(data: data, encoding: .utf8) ?? ""
        let stripped = HookSetupManager.stripJSONCArtifacts(raw)
        let strippedData = stripped.data(using: .utf8) ?? data

        let json = try JSONSerialization.jsonObject(with: strippedData)
        return json as? [String: Any] ?? [:]
    }

    /// Strips JSONC-only constructs (`// line` comments, `/* block */`
    /// comments, and trailing commas before `}`/`]`) so the result parses
    /// under strict JSON. Aware of string literals and escape sequences so
    /// `"http://..."` inside a value is left untouched.
    static func stripJSONCArtifacts(_ raw: String) -> String {
        var output = String()
        output.reserveCapacity(raw.count)

        var inString = false
        var escaping = false
        var i = raw.startIndex
        let end = raw.endIndex

        while i < end {
            let c = raw[i]

            if inString {
                output.append(c)
                if escaping {
                    escaping = false
                } else if c == "\\" {
                    escaping = true
                } else if c == "\"" {
                    inString = false
                }
                i = raw.index(after: i)
                continue
            }

            // Detect comment starts only outside string literals.
            if c == "/" {
                let next = raw.index(after: i)
                if next < end {
                    let n = raw[next]
                    if n == "/" {
                        // Line comment — skip to next newline (preserve the \n
                        // so line numbers in error messages still line up).
                        i = next
                        while i < end, raw[i] != "\n" {
                            i = raw.index(after: i)
                        }
                        continue
                    }
                    if n == "*" {
                        // Block comment — skip to matching */
                        i = raw.index(after: next)
                        while i < end {
                            if raw[i] == "*" {
                                let n2 = raw.index(after: i)
                                if n2 < end, raw[n2] == "/" {
                                    i = raw.index(after: n2)
                                    break
                                }
                            }
                            i = raw.index(after: i)
                        }
                        continue
                    }
                }
            }

            if c == "\"" {
                inString = true
            }
            output.append(c)
            i = raw.index(after: i)
        }

        // Strip trailing commas: `,` followed by optional whitespace and a
        // closing `}` or `]`. JSONSerialization rejects them; JSONC allows.
        let trailingCommaRegex = try? NSRegularExpression(pattern: #",(\s*[}\]])"#)
        guard let regex = trailingCommaRegex else { return output }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        return regex.stringByReplacingMatches(in: output, range: range, withTemplate: "$1")
    }

    private func codexNotifyCommandLine(existing: String, hookPath: String) -> String {
        let hookPathLiteral = tomlBasicStringLiteral(hookPath)
        let defaultCommand = #"notify = ["/bin/bash", \#(hookPathLiteral)]"#
        guard let assignment = findNotifyAssignment(in: existing) else {
            return defaultCommand
        }

        let existingCommand = assignment.value
        guard !existingCommand.contains(hookPath) else {
            return defaultCommand
        }

        let escapedPrevious = tomlBasicStringLiteral(existingCommand)
        return #"notify = ["/bin/bash", \#(hookPathLiteral), "--previous-notify", \#(escapedPrevious)]"#
    }

    private func updateCodexConfig(_ existing: String, commandLine: String) -> String {
        var updated = existing

        if let assignment = findNotifyAssignment(in: updated) {
            // `String.lineRange(for:)` INCLUDES the trailing newline, so
            // replacing with `commandLine` alone fuses the new line with the
            // following content and corrupts the TOML (e.g.
            // `notify = [...]<<no newline>>[mcp_servers.github]`). Append
            // the `\n` back when the replaced range ended at one — and
            // preserve the EOF case where it didn't.
            let originalEndedWithNewline = assignment.lineRange.upperBound > updated.startIndex
                && updated[updated.index(before: assignment.lineRange.upperBound)] == "\n"
            let replacement = originalEndedWithNewline ? commandLine + "\n" : commandLine
            updated.replaceSubrange(assignment.lineRange, with: replacement)
        } else {
            // No existing `notify`: insert at the TOP LEVEL, BEFORE the first
            // `[table]` header. Appending at EOF silently re-binds the key
            // into whichever table happens to be last (e.g.
            // `mcp_servers.github.notify`), and Codex never invokes the hook.
            let lines = updated.split(separator: "\n", omittingEmptySubsequences: false)
            var insertIdx: Int? = nil
            for (i, line) in lines.enumerated() {
                let stripped = line.trimmingCharacters(in: .whitespaces)
                if stripped.hasPrefix("[") && stripped.hasSuffix("]") {
                    insertIdx = i
                    break
                }
            }

            if let idx = insertIdx {
                let head = lines[..<idx].joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rest = lines[idx...].joined(separator: "\n")
                let prefix = head.isEmpty ? "" : head + "\n\n"
                updated = "\(prefix)\(commandLine)\n\n\(rest)"
            } else {
                let trimmed = updated.trimmingCharacters(in: .whitespacesAndNewlines)
                updated = trimmed.isEmpty ? "\(commandLine)\n" : "\(trimmed)\n\n\(commandLine)\n"
            }
        }

        return updated.hasSuffix("\n") ? updated : updated + "\n"
    }

    private func findNotifyAssignment(in content: String) -> NotifyAssignment? {
        guard let notifyLine = content.firstMatch(for: #"(?m)^[ \t]*notify[ \t]*=[ \t]*"#),
              let valuePrefix = Range(notifyLine.range, in: content) else {
            return nil
        }

        let lineRange = content.lineRange(for: valuePrefix)
        var valueStart = valuePrefix.upperBound
        while valueStart < content.endIndex, content[valueStart] == " " || content[valueStart] == "\t" {
            valueStart = content.index(after: valueStart)
        }

        let valueRange: Range<String.Index>
        if valueStart < content.endIndex, content[valueStart] == "[" {
            valueRange = parseBracketValue(in: content, startingAt: valueStart)
                ?? (valueStart..<lineRange.upperBound)
        } else {
            valueRange = valueStart..<lineRange.upperBound
        }

        let finalLineRange = content.lineRange(for: valueRange)
        let value = String(content[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return NotifyAssignment(lineRange: finalLineRange, value: value)
    }

    private func parseBracketValue(in content: String, startingAt start: String.Index) -> Range<String.Index>? {
        var depth = 1
        var cursor = content.index(after: start)
        var inString = false
        var escaping = false

        while cursor < content.endIndex {
            let character = content[cursor]

            if inString {
                if escaping {
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        let end = content.index(after: cursor)
                        return start..<end
                    }
                }
            }

            cursor = content.index(after: cursor)
        }

        return nil
    }

    private func tomlBasicStringLiteral(_ raw: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(raw.count + 8)

        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\n":
                escaped += "\\n"
            case "\r":
                escaped += "\\r"
            case "\t":
                escaped += "\\t"
            default:
                escaped.append(String(scalar))
            }
        }

        return "\"\(escaped)\""
    }

    private struct NotifyAssignment {
        let lineRange: Range<String.Index>
        let value: String
    }

}

private extension String {
    func firstMatch(for pattern: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.firstMatch(in: self, options: [], range: range)
    }
}
