import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out class diagram, centered and as wide as it was laid out (in proportion to the text size now, if that
/// changed since the note was built), scaled down when the column is narrower.
struct ReadingClassDiagramDrawing: View {
    let diagram: ReadingClassDiagram
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        let size = diagram.layout.size
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: size.width * textSize / diagram.layout.font.size)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ReadingClassDiagramPainting(shapes: diagram.shapes, colors: ReadingClassDiagramColors(diagram: ReadingDiagramColors(theme: theme)))
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(diagram.title ?? "Class diagram")
            .accessibilityValue(diagram.description ?? diagram.classNames.joined(separator: ", "))
    }
}

/// The class diagram's shapes and text at the layout's size, back to front as Pele draws them.
private struct ReadingClassDiagramPainting: View {
    let shapes: ReadingClassDiagramShapes
    let colors: ReadingClassDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.solidLines.stroke(colors.diagram.foreground, style: Self.lineStyle())
            shapes.dashedLines.stroke(colors.diagram.foreground, style: Self.lineStyle(dash: ClassDiagramDrawingParts.dashedDashLengths))
            shapes.dottedLines.stroke(colors.diagram.foreground, style: Self.lineStyle(dash: ClassDiagramDrawingParts.dottedDashLengths))
            shapes.filledMarks.fill(colors.diagram.foreground)
            shapes.strokedMarks.stroke(colors.diagram.foreground, style: Self.lineStyle())
            shapes.edgeTextPatches.fill(colors.diagram.background)
            lines(shapes.edgeTextLines, color: colors.diagram.foreground)
            lines(shapes.cardinalityLines, color: colors.muted)
            shapes.classFills.fill(colors.diagram.surface)
            shapes.noteFills.fill(colors.noteSurface)
            shapes.outlines.stroke(colors.diagram.border, style: Self.lineStyle())
            lines(shapes.annotationLines, color: colors.muted)
            lines(shapes.nameLines, color: colors.diagram.foreground)
            memberLines
            lines(shapes.noteTextLines, color: colors.diagram.foreground)
        }
    }

    private var memberLines: some View {
        ForEach(shapes.memberLines.indices, id: \.self) { index in
            let line = shapes.memberLines[index]
            Text(verbatim: line.text)
                .font(line.swiftUIFont)
                .italic(line.isItalic)
                .underline(line.isUnderlined)
                .foregroundStyle(colors.diagram.foreground)
                .fixedSize()
                .frame(width: line.width, alignment: .leading)
                .position(line.center)
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
        StrokeStyle(lineWidth: ClassDiagramDrawingParts.lineWidth, lineCap: .round, lineJoin: .round, dash: dash)
    }
}
