import SwiftUI

/// Design 01 · Notch · Compact
///
/// Dynamic Island-style dark pill that drops from under the menubar.
/// Layout: [status dot] ["tockk · {title}" / "{LABEL} {duration}"] [+N] [×]
struct CompactNotchView: View {
    let event: Event
    let pendingCount: Int
    let theme: AppTheme
    /// When true, the arrival pulse is suppressed (user-level opt-out on top
    /// of the system `accessibilityReduceMotion` check inside the modifier).
    var reduceMotion: Bool = false
    /// Optional dismiss handler. When provided, a hover-reveal X button and
    /// an ESC shortcut are wired up — essential for persistent residence mode
    /// where the compact pill stays until the user explicitly closes it.
    var onClose: (() -> Void)? = nil
    /// Optional expand handler. When provided, an always-visible chevron.down
    /// button is rendered — the visual affordance symmetric to Expanded's
    /// chevron.up. Without it users had no hint that tapping the pill would
    /// expand it.
    var onExpand: (() -> Void)? = nil

    /// Corner radius matches the design token (22 in the prototype). Expressed
    /// as a constant here because the notch compact is effectively a capsule
    /// that trends toward `height/2`, but a fixed value keeps the shape stable
    /// across short/long content widths.
    private let cornerRadius: CGFloat = 22

    var body: some View {
        HStack(spacing: 12) {
            // Status glyph — chosen per theme so the first thing the user's
            // eye lands on differs by mood (plain dot, terminal prompt + dot,
            // or the Tockk brand mark).
            BrandGlyphView(
                glyph: theme.brandGlyph,
                tint: theme.statusColor(for: event.status)
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(event.agent)
                        .font(theme.typography.agentName)
                        .foregroundStyle(theme.textSecondary)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                    Text(primaryMessage)
                        .font(theme.typography.compactTitle)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 8) {
                    // Status label — uppercase only when the theme opts in
                    // (developerTool's micro-signature).
                    Text(
                        theme.statusLabelUppercased
                            ? theme.statusLabel(for: event.status).uppercased()
                            : theme.statusLabel(for: event.status)
                    )
                        .font(theme.typography.statusLabel)
                        .tracking(theme.typography.statusLabelTracking)
                        .foregroundStyle(theme.statusColor(for: event.status))

                    if let ms = event.durationMs {
                        Text(formatDuration(ms))
                            .font(theme.typography.compactDuration)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            .frame(maxWidth: 320, alignment: .leading)

            Spacer(minLength: 0)

            if pendingCount > 0 {
                Text("+\(pendingCount)")
                    .font(theme.typography.badge)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(theme.accentColor.opacity(0.16), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(theme.accentColor.opacity(0.28), lineWidth: 1)
                    )
            }

            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(theme.textPrimary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand")
                .help("Expand to Expanded")
            }

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(theme.textPrimary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Close")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .frame(minWidth: 300, minHeight: 38)
        // The pill's surface is driven by the theme: developerTool uses a
        // solid near-black so the pill reads as a physical Dynamic Island;
        // practicalUtility uses macOS glass; smallProduct uses a warm cream
        // gradient. All three keep the same capsule silhouette.
        .background(theme.pillBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(theme.pillBorderColor, lineWidth: 0.5)
        )
        .overlay(
            // CRT scanline whisper — gated by theme token.
            Capsule()
                .fill(Color.clear)
                .tockkScanlines(enabled: theme.showsScanlines)
                .clipShape(Capsule())
        )
        .shadow(color: .black.opacity(0.55), radius: 16, y: 12)
        .arrivalEffect(
            tint: theme.statusColor(for: event.status),
            shape: Capsule(),
            motion: theme.motion,
            isDisabled: reduceMotion
        )
        .forcedColorScheme(theme.forcedColorScheme)
    }

    /// Title is the promoted headline (the hook already surfaces the most
    /// meaningful line there). Summary falls through only when no title was
    /// set, which effectively only happens for CLI-sent events that omit it.
    /// The compact slot is single-line, so any stray newlines get flattened
    /// so truncation ellipsis lands where it should.
    private var primaryMessage: String {
        let source = event.title.isEmpty ? (event.summary ?? "") : event.title
        return source.replacingOccurrences(of: "\n", with: " ")
    }

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(s)s"
    }
}

/// Small colored dot used as the compact pill's status glyph.
/// Keeps the running-state pulse local so CompactNotchView stays declarative.
struct StatusDot: View {
    let color: Color
    var size: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.18), lineWidth: 2)
                )
        }
        .frame(width: size, height: size)
    }
}

/// Renders the theme's chosen status glyph in compact surfaces. Keeps the
/// switch over `BrandGlyph` in one place so every compact view (notch,
/// floating) uses the same glyph logic.
struct BrandGlyphView: View {
    let glyph: BrandGlyph
    let tint: Color

    var body: some View {
        switch glyph {
        case .dot:
            StatusDot(color: tint)
        case .promptAndDot:
            HStack(spacing: 6) {
                Text(">")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint.opacity(0.7))
                StatusDot(color: tint)
            }
        case .tockkMark:
            TockkMark(tint: tint, dotSize: 5, spacing: 4)
        }
    }
}

#if DEBUG

private func previewEvent(status: EventStatus) -> Event {
    switch status {
    case .success:
        return Event(
            agent: "claude-code", project: "tockk", status: .success,
            title: "Build complete", summary: "56 tests, 0 failures", durationMs: 3_200
        )
    case .error:
        return Event(
            agent: "codex", project: "somee4", status: .error,
            title: "Tests failed", durationMs: 134_000
        )
    case .waiting:
        return Event(
            agent: "claude-code", project: "tockk", status: .waiting,
            title: "Approval pending", summary: "Confirm before running the next command"
        )
    case .info:
        return Event(
            agent: "custom", project: "site", status: .info,
            title: "Deploy notice", summary: "v0.1.0 tag pushed"
        )
    }
}

#Preview("Notch · dark desktop · success") {
    NotchPreviewBackdrop(wallpaper: .dark) {
        VStack(spacing: 12) {
            ForEach(AppThemePreset.allCases) { preset in
                CompactNotchView(
                    event: previewEvent(status: .success),
                    pendingCount: 0,
                    theme: AppTheme(preset: preset)
                )
            }
        }
    }
    .frame(width: 900, height: 360)
}

#Preview("Notch · light desktop · error") {
    NotchPreviewBackdrop(wallpaper: .light) {
        VStack(spacing: 12) {
            ForEach(AppThemePreset.allCases) { preset in
                CompactNotchView(
                    event: previewEvent(status: .error),
                    pendingCount: 2,
                    theme: AppTheme(preset: preset)
                )
            }
        }
    }
    .frame(width: 900, height: 360)
}

#Preview("Notch · all statuses per preset") {
    NotchPreviewBackdrop(wallpaper: .dark) {
        HStack(alignment: .top, spacing: 24) {
            ForEach(AppThemePreset.allCases) { preset in
                VStack(spacing: 10) {
                    Text(AppTheme(preset: preset).displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    ForEach([EventStatus.success, .error, .waiting, .info], id: \.self) { status in
                        CompactNotchView(
                            event: previewEvent(status: status),
                            pendingCount: 0,
                            theme: AppTheme(preset: preset)
                        )
                    }
                }
            }
        }
        .padding(.top, 12)
    }
    .frame(width: 1100, height: 520)
}

#endif
