import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out XY chart in the reading view: its bars and lines in Pele's series colors, its grid, axes and text in the
/// note's colors, centered and scaled down when the column is narrower, with what a screen reader says of it.
struct ReadingXYChartDrawing: View {
    let chart: ReadingXYChart
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: chart.layout.size, layoutTextSize: chart.layout.font.size, textSize: textSize) {
            ReadingXYChartPainting(shapes: chart.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(chart.title ?? "XY chart")
        .accessibilityValue(chart.description ?? chart.seriesSummaries.joined(separator: "; "))
    }
}

/// The XY chart's shapes and text at the layout's size, back to front as Pele draws them: the grid, the bars, the
/// lines with their dots, the axes, the text.
private struct ReadingXYChartPainting: View {
    let shapes: ReadingXYChartShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.gridLines.stroke(colors.alternateSurface, lineWidth: XYChartDrawingParts.lineWidth)
            ForEach(shapes.barFills.indices, id: \.self) { index in
                shapes.barFills[index].fill(ReadingDiagramColors.seriesColor(index))
            }
            ForEach(shapes.lines.indices, id: \.self) { index in
                let line = shapes.lines[index]
                line.stroke.stroke(ReadingDiagramColors.seriesColor(line.seriesIndex), style: Self.seriesLineStyle)
                line.dots.fill(ReadingDiagramColors.seriesColor(line.seriesIndex))
            }
            shapes.axisLines.stroke(colors.border, lineWidth: XYChartDrawingParts.lineWidth)
            lines(shapes.axisLabelLines, color: colors.muted)
            lines(shapes.textLines, color: colors.foreground)
            ForEach(shapes.turnedTextLines.indices, id: \.self) { index in
                Text(verbatim: shapes.turnedTextLines[index].text)
                    .font(shapes.turnedTextLines[index].swiftUIFont)
                    .foregroundStyle(colors.foreground)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .position(shapes.turnedTextLines[index].center)
            }
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

    private static let seriesLineStyle = StrokeStyle(lineWidth: XYChartDrawingParts.seriesLineWidth, lineCap: .round, lineJoin: .round)
}
