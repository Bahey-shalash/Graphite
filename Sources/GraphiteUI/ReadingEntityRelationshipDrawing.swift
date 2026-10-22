import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out entity relationship diagram, centered and as wide as it was laid out (in proportion to the text size
/// now, if that changed since the note was built), scaled down when the column is narrower.
struct ReadingEntityRelationshipDrawing: View {
    let diagram: ReadingEntityRelationshipDiagram
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        let size = diagram.layout.size
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: size.width * textSize / diagram.layout.font.size)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ReadingEntityRelationshipPainting(shapes: diagram.shapes, colors: ReadingDiagramColors(theme: theme))
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(diagram.title ?? "Entity relationship diagram")
            .accessibilityValue(diagram.description ?? diagram.summary.joined(separator: ", "))
    }
}

/// The diagram's shapes and text at the layout's size, back to front as Pele draws them: lines and marks, labels on
/// their patches, boxes with their striped rows and outlines, then their text.
private struct ReadingEntityRelationshipPainting: View {
    let shapes: ReadingEntityRelationshipShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.identifyingLines.stroke(colors.foreground, style: Self.lineStyle())
            shapes.nonIdentifyingLines.stroke(colors.foreground, style: Self.lineStyle(dash: EntityRelationshipDrawingParts.nonIdentifyingDashLengths))
            shapes.markFills.fill(colors.background)
            shapes.markOutlines.stroke(colors.foreground, style: Self.lineStyle())
            shapes.labelPatches.fill(colors.background)
            lines(shapes.labelLines, color: colors.foreground)
            shapes.boxFills.fill(colors.surface)
            shapes.rowStripes.fill(colors.background)
            shapes.boxOutlines.stroke(colors.border, style: Self.lineStyle())
            lines(shapes.textLines, color: colors.foreground)
            lines(shapes.mutedLines, color: colors.foreground.opacity(EntityRelationshipDrawingParts.mutedTextOpacity))
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

    private static func lineStyle(dash: [CGFloat] = []) -> StrokeStyle {
        StrokeStyle(lineWidth: EntityRelationshipDrawingParts.lineWidth, lineCap: .round, lineJoin: .round, dash: dash)
    }
}
