# Native Mermaid diagrams: implementation TODO

Created: 2026-10-18.

Status: started 2026-10-22 on the branch `native-diagrams`. The decisions below unblock the first slice, the flowchart drawn natively in the reading view; nothing in the scope is ticked yet, and `Docs/Obsidian-mobile-gaps.md` still lists Mermaid diagrams as Missing (shown as code).

## Request

Recreate [Pele](https://github.com/obsidianmd/pele) in Swift so Mermaid diagrams render natively on iOS, iPadOS and macOS. Pele is Obsidian's Mermaid renderer, written in TypeScript. It reads every diagram type built into Mermaid 12.1.0, uses its own layout and visual style, and draws SVG. Its README claims, as given by the owner:

- 100–500× faster than mermaid.js
- 6× smaller bundle
- No dependencies
- Easy to theme
- Responsive to device width

| Pele (TypeScript) | Value |
|---|---|
| Bundle size | 230 kB |
| Render time | 0.05–0.3 ms |
| Dependencies | 0 |

Because Graphite's version is native, it has to beat these numbers by a wide margin, not match them.

## Performance targets

Targets to meet before the feature counts as done. Each number is measured, never estimated, and recorded in `Coverage.md` with the machine, the build configuration (Release) and the input set.

| Metric | Pele | Graphite target | Stretch |
|---|---|---|---|
| Render time, parse + layout, per diagram | 0.05–0.3 ms | 10× faster: 5–30 µs | 50× faster: 1–6 µs |
| Size added to the app binary, all diagram types | 230 kB | 4× smaller: ≤ 60 kB per architecture | ≤ 30 kB |
| Dependencies | 0 | 0: no WebKit, no JavaScriptCore, no Swift packages | |
| Drawing on screen | SVG in the DOM | Core Graphics / Core Text on the main thread, no dropped frames while scrolling a note full of diagrams | |
| Memory per diagram | not stated | ≤ 64 kB for layout data of a typical diagram | |
| Theme change | CSS variables, no re-render | Redraw with the new colors without parsing or laying out again | |
| Width change | Layout adapts to the container | Layout again only, without parsing again, within one frame | |

Rules for the comparison:

- Compare on the same inputs: Pele's benchmark set (`npm run bench`) and the diagrams of the Mermaid 12.1.0 specs, run on the same Mac. Pele's README gives no measuring method, so run its benchmark ourselves and record its numbers next to ours.
- Measure parse, layout and drawing separately, and report the median and the 99th percentile.
- Measure on the owner's iPad Pro M1 and an iPhone too, not only on the Mac.
- Measure binary size as the difference in the Release app's executable with and without the diagram module, per architecture.

## Decisions (2026-10-22)

1. **The code is a standalone package, `Packages/MermaidDiagrams`** (`Docs/solid/rewrite-foundations.md` section 3.5, `FR-110`), like `Packages/NotebookImport`. It reads Mermaid text, lays the diagram out and draws it into any `CGContext`, and knows nothing of Graphite: no vault, preference, logger or Graphite type, and limits and fonts are parameters. It imports Foundation, CoreGraphics and CoreText only (no UIKit, AppKit or SwiftUI), so it builds and tests alone on the Mac. Inside it: one folder per diagram type (`Flowchart/`: model and parser), and the parts the types share: `Layout/` (a layered graph layout over plain values, which the graph-shaped types such as state, class and ER diagrams will use too), `Text/` (label measuring and wrapping) and `Drawing/` (the renderer, given a palette of colors). Graphite's reading view is the one module that imports it.
2. **One package with one library, not one module per diagram type** (the first open question). Statically linked Swift code cannot be loaded on demand on iOS, so a module per type would save nothing at run time; the types share their layout, text and drawing code, which separate modules would duplicate or split further. The size target is met by keeping each type small and by dead-code stripping, measured as the targets above say.
3. **Pele's visual style, Graphite's fonts and colors** (the second open question). Shapes, their padding, the spacing between nodes and ranks, the arrowheads, the S-curved edges and the patch behind an edge label follow Pele, so a vault looks the same in Obsidian and in Graphite. The text is the note's font at the note's text size, and the colors come from the note's appearance: light or dark, and the vault theme's background, text and accent where it sets them. The `--pele-*` variables of an Obsidian theme or snippet stay in the theme item below.
4. **The first type is the flowchart** (`flowchart` and `graph`): the type notes use most, and the one most others build on, since state, class and ER diagrams are graphs laid out the same way. The first slice reads the direction, the classic node shapes (`[ ]`, `( )`, `([ ])`, `[[ ]]`, `[( )]`, `(( ))`, `((( )))`, `> ]`, `{ }`, `{{ }}`, `[/ /]`, `[\ \]`, `[/ \]`, `[\ /]`) and `@{ shape: … }` with those shapes' names, quoted and Markdown labels and entity codes, edges (arrow, open, dotted, thick, invisible, circle and cross ends, both ways, longer edges, labels in both syntaxes), chains and `&`, `%%` comments, and `accTitle` and `accDescr`. It reads but does not apply styles (`classDef`, `class`, `:::`, `style`, `linkStyle`) and `click`. A flowchart with a `subgraph` stays shown as code until clusters are laid out: drawn without its boxes, it would look complete and be wrong.
5. **The reading view draws it; the main actor only draws.** Core splits a ` ```mermaid ` fence into a block of its own, as it does a ` ```base ` fence, unless a community plugin draws `mermaid`. The reading view's builder, which already runs off the main actor, parses the diagram and lays it out at the note's text size. The view draws the result with Core Graphics and Core Text in a SwiftUI `Canvas`, with the colors of the moment, so a theme change redraws without parsing or laying out again. In this slice a diagram wider than the column is scaled down to fit; laying it out again for the width is the width item. A diagram type not drawn natively yet stays shown as code, as today, and a flowchart that cannot be read shows why under its source.
6. **Live Preview comes next, through the same view.** `LivePreviewBlockScanner` gets the same block kind, and `LivePreviewRenderedBlocks` draws the same diagram view over the concealed fence, showing the source when the cursor enters the block, as it does for math, bases and tables.
7. **Diagrams are part of the reading view, not a switchable feature.** The reading view is in the kernel (`rewrite-foundations.md` decision 16), and Obsidian has no switch for Mermaid either. Nothing is built at launch: the package does work only for a note that has a ` ```mermaid ` block, and its only state is the text measurer each reading build makes and drops (`FR-109`).

## Scope

- [ ] Parsers for every Mermaid 12.1.0 diagram type Pele supports, tested against Mermaid's parser specs (`tests/compat` in Pele, MIT licensed), with differential testing against Pele's output.
  - [x] The flowchart's parser (`flowchart`, `graph`, `flowchart-elk`), as decision 4 lists. Done 2026-10-22: `MermaidDiagramReader` (front matter, comments, the type keyword; other types named by their keyword) and `FlowchartParser` with its node, link and text syntaxes, over the UTF-8 bytes in one pass, every error a typed case with its line, text, nodes and edges bounded by `MermaidDiagramLimits`. Tests: `FlowchartParserTests` (29: every bracket shape, `@{ … }`, every link operator with marks and span, both label syntaxes, chains, `&`, edge identifiers, groups, style statements, comments, accessibility text, errors and limits), `MermaidDiagramReaderTests` (9), `DiagramLabelDecoderTests` (7), `FlowchartNodeShapeTests` and `FlowchartDirectionTests`. Fourteen examples of Mermaid's flowchart documentation were read by hand once, all as expected; that check is not in the suite.
  - [ ] The flowchart against Mermaid's flowchart parser specs (`tests/compat` in Pele) and differentially against Pele's output.
  - [ ] The other types.
- [ ] Layout engine in pure Swift: value types, no per-node class allocation, nothing on the main thread except drawing.
- [ ] Renderer drawing with Core Graphics and Core Text; SVG export for sharing and for files Obsidian reads.
- [ ] Theme from Graphite's appearance (light and dark, accent color, fonts), plus the colors an Obsidian theme or snippet sets with Pele's variables (`--pele-bg`, `--pele-accent`, `--pele-series-1` to `--pele-series-8`).
- [ ] Layout that adapts to the pane width (iPhone, iPad split view, Mac windows).
- [ ] Reading view and Live Preview render ` ```mermaid ` blocks; Live Preview shows the source when the cursor enters the block, as other blocks do.
- [ ] Safety as in Pele: diagram text is escaped, links and styles filtered, source and output size limited. A diagram that fails to parse shows the error and its source, never a crash.
- [ ] A benchmark test target that runs the comparison above and fails when a target is missed.
- [ ] `Architecture.md`, `Coverage.md` and the gaps list updated once each part is built and tested.

## Open questions

- ~~One Swift module per diagram type, loaded only when a note uses it, or one module? Affects the size target.~~ Answered by decision 2: one package.
- ~~Match Pele's visual style exactly, so a vault looks the same in Obsidian and Graphite, or use Graphite's own?~~ Answered by decision 3: Pele's style, Graphite's fonts and colors.
