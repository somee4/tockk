import SwiftUI

/// The right-hand preview column of the Settings window.
///
/// The rail is a self-contained simulator:
///   • top: SANDBOX label + variant badge + Trigger button
///   • middle: a gradient mini-macOS desktop with a menubar, anchoring a
///     notch-style notification preview so the user can see how the choices
///     will actually land on their screen
///   • bottom: an event-state selector + auto-save tip
///
/// Tockk's current alerts are notch-based (no floating variant yet), so the
/// rail always anchors the preview under the notch. State changes re-mount
/// the preview so the drop-in animation replays — same idiom as the `key`
/// prop in the JSX prototype.
struct SettingsSandboxRail: View {
    @Binding var previewStatus: EventStatus
    let defaultExpansion: DefaultExpansionMode
    let themePreset: AppThemePreset
    let projectName: String
    /// Fires a real event through `EventQueue` / `NotchPresenter`. Unlike
    /// the prototype (which only replayed an in-sandbox mock animation),
    /// pressing Trigger now produces an actual notch on the chosen screen,
    /// so the user validates their settings against the real presenter.
    let onTrigger: () -> Void

    private var theme: AppTheme { AppTheme(preset: themePreset) }

    var body: some View {
        VStack(spacing: 0) {
            header
            miniDesktop
                .padding(.horizontal, 16)
                .padding(.top, 2)
            controls
            Spacer(minLength: 0)
            footerTip
        }
        .frame(width: SettingsDesign.sandboxWidth)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0x0E/255.0, green: 0x11/255.0, blue: 0x16/255.0))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.2))
                .frame(width: 0.5)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("SANDBOX")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.9))

            Text(variantBadge)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                )

            Spacer()

            Button(action: onTrigger) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                    Text("TRIGGER")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(previewAccent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var variantBadge: String {
        defaultExpansion == .compact ? "notch · compact" : "notch · extended"
    }

    // MARK: - Mini desktops (two separate)

    /// Each preview gets its own mini desktop, matching the user's mental
    /// model: the notch version simulates a Mac with a physical notch
    /// cutout (thick black top strip, pill emerges from under it); the
    /// floating version simulates a notch-less Mac (thin menubar, pill
    /// drifts in free space). Showing both side-by-side stacked lets the
    /// user see exactly how each variant renders under the current theme
    /// before committing to one.
    private var miniDesktop: some View {
        VStack(alignment: .leading, spacing: 12) {
            miniDesktopSection(label: "NOTCH · ANCHORED") {
                notchHardwareDesktop
            }
            miniDesktopSection(label: "FLOATING · FREE") {
                floatingFreeDesktop
            }
        }
    }

    /// A labeled mini-desktop slot with a small uppercase caption above
    /// each canvas, mirroring the rail's "EVENT STATE" / "MESSAGE PRESET"
    /// section labels further down. Keeps vertical rhythm consistent.
    @ViewBuilder
    private func miniDesktopSection<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.45))
            content()
        }
    }

    /// Height of each mini desktop — held constant across compact /
    /// expanded so the Sandbox rail total height doesn't shrink/grow
    /// when the user toggles variants. The window itself is fixed-size,
    /// and letting the rail outgrow it (extended was 150pt per desktop,
    /// pushing the total past the window's usable height) clipped the
    /// status bar and footer tip. Sized to comfortably fit the taller
    /// expanded pill + floating offset (~108pt) with breathing room.
    private let miniDesktopHeight: CGFloat = 120

    /// Vertical position of the floating pill inside the floating desktop.
    /// Pulled well below the menubar so the variant clearly reads as
    /// "free-floating", not "stuck to the top edge" — matching the user's
    /// ask to drop it further down from the top.
    private var floatingTopOffset: CGFloat {
        defaultExpansion == .compact ? 36 : 32
    }

    // MARK: - Notch desktop (hardware notch simulation)

    private var notchHardwareDesktop: some View {
        ZStack(alignment: .top) {
            wallpaper

            // The library's NotchView wraps our content in a black-filled
            // NotchShape that has a flat top edge. That flat top edge IS
            // the seam with the Mac's physical notch — so in preview we
            // just anchor the pill to the very top of the mini desktop
            // (y=0) and let the shape itself read as "hardware notch +
            // expanded island". No separate strip needed.
            notchVariantPreview
                .frame(maxWidth: .infinity, alignment: .top)
                .id("notch-\(previewStatus)-\(defaultExpansion)")
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        .frame(height: miniDesktopHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: previewStatus)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: defaultExpansion)
    }

    // MARK: - Floating desktop (no hardware notch)

    private var floatingFreeDesktop: some View {
        ZStack(alignment: .top) {
            wallpaper

            // Thin translucent menubar — stands in for the real macOS
            // menubar on a notchless Mac (no camera cutout), so the
            // floating pill reads as sitting ON the desktop rather than
            // merging with any hardware feature.
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 18)
                .frame(maxWidth: .infinity, alignment: .top)

            // Floating variant positioned well below the menubar so the
            // "free floating" nature is unmistakable — this is the key
            // visual difference from the notch variant above it.
            floatingVariantPreview
                .frame(maxWidth: .infinity, alignment: .top)
                .offset(y: floatingTopOffset)
                .id("float-\(previewStatus)-\(defaultExpansion)")
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        .frame(height: miniDesktopHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: previewStatus)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: defaultExpansion)
    }

    /// Shared warm-gradient wallpaper used by both mini desktops so the
    /// pair reads as two variants of the same "desktop", not two unrelated
    /// surfaces.
    private var wallpaper: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0xC8/255, green: 0xAA/255, blue: 0x85/255),
                        Color(red: 0x8A/255, green: 0x66/255, blue: 0x50/255),
                        Color(red: 0x4A/255, green: 0x35/255, blue: 0x28/255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }

    /// Renders the real production notch view (`CompactNotchView` or
    /// `ExpandedNotchView`) scaled down to fit inside the mini desktop.
    /// Using the same views the presenter uses — not a hand-rolled mock —
    /// guarantees the preview reflects every theme's actual pill
    /// background, typography, brand glyph, and status label casing. When
    /// the user switches `developerTool → practicalUtility → smallProduct`,
    /// the sandbox swap is pixel-accurate, because it *is* the same code
    /// path the notch itself draws through.
    /// Per-context scale. Tuned so each pill occupies only ~60-75% of the
    /// mini-desktop width — after `LibraryLandingWrapper` stacks the
    /// library's two padding layers (safeAreaInsets + outer
    /// `topCornerRadius` horizontal padding) the pill grows quite a bit
    /// past its naked intrinsic size, so scales below look small but
    /// produce a correctly-proportioned result.
    private var notchScale: CGFloat {
        defaultExpansion == .compact ? 0.48 : 0.38
    }
    private var floatingScale: CGFloat {
        defaultExpansion == .compact ? 0.52 : 0.42
    }

    /// Small translucent label used to identify the two stacked pills in
    /// the mini desktop. Mono-spaced so "notch" and "floating" visually
    /// align to the same cap height at the Sandbox's small scale.
    private func captionChip(text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.black.opacity(0.35)))
    }

    /// The notch-anchored variant (Dynamic Island style). Renders flush
    /// with the menubar via positioning in `miniDesktop`. The real
    /// production view (`CompactNotchView` / `ExpandedNotchView`) is used
    /// scaled so every theme token (pill background, glyph, typography)
    /// matches what the presenter actually draws.
    /// Wraps the real `CompactNotchView` / `ExpandedNotchView` content in
    /// a simulation of `DynamicNotchKit`'s *notch* landing mode: solid
    /// black fill clipped to a NotchShape (flat top edge, rounded bottom
    /// corners). This is what the library actually renders on a Mac that
    /// has a physical notch — the user's content gets forced into that
    /// peninsula silhouette. Previewing the raw pill hid this, so the
    /// user couldn't tell a notched-Mac screenshot from a floating one.
    @ViewBuilder
    private var notchVariantPreview: some View {
        let scale = notchScale

        styledLibraryWrapper(style: .notch, scale: scale) {
            if defaultExpansion == .compact {
                CompactNotchView(
                    event: previewEvent,
                    pendingCount: 0,
                    theme: theme,
                    reduceMotion: true,
                    onClose: nil,
                    onExpand: nil
                )
            } else {
                ExpandedNotchView(
                    event: previewEvent,
                    theme: theme,
                    reduceMotion: true,
                    onClose: {}
                )
            }
        }
    }

    /// The complementary *floating* landing mode: `NotchlessView` from
    /// the library renders our content inside a glass popover with a
    /// hairline stroke and a generous rounded-rect clip. Shown side-by-
    /// side with the notch variant so users on either kind of Mac can
    /// preview their own reality.
    @ViewBuilder
    private var floatingVariantPreview: some View {
        let scale = floatingScale

        styledLibraryWrapper(style: .floating, scale: scale) {
            if defaultExpansion == .compact {
                CompactNotchView(
                    event: previewEvent,
                    pendingCount: 0,
                    theme: theme,
                    reduceMotion: true,
                    onClose: nil,
                    onExpand: nil
                )
            } else {
                ExpandedNotchView(
                    event: previewEvent,
                    theme: theme,
                    reduceMotion: true,
                    onClose: {}
                )
            }
        }
    }

    /// Which of the library's two landing styles to reproduce in a
    /// wrapper.
    private enum LibraryLandingStyle { case notch, floating }

    /// Apply the library's wrapper (shape, background, stroke) around the
    /// supplied content, scaled to fit the Sandbox mini-desktop. Sizing
    /// is done via an outer `Color.clear` that claims the post-scale
    /// footprint — the real content renders inside at intrinsic size and
    /// is only visually scaled, so each theme's own metrics are respected.
    @ViewBuilder
    private func styledLibraryWrapper<Content: View>(
        style: LibraryLandingStyle,
        scale: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let inner = content()
            .fixedSize()
            // Modifiers below mirror `NotchView` / `NotchlessView` from
            // DynamicNotchKit (see vendored `NotchShape` comments).
            .modifier(LibraryLandingWrapper(style: style))

        // Intrinsic outer sizes after the wrapper's two padding layers
        // are applied to each base view. Each value is a little larger
        // than the actual rendered size so `Color.clear` never clips the
        // scaled content's shadow / stroke.
        //
        //   Notch wrapper adds:    26 top + 15 bottom + 30 sides (safe
        //                          insets) + 30 sides (outer padding)
        //   Floating wrapper adds: 15 on all sides (safe insets)
        let base: CGSize = {
            switch (style, defaultExpansion) {
            case (.notch, .compact):    return CGSize(width: 370, height: 86)   // 300x38 + wrapper
            case (.notch, .expanded):   return CGSize(width: 540, height: 180)  // 460x130 + wrapper
            case (.floating, .compact): return CGSize(width: 340, height: 72)   // 300x38 + wrapper
            case (.floating, .expanded):return CGSize(width: 500, height: 165)  // 460x130 + wrapper
            }
        }()

        Color.clear
            .frame(width: base.width * scale, height: base.height * scale)
            .overlay(alignment: .top) {
                inner
                    .scaleEffect(scale, anchor: .top)
            }
    }

    // MARK: - State controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("EVENT STATE")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.45))

                // Single-row HStack. The four uppercase mono labels
                // (COMPLETE / ERROR / WAITING / RUNNING) plus tight chip
                // padding total ~260pt, which fits the 288pt inner
                // width of the 320pt Sandbox rail with breathing room —
                // the earlier 2×2 grid was defensive but unnecessary.
                HStack(spacing: 4) {
                    ForEach([EventStatus.success, .error, .waiting, .info], id: \.self) { s in
                        stateChip(for: s)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func stateChip(for status: EventStatus) -> some View {
        let isSelected = status == previewStatus
        let accent = accent(for: status)
        return Button {
            previewStatus = status
        } label: {
            HStack(spacing: 4) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(shortLabel(for: status).uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.3)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? accent : Color.white.opacity(0.7))
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? accent.opacity(0.14) : Color.white.opacity(0.04))
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? accent : Color.white.opacity(0.12),
                                        lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer tip

    private var footerTip: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
            // Two-line VStack instead of an inline " · " concatenation: long
            // Korean strings wrapped awkwardly across the separator, and the
            // hierarchy is clearer when the primary policy note and the
            // secondary "how to test" hint sit on their own lines.
            VStack(alignment: .leading, spacing: 2) {
                Text("Changes save automatically.")
                    .foregroundStyle(Color.white.opacity(0.6))
                Text("Use the Trigger button to test real notifications")
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .font(.system(size: 10.5))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 10)
    }

    // MARK: - Helpers

    // MARK: - Library-landing simulation

    /// Reproduces the wrapping that `DynamicNotchKit` applies to user
    /// content inside `NotchView` (notch mode) and `NotchlessView`
    /// (floating mode). The library applies two layers of padding around
    /// the supplied content:
    ///
    ///   1. `safeAreaInset` — 15pt leading/trailing/bottom and
    ///      `notchSize.height` (~30pt) top, so content never touches the
    ///      shape's edges.
    ///   2. `.padding(.horizontal, topCornerRadius)` on the outer shape
    ///      so the NotchShape's convex top corners have room to curve
    ///      inward without crowding the content.
    ///
    /// Missing both in the first pass was why the preview pills looked
    /// like the content was bleeding into the black mask with no
    /// breathing room.
    private struct LibraryLandingWrapper: ViewModifier {
        let style: LibraryLandingStyle

        // Constants mirror `DynamicNotchStyle.notch` / `.floating`
        // defaults and `NotchView.safeAreaInset` / `NotchlessView.safeAreaInset`.
        // Kept in one place so any future alignment with the library is
        // a single-file change.
        private let notchTopRadius: CGFloat = 15
        private let notchBottomRadius: CGFloat = 20
        private let floatingRadius: CGFloat = 20
        private let insetSides: CGFloat = 15
        private let insetBottom: CGFloat = 15
        /// Simulated "notch head" clearance — the library uses the actual
        /// screen's notch height (≈30pt). Fixed at 26pt here so the
        /// preview has the same visual vocabulary without needing a real
        /// screen to query.
        private let notchHeadInset: CGFloat = 26

        func body(content: Content) -> some View {
            switch style {
            case .notch:
                content
                    // Safe-area insets PUSH the actual content away from
                    // the NotchShape's edges, the same way the library
                    // does. Top is taller (notch-head simulation) so the
                    // flat top strip reads as "physical notch area".
                    .padding(.top, notchHeadInset)
                    .padding(.bottom, insetBottom)
                    .padding(.leading, insetSides)
                    .padding(.trailing, insetSides)
                    // Outer horizontal padding = topCornerRadius, giving
                    // the NotchShape's convex top corners room to curve.
                    .padding(.horizontal, notchTopRadius)
                    .background {
                        // `.foregroundStyle(.black)` matches the library,
                        // and `padding(-50)` is the library's trick to
                        // keep the black visible during animation
                        // overshoot — preserved for fidelity.
                        Rectangle()
                            .foregroundStyle(.black)
                            .padding(-50)
                    }
                    .mask {
                        SandboxNotchShape(
                            topCornerRadius: notchTopRadius,
                            bottomCornerRadius: notchBottomRadius
                        )
                    }

            case .floating:
                content
                    .padding(.top, insetSides)
                    .padding(.bottom, insetBottom)
                    .padding(.leading, insetSides)
                    .padding(.trailing, insetSides)
                    .background {
                        // `VisualEffectView(material: .popover)` in the
                        // library — approximated with `.regularMaterial`
                        // for a SwiftUI-only simulation that still reads
                        // as frosted glass in all color schemes.
                        RoundedRectangle(cornerRadius: floatingRadius, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: floatingRadius, style: .continuous)
                                    .strokeBorder(.quaternary, lineWidth: 1)
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: floatingRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            }
        }
    }

    /// Local port of the library's `NotchShape`: flat top edge spanning
    /// full width, convex top corners pinching inward to the body, and
    /// rounded bottom corners. This is the Dynamic Island silhouette.
    private struct SandboxNotchShape: Shape {
        let topCornerRadius: CGFloat
        let bottomCornerRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
                control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
            )
            p.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
                control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
            )
            p.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
                control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
            )
            p.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
            )
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            return p
        }
    }

    /// A stable `Event` for the preview views to render. Delegates to
    /// the shared `Event.preview(status:project:)` factory so the Sandbox
    /// mockup and the real notification fired by the Trigger button are
    /// built from a single source of truth — same title, summary, and
    /// `durationMs`. Drift between preview and trigger is how the "3s"
    /// duration chip ended up missing from the actual pill earlier.
    private var previewEvent: Event {
        .preview(status: previewStatus, project: projectName)
    }

    private var previewAccent: Color { accent(for: previewStatus) }

    private func accent(for status: EventStatus) -> Color {
        switch status {
        case .success: theme.palette.success
        case .error:   theme.palette.error
        case .waiting: theme.palette.waiting
        case .info:    theme.palette.info
        }
    }

    private var previewLabel: String { theme.statusLabel(for: previewStatus) }

    private func shortLabel(for status: EventStatus) -> String {
        switch status {
        case .success: "Complete"
        case .error:   "Error"
        case .waiting: "Waiting"
        case .info:    "Running"
        }
    }
}
