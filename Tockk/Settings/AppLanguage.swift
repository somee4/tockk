import Foundation

/// UI language override for Tockk. Writes to `AppleLanguages` in the app's
/// `UserDefaults` at save time; `NSLocalizedString` / SwiftUI String Catalog
/// lookups read this at launch, so changes only land after a relaunch.
///
/// `.system` removes the override so macOS falls back to the user's system
/// language preferences. `.english` and `.korean` pin the UI regardless of
/// system locale — useful for screenshotting, QA, or users who prefer an
/// app-local language that differs from the system.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case english
    case korean

    /// System is the zero-config default — new installs behave exactly like
    /// before the feature existed.
    static let defaultValue: Self = .system

    var id: String { rawValue }

    /// `.english` / `.korean` render in their own language (endonym) so users
    /// can always recognize their own regardless of the active UI locale.
    /// `.system` isn't tied to a specific language, so it follows the current
    /// UI language instead.
    var displayName: String {
        switch self {
        case .system:  String(localized: "System")
        case .english: "English"
        case .korean:  "한국어"
        }
    }

    /// Locale codes written into `AppleLanguages`. `nil` means "clear the
    /// override" — the system handles fallback from there.
    var appleLanguageCode: String? {
        switch self {
        case .system:  nil
        case .english: "en"
        case .korean:  "ko"
        }
    }
}
