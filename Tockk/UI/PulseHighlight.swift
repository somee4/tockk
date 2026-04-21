import SwiftUI

// MARK: - Arrival Effect

/// A continuous attention effect applied to a notification panel — colored
/// stroke + tinted halo breathing in a loop while the panel is on screen.
/// Shared across all themes so the "new event" signal reads consistently
/// regardless of the active visual direction.
///
/// Honors `accessibilityReduceMotion` and a per-call `isDisabled` opt-out.
/// When either is set, the effect is skipped and the panel sits at rest.
struct ArrivalEffect<S: InsettableShape>: ViewModifier {
    let tint: Color
    let shape: S
    let motion: AppTheme.Motion
    let isDisabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseIntensity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(pulseOverlay)
            .shadow(
                color: tint.opacity(pulseIntensity * motion.pulseShadowOpacity),
                radius: motion.pulseShadowRadius,
                y: 0
            )
            .onAppear(perform: runAnimation)
    }

    private var pulseOverlay: some View {
        shape
            .stroke(
                tint.opacity(pulseIntensity * motion.pulseGlowOpacity),
                lineWidth: 3
            )
            .blur(radius: 3)
            .allowsHitTesting(false)
    }

    private func runAnimation() {
        guard !reduceMotion, !isDisabled else {
            pulseIntensity = 0
            return
        }
        // Start the border at rest and breathe up to full intensity, then
        // autoreverse forever. The autoreverse cadence means one full cycle
        // takes 2 × pulseDuration, which keeps the visible rhythm close to
        // the previous one-shot reading while now lasting the lifetime of
        // the alert instead of just the first glance.
        pulseIntensity = 0
        withAnimation(
            .easeInOut(duration: motion.pulseDuration)
                .repeatForever(autoreverses: true)
        ) {
            pulseIntensity = motion.pulseInitialIntensity
        }
    }
}

extension View {
    /// Applies the shared pulse arrival effect, using the given panel outline
    /// for stroke alignment.
    func arrivalEffect<S: InsettableShape>(
        tint: Color,
        shape: S,
        motion: AppTheme.Motion,
        isDisabled: Bool = false
    ) -> some View {
        modifier(ArrivalEffect(tint: tint, shape: shape, motion: motion, isDisabled: isDisabled))
    }
}
