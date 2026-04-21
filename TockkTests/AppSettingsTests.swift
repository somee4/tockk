import XCTest
@testable import Tockk

@MainActor
final class AppSettingsTests: XCTestCase {
    func testThemePresetDefaultsToConfiguredDefaultValue() {
        let store = makeStore(testName: #function)
        let settings = AppSettings(store: store, launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: false))

        // Mirrors AppThemePreset.defaultValue; changing the default in one
        // place should automatically flow through here.
        XCTAssertEqual(settings.themePreset, AppThemePreset.defaultValue)
    }

    func testThemePresetPersistsRawValue() {
        let store = makeStore(testName: #function)
        let settings = AppSettings(store: store, launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: false))

        settings.themePreset = .developerTool

        XCTAssertEqual(store.string(forKey: "themePreset"), AppThemePreset.developerTool.rawValue)
    }

    func testInitReflectsLaunchAtLoginControllerState() {
        let settings = AppSettings(launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: true))

        XCTAssertTrue(settings.launchAtLoginEnabled)
    }

    func testUpdateLaunchAtLoginEnabledPersistsThroughController() {
        let controller = LaunchAtLoginControllerSpy(isEnabled: false)
        let settings = AppSettings(launchAtLoginController: controller)

        settings.updateLaunchAtLoginEnabled(true)

        XCTAssertTrue(settings.launchAtLoginEnabled)
        XCTAssertEqual(controller.setEnabledCalls, [true])
    }

    func testUpdateLaunchAtLoginEnabledRestoresPreviousValueWhenControllerThrows() {
        let controller = LaunchAtLoginControllerSpy(isEnabled: false, error: LaunchAtLoginTestError.updateFailed)
        let settings = AppSettings(launchAtLoginController: controller)

        settings.updateLaunchAtLoginEnabled(true)

        XCTAssertFalse(settings.launchAtLoginEnabled)
        XCTAssertEqual(controller.setEnabledCalls, [true])
    }

    // MARK: - Alert residence & screen selection

    func testAlertResidenceModeDefaultsToPersistent() {
        let store = makeStore(testName: #function)
        let settings = AppSettings(store: store, launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: false))

        XCTAssertEqual(settings.alertResidenceMode, .persistent)
    }

    func testAlertResidenceModePersistsAcrossReloads() {
        let store = makeStore(testName: #function)
        let first = AppSettings(store: store, launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: false))
        first.alertResidenceMode = .dismissAfter

        let second = AppSettings(store: store, launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: false))
        XCTAssertEqual(second.alertResidenceMode, .dismissAfter)
    }

    func testScreenSelectionStrategyDefaultsToActiveWindow() {
        let store = makeStore(testName: #function)
        let settings = AppSettings(store: store, launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: false))

        XCTAssertEqual(settings.screenSelectionStrategy, .activeWindow)
    }

    func testScreenSelectionStrategyPersistsRawValue() {
        let store = makeStore(testName: #function)
        let settings = AppSettings(store: store, launchAtLoginController: LaunchAtLoginControllerSpy(isEnabled: false))

        settings.screenSelectionStrategy = .mainDisplay

        XCTAssertEqual(
            store.string(forKey: "screenSelectionStrategy"),
            ScreenSelectionStrategy.mainDisplay.rawValue
        )
    }
}

private func makeStore(testName: String) -> UserDefaults {
    let suiteName = "AppSettingsTests.\(testName)"
    let store = UserDefaults(suiteName: suiteName)!
    store.removePersistentDomain(forName: suiteName)
    return store
}

private final class LaunchAtLoginControllerSpy: LaunchAtLoginControlling {
    private(set) var isEnabled: Bool
    private let error: Error?
    private(set) var setEnabledCalls: [Bool] = []

    init(isEnabled: Bool, error: Error? = nil) {
        self.isEnabled = isEnabled
        self.error = error
    }

    func currentValue() -> Bool {
        isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)

        if let error {
            throw error
        }

        isEnabled = enabled
    }
}

private enum LaunchAtLoginTestError: Error {
    case updateFailed
}
