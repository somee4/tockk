import XCTest
@testable import Tockk

@MainActor
final class EventQueueTests: XCTestCase {

    func testEnqueueShowsFirstEventImmediatelyAndQueuesRest() {
        let queue = EventQueue(minDisplaySeconds: 0, displayDuration: 999, interAlertGap: 0)
        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertNil(queue.current)

        queue.enqueue(sampleEvent(title: "first"))
        XCTAssertEqual(queue.current?.title, "first")
        XCTAssertEqual(queue.pendingCount, 0, "nothing waiting behind")

        queue.enqueue(sampleEvent(title: "second"))
        XCTAssertEqual(queue.current?.title, "first", "first still showing")
        XCTAssertEqual(queue.pendingCount, 1, "second waiting behind")
    }

    func testSequentialDisplayOnDismiss() {
        let queue = EventQueue(minDisplaySeconds: 0, displayDuration: 999, interAlertGap: 0)
        queue.enqueue(sampleEvent(title: "A"))
        queue.enqueue(sampleEvent(title: "B"))

        XCTAssertEqual(queue.current?.title, "A")
        XCTAssertEqual(queue.pendingCount, 1)

        queue.dismissCurrent()

        XCTAssertEqual(queue.current?.title, "B")
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testPersistentModeSkipsAutoDismiss() async throws {
        // With displayDuration: nil the queue must never self-dismiss. This
        // is the behavior underpinning `AlertResidenceMode.persistent`.
        let queue = EventQueue(minDisplaySeconds: 0, displayDuration: nil, interAlertGap: 0)
        queue.enqueue(sampleEvent(title: "persistent"))
        XCTAssertEqual(queue.current?.title, "persistent")

        try await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
        XCTAssertEqual(
            queue.current?.title,
            "persistent",
            "nil displayDuration must leave the event visible indefinitely"
        )
    }

    func testSetDisplayDurationSwitchesToPersistentMidFlight() async throws {
        let queue = EventQueue(minDisplaySeconds: 0, displayDuration: 0.1, interAlertGap: 0)
        queue.enqueue(sampleEvent(title: "A"))
        // Switch to persistent before the auto-dismiss timer fires.
        queue.setDisplayDuration(nil)

        try await Task.sleep(nanoseconds: 300_000_000)  // 0.3s > original 0.1s
        XCTAssertNotNil(
            queue.current,
            "switching to persistent must cancel the pending auto-dismiss"
        )
    }

    func testMinDisplayTimePreventsEarlyDismiss() {
        let queue = EventQueue(minDisplaySeconds: 10, displayDuration: 999, interAlertGap: 0)
        queue.enqueue(sampleEvent(title: "A"))
        XCTAssertNotNil(queue.current)

        queue.dismissCurrent()  // should be ignored — minimum not met

        XCTAssertNotNil(queue.current, "should not dismiss before min time")
        XCTAssertEqual(queue.current?.title, "A")
    }

    func testForceDismissBypassesMinDisplayTime() {
        // Explicit user actions (X, ESC) must dismiss immediately regardless
        // of minDisplaySeconds — that guard exists to prevent auto-dismiss
        // flashing, not to reject deliberate user dismissal.
        let queue = EventQueue(minDisplaySeconds: 10, displayDuration: 999, interAlertGap: 0)
        queue.enqueue(sampleEvent(title: "A"))
        queue.enqueue(sampleEvent(title: "B"))
        XCTAssertEqual(queue.current?.title, "A")

        queue.dismissCurrent(force: true)

        XCTAssertEqual(queue.current?.title, "B", "force dismiss advances the queue")
    }

    func testInterAlertGapDelaysNextAfterDismiss() async throws {
        // Back-to-back alerts would feel rushed if the next drop begins before
        // the close animation finishes reading as a close. The queue should
        // hold for `interAlertGap` seconds before advancing to the next.
        let queue = EventQueue(
            minDisplaySeconds: 0,
            displayDuration: 999,
            interAlertGap: 0.2
        )
        queue.enqueue(sampleEvent(title: "A"))
        queue.enqueue(sampleEvent(title: "B"))
        XCTAssertEqual(queue.current?.title, "A")

        queue.dismissCurrent(force: true)

        // During the gap, current must be nil (not yet advanced).
        XCTAssertNil(
            queue.current,
            "gap should leave an empty beat between dismiss and next"
        )
        XCTAssertEqual(queue.pendingCount, 1, "B still queued during gap")

        try await Task.sleep(nanoseconds: 300_000_000)  // 0.3s > 0.2s gap
        XCTAssertEqual(
            queue.current?.title,
            "B",
            "after the gap elapses, next event must be shown"
        )
    }

    func testEnqueueDuringGapDoesNotBypassIt() async throws {
        // When A is dismissed with B already queued, a gap starts. A third
        // event C that lands during the gap must not jump ahead of B, and
        // must not shorten the gap — the queued sequence continues in order.
        let queue = EventQueue(
            minDisplaySeconds: 0,
            displayDuration: 999,
            interAlertGap: 0.2
        )
        queue.enqueue(sampleEvent(title: "A"))
        queue.enqueue(sampleEvent(title: "B"))
        queue.dismissCurrent(force: true)
        XCTAssertNil(queue.current, "gap active after dismiss with queue backlog")

        // Arrives during the gap.
        queue.enqueue(sampleEvent(title: "C"))
        XCTAssertNil(queue.current, "enqueue during gap must not bypass it")

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(queue.current?.title, "B", "queue order preserved through gap")
        XCTAssertEqual(queue.pendingCount, 1, "C still waiting")
    }

    func testFreshEnqueueSkipsGap() {
        // First alert after a period of silence must show immediately — the
        // gap only applies to dismiss→advance chains, not to cold-start.
        let queue = EventQueue(
            minDisplaySeconds: 0,
            displayDuration: 999,
            interAlertGap: 0.2
        )
        queue.enqueue(sampleEvent(title: "A"))
        XCTAssertEqual(queue.current?.title, "A", "fresh enqueue is immediate")
    }

    private func sampleEvent(title: String) -> Event {
        Event(agent: "test", project: "p", status: .success, title: title)
    }
}
