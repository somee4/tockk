import SwiftUI

/// A whisper-quiet horizontal scanline texture, used exclusively by the
/// `.developerTool` preset. It's barely perceptible up close but lends the
/// panel a CRT / terminal atmosphere that separates Tockk from a standard
/// macOS glass surface.
///
/// Opacity is tuned low enough (under 4%) that it reads as "material" not
/// "pattern." If a user notices the lines, the effect is too strong — turn
/// `opacity` down rather than up.
struct ScanlineOverlay: View {
    /// Vertical gap between scanlines in points. Smaller = denser CRT feel.
    var spacing: CGFloat = 2
    /// Opacity of each line; kept below 0.04 by default.
    var opacity: Double = 0.035

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0.5
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    path,
                    with: .color(.white.opacity(opacity)),
                    lineWidth: 0.5
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Adds a subtle scanline texture on top of a panel when `enabled`.
    /// New call sites should read `theme.showsScanlines` and pass it here
    /// so the decision lives in the theme, not re-derived from the preset
    /// enum.
    @ViewBuilder
    func tockkScanlines(enabled: Bool) -> some View {
        if enabled {
            overlay(
                ScanlineOverlay()
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
        } else {
            self
        }
    }

}

#Preview {
    RoundedRectangle(cornerRadius: 16)
        .fill(.black)
        .frame(width: 320, height: 100)
        .overlay(ScanlineOverlay(opacity: 0.08))
        .padding(40)
        .background(Color.gray)
}
