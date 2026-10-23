import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out user journey in the reading view: its cards, bands, scale and faces in the note's colors, its actors'
/// dots in Pele's series colors, centered and scaled down when the column is narrower, with what a screen reader says
/// of it.
struct ReadingUserJourneyDrawing: View {
    let journey: ReadingUserJourney
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: journey.layout.size, layoutTextSize: journey.layout.font.size, textSize: textSize) {
            ReadingUserJourneyPainting(shapes: journey.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(journey.title ?? "User journey")
        .accessibilityValue(journey.description ?? journey.taskTexts.joined(separator: "; "))
    }
}

/// The user journey's shapes and text at the layout's size, back to front as Pele draws them: the scale, the stems,
/// the line from face to face, the faces, the bands, the cards and their dots, the legend, the text.
private struct ReadingUserJourneyPainting: View {
    let shapes: ReadingUserJourneyShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.scaleLines.stroke(colors.alternateSurface, lineWidth: UserJourneyDrawingParts.lineWidth)
            lines(shapes.scaleTextLines, color: colors.muted)
            shapes.stems.stroke(colors.border, style: StrokeStyle(lineWidth: UserJourneyDrawingParts.lineWidth, dash: UserJourneyDrawingParts.stemDashLengths))
            shapes.scoreLine.stroke(colors.foreground, style: StrokeStyle(lineWidth: UserJourneyDrawingParts.lineWidth, lineJoin: .round))
            shapes.faces.fill(colors.background)
            shapes.faces.stroke(colors.foreground, lineWidth: UserJourneyDrawingParts.lineWidth)
            shapes.eyes.fill(colors.foreground)
            shapes.mouths.stroke(colors.foreground, style: StrokeStyle(lineWidth: UserJourneyDrawingParts.lineWidth, lineCap: .round))
            shapes.sectionBands.fill(colors.alternateSurface)
            shapes.cards.fill(colors.surface)
            shapes.cards.stroke(colors.border, lineWidth: UserJourneyDrawingParts.lineWidth)
            ForEach(shapes.cardDotsBySeries.indices, id: \.self) { index in
                shapes.cardDotsBySeries[index].fill(ReadingDiagramColors.seriesColor(index))
                shapes.cardDotsBySeries[index].stroke(colors.surface, lineWidth: UserJourneyDrawingParts.lineWidth)
            }
            ForEach(shapes.legendDotsBySeries.indices, id: \.self) { index in
                shapes.legendDotsBySeries[index].fill(ReadingDiagramColors.seriesColor(index))
            }
            lines(shapes.textLines, color: colors.foreground)
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
