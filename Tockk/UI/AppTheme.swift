import SwiftUI

enum AppThemePreset: String, CaseIterable, Identifiable, Codable {
    case practicalUtility
    case developerTool
    case smallProduct

    // developerTool is Tockk's point of view — the terminal-inflected
    // aesthetic that matches its audience (Claude Code / Codex users).
    // practicalUtility and smallProduct remain available as alternate
    // moods, but the product speaks through developerTool first.
    static let defaultValue: Self = .developerTool

    var id: String { rawValue }
}

/// The status glyph slot in compact surfaces. Each preset picks one so the
/// "first thing your eye lands on" differs by theme.
enum BrandGlyph: Equatable {
    /// Plain colored status dot. Used by practicalUtility — no ornament.
    case dot
    /// `>` prompt glyph + colored dot. Used by developerTool to read as terminal.
    case promptAndDot
    /// Two-dot Tockk brand mark tinted with the status color. Used by
    /// smallProduct so the "똑" brand lands on every notification.
    case tockkMark
}

struct AppTheme {
    // MARK: - Design Tokens

    /// Typography tokens. Korean-friendly content uses SF Pro; Latin-only
    /// content (agent names, durations, status codes, counters) uses SF Mono
    /// to reinforce the terminal aesthetic without breaking 한글 rendering.
    struct Typography {
        let title: Font           // 이벤트 제목 (한글/Latin 혼용)
        let summary: Font         // 요약 본문
        let projectName: Font     // 프로젝트명 (한글/Latin 혼용)
        let agentName: Font       // 에이전트명 (Latin 전용 → Mono)
        let compactTitle: Font    // Compact 상태 주 텍스트
        let compactDuration: Font // duration (숫자 → Mono)
        let statusLabel: Font     // PASS/FAIL/Queued (Latin → Mono + tracking)
        let statusLabelTracking: CGFloat
        let badge: Font           // +N 뱃지 (숫자 → Mono)

        // Pushed toward an editorial feel: title larger and tighter, meta
        // elements treated as micro-labels with pronounced tracking so the
        // type system reads as "intentional," not default SwiftUI.
        static let developerTool = Typography(
            title: .system(size: 17, weight: .semibold, design: .rounded),
            summary: .system(size: 12),
            projectName: .system(size: 11, weight: .semibold),
            agentName: .system(size: 10, design: .monospaced),
            compactTitle: .system(size: 13, weight: .semibold),
            compactDuration: .system(size: 10, weight: .medium, design: .monospaced),
            statusLabel: .system(size: 10, weight: .semibold, design: .monospaced),
            // Wider tracking turns PASS/FAIL/LOG into a micro-signature that
            // balances the more assertive title.
            statusLabelTracking: 1.4,
            badge: .system(size: 10, weight: .bold, design: .monospaced)
        )

        // Quiet mood — no mono, no tracking, no type theatre. Matches the
        // visual register of a system notification. Meta text is .medium so
        // it stays readable against glass without leaning loud.
        static let practicalUtility = Typography(
            title: .system(size: 17, weight: .semibold),
            summary: .system(size: 12),
            projectName: .system(size: 11, weight: .semibold),
            agentName: .system(size: 10, weight: .medium),
            compactTitle: .system(size: 13, weight: .semibold),
            compactDuration: .system(size: 10, weight: .medium),
            statusLabel: .system(size: 10, weight: .semibold),
            statusLabelTracking: 0,
            badge: .system(size: 10, weight: .bold)
        )

        // Playful mood — rounded throughout so the pill reads as soft and
        // friendly, with Korean onomatopoeia labels that don't need tracking.
        static let smallProduct = Typography(
            title: .system(size: 17, weight: .semibold, design: .rounded),
            summary: .system(size: 12, design: .rounded),
            projectName: .system(size: 11, weight: .semibold, design: .rounded),
            agentName: .system(size: 10, design: .rounded),
            compactTitle: .system(size: 13, weight: .semibold, design: .rounded),
            compactDuration: .system(size: 10, weight: .medium, design: .rounded),
            statusLabel: .system(size: 11, weight: .semibold, design: .rounded),
            statusLabelTracking: 0,
            badge: .system(size: 10, weight: .bold, design: .rounded)
        )
    }

    /// Status palette. Each preset expresses the terminal color identity at a
    /// different intensity:
    ///   • developerTool → full-saturation neon (cyan/amber/red)
    ///   • practicalUtility → system-native defaults (quiet desktop feel)
    ///   • smallProduct → softened pastels that still read as "signal"
    struct StatusPalette {
        let success: Color
        let error: Color
        let waiting: Color
        let info: Color
    }

    /// Motion tokens. Kept here so animation parameters live next to the
    /// visual tokens they modulate; the view layer only reads these constants.
    ///
    /// 모든 테마는 동일한 pulse 모션을 공유한다 — 이벤트 도착이라는 신호는
    /// 시각적 질감과 분리된 "일관된 언어"여야 사용자가 테마 변경으로 학습을
    /// 다시 하지 않는다.
    struct Motion {
        /// Seconds the pulse takes to fade from full to zero.
        let pulseDuration: TimeInterval
        /// Starting intensity multiplier (applied to glow opacity).
        let pulseInitialIntensity: Double
        /// Peak glow stroke opacity (at pulseIntensity == 1).
        let pulseGlowOpacity: Double
        /// Peak shadow halo opacity (at pulseIntensity == 1).
        let pulseShadowOpacity: Double
        /// Halo shadow radius — how far the glow bleeds.
        let pulseShadowRadius: CGFloat

        // Tuned so the border breathes noticeably in peripheral vision — the
        // pulse is the shared "new event" signal across every theme, so the
        // intensity is pushed past the earlier one-shot values (it has to
        // read as motion, not a tint change) but still stays compositor-only
        // (opacity + shadow) to keep the loop cheap.
        static let pulse = Motion(
            pulseDuration: 1.1,
            pulseInitialIntensity: 1.0,
            pulseGlowOpacity: 0.85,
            pulseShadowOpacity: 0.45,
            pulseShadowRadius: 26
        )
    }

    // MARK: - Static Properties

    let preset: AppThemePreset
    let displayName: String
    let previewTitle: String
    let previewSubtitle: String
    let badgeBackgroundName: String
    let menuBarSymbolName: String
    let appMenuTitle: String
    let recentEventsTitle: String
    let emptyRecentEventsTitle: String
    let accentColor: Color
    let panelMaterial: Material
    let typography: Typography
    let palette: StatusPalette
    let motion: Motion
    /// Hairline border color painted on top of the panel material.
    let borderColor: Color
    /// Background painted behind the pill. `AnyShapeStyle` so presets can
    /// supply a Material, a solid Color, or a gradient interchangeably.
    let pillBackground: AnyShapeStyle
    /// Hairline border painted on top of the pill background.
    let pillBorderColor: Color
    /// Whether to overlay CRT scanlines on pill surfaces.
    let showsScanlines: Bool
    /// Whether the status label text is rendered uppercase.
    let statusLabelUppercased: Bool
    /// Status glyph slot for compact surfaces.
    let brandGlyph: BrandGlyph
    /// Color scheme to pin the pill to, if any. Needed when the pill's
    /// background brightness diverges from the system appearance. Kept as a
    /// secondary safety net — primary text color control now lives in the
    /// textPrimary/Secondary/Tertiary tokens below, since macOS's .primary
    /// style can resolve against the window appearance instead of the
    /// environment scheme in some contexts.
    let forcedColorScheme: ColorScheme?

    /// Foreground color for the dominant text layer (titles, primary copy).
    /// Each preset owns this explicitly so text contrast never depends on
    /// the ambient color scheme resolving correctly — solid-black and cream
    /// pills both need fixed values, not `.primary`.
    let textPrimary: Color
    /// Foreground for meta text (agent name, duration, timestamps).
    let textSecondary: Color
    /// Foreground for the quietest layer (dividers, interstitial glyphs).
    let textTertiary: Color

    init(preset: AppThemePreset) {
        self.preset = preset

        // 이벤트 도착 피드백은 테마와 무관하게 pulse로 통일한다.
        // 테마는 색/타이포/표면 질감으로 차별화되고, 모션은 공통 언어를 유지해
        // "새 이벤트가 들어왔다"는 신호가 항상 같은 방식으로 읽히게 한다.
        self.motion = .pulse

        switch preset {
        case .practicalUtility:
            self.typography = .practicalUtility
        case .developerTool:
            self.typography = .developerTool
        case .smallProduct:
            self.typography = .smallProduct
        }

        switch preset {
        case .practicalUtility:
            displayName = "Practical Utility"
            previewTitle = "Native and clear"
            // Preview subtitle is shown as a row hint in the Appearance tab's
            // theme picker. Keeps it concrete and Korean-first to match the
            // rest of the Settings copy and describe what the user will
            // *actually see* (material, contrast, label casing) rather than
            // mood words.
            previewSubtitle = String(localized: "Glass feel close to macOS's default notifications. Standard and quiet.")
            badgeBackgroundName = "glass-neutral"
            menuBarSymbolName = "bell.badge"
            appMenuTitle = "Tockk"
            recentEventsTitle = "Recent Notifications"
            emptyRecentEventsTitle = "No recent notifications"
            accentColor = .accentColor
            panelMaterial = .regularMaterial
            borderColor = Color.primary.opacity(0.06)
            pillBackground = AnyShapeStyle(.regularMaterial)
            pillBorderColor = Color.primary.opacity(0.06)
            showsScanlines = false
            statusLabelUppercased = false
            brandGlyph = .dot
            forcedColorScheme = nil
            // Practical is the only preset that actually wants system-adaptive
            // text: macOS glass reads against whatever is behind it. `.primary`
            // bridges to `NSColor.labelColor` which adapts with the window.
            textPrimary = Color.primary
            textSecondary = Color.primary.opacity(0.7)
            textTertiary = Color.primary.opacity(0.45)
            palette = StatusPalette(
                success: .green,
                error: .red,
                waiting: .orange,
                info: .accentColor
            )
        case .developerTool:
            displayName = "Developer Tool"
            previewTitle = "Dense and technical"
            previewSubtitle = String(localized: "Dark surface with mint-teal accents. Uppercase labels like PASS/FAIL.")
            badgeBackgroundName = "terminal-contrast"
            menuBarSymbolName = "terminal"
            appMenuTitle = "Tockk Agent Feed"
            recentEventsTitle = "Recent Agent Events"
            emptyRecentEventsTitle = "No recent agent events"
            // Signature color — a warm minty teal that reads as "terminal
            // green" from far away but feels hand-picked up close. Different
            // from both SF Symbol system green and default terminal colors.
            accentColor = Color(red: 0.37, green: 0.82, blue: 0.65)
            panelMaterial = .ultraThinMaterial
            borderColor = Color.white.opacity(0.08)
            // Solid near-black pill — developerTool's signature surface.
            pillBackground = AnyShapeStyle(Color(red: 0.039, green: 0.039, blue: 0.043))
            pillBorderColor = Color.white.opacity(0.04)
            showsScanlines = true
            statusLabelUppercased = true
            brandGlyph = .promptAndDot
            forcedColorScheme = .dark
            // Fixed white-on-black text — independent of system appearance.
            textPrimary = Color.white
            textSecondary = Color.white.opacity(0.68)
            textTertiary = Color.white.opacity(0.42)
            // Commit to a named palette instead of standard status colors:
            //   success — warm minty teal (#5ED1A6)
            //   error   — dusty coral, assertive but not alarmist (#DB7A73)
            //   waiting — antique amber, softer than raw orange (#E8B568)
            //   info    — dusty azure, a quieter cyan (#6FB5DF)
            // The throughline: every swatch looks like it was mixed, not
            // pulled from `.systemGreen` etc. This is Tockk's color voice.
            palette = StatusPalette(
                success: Color(red: 0.37, green: 0.82, blue: 0.65),   // warm minty teal
                error: Color(red: 0.86, green: 0.48, blue: 0.45),     // dusty coral
                waiting: Color(red: 0.91, green: 0.71, blue: 0.41),   // antique amber
                info: Color(red: 0.44, green: 0.71, blue: 0.87)       // dusty azure
            )
        case .smallProduct:
            displayName = "Small Product"
            previewTitle = "Warm and branded"
            previewSubtitle = String(localized: "Warm cream pill and rounded type. Friendly labels like 'Tock!'.")
            badgeBackgroundName = "warm-brand"
            menuBarSymbolName = "sparkles"
            appMenuTitle = "Tockk"
            recentEventsTitle = String(localized: "Tock, recent alerts")
            emptyRecentEventsTitle = String(localized: "No alerts have arrived yet")
            accentColor = .orange
            panelMaterial = .thinMaterial
            borderColor = Color.primary.opacity(0.07)
            // Warm cream → peach gradient. Replaces the dark pill so the
            // smallProduct mood reads as friendly paper, not glass or CRT.
            pillBackground = AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.96, blue: 0.91),   // #FFF4E8
                        Color(red: 1.00, green: 0.89, blue: 0.80)    // #FFE3CC
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            pillBorderColor = Color.orange.opacity(0.18)
            showsScanlines = false
            statusLabelUppercased = false
            brandGlyph = .tockkMark
            // Pin to light scheme so `.primary/.secondary` text resolves to
            // dark values against the cream pill regardless of the system
            // appearance.
            forcedColorScheme = .light
            // Fixed dark-on-cream text — warm-tinted near-black for the
            // primary layer so it feels hand-drawn rather than digital,
            // and deep browns for meta so the cream background reads as
            // one continuous paper surface.
            textPrimary = Color(red: 0.16, green: 0.12, blue: 0.08)          // warm near-black
            textSecondary = Color(red: 0.32, green: 0.22, blue: 0.14).opacity(0.75)
            textTertiary = Color(red: 0.32, green: 0.22, blue: 0.14).opacity(0.50)
            // Saturated warm palette — pastel mints and peaches disappear on
            // cream, so smallProduct uses deeper, hand-mixed hues that still
            // feel friendly but actually register as "signal."
            palette = StatusPalette(
                success: Color(red: 0.18, green: 0.62, blue: 0.48),   // deep mint-teal
                error: Color(red: 0.82, green: 0.28, blue: 0.28),     // deep coral
                waiting: Color(red: 0.85, green: 0.54, blue: 0.14),   // saturated amber
                info: Color(red: 0.88, green: 0.44, blue: 0.10)       // rich orange
            )
        }
    }

    // MARK: - Status Accessors

    func statusColor(for status: EventStatus) -> Color {
        switch status {
        case .success: palette.success
        case .error: palette.error
        case .waiting: palette.waiting
        case .info: palette.info
        }
    }

    /// Translucent variant of the status color. Used for glow halos, fill
    /// washes, and pulse animations so the signal reads at a glance without
    /// overwhelming the panel material.
    func glowColor(for status: EventStatus) -> Color {
        statusColor(for: status).opacity(0.35)
    }

    func statusSymbol(for status: EventStatus) -> String {
        switch status {
        case .success:
            "checkmark.circle.fill"
        case .error:
            "xmark.octagon.fill"
        case .waiting:
            "hourglass.circle.fill"
        case .info:
            "message.fill"
        }
    }

    /// Text or emoji used to render `EventStatus` in non-pill surfaces
    /// (currently: the status-bar Recent Events list). Previously lived in
    /// `AppDelegate`, lifted here so preset-specific presentation stays
    /// co-located with the rest of the theme.
    func statusIcon(for status: EventStatus) -> String {
        if preset == .developerTool {
            switch status {
            case .success: return "PASS"
            case .error:   return "FAIL"
            case .waiting: return "WAIT"
            case .info:    return "INFO"
            }
        }
        switch status {
        case .success: return "✅"
        case .error:   return "❌"
        case .waiting: return "⏳"
        case .info:    return "💬"
        }
    }

    /// Locale used when the status-bar menu formats relative timestamps.
    /// Developer Tool keeps everything in English for visual consistency with
    /// the `PASS/FAIL/...` tokens; other presets follow the system locale.
    var menuLocale: Locale {
        preset == .developerTool ? Locale(identifier: "en_US_POSIX") : .current
    }

    func statusLabel(for status: EventStatus) -> String {
        switch preset {
        case .practicalUtility:
            switch status {
            case .success: "Complete"
            case .error: "Issue"
            case .waiting: "Waiting"
            case .info: "Info"
            }
        case .developerTool:
            switch status {
            case .success: "Pass"
            case .error: "Fail"
            case .waiting: "Queued"
            case .info: "Log"
            }
        case .smallProduct:
            switch status {
            case .success: String(localized: "Tock!")
            case .error: String(localized: "Hmm?")
            case .waiting: String(localized: "Hold on")
            case .info: String(localized: "Note")
            }
        }
    }
}
