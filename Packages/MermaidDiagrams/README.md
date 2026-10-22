# MermaidDiagrams

Reads [Mermaid](https://mermaid.js.org) diagram text, lays the diagram out and draws it with Core Graphics and Core Text, in the visual style of [Pele](https://github.com/obsidianmd/pele), Obsidian's Mermaid renderer. It knows no app: fonts, colors and limits are parameters, and it reads and writes no file.

Graphite's plan for it is `Docs/Native-diagrams-todo.md`; the decisions that shaped it are recorded there.

## Diagram types

| Type | State |
| --- | --- |
| Flowchart (`flowchart`, `graph`) | Read: the direction, nodes in the classic shapes (by bracket or `@{ shape: … }`), quoted and Markdown text, entity codes, edges with their strokes, marks, lengths and labels, chains and `&`, groups, `accTitle` and `accDescr`. Styles and `click` are counted and not applied. |

## Public API

- `MermaidDiagramReader.read(_:limits:)` reads a diagram's text and returns a `MermaidDiagram` (one case per type read), or throws a `MermaidDiagramReadError`: no diagram, a type not read yet (by its keyword), a syntax problem with its line (`MermaidSyntaxProblem`), or a limit passed.
- `MermaidDiagramLimits`: the bounds a diagram is read within.
- `FlowchartDiagram`, `FlowchartNode`, `FlowchartNodeShape`, `FlowchartEdge` (with `FlowchartEdgeStroke` and `FlowchartArrowhead`), `FlowchartSubgraph`, `FlowchartDirection`: a flowchart as its text describes it.
- `DiagramLabel`: the text of a node, an edge or a group as plain lines, drawn as the characters they hold.

## Limits

`MermaidDiagramLimits.standard` bounds the text to 50,000 UTF-8 bytes (Mermaid's default), a diagram to 5,000 nodes and 5,000 edges (Pele's edge limit; `A & B --> C & D` makes four edges, so a short text can ask for many), and the layout to 50,000 points. Each count is checked before anything of that count is made, and a diagram past a limit fails with a typed error.

## What the package does not do

It imports Foundation, CoreGraphics and CoreText only: no UIKit, AppKit or SwiftUI. It reads and writes no file.

## Tests

`swift test --package-path Packages/MermaidDiagrams`.
