import SwiftUI

/// A laid-out diagram's painting, centered and as wide as it was laid out (in proportion to the text size now, if
/// that changed since the note was built), scaled down when the column is narrower.
struct ReadingScaledDiagram<Painting: View>: View {
    /// The size the diagram was laid out at.
    let size: CGSize
    /// The text size the diagram was laid out in.
    let layoutTextSize: CGFloat
    /// The note's text size now.
    let textSize: Double
    let painting: Painting

    init(size: CGSize, layoutTextSize: CGFloat, textSize: Double, @ViewBuilder painting: () -> Painting) {
        self.size = size
        self.layoutTextSize = layoutTextSize
        self.textSize = textSize
        self.painting = painting()
    }

    var body: some View {
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: size.width * textSize / layoutTextSize)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    painting
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
    }
}
