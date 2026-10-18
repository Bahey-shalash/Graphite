# Progress

Snapshot: b13dec3 (main, 2026-10-18).

The cleanup log, newest step last. One row per landed step: the date, what moved (old type or file → new), the findings it answers, the checks before and after (test count, `scripts/size-report.py` summary line, platform builds run, and the `FR-101` benchmark results), and the commit. A step that regresses a budget beyond its tolerance does not land (`FR-102`). A step is logged only after it lands on `main`; its claims are checked against the code before `status.md` and `rule-status.md` change.

| Date | Step | What moved | Findings answered | Checks before → after | Commit |
| --- | --- | --- | --- | --- | --- |
| 2026-10-18 | Audit | Nothing in the code moved. `Docs/solid/` and `scripts/size-report.py`, `scripts/solid-metrics.py` were written from snapshot b13dec3. | — | Baseline: 2,310 XCTest functions and 85 JavaScript tests (counted, not run); `size-report.py`: 285 items over a threshold, 70 reviewed, 215 without a review row | (the commit that adds `Docs/solid/`) |
| 2026-10-18 | Phase 0: `BUG-MDCORE-01` | `NotePreviewDocument.sections(of:)` applies the nesting guard before parsing | `BUG-MDCORE-01`; rule `FR-68` (a guard every caller must remember lives at one boundary) | `NotePreviewDocumentTests` and `CrashLoopRegressionTests`: 27 pass (new test failed before the fix); `size-report.py` unchanged (285 items, 70 reviewed); no platform build; no benchmark exists yet (`FR-101`) | `1798e2c` |
| 2026-10-18 | Phase 0: `BUG-RUNTIME-01` | Plugin runtime: each command and each newly focused note gets its own `SnapshotEditor` | `BUG-RUNTIME-01`; `FR-12`, `FR-28` | Node runtime suite: 68 pass, 18 skipped as before (new test failed before the fix with `Second.md`); no Swift build | `1f45079` |
| 2026-10-18 | Phase 0: `BUG-VOICE-V01`, `BUG-VOICE-L01` | `ReadAloudPronunciations.readVaultFile` returns a typed `VaultFileReading`; the Settings editor refuses to rewrite a file it did not fully read | `BUG-VOICE-V01`, `BUG-VOICE-L01`; `FR-59`, `FR-61` | `ReadAloudPronunciation*` tests: 17 pass (written with the new reader, not seen failing on the old code); `swift build --target GraphiteUI` compiles | `a31ce63` |
| 2026-10-18 | Phase 0: `BUG-CANVAS-01` | `CanvasUndoManager` commits the pending text edit before every undo and redo | `BUG-CANVAS-01`; `FR-04` | `CanvasSessionTests` all pass (new test failed before the fix); not checked on a device | `6cb0377` |
| 2026-10-18 | Phase 0: `BUG-SHELL-03` | `QuitSaveDecision` decides the Mac quit reply from the save outcome; `GraphiteApplicationDelegate` performs it | `BUG-SHELL-03` (alias `BUG-ARCH-02`); `FR-05`, `FR-60` | `QuitSaveDecisionTests`: 4 pass (2 failed against the old always-quit rule); real ⌘Q not tried on a Mac | `e4feaa1` |

## How a wave is logged

1. Before the wave: record the test count, the full `size-report.py` summary line, which platform builds ran (iPad simulator, iPhone simulator, Mac) and the benchmark results.
2. Land the wave as small commits on a descriptively named branch (for example `extract-vault-session-lifecycle`), each passing the full suite, the platform build and `size-report.py`.
3. After it lands: add one row here per step; update [status.md](status.md) and [rule-status.md](rule-status.md) with evidence from the current code. The wave's own report is a lead, never proof.
