# Editor scrolling: jumps, lag and memory: TODO

Created: 2026-10-21. Issue: [#57](https://github.com/Graphite-Note/Graphite/issues/57).

Status: the block heights and the canvases are fixed and measured (2026-10-21); the items below are open. A Live Preview note is text plus one SwiftUI view per rendered block (tables, formulas, callouts, embeds, properties). Scrolling a long note jumps, stutters and grows memory on the Mac, the iPad and the iPhone.

## Request

The owner, 2026-10-21: scrolling in a Markdown note is "jumpy, laggy and causes huge memory spikes" on macOS, iOS and iPadOS; keep working on it, especially on the iPad.

## Measured so far

`PerformanceBenchmarkTests.testOpeningScrollingAndTypingInALongNote` (a 40-section lecture note, steps of 40 % of an 834 by 1,210 point window, down to the end and back up, three runs). Since 2026-10-21 it also reports jumps: before each step it takes the line at the middle of the screen, and after the step it records how far that line moved beyond the distance scrolled (`note-scroll-jumps`, `-down`, `-up`).

Before any change (main d93d23ca), runs 2 and 3:

| | Mac (Release) | iPad simulator (Release) |
| --- | --- | --- |
| Jumps over 50 pt per run | 9 | 6–7, scrolling down |
| Largest jump | 377 pt (996 pt in the first run) | 437 pt |
| Frames over 16 ms, of about 175 (Mac) or 190 (iPad) | 60–62 | 75–78 |
| Frame 95th percentile | 27 ms | 41–51 ms |
| Memory growth scrolling down | 217–228 MB (368 MB in the first run) | 33–37 MB |

Found: TextKit 2 estimates the height of text it has not laid out from ordinary line heights, without the height reserved under each block's last line, so the note starts at half its height (20,528 pt, 40,702 pt once laid out) and moves as text is laid out; blocks reserve an estimate until their view reports its height, and nothing kept the screen in place when a block above it changed height; the same jumps repeat in every run at the same places, so the measured-height cache does not prevent them; emptying the kept-views pool after scrolling down freed only 23–52 MB of the Mac's 430–480 MB.

## Scope

Issue: [#57](https://github.com/Graphite-Note/Graphite/issues/57)

- [x] Jumps: a block's view takes the height its lines reserve the first time it shows, from the second time it is shown on. Done 2026-10-21: a new view of a block measured before keeps the measured height until its own reports settle (`MarkdownEditorStyling.newViewHeightSettlingDelay`, `LivePreviewRenderedBlocks.isNewViewOfMeasuredBlock`); in runs 2 and 3 of the benchmark no block changed height, against 360 restyles before; jumps over 50 pt per run 9 → 2 on the Mac and 6–7 → 2 in the iPad simulator (`Coverage.md`, "Scrolling a long note"). Not checked by hand or on a device.
- [x] Memory: no SwiftUI `Canvas` in a note's rendered blocks, which started RenderBox's Metal device (about 200 MB while scrolling). Done 2026-10-21: Textual patch 19 and SwiftUIMath patch 5 (formulas as glyph outlines); Mac growth scrolling down 217–228 → 71–78 MB, peak 452–488 → 273–308 MB; renders compared with the canvas versions; `AppProjectTextualPatchTests` and the Live Preview classes pass. Not checked on a physical iPad, where the graphics memory counts.
- [ ] ~~Jumps: a block above the top of the screen that takes another height does not move what is on screen (scroll anchoring).~~ Dropped 2026-10-21: AppKit already keeps the visible text in place when text above it changes height, and the correction doubled it (more jumps on the Mac).
- [ ] Jumps: the text at the very top of the note keeps its place (TextKit's estimate of the text above the viewport): the two jumps left per run, 377 pt on the Mac, 193 pt on the iPad.
- [ ] Jumps: the first time a note's blocks are shown, their heights are close to right (better estimates, or measuring blocks just below the screen while the note is idle): 4 jumps over 50 pt in the first run, up to 1,149 pt.
- [ ] Lag: a block's view is ready before it scrolls into view, so building it does not fall in a frame; frames over 16 ms (Mac 40–43 down, iPad 34–41 down of about 95) and the 95th percentile measured down on the iPad, the Mac and the iPhone.
- [ ] Memory: the GPU allocation of about 128 MB the first time a note scrolls in a process (reclaimable afterwards), and the 140 MB of heap held after scrolling the note down, found and bounded; memory kept after closing a note returns.
- [ ] iPhone: the same benchmark on an iPhone simulator, before and after.
- [ ] Checked by hand in the app on the iPad (finger and trackpad), the Mac (trackpad) and the iPhone, on a long note with tables, formulas, callouts and pictures; and on a physical iPad for memory.
- [ ] The PDF export's `NotePDFRendererTests` and `NotePDFExportHostedTests` pass with formulas drawn as outlines, once the export is on main.
- [ ] `Coverage.md`, `Architecture.md` and `Docs/solid/invariants.md` updated as the items land; `python3 scripts/size-report.py` passes.

## Decisions

- PDFs stay with PDFKit as Apple ships it: no private switches for its page analysis or GPU tiles, even though they cause a 345 MB peak when a PDF opens on the Mac (owner, 2026-10-21; measured in `Coverage.md`, "A small core").
- Fixes use public API only (owner, 2026-10-21).
- Benchmarks of the iPad run through `scripts/run-hosted-suite-silently.sh`, one build at a time, with simulators shut down after each run (the owner's no-sound rule).
