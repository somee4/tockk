import Foundation

/// Whether an arriving alert is shown as the compact pill or the expanded
/// card by default. The user can still toggle at runtime (tap to expand,
/// collapse button to fold back), but this controls the first paint.
enum DefaultExpansionMode: String, Codable, CaseIterable, Identifiable {
    /// Start as the compact pill. Expands on tap.
    case compact
    /// Start as the full expanded card. The user can collapse back to the
    /// pill using the header's fold button.
    case expanded

    /// Compact is the baseline glanceable experience, so it remains the
    /// default. Extended is opt-in for users who want full context on arrival.
    static let defaultValue: Self = .compact

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .expanded: String(localized: "Expanded")
        }
    }
}
