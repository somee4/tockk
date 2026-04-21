import SwiftUI

/// Shared design primitives for the Tockk settings window.
///
/// The settings window follows the "Direction C" spec from the handoff design
/// bundle: a pill-tabbed, two-column layout with a live Sandbox rail on the
/// right. These primitives (`SettingsRow`, `GroupCard`, `SectionLabel`,
/// `SectionHead`, `StatusPill`, `PillSegment`) are the Swift analogues of the
/// JSX components in `settings-common.jsx` and keep the tab content visually
/// coherent across General / Appearance / Notifications / Integrations.

enum SettingsDesign {
    static let windowWidth: CGFloat = 900
    static let windowHeight: CGFloat = 620
    static let sandboxWidth: CGFloat = 320
    static let contentPadding = EdgeInsets(top: 20, leading: 22, bottom: 20, trailing: 22)

    static let rowMinHeight: CGFloat = 44
    static let groupCardRadius: CGFloat = 10
    static let variantCardRadius: CGFloat = 10

    /// The "blue" accent used throughout macOS settings prominence affordances
    /// (selected variant card outline, primary CTA). Mirrors the `#0a84ff`
    /// constant used in the prototype.
    static let accentBlue = Color(red: 10.0/255, green: 132.0/255, blue: 255.0/255)

    /// Top status bar background — a single near-white fill that sits above
    /// the content to separate the "meta" row (hook status, auto-save) from
    /// the tabs below.
    static let statusBarBackground = Color(red: 0xEB/255.0, green: 0xEB/255.0, blue: 0xEF/255.0)

    static let hairline = Color.black.opacity(0.08)
    static let rowDivider = Color.black.opacity(0.06)
    static let groupCardFill = Color(nsColor: .textBackgroundColor)
    static let groupCardBorder = Color.black.opacity(0.08)

    static let sectionLabelColor = Color.black.opacity(0.45)
    static let rowHintColor = Color.black.opacity(0.52)

    static let tabBarBackground = Color(red: 0xF5/255.0, green: 0xF5/255.0, blue: 0xF7/255.0)
    static let tabTrackFill = Color(white: 120.0/255.0).opacity(0.14)
}

// MARK: - Section Header

/// A title + hint pair rendered at the top of a tab's scroll content.
struct SectionHead: View {
    let title: String
    let hint: String?

    init(_ title: String, hint: String? = nil) {
        self.title = title
        self.hint = hint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 19, weight: .bold))
                .kerning(-0.3)
            if let hint {
                Text(LocalizedStringKey(hint))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesign.rowHintColor)
            }
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section Label

/// The uppercase "group header" that sits above a `GroupCard`. Written in
/// ALL CAPS with tight tracking to read as a micro-label.
struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(LocalizedStringKey(text))
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(SettingsDesign.sectionLabelColor)
            .padding(.horizontal, 2)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Group Card

/// A bordered white surface that groups related `SettingsRow` items.
/// Children are laid out vertically; the card draws its own shell.
struct GroupCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(SettingsDesign.groupCardFill)
            .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.groupCardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.groupCardRadius, style: .continuous)
                    .strokeBorder(SettingsDesign.groupCardBorder, lineWidth: 0.5)
            )
    }
}

// MARK: - Settings Row

/// A label/hint/control triplet rendered inside a `GroupCard`. Uses a hairline
/// bottom divider so adjacent rows visually separate without needing an
/// explicit `Divider`. The last row's divider is painted too — that's fine
/// because the card's clip mask hides the overflow.
struct SettingsRow<Trailing: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ label: String, hint: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.hint = hint
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label))
                    .font(.system(size: 13, weight: .medium))
                if let hint {
                    Text(LocalizedStringKey(hint))
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsDesign.rowHintColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: SettingsDesign.rowMinHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SettingsDesign.rowDivider)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Status Pill

/// A colored capsule used to surface hook install status in the top status
/// bar and in the Integrations tab. Green = connected, amber = not installed.
struct SettingsStatusPill: View {
    let label: String
    let isOk: Bool

    var body: some View {
        let color: Color = isOk ? Color(red: 34/255, green: 197/255, blue: 94/255)
                                 : Color(red: 245/255, green: 158/255, blue: 11/255)
        let fill = color.opacity(0.12)

        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(LocalizedStringKey(label))
                .textCase(.uppercase)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(Capsule().fill(fill))
    }
}
