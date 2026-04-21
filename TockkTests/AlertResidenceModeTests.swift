import XCTest
@testable import Tockk

final class AlertResidenceModeTests: XCTestCase {
    func testDefaultIsPersistentToPrioritizeCatchOverClutter() {
        // Tockk's product promise is "don't let the user miss a completion."
        // Any auto-dismiss default risks failing that promise, so the baseline
        // mode must be persistent.
        XCTAssertEqual(AlertResidenceMode.defaultValue, .persistent)
    }

    func testEveryModeExposesDisplayName() {
        for mode in AlertResidenceMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode) must be labelable in UI")
        }
    }

    func testPersistentModeDoesNotNeedSeconds() {
        XCTAssertFalse(AlertResidenceMode.persistent.needsResidenceSeconds)
    }

    func testTimedModesNeedSeconds() {
        XCTAssertTrue(AlertResidenceMode.collapseAfter.needsResidenceSeconds)
        XCTAssertTrue(AlertResidenceMode.dismissAfter.needsResidenceSeconds)
    }

    func testIsRoundTripCodable() throws {
        for mode in AlertResidenceMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AlertResidenceMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }
}
