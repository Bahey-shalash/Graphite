# MermaidDiagrams

Reads [Mermaid](https://mermaid.js.org) diagram text, lays the diagram out and draws it with Core Graphics and Core Text, in the visual style of [Pele](https://github.com/obsidianmd/pele), Obsidian's Mermaid renderer. It knows no app: fonts, colors and limits are parameters, and it reads and writes no file.

Graphite's plan for it is `Docs/Native-diagrams-todo.md`; the decisions that shaped it are recorded there.

## Diagram types

| Type | State |
| --- | --- |
| Flowchart (`flowchart`, `graph`) | Drawn. Laid out in ranks, without subgraphs yet. Read: the direction, nodes in the classic shapes (by bracket or `@{ shape: … }`), quoted and Markdown text, entity codes, edges with their strokes, marks, lengths and labels, chains and `&`, groups, `accTitle` and `accDescr`. Styles and `click` are counted and not applied. |
| Pie chart (`pie`) | Drawn: slices clockwise from the top in the series colors, percentages inside or outside the rim, the legend on the right, the title above. Read: `showData`, `title`, `accTitle`, `accDescr`, slices (`"label" : value`). The front matter's `config` options are not applied. |

## Public API

- `MermaidDiagramReader.read(_:limits:)` reads a diagram's text and returns a `MermaidDiagram` (one case per type read), or throws a `MermaidDiagramReadError`: no diagram, a type not read yet (by its keyword), a syntax problem with its line (`MermaidSyntaxProblem`), or a limit passed.
- `MermaidDiagramLimits`: the bounds a diagram is read and laid out within.
- `FlowchartLayoutEngine.layout(_:typography:limits:)` lays a flowchart out and returns a `FlowchartLayout`: its size, and each node's shape, frame and text, each edge's path, marks and text, and the title, on a page whose y runs down. It throws `FlowchartLayoutError` for a flowchart with subgraphs or one past the layout limit.
- `DiagramTypography(font:)`: the measurers of a `DiagramFont` (the system font or one by PostScript name), made once and used for every diagram in that font. `CoreTextDiagramTextMeasurer` measures with Core Text; `DiagramTextMeasuring` is what the layout measures with.
- `DiagramTextBlock`, `DiagramPath` (with `DiagramPathSegment`) and `DiagramEdgeMark`: placed text, lines and edge marks.
- `FlowchartDrawingParts(layout:)` groups a layout's geometry by how it is painted: Core Graphics paths for the solid, thick and dotted edges, the filled and stroked marks, the patches behind edge text, the node fills and the node outlines, with the text blocks; a view paints them with its own shapes and colors.
- `FlowchartRenderer.draw(_:in:palette:)` paints those parts into a `CGContext` whose y runs down, in a `DiagramPalette` (Pele's color roles: background, foreground, line, surface, border). It parses and measures nothing, so a change of colors only draws again.
- `FlowchartDiagram`, `FlowchartNode`, `FlowchartNodeShape`, `FlowchartEdge` (with `FlowchartEdgeStroke` and `FlowchartArrowhead`), `FlowchartSubgraph`, `FlowchartDirection`: a flowchart as its text describes it.
- `DiagramLabel`: the text of a node, an edge or a group as plain lines, drawn as the characters they hold.
- `PieChart` (with `PieChartSlice`): a pie chart as its text describes it. `PieChartLayoutEngine.layout(_:typography:)` returns a `PieChartLayout` (the pie's center and radius, each drawn slice's angles and percentage, the legend's swatches and labels, the title); `PieChartDrawingParts(layout:)` groups it by how it is painted, one fill per series color; `PieChartRenderer.draw(_:in:palette:)` paints it, the slices in `DiagramPalette.series`.

## Limits

`MermaidDiagramLimits.standard` bounds the text to 50,000 UTF-8 bytes (Mermaid's default), a diagram to 5,000 nodes and 5,000 edges (Pele's edge limit; `A & B --> C & D` makes four edges, so a short text can ask for many), and the layout to 50,000 points. Each count is checked before anything of that count is made, and a diagram past a limit fails with a typed error.

## Layout

A layered layout (Sugiyama's method) on plain values: the edges that close cycles are turned around, nodes get ranks by their longest path (a node no edge enters moves down next to its successor), an edge spanning several ranks passes through a point in each rank between, an edge's text gets a rank of its own between the ranks of nodes, the order across each rank comes from sweeps that sort by the neighbours' mean position, keeping the order with the fewest crossings, and positions across come from a weighted isotonic regression per rank, solved exactly by pooling adjacent violators, then straightened along long edges. The measurements are Pele's: 40 points between nodes, 48 between ranks, 18 and 12 points of padding around a node's text, text wrapped at 200 points and an edge's text seven eighths of the nodes'. Edges meeting a side of a node spread along it, 20 points apart where the side has room, and meet the shape's outline.

## What the package does not do

It imports Foundation, CoreGraphics and CoreText only: no UIKit, AppKit or SwiftUI. It reads and writes no file.

## Credits

The visual style, the spacing and the shapes' geometry follow [Pele](https://github.com/obsidianmd/pele) (MIT licensed, `PELE-LICENSE`). The code is written for this package.

## Tests and benchmark

`swift test --package-path Packages/MermaidDiagrams`. `FlowchartCorpusTests` reads and lays out Mermaid's 114 flowchart documentation examples and Pele's generated trees and meshes.

`swift run -c release --package-path Packages/MermaidDiagrams MermaidDiagramsBenchmark` times reading, layout, the drawing parts and painting, with the median and 99th percentile per diagram, and the heap a layout holds, on the inputs of Pele's benchmark (`FlowchartCorpus`; the documentation examples are its resources). Graphite records the results in its `Docs/Coverage.md`.
