import Foundation

/// How long an alert remains visible on screen, and what happens when the
/// timer elapses. Tockk defaults to `.persistent` because its core product
/// promise is "catch the user when they aren't looking" — a short auto-dismiss
/// defeats that purpose for the baseline experience.
enum AlertResidenceMode: String, Codable, CaseIterable, Identifiable {
    /// Stays until the user explicitly dismisses it (click X, press ESC).
    case persistent

    /// After the configured seconds elapse, the expanded view collapses back
    /// to the compact pill. The pill persists until manually dismissed.
    case collapseAfter

    /// After the configured seconds elapse, the entire alert is dismissed.
    /// This is the "traditional" macOS notification behavior.
    case dismissAfter

    static let defaultValue: Self = .persistent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .persistent: String(localized: "Until manually dismissed")
        case .collapseAfter: String(localized: "Auto-collapse")
        case .dismissAfter: String(localized: "Auto-dismiss")
        }
    }

    /// Whether this mode requires a configurable seconds value from the user.
    var needsResidenceSeconds: Bool {
        switch self {
        case .persistent: false
        case .collapseAfter, .dismissAfter: true
        }
    }
}
