import SwiftUI

/// Pins the subtree to a specific `colorScheme` when one is supplied.
/// Used by themes whose pill background brightness diverges from the system
/// appearance — solid-black pills need `.dark`, cream pills need `.light`.
/// When `scheme` is `nil`, the system appearance is inherited unchanged.
struct ForcedColorSchemeIfNeeded: ViewModifier {
    let scheme: ColorScheme?

    func body(content: Content) -> some View {
        if let scheme {
            content.environment(\.colorScheme, scheme)
        } else {
            content
        }
    }
}

extension View {
    /// Pins the view to `scheme` when non-nil, otherwise inherits the system
    /// appearance. Replaces the earlier dark-only helper so pills with
    /// light backgrounds can force `.light` too.
    func forcedColorScheme(_ scheme: ColorScheme?) -> some View {
        modifier(ForcedColorSchemeIfNeeded(scheme: scheme))
    }
}
