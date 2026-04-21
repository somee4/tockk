import SwiftUI

@main
struct TockkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { SettingsView() }
    }
}
