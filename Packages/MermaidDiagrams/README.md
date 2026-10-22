# MermaidDiagrams

Reads [Mermaid](https://mermaid.js.org) diagram text, lays the diagram out and draws it with Core Graphics and Core Text, in the visual style of [Pele](https://github.com/obsidianmd/pele), Obsidian's Mermaid renderer. It knows no app: fonts, colors and limits are parameters, and it reads and writes no file.

Graphite's plan for it is `Docs/Native-diagrams-todo.md`; the decisions that shaped it are recorded there.

## Diagram types

| Type | State |
| --- | --- |
| Flowchart (`flowchart`, `graph`) | Drawn. Laid out in ranks, without subgraphs yet. Read: the direction, nodes in the classic shapes (by bracket or `@{ shape: … }`), quoted and Markdown text, entity codes, edges with their strokes, marks, lengths and labels, chains and `&`, groups, `accTitle` and `accDescr`. Styles and `click` are counted and not applied. |
| Mindmap (`mindmap`) | Drawn, Pele's way: the root in the middle, branches to its right and left in the series colors. Read: the tree from indentation, every shape (`[ ]`, `( )`, `(( ))`, `) (`, `)) ((`, `{{ }}`, none), quoted and Markdown text, `%%` comments, `accTitle` and `accDescr` (not in Mermaid's mindmap grammar). Icons and classes are counted and not drawn. |
| Timeline (`timeline`) | Drawn, Pele's way: across, or down for `timeline TD`, periods and sections in the series colors. Read: `title`, `section`, periods with their events on their line and the lines after, `accTitle` and `accDescr`, `%%` and `#` comments; only `<br>` is markup in the text. Front matter configuration (`disableMulticolor`) is not read. |

## Public API

- `MermaidDiagramReader.read(_:limits:)` reads a diagram's text and returns a `MermaidDiagram` (one case per type read), or throws a `MermaidDiagramReadError`: no diagram, a type not read yet (by its keyword), a syntax problem with its line (`MermaidSyntaxProblem`), or a limit passed.
- `MermaidDiagramLimits`: the bounds a diagram is read and laid out within.
- `FlowchartLayoutEngine.layout(_:typography:limits:)` lays a flowchart out and returns a `FlowchartLayout`: its size, and each node's shape, frame and text, each edge's path, marks and text, and the title, on a page whose y runs down. It throws `FlowchartLayoutError` for a flowchart with subgraphs or one past the layout limit.
- `DiagramTypography(font:)`: the measurers of a `DiagramFont` (the system font or one by PostScript name), made once and used for every diagram in that font. `CoreTextDiagramTextMeasurer` measures with Core Text; `DiagramTextMeasuring` is what the layout measures with.
- `DiagramTextBlock`, `DiagramPath` (with `DiagramPathSegment`) and `DiagramEdgeMark`: placed text, lines and edge marks.
- `FlowchartDrawingParts(layout:)` groups a layout's geometry by how it is painted: Core Graphics paths for the solid, thick and dotted edges, the filled and stroked marks, the patches behind edge text, the node fills and the node outlines, with the text blocks; a view paints them with its own shapes and colors.
- `FlowchartRenderer.draw(_:in:palette:)` paints those parts into a `CGContext` whose y runs down, in a `DiagramPalette` (Pele's color roles: background, foreground, line, surface, border). It parses and measures nothing, so a change of colors only draws again.
- `MindmapLayoutEngine.layout(_:typography:)` lays a mindmap out (`MindmapLayout`: each node's outline, frame, text and branch, each link's path and branch, the title); `MindmapDrawingParts(layout:)` groups it by branch for painting, and `MindmapRenderer.draw(_:in:palette:)` paints it, each branch in `DiagramPalette.seriesColor(_:)`. `MindmapDiagram`, `MindmapNode` and `MindmapNodeShape` are a mindmap as its text describes it.
- `TimelineLayoutEngine.layout(_:typography:)` lays a timeline out (`TimelineLayout`: sections, periods with their dots, lines and events, the axis and its arrow, the title); `TimelineDrawingParts(layout:)` groups it by color, and `TimelineRenderer.draw(_:in:palette:)` paints it. `TimelineDiagram`, `TimelinePeriod` and `TimelineDirection` are a timeline as its text describes it.
- `FlowchartDiagram`, `FlowchartNode`, `FlowchartNodeShape`, `FlowchartEdge` (with `FlowchartEdgeStroke` and `FlowchartArrowhead`), `FlowchartSubgraph`, `FlowchartDirection`: a flowchart as its text describes it.
- `DiagramLabel`: the text of a node, an edge or a group as plain lines, drawn as the characters they hold.

## Limits

`MermaidDiagramLimits.standard` bounds the text to 50,000 UTF-8 bytes (Mermaid's default), a diagram to 5,000 nodes and 5,000 edges (Pele's edge limit; `A & B --> C & D` makes four edges, so a short text can ask for many), and the layout to 50,000 points. Each count is checked before anything of that count is made, and a diagram past a limit fails with a typed error.

## Layout

A layered layout (Sugiyama's method) on plain values: the edges that close cycles are turned around, nodes get ranks by their longest path (a node no edge enters moves down next to its successor), an edge spanning several ranks passes through a point in each rank between, an edge's text gets a rank of its own between the ranks of nodes, the order across each rank comes from sweeps that sort by the neighbours' mean position, keeping the order with the fewest crossings, and positions across come from a weighted isotonic regression per rank, solved exactly by pooling adjacent violators, then straightened along long edges. The measurements are Pele's: 40 points between nodes, 48 between ranks, 18 and 12 points of padding around a node's text, text wrapped at 200 points and an edge's text seven eighths of the nodes'. Edges meeting a side of a node spread along it, 20 points apart where the side has room, and meet the shape's outline.

## What the package does not do

It imports Foundation, CoreGraphics and CoreText only: no UIKit, AppKit or SwiftUI. It reads and writes no file.

## Credits

The visual style, the spacing and the shapes' geometry follow [Pele](https://github.com/obsidianmd/pele) (MIT licensed, `PELE-LICENSE`). The code is written for this package.

## Tests and benchmark

`swift test --package-path Packages/MermaidDiagrams`. `FlowchartCorpusTests` reads and lays out Mermaid's 114 flowchart documentation examples and Pele's generated trees and meshes; `MindmapCorpusTests` Mermaid's 13 mindmap examples and generated trees; `TimelineCorpusTests` Mermaid's 14 timeline examples and generated timelines.

`swift run -c release --package-path Packages/MermaidDiagrams MermaidDiagramsBenchmark` times reading, layout, the drawing parts and painting, with the median and 99th percentile per diagram, and the heap a layout holds, on the inputs of Pele's benchmark (`FlowchartCorpus`; the documentation examples are its resources), then mindmaps (`MindmapBenchmark` on `MindmapCorpus`) and timelines (`TimelineBenchmark` on `TimelineCorpus`). Graphite records the results in its `Docs/Coverage.md`.
