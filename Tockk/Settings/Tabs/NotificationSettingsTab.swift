import SwiftUI

/// "알림" tab. Keeps the sound / motion / residence / duration controls that
/// `AppSettings` already exposes, but re-homes them into the new
/// `GroupCard` + `SettingsRow` vocabulary so sectioning matches the rest of
/// the window. The duration slider is given its own full-width row so it
/// doesn't sit cramped next to a label — the original 110pt slider from the
/// prototype was too fiddly to target precisely.
struct NotificationSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("Notifications", hint: "Adjust sound, animation, duration, and other behaviors.")

            SectionLabel("Sound")
            GroupCard {
                SettingsRow("Notification sound") {
                    Toggle("", isOn: $settings.soundEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 14)

            SectionLabel("Motion")
            GroupCard {
                SettingsRow(
                    "Pulse animation",
                    hint: "Pulses the panel border continuously while the alert is visible"
                ) {
                    Toggle("", isOn: $settings.pulseAnimationEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 14)

            SectionLabel("Duration")
            GroupCard {
                SettingsRow("Residence mode", hint: residenceHint) {
                    Picker("", selection: Binding(
                        get: { settings.alertResidenceMode },
                        set: { settings.alertResidenceMode = $0 }
                    )) {
                        ForEach(AlertResidenceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if settings.alertResidenceMode.needsResidenceSeconds {
                    durationSliderRow
                }
            }
        }
    }

    /// A dedicated 2-line row for the seconds slider. The previous layout
    /// used a 110pt slider inside a standard `SettingsRow`, which made
    /// precise seconds impossible to dial in with the mouse. Giving it the
    /// whole row width plus a mono-digit readout makes the control actually
    /// usable, and the vertical stack keeps the label/hint legible.
    private var durationSliderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(residenceSecondsLabel)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(settings.displayDurationSeconds))s")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SettingsDesign.accentBlue)
                    .monospacedDigit()
            }

            Slider(value: $settings.displayDurationSeconds, in: 5...120, step: 1) {
                Text(residenceSecondsLabel)
            } minimumValueLabel: {
                Text("5s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("120s")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .tint(SettingsDesign.accentBlue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsDesign.rowDivider)
                .frame(height: 0.5)
        }
    }

    private var residenceSecondsLabel: String {
        switch settings.alertResidenceMode {
        case .collapseAfter: String(localized: "Until collapse")
        case .dismissAfter: String(localized: "Until dismiss")
        case .persistent: String(localized: "Residence time")
        }
    }

    /// Hint copy pinned to the residence-mode row so the user sees *why*
    /// each mode exists — the mode labels alone aren't self-explanatory.
    private var residenceHint: String {
        switch settings.alertResidenceMode {
        case .persistent:
            String(localized: "Stays until the user dismisses it")
        case .collapseAfter:
            String(localized: "The pill remains after the expanded view collapses")
        case .dismissAfter:
            String(localized: "The notch disappears completely after the set time")
        }
    }
}
