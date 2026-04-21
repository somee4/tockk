import AppKit
import Foundation

// MARK: - Strategy

/// Policy that decides which physical screen Tockk should present notifications on.
///
/// The chosen strategy is a strong determinant of whether the user *catches*
/// completion alerts — Tockk's core product promise. Presenting on a screen
/// the user isn't looking at defeats the purpose.
enum ScreenSelectionStrategy: String, Codable, CaseIterable, Identifiable {
    /// The screen that currently contains the mouse pointer. Best for
    /// multi-monitor setups where the user switches focus between displays.
    case activeWindow

    /// The primary display (System Settings → Displays → "Main display").
    /// Useful when the user wants notifications pinned to one known surface.
    case mainDisplay

    static let defaultValue: Self = .activeWindow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .activeWindow: String(localized: "Active window monitor")
        case .mainDisplay: String(localized: "Main display")
        }
    }
}

// MARK: - Pure Geometry

/// Finds the index of the first frame that contains `point`.
///
/// Extracted as a free function so that screen selection logic can be unit
/// tested without instantiating `NSScreen` (which cannot be constructed by
/// client code on macOS).
func screenIndex(containing point: CGPoint, in frames: [CGRect]) -> Int? {
    frames.firstIndex { $0.contains(point) }
}

// MARK: - Providers

/// Abstracts the system inputs that `ScreenSelector` reads, so that tests
/// (and future non-AppKit hosts) can inject alternatives.
protocol ScreenProvider {
    var screens: [NSScreen] { get }
    var mainScreen: NSScreen? { get }
    /// Global-coordinate mouse position. Matches `NSEvent.mouseLocation`
    /// semantics (bottom-left origin, points).
    var mouseLocation: CGPoint { get }
}

struct SystemScreenProvider: ScreenProvider {
    var screens: [NSScreen] { NSScreen.screens }
    var mainScreen: NSScreen? { NSScreen.main }
    var mouseLocation: CGPoint { NSEvent.mouseLocation }
}

// MARK: - Selector

struct ScreenSelector {
    let strategy: ScreenSelectionStrategy
    let provider: ScreenProvider

    init(
        strategy: ScreenSelectionStrategy = .defaultValue,
        provider: ScreenProvider = SystemScreenProvider()
    ) {
        self.strategy = strategy
        self.provider = provider
    }

    /// Resolves the current strategy against live system state.
    /// Returns `nil` only if no displays are connected at all.
    func selectScreen() -> NSScreen? {
        switch strategy {
        case .mainDisplay:
            return provider.mainScreen ?? provider.screens.first

        case .activeWindow:
            let screens = provider.screens
            let frames = screens.map(\.frame)
            if let idx = screenIndex(containing: provider.mouseLocation, in: frames) {
                return screens[idx]
            }
            // Mouse outside every known frame (rare; display teardown race).
            return provider.mainScreen ?? screens.first
        }
    }
}
