import SwiftUI

/// The Tockk brand mark — two stacked dots that visualize the product name
/// ("똑똑", the Korean onomatopoeia for a double knock).
///
/// Used in the Compact pill in place of a generic bell/terminal/sparkles
/// glyph. It replaces the default macOS notification iconography with
/// something specific to Tockk — a small but defining brand signature that
/// shows up every time a notification lands.
///
/// The dots pick up whichever status color is active, so the mark itself
/// still reads as a status signal at a glance.
struct TockkMark: View {
    let tint: Color
    /// Size of an individual dot. Default matches Compact proportions.
    var dotSize: CGFloat = 4
    /// Vertical gap between the two dots.
    var spacing: CGFloat = 4

    var body: some View {
        VStack(spacing: spacing) {
            dot
            dot
        }
    }

    private var dot: some View {
        Circle()
            .fill(tint)
            .frame(width: dotSize, height: dotSize)
    }
}

#Preview {
    HStack(spacing: 24) {
        TockkMark(tint: .green)
        TockkMark(tint: .red, dotSize: 6, spacing: 5)
        TockkMark(tint: .orange, dotSize: 3, spacing: 3)
    }
    .padding(40)
    .background(.black)
}
