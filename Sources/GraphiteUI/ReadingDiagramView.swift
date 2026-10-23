import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A ```` ```mermaid ```` block in the reading view: a diagram of a type drawn natively, painted in the note's colors and
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
        case .pieChart(let chart):
            ReadingPieChartDrawing(chart: chart, textSize: textSize)
        case .ganttChart(let chart):
            ReadingGanttChartDrawing(chart: chart, textSize: textSize)
        case .unreadable(let source, let failure):
            VStack(alignment: .leading, spacing: 6) {
                ObsidianMarkdownText(markdown: "```mermaid\n" + source + "\n```", root: root, textSize: textSize, navigate: navigate,
                                     scrollToHeading: scrollToHeading)
                Label(failure.explanation, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .stateDiagram(let stateDiagram):
            ReadingStateDiagramDrawing(diagram: stateDiagram, textSize: textSize)
        case .classDiagram(let classDiagram):
            ReadingClassDiagramDrawing(diagram: classDiagram, textSize: textSize)
        case .sequence(let sequence):
            ReadingSequenceDrawing(sequence: sequence, textSize: textSize)
        case .entityRelationship(let entityRelationship):
            ReadingEntityRelationshipDrawing(diagram: entityRelationship, textSize: textSize)
        case .mindmap(let mindmap):
            ReadingMindmapDrawing(mindmap: mindmap, textSize: textSize)
        case .timeline(let timeline):
            ReadingTimelineDrawing(timeline: timeline, textSize: textSize)
        case .gitGraph(let gitGraph):
            ReadingGitGraphDrawing(gitGraph: gitGraph, textSize: textSize)
        case .userJourney(let journey):
            ReadingUserJourneyDrawing(journey: journey, textSize: textSize)
        case .quadrantChart(let chart):
            ReadingQuadrantChartDrawing(chart: chart, textSize: textSize)
        case .xyChart(let chart):
            ReadingXYChartDrawing(chart: chart, textSize: textSize)
        case .sankey(let diagram):
            ReadingSankeyDrawing(diagram: diagram, textSize: textSize)
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
            ReadingFlowchartClusterBoxes(clusters: shapes.clusters, colors: colors)
            shapes.solidEdges.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            shapes.thickEdges.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.thickLineWidth))
            shapes.dottedEdges.stroke(colors.foreground,
                                      style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth, dash: FlowchartDrawingParts.dottedDashLengths))
            shapes.filledMarks.fill(colors.foreground)
            shapes.strokedMarks.stroke(colors.foreground, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            ReadingFlowchartCrossedClusterTitles(clusters: shapes.clusters, colors: colors)
            shapes.edgeTextPatches.fill(colors.background)
            lines(shapes.edgeTextLines)
            shapes.nodeFills.fill(colors.surface)
            shapes.nodeOutlines.stroke(colors.border, style: Self.lineStyle(width: FlowchartDrawingParts.lineWidth))
            lines(shapes.nodeTextLines)
        }
    }

    private func lines(_ lines: [ReadingDiagramTextLine]) -> some View {
        ReadingDiagramTextLines(lines: lines, color: colors.foreground)
    }

    private static func lineStyle(width: CGFloat, dash: [CGFloat] = []) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
    }
}

/// The groups' boxes behind everything, as Pele paints them: the fills depth by depth, each half of the alternate
/// surface over what is behind, the outlines, and the titles no edge crosses.
private struct ReadingFlowchartClusterBoxes: View {
    let clusters: ReadingFlowchartClusterShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(clusters.fillsByDepth.indices, id: \.self) { depth in
                clusters.fillsByDepth[depth].fill(colors.alternateSurface.opacity(FlowchartClusterDrawingParts.fillOpacity))
            }
            clusters.outlines.stroke(colors.border, lineWidth: FlowchartDrawingParts.lineWidth)
            ReadingDiagramTextLines(lines: clusters.titleLines, color: colors.muted)
        }
    }
}

/// The titles edges run through, over the edges, each on a patch painted as its box is where it sits: the background,
/// then the alternate surface at half its opacity once for each box around it and its own.
private struct ReadingFlowchartCrossedClusterTitles: View {
    let clusters: ReadingFlowchartClusterShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(clusters.crossedTitlePatchesByDepth.indices, id: \.self) { depth in
                ZStack(alignment: .topLeading) {
                    clusters.crossedTitlePatchesByDepth[depth].fill(colors.background)
                    ForEach(0...depth, id: \.self) { _ in
                        clusters.crossedTitlePatchesByDepth[depth].fill(colors.alternateSurface.opacity(FlowchartClusterDrawingParts.fillOpacity))
                    }
                }
            }
            ReadingDiagramTextLines(lines: clusters.crossedTitleLines, color: colors.muted)
        }
    }
}

/// Lines of a diagram's text, each centered where the layout put it, in one color.
private struct ReadingDiagramTextLines: View {
    let lines: [ReadingDiagramTextLine]
    let color: Color

    var body: some View {
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index].text)
                .font(lines[index].swiftUIFont)
                .foregroundStyle(color)
                .fixedSize()
                .position(lines[index].center)
        }
    }
}
