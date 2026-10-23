import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out quadrant chart in the reading view: its quadrants and texts in the note's colors, its points in Pele's
/// first series color or the colors the chart writes, centered and scaled down when the column is narrower, with what a
/// screen reader says of it.
struct ReadingQuadrantChartDrawing: View {
    let chart: ReadingQuadrantChart
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: chart.layout.size, layoutTextSize: chart.layout.font.size, textSize: textSize) {
            ReadingQuadrantChartPainting(shapes: chart.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(chart.title ?? "Quadrant chart")
        .accessibilityValue(chart.description ?? chart.summaries.joined(separator: "; "))
    }
}

/// The quadrant chart's shapes and text at the layout's size, back to front as Pele draws them: the quadrants, the
/// axes' texts, the points, the texts.
private struct ReadingQuadrantChartPainting: View {
    let shapes: ReadingQuadrantChartShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.quadrants.fill(colors.surface)
            shapes.quadrants.stroke(colors.border, lineWidth: QuadrantChartDrawingParts.lineWidth)
            lines(shapes.axisTextLines, color: colors.muted, isTurned: false)
            lines(shapes.turnedAxisTextLines, color: colors.muted, isTurned: true)
            ForEach(shapes.pointGroups.indices, id: \.self) { index in
                let group = shapes.pointGroups[index]
                group.circles.fill(color(group.fill))
                if let stroke = group.stroke { group.circles.stroke(color(stroke.paint), lineWidth: stroke.width) }
            }
            lines(shapes.textLines, color: colors.foreground, isTurned: false)
        }
    }

    private func color(_ paint: QuadrantChartPaint) -> Color {
        switch paint {
        case .firstSeries: ReadingDiagramColors.seriesColor(0)
        case .written(let written): Color(.sRGB, red: Double(written.red) / 255, green: Double(written.green) / 255, blue: Double(written.blue) / 255)
        }
    }

    /// Each line at its middle, turned a quarter anticlockwise about it when `isTurned`.
    private func lines(_ lines: [ReadingDiagramTextLine], color: Color, isTurned: Bool) -> some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index].text)
                .font(lines[index].swiftUIFont)
                .foregroundStyle(color)
                .fixedSize()
                .rotationEffect(.degrees(isTurned ? Self.turnedDegrees : 0))
                .position(lines[index].center)
        }
    }

    /// A quarter turn anticlockwise on the page.
    private static let turnedDegrees: Double = -90
}
