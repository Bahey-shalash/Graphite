import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out mindmap in the reading view: its branches in Pele's series colors, the root and the text in the
/// note's colors, centered and scaled down when the column is narrower, with what a screen reader says of it.
struct ReadingMindmapDrawing: View {
    let mindmap: ReadingMindmap
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: mindmap.layout.size, layoutTextSize: mindmap.layout.font.size, textSize: textSize) {
            ReadingMindmapPainting(shapes: mindmap.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(mindmap.title ?? "Mindmap")
        .accessibilityValue(mindmap.description ?? mindmap.nodeTexts.joined(separator: ", "))
    }
}

/// The mindmap's shapes and text at the layout's size, back to front as Pele draws them: each branch's links and
/// tinted nodes, the root over the links that leave it, the text.
private struct ReadingMindmapPainting: View {
    let shapes: ReadingMindmapShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(shapes.branches, id: \.branchIndex) { branch in
                let color = ReadingDiagramColors.seriesColor(branch.branchIndex)
                branch.links.stroke(color, lineWidth: MindmapDrawingParts.linkLineWidth)
                branch.nodeOutlines.fill(color.opacity(MindmapDrawingParts.nodeFillOpacity))
                branch.nodeOutlines.stroke(color, lineWidth: MindmapDrawingParts.outlineLineWidth)
            }
            shapes.rootOutline.fill(colors.surface)
            shapes.rootOutline.stroke(colors.border, lineWidth: MindmapDrawingParts.outlineLineWidth)
            ForEach(shapes.textLines.indices, id: \.self) { index in
                let line = shapes.textLines[index]
                Text(verbatim: line.text)
                    .font(line.swiftUIFont)
                    .foregroundStyle(colors.foreground)
                    .fixedSize()
                    .position(line.center)
            }
        }
    }
}
