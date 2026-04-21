import SwiftUI

#if DEBUG

/// Preview-only backdrop that simulates a MacBook Pro notch plus menubar and
/// desktop wallpaper, so a CompactNotchView preview is judged against the
/// real on-device context rather than a black void. Not for production use.
struct NotchPreviewBackdrop<Content: View>: View {
    /// Approximate MacBook Pro 14" notch dimensions in points.
    var notchWidth: CGFloat = 210
    var notchHeight: CGFloat = 32
    /// Simulated desktop wallpaper. Two presets: dark desktop and light
    /// desktop, so adaptive glass can be judged against both.
    var wallpaper: Wallpaper = .dark
    let content: () -> Content

    enum Wallpaper {
        case dark, light

        var gradient: LinearGradient {
            switch self {
            case .dark:
                return LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.12, blue: 0.16),
                        Color(red: 0.22, green: 0.16, blue: 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .light:
                return LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.84, blue: 0.92),
                        Color(red: 0.92, green: 0.88, blue: 0.82)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper.gradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Menubar area — dark regardless of wallpaper on macOS.
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(Color.black.opacity(0.75))
                        .frame(height: 28)

                    // Notch cutout: rounded-bottom black pill centered at the
                    // top edge, bleeding into the menubar.
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 12,
                        bottomTrailingRadius: 12,
                        style: .continuous
                    )
                    .fill(Color.black)
                    .frame(width: notchWidth, height: notchHeight)
                }
                .frame(maxWidth: .infinity)

                // The pill emerges just below the notch, matching how the
                // real NotchPresenter anchors.
                content()
                    .padding(.top, 6)

                Spacer(minLength: 0)
            }
        }
    }
}

#endif
