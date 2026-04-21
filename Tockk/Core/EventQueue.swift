import Foundation
import Combine

@MainActor
final class EventQueue: ObservableObject {
    @Published private(set) var current: Event?
    @Published private(set) var pendingCount: Int = 0

    var onShow: ((Event) -> Void)?
    var onHide: (() -> Void)?

    private var queue: [Event] = []
    private var currentShownAt: Date?
    private let minDisplaySeconds: TimeInterval
    /// When `nil`, the queue never auto-dismisses — the alert persists until
    /// the user acts. When set, the timer fires after the interval elapses.
    private var displayDuration: TimeInterval?
    private var autoDismissTask: Task<Void, Never>?
    /// Breathing gap between "dismissing current" and "showing next from the
    /// queue". Without it, back-to-back alerts feel rushed — the new pill
    /// drops in before the close animation has finished reading as a close.
    /// A fresh `enqueue()` (no event currently showing) is not gated by this
    /// — only dismiss→advance transitions are.
    private let interAlertGap: TimeInterval
    private var gapTask: Task<Void, Never>?

    init(
        minDisplaySeconds: TimeInterval = 2.0,
        displayDuration: TimeInterval? = 30.0,
        interAlertGap: TimeInterval = 0.25
    ) {
        self.minDisplaySeconds = minDisplaySeconds
        self.displayDuration = displayDuration
        self.interAlertGap = interAlertGap
    }

    /// Updates the auto-dismiss duration live. Pass `nil` to disable
    /// auto-dismiss ("persistent" mode). Cancels any timer already running
    /// for the current alert and re-schedules under the new policy.
    func setDisplayDuration(_ seconds: TimeInterval?) {
        displayDuration = seconds
        autoDismissTask?.cancel()
        guard current != nil, let seconds, seconds > 0 else { return }
        scheduleAutoDismiss(after: seconds)
    }

    func enqueue(_ event: Event) {
        queue.append(event)
        updatePending()
        // Gap이 돌고 있으면 그 task가 끝날 때 advance가 일어난다 — 여기서
        // advance()를 또 호출하면 gap을 건너뛰게 된다. Gap이 없고 current도
        // 비어있는 평상시(첫 알림) 경로에서만 즉시 advance.
        if gapTask == nil {
            advance()
        }
    }

    /// Dismisses the currently shown event.
    ///
    /// - Parameter force: When `true`, bypasses `minDisplaySeconds`. This is
    ///   meant for explicit user actions (clicking ×, pressing ESC) — the
    ///   minimum-display guard exists to stop auto-dismiss timers from
    ///   flashing alerts off too quickly, not to reject a deliberate user
    ///   dismiss.
    func dismissCurrent(force: Bool = false) {
        guard current != nil else { return }
        if !force,
           let shownAt = currentShownAt,
           Date().timeIntervalSince(shownAt) < minDisplaySeconds {
            return
        }
        autoDismissTask?.cancel()
        current = nil
        currentShownAt = nil
        onHide?()
        scheduleNextAfterGap()
    }

    /// After a dismiss, wait `interAlertGap` before showing the next queued
    /// alert so the close animation reads as a close before the next drop
    /// begins. If the queue is empty or the gap is zero, advance immediately.
    private func scheduleNextAfterGap() {
        gapTask?.cancel()
        gapTask = nil
        guard !queue.isEmpty else { return }
        guard interAlertGap > 0 else {
            advance()
            return
        }
        gapTask = Task { [weak self] in
            let gap = await MainActor.run { self?.interAlertGap ?? 0 }
            try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run {
                self?.gapTask = nil
                self?.advance()
            }
        }
    }

    private func advance() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        currentShownAt = Date()
        updatePending()
        onShow?(next)
        if let seconds = displayDuration, seconds > 0 {
            scheduleAutoDismiss(after: seconds)
        }
    }

    private func updatePending() {
        pendingCount = queue.count
    }

    private func scheduleAutoDismiss(after seconds: TimeInterval) {
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { self?.dismissCurrent() }
        }
    }
}
