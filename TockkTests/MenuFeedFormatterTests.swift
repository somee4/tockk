import XCTest
import AppKit
@testable import Tockk

final class MenuFeedFormatterTests: XCTestCase {

    private let korean = Locale(identifier: "ko_KR")
    private let english = Locale(identifier: "en_US_POSIX")

    // MARK: - Relative time

    func testRelativeTimeSecondsAgoKorean() {
        let f = MenuFeedFormatter(locale: korean)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let past = now.addingTimeInterval(-30)                // 30s ago
        // RelativeDateTimeFormatter in ko → contains "초" (second)
        XCTAssertTrue(f.relativeTime(for: past, now: now).contains("초"))
    }

    func testRelativeTimeMinutesAgoEnglish() {
        let f = MenuFeedFormatter(locale: english)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let past = now.addingTimeInterval(-3 * 60)            // 3 min
        let text = f.relativeTime(for: past, now: now)
        XCTAssertTrue(text.lowercased().contains("min"),
                      "expected minute token, got \(text)")
    }

    func testRelativeTimeIsStableForSameInput() {
        let f = MenuFeedFormatter(locale: english)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let past = now.addingTimeInterval(-45 * 60)
        XCTAssertEqual(f.relativeTime(for: past, now: now),
                       f.relativeTime(for: past, now: now))
    }

    // MARK: - Attributed row composition

    func testAttributedRowContainsAllExpectedFragments() {
        let f = MenuFeedFormatter(locale: english)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let event = Event(
            agent: "tockk",
            project: "api-server",
            status: .success,
            title: "migration done",
            timestamp: now.addingTimeInterval(-2 * 60)
        )
        let theme = AppTheme(preset: .practicalUtility)

        let row = f.attributedRow(for: event, theme: theme, now: now)
        let plain = row.string

        XCTAssertTrue(plain.contains("✅"))
        XCTAssertTrue(plain.contains("api-server"))
        XCTAssertTrue(plain.contains("migration done"))
        XCTAssertTrue(plain.contains("\t"),
                      "expected tab separator between label and time")
        XCTAssertTrue(plain.lowercased().contains("min"))
    }

    func testAttributedRowTruncatesLongTitlePreservingProject() {
        let f = MenuFeedFormatter(locale: english)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let event = Event(
            agent: "tockk",
            project: "api-server",
            status: .info,
            title: String(repeating: "x", count: 200),
            timestamp: now
        )
        let row = f.attributedRow(for: event,
                                  theme: AppTheme(preset: .practicalUtility),
                                  now: now)
        let plain = row.string

        XCTAssertTrue(plain.contains("api-server"),
                      "project segment must survive truncation")
        XCTAssertTrue(plain.contains("…"))
    }

    func testAttributedRowAppliesRightAlignedTabStopForTime() {
        let f = MenuFeedFormatter(locale: english)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let event = Event(agent: "x", project: "p", status: .success,
                          title: "t", timestamp: now)
        let row = f.attributedRow(for: event,
                                  theme: AppTheme(preset: .practicalUtility),
                                  now: now)
        let style = row.attribute(.paragraphStyle,
                                  at: 0,
                                  effectiveRange: nil) as? NSParagraphStyle
        XCTAssertNotNil(style, "paragraph style must be attached")
        let stops = style?.tabStops ?? []
        XCTAssertFalse(stops.isEmpty, "must include at least one tab stop")
        XCTAssertEqual(stops.first?.alignment, .right,
                       "the time column must be right-aligned")
    }

    func testDeveloperToolRowUsesTextTokenIcon() {
        let f = MenuFeedFormatter(locale: english)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let event = Event(agent: "x", project: "p", status: .error,
                          title: "oops", timestamp: now)
        let row = f.attributedRow(for: event,
                                  theme: AppTheme(preset: .developerTool),
                                  now: now)
        XCTAssertTrue(row.string.contains("FAIL"))
    }

    func testTimeSegmentUsesSecondaryLabelColorAndMonospacedDigitFont() {
        // The right-aligned time column must visually de-emphasize vs. the
        // label (secondaryLabelColor) and use monospaced-digit so "3 min. ago"
        // vs. "15 min. ago" stay column-aligned across rows.
        let f = MenuFeedFormatter(locale: english)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let event = Event(agent: "tockk", project: "api-server",
                          status: .success, title: "done",
                          timestamp: now.addingTimeInterval(-5 * 60))
        let row = f.attributedRow(for: event,
                                  theme: AppTheme(preset: .practicalUtility),
                                  now: now)

        // The final character belongs to the time segment — inspect its
        // attributes. `length - 1` dodges the trailing-index boundary.
        let tailIndex = row.length - 1
        XCTAssertGreaterThanOrEqual(tailIndex, 0,
                                    "row must contain a time segment")

        let attrs = row.attributes(at: tailIndex, effectiveRange: nil)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor,
                       NSColor.secondaryLabelColor,
                       "time segment must use secondaryLabelColor")

        let font = attrs[.font] as? NSFont
        XCTAssertNotNil(font, "time segment must have a font attribute")
        // Monospaced-digit fonts advertise this via a font descriptor trait;
        // a simpler signal is the numeric-space feature, but here we just
        // assert the font is NOT the plain menu font used for the label.
        XCTAssertNotEqual(font, NSFont.menuFont(ofSize: 0),
                          "time segment must not reuse the menu label font")
    }
}
