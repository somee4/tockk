import AppKit
import SwiftUI
import XCTest
@testable import Tockk

final class AppThemeTests: XCTestCase {
    func testDeveloperToolIsDefaultPresetToCommitToPointOfView() {
        // Tockk's product POV is the terminal-inflected developerTool
        // aesthetic. Splitting attention equally across three presets reads
        // as "no opinion" — defaulting new installs to developerTool pins
        // the first impression to the brand voice we want users to remember.
        XCTAssertEqual(AppThemePreset.defaultValue, .developerTool)
    }

    func testEveryPresetExposesPreviewDescription() {
        for preset in AppThemePreset.allCases {
            let theme = AppTheme(preset: preset)

            XCTAssertFalse(theme.previewTitle.isEmpty)
            XCTAssertFalse(theme.previewSubtitle.isEmpty)
        }
    }

    func testEachPresetProducesDistinctThemeName() {
        XCTAssertEqual(AppTheme(preset: .practicalUtility).displayName, "Practical Utility")
        XCTAssertEqual(AppTheme(preset: .developerTool).displayName, "Developer Tool")
        XCTAssertEqual(AppTheme(preset: .smallProduct).displayName, "Small Product")
    }

    func testDeveloperToolUsesHigherContrastThanPracticalUtility() {
        let practical = AppTheme(preset: .practicalUtility)
        let developer = AppTheme(preset: .developerTool)

        XCTAssertNotEqual(practical.badgeBackgroundName, developer.badgeBackgroundName)
    }

    func testSmallProductUsesFriendlyMenuSectionTitle() {
        XCTAssertEqual(
            AppTheme(preset: .smallProduct).recentEventsTitle,
            String(localized: "Tock, recent alerts")
        )
    }

    func testDeveloperToolUsesTechnicalMenuSectionTitle() {
        XCTAssertEqual(AppTheme(preset: .developerTool).recentEventsTitle, "Recent Agent Events")
    }

    // MARK: - Design Tokens

    func testEveryPresetExposesTypographyTokens() {
        for preset in AppThemePreset.allCases {
            let theme = AppTheme(preset: preset)
            XCTAssertGreaterThanOrEqual(theme.typography.statusLabelTracking, 0)
        }
    }

    // MARK: - Typography per preset

    func testPracticalUtilityDropsTrackingForQuietVoice() {
        // The quiet mood asks for neutral Latin typography — no uppercase
        // tracking theatre. Practical must keep tracking at 0.
        XCTAssertEqual(AppTheme(preset: .practicalUtility).typography.statusLabelTracking, 0)
    }

    func testDeveloperToolKeepsWideTrackingForMicroSignal() {
        XCTAssertEqual(AppTheme(preset: .developerTool).typography.statusLabelTracking, 1.4)
    }

    func testSmallProductDropsTrackingForFriendlyVoice() {
        XCTAssertEqual(AppTheme(preset: .smallProduct).typography.statusLabelTracking, 0)
    }

    func testEveryPresetExposesDistinctStatusPalette() {
        for preset in AppThemePreset.allCases {
            let theme = AppTheme(preset: preset)

            XCTAssertNotEqual(
                theme.statusColor(for: .success),
                theme.statusColor(for: .error),
                "Preset \(preset) must distinguish success from error at a glance"
            )
            XCTAssertNotEqual(
                theme.statusColor(for: .success),
                theme.statusColor(for: .waiting),
                "Preset \(preset) must distinguish success from waiting"
            )
        }
    }

    func testGlowColorIsTranslucentRelativeToStatusColor() {
        // The glow token is used for halo/pulse effects. It must read as a
        // softened version of the status color — same hue, lower opacity.
        // Bridging to NSColor is the stable way to inspect alpha on macOS.
        let theme = AppTheme(preset: .developerTool)

        for status in [EventStatus.success, .error, .waiting, .info] {
            let base = NSColor(theme.statusColor(for: status))
                .usingColorSpace(.sRGB)
            let glow = NSColor(theme.glowColor(for: status))
                .usingColorSpace(.sRGB)

            guard let base, let glow else {
                XCTFail("Expected sRGB representations to exist for \(status)")
                continue
            }

            XCTAssertLessThan(
                glow.alphaComponent,
                base.alphaComponent,
                "glowColor(\(status)) must have lower alpha than statusColor"
            )
            XCTAssertLessThan(
                glow.alphaComponent,
                1.0,
                "glowColor(\(status)) must be translucent"
            )
        }
    }

    func testBorderColorIsExposedForAllPresets() {
        for preset in AppThemePreset.allCases {
            let theme = AppTheme(preset: preset)
            // Just confirm the token exists; actual hairline rendering is visual.
            _ = theme.borderColor
        }
    }

    // MARK: - Motion Tokens

    func testMotionTokensAreWithinSensibleRanges() {
        // The pulse is a "catch the user" signal, not a distraction. These
        // assertions codify the design commitment that it must read as a
        // single confident flash, not a strobe.
        let motion = AppTheme.Motion.pulse

        XCTAssertGreaterThan(motion.pulseDuration, 0.3,
            "Pulse shorter than 0.3s reads as a glitch")
        XCTAssertLessThan(motion.pulseDuration, 1.5,
            "Pulse longer than 1.5s overstays the attention window")

        XCTAssertEqual(motion.pulseInitialIntensity, 1.0,
            "Pulse must start at full intensity so the peak is obvious")

        XCTAssertGreaterThan(motion.pulseGlowOpacity, 0,
            "Glow opacity must be positive to be visible")
        XCTAssertLessThanOrEqual(motion.pulseGlowOpacity, 1.0)

        XCTAssertGreaterThan(motion.pulseShadowRadius, 0,
            "Shadow radius must be positive to create a halo")
    }

    func testAllPresetsShareTheSamePulseMotion() {
        // 이벤트 도착 신호는 테마와 무관하게 동일한 언어(pulse)로 읽혀야
        // 사용자가 테마 전환 시 "새 알림" 신호를 다시 학습하지 않는다.
        let motions = AppThemePreset.allCases.map { AppTheme(preset: $0).motion }
        for m in motions {
            XCTAssertEqual(m.pulseDuration, AppTheme.Motion.pulse.pulseDuration)
            XCTAssertEqual(m.pulseGlowOpacity, AppTheme.Motion.pulse.pulseGlowOpacity)
            XCTAssertEqual(m.pulseShadowRadius, AppTheme.Motion.pulse.pulseShadowRadius)
        }
    }

    // MARK: - Pill tokens

    func testOnlyDeveloperToolShowsScanlines() {
        XCTAssertTrue(AppTheme(preset: .developerTool).showsScanlines)
        XCTAssertFalse(AppTheme(preset: .practicalUtility).showsScanlines)
        XCTAssertFalse(AppTheme(preset: .smallProduct).showsScanlines)
    }

    func testOnlyDeveloperToolUppercasesStatusLabel() {
        XCTAssertTrue(AppTheme(preset: .developerTool).statusLabelUppercased)
        XCTAssertFalse(AppTheme(preset: .practicalUtility).statusLabelUppercased)
        XCTAssertFalse(AppTheme(preset: .smallProduct).statusLabelUppercased)
    }

    func testEveryPresetExposesBrandGlyph() {
        XCTAssertEqual(AppTheme(preset: .practicalUtility).brandGlyph, .dot)
        XCTAssertEqual(AppTheme(preset: .developerTool).brandGlyph, .promptAndDot)
        XCTAssertEqual(AppTheme(preset: .smallProduct).brandGlyph, .tockkMark)
    }

    func testForcedColorSchemePerPreset() {
        // developerTool pins .dark (light text on solid-black pill);
        // smallProduct pins .light (dark text on cream pill);
        // practicalUtility follows system (adaptive glass reads both ways).
        XCTAssertEqual(AppTheme(preset: .developerTool).forcedColorScheme, .dark)
        XCTAssertEqual(AppTheme(preset: .smallProduct).forcedColorScheme, .light)
        XCTAssertNil(AppTheme(preset: .practicalUtility).forcedColorScheme)
    }

    func testSmallProductUsesFriendlyOnomatopoeiaLabels() {
        let theme = AppTheme(preset: .smallProduct)
        XCTAssertEqual(theme.statusLabel(for: .success), String(localized: "Tock!"))
        XCTAssertEqual(theme.statusLabel(for: .error), String(localized: "Hmm?"))
        XCTAssertEqual(theme.statusLabel(for: .waiting), String(localized: "Hold on"))
        XCTAssertEqual(theme.statusLabel(for: .info), String(localized: "Note"))
    }

    // MARK: - Status Icon

    func testStatusIconPracticalUsesEmoji() {
        let theme = AppTheme(preset: .practicalUtility)
        XCTAssertEqual(theme.statusIcon(for: .success), "✅")
        XCTAssertEqual(theme.statusIcon(for: .error),   "❌")
        XCTAssertEqual(theme.statusIcon(for: .waiting), "⏳")
        XCTAssertEqual(theme.statusIcon(for: .info),    "💬")
    }

    func testStatusIconSmallProductUsesEmoji() {
        // Same emoji set as Practical — both fall through the `preset !=
        // .developerTool` branch. Locked in so a future preset-specific
        // override (e.g. Small Product wanting "🫡" for success) fails loudly.
        let theme = AppTheme(preset: .smallProduct)
        XCTAssertEqual(theme.statusIcon(for: .success), "✅")
        XCTAssertEqual(theme.statusIcon(for: .error),   "❌")
        XCTAssertEqual(theme.statusIcon(for: .waiting), "⏳")
        XCTAssertEqual(theme.statusIcon(for: .info),    "💬")
    }

    func testStatusIconDeveloperToolUsesTextTokens() {
        let theme = AppTheme(preset: .developerTool)
        XCTAssertEqual(theme.statusIcon(for: .success), "PASS")
        XCTAssertEqual(theme.statusIcon(for: .error),   "FAIL")
        XCTAssertEqual(theme.statusIcon(for: .waiting), "WAIT")
        XCTAssertEqual(theme.statusIcon(for: .info),    "INFO")
    }

    // MARK: - Menu Locale

    func testMenuLocaleIsEnglishForDeveloperTool() {
        XCTAssertEqual(AppTheme(preset: .developerTool).menuLocale.identifier,
                       "en_US_POSIX")
    }

    func testMenuLocaleIsCurrentForNonDeveloperThemes() {
        XCTAssertEqual(AppTheme(preset: .practicalUtility).menuLocale.identifier,
                       Locale.current.identifier)
        XCTAssertEqual(AppTheme(preset: .smallProduct).menuLocale.identifier,
                       Locale.current.identifier)
    }
}
