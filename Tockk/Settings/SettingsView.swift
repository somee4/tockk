import SwiftUI

/// Root of the Settings window. Implements the "Direction C" layout from the
/// handoff design bundle:
///
///   [status bar                                            ] ← hook · project · auto-save
///   [pill tab bar                                          ] ← general / appearance / notifications / integrations
///   [tab content                         │  Sandbox rail   ]
///   [                                    │                 ]
///   [footer: version · links                               ]
///
/// The Sandbox rail is a live preview simulator: changing tabs and settings
/// on the left updates the rendered notch on the right, and the Trigger
/// button dispatches a real event through `AppDelegate` — same pipeline as
/// production alerts, not a SwiftUI mock.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab = .appearance
    @State private var sandboxStatus: EventStatus = .success
    @State private var savedHint: Bool = false
    @State private var savedHintTask: Task<Void, Never>?
    /// Latest snapshot of `~/.claude/settings.json` hook state. Queried on
    /// window open and refreshed whenever the user acts on the Integrations
    /// tab. Drives the "훅 OK" pill in the status bar.
    @State private var hookInstalled: Bool = false
    /// Incremented once a second so `RelativeDateTimeFormatter` output in
    /// the status bar reflects the passage of time without needing a manual
    /// refresh. Re-ticks don't cost anything here — the view body is tiny.
    @State private var tickNonce: Int = 0

    private let statusBarTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            SettingsStatusBar(
                hookInstalled: hookInstalled,
                projectName: settings.lastEventProject,
                lastEventAt: settings.lastEventAt,
                showsSavedHint: savedHint
            )

            SettingsTabBar(selection: $selectedTab)

            HStack(spacing: 0) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .textBackgroundColor))

                SettingsSandboxRail(
                    previewStatus: $sandboxStatus,
                    defaultExpansion: settings.defaultExpansionMode,
                    themePreset: settings.themePreset,
                    projectName: settings.lastEventProject ?? "claude-code",
                    onTrigger: { AppDelegate.shared?.triggerTestNotification(status: sandboxStatus) }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            SettingsFooterView()
        }
        .frame(minWidth: SettingsDesign.windowWidth, maxWidth: .infinity,
               minHeight: SettingsDesign.windowHeight, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refreshHookState() }
        .onReceive(statusBarTimer) { _ in tickNonce &+= 1 }
        .onChange(of: settings.themePreset) { _ in pingSaved() }
        .onChange(of: settings.defaultExpansionMode) { _ in pingSaved() }
        .onChange(of: settings.alertResidenceMode) { _ in pingSaved() }
        .onChange(of: settings.displayDurationSeconds) { _ in pingSaved() }
        .onChange(of: settings.soundEnabled) { _ in pingSaved() }
        .onChange(of: settings.pulseAnimationEnabled) { _ in pingSaved() }
        .onChange(of: settings.screenSelectionStrategy) { _ in pingSaved() }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selectedTab {
                case .general:       GeneralSettingsTab()
                case .appearance:    AppearanceSettingsTab()
                case .notifications: NotificationSettingsTab()
                case .integrations:  IntegrationsSettingsTab(onHookStateChanged: refreshHookState)
                }
            }
            .padding(SettingsDesign.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Each tab gets a fresh ScrollView identity so scroll position
        // resets on switch instead of stranding a previous tab's scroll
        // offset on the new content.
        .id(selectedTab)
    }

    // MARK: - Side effects

    /// Queries the on-disk hook state once. Fast (~1ms — reads two JSON
    /// files at most) so we can call it on every window open and on every
    /// Integrations-tab action without debouncing.
    private func refreshHookState() {
        let manager = HookSetupManager()
        hookInstalled = manager.isClaudeConfigured()
    }

    /// Flashes the "저장됨" indicator for 1.2s whenever a setting changes.
    /// Uses a task we can cancel so rapid toggles don't trail ghost timers.
    private func pingSaved() {
        savedHintTask?.cancel()
        savedHint = true
        savedHintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            savedHint = false
        }
    }
}

#Preview { SettingsView() }
