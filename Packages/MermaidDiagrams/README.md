# MermaidDiagrams

Reads [Mermaid](https://mermaid.js.org) diagram text, lays the diagram out and draws it with Core Graphics and Core Text, in the visual style of [Pele](https://github.com/obsidianmd/pele), Obsidian's Mermaid renderer. It knows no app: fonts, colors and limits are parameters, and it reads and writes no file.

Graphite's plan for it is `Docs/Native-diagrams-todo.md`; the decisions that shaped it are recorded there.

## Diagram types

| Type | State |
| --- | --- |
| Flowchart (`flowchart`, `graph`) | The model: nodes in the classic shapes, edges with their strokes, marks, lengths and labels, groups. |

## Public API

- `FlowchartDiagram`, `FlowchartNode`, `FlowchartNodeShape`, `FlowchartEdge` (with `FlowchartEdgeStroke` and `FlowchartArrowhead`), `FlowchartSubgraph`, `FlowchartDirection`: a flowchart as its text describes it.
- `DiagramLabel`: the text of a node, an edge or a group as plain lines, drawn as the characters they hold.

## What the package does not do

It imports Foundation, CoreGraphics and CoreText only: no UIKit, AppKit or SwiftUI. It reads and writes no file.

## Tests

`swift test --package-path Packages/MermaidDiagrams`.
