import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out timeline in the reading view: its periods and sections in Pele's series colors, its lines and text in
/// the note's colors, centered and scaled down when the column is narrower, with what a screen reader says of it.
struct ReadingTimelineDrawing: View {
    let timeline: ReadingTimeline
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: timeline.layout.size, layoutTextSize: timeline.layout.font.size, textSize: textSize) {
            ReadingTimelinePainting(shapes: timeline.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(timeline.title ?? "Timeline")
        .accessibilityValue(timeline.description ?? timeline.periodTexts.joined(separator: "; "))
    }
}

/// The timeline's shapes and text at the layout's size, back to front as Pele draws them: the axis, the lines to
/// the events, the boxes and dots, the text.
private struct ReadingTimelinePainting: View {
    let shapes: ReadingTimelineShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.axis.stroke(colors.foreground, lineWidth: TimelineDrawingParts.lineWidth)
            shapes.axisArrow.fill(colors.foreground)
            shapes.connectors.stroke(colors.border, lineWidth: TimelineDrawingParts.lineWidth)
            ForEach(shapes.colorGroups.indices, id: \.self) { index in
                let group = shapes.colorGroups[index]
                let groupColor = color(group.color)
                group.boxes.fill(groupColor)
                group.eventBoxes.fill(groupColor.opacity(TimelineDrawingParts.eventFillOpacity))
                group.dots.fill(groupColor)
                group.dots.stroke(colors.background, lineWidth: TimelineDrawingParts.dotOutlineWidth)
            }
            lines(shapes.textLinesOnBoxes, color: colors.background)
            lines(shapes.textLines, color: colors.foreground)
        }
    }

    private func color(_ color: TimelineColor) -> Color {
        switch color {
        case .series(let index): ReadingDiagramColors.seriesColor(index)
        case .muted: colors.muted
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
