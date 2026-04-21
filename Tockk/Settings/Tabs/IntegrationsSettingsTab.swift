import SwiftUI

/// "연동" tab. Lists the agent hosts Tockk can hook into (Claude Code,
/// Codex CLI) with a status pill on each row reflecting real on-disk state,
/// plus a CLI one-liner and a "모두 설정" action for users who prefer to
/// configure both agents in one shot.
struct IntegrationsSettingsTab: View {
    /// Called after a `configure*` action completes so the parent (and the
    /// top status bar) can re-query the hook install state. Injected so
    /// this tab doesn't need to reach back into the Settings root itself.
    let onHookStateChanged: () -> Void

    @State private var claudeInstalled: Bool = false
    @State private var codexInstalled: Bool = false
    @State private var geminiInstalled: Bool = false
    @State private var statusMessage: String?
    @State private var statusIsError: Bool = false
    @State private var cliStatus: CLIInstallStatus = .notInstalled(
        linkPath: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/bin/tockk")
    )
    @State private var cliPathHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("Integrations", hint: "Tools with an agent-done hook installed.")

            SectionLabel("Agent hooks")
            GroupCard {
                agentRow(
                    iconName: "ClaudeMark",
                    name: "Claude Code",
                    hint: "~/.claude/settings.json",
                    isInstalled: claudeInstalled,
                    action: { configure(.claude) }
                )
                agentRow(
                    iconName: "CodexMark",
                    name: "Codex CLI",
                    hint: "~/.codex/config.toml",
                    isInstalled: codexInstalled,
                    action: { configure(.codex) }
                )
                agentRow(
                    iconName: "GeminiMark",
                    name: "Gemini CLI",
                    hint: "~/.gemini/settings.json",
                    isInstalled: geminiInstalled,
                    action: { configure(.gemini) }
                )
            }
            .padding(.bottom, 10)

            HStack {
                Spacer()
                Button {
                    configure(.both)
                } label: {
                    Text("Set up all")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.bottom, 14)

            SectionLabel("Command line")
            terminalRow
            Text("Run the command above to install everything at once. It wires the agent-done hook into every auto-detected tool.")
                .font(.system(size: 11.5))
                .foregroundStyle(SettingsDesign.rowHintColor)
                .padding(.top, 8)

            cliRow
                .padding(.top, 18)

            if let statusMessage {
                Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(statusIsError ? Color.red : Color(red: 34/255, green: 197/255, blue: 94/255))
                    .textSelection(.enabled)
                    .padding(.top, 12)
            }
        }
        .onAppear {
            refreshInstalledState()
            refreshCLIStatus()
        }
    }

    // MARK: - CLI row

    @ViewBuilder
    private var cliRow: some View {
        let isInstalled: Bool = {
            if case .installed = cliStatus { return true }
            return false
        }()
        let linkPath: String = {
            switch cliStatus {
            case .installed(let p), .notInstalled(let p), .installedElsewhere(let p, _):
                return "~" + p.path.replacingOccurrences(of: NSHomeDirectory(), with: "")
            case .unavailable:
                return "—"
            }
        }()
        let statusLabel: String = {
            switch cliStatus {
            case .installed:          return String(localized: "Installed")
            case .installedElsewhere: return String(localized: "Conflict")
            case .notInstalled:       return String(localized: "Not installed")
            case .unavailable:        return String(localized: "Unavailable")
            }
        }()
        let statusOK: Bool = {
            if case .installed = cliStatus { return true }
            return false
        }()

        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Shell command")

            GroupCard {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "terminal")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("tockk")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Text(linkPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SettingsDesign.rowHintColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        SettingsStatusPill(label: statusLabel, isOk: statusOK)

                        if case .unavailable = cliStatus {
                            EmptyView()
                        } else {
                            Button(action: installOrReinstallCLI) {
                                Text(isInstalled ? "Reinstall" : "Install")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(isInstalled ? Color.primary : Color.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5)
                                            .fill(isInstalled ? Color.black.opacity(0.06) : SettingsDesign.accentBlue)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder(isInstalled ? Color.black.opacity(0.1) : .clear, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)

                            if isInstalled {
                                Button(action: removeCLI) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.secondary)
                                        .padding(5)
                                }
                                .buttonStyle(.plain)
                                .help("Remove symlink")
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: SettingsDesign.rowMinHeight)
            }

            if let hint = cliPathHint {
                Text(hint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.orange)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Agent row

    private func agentRow(
        iconName: String,
        name: String,
        hint: String,
        isInstalled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(iconName)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(hint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SettingsDesign.rowHintColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                SettingsStatusPill(
                    label: isInstalled ? String(localized: "Connected") : String(localized: "Not installed"),
                    isOk: isInstalled
                )
                Button(action: action) {
                    Text(isInstalled ? "Reapply" : "Install")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isInstalled ? Color.primary : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isInstalled ? Color.black.opacity(0.06) : SettingsDesign.accentBlue)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(isInstalled ? Color.black.opacity(0.1) : .clear, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: SettingsDesign.rowMinHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsDesign.rowDivider)
                .frame(height: 0.5)
        }
    }

    // MARK: - Terminal row

    private var terminalRow: some View {
        HStack(spacing: 8) {
            Text("$")
                .foregroundStyle(Color.white.opacity(0.55))
            HStack(spacing: 4) {
                Text("tockk").foregroundStyle(Color(red: 165/255, green: 214/255, blue: 255/255))
                Text("setup").foregroundStyle(Color.white.opacity(0.9))
                Text("--all").foregroundStyle(Color(red: 241/255, green: 200/255, blue: 75/255))
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("tockk setup", forType: .string)
                statusMessage = String(localized: "Copied to clipboard.")
                statusIsError = false
            } label: {
                Text("COPY")
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Paste into terminal")
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(red: 0x1E/255, green: 0x1E/255, blue: 0x22/255))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Actions

    private enum HookSetupTarget { case claude, codex, gemini, both }

    private func refreshInstalledState() {
        let manager = HookSetupManager()
        claudeInstalled = manager.isClaudeConfigured()
        codexInstalled = manager.isCodexConfigured()
        geminiInstalled = manager.isGeminiConfigured()
    }

    private func refreshCLIStatus() {
        let installer = CLIInstaller()
        cliStatus = installer.status()
        // Only surface the PATH hint when the symlink is actually in place
        // — warning about PATH for a binary the user hasn't installed yet
        // is noise.
        if case .installed = cliStatus {
            cliPathHint = installer.diagnosePATH()
        } else {
            cliPathHint = nil
        }
    }

    private func installOrReinstallCLI() {
        let installer = CLIInstaller()
        do {
            try installer.install()
            statusMessage = String(localized: "Installed the 'tockk' command at ~/.local/bin/tockk.")
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        refreshCLIStatus()
    }

    private func removeCLI() {
        let installer = CLIInstaller()
        do {
            try installer.uninstall()
            statusMessage = String(localized: "Removed the 'tockk' symlink.")
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        refreshCLIStatus()
    }

    private func configure(_ target: HookSetupTarget) {
        let manager = HookSetupManager()
        do {
            switch target {
            case .claude:
                try manager.configureClaudeCode()
                statusMessage = String(localized: "Added the Claude Code hook.")
            case .codex:
                try manager.configureCodexCLI()
                statusMessage = String(localized: "Added the Codex CLI notify command.")
            case .gemini:
                try manager.configureGeminiCLI()
                statusMessage = String(localized: "Added the Gemini CLI hook.")
            case .both:
                try manager.configureAll()
                statusMessage = String(localized: "Completed setup for all agent hooks.")
            }
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
        refreshInstalledState()
        onHookStateChanged()
    }
}
