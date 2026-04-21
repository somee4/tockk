import AppKit
import Foundation

/// Renders status-bar "Recent Events" rows. Stateless apart from the cached
/// `RelativeDateTimeFormatter`, which is keyed by locale so the Developer Tool
/// preset (en_US_POSIX) and the default system locale can coexist without
/// re-creating the formatter on every menu rebuild.
struct MenuFeedFormatter {
    /// Max total characters (grapheme clusters) for the left-hand
    /// `project · title` label before middle ellipsis kicks in.
    static let maxLabelChars = 50

    /// Minimum column width (points) before the right-aligned time stops
    /// shifting. The menu expands past this automatically when the label
    /// is longer. Tunable — this value was chosen by eye to balance typical
    /// project+title lengths against the smallest pleasant menu width.
    static let tabStopLocation: CGFloat = 360

    let locale: Locale
    private let relative: RelativeDateTimeFormatter

    init(locale: Locale) {
        self.locale = locale
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = locale
        self.relative = f
    }

    // MARK: - Public

    func relativeTime(for timestamp: Date, now: Date = Date()) -> String {
        relative.localizedString(for: timestamp, relativeTo: now)
    }

    func attributedRow(
        for event: Event,
        theme: AppTheme,
        now: Date = Date()
    ) -> NSAttributedString {
        let icon = theme.statusIcon(for: event.status)
        let rawLabel = "\(icon)  \(event.project) · \(event.title)"
        let label = Self.clampLabel(rawLabel,
                                    icon: icon,
                                    project: event.project,
                                    maxChars: Self.maxLabelChars)
        let time = relativeTime(for: event.timestamp, now: now)

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right,
                      location: Self.tabStopLocation,
                      options: [:])
        ]

        let labelFont = NSFont.menuFont(ofSize: 0)
        let timeFont = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize,
            weight: .regular
        )

        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: label, attributes: [
            .font: labelFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]))
        out.append(NSAttributedString(string: "\t", attributes: [
            .paragraphStyle: paragraph
        ]))
        out.append(NSAttributedString(string: time, attributes: [
            .font: timeFont,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]))
        return out
    }

    // MARK: - Private

    /// Clamps the fully-composed `icon  project · title` string to `maxChars`
    /// grapheme clusters by shortening only the `title` segment — the icon and
    /// project survive intact because they carry the routing signal.
    private static func clampLabel(
        _ raw: String,
        icon: String,
        project: String,
        maxChars: Int
    ) -> String {
        guard raw.count > maxChars else { return raw }

        let prefix = "\(icon)  \(project) · "
        let titleBudget = maxChars - prefix.count
        guard titleBudget >= 2 else {
            // Project alone is already longer than the budget; fall back to a
            // naive middle-ellipsis on the whole string.
            return raw.truncatedMiddle(maxChars: maxChars)
        }
        let title = String(raw.dropFirst(prefix.count))
        return prefix + title.truncatedMiddle(maxChars: titleBudget)
    }
}
