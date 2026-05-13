import SwiftUI
import XCTest
import DynamicNotchKit
@testable import Tockk

@MainActor
final class NotchPresenterTests: XCTestCase {
    func testShowReusesSingleDynamicNotchControllerAcrossEvents() {
        let fakeNotch = FakeDynamicNotchController()
        var creationCount = 0
        var capturedModel: NotchPresentationModel?
        let presenter = NotchPresenter { model in
            creationCount += 1
            capturedModel = model
            return fakeNotch
        }

        presenter.show(
            event: sampleEvent(title: "first"),
            pendingCount: 0,
            theme: AppTheme(preset: .developerTool),
            screen: nil,
            onClose: {}
        )
        presenter.hide()
        presenter.show(
            event: sampleEvent(title: "second"),
            pendingCount: 0,
            theme: AppTheme(preset: .developerTool),
            screen: nil,
            onClose: {}
        )

        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(capturedModel?.presentation?.event.title, "second")
    }

    func testShowWaitsForInFlightHideBeforeExpandingAgain() async {
        let fakeNotch = FakeDynamicNotchController()
        fakeNotch.shouldHoldHide = true
        let presenter = NotchPresenter { _ in fakeNotch }

        presenter.show(
            event: sampleEvent(title: "first"),
            pendingCount: 0,
            theme: AppTheme(preset: .developerTool),
            screen: nil,
            onClose: {}
        )
        await waitUntil { fakeNotch.expandCount == 1 }

        presenter.hide()
        await waitUntil { fakeNotch.hideStarted }

        presenter.show(
            event: sampleEvent(title: "second"),
            pendingCount: 0,
            theme: AppTheme(preset: .developerTool),
            screen: nil,
            onClose: {}
        )
        await Task.yield()
        XCTAssertEqual(fakeNotch.expandCount, 1)

        fakeNotch.finishHide()
        await waitUntil { fakeNotch.expandCount == 2 }
    }

    private func sampleEvent(title: String) -> Event {
        Event(agent: "test", project: "p", status: .success, title: title)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .nanoseconds(Int(timeoutNanoseconds))
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

@MainActor
private final class FakeDynamicNotchController: DynamicNotchControlling {
    var transitionConfiguration = DynamicNotchTransitionConfiguration()
    var shouldHoldHide = false
    private(set) var expandCount = 0
    private(set) var hideCount = 0
    private(set) var hideStarted = false
    private var hideContinuation: CheckedContinuation<Void, Never>?

    func expand(on screen: NSScreen) async {
        expandCount += 1
    }

    func expand() async {
        expandCount += 1
    }

    func hide() async {
        hideStarted = true
        if shouldHoldHide {
            await withCheckedContinuation { continuation in
                hideContinuation = continuation
            }
        }
        hideCount += 1
    }

    func finishHide() {
        hideContinuation?.resume()
        hideContinuation = nil
    }
}
