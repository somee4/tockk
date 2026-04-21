import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    // Sized to accommodate the two-column "Direction C" layout: tab content
    // on the left, the live Sandbox rail on the right, plus the top status bar
    // and bottom footer. The window is matched to the design's 900×620 stage
    // with an extra 40pt for the links footer.
    private let defaultFrameSize = NSSize(width: 900, height: 660)

    func makeWindow() -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        if #available(macOS 13.0, *) {
            // Manage the window size ourselves to avoid recursive constraint updates
            // between NSHostingView's automatic sizing and the fixed-width settings UI.
            hostingController.sizingOptions = []
        }

        let window = NSWindow(contentViewController: hostingController)
        let defaultContentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: defaultFrameSize)
        ).size

        window.title = "Tockk Settings"
        window.setContentSize(defaultContentSize)
        window.contentMinSize = defaultContentSize
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.identifier = NSUserInterfaceItemIdentifier("Tockk.SettingsWindow")
        window.setFrameAutosaveName("TockkSettingsWindow")

        self.window = window
        return window
    }

    func show() {
        let window = makeWindow()
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
