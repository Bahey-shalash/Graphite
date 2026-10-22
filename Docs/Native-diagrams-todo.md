# Native Mermaid diagrams: implementation TODO

Created: 2026-10-18.

Status: not started. Nothing below is implemented; `Docs/Obsidian-mobile-gaps.md` still lists Mermaid diagrams as Missing (shown as code).

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

## Scope

Issue: [#48](https://github.com/Graphite-Note/Graphite/issues/48)

- [ ] Parsers for every Mermaid 12.1.0 diagram type Pele supports, tested against Mermaid's parser specs (`tests/compat` in Pele, MIT licensed), with differential testing against Pele's output.
- [ ] Layout engine in pure Swift: value types, no per-node class allocation, nothing on the main thread except drawing.
- [ ] Renderer drawing with Core Graphics and Core Text; SVG export for sharing and for files Obsidian reads.
- [ ] Theme from Graphite's appearance (light and dark, accent color, fonts), plus the colors an Obsidian theme or snippet sets with Pele's variables (`--pele-bg`, `--pele-accent`, `--pele-series-1` to `--pele-series-8`).
- [ ] Layout that adapts to the pane width (iPhone, iPad split view, Mac windows).
- [ ] Reading view and Live Preview render ` ```mermaid ` blocks; Live Preview shows the source when the cursor enters the block, as other blocks do.
- [ ] Safety as in Pele: diagram text is escaped, links and styles filtered, source and output size limited. A diagram that fails to parse shows the error and its source, never a crash.
- [ ] A benchmark test target that runs the comparison above and fails when a target is missed.
- [ ] `Architecture.md`, `Coverage.md` and the gaps list updated once each part is built and tested.

## Open questions

- One Swift module per diagram type, loaded only when a note uses it, or one module? Affects the size target.
- Match Pele's visual style exactly, so a vault looks the same in Obsidian and Graphite, or use Graphite's own?
