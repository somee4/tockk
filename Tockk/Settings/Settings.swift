import SwiftUI
#if canImport(ServiceManagement)
import ServiceManagement
#endif

protocol LaunchAtLoginControlling {
    func currentValue() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

struct SMAppLaunchAtLoginController: LaunchAtLoginControlling {
    func currentValue() -> Bool {
#if canImport(ServiceManagement)
        SMAppService.mainApp.status == .enabled
#else
        false
#endif
    }

    func setEnabled(_ enabled: Bool) throws {
#if canImport(ServiceManagement)
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
#endif
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store: UserDefaults
    @AppStorage("soundEnabled") var soundEnabled: Bool = true
    /// Legacy key: the auto-dismiss duration used when
    /// `alertResidenceMode == .dismissAfter`. Also reused as the collapse
    /// timer for `.collapseAfter`. Kept under the same `UserDefaults` key for
    /// settings continuity across upgrades.
    @AppStorage("displayDurationSeconds") var displayDurationSeconds: Double = 30.0
    @AppStorage("minDisplaySeconds") var minDisplaySeconds: Double = 2.0
    /// When enabled, the panel border pulses briefly on alert arrival. The
    /// system-level `accessibilityReduceMotion` still wins and suppresses the
    /// effect regardless of this preference.
    @AppStorage("pulseAnimationEnabled") var pulseAnimationEnabled: Bool = true

    @Published private(set) var launchAtLoginEnabled: Bool

    /// Project name of the most-recent event that reached the presenter.
    /// Shown in the Settings status bar so the user can confirm "yes, the
    /// hook is actually delivering events from the project I'm working in."
    /// Not persisted across launches — stale project info is less useful
    /// than an honest "아직 없음".
    @Published private(set) var lastEventProject: String?
    /// Timestamp of the most-recent delivered event. Paired with
    /// `lastEventProject` to drive "N분 전 트리거" in the Settings status bar
    /// via `RelativeDateTimeFormatter`.
    @Published private(set) var lastEventAt: Date?

    private let launchAtLoginController: LaunchAtLoginControlling

    init(
        store: UserDefaults = .standard,
        launchAtLoginController: LaunchAtLoginControlling = SMAppLaunchAtLoginController()
    ) {
        self.store = store
        self.launchAtLoginController = launchAtLoginController
        self.launchAtLoginEnabled = launchAtLoginController.currentValue()
    }

    var themePreset: AppThemePreset {
        get {
            guard let rawValue = store.string(forKey: "themePreset"),
                  let preset = AppThemePreset(rawValue: rawValue) else {
                return .defaultValue
            }

            return preset
        }
        set {
            store.set(newValue.rawValue, forKey: "themePreset")
            notifySettingsChanged()
        }
    }

    var alertResidenceMode: AlertResidenceMode {
        get {
            guard let raw = store.string(forKey: "alertResidenceMode"),
                  let mode = AlertResidenceMode(rawValue: raw) else {
                return .defaultValue
            }
            return mode
        }
        set {
            store.set(newValue.rawValue, forKey: "alertResidenceMode")
            notifySettingsChanged()
        }
    }

    var defaultExpansionMode: DefaultExpansionMode {
        get {
            guard let raw = store.string(forKey: "defaultExpansionMode"),
                  let mode = DefaultExpansionMode(rawValue: raw) else {
                return .defaultValue
            }
            return mode
        }
        set {
            store.set(newValue.rawValue, forKey: "defaultExpansionMode")
            notifySettingsChanged()
        }
    }

    var screenSelectionStrategy: ScreenSelectionStrategy {
        get {
            guard let raw = store.string(forKey: "screenSelectionStrategy"),
                  let strategy = ScreenSelectionStrategy(rawValue: raw) else {
                return .defaultValue
            }
            return strategy
        }
        set {
            store.set(newValue.rawValue, forKey: "screenSelectionStrategy")
            notifySettingsChanged()
        }
    }

    /// User-chosen UI language. Persisted under `preferredLanguage` for our own
    /// display, and mirrored into `AppleLanguages` so macOS picks the right
    /// `.lproj` at launch. The effect is only visible after the next launch —
    /// the Settings UI surfaces that via a "Relaunch to apply" notice.
    var preferredLanguage: AppLanguage {
        get {
            guard let raw = store.string(forKey: "preferredLanguage"),
                  let value = AppLanguage(rawValue: raw) else {
                return .defaultValue
            }
            return value
        }
        set {
            store.set(newValue.rawValue, forKey: "preferredLanguage")
            if let code = newValue.appleLanguageCode {
                store.set([code], forKey: "AppleLanguages")
            } else {
                store.removeObject(forKey: "AppleLanguages")
            }
            notifySettingsChanged()
        }
    }

    var activeTheme: AppTheme {
        AppTheme(preset: themePreset)
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = launchAtLoginController.currentValue()
    }

    /// Schedule an `objectWillChange` notification for the next runloop tick.
    ///
    /// Our UserDefaults-backed computed properties are driven by SwiftUI
    /// `Binding`s (segmented pickers, theme cards, etc.). The binding's setter
    /// often runs *inside* a view update — e.g. mid-gesture on a segmented
    /// Picker — and calling `objectWillChange.send()` synchronously there
    /// produces SwiftUI's "Publishing changes from within view updates is
    /// not allowed, this will cause undefined behavior." warning in the
    /// console.
    ///
    /// Deferring to the next runloop guarantees the publisher fires *after*
    /// SwiftUI finishes the current render pass. The write to `UserDefaults`
    /// has already happened synchronously, so the next read returns the new
    /// value; we're only moving the "something changed" notification by one
    /// tick.
    private func notifySettingsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Records that an event has just been presented. Call this from the
    /// event-queue callback so the Settings status bar (and anything else
    /// observing `AppSettings`) can surface a truthful "last trigger" line.
    func recordEventDelivered(project: String) {
        lastEventProject = project
        lastEventAt = Date()
    }

    func updateLaunchAtLoginEnabled(_ enabled: Bool) {
        let previousValue = launchAtLoginEnabled
        launchAtLoginEnabled = enabled

        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLoginEnabled = launchAtLoginController.currentValue()
        } catch {
            launchAtLoginEnabled = previousValue
        }
    }
}
