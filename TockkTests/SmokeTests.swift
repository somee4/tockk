import XCTest
import SwiftUI
@testable import Tockk

@MainActor
final class SmokeTests: XCTestCase {
    func testSettingsWindowControllerReusesSingleWindowInstance() {
        let controller = SettingsWindowController()

        let first = controller.makeWindow()
        let second = controller.makeWindow()

        XCTAssertTrue(first === second)
        XCTAssertEqual(first.title, "Tockk Settings")
    }

    func testSettingsWindowControllerUsesManualWindowSizing() throws {
        let controller = SettingsWindowController()
        let window = controller.makeWindow()
        let hostingController = try XCTUnwrap(window.contentViewController as? NSHostingController<SettingsView>)
        // Bumped to the Direction-C layout footprint (900×660) so the
        // Sandbox rail and tab content both fit without scrolling.
        let expectedFrameSize = NSSize(width: 900, height: 660)
        let expectedContentSize = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: expectedFrameSize)
        ).size

        if #available(macOS 13.0, *) {
            XCTAssertEqual(hostingController.sizingOptions, NSHostingSizingOptions())
        }

        XCTAssertEqual(window.contentMinSize.width, expectedContentSize.width)
        XCTAssertEqual(window.contentMinSize.height, expectedContentSize.height)
    }
}
