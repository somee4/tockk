import AppKit
import XCTest
@testable import Tockk

final class ScreenSelectorTests: XCTestCase {
    // MARK: - screenIndex(containing:in:)

    func testScreenIndexHitsFirstFrameContainingPoint() {
        // Classic dual monitor: 1920x1080 primary, 2560x1440 secondary to the right.
        let frames = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        ]
        XCTAssertEqual(screenIndex(containing: CGPoint(x: 100, y: 100), in: frames), 0)
        XCTAssertEqual(screenIndex(containing: CGPoint(x: 2500, y: 200), in: frames), 1)
    }

    func testScreenIndexReturnsNilWhenPointOutsideAllFrames() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        XCTAssertNil(screenIndex(containing: CGPoint(x: 200, y: 200), in: frames))
    }

    func testScreenIndexReturnsNilForEmptyFrames() {
        XCTAssertNil(screenIndex(containing: .zero, in: []))
    }

    func testScreenIndexBoundaryBehaviorMatchesCGRectContains() {
        // CGRect.contains is inclusive on origin, exclusive on max edges.
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        XCTAssertEqual(screenIndex(containing: CGPoint(x: 0, y: 0), in: frames), 0)
        XCTAssertNil(screenIndex(containing: CGPoint(x: 100, y: 100), in: frames))
    }

    // MARK: - Strategy metadata

    func testEveryStrategyExposesDisplayName() {
        for strategy in ScreenSelectionStrategy.allCases {
            XCTAssertFalse(strategy.displayName.isEmpty, "\(strategy) must be labelable in UI")
        }
    }

    func testDefaultStrategyFavorsActiveWindow() {
        // Rationale: Tockk's product promise is catching the user's attention
        // where they are looking. Active-window is the only default that honors
        // that on multi-monitor setups.
        XCTAssertEqual(ScreenSelectionStrategy.defaultValue, .activeWindow)
    }

    func testStrategyIsCodableAsRawString() throws {
        let encoded = try JSONEncoder().encode(ScreenSelectionStrategy.mainDisplay)
        let decoded = try JSONDecoder().decode(ScreenSelectionStrategy.self, from: encoded)
        XCTAssertEqual(decoded, .mainDisplay)
    }

    // MARK: - ScreenSelector (smoke)

    func testSelectorReturnsNonNilInSingleDisplayEnvironment() {
        // Unit test runners always have at least one display; we only verify
        // the selector doesn't crash or return nil under normal conditions.
        let selector = ScreenSelector(strategy: .mainDisplay)
        XCTAssertNotNil(selector.selectScreen())
    }
}
