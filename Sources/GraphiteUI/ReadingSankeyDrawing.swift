import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out Sankey diagram in the reading view: its bands and bars in Pele's series colors, its text in the note's
/// colors, centered and scaled down when the column is narrower, with what a screen reader says of it.
struct ReadingSankeyDrawing: View {
    let diagram: ReadingSankeyDiagram
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: diagram.layout.size, layoutTextSize: diagram.layout.font.size, textSize: textSize) {
            ReadingSankeyPainting(shapes: diagram.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(diagram.title ?? "Sankey diagram")
        .accessibilityValue(diagram.flowSummaries.joined(separator: "; "))
    }
}

/// The Sankey diagram's shapes and text at the layout's size, back to front as Pele draws them: each band filled with a
/// gradient from its source's color to its target's at Pele's opacity, the bars, the names and the values.
private struct ReadingSankeyPainting: View {
    let shapes: ReadingSankeyShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(shapes.bands.indices, id: \.self) { index in
                let band = shapes.bands[index]
                let gradientColors = [ReadingDiagramColors.seriesColor(band.sourceSeriesIndex), ReadingDiagramColors.seriesColor(band.targetSeriesIndex)]
                band.outline
                    .fill(LinearGradient(colors: gradientColors, startPoint: band.gradientStart, endPoint: band.gradientEnd))
                    .opacity(SankeyDrawingParts.bandOpacity)
            }
            ForEach(shapes.nodeFills.indices, id: \.self) { index in
                shapes.nodeFills[index].fill(ReadingDiagramColors.seriesColor(index))
            }
            lines(shapes.textLines, color: colors.foreground)
            lines(shapes.valueLines, color: colors.muted)
        }
    }

    private func lines(_ lines: [ReadingDiagramTextLine], color: Color) -> some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index].text)
                .font(lines[index].swiftUIFont)
                .foregroundStyle(color)
                .fixedSize()
                .position(lines[index].center)
        }
    }
}
