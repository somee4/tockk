import AppKit
import SwiftUI

/// "General" tab content.
///
/// Only exposes what actually exists in `AppSettings`. The design mock has
/// extra rows (Dock hiding, update cadence, time format) that the current app
/// doesn't implement yet — those are intentionally left out of this view so
/// the UI never lies about what the product can actually do.
struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    /// Captures the language the window was opened with so we can detect the
    /// user changing it mid-session and show a "relaunch to apply" notice.
    /// `AppleLanguages` is read by `NSBundle` at process start, so there's no
    /// way to hot-swap — the notice is the honest answer.
    @State private var initialLanguage: AppLanguage = .defaultValue
    @State private var showsRelaunchNotice: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("General", hint: "How tockk behaves in your system.")

            SectionLabel("Launch")
            GroupCard {
                SettingsRow(
                    "Launch at login",
                    hint: "Runs in the background after reboot"
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLoginEnabled },
                        set: { settings.updateLaunchAtLoginEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            .padding(.bottom, 14)

            SectionLabel("Language")
            GroupCard {
                SettingsRow(
                    "Interface language",
                    hint: "Applies on next launch"
                ) {
                    Picker("", selection: Binding(
                        get: { settings.preferredLanguage },
                        set: { newValue in
                            settings.preferredLanguage = newValue
                            showsRelaunchNotice = (newValue != initialLanguage)
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
            }

            if showsRelaunchNotice {
                relaunchNotice
                    .padding(.top, 8)
            }
        }
        .onAppear {
            settings.refreshLaunchAtLoginState()
            initialLanguage = settings.preferredLanguage
        }
    }

    private var relaunchNotice: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
                .foregroundStyle(SettingsDesign.accentBlue)

            Text("Relaunch required — quit and reopen Tockk to apply")
                .font(.system(size: 11.5))
                .foregroundStyle(SettingsDesign.rowHintColor)

            Spacer(minLength: 8)

            Button(action: relaunch) {
                Text("Relaunch")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(SettingsDesign.accentBlue)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: SettingsDesign.groupCardRadius, style: .continuous)
                .fill(SettingsDesign.accentBlue.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsDesign.groupCardRadius, style: .continuous)
                .strokeBorder(SettingsDesign.accentBlue.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Relaunches the app cleanly: spawns a detached copy via `open` and
    /// terminates the current process once the new one has started. Avoids
    /// `NSApp.terminate` races where the old process exits before the shell
    /// inherits argv, which can leave the Dock without an app icon briefly.
    private func relaunch() {
        guard let bundlePath = Bundle.main.bundleURL.path as String? else {
            NSApp.terminate(nil)
            return
        }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        do {
            try task.run()
        } catch {
            NSApp.terminate(nil)
            return
        }
        NSApp.terminate(nil)
    }
}
