# Progress

Snapshot: b13dec3 (main, 2026-10-18).

The cleanup log, newest step last. One row per landed step: the date, what moved (old type or file → new), the findings it answers, the checks before and after (test count, `scripts/size-report.py` summary line, platform builds run, and the `FR-101` benchmark results), and the commit. A step that regresses a budget beyond its tolerance does not land (`FR-102`). A step is logged only after it lands on `main`; its claims are checked against the code before `status.md` and `rule-status.md` change.

| Date | Step | What moved | Findings answered | Checks before → after | Commit |
| --- | --- | --- | --- | --- | --- |
| 2026-10-18 | Audit | Nothing in the code moved. `Docs/solid/` and `scripts/size-report.py`, `scripts/solid-metrics.py` were written from snapshot b13dec3. | — | Baseline: 2,310 XCTest functions and 85 JavaScript tests (counted, not run); `size-report.py`: 285 items over a threshold, 70 reviewed, 215 without a review row | (the commit that adds `Docs/solid/`) |
| 2026-10-19 | Writing feel (branch `writing-feel-device`, not on `main`) | Pen-up on a PDF page: `PencilDrawingChange(appendingLastStrokeOf:to:)`, `PDFPageInkTracker.updateAppending`, the append-only path of `PDFPageManager.applyInkUpdate`, `GraphitePDFView.hideInkAnnotations(named:on:)`. Width at zoom: `PDFPageOverlayView.largestRenderingScale(keepingWidthOf:)`, `HistoryCanvasView.prepareToDraw(with:)`, `InfiniteCanvasView.toolForDrawing`. `PaletteToolCorrection` → `PaletteToolFollower` (the canvas no longer observes the palette). New debug-only `PencilWritingTrace`. | `FR-104` (pen-up), `CC-INK-03` (one next-turn hop gone) | Pen-up on a 2,000-stroke page, main-thread time of `canvasViewDrawingDidChange`, iPad Pro 11-inch (M5) simulator, Debug, 40 strokes: median 16.3 ms → 2.1 ms, p90 17.8 → 2.5 ms (hosted probe; the iPad measurement is in `Docs/Goodnotes-writing-feel.md`, Experiments). Hosted suite on that simulator: 358 tests, 5 skipped, 0 failures after. `size-report.py`: 285 items over a threshold, 70 reviewed, 215 without a review row, before and after. | 52393d3, 9998327, 5602430, 3c20a95 |

## How a wave is logged

1. Before the wave: record the test count, the full `size-report.py` summary line, which platform builds ran (iPad simulator, iPhone simulator, Mac) and the benchmark results.
2. Land the wave as small commits on a descriptively named branch (for example `extract-vault-session-lifecycle`), each passing the full suite, the platform build and `size-report.py`.
3. After it lands: add one row here per step; update [status.md](status.md) and [rule-status.md](rule-status.md) with evidence from the current code. The wave's own report is a lead, never proof.
