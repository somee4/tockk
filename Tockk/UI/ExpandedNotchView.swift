import SwiftUI

/// Design 02 · Notch · Extended
///
/// Wider solid-dark panel that drops from under the menubar. Structure:
///   Header : [dot] tockk / {project}         [LABEL] [×]
///   Body   : {message (19pt bold)}
///            {detail (mono, sub)}
///   Footer : {duration} · {time}
struct ExpandedNotchView: View {
    let event: Event
    let theme: AppTheme
    /// When true, the arrival pulse is suppressed (user-level opt-out on top
    /// of the system `accessibilityReduceMotion` check inside the modifier).
    var reduceMotion: Bool = false
    let onClose: () -> Void
    /// Optional collapse handler. When provided, the header shows a fold
    /// button between the LABEL chip and the close X. `nil` hides the
    /// button — used by contexts that can't express a compact form.
    var onCollapse: (() -> Void)? = nil

    @State private var isHovering = false

    private let cornerRadius: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            bodyBlock
            footerRow
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(width: 460)
        .background(
            theme.pillBackground,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.pillBorderColor, lineWidth: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .tockkScanlines(enabled: theme.showsScanlines)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        )
        .shadow(color: .black.opacity(0.6), radius: 24, y: 20)
        .arrivalEffect(
            tint: theme.statusColor(for: event.status),
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            motion: theme.motion,
            isDisabled: reduceMotion
        )
        .forcedColorScheme(theme.forcedColorScheme)
        .onHover { isHovering = $0 }
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 8) {
            BrandGlyphView(
                glyph: theme.brandGlyph,
                tint: theme.statusColor(for: event.status)
            )
            Text(event.agent)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
            Text("/")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
            Text(event.project)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(
                theme.statusLabelUppercased
                    ? theme.statusLabel(for: event.status).uppercased()
                    : theme.statusLabel(for: event.status)
            )
                .font(theme.typography.statusLabel)
                .tracking(theme.typography.statusLabelTracking)
                .foregroundStyle(theme.statusColor(for: event.status))

            if let onCollapse {
                Button(action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(theme.textTertiary.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse")
                .help("Collapse to Compact")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(theme.textTertiary.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close")
        }
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            if let detail = event.summary, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.textTertiary.opacity(0.25))
                .frame(height: 0.5)
                .padding(.top, 2)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                if let ms = event.durationMs {
                    Text(formatDuration(ms))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(theme.textSecondary)
                    Text("·")
                        .foregroundStyle(theme.textTertiary)
                }
                Text(relativeTime(from: event.timestamp))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(theme.textSecondary)
                    .textCase(.uppercase)
            }
        }
    }

    // MARK: - Styling

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(s)s"
    }

    /// Very coarse "time ago" for the footer meta slot — the notification is
    /// almost always shown within seconds of the event, so `just now` is the
    /// dominant case. Keeps the mono meta tight.
    private func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

#if DEBUG

#Preview("Expanded · all presets · success") {
    VStack(spacing: 20) {
        ForEach(AppThemePreset.allCases) { preset in
            ExpandedNotchView(
                event: Event(
                    agent: "claude-code",
                    project: "tockk",
                    status: .success,
                    title: "Build complete",
                    summary: "56 tests, 0 failures",
                    durationMs: 3_200,
                    cwd: "/Users/yonghui/yonProject/site"
                ),
                theme: AppTheme(preset: preset),
                onClose: {}
            )
        }
    }
    .padding(40)
    .background(
        LinearGradient(
            colors: [
                Color(red: 0.14, green: 0.12, blue: 0.18),
                Color(red: 0.22, green: 0.20, blue: 0.28)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

#Preview("Expanded · all presets · error") {
    VStack(spacing: 20) {
        ForEach(AppThemePreset.allCases) { preset in
            ExpandedNotchView(
                event: Event(
                    agent: "codex",
                    project: "tockk",
                    status: .error,
                    title: "Tests failed",
                    summary: "AppSettingsTests · themePresetRoundtrip"
                ),
                theme: AppTheme(preset: preset),
                onClose: {}
            )
        }
    }
    .padding(40)
    .background(
        LinearGradient(
            colors: [
                Color(red: 0.85, green: 0.80, blue: 0.72),
                Color(red: 0.72, green: 0.78, blue: 0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

#endif
