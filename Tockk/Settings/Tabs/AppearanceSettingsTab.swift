import SwiftUI

/// "외관" tab. The design bundle uses the Appearance tab as the primary sell
/// for the Sandbox rail: every change on the left reflects immediately on the
/// right. To preserve that feel we lead with a grid of variant cards that
/// map to Tockk's existing `DefaultExpansionMode` (Compact/Extended), then
/// follow with the theme preset picker and (for future) the screen selection
/// strategy.
struct AppearanceSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(
                "Appearance",
                hint: "The Sandbox on the right updates live as you change settings."
            )

            SectionLabel("Alert style")
            HStack(spacing: 8) {
                variantCard(mode: .compact, title: "Notch · Compact")
                variantCard(mode: .expanded, title: "Notch · Expanded")
            }
            .padding(.bottom, 16)

            SectionLabel("Theme")
            GroupCard {
                ForEach(Array(AppThemePreset.allCases.enumerated()), id: \.element) { _, preset in
                    themeRow(preset: preset)
                }
            }
            .padding(.bottom, 14)

            SectionLabel("Display")
            GroupCard {
                SettingsRow(
                    "Display monitor",
                    hint: "Which display shows alerts when multiple monitors are connected"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.screenSelectionStrategy },
                        set: { settings.screenSelectionStrategy = $0 }
                    )) {
                        ForEach(ScreenSelectionStrategy.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Variant card

    @ViewBuilder
    private func variantCard(mode: DefaultExpansionMode, title: String) -> some View {
        let isSelected = settings.defaultExpansionMode == mode
        Button {
            settings.defaultExpansionMode = mode
        } label: {
            VStack(spacing: 0) {
                variantDiagram(mode: mode)
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .background(Color(red: 0x1A/255, green: 0x1D/255, blue: 0x24/255))
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: SettingsDesign.variantCardRadius - 1,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: SettingsDesign.variantCardRadius - 1
                        )
                    )

                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? SettingsDesign.accentBlue : Color.primary)
                    Spacer()
                    if isSelected {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(SettingsDesign.accentBlue)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
            }
            .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.variantCardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.variantCardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? SettingsDesign.accentBlue : Color.black.opacity(0.1),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.variantCardRadius + 2)
                    .strokeBorder(SettingsDesign.accentBlue.opacity(isSelected ? 0.12 : 0), lineWidth: 4)
            )
        }
        .buttonStyle(.plain)
    }

    /// Mini "desktop + notch" mock rendered inside each variant card. Reads
    /// as a dark bar at the top (menubar stand-in) with the notch pill hanging
    /// off center so the user can compare compact vs. extended silhouettes.
    @ViewBuilder
    private func variantDiagram(mode: DefaultExpansionMode) -> some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(height: 8)
                Spacer()
            }
            switch mode {
            case .compact:
                HStack(spacing: 3) {
                    Circle().fill(Color(red: 34/255, green: 197/255, blue: 94/255))
                        .frame(width: 4, height: 4)
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 30, height: 2)
                }
                .padding(.horizontal, 8)
                .frame(width: 56, height: 16)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                        .fill(Color(white: 0.04))
                )
            case .expanded:
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Circle().fill(Color(red: 34/255, green: 197/255, blue: 94/255))
                            .frame(width: 3, height: 3)
                        Capsule().fill(Color.white.opacity(0.25)).frame(height: 1.5)
                    }
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: 60, height: 5)
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 40, height: 2)
                }
                .padding(6)
                .frame(width: 84, height: 46, alignment: .topLeading)
                .background(
                    UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                        .fill(Color(white: 0.04))
                )
            }
        }
    }

    // MARK: - Theme row

    @ViewBuilder
    private func themeRow(preset: AppThemePreset) -> some View {
        let theme = AppTheme(preset: preset)
        let isSelected = settings.themePreset == preset
        let isRecommended = preset == .defaultValue

        // The whole row is tappable (not just the checkmark) so the hit
        // target matches user expectations from macOS Settings. A plain
        // button avoids the default focus ring while preserving the press
        // feedback that `contentShape` would otherwise strip off.
        Button {
            settings.themePreset = preset
        } label: {
            SettingsRow(theme.displayName, hint: theme.previewSubtitle) {
                HStack(spacing: 8) {
                    if isRecommended {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(theme.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(theme.accentColor.opacity(0.55), lineWidth: 0.8))
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.accentColor : Color.secondary.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
