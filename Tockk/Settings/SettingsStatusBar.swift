import SwiftUI

/// The 32pt strip at the top of the Settings window. Answers three questions
/// at a glance without forcing the user into the Integrations tab:
///
///   1. Is the Claude Code hook installed? (`StatusPill`)
///   2. Which project last triggered a notification? (project badge)
///   3. Are my changes being persisted? (auto-save indicator on the right)
///
/// All values are display-only — no settings are mutated from this row. When
/// there is no trigger history yet (fresh install or new session), the
/// status bar collapses the project / time fields into a single muted
/// "아직 트리거 없음" line so we never lie with stale defaults.
struct SettingsStatusBar: View {
    let hookInstalled: Bool
    let projectName: String?
    let lastEventAt: Date?
    let showsSavedHint: Bool

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            SettingsStatusPill(
                label: hookInstalled ? String(localized: "Hook OK") : String(localized: "Hook missing"),
                isOk: hookInstalled
            )

            triggerContext

            Spacer(minLength: 8)

            savedIndicator
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(SettingsDesign.statusBarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsDesign.hairline)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var triggerContext: some View {
        if let projectName, let lastEventAt {
            Text(projectName)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("·")
                .foregroundStyle(Color.black.opacity(0.25))

            Text(String(format: String(localized: "triggered %@"),
                         Self.relativeFormatter.localizedString(for: lastEventAt, relativeTo: Date())))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("No triggers yet")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.35))
                .lineLimit(1)
        }
    }

    private var savedIndicator: some View {
        // Resting state is just a quiet "자동 저장" label — no checkmark, so
        // it reads as a policy note, not a stale confirmation. The moment a
        // change lands we flash the green checkmark + "저장됨" for ~1s; the
        // appearance of the checkmark is what sells the feedback.
        let color: Color = showsSavedHint
            ? Color(red: 34/255, green: 197/255, blue: 94/255)
            : Color.black.opacity(0.35)

        // Ternary of string literals resolves to `String` (verbatim init),
        // bypassing SwiftUI's LocalizedStringKey lookup — so the label is
        // resolved explicitly via `String(localized:)` to keep xcstrings
        // translations applied.
        let label = showsSavedHint
            ? String(localized: "Saved")
            : String(localized: "Auto-saves")

        return HStack(spacing: 5) {
            if showsSavedHint {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(color)
        .animation(.easeOut(duration: 0.2), value: showsSavedHint)
    }
}

#Preview {
    VStack(spacing: 0) {
        SettingsStatusBar(
            hookInstalled: true,
            projectName: "claude-code",
            lastEventAt: Date().addingTimeInterval(-120),
            showsSavedHint: false
        )
        SettingsStatusBar(
            hookInstalled: false,
            projectName: nil,
            lastEventAt: nil,
            showsSavedHint: true
        )
    }
    .frame(width: 900)
    .padding()
}
