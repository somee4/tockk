import SwiftUI

/// Design 03 · Floating · Compact
///
/// Liquid-glass pill anchored to the top-right corner. Unlike the notch
/// compact, this surface is translucent — it sits over the desktop/app
/// content rather than emerging from hardware, so material + hairline
/// carry the design.
struct FloatingCompactView: View {
    let event: Event
    let pendingCount: Int
    let theme: AppTheme
    var reduceMotion: Bool = false
    var onClose: (() -> Void)? = nil

    @State private var isHovering = false

    private let cornerRadius: CGFloat = 18

    var body: some View {
        HStack(spacing: 10) {
            // Full-height accent stripe (4pt wide) on the left edge.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(theme.statusColor(for: event.status))
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(event.agent)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                    Text(primaryMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 8) {
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
            .frame(maxWidth: 260, alignment: .leading)

            Spacer(minLength: 0)

            // Right-side status glyph. The left bar carries peripheral
            // signal, this carries focal signal — and the shape of the
            // focal glyph differs per theme (dot / prompt+dot / TockkMark).
            BrandGlyphView(
                glyph: theme.brandGlyph,
                tint: theme.statusColor(for: event.status)
            )

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(theme.textPrimary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Close")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 260)
        .background(theme.pillBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.pillBorderColor, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
        .arrivalEffect(
            tint: theme.statusColor(for: event.status),
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            motion: theme.motion,
            isDisabled: reduceMotion
        )
        .forcedColorScheme(theme.forcedColorScheme)
        // 큐 연속 dismiss 시 새 뷰가 마운트될 때 마우스가 이미 위에 있으면
        // 일반 `.onHover`는 fire되지 않아 × 버튼 hit-test가 막힌다.
        // `.onContinuousHover`는 마운트 시점 상태도 반영한다.
        .onContinuousHover { phase in
            switch phase {
            case .active: isHovering = true
            case .ended: isHovering = false
            }
        }
    }

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

#Preview {
    VStack(spacing: 16) {
        FloatingCompactView(
            event: Event(
                agent: "claude-code",
                project: "tockk",
                status: .success,
                title: "Build complete",
                summary: "56 tests, 0 failures",
                durationMs: 3_200
            ),
            pendingCount: 0,
            theme: AppTheme(preset: .developerTool)
        )
        FloatingCompactView(
            event: Event(
                agent: "codex",
                project: "site",
                status: .error,
                title: "Tests failed",
                durationMs: 12_000
            ),
            pendingCount: 1,
            theme: AppTheme(preset: .developerTool)
        )
    }
    .padding(40)
    .frame(width: 480)
    .background(
        LinearGradient(colors: [.orange.opacity(0.4), .purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    )
}
