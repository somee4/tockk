import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Convenience reach-through so `SettingsView` can request a test
    /// notification without a dedicated DI container. We hold the instance
    /// ourselves rather than going through `NSApp.delegate` because
    /// `@NSApplicationDelegateAdaptor` can leave `NSApp.delegate` as a
    /// SwiftUI-owned wrapper whose cast back to `AppDelegate` fails — the
    /// Sandbox Trigger then silently no-ops because `shared` is `nil`.
    static private(set) weak var shared: AppDelegate?

    override init() {
        super.init()
        // Grabbed immediately so callers reaching `.shared` during the first
        // view render (e.g. Settings window opened before launch finishes)
        // still see a non-nil instance.
        Self.shared = self
    }

    private let queue = EventQueue(
        minDisplaySeconds: AppSettings.shared.minDisplaySeconds,
        displayDuration: AppDelegate.effectiveDisplayDuration(from: AppSettings.shared)
    )
    private let presenter = NotchPresenter()
    private let settingsWindowController = SettingsWindowController()
    private var server: SocketServer?
    private var statusItem: NSStatusItem?
    private var recent: [Event] = []
    private var settingsObserver: AnyCancellable?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.setupMenubar()
            self.setupThemeObservation()
            self.setupQueueCallbacks()
            self.startServer()
            // Silently install the `tockk` CLI symlink if nothing is
            // present yet. Mirrors VS Code's `code` command: new installs
            // get the shell command for free without a separate step.
            // Existing symlinks (including ones pointing elsewhere) are
            // left untouched — Settings exposes the explicit install/
            // reinstall/remove buttons for those cases.
            CLIInstaller().autoInstallIfNeeded()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            server?.stop()
        }
    }

    // MARK: - Private

    private var activeTheme: AppTheme {
        AppSettings.shared.activeTheme
    }

    private func setupMenubar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshMenubarAppearance()
    }

    private func setupThemeObservation() {
        settingsObserver = AppSettings.shared.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                self?.refreshMenubarAppearance()
                self?.applyResidencePolicy()
            }
        }
    }

    /// Pushes the current residence policy into `EventQueue`. Called on launch
    /// and whenever `AppSettings` changes, so Settings toggles take effect
    /// without an app restart.
    private func applyResidencePolicy() {
        queue.setDisplayDuration(Self.effectiveDisplayDuration(from: AppSettings.shared))
    }

    /// Maps the residence mode + seconds in AppSettings to the optional
    /// duration EventQueue understands: `nil` for persistent/collapse modes
    /// (no full auto-dismiss), a positive interval for `.dismissAfter`.
    private static func effectiveDisplayDuration(from settings: AppSettings) -> TimeInterval? {
        switch settings.alertResidenceMode {
        case .persistent, .collapseAfter:
            return nil
        case .dismissAfter:
            return settings.displayDurationSeconds
        }
    }

    /// Builds a fresh `ScreenSelector` honoring the user's current strategy.
    /// Allocating per-event is negligible in cost and lets strategy changes
    /// in Settings take effect on the very next notification.
    private func currentScreenSelector() -> ScreenSelector {
        ScreenSelector(strategy: AppSettings.shared.screenSelectionStrategy)
    }

    private func refreshMenubarAppearance() {
        guard let statusItem else { return }
        let button = statusItem.button
        let theme = activeTheme

        button?.title = ""
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: theme.menuBarSymbolName, accessibilityDescription: theme.appMenuTitle)
        image?.isTemplate = true
        button?.image = image
        button?.image?.accessibilityDescription = theme.appMenuTitle
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu, theme: activeTheme)
        return menu
    }

    /// Fills an existing menu with the current `recent` snapshot. Called both
    /// from `buildMenu` (initial attach) and from `menuNeedsUpdate(_:)` (every
    /// time the user clicks the menu-bar icon) so relative timestamps stay
    /// fresh without a timer.
    private func populate(_ menu: NSMenu, theme: AppTheme) {
        menu.removeAllItems()

        let title = NSMenuItem(title: theme.appMenuTitle, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        if recent.isEmpty {
            let empty = NSMenuItem(title: theme.emptyRecentEventsTitle,
                                   action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: theme.recentEventsTitle,
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let formatter = MenuFeedFormatter(locale: theme.menuLocale)
            let now = Date()
            for event in recent {
                let item = NSMenuItem()
                item.attributedTitle = formatter.attributedRow(
                    for: event, theme: theme, now: now
                )
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit",
                              action: #selector(NSApp.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @MainActor @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.show()
    }

    private func setupQueueCallbacks() {
        queue.onShow = { [weak self] event in
            guard let self else { return }
            if AppSettings.shared.soundEnabled { NSSound(named: "Tink")?.play() }
            recent.insert(event, at: 0)
            // Matches the 5-row cap of the status-bar menu (see MenuFeedFormatter).
            recent = Array(recent.prefix(5))
            refreshMenubarAppearance()
            // Tell the Settings status bar about this delivery so
            // "last triggered N분 전" reflects reality instead of a dummy.
            AppSettings.shared.recordEventDelivered(project: event.project)
            presenter.show(
                event: event,
                pendingCount: queue.pendingCount,
                theme: activeTheme,
                screen: currentScreenSelector().selectScreen(),
                residence: AppSettings.shared.alertResidenceMode,
                residenceSeconds: AppSettings.shared.displayDurationSeconds,
                reduceMotion: !AppSettings.shared.pulseAnimationEnabled,
                defaultExpansion: AppSettings.shared.defaultExpansionMode,
                onClose: { [weak self] in self?.queue.dismissCurrent(force: true) }
            )
        }
        queue.onHide = { [weak self] in
            self?.presenter.hide()
        }
    }

    /// Enqueues a synthetic event representing the chosen status. Used by
    /// the Settings Sandbox "Trigger" button to fire a real notification
    /// through the same pipeline production events travel — so the user
    /// verifies their theme / residence / expansion settings against the
    /// actual `NotchPresenter`, not a SwiftUI mockup. Uses the shared
    /// `Event.preview(status:)` factory so the triggered pill matches
    /// the Sandbox preview byte-for-byte, including `durationMs` which
    /// drives the "3s" chip shown in the expanded pill.
    func triggerTestNotification(status: EventStatus) {
        queue.enqueue(.preview(status: status))
    }

    private func startServer() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            NSLog("Tockk: could not resolve Application Support directory; socket server not started")
            return
        }
        let dir = appSupport.appendingPathComponent("Tockk", isDirectory: true)

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let socketPath = dir.appendingPathComponent("tockk.sock").path
        let server = SocketServer(path: socketPath)

        server.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.queue.enqueue(event)
            }
        }

        do {
            try server.start()
            self.server = server
            NSLog("Tockk: listening at \(socketPath)")
        } catch let error as POSIXError where error.code == .EADDRINUSE {
            // Another live Tockk is already listening on the socket. Leave it
            // alone — stealing the path orphans the other instance's fd and
            // breaks both CLI `tockk send` and the in-app Trigger button the
            // moment this process exits.
            NSLog("Tockk: another instance is already listening; not binding socket")
        } catch {
            NSLog("Tockk: failed to start socket server: \(error)")
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            populate(menu, theme: activeTheme)
        }
    }
}
