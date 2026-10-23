import SwiftUI
import GraphiteCore
import MermaidDiagrams

/// A laid-out Git graph in the reading view: its lanes, lines and commits in Pele's series colors, its patches, ids
/// and tags in the note's colors, centered and scaled down when the column is narrower, with what a screen reader
/// says of it.
struct ReadingGitGraphDrawing: View {
    let gitGraph: ReadingGitGraph
    let textSize: Double
    @Environment(\.noteTheme) private var theme

    var body: some View {
        ReadingScaledDiagram(size: gitGraph.layout.size, layoutTextSize: gitGraph.layout.font.size, textSize: textSize) {
            ReadingGitGraphPainting(shapes: gitGraph.shapes, colors: ReadingDiagramColors(theme: theme))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel(gitGraph.title ?? "Git graph")
        .accessibilityValue(gitGraph.description ?? gitGraph.branchTexts.joined(separator: "; "))
    }
}

/// The Git graph's shapes and text at the layout's size, back to front as Pele draws them: lanes and names, lines,
/// symbols and their marks, ids on their patches, tags, the title.
private struct ReadingGitGraphPainting: View {
    let shapes: ReadingGitGraphShapes
    let colors: ReadingDiagramColors

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(shapes.colorGroups.indices, id: \.self) { index in
                let group = shapes.colorGroups[index]
                group.laneLines.stroke(color(group),
                                       style: StrokeStyle(lineWidth: GitGraphDrawingParts.laneLineWidth, dash: GitGraphDrawingParts.laneDashLengths))
                group.nameBoxes.fill(color(group))
            }
            ReadingGitGraphTextLines(lines: shapes.nameLines, color: colors.background)
            ReadingGitGraphConnectors(groups: shapes.colorGroups)
            ForEach(shapes.colorGroups.indices, id: \.self) { index in
                let group = shapes.colorGroups[index]
                group.rings.fill(colors.background)
                group.rings.stroke(color(group), lineWidth: GitGraphDrawingParts.ringLineWidth)
                group.symbols.fill(color(group))
            }
            shapes.reverseCrosses.stroke(colors.background, style: StrokeStyle(lineWidth: GitGraphDrawingParts.crossLineWidth, lineCap: .round))
            shapes.cherryStems.stroke(colors.background, style: StrokeStyle(lineWidth: GitGraphDrawingParts.cherryStemLineWidth, lineJoin: .round))
            shapes.cherryFruits.fill(colors.background)
            shapes.labelPatches.fill(colors.background)
            ForEach(shapes.labelLines.indices, id: \.self) { index in
                let turned = shapes.labelLines[index]
                Text(verbatim: turned.line.text)
                    .font(turned.line.swiftUIFont)
                    .foregroundStyle(colors.muted)
                    .fixedSize()
                    .rotationEffect(.radians(turned.angle))
                    .position(turned.line.center)
            }
            shapes.tagBoxes.fill(colors.surface)
            shapes.tagBoxes.stroke(colors.border, style: StrokeStyle(lineWidth: GitGraphDrawingParts.tagLineWidth, lineJoin: .round))
            shapes.tagHoles.fill(colors.border)
            ReadingGitGraphTextLines(lines: shapes.textLines, color: colors.foreground)
        }
    }

    private func color(_ group: ReadingGitGraphShapes.ColorGroup) -> Color {
        ReadingDiagramColors.seriesColor(group.seriesIndex)
    }
}

/// The lines between commits: between lanes, then dashed to cherry-picks, then along lanes, each in its group's color.
private struct ReadingGitGraphConnectors: View {
    let groups: [ReadingGitGraphShapes.ColorGroup]

    var body: some View {
        let width = GitGraphDrawingParts.connectorLineWidth
        ZStack(alignment: .topLeading) {
            ForEach(groups.indices, id: \.self) { index in
                groups[index].curves.stroke(ReadingDiagramColors.seriesColor(groups[index].seriesIndex), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            ForEach(groups.indices, id: \.self) { index in
                groups[index].cherryPickCurves.stroke(ReadingDiagramColors.seriesColor(groups[index].seriesIndex),
                                                      style: StrokeStyle(lineWidth: width, lineCap: .round, dash: GitGraphDrawingParts.cherryPickDashLengths))
            }
            ForEach(groups.indices, id: \.self) { index in
                groups[index].straightLines.stroke(ReadingDiagramColors.seriesColor(groups[index].seriesIndex),
                                                   style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }
}

/// Lines of a Git graph's text, each centered where the layout put it, in one color.
private struct ReadingGitGraphTextLines: View {
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
