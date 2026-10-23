import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out state diagram, centered and as wide as it was laid out (in proportion to the text size now, if that
/// changed since the note was built), scaled down when the column is narrower.
struct ReadingStateDiagramDrawing: View {
    let diagram: ReadingStateDiagram
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        let size = diagram.layout.size
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: size.width * textSize / diagram.layout.font.size)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ReadingStateDiagramPainting(shapes: diagram.shapes, colors: ReadingDiagramColors(theme: theme))
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(diagram.title ?? "State diagram")
            .accessibilityValue(diagram.description ?? diagram.stateNames.joined(separator: ", "))
    }
}

/// The state diagram's shapes and text at the layout's size, back to front as Pele draws them.
private struct ReadingStateDiagramPainting: View {
    let shapes: ReadingStateDiagramShapes
    let colors: ReadingDiagramColors

    var body: some View {
        let lineStyle = StrokeStyle(lineWidth: StateDiagramDrawingParts.lineWidth, lineCap: .round, lineJoin: .round)
        ZStack(alignment: .topLeading) {
            shapes.transitionLines.stroke(colors.foreground, style: lineStyle)
            shapes.noteConnectors.stroke(colors.border, style: StrokeStyle(lineWidth: StateDiagramDrawingParts.lineWidth, lineCap: .round, lineJoin: .round,
                                                                           dash: StateDiagramDrawingParts.noteConnectorDashLengths))
            shapes.arrows.fill(colors.foreground)
            shapes.transitionTextPatches.fill(colors.background)
            lines(shapes.transitionTextLines, color: colors.foreground)
            shapes.stateFills.fill(colors.surface)
            shapes.stateOutlines.stroke(colors.border, style: lineStyle)
            shapes.endRings.fill(colors.background)
            shapes.endRings.stroke(colors.foreground, style: lineStyle)
            shapes.solidMarks.fill(colors.foreground)
            lines(shapes.stateTextLines, color: colors.foreground)
            shapes.noteSheets.fill(colors.background)
            shapes.noteSheets.stroke(colors.border, style: lineStyle)
            shapes.noteFolds.stroke(colors.border, style: lineStyle)
            lines(shapes.noteTextLines, color: colors.background.mix(with: colors.foreground, by: Double(DiagramPalette.noteTextShare), in: .device))
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
