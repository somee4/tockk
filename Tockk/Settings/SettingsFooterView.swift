import AppKit
import SwiftUI

struct SettingsFooterView: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Tockk v\(versionString)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                linkButton(
                    url: SettingsLinks.site,
                    systemName: "globe",
                    tooltip: "Open Tockk website"
                )
                linkButton(
                    url: SettingsLinks.github,
                    systemName: "chevron.left.forwardslash.chevron.right",
                    tooltip: "Open GitHub repository"
                )
                linkButton(
                    url: SettingsLinks.sponsor,
                    systemName: "cup.and.saucer.fill",
                    tooltip: "Support on Ko-fi"
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(.ultraThinMaterial)
    }

    private func linkButton(url: URL, systemName: String, tooltip: String) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tooltip)
        .help(tooltip)
    }

    private var versionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }
}

#Preview { SettingsFooterView().frame(width: 560) }
