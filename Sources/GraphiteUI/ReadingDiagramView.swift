import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block in the reading view: a flowchart or a state diagram painted in the note's colors and
/// centered, scaled down when the column is narrower; or the block's source with why it could not be drawn.
struct ReadingDiagramView: View {
    let diagram: ReadingDiagram
    let textSize: Double
    let root: URL
    let navigate: (String, Bool) -> Void
    let scrollToHeading: (String) -> Void

    var body: some View {
        switch diagram {
        case .flowchart(let flowchart):
            ReadingFlowchartDrawing(flowchart: flowchart, textSize: textSize)
        case .unreadable(let source, let failure):
            VStack(alignment: .leading, spacing: 6) {
                ObsidianMarkdownText(markdown: "```mermaid\n" + source + "\n```", root: root, textSize: textSize, navigate: navigate,
                                     scrollToHeading: scrollToHeading)
                Label(failure.explanation, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .stateDiagram(let stateDiagram):
            ReadingStateDiagramDrawing(diagram: stateDiagram, textSize: textSize)
        }
    }
}

/// A laid-out flowchart, centered and as wide as it was laid out (in proportion to the text size now, if that
/// changed since the note was built), scaled down when the column is narrower.
private struct ReadingFlowchartDrawing: View {
    let flowchart: ReadingFlowchart
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        let size = flowchart.layout.size
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: size.width * textSize / flowchart.layout.font.size)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    ReadingFlowchartPainting(shapes: flowchart.shapes, colors: ReadingDiagramColors(theme: theme))
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(flowchart.title ?? "Flowchart")
            .accessibilityValue(flowchart.description ?? flowchart.nodeTexts.joined(separator: ", "))
    }
}

/// The flowchart's shapes and text at the layout's size, back to front as Pele draws them.
private struct ReadingFlowchartPainting: View {
    let shapes: ReadingFlowchartShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            shapes.solidEdges.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            shapes.thickEdges.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.thickLineWidth))
            shapes.dottedEdges.stroke(colors.foreground,
                                      style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth, dash: FlowchartDrawingParts.dottedDashLengths))
            shapes.filledMarks.fill(colors.foreground)
            shapes.strokedMarks.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            shapes.edgeTextPatches.fill(colors.background)
            lines(shapes.edgeTextLines)
            shapes.nodeFills.fill(colors.surface)
            shapes.nodeOutlines.stroke(colors.border, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            lines(shapes.nodeTextLines)
        }
    }

    private func lines(_ lines: [ReadingDiagramTextLine]) -> some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index].text)
                .font(lines[index].swiftUIFont)
                .foregroundStyle(colors.foreground)
                .fixedSize()
                .position(lines[index].center)
        }
    }

    private static func lineStyle(width: CGFloat, dash: [CGFloat] = []) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
    }
}
