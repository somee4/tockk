import SwiftUI
import AppKit
import DynamicNotchKit

// MARK: - NotchPresenter

/// Bridges EventQueue callbacks to DynamicNotchKit.
///
/// `NotchPresenter` owns a single `DynamicNotch` instance at a time.
/// It uses DynamicNotchKit's compact/expanded states to show `CompactNotchView`
/// and `ExpandedNotchView` respectively. Timing is owned entirely by `EventQueue`
/// (for full-dismiss policies) and `NotchContent` (for collapse-to-compact) —
/// no auto-dismiss is configured here.
@MainActor
final class NotchPresenter {
    // DynamicNotch is typed to the concrete view types we pass in.
    // We use AnyView to keep the presenter's type simple.
    private var notch: DynamicNotch<AnyView, EmptyView, EmptyView>?
    private var showTask: Task<Void, Never>?

    /// Shows a notification in the notch.
    ///
    /// - Parameters:
    ///   - event: The event to display.
    ///   - pendingCount: Number of events waiting behind this one.
    ///   - theme: The active theme tokens.
    ///   - screen: The display to present on. When `nil`, DynamicNotchKit falls
    ///     back to `NSScreen.screens[0]`.
    ///   - residence: Policy for how long the alert stays. Controls whether
    ///     `NotchContent` schedules a collapse timer and whether pulse motion
    ///     should be suppressed.
    ///   - residenceSeconds: Seconds for the collapse/dismiss timer.
    ///   - reduceMotion: User-level preference to suppress pulse motion.
    ///   - onClose: Called when the user dismisses the expanded view.
    func show(
        event: Event,
        pendingCount: Int,
        theme: AppTheme,
        screen: NSScreen? = nil,
        residence: AlertResidenceMode = .defaultValue,
        residenceSeconds: TimeInterval = 30,
        reduceMotion: Bool = false,
        defaultExpansion: DefaultExpansionMode = .defaultValue,
        onClose: @escaping () -> Void
    ) {
        // Cancel any in-flight show task and tear down the previous notch.
        showTask?.cancel()
        notch = nil

        let contentView = NotchContent(
            event: event,
            pendingCount: pendingCount,
            theme: theme,
            residence: residence,
            residenceSeconds: residenceSeconds,
            reduceMotion: reduceMotion,
            defaultExpansion: defaultExpansion,
            onClose: onClose
        )

        // Use the expanded-only convenience init so compact() falls through to hide().
        // We manage compact/expanded ourselves via NotchContent's @State.
        // NOTE: `.keepVisible`은 일부러 빼뒀다. DynamicNotchKit의 `_hide`는
        // `.keepVisible` + `isHovering`이면 100ms 단위로 hide를 폴링하며
        // hover를 벗어날 때까지 미룬다. 우리는 auto-dismiss 타이밍을
        // EventQueue가 전적으로 소유하므로 `.keepVisible`이 보호해줄 대상이
        // 없고, 오히려 × 버튼을 눌렀을 때 "호버 영역을 벗어나야만 닫히는"
        // 체감 버그를 만든다. hover 시각 피드백은 `.increaseShadow`로 충분.
        let notchInstance = DynamicNotch<AnyView, EmptyView, EmptyView>(
            hoverBehavior: [.increaseShadow],
            style: .auto,
            expanded: { AnyView(contentView) }
        )
        // Shape the motion to the "똑" of Tockk — a quick, punchy hit with
        // the faintest bounce, not a slow drop. Closing is sharper than the
        // library default so dismissal feels crisp, not dragged out.
        //
        // 큐에 여러 알림이 쌓여 연속 전환될 때 close와 open이 overlap되어
        // choppy해 보이는 문제가 있어 튜닝 포인트가 있다:
        // - opening: damping을 약간 낮춰 "똑" 하고 내려와 살짝 정착하는
        //   질감을 살리되, 연속 arrival 시 바운스가 과하지 않도록 0.78
        //   선에서 멈춘다. response는 조금 늘려 드롭이 체감되도록.
        // - closing: easeIn으로 가속감을 줘 위로 빨려 올라가는 듯한
        //   "retreat" 인상. 뒤이어 오는 open과 곡선 방향이 대비되어
        //   스택 전환 때 오히려 박자가 분명해진다.
        // - conversion: compact↔expanded 폭 변화에 쓰이므로 damping을
        //   조금 더 풀어 확장 시 살짝 breath 있게.
        notchInstance.transitionConfiguration.openingAnimation =
            .spring(response: 0.38, dampingFraction: 0.78)
        notchInstance.transitionConfiguration.closingAnimation =
            .timingCurve(0.55, 0.0, 0.85, 0.45, duration: 0.18)
        // conversion은 compact↔expanded에서 노치 바깥 container의 폭/높이를
        // 보간하는 곡선이다. 스프링을 쓰면 크기가 튕기면서 안쪽 fade와
        // 어긋나 전환이 "끊겨" 보였다. easeInOut으로 단일 호흡을 유지.
        notchInstance.transitionConfiguration.conversionAnimation =
            .easeInOut(duration: 0.34)
        self.notch = notchInstance

        showTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            if let screen {
                await self?.notch?.expand(on: screen)
            } else {
                await self?.notch?.expand()
            }
        }
    }

    /// Hides the currently displayed notch.
    func hide() {
        showTask?.cancel()
        showTask = nil
        let captured = notch
        notch = nil
        Task {
            await captured?.hide()
        }
    }
}

// MARK: - NotchContent

/// Internal SwiftUI view rendered inside the expanded notch.
/// Manages the compact ↔ expanded toggle without leaking state into `NotchPresenter`.
/// For `AlertResidenceMode.collapseAfter`, schedules its own timer to fold
/// the expanded view back to compact while leaving dismissal to the user.
private struct NotchContent: View {
    let event: Event
    let pendingCount: Int
    let theme: AppTheme
    let residence: AlertResidenceMode
    let residenceSeconds: TimeInterval
    let reduceMotion: Bool
    let defaultExpansion: DefaultExpansionMode
    let onClose: () -> Void

    @State private var expanded: Bool
    @State private var collapseTask: Task<Void, Never>?

    init(
        event: Event,
        pendingCount: Int,
        theme: AppTheme,
        residence: AlertResidenceMode,
        residenceSeconds: TimeInterval,
        reduceMotion: Bool,
        defaultExpansion: DefaultExpansionMode,
        onClose: @escaping () -> Void
    ) {
        self.event = event
        self.pendingCount = pendingCount
        self.theme = theme
        self.residence = residence
        self.residenceSeconds = residenceSeconds
        self.reduceMotion = reduceMotion
        self.defaultExpansion = defaultExpansion
        self.onClose = onClose
        // Honour the user's default-expansion preference on first paint.
        // After that, user interaction drives the state.
        self._expanded = State(initialValue: defaultExpansion == .expanded)
    }

    // 노치 마스크(NotchShape)는 상단에서 안쪽으로 휘어들어오는 곡선을 가진다.
    // arrivalEffect의 pulse shadow(radius ~26pt)가 pill 위쪽으로 번지면서
    // 그 곡선에 걸려 윗변이 잘려 보이는 현상이 있어, 콘텐츠를 노치 바닥에서
    // 한 호흡 더 내려 pulse가 숨 쉴 여백을 확보한다.
    private let notchTopInset: CGFloat = 8

    var body: some View {
        Group {
            if expanded {
                ExpandedNotchView(
                    event: event,
                    theme: theme,
                    reduceMotion: reduceMotion,
                    // 닫기(×)는 완전 dismiss로 직행한다. 이전에는 여기서
                    // `expanded = false`를 선행시켰는데, 그 결과 내부 뷰가
                    // CompactNotchView로 먼저 전환되는 0.3s 애니메이션이
                    // 재생된 뒤 노치 전체가 닫혔다. 연속 알림을 빠르게
                    // 닫을 때 "완전 닫기가 아니라 접히는 느낌"으로 보이던
                    // 원인. onClose가 호출되면 presenter.hide()가 뷰
                    // 자체를 파괴하므로 내부 state는 건드릴 필요가 없다.
                    onClose: onClose,
                    onCollapse: { expanded = false }
                )
                .transition(.opacity)
            } else {
                CompactNotchView(
                    event: event,
                    pendingCount: pendingCount,
                    theme: theme,
                    reduceMotion: reduceMotion,
                    onClose: onClose,
                    onExpand: { expanded = true }
                )
                .onTapGesture {
                    expanded = true
                }
                .transition(.opacity)
            }
        }
        // compact↔expanded 전환 질감:
        // - 바깥 노치 container(DynamicNotchKit)는 conversionAnimation의
        //   easeInOut(0.34)로 폭/높이를 연속 보간한다. 안쪽 컨텐츠가 scale
        //   애니메이션까지 돌리면 두 모션이 어긋나 "두 번 움직이는" 느낌이
        //   되므로, 안쪽은 opacity crossfade만 담당해 외부 리사이즈의
        //   호흡에 얹힌다. 결과적으로 "점점 커져서 expanded, 점점 작아져서
        //   compact"의 단일 제스처처럼 읽힌다.
        // - 스프링 대신 동일한 easeInOut을 써서 바깥/안쪽 곡선을 맞췄다.
        //   안쪽 fade는 살짝 더 짧게 잡아 컨텐츠 교체가 리사이즈 중반쯤
        //   이미 끝나도록 — 새 사이즈에 자리 잡은 후 스냅으로 보이지
        //   않도록 완성 타이밍을 앞당긴다.
        .padding(.top, notchTopInset)
        .animation(.easeInOut(duration: 0.28), value: expanded)
        .onChange(of: expanded) { isExpanded in
            handleExpansionChange(isExpanded: isExpanded)
        }
        .onDisappear {
            collapseTask?.cancel()
        }
    }

    private func handleExpansionChange(isExpanded: Bool) {
        collapseTask?.cancel()
        guard isExpanded,
              residence == .collapseAfter,
              residenceSeconds > 0
        else { return }

        let seconds = residenceSeconds
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            expanded = false
        }
    }
}
