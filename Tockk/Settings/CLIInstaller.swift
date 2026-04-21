import Foundation

enum CLIInstallStatus: Equatable {
    /// Symlink exists and points at the bundled executable.
    case installed(linkPath: URL)
    /// Symlink exists but targets a different file (manual install, repo
    /// symlink, stale entry from an old app location).
    case installedElsewhere(linkPath: URL, actualTarget: URL)
    /// No symlink at the expected path.
    case notInstalled(linkPath: URL)
    /// Bundled executable is missing — the app wasn't built with CLI support.
    case unavailable
}

enum CLIInstallError: Error, LocalizedError {
    case missingBundledScript
    case symlinkCreationFailed(underlying: Error)
    case symlinkRemovalFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingBundledScript:
            return "Bundled 'tockk' command-line script not found inside the app. Rebuild the app."
        case .symlinkCreationFailed(let underlying):
            return "Could not create the 'tockk' symlink: \(underlying.localizedDescription)"
        case .symlinkRemovalFailed(let underlying):
            return "Could not remove the existing 'tockk' symlink: \(underlying.localizedDescription)"
        }
    }
}

/// Creates and removes a user-local symlink so `tockk` can be invoked from
/// any shell. We target `~/.local/bin/tockk` instead of `/usr/local/bin`
/// because the former lives inside the user's home directory — no sudo, no
/// PATH pollution for other users, and it's already the default install
/// location honoured by modern user-scoped package managers (pipx, cargo,
/// rustup). The trade-off is that `~/.local/bin` isn't in PATH by default
/// on macOS, so `diagnosePATH()` tells callers whether the shell will
/// actually find the binary and which startup file needs editing.
struct CLIInstaller {
    /// The bundled script that the symlink will point at. `nil` when the
    /// app was built without CLI support.
    let bundledExecutableURL: URL?
    /// Where the symlink itself lives. Defaults to `~/.local/bin/tockk`.
    let symlinkURL: URL

    init(
        bundledExecutableURL: URL? = Bundle.main.url(forResource: "tockk", withExtension: nil),
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) {
        self.bundledExecutableURL = bundledExecutableURL
        self.symlinkURL = homeDirectoryURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("tockk")
    }

    /// Inspect the filesystem without mutating it. Cheap — safe to call on
    /// every Settings render and on first launch.
    func status() -> CLIInstallStatus {
        guard let bundledExecutableURL else { return .unavailable }

        let fm = FileManager.default
        let linkPath = symlinkURL.path
        // `fileExists` follows symlinks and returns false for broken ones,
        // so we use the attribute API directly to tell "doesn't exist"
        // apart from "exists but dangling".
        let attrs = try? fm.attributesOfItem(atPath: linkPath)
        if attrs == nil && !fm.fileExists(atPath: linkPath) {
            return .notInstalled(linkPath: symlinkURL)
        }

        if let destination = try? fm.destinationOfSymbolicLink(atPath: linkPath) {
            let resolved = URL(fileURLWithPath: destination, relativeTo: symlinkURL.deletingLastPathComponent())
                .standardizedFileURL
            if resolved.path == bundledExecutableURL.standardizedFileURL.path {
                return .installed(linkPath: symlinkURL)
            }
            return .installedElsewhere(linkPath: symlinkURL, actualTarget: resolved)
        }
        // It's a regular file, not a symlink. Treat as "installed elsewhere"
        // so the UI offers to replace it rather than silently clobbering.
        return .installedElsewhere(linkPath: symlinkURL, actualTarget: symlinkURL)
    }

    /// Create (or replace) the symlink. Best-effort: callers can ignore the
    /// thrown error on first-launch autopilot runs.
    @discardableResult
    func install() throws -> CLIInstallStatus {
        guard let bundledExecutableURL else {
            throw CLIInstallError.missingBundledScript
        }

        let fm = FileManager.default
        try fm.createDirectory(
            at: symlinkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Remove any stale entry first. `removeItem(at:)` handles both
        // broken symlinks and regular files; it returns "No such file"
        // which we swallow silently.
        if fileExistsOrIsDanglingLink(atPath: symlinkURL.path) {
            do {
                try fm.removeItem(at: symlinkURL)
            } catch {
                throw CLIInstallError.symlinkRemovalFailed(underlying: error)
            }
        }

        do {
            try fm.createSymbolicLink(at: symlinkURL, withDestinationURL: bundledExecutableURL)
        } catch {
            throw CLIInstallError.symlinkCreationFailed(underlying: error)
        }

        return .installed(linkPath: symlinkURL)
    }

    /// Remove the symlink if (and only if) it currently points at our
    /// bundled script. We don't clobber foreign `tockk` binaries the user
    /// may have installed via another channel (Homebrew, manual copy).
    func uninstall() throws {
        let fm = FileManager.default
        switch status() {
        case .installed:
            do {
                try fm.removeItem(at: symlinkURL)
            } catch {
                throw CLIInstallError.symlinkRemovalFailed(underlying: error)
            }
        case .notInstalled, .installedElsewhere, .unavailable:
            return  // Nothing we own to remove.
        }
    }

    /// Install the symlink on first launch if nothing is present yet. This
    /// is the silent "just works" path — the button in Settings is the
    /// escape hatch for users whose `~/.local/bin/tockk` is owned by
    /// someone else (Homebrew, a different Tockk.app location).
    func autoInstallIfNeeded() {
        guard bundledExecutableURL != nil else { return }
        switch status() {
        case .notInstalled:
            _ = try? install()
        case .installed, .installedElsewhere, .unavailable:
            return
        }
    }

    private func fileExistsOrIsDanglingLink(atPath path: String) -> Bool {
        var stat = stat()
        // `lstat` inspects the link itself rather than following it, so
        // this is true even when the symlink is broken.
        return lstat(path, &stat) == 0
    }

    /// Tell the caller whether the shell that spawned them will actually
    /// find `tockk`. Returns `nil` when `~/.local/bin` is already in PATH.
    /// Otherwise returns a short hint suited for Settings UI. This only
    /// inspects `ProcessInfo.processInfo.environment["PATH"]`, which is
    /// the PATH the *app* inherited from launchd — close enough for a
    /// rough diagnostic, but not authoritative for every shell the user
    /// might open.
    func diagnosePATH() -> String? {
        let binDir = symlinkURL.deletingLastPathComponent().path
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let components = pathEnv.split(separator: ":").map(String.init)
        if components.contains(binDir) { return nil }

        let shell = (ProcessInfo.processInfo.environment["SHELL"] as NSString?)?
            .lastPathComponent ?? "zsh"
        let rcHint: String = {
            switch shell {
            case "bash": return "~/.bashrc (or ~/.bash_profile)"
            case "fish": return "~/.config/fish/config.fish"
            case "zsh":  fallthrough
            default:     return "~/.zshrc"
            }
        }()

        return "Add to \(rcHint): export PATH=\"$HOME/.local/bin:$PATH\""
    }
}
