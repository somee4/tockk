import SwiftUI

/// Design 04 · Floating · Extended
///
/// Liquid-glass card anchored to the top-right corner. Left edge carries a
/// vertical accent gradient bar, mirroring the notch-extended's header
/// chip but in a softer material idiom. Secondary action is "무시".
struct FloatingExtendedView: View {
    let event: Event
    let theme: AppTheme
    var reduceMotion: Bool = false
    let onClose: () -> Void

    @State private var isHovering = false

    private let cornerRadius: CGFloat = 20

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Accent gradient bar — full height, shifting from solid accent
            // to its translucent soft-tone so the stripe reads as a state
            // ribbon rather than a flat rule.
            LinearGradient(
                colors: [
                    theme.statusColor(for: event.status),
                    theme.statusColor(for: event.status).opacity(0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .frame(width: 4)
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                headerRow
                bodyBlock
                footerRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 380)
        .background(theme.pillBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.pillBorderColor, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 20)
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
            Text("·")
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

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(theme.textPrimary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close")
        }
    }

    private var bodyBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            if let detail = event.summary, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.textTertiary.opacity(0.35))
                .frame(height: 0.5)
                .padding(.top, 2)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                Button(action: onClose) {
                    Text("Ignore")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

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

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m \(s)s"
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}

#Preview {
    VStack(spacing: 20) {
        FloatingExtendedView(
            event: Event(
                agent: "claude-code",
                project: "claude-code",
                status: .success,
                title: "Build complete",
                summary: "56 tests, 0 failures",
                durationMs: 3_200
            ),
            theme: AppTheme(preset: .developerTool),
            onClose: {}
        )

        FloatingExtendedView(
            event: Event(
                agent: "codex",
                project: "tockk",
                status: .error,
                title: "Tests failed",
                summary: "AppSettingsTests · themePresetRoundtrip"
            ),
            theme: AppTheme(preset: .developerTool),
            onClose: {}
        )
    }
    .padding(40)
    .frame(width: 480)
    .background(
        LinearGradient(colors: [.orange.opacity(0.4), .purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
}
