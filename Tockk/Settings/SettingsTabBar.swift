import SwiftUI

/// The settings-window tab bar — a pill-shaped segmented control that
/// replaces the default `TabView` chrome. macOS's built-in style is fine but
/// visually generic; the design calls for a centered pill with icon glyphs
/// and a soft white "selected" lozenge so the window reads as a deliberate
/// product surface rather than a stock preferences pane.

enum SettingsTab: String, CaseIterable, Identifiable, Equatable {
    case general
    case appearance
    case notifications
    case integrations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:       String(localized: "General")
        case .appearance:    String(localized: "Appearance")
        case .notifications: String(localized: "Notifications")
        case .integrations:  String(localized: "Integrations")
        }
    }

    /// SF Symbols chosen to keep the pill bar feeling like a deliberate
    /// product surface rather than a stock preferences pane. "general" uses
    /// sliders (system-behavior knobs) instead of a star, which read as
    /// template-y in the original pass.
    var symbolName: String {
        switch self {
        case .general:       "slider.horizontal.3"
        case .appearance:    "circle.righthalf.filled"
        case .notifications: "bell"
        case .integrations:  "link"
        }
    }
}

struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    PillSegment(
                        tab: tab,
                        isSelected: selection == tab,
                        action: { selection = tab }
                    )
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsDesign.tabTrackFill)
            )
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(SettingsDesign.tabBarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }
}

private struct PillSegment: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(isSelected ? 1 : 0.7)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.62))
            // Padding drives both visual lozenge size *and* the click hit
            // target. The original 13/5 made the tabs feel like tiny chips
            // that were easy to miss with the mouse; bumping to 18/7 keeps
            // the pill look while giving each tab a proper button-sized
            // target (~60×30+). `contentShape(Rectangle())` ensures the
            // padded transparent area around the label is also hit-testable,
            // not just the drawn lozenge bounds.
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .frame(minWidth: 96)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .shadow(color: isSelected ? Color.black.opacity(0.1) : .clear, radius: 1, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            // Show a pointing-hand cursor over the full padded hit area so
            // users get affordance feedback before they click, the way
            // they would on any clickable segmented control.
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

#Preview {
    struct PreviewHost: View {
        @State var sel: SettingsTab = .appearance
        var body: some View {
            SettingsTabBar(selection: $sel)
                .frame(width: 900)
        }
    }
    return PreviewHost()
}
