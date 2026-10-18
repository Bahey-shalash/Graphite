# Clean code

Snapshot: b13dec3 (main, 2026-10-18).

This document merges the "Clean code" sections of the twelve area audits and the cross-cutting audit into one standard. It covers how functions, names, comments, errors, waiting, state, constants, duplication and tests are written. The area documents hold the full evidence; this page states the app-wide patterns, the worst offenders, the designs to imitate, the complete finding index and the rules new code must follow. All counts of findings come from [findings-index.md](../findings-index.md): 151 `CC-*` findings, 2 High, 70 Medium, 79 Low. All size and frequency numbers come from [metrics.md](../metrics.md) or from the area document cited beside them.

## 1. Verdict by area

| Area | Area verdict | High | Medium | Low | Total | Reason (numbers from the area's own verdict row) |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| [SHELL](../areas/shell.md) | Mixed | 0 | 6 | 4 | 10 | 29 functions over 40 code lines (`GraphiteRootView.body` 172); 82 assignments to one `errorMessage` string; sleeps as ordering or polling in 5 places; 11 pieces of logic written twice. |
| [EDITOR](../areas/editor.md) | Mixed | 0 | 4 | 7 | 11 | 13 functions over 40 code lines; 16 main-queue hops and 15 unowned `Task {}` in `NativeMarkdownEditor.swift`; 7 re-entrancy Booleans; 14 history comments; pure helpers small and tested. |
| [READING](../areas/reading.md) | Mixed | 0 | 4 | 6 | 10 | 18 functions over 40 code lines (largest 127); 8 sleeps, 2 used as layout ordering; 16 raw `localizedDescription` messages; failed index reads shown as empty lists. |
| [MDCORE](../areas/mdcore.md) | Mixed | 0 | 3 | 6 | 9 | 23 functions over 40 code lines (largest 176); 53 `try?` regular-expression constants that fail silently beside 2 `try!`; 9 history comments; one unguarded parser call. |
| [VAULT](../areas/vault.md) | Mixed | 0 | 3 | 7 | 10 | 13 functions over 40 code lines; frontmatter regular expression in 4 copies; SHA-256 hex in 5; 44 thrown English sentences in Core, Index and Apple code. |
| [BASES](../areas/bases.md) | Mixed | 0 | 4 | 6 | 10 | 29 functions over 40 code lines (largest 109); 17 owner-less view tasks and 2 hand-rolled generation counters; 7 static regular expressions built with `try?`. |
| [CANVAS](../areas/canvas.md) | Mixed | 0 | 3 | 6 | 9 | 10 functions over 40 code lines; drag state split over 1 enum and 4 loose fields; 3 loops driven by `Task.sleep`; English user text in Core. |
| [INK](../areas/ink.md) | Mixed | 0 | 8 | 7 | 15 | 11 functions over 40 code lines; 10 duplicated rules or constants; 3 correctness-bearing timing windows; 2 observers never removed; menu rebuilt on every layout pass while zooming. |
| [LECTURE](../areas/lecture.md) | Mixed | 0 | 7 | 8 | 15 | 19 functions over 40 code lines; 64 `try?`; 49 `Task {}` with no owner; 3 `asyncAfter` as timing; at least 10 incident comments. |
| [VOICE](../areas/voice.md) | Mixed | 0 | 10 | 5 | 15 | 19 functions over 40 code lines (`ReadAloudDocument.markdown` 273); 9 `Task.sleep` including one sleep-poll loop; 15 persisted keys in 8 files under 2 naming styles; 7 dead members. |
| [PLUGIN](../areas/plugin.md) | Mixed | 1 | 6 | 7 | 14 | 4 sleep-polling loops; 3 hand-made "first outcome wins" primitives; 251 lines of JavaScript and 28 of HTML/CSS in Swift strings; error kinds classified by message text. |
| [RUNTIME](../areas/runtime.md) | Mixed | 0 | 8 | 4 | 12 | 11 functions over 40 lines (longest 187); 81 lines over 160 characters; one error-text idiom copied 15 times; timers stand in for ordering in 6 places. |
| [ARCH](../cross-cutting/architecture.md) | Mixed | 1 | 4 | 6 | 11 | Errors travel as `String?` slots (208 `localizedDescription` uses; see Corrections); 20 of 63 sampled `try?` hide failures the user should see; 7 sleep-polling loops; no shared test support and no CI. |
| **All** | | **2** | **70** | **79** | **151** | |

**App-wide verdict.** Graphite's clean-code quality is Mixed everywhere and Weak nowhere: names follow RULES.md, most comments state precise invariants, and the pure decision helpers are small and tested in every area. What fails is the same five habits in every area — failures swallowed into silence or English prose, time used as a synchronisation mechanism, multi-state flows kept as loose Booleans, one rule implemented several times, and a test suite that is not hermetic, has no CI and is named after audit rounds — and these habits produce data-loss and stop-does-not-stop defects, not only style debt.

## 2. Systemic patterns across the whole app

Ordered by cost: patterns that lose or misreport user work first, then patterns that break Pencil and editor responsiveness or block safe cleanup, then readability debt.

### 2.1 Failures become silence, empty results or defaults

**What it is.** A failed write, save, safety copy or read is absorbed by `try?`, `?? []`, `?? 0` or a log line, and the code continues as if it had succeeded or as if there were nothing to read.

**Where.** Systemic in SHELL, ARCH, VAULT, READING, EDITOR, VOICE, RUNTIME, CANVAS, LECTURE, INK: `CC-ARCH-02`, `CC-SHELL-04`, `CC-VAULT-01`, `CC-READING-04`, `CC-EDITOR-09`, `CC-VOICE-11`, `CC-RUNTIME-06`, `CC-CANVAS-07`, `CC-LECTURE-14`, `CC-INK-07`. The same habit applied to constant patterns: `CC-MDCORE-01` (53 sites), `CC-BASES-03` (7 sites).

**Evidence.**
- The Mac quit path discards the save outcome: `try? await workspace.saveOpenDocuments()` and then allows termination ([GraphiteMacScenes.swift:55-56](../../../Sources/GraphiteUI/GraphiteMacScenes.swift#L55-L56)).
- Every Obsidian settings read turns any failure into "file missing": two `try?` in `configurationData` ([VaultStore.swift:254-257](../../../Sources/GraphiteCore/VaultStore.swift#L254-L257)), consumed by `bookmarks()` as "none" ([VaultStore.swift:177-180](../../../Sources/GraphiteCore/VaultStore.swift#L177-L180)).
- Backlinks show "none" when the index fails: `(try? await index.backlinks(to: note)) ?? []` ([WorkspaceMentions.swift:27](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L27)); an unknown file count counts as unique ([WorkspaceMentions.swift:64-65](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L64-L65)).
- A static regular expression that does not compile becomes `nil` and silently disables its feature ([MarkdownSemantics.swift:29](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L29), [BasePropertyEditing.swift:6](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L6)), while another constant pattern in the same file uses `try!` with a "covered by tests" comment ([MarkdownSemantics.swift:642-645](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L642-L645)).
- Scale: 628 `try?` in production Swift ([metrics.md](../metrics.md)); of 63 classified by reading in the workspace files, 20 should reach the user and none carries a same-line reason (`CC-ARCH-02`).

**Cost.** Lost or misreported work on the paths that matter most: BUG-SHELL-03 and BUG-ARCH-02 (Mac quit discards unsaved edits), BUG-ARCH-04 (text typed during a vault switch dropped), BUG-VAULT-02 (unreadable `bookmarks.json` shows as no bookmarks), BUG-SHELL-05 (File Recovery says "No Snapshots Yet" when its list cannot be read), BUG-PLUGIN-05 (a failed keychain read makes the next save erase other secrets). Destructive steps (`overwrite` deep link, restore, delete) proceed after their safety copy failed (`CC-SHELL-04`). The Read Aloud audio cache loses its size bound after one unreadable index (`CC-VOICE-11`).

**Fix direction.** Rules CC 1–CC 4: `try?` only where absence is the answer, with a same-line reason; reads return a typed `missing | contents | unreadable(Error)`; a destructive step stops when its backup fails; unreadable stored data is moved aside per element, as `VaultLibrary` already does.

### 2.2 Time stands in for ordering, and tasks have no owner

**What it is.** Code sleeps, polls or hops to the next run-loop turn to wait for other work instead of awaiting its completion; tasks are started and never stored or cancelled; each feature hand-writes its own "latest answer wins", debounce or "first outcome wins".

**Where.** Systemic in every Swift UI area and the runtime: `CC-ARCH-03`, `CC-ARCH-04`, `CC-ARCH-05`, `CC-SHELL-02`, `CC-SHELL-03`, `CC-EDITOR-02`, `CC-READING-02`, `CC-READING-06`, `CC-BASES-02`, `CC-CANVAS-02`, `CC-INK-03`, `CC-INK-14`, `CC-LECTURE-05`, `CC-VOICE-02`, `CC-VOICE-03`, `CC-PLUGIN-02`, `CC-PLUGIN-03`, `CC-RUNTIME-03`.

**Evidence.**
- Polling for other work: a deep link polls the index every 250 ms up to 40 times ([WorkspaceDeepLinks.swift:81-86](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L81-L86)); Read Aloud polls `isPreparing` 200 times at 50 ms and then acts whatever the state ([ReadAloudNavigator.swift:155-163](../../../Sources/GraphiteUI/ReadAloudNavigator.swift#L155-L163)); the plugin host polls a queued insertion 50 × 10 ms ([CommunityPluginHost.swift:711](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L711)) and infers a rename from the destination's existence for up to 10 s ([CommunityPluginHost.swift:928-933](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L928-L933)).
- Sleep as ordering: the template picker opens 250 ms after the palette closes ([GraphiteRootView.swift:470-474](../../../Sources/GraphiteUI/GraphiteRootView.swift#L470-L474)); the reading view scrolls, sleeps 50 ms, then reads a frame ([MarkdownPreview.swift:963-967](../../../Sources/GraphiteUI/MarkdownPreview.swift#L963-L967)), and follows the spoken word with up to three 80 ms sleeps ([MarkdownPreview.swift:987-992](../../../Sources/GraphiteUI/MarkdownPreview.swift#L987-L992)); a canvas-made stroke must arrive within a 1 s `asyncAfter` window ([HistoryCanvasView.swift:321-331](../../../Sources/GraphiteUI/HistoryCanvasView.swift#L321-L331)).
- A hand-made "first outcome wins" leaves its sleeping loser running on every call: two unstored tasks race a `send` against `Task.sleep(for: timeout)` ([CommunityPluginHost.swift:826-832](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L826-L832)); the stop path does the same with a 2-second sleeper ([CommunityPluginHost.swift:510-514](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L510-L514)).
- Scale: 51 sleeps and 10 `asyncAfter` in production; 429 unstructured `Task {}`/`Task.detached` ([metrics.md](../metrics.md)); 28 of 50 `Task.sleep` lines use `try?` and keep running after cancellation (`CC-ARCH-03`); about 13 hand-written debounces (`CC-ARCH-04`).

**Cost.** BUG-VOICE-01 and BUG-VOICE-02 (Stop does not stop: an unowned preparation task restarts reading), BUG-PLUGIN-03 (a refused rename reported as done), BUG-INK-03 (two taps on Rotate turn the picture once and leave two undo steps), BUG-PLUGIN-02 (a plugin load with no timeout blocks every later plugin). Every fixed delay is a guess that fails on a busy iPad, exactly when the Pencil is in use (`CC-INK-03`), and the hosted suite inherits the same flakiness (`CC-READING-02` cites a flaky reading-position test).

**Fix direction.** Rules CC 9–CC 11: await completion signals (`AsyncStream`, a continuation resumed by the session, `onDismiss`, the task's value); every task has an owner that cancels it; one tested `LatestRequest`, `Debouncer` and `withTimeout` on an injected clock. Two refinements recorded by the areas are part of the rule: a bounded backpressure wait on a dedicated media queue is allowed (`CC-LECTURE-12`), and UIKit's documented "after the current update" hop goes through one owned scheduler (`CC-EDITOR-02`).

### 2.3 Multi-state flows are loose Booleans, and outcomes ride on shared fields

**What it is.** A lifecycle with three or more phases is spread over Booleans, optionals, sentinel values and identity checks that must be set and reset together; a result is left in a field for a later callback to pick up.

**Where.** `CC-PLUGIN-01` (High), `CC-EDITOR-03`, `CC-LECTURE-07`, `CC-VOICE-12`, `CC-CANVAS-01`, `CC-INK-01`, `CC-INK-02`, `CC-LECTURE-13`; systemic in PLUGIN, EDITOR, LECTURE, VOICE, CANVAS and INK.

**Evidence.**
- The plugin runtime's six phases are `isRuntimeRunning` ([CommunityPluginHost.swift:194](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L194)), `isPageLoaded`, `pageLoadFailure` and `pageLoadWaiters` ([CommunityPluginHost.swift:269-271](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L269-L271)) plus four `webView === pluginWebView` checks ([CommunityPluginHost.swift:404-417](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L404-L417)); "stopping" has no representation, and `stopRuntime` resets 35 fields by hand before clearing the flag last ([CommunityPluginHost.swift:506-557](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L506-L557)).
- The iPad editor guards re-entrancy with seven Booleans ([NativeMarkdownEditor.swift:783](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L783), [811](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L811), [849](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L849), [857](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L857), [861](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L861), [873](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L873), [885](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L885)); `isPerformingEdit` is set and reset by hand in 5 places without `defer` (`CC-EDITOR-03`).
- The recording controller keeps `state` plus `pendingResume`, `isAbandoningRecorder`, `resumesWhenInterruptionEnds`, `isPublishing` and `startAttempt` ([RecordingController.swift:51-78](../../../Sources/GraphiteApple/RecordingController.swift#L51-L78)).
- Read Aloud playback is a 4-case `State` ([ReadAloudSpeech.swift:397](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L397)) plus `lacksWordTiming`, `requestIdentifier`, `utteranceStartOffset`, `needsRestart` and `wasSpeakingWhenInterrupted` ([ReadAloudSpeech.swift:409](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L409), [433-436](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L433-L436)); "finished while paused" is a sentinel offset (`CC-VOICE-12`).
- A shared field as a channel: `arrivingStroke` is written by `expect` and consumed by the next delegate callback ([HistoryCanvasView.swift:318-331](../../../Sources/GraphiteUI/HistoryCanvasView.swift#L318-L331)).

**Cost.** BUG-PLUGIN-01 (turning plugins off and on quickly leaves them off while the switch shows on). Impossible combinations are representable (`isRestoringStoredInk && !hasRestoredStoredInk`, `CC-LECTURE-7`), every guard must list the right subset, and an early return between set and reset leaves smart editing off for every keystroke (`CC-EDITOR-03`). The ink tracker advances before the edit is known to succeed, so a retry finds nothing to record (`CC-LECTURE-13`).

**Fix direction.** Rules CC 8 and CC 12: one enum with associated values per flow, changed only by intent methods (the PLUGIN, LECTURE, VOICE, CANVAS and INK documents each name the enum); scoped helpers with `defer` for "performing own edit"; outcomes returned, not parked in fields.

### 2.4 One rule, several implementations, already disagreeing

**What it is.** A rule, fact or small algorithm is written two to seven times; the copies drift.

**Where.** Every area: `CC-SHELL-05`, `CC-VAULT-03`, `CC-VAULT-04`, `CC-BASES-04`, `CC-BASES-05`, `CC-READING-08`, `CC-INK-04`, `CC-LECTURE-03`, `CC-CANVAS-06`, `CC-PLUGIN-08`, `CC-RUNTIME-02`, `CC-RUNTIME-09`, `CC-ARCH-08`, `CC-ARCH-10`, `CC-ARCH-11`, `CC-EDITOR-04`, `CC-VOICE-07`, `CC-MDCORE-02`, `CC-MDCORE-07`.

**Evidence.**
- The frontmatter regular expression exists four times, one copy byte-identical to another: [MarkdownSemantics.swift:29](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L29), [MarkdownSemantics.swift:625](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L625), [NoteProperties.swift:505](../../../Sources/GraphiteCore/NoteProperties.swift#L505), [BasePropertyEditing.swift:6](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L6).
- The conflict-copy name is built in four sessions, three with `" Graphite edits"` ([MarkdownSession.swift:227](../../../Sources/GraphiteUI/MarkdownSession.swift#L227), [CanvasSession.swift:392](../../../Sources/GraphiteUI/CanvasSession.swift#L392), [WorkspaceFileManagement.swift:218](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L218)) and one with a different format that appends a UUID ([PDFSession.swift:516](../../../Sources/GraphiteUI/PDFSession.swift#L516)).
- The 5-second plugin answer timeout is written as a literal 10 times in the host's extensions and once as the named `tapTimeout` ([CommunityPluginReadingBlocks.swift:58](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L58) against, e.g., [CommunityPluginViews.swift:75](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L75)).
- The iPad and Mac editors repeat about 14 function pairs (`CC-EDITOR-04`); two adapters each own the one audio session with separate flags (`CC-VOICE-07`).

**Cost.** Copies already disagree in shipped behaviour: BUG-LECTURE-03 (one page-number parser rejects non-ASCII digits), BUG-SHELL-06 (two tab-title rules), BUG-RUNTIME-04 (two default style layers), the media icon and alert titles (`CC-SHELL-05`), installer 404 handling (`CC-PLUGIN-08`), and fixes landing on one platform only (`CC-EDITOR-04`). In the editor's per-keystroke path the quadratic overlap test survives in one file after being fixed in two others (`CC-MDCORE-02`).

**Fix direction.** Rule CC 13: one owner per rule, the copies deleted; a deliberate fast mirror keeps a parity test, as `NoteFolding.isListItem` does against `MarkdownEditing.listLine` (MDCORE "What to keep" row 8). Rule CC 14 for iPad/Mac pairs.

### 2.5 The test suite is not hermetic, has no CI and is named after audit rounds

**What it is.** Tests share the process's preferences and the developer's caches, wait with sleeps, assert on English text, live in files named after fix rounds, and are run by hand only.

**Where.** `CC-ARCH-09` (High), `CC-SHELL-09`, `CC-VAULT-10`, `CC-BASES-10`, `CC-MDCORE-06`, `CC-EDITOR-11`, `CC-READING-10`, `CC-LECTURE-10`, `CC-INK-15`, `CC-CANVAS-03`, `CC-RUNTIME-05`.

**Evidence.**
- Four package test targets ([Package.swift:40-43](../../../Package.swift#L40-L43)), no shared test-support target, and no CI configuration (no `.github` folder in the snapshot).
- The workspace tests snapshot and restore the whole `Graphite*` domain of `UserDefaults.standard` and delete real index caches ([UiWorkspaceModelFixTests.swift:17-37](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L17-L37)) and poll every 10 ms ([UiWorkspaceModelFixTests.swift:57-66](../../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L57-L66)); a hosted test removes a real preference key without restoring it ([PicturesAndPaperTests.swift:23](../../../App/Tests/PicturesAndPaperTests.swift#L23)).
- `waitUntil` is redefined privately 22 times in 21 hosted test files (and 17 more times in package test files), e.g. [CanvasTests.swift:422](../../../App/Tests/CanvasTests.swift#L422) and [PicturesAndPaperTests.swift:1037](../../../App/Tests/PicturesAndPaperTests.swift#L1037).
- A test asserts on two English phrases of an error ([CanvasSessionTests.swift:396-397](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L396-L397)).
- 27 test files are named after fix rounds: 24 `*FixTests` and 3 `*RegressionTests` (`list_files`; see Corrections). Tests sleep 173 times in `App/Tests` and 76 in `Tests/GraphiteUITests`; `UserDefaults.standard` appears 75 and 26 times ([metrics.md](../metrics.md)).

**Cost.** No cleanup wave can prove it kept behaviour: tests cannot run without touching the developer's preferences and indexes, no contract runs against a fake and a real adapter, recorded results cannot be reproduced, and the tests that pin a type cannot be found by its name. Wording edits break tests; load makes the hosted suite time out.

**Fix direction.** Rules CC 31–CC 35: a `GraphiteTestSupport` target with temporary vaults, isolated defaults, an injected clock and one event-based `waitUntil`; tests named after the type they pin; typed assertions; a CI workflow for `swift test`, the hosted simulator suite and the Node runtime suite.

### 2.6 Errors are English sentences, and code reads the wording

**What it is.** Failures are thrown, stored and shown as English text. Core, Index and Apple code build user sentences; `GraphiteError` carries a `String` payload for most of its cases; every feature keeps its own `String?` slot; some callers decide what to do by reading the wording.

**Where.** Systemic in twelve of thirteen areas: `CC-ARCH-01`, `CC-VAULT-02`, `CC-VAULT-06`, `CC-BASES-07`, `CC-CANVAS-03`, `CC-LECTURE-04`, `CC-VOICE-10`, `CC-INK-08`, `CC-SHELL-06`, `CC-READING-05`, `CC-EDITOR-09`, `CC-PLUGIN-05`, `CC-RUNTIME-05`.

**Evidence.**
- Three of the six `GraphiteError` cases (`invalidFile`, `oversized`, `unavailable`) are a bare `String` that `errorDescription` prints unchanged ([VaultPath.swift:3-12](../../../Sources/GraphiteCore/VaultPath.swift#L3-L12)); `.unavailable(String)` stands for "already exists", "no longer in the vault", "moved into itself", provider refusal and "no free name" (`CC-VAULT-02`). Core throws 84 such sentences (`grep -rnE 'GraphiteError\.(unavailable|invalidFile|oversized)\("' Sources/GraphiteCore`).
- Callers read the wording: the plugin bridge maps `reason.hasSuffix("already exists.")` to the kind `exists` and `hasSuffix("is no longer in the vault.")` to `missing` ([CommunityPluginVaultBridge.swift:360-361](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L360-L361)); the JavaScript runtime retries a write only when `/changed outside this plugin/` matches the error message ([community-plugin-runtime-vault.js:279](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L279)).
- Other layers write the words too: canvas colour names "Red" to "Purple" in Core ([CanvasFile.swift:55-58](../../../Sources/GraphiteCore/CanvasFile.swift#L55-L58)), `CanvasFileError.errorDescription` ([CanvasJSON.swift:22-38](../../../Sources/GraphiteCore/CanvasJSON.swift#L22-L38)), `ReadAloudError.errorDescription` in Core ([ReadAloudDocument.swift:716-725](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L716-L725)), and about 40 `BaseExpressionError.evaluation("…")` sentences (`CC-BASES-07`).
- Presentation: 208 `localizedDescription` uses in production Swift, 140 of them on lines that also assign an `errorMessage`-style slot; `MessageAlert` titles an alert with the message's first sentence ([MessageAlert.swift:6-34](../../../Sources/GraphiteUI/MessageAlert.swift#L6-L34)) while `errorAlert` titles it "Graphite"; one slot means a second failure overwrites the first (`CC-ARCH-01`).

**Cost.** Rewording a sentence changes behaviour: the runtime's retry stops and every concurrent `process` becomes a plugin-visible failure (`CC-RUNTIME-05`). Tests assert on text, so copy edits break them ([CanvasSessionTests.swift:396-397](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L396-L397)). The sentence can be wrong for its cause: every geometry failure reads "exceeds the supported canvas size" (`CC-INK-08`), and every size limit names "the current editor's memory budget" (`CC-VAULT-06`). Callers cannot tell success from failure (`CC-READING-05`, BUG-READING-04), Foundation and MLX text reaches the person unfiltered (`CC-VOICE-10`), and nothing can be localized.

**Fix direction.** Rules CC 6, CC 7 and CC 15: typed cases that carry facts (`.alreadyExists(VaultPath)`, `.tooLarge(limitBytes:)`), matched by case; one presenter maps them to catalogue strings and chooses alert or banner. Keep the bridge's `{failure: {kind, message}}` shape ([CommunityPluginVaultBridge.swift:34-44](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L44)) and the alert-title rule of `MessageAlert`.

### 2.7 Work on the main actor and on every frame

**What it is.** Work whose cost grows with the whole document, vault or payload runs on every frame, keystroke or message, or runs on the main actor while the person writes or draws.

**Where.** `CC-INK-05`, `CC-INK-06`, `CC-VOICE-13`, `CC-VOICE-14`, `CC-PLUGIN-06`, `CC-PLUGIN-13`, `CC-CANVAS-09`, `CC-RUNTIME-11`, `CC-MDCORE-02`.

**Evidence.**
- Zooming a lasso selection: every layout pass calls `inkSelection.canvasDidChangeScale()` ([HistoryCanvasView.swift:285-288](../../../Sources/GraphiteUI/HistoryCanvasView.swift#L285-L288)), which re-places the frame and assigns `additionalAccessibilityActions = accessibilityActions()` ([InkSelection.swift:515](../../../Sources/GraphiteUI/InkSelection.swift#L515)); that rebuilds the whole menu and decodes the stored palette each time (`CC-INK-05`).
- Reading a PDF aloud runs language recognition, up to 400 spell-checker lookups and a `difference(from:)` over up to 200,000 UTF-16 units on the main actor ([ReadAloudController.swift:665-669](../../../Sources/GraphiteUI/ReadAloudController.swift#L665-L669), [ReadAloudController.swift:700-703](../../../Sources/GraphiteUI/ReadAloudController.swift#L700-L703)) while the person writes on the same page.
- A plugin message is validated and re-serialized on the main actor, so a `vault.write` of up to 64 MB is walked and copied there ([CommunityPluginHost.swift:851-862](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L851-L862)); a plugin's network response is appended one byte at a time up to the same cap ([CommunityPluginNetworkRequest.swift:44-48](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L44-L48)).
- The canvas filters every node on every viewport change ([CanvasSession.swift:109-111](../../../Sources/GraphiteUI/CanvasSession.swift#L109-L111)) with up to 50,000 cards allowed; the per-keystroke style scanner tests overlaps against every claimed range ([MarkdownStyleScanner.swift:500-502](../../../Sources/GraphiteCore/MarkdownStyleScanner.swift#L500-L502)) after two other files fixed the same quadratic (`CC-MDCORE-02`).
- Every canvas adds a `UserDefaults.didChangeNotification` observer and never removes it ([HistoryCanvasView.swift:95-103](../../../Sources/GraphiteUI/HistoryCanvasView.swift#L95-L103)), so each preference write wakes every canvas ever created (`CC-INK-06`).

**Cost.** OBJECTIVE.md puts the Pencil experience and editor responsiveness first. These paths run exactly while the Pencil or keyboard is in use, and their cost scales with the size of the page, canvas or vault. A page whose exported text differs widely from the live text makes the diff on the main thread quadratic in the number of differences (`CC-VOICE-13`).

**Fix direction.** Rules CC 19 and CC 10: layout passes place geometry only, build menus when the selection changes, run language, diff and serialization steps in the detached worker that already exists, use sorted or indexed structures for overlap tests, and give each observer an owner that removes it.

### 2.8 Getters, predicates and `body` write state or do work

**What it is.** A read path (a property getter, a predicate, `body`, a view `init`) writes observed state, writes a file, moves a view, or builds an expensive object.

**Where.** `CC-BASES-06`, `CC-EDITOR-08`, `CC-LECTURE-06`, `CC-READING-03`, `CC-VOICE-04`, `CC-CANVAS-08`.

**Evidence.**
- `ReadAloudSession.voices` calls `refreshVoices()` on first access and writes three observed fields ([ReadAloudSpeech.swift:419-424](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L419-L424)); `selectedVoice` reaches it from a view body ([ReadAloudControls.swift:231](../../../Sources/GraphiteUI/ReadAloudControls.swift#L231)).
- The reading view assigns inside its builder: `let _ = blockActions.update(…)` ([MarkdownPreview.swift:825-828](../../../Sources/GraphiteUI/MarkdownPreview.swift#L825-L828)); `updateUIView` calls `coordinator.update(input:)` ([GraphitePDFView.swift:286](../../../Sources/GraphiteUI/GraphitePDFView.swift#L286)), whose `defer` ends in `pictureSelection?.update()`, which sets the observable `session.selectedPicture = nil` ([PDFPictureControls.swift:221](../../../Sources/GraphiteUI/PDFPictureControls.swift#L221), `CC-LECTURE-06`).
- `ReadAloudAudioCache.passage(for:)` rewrites `index.json` on every lookup ([ReadAloudAudioCache.swift:71-72](../../../Sources/GraphiteVoices/ReadAloudAudioCache.swift#L71-L72)); the predicate `isRunningHeaderOrFooter` appends to `runningText` ([ReadAloudDocument.swift:117-131](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L117-L131)); two `@State` initial values construct a `ReadAloudSession` that builds an `AVSpeechSynthesizer` ([ReadAloudVoiceSettings.swift:14](../../../Sources/GraphiteUI/ReadAloudVoiceSettings.swift#L14)).
- `BaseContainerView.init` mutates `EmbeddedBaseModelCache` ([BaseDocumentView.swift:213-218](../../../Sources/GraphiteUI/BaseDocumentView.swift#L213-L218)); `reservedHeight(of:…)` reads like a query but transfers a table's view and writes estimates ([LivePreviewRenderedBlocks.swift:207-219](../../../Sources/GraphiteUI/LivePreviewRenderedBlocks.swift#L207-L219)).
- Exempt: a memo cache marked `@ObservationIgnored`, as `PDFSession.cachedOutlineEntries` ([PDFSession.swift:303](../../../Sources/GraphiteUI/PDFSession.swift#L303)); the harmless memoizing getters `foldLayout` and `concealedEntries` (`CC-EDITOR-08`).

**Cost.** Writing observed state during `body` schedules another update; each passage start writes a file; each parent re-render builds a throw-away synthesizer; calling `reservedHeight` from a new place changes which view a table keeps.

**Fix direction.** Rule CC 18: queries return values; refreshes are named intent methods called from `.task`, `.onChange` or the owning model; only `@ObservationIgnored` memo caches may be written from a read path.

### 2.9 Long functions, and files that hold many concepts

**What it is.** A function is one linear body that names no stages; a SwiftUI `body` inlines dozens of views; a table is written as code; a file holds unrelated types.

**Where.** Every area: `CC-SHELL-01`, `CC-EDITOR-01`, `CC-READING-01`, `CC-MDCORE-03`, `CC-VAULT-05`, `CC-BASES-01`, `CC-CANVAS-04`, `CC-INK-12`, `CC-LECTURE-02`, `CC-VOICE-01`, `CC-PLUGIN-11`, `CC-RUNTIME-01`; files: `CC-EDITOR-07`, `CC-SHELL-10`, `CC-MDCORE-05`; line length: `CC-RUNTIME-10`.

**Evidence.**

| Measure | Value | Source |
| --- | ---: | --- |
| Production Swift functions over 40 code lines | 189 of 6,222 | [metrics.md](../metrics.md) Sizes |
| Functions over 80 code lines | 26 | same |
| Types over 300 / over 600 code lines | 39 / 12 | same |
| Files over 400 / over 500 code lines | 57 / 39 | same |
| Runtime JavaScript functions over 40 lines | 11 (longest 187) | `CC-RUNTIME-01` |
| Runtime JavaScript lines over 160 characters | 81 | `CC-RUNTIME-10` |

The longest: `ReadAloudDocument.markdown` 273 and `pageText` 149, `Converter.handleTag` 176 ([HTMLToMarkdown.swift:242](../../../Sources/GraphiteCore/HTMLToMarkdown.swift#L242)), `GraphiteRootView.body` 172 ([GraphiteRootView.swift:62-252](../../../Sources/GraphiteUI/GraphiteRootView.swift#L62-L252)), `CodeLineScanner.scanSigil` 160, `MarkdownPreview.body` 127. Multi-concept files: `VaultSidebar.swift` declares 20 types, `WorkspacePanes.swift` 14, `MarkdownTextStyler.swift` 15, `LivePreviewEditTracking.swift` 16 (`CC-SHELL-10`, `CC-EDITOR-07`).

**Cost.** The longest functions are the riskiest to change: `WorkspaceModel.load` mixes choosing a session, saving, swapping and six follow-up updates in 77 lines; `openVault` interleaves I/O with the reset of 33 fields (`CC-SHELL-01`); `GraphiteRootView.body` mixes layout, sheets and lifecycle. A table written as code (`BaseEvaluator.callFunction` 109, the moment.js token switch) hides the table.

**Fix direction.** Rules CC 17 and CC 27: one function per stage, per block kind or per change kind; dispatch tables for mappings; named subviews for SwiftUI bodies. The areas record two legitimate exceptions: an exhaustive single-switch mapper (`MarkdownTextStyler.apply(_ style:)`, `CC-EDITOR-01`) and a long straightforward sequence.

### 2.10 Persisted keys, names and identities are declared inline

**What it is.** Preference keys, notification names, icon mappings, file-name stamps and element identities are string literals or display text, written next to their use and repeated.

**Where.** `CC-INK-09`, `CC-VOICE-05`, `CC-CANVAS-08`, `CC-EDITOR-10`, `CC-EDITOR-08`, `CC-ARCH-11`, `CC-SHELL-10`.

**Evidence.**
- Ink keys are declared in separate files: `"GraphiteLassoShape"` ([LassoTools.swift:12](../../../Sources/GraphiteUI/LassoTools.swift#L12)), `"GraphiteLaserPointerStyle"` ([LassoTools.swift:39](../../../Sources/GraphiteUI/LassoTools.swift#L39)), `"GraphitePencilToolbarStyle"` ([PencilToolbox.swift:19](../../../Sources/GraphiteUI/PencilToolbox.swift#L19)), `"GraphiteMakesShapesOnHold"` ([StrokeHold.swift:39](../../../Sources/GraphiteUI/StrokeHold.swift#L39)); Read Aloud has 15 keys and one suite name in 8 files under two naming styles (`CC-VOICE-05`); canvas keys carry a `Graphite` prefix, graph keys do not (`graphShowsTags`, [WorkspaceGraph.swift:39-55](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L39-L55)).
- Identity from display text or hashes: key commands are found again by their title ([NativeMarkdownEditor.swift:318-321](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L318-L321)); a rendered block's identity string starts with `markdown.hashValue` ([LivePreviewWidgets.swift:354-356](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L354-L356)); one concept has two names, "widget" and "rendered block" (`CC-EDITOR-10`).
- Facts without an owner: the document-kind icon is mapped three times ([QuickPalette.swift:306-317](../../../Sources/GraphiteUI/QuickPalette.swift#L306-L317), [VaultSidebar.swift:831-842](../../../Sources/GraphiteUI/VaultSidebar.swift#L831-L842), [VaultSidebarPanels.swift:429](../../../Sources/GraphiteUI/VaultSidebarPanels.swift#L429)); file-name timestamps use three formats (`CC-ARCH-11`); search queries are assembled from text in four places (`CC-SHELL-10`).

**Cost.** A second key style invites a third (`CC-CANVAS-08`); renaming a shortcut's title changes which command runs when two titles collide; keys spread over six declarations cannot be checked for collisions or migrated.

**Fix direction.** Rules CC 20 and CC 21: one typed key registry per feature with one prefix rule, raw values pinned by a test; identities computed from structured values; one name per concept.

### 2.11 Durations, thresholds and sizes are literals in logic

**What it is.** A delay, cap, ratio or size appears as a number in the expression that uses it, with its unit and reason absent, often several times.

**Where.** Eleven areas: `CC-SHELL-07`, `CC-EDITOR-05`, `CC-CANVAS-05`, `CC-BASES-09`, `CC-INK-10`, `CC-LECTURE-08`, `CC-VOICE-08`, `CC-READING-09`, `CC-PLUGIN-09`, `CC-RUNTIME-04`, `CC-MDCORE-07`.

**Evidence.**
- The same value, written repeatedly: the plugin answer timeout `.seconds(5)` is a literal 10 times in the host and its extensions (for example [CommunityPluginViews.swift:75](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L75), [CommunityPluginMenus.swift:66](../../../Sources/GraphiteUI/CommunityPluginMenus.swift#L66)) beside the named `tapTimeout` ([CommunityPluginReadingBlocks.swift:58](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L58)); the tab width 220 is written twice ([WorkspacePanes.swift:183](../../../Sources/GraphiteUI/WorkspacePanes.swift#L183), [WorkspacePanes.swift:318](../../../Sources/GraphiteUI/WorkspacePanes.swift#L318)); the nine-digit list cap is `maximumOrderedListNumber` in one file ([HTMLToMarkdown.swift:102](../../../Sources/GraphiteCore/HTMLToMarkdown.swift#L102)) and `999_999_999` or `(1...9)` in three others ([MarkdownEditing.swift:173](../../../Sources/GraphiteCore/MarkdownEditing.swift#L173), [MarkdownSemantics.swift:810](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L810)).
- Values that must agree and do not: a card width clamp of 80…1,200 at parse against a 120…600 stepper ([BaseDefinition.swift:447](../../../Sources/GraphiteCore/BaseDefinition.swift#L447), [BaseViewEditorSheet.swift:445-446](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L445-L446)); the retry limit of `process` written as `3` and as `attempt === 2` ([vault.js:279](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L279), `CC-RUNTIME-04`).
- Delays as guesses: 250 ms before the template picker ([GraphiteRootView.swift:470-474](../../../Sources/GraphiteUI/GraphiteRootView.swift#L470-L474)), 40 × 250 ms ([WorkspaceDeepLinks.swift:81-86](../../../Sources/GraphiteUI/WorkspaceDeepLinks.swift#L81-L86)), `0..<50` × 10 ms ([CommunityPluginHost.swift:711](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L711)).
- Days counted in seconds: `snapshotHistoryDays * 86_400` ([WorkspaceRecovery.swift:44](../../../Sources/GraphiteUI/WorkspaceRecovery.swift#L44)) and `30 * 86_400` ([VaultIndex.swift:237](../../../Sources/GraphiteIndex/VaultIndex.swift#L237)).

**Cost.** Tuning choices keep their reasons only in the developer's memory; the documented timeout table cannot be checked against one declaration (`CC-PLUGIN-09`); a width written at 1,000 points parses but the stepper cannot show it (`CC-BASES-09`); a change to one copy leaves the others.

**Fix direction.** Rule CC 22: named constants with units on the type that owns the policy. The code already shows the shape: `TouchMetrics` and `NewCardSize` ([CanvasInteraction.swift:23-43](../../../Sources/GraphiteUI/CanvasInteraction.swift#L23-L43)), `externalRefreshDelay` ([WorkspaceModel.swift:1272-1275](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1272-L1275)), `MoviePartWriter.swift:11-21`, and the runtime's `maximumIndexedNoteBytes` and `snapshotDelayMilliseconds`.

### 2.12 JavaScript, HTML, CSS and YAML live inside Swift strings

**What it is.** Code or a document in another language is a string literal in a Swift file, so no linter, formatter or Node test sees it.

**Where.** `CC-PLUGIN-04`, `CC-SHELL-10`; the only other embedded document found in the findings is the probe page in `ThemeTokenResolver`.

**Evidence.**
- 251 lines of JavaScript in `static let script = """` ([CommunityPluginReadingBlocks.swift:436-686](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L436-L686)) and 28 lines of HTML and CSS in `static var shell` ([CommunityPluginReadingBlocks.swift:404-431](../../../Sources/GraphiteUI/CommunityPluginReadingBlocks.swift#L404-L431)); the probe page's HTML ([ThemeTokenResolver.swift:140-145](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L140-L145)).
- A new base file's YAML and the inserted Markdown blocks ([WorkspaceModel.swift:786](../../../Sources/GraphiteUI/WorkspaceModel.swift#L786), [WorkspaceCommands.swift:241-244](../../../Sources/GraphiteUI/WorkspaceCommands.swift#L241-L244)).
- The counter-example is already in the repository: the theme probe is the resource file [theme-probe.js](../../../Sources/GraphiteUI/Resources/ThemeResolver/theme-probe.js), and the runtime's own JavaScript has 85 Node test cases (`metrics.md`).
- Out of scope: SQL statements beside GRDB calls; no area finding reports them.

**Cost.** The copy page's tap, drag, long-press and morph logic is not linted and is exercised only by hosted iPad tests, not by the Node suite; `GraphiteCodeBlock.show` takes 9 positional arguments whose order the Swift string fixes (`CC-PLUGIN-04`).

**Fix direction.** Rule CC 23: resource files with their own tests.

### 2.13 Comments narrate incidents, dates and the owner

**What it is.** A comment records when a defect was seen, on whose device, or what the code "used to" do, instead of stating the rule the code keeps; some comments are stale or sit on the wrong declaration.

**Where.** `CC-EDITOR-06`, `CC-BASES-08`, `CC-INK-11`, `CC-LECTURE-01`, `CC-MDCORE-04`, `CC-MDCORE-05`, `CC-PLUGIN-10`, `CC-READING-07`, `CC-RUNTIME-07`, `CC-SHELL-08`, `CC-VAULT-09`, `CC-VOICE-09`, `CC-ARCH-07`.

**Evidence.**
- Counts ([metrics.md](../metrics.md)): 35 comment lines carry a calendar date, 16 of them record an incident or measurement; 14 lines name the owner or the owner's iPad; 5 say "used to".
- Examples: "(an iPad, 2026-10-10)" ([NativeMarkdownEditor.swift:949-952](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L949-L952)); "reported by the owner, 2026-10-13" ([GraphitePDFView.swift:352-356](../../../Sources/GraphiteUI/GraphitePDFView.swift#L352-L356)); "made the iPad's sidebar update again without end" ([GraphiteRootView.swift:64-66](../../../Sources/GraphiteUI/GraphiteRootView.swift#L64-L66)); "measured 2026-10-16" ([ReadAloudSpeech.swift:419-420](../../../Sources/GraphiteApple/ReadAloudSpeech.swift#L419-L420)).
- Stale or false: [BasePropertyEditing.swift:18](../../../Sources/GraphiteCore/BasePropertyEditing.swift#L18) says comment-only YAML reads as invalid, the code returns `[]` (`CC-BASES-08`); `CanvasCardRenderCache` documents least-recently-used eviction and evicts by insertion order (`CC-CANVAS-08`); a runtime CSS header contradicts its file (`CC-RUNTIME-09`); doc comments are fused onto the wrong declaration (`CC-MDCORE-05`, `CC-READING-07`).

**Cost.** The incident part grows with every fix and the dates become noise; a stale comment justifies a fallback that guards nothing (`CC-BASES-08`). The platform constraint inside these comments is the most valuable text in the files and must survive the clean-up (EDITOR "What to keep").

**Fix direction.** Rule CC 24: keep the rule sentence in the present tense; move the incident to the commit message and to the name of the regression test.

### 2.14 Dead code and test-only members ship

**What it is.** Declarations that no production path calls stay in the product, and tests pin them.

**Where.** `CC-INK-13`, `CC-LECTURE-11`, `CC-MDCORE-05`, `CC-READING-10`, `CC-VOICE-06`, `CC-VAULT-07`, `CC-CANVAS-01`.

**Evidence.**
- `CalloutFoldScope` is declared and referenced nowhere else ([CalloutFoldStore.swift:24-27](../../../Sources/GraphiteUI/CalloutFoldStore.swift#L24-L27); `grep -rn CalloutFoldScope Sources` returns the declaration only).
- `PDFTemplateGenerator.pageData(template:matching:)` has no caller in `Sources` ([PDFTemplateGenerator.swift:72](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L72)); `LassoPicture.corners` has no caller ([LassoTools.swift:161-168](../../../Sources/GraphiteUI/LassoTools.swift#L161-L168)); `PDFStructureInspection.hasDigitalSignature(in:)` is called only by tests; seven Read Aloud members are dead or test-only (`CC-VOICE-06`).
- A dead parameter suggests a feature: `selecting(baseSelection:)` is always created with `[]`, so the documented Shift-drag extension never happens ([CanvasInteraction.swift:126](../../../Sources/GraphiteUI/CanvasInteraction.swift#L126), `CC-CANVAS-01`).

**Cost.** A green test proves nothing about code the product never runs; readers assume features exist.

**Fix direction.** Rule CC 26: delete, or move test-only members into the test-support target.

## 3. Largest offenders

Ranked by how many clean-code habits one unit combines and how much of the product's critical path it carries. Counts marked "grep" are raw `grep -c` line counts (comments included); sizes come from [metrics.md](../metrics.md).

| # | Unit | Size and counts | What fails | Findings |
| ---: | --- | --- | --- | --- |
| 1 | `NativeMarkdownEditor.swift` (`NativeMarkdownEditor` 1,947 and `Coordinator` 1,616 code lines; file 2,631, 41 commits) | 16 `DispatchQueue.main` uses, 17 `Task {` lines (grep), 7 re-entrancy Booleans, about 14 iPad/Mac function pairs, 14 history comments, 13 functions over 40 lines (`makeTextView` 78) | Ordering is guessed with main-queue hops and unowned tasks; a flag set by hand stays on after an early return; fixes land on one platform | `CC-EDITOR-01`–`CC-EDITOR-07` |
| 2 | `CommunityPluginHost` (771 code lines in its main file's type, 1,158 over 6 files) | 37 `try?`, 17 `Task {` lines in the file (41 in the area), 4 sleep-polling loops, 3 hand-made "first outcome wins" primitives, 20 literal durations and caps, runtime phase kept in 4 fields plus 4 identity checks, `stopRuntime` resets 35 fields | "Stopping" has no representation; a rename is inferred from file existence for up to 10 s; a sleeping loser stays alive after every request | `CC-PLUGIN-01`, `CC-PLUGIN-02`, `CC-PLUGIN-03`, `CC-PLUGIN-09`, BUG-PLUGIN-01, BUG-PLUGIN-03 |
| 3 | `WorkspaceModel` and its extensions (2,695 code lines over 23 files) | 82 `errorMessage` sentences written in the model, 22 `localizedDescription` lines (grep), 20 `try?`, 15 tasks of which 2 are stored and cancelled, `load` 77 lines, `openVault` 62 lines resetting 33 fields | Failures become strings or silence; quit and switch paths drop work | `CC-SHELL-01`, `CC-SHELL-04`, `CC-SHELL-06`, `CC-ARCH-01`, `CC-ARCH-02`, `CC-ARCH-05`, BUG-SHELL-03, BUG-ARCH-04 |
| 4 | `ReadAloudDocument.markdown` (273 lines) and `pageText` (149) in a 579-line type | Two of the five longest functions in the app; 4 user sentences built in Core; a predicate that appends to a list | One function holds layout, language and notice rules; Core produces English | `CC-VOICE-01`, `CC-VOICE-04`, `CC-VOICE-10` |
| 5 | `Converter.handleTag` (176), `CodeLineScanner.scanSigil` (160), `MarkdownSemantics.parse` (115), `NoteBlocks.blocks` (113) | 23 functions over 40 lines in MDCORE; 53 `try?` regular-expression constants | A switch per tag or sigil written as one body; a mistyped pattern silently disables its feature | `CC-MDCORE-03`, `CC-MDCORE-01` |
| 6 | `GraphiteRootView.body` | 172 lines in a 475-line type | Layout, sheets and lifecycle in one expression; a 250 ms sleep orders the template picker; an incident story in a comment | `CC-SHELL-01`, `CC-SHELL-02`, `CC-SHELL-08` |
| 7 | `MarkdownPreview.swift` (2,293 code lines) | `body` 127, `blockView` 105, 18 `try?`, 3 sleeps (grep) of which 2 order layout | `body` assigns closures; scrolling and Read Aloud following wait fixed milliseconds for a frame | `CC-READING-01`, `CC-READING-02`, `CC-READING-03`, `CC-READING-07` |
| 8 | `DrawingEditor.swift` (1,090 code lines) with `HistoryCanvasView` (511) | 16 `Task {` lines (grep), 3 correctness-bearing timing windows (1 s, 0.5 s, 1 s), 2 observers never removed, picture flow kept as 2 Booleans and an optional in 2 objects, `toolbarContent` 74, `body` 67, `makeUIView` 67 | A stroke made by the canvas must arrive within 1 s to be recognised; rotate and crop apply results to a value read before the await | `CC-INK-01`, `CC-INK-02`, `CC-INK-03`, `CC-INK-05`, `CC-INK-06`, `CC-INK-12`, `CC-INK-14`, BUG-INK-03 |
| 9 | `RecordingController` (501 code lines) | `state` plus 5 flag fields, 17 `Task {` lines (grep), 21 `try?` | Impossible flag combinations; recovery-folder leftovers swallowed and offered again | `CC-LECTURE-05`, `CC-LECTURE-07`, `CC-LECTURE-14`, BUG-LECTURE-01 |
| 10 | Read Aloud playback: `ReadAloudSession` ([ReadAloudSpeech.swift](../../../Sources/GraphiteApple/ReadAloudSpeech.swift), 698 code lines), `ReadAloudNavigator.resumeWhenPrepared`, `ReadAloudController` (617) | 4-case `State` plus 5 flags and a sentinel offset, a 200 × 50 ms poll, 9 `Task.sleep`, a getter that writes observed state, language and diff work on the main actor | Stop does not stop (an unowned preparation task restarts reading) | `CC-VOICE-02`, `CC-VOICE-03`, `CC-VOICE-04`, `CC-VOICE-12`, `CC-VOICE-13`, BUG-VOICE-01, BUG-VOICE-02 |

## 4. What to keep for this principle

The areas record these designs as meeting the rules already. The clean-up moves them with their tests unchanged and imitates them.

| Design | Evidence | Rule it satisfies |
| --- | --- | --- |
| Constants named with units on the type that owns the policy | `TouchMetrics`, `NewCardSize` ([CanvasInteraction.swift:23-43](../../../Sources/GraphiteUI/CanvasInteraction.swift#L23-L43)); `externalRefreshDelay` ([WorkspaceModel.swift:1272-1275](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1272-L1275)); `MoviePartWriter` limits ([MoviePartWriter.swift:11-21](../../../Sources/GraphiteApple/MoviePartWriter.swift#L11-L21)); the runtime's `maximumIndexedNoteBytes`, `snapshotDelayMilliseconds` ([metadata.js:16-18](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-metadata.js#L16-L18)) | CC 22 |
| Every `@unchecked Sendable` states its invariant | 20 of 20 carry a reason (ARCH "What to keep"); e.g. [FolderAccess.swift:131-135](../../../Sources/GraphiteApple/FolderAccess.swift#L131-L135), [CanvasCardViews.swift:407-408](../../../Sources/GraphiteUI/CanvasCardViews.swift#L407-L408) | CC 28 |
| Comments that state a platform constraint precisely | [NativeMarkdownEditor.swift:1089-1092](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1089-L1092); the runtime's shims name the plugin that needs them ([vault.js:197-200](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L197-L200)) | CC 24: strip only the incident |
| Decide-then-do values: inputs in, one value out | `MarkdownTextEdit` helpers ([EditorKeyboardToolbar.swift:76-110](../../../Sources/GraphiteUI/EditorKeyboardToolbar.swift#L76-L110)); `ExternalChangeRefresh` ([WorkspaceModel.swift:1405-1453](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1405-L1453)); `UnansweredGestureCount`, `PDFResizeZoom`, `RecordingPreviewLayout` ([PDFPaneHealth.swift:8-77](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L8-L77)); autosave back-off as a pure static function ([PDFSession.swift:479-487](../../../Sources/GraphiteUI/PDFSession.swift#L479-L487)) | CC 12, CC 17 |
| A fast duplicate that keeps one owner through a parity test | `NoteFolding.isListItem` against `MarkdownEditing.listLine`, pinned on 34 lines ([NoteFolding.swift:96-135](../../../Sources/GraphiteCore/NoteFolding.swift#L96-L135), [NoteFoldingTests.swift:75-81](../../../Tests/GraphiteCoreTests/NoteFoldingTests.swift#L75-L81)) | CC 13 |
| "Latest answer wins" by run identifier, so late results never install | [WorkspaceModel.swift:523-556](../../../Sources/GraphiteUI/WorkspaceModel.swift#L523-L556), [ReadAloudController.swift:115](../../../Sources/GraphiteUI/ReadAloudController.swift#L115), [ReadAloudController.swift:629-632](../../../Sources/GraphiteUI/ReadAloudController.swift#L629-L632); the shared `LatestRequest` keeps exactly this behaviour | CC 11 |
| Tasks with an owner that cancels them | table-cell commit task ([LivePreviewTableEditing.swift:122-142](../../../Sources/GraphiteUI/LivePreviewTableEditing.swift#L122-L142)); the drawing check cancels its file read ([MarkdownPane.swift:733-740](../../../Sources/GraphiteUI/MarkdownPane.swift#L733-L740)) | CC 10 |
| A scoped flag with `defer` | `isApplyingOwnEdit` on the Mac ([NativeMarkdownEditor.swift:3174-3175](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L3174-L3175)) | CC 12 |
| Flows as typed values, not Booleans | `FileChange` in the view editor ([BaseViewEditorSheet.swift:113-165](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L113-L165)); `WorkspaceFocusMode` ([WorkspaceFocusMode.swift:4-23](../../../Sources/GraphiteUI/WorkspaceFocusMode.swift#L4-L23)); the conflict-version feature (model, wording enum, injected store: [ConflictVersionsSheet.swift:8-65](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L8-L65), [ConflictVersionsSheet.swift:174-201](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L174-L201)) | CC 8 |
| Unreadable data kept and reported, never dropped or overwritten | `VaultLibrary` keeps unreadable entries and an unreadable list ([VaultLibrary.swift:67-109](../../../Sources/GraphiteUI/VaultLibrary.swift#L67-L109)); unreadable plugin folders listed with their reason ([CommunityPluginInventory.swift:134-146](../../../Sources/GraphiteCore/CommunityPluginInventory.swift#L134-L146)); rows from a failed lookup are never published ([BaseRecordQueries.swift:277-289](../../../Sources/GraphiteIndex/BaseRecordQueries.swift#L277-L289)); the runtime does not overwrite an unreadable `types.json` ([plugins.js:776-781](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L776-L781)) | CC 1–CC 4 |
| Failures as typed kinds across a boundary | bridge requests decode into private `Decodable` structs and fail as `{failure: {kind, message}}` ([CommunityPluginVaultBridge.swift:34-44](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L44)); `runtime.receive` never throws ([plugins.js:1541-1550](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1541-L1550)) | CC 6 |
| Display words kept out of Core | UI vocabulary for Core enums in the UI module ([DrawingEditor.swift:58-75](../../../Sources/GraphiteUI/DrawingEditor.swift#L58-L75)); the error alert titled by its first sentence ([MessageAlert.swift:6-34](../../../Sources/GraphiteUI/MessageAlert.swift#L6-L34)), a rule the one presenter adopts | CC 7, CC 15 |
| Read once, write on change, injected defaults | `DocumentPlaceStore` ([WorkspacePlaces.swift:79-112](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L79-L112), [DocumentPlaceStoreTests.swift:32-73](../../../Tests/GraphiteUITests/DocumentPlaceStoreTests.swift#L32-L73)); the pencil toolbox tests use a private suite | CC 20, CC 34 |
| Bounds enforced where untrusted input enters, with tests that reproduce the hazard | `MarkdownNesting`, `YAMLNesting` ([ParserNestingLimits.swift:9-151](../../../Sources/GraphiteCore/ParserNestingLimits.swift#L9-L151)) tested on a 512 KB stack ([CrashLoopRegressionTests.swift:47-87](../../../Tests/GraphiteCoreTests/CrashLoopRegressionTests.swift#L47-L87)) | CC 16, CC 35 |
| Pure state with explicit times instead of the wall clock | `PalmRejection` ([PalmRejection.swift:19-92](../../../Sources/GraphiteUI/PalmRejection.swift#L19-L92), tested in [PalmRejectionTests.swift:94-129](../../../Tests/GraphiteUITests/PalmRejectionTests.swift#L94-L129)) | CC 34 |
| A bounded wait on a dedicated media queue, with named limits and a documented reason | `readinessPollSeconds` and `maximumReadinessWaitSeconds` ([MoviePartWriter.swift:13-16](../../../Sources/GraphiteApple/MoviePartWriter.swift#L13-L16), [MoviePartWriter.swift:168-177](../../../Sources/GraphiteApple/MoviePartWriter.swift#L168-L177)) | The exception in CC 9 |
| Bounded caches with cost estimates | detached views, measured heights, recent spans ([LivePreviewRenderedBlocks.swift:700-793](../../../Sources/GraphiteUI/LivePreviewRenderedBlocks.swift#L700-L793)); retention policy as a separately tested object ([MarkdownEditorRetention.swift:28-142](../../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L28-L142)) | CC 30 |
| Calendar arithmetic for dates | wall-clock date arithmetic with daylight saving and month overflow ([BaseDateSupport.swift:163-222](../../../Sources/GraphiteCore/BaseDateSupport.swift#L163-L222)) | CC 22 |

## 5. Index of findings

All 151 `CC` findings, generated from [findings-index.md](../findings-index.md), ordered by severity, then area.

| ID | Area | Severity | Title |
| --- | --- | --- | --- |
| [CC-ARCH-09](../cross-cutting/architecture.md#cc-arch-09-the-test-suite-has-no-shared-support-no-ci-and-is-not-hermetic) | ARCH | High | The test suite has no shared support, no CI and is not hermetic |
| [CC-PLUGIN-01](../areas/plugin.md#cc-plugin-01-the-runtime-lifecycle-is-a-set-of-booleans-and-identity-checks-not-a-state-enum) | PLUGIN | High | The runtime lifecycle is a set of booleans and identity checks, not a state enum |
| [CC-ARCH-01](../cross-cutting/architecture.md#cc-arch-01-errors-travel-as-untyped-string-slots-built-from-localizeddescription-through-two-presenters-with-different-rules) | ARCH | Medium | Errors travel as untyped `String?` slots built from `localizedDescription`, through two presenters with different rules |
| [CC-ARCH-02](../cross-cutting/architecture.md#cc-arch-02-try-hides-failures-the-user-should-see-20-of-63-sampled-sites) | ARCH | Medium | `try?` hides failures the user should see: 20 of 63 sampled sites |
| [CC-ARCH-03](../cross-cutting/architecture.md#cc-arch-03-sleep-polling-and-sleep-as-ordering-stand-in-for-completion-signals) | ARCH | Medium | Sleep-polling and sleep-as-ordering stand in for completion signals |
| [CC-ARCH-05](../cross-cutting/architecture.md#cc-arch-05-most-unstructured-tasks-have-no-owner-that-cancels-them) | ARCH | Medium | Most unstructured tasks have no owner that cancels them |
| [CC-BASES-01](../areas/bases.md#cc-bases-01-29-functions-exceed-40-code-lines) | BASES | Medium | 29 functions exceed 40 code lines |
| [CC-BASES-02](../areas/bases.md#cc-bases-02-ad-hoc-latest-answer-wins-and-17-owner-less-view-tasks) | BASES | Medium | Ad-hoc "latest answer wins" and 17 owner-less view tasks |
| [CC-BASES-06](../areas/bases.md#cc-bases-06-work-and-side-effects-in-body-and-view-initialisers) | BASES | Medium | Work and side effects in `body` and view initialisers |
| [CC-BASES-07](../areas/bases.md#cc-bases-07-user-visible-english-is-produced-in-core-and-carried-as-string) | BASES | Medium | User-visible English is produced in Core and carried as `String` |
| [CC-CANVAS-01](../areas/canvas.md#cc-canvas-01-drag-state-is-one-enum-plus-four-loose-fields-that-must-be-reset-together) | CANVAS | Medium | Drag state is one enum plus four loose fields that must be reset together |
| [CC-CANVAS-02](../areas/canvas.md#cc-canvas-02-sleep-driven-loops-and-unowned-tasks) | CANVAS | Medium | Sleep-driven loops and unowned tasks |
| [CC-CANVAS-03](../areas/canvas.md#cc-canvas-03-core-types-carry-english-user-text-and-tests-assert-on-it) | CANVAS | Medium | Core types carry English user text, and tests assert on it |
| [CC-EDITOR-01](../areas/editor.md#cc-editor-01-thirteen-functions-exceed-40-code-lines) | EDITOR | Medium | Thirteen functions exceed 40 code lines |
| [CC-EDITOR-02](../areas/editor.md#cc-editor-02-ordering-is-expressed-as-main-queue-hops-sleeps-and-unowned-tasks) | EDITOR | Medium | Ordering is expressed as main-queue hops, sleeps and unowned tasks |
| [CC-EDITOR-03](../areas/editor.md#cc-editor-03-re-entrancy-is-guarded-by-seven-booleans-set-around-calls) | EDITOR | Medium | Re-entrancy is guarded by seven Booleans set around calls |
| [CC-EDITOR-04](../areas/editor.md#cc-editor-04-about-twelve-ipadmac-function-pairs-repeat-the-same-logic) | EDITOR | Medium | About twelve iPad/Mac function pairs repeat the same logic |
| [CC-INK-01](../areas/ink.md#cc-ink-01-the-picture-arrangement-flow-is-two-booleans-and-an-optional-kept-in-two-objects) | INK | Medium | The picture-arrangement flow is two booleans and an optional, kept in two objects |
| [CC-INK-02](../areas/ink.md#cc-ink-02-outcomes-travel-through-shared-mutable-fields) | INK | Medium | Outcomes travel through shared mutable fields |
| [CC-INK-03](../areas/ink.md#cc-ink-03-correctness-rests-on-timing-windows-and-next-turn-hops) | INK | Medium | Correctness rests on timing windows and next-turn hops |
| [CC-INK-04](../areas/ink.md#cc-ink-04-ten-rules-and-constants-are-implemented-two-or-three-times) | INK | Medium | Ten rules and constants are implemented two or three times |
| [CC-INK-05](../areas/ink.md#cc-ink-05-zooming-a-selection-rebuilds-its-whole-menu-and-reads-stored-colors-on-every-layout-pass) | INK | Medium | Zooming a selection rebuilds its whole menu and reads stored colors on every layout pass |
| [CC-INK-06](../areas/ink.md#cc-ink-06-two-observers-are-never-removed-and-fan-out-on-every-preference-write) | INK | Medium | Two observers are never removed and fan out on every preference write |
| [CC-INK-07](../areas/ink.md#cc-ink-07-the-toolboxs-saved-state-is-all-or-nothing-and-is-overwritten-after-a-failed-read) | INK | Medium | The toolbox's saved state is all-or-nothing and is overwritten after a failed read |
| [CC-INK-14](../areas/ink.md#cc-ink-14-picture-edits-run-in-unowned-tasks-and-apply-results-to-state-read-before-the-await) | INK | Medium | Picture edits run in unowned tasks and apply results to state read before the await |
| [CC-LECTURE-02](../areas/lecture.md#cc-lecture-02-nineteen-functions-exceed-40-code-lines-the-largest-in-swiftui-bodies-and-edit-application) | LECTURE | Medium | Nineteen functions exceed 40 code lines, the largest in SwiftUI bodies and edit application |
| [CC-LECTURE-03](../areas/lecture.md#cc-lecture-03-one-behaviour-is-implemented-several-times) | LECTURE | Medium | One behaviour is implemented several times |
| [CC-LECTURE-04](../areas/lecture.md#cc-lecture-04-domain-and-adapter-types-carry-user-visible-english-raw-error-text-reaches-the-user) | LECTURE | Medium | Domain and adapter types carry user-visible English; raw error text reaches the user |
| [CC-LECTURE-05](../areas/lecture.md#cc-lecture-05-tasks-have-no-owner-and-fixed-delays-order-work) | LECTURE | Medium | Tasks have no owner, and fixed delays order work |
| [CC-LECTURE-06](../areas/lecture.md#cc-lecture-06-swiftui-updates-and-view-creation-write-model-state) | LECTURE | Medium | SwiftUI updates and view creation write model state |
| [CC-LECTURE-07](../areas/lecture.md#cc-lecture-07-flows-with-more-than-two-states-are-kept-as-sets-of-booleans) | LECTURE | Medium | Flows with more than two states are kept as sets of booleans |
| [CC-LECTURE-13](../areas/lecture.md#cc-lecture-13-the-ink-tracker-is-advanced-before-the-edit-is-known-to-succeed) | LECTURE | Medium | The ink tracker is advanced before the edit is known to succeed |
| [CC-MDCORE-01](../areas/mdcore.md#cc-mdcore-01-constant-regular-expressions-use-three-failure-policies-53-of-them-fail-silently) | MDCORE | Medium | Constant regular expressions use three failure policies; 53 of them fail silently |
| [CC-MDCORE-02](../areas/mdcore.md#cc-mdcore-02-per-keystroke-code-still-tests-overlaps-linearly-while-two-other-files-fixed-the-same-quadratic) | MDCORE | Medium | Per-keystroke code still tests overlaps linearly, while two other files fixed the same quadratic |
| [CC-MDCORE-09](../areas/mdcore.md#cc-mdcore-09-parser-bounds-are-decided-per-call-site-instead-of-at-the-parser-boundary) | MDCORE | Medium | Parser bounds are decided per call site instead of at the parser boundary |
| [CC-PLUGIN-02](../areas/plugin.md#cc-plugin-02-four-sleep-polling-loops-wait-for-other-work) | PLUGIN | Medium | Four sleep-polling loops wait for other work |
| [CC-PLUGIN-03](../areas/plugin.md#cc-plugin-03-three-hand-made-first-outcome-wins-primitives-and-41-unowned-tasks) | PLUGIN | Medium | Three hand-made "first outcome wins" primitives and 41 unowned tasks |
| [CC-PLUGIN-04](../areas/plugin.md#cc-plugin-04-javascript-html-and-css-live-inside-swift-strings) | PLUGIN | Medium | JavaScript, HTML and CSS live inside Swift strings |
| [CC-PLUGIN-05](../areas/plugin.md#cc-plugin-05-failure-kinds-are-classified-by-the-end-of-an-errors-message-text) | PLUGIN | Medium | Failure kinds are classified by the end of an error's message text |
| [CC-PLUGIN-06](../areas/plugin.md#cc-plugin-06-every-plugin-message-is-validated-and-re-serialized-on-the-main-actor) | PLUGIN | Medium | Every plugin message is validated and re-serialized on the main actor |
| [CC-PLUGIN-07](../areas/plugin.md#cc-plugin-07-installation-writes-files-one-at-a-time-with-no-staging) | PLUGIN | Medium | Installation writes files one at a time with no staging |
| [CC-READING-01](../areas/reading.md#cc-reading-01-eighteen-functions-exceed-40-code-lines) | READING | Medium | Eighteen functions exceed 40 code lines |
| [CC-READING-02](../areas/reading.md#cc-reading-02-sleeps-are-used-as-layout-ordering) | READING | Medium | Sleeps are used as layout ordering |
| [CC-READING-04](../areas/reading.md#cc-reading-04-failed-index-reads-become-empty-lists) | READING | Medium | Failed index reads become empty lists |
| [CC-READING-05](../areas/reading.md#cc-reading-05-outcomes-travel-through-errormessage-with-raw-error-text) | READING | Medium | Outcomes travel through `errorMessage` with raw error text |
| [CC-RUNTIME-01](../areas/runtime.md#cc-runtime-01-eleven-functions-run-over-40-lines-the-longest-is-187) | RUNTIME | Medium | Eleven functions run over 40 lines; the longest is 187 |
| [CC-RUNTIME-02](../areas/runtime.md#cc-runtime-02-the-same-code-is-copied-in-eight-patterns) | RUNTIME | Medium | The same code is copied in eight patterns |
| [CC-RUNTIME-03](../areas/runtime.md#cc-runtime-03-timers-stand-in-for-ordering-and-are-never-cancelled) | RUNTIME | Medium | Timers stand in for ordering and are never cancelled |
| [CC-RUNTIME-05](../areas/runtime.md#cc-runtime-05-a-retry-decision-and-several-tests-depend-on-message-or-source-text) | RUNTIME | Medium | A retry decision and several tests depend on message or source text |
| [CC-RUNTIME-06](../areas/runtime.md#cc-runtime-06-failed-writes-and-failed-reads-are-swallowed-into-logs-or-empty-values) | RUNTIME | Medium | Failed writes and failed reads are swallowed into logs or empty values |
| [CC-RUNTIME-09](../areas/runtime.md#cc-runtime-09-two-default-style-layers-disagree-and-one-contradicts-its-own-header) | RUNTIME | Medium | Two default style layers disagree, and one contradicts its own header |
| [CC-RUNTIME-11](../areas/runtime.md#cc-runtime-11-every-create-delete-or-rename-re-resolves-every-link-in-the-vault) | RUNTIME | Medium | Every create, delete or rename re-resolves every link in the vault |
| [CC-RUNTIME-12](../areas/runtime.md#cc-runtime-12-the-html-sanitizer-is-a-deny-list) | RUNTIME | Medium | The HTML sanitizer is a deny list |
| [CC-SHELL-01](../areas/shell.md#cc-shell-01-29-functions-exceed-40-code-lines-the-root-views-body-is-172) | SHELL | Medium | 29 functions exceed 40 code lines; the root view's `body` is 172 |
| [CC-SHELL-02](../areas/shell.md#cc-shell-02-sleeps-act-as-ordering-or-polling-in-five-places) | SHELL | Medium | Sleeps act as ordering or polling in five places |
| [CC-SHELL-04](../areas/shell.md#cc-shell-04-try-swallows-failures-the-person-needs-to-know-about) | SHELL | Medium | `try?` swallows failures the person needs to know about |
| [CC-SHELL-05](../areas/shell.md#cc-shell-05-eleven-pieces-of-logic-are-implemented-twice) | SHELL | Medium | Eleven pieces of logic are implemented twice |
| [CC-SHELL-06](../areas/shell.md#cc-shell-06-the-model-writes-user-facing-text-and-views-have-no-string-catalogue) | SHELL | Medium | The model writes user-facing text, and views have no string catalogue |
| [CC-SHELL-09](../areas/shell.md#cc-shell-09-shell-tests-are-named-after-audit-rounds-share-the-processs-defaults-poll-with-sleeps-and-assert-on-text) | SHELL | Medium | Shell tests are named after audit rounds, share the process's defaults, poll with sleeps and assert on text |
| [CC-VAULT-01](../areas/vault.md#cc-vault-01-a-failed-read-of-an-obsidian-settings-file-is-returned-as-nothing-configured) | VAULT | Medium | A failed read of an Obsidian settings file is returned as "nothing configured" |
| [CC-VAULT-02](../areas/vault.md#cc-vault-02-graphiteerror-carries-prose-instead-of-facts-and-one-case-covers-ten-different-failures) | VAULT | Medium | `GraphiteError` carries prose instead of facts, and one case covers ten different failures |
| [CC-VAULT-03](../areas/vault.md#cc-vault-03-the-frontmatter-regular-expression-is-written-four-times) | VAULT | Medium | The frontmatter regular expression is written four times |
| [CC-VOICE-01](../areas/voice.md#cc-voice-01-nineteen-functions-exceed-40-code-lines-two-exceed-140) | VOICE | Medium | Nineteen functions exceed 40 code lines; two exceed 140 |
| [CC-VOICE-02](../areas/voice.md#cc-voice-02-a-sleep-poll-loop-waits-for-another-objects-preparation) | VOICE | Medium | A sleep-poll loop waits for another object's preparation |
| [CC-VOICE-03](../areas/voice.md#cc-voice-03-sleeps-order-ui-events-and-tasks-run-without-an-owner) | VOICE | Medium | Sleeps order UI events, and tasks run without an owner |
| [CC-VOICE-04](../areas/voice.md#cc-voice-04-getters-predicates-and-view-initializers-have-side-effects) | VOICE | Medium | Getters, predicates and view initializers have side effects |
| [CC-VOICE-05](../areas/voice.md#cc-voice-05-fifteen-persisted-preference-keys-and-one-suite-name-live-in-8-files-under-two-naming-styles) | VOICE | Medium | Fifteen persisted preference keys and one suite name live in 8 files under two naming styles |
| [CC-VOICE-07](../areas/voice.md#cc-voice-07-two-adapters-each-own-the-one-shared-audio-session) | VOICE | Medium | Two adapters each own the one shared audio session |
| [CC-VOICE-10](../areas/voice.md#cc-voice-10-core-apple-and-voices-code-produces-user-visible-english-often-with-raw-error-text-appended) | VOICE | Medium | Core, Apple and Voices code produces user-visible English, often with raw error text appended |
| [CC-VOICE-11](../areas/voice.md#cc-voice-11-failures-are-swallowed-where-the-person-or-the-caches-size-limit-depends-on-them) | VOICE | Medium | Failures are swallowed where the person or the cache's size limit depends on them |
| [CC-VOICE-12](../areas/voice.md#cc-voice-12-the-playback-flow-is-an-enum-plus-flags-and-a-sentinel-offset) | VOICE | Medium | The playback flow is an enum plus flags and a sentinel offset |
| [CC-VOICE-13](../areas/voice.md#cc-voice-13-heavy-per-page-work-runs-on-the-main-actor-while-the-person-writes) | VOICE | Medium | Heavy per-page work runs on the main actor while the person writes |
| [CC-ARCH-04](../cross-cutting/architecture.md#cc-arch-04-about-13-hand-written-debounce-and-latest-answer-wins-implementations) | ARCH | Low | About 13 hand-written debounce and "latest answer wins" implementations |
| [CC-ARCH-06](../cross-cutting/architecture.md#cc-arch-06-two-of-41-mainactorassumeisolated-uses-rely-on-threading-no-api-documents) | ARCH | Low | Two of 41 `MainActor.assumeIsolated` uses rely on threading no API documents |
| [CC-ARCH-07](../cross-cutting/architecture.md#cc-arch-07-comments-in-the-composition-files-narrate-incidents-and-dates) | ARCH | Low | Comments in the composition files narrate incidents and dates |
| [CC-ARCH-08](../cross-cutting/architecture.md#cc-arch-08-turning-a-file-url-into-a-vault-path-is-written-seven-times) | ARCH | Low | Turning a file URL into a vault path is written seven times |
| [CC-ARCH-10](../cross-cutting/architecture.md#cc-arch-10-link-format-and-link-syntax-rules-are-duplicated-between-core-and-the-workspace) | ARCH | Low | Link-format and link-syntax rules are duplicated between Core and the workspace |
| [CC-ARCH-11](../cross-cutting/architecture.md#cc-arch-11-three-icon-mappings-and-three-file-name-timestamp-formats) | ARCH | Low | Three icon mappings and three file-name timestamp formats |
| [CC-BASES-03](../areas/bases.md#cc-bases-03-seven-static-regular-expressions-are-built-with-try) | BASES | Low | Seven static regular expressions are built with `try?` |
| [CC-BASES-04](../areas/bases.md#cc-bases-04-the-frontmatter-regular-expression-exists-four-times-one-copy-byte-identical) | BASES | Low | The frontmatter regular expression exists four times, one copy byte-identical |
| [CC-BASES-05](../areas/bases.md#cc-bases-05-one-concept-several-rules-property-name-matching-and-number-reading) | BASES | Low | One concept, several rules: property-name matching and number reading |
| [CC-BASES-08](../areas/bases.md#cc-bases-08-a-stale-comment-and-comments-narrating-history) | BASES | Low | A stale comment and comments narrating history |
| [CC-BASES-09](../areas/bases.md#cc-bases-09-unnamed-constants-for-sizes-clamps-and-durations) | BASES | Low | Unnamed constants for sizes, clamps and durations |
| [CC-BASES-10](../areas/bases.md#cc-bases-10-tests-are-named-after-audit-rounds-and-file-names-do-not-match-their-classes) | BASES | Low | Tests are named after audit rounds, and file names do not match their classes |
| [CC-CANVAS-04](../areas/canvas.md#cc-canvas-04-ten-functions-exceed-40-code-lines) | CANVAS | Low | Ten functions exceed 40 code lines |
| [CC-CANVAS-05](../areas/canvas.md#cc-canvas-05-literal-sizes-durations-and-thresholds-in-drawing-interaction-and-layout) | CANVAS | Low | Literal sizes, durations and thresholds in drawing, interaction and layout |
| [CC-CANVAS-06](../areas/canvas.md#cc-canvas-06-duplicated-code-and-duplicated-facts) | CANVAS | Low | Duplicated code and duplicated facts |
| [CC-CANVAS-07](../areas/canvas.md#cc-canvas-07-errors-swallowed-without-a-stated-reason) | CANVAS | Low | Errors swallowed without a stated reason |
| [CC-CANVAS-08](../areas/canvas.md#cc-canvas-08-naming-and-persisted-key-inconsistencies) | CANVAS | Low | Naming and persisted-key inconsistencies |
| [CC-CANVAS-09](../areas/canvas.md#cc-canvas-09-whole-collection-work-on-every-frame-or-update) | CANVAS | Low | Whole-collection work on every frame or update |
| [CC-EDITOR-05](../areas/editor.md#cc-editor-05-durations-sizes-and-thresholds-are-literals-in-logic) | EDITOR | Low | Durations, sizes and thresholds are literals in logic |
| [CC-EDITOR-06](../areas/editor.md#cc-editor-06-comments-narrate-incidents-and-dates) | EDITOR | Low | Comments narrate incidents and dates |
| [CC-EDITOR-07](../areas/editor.md#cc-editor-07-files-hold-many-concepts-under-one-name) | EDITOR | Low | Files hold many concepts under one name |
| [CC-EDITOR-08](../areas/editor.md#cc-editor-08-getters-and-body-write-state) | EDITOR | Low | Getters and `body` write state |
| [CC-EDITOR-09](../areas/editor.md#cc-editor-09-failures-become-empty-results-or-raw-text) | EDITOR | Low | Failures become empty results or raw text |
| [CC-EDITOR-10](../areas/editor.md#cc-editor-10-one-concept-has-two-names-and-identities-are-built-from-display-text) | EDITOR | Low | One concept has two names, and identities are built from display text |
| [CC-EDITOR-11](../areas/editor.md#cc-editor-11-tests-are-named-after-fix-rounds-and-the-ipad-coordinator-has-no-package-tests) | EDITOR | Low | Tests are named after fix rounds and the iPad coordinator has no package tests |
| [CC-INK-08](../areas/ink.md#cc-ink-08-service-and-domain-errors-carry-user-sentences-one-is-wrong-for-its-cause) | INK | Low | Service and domain errors carry user sentences; one is wrong for its cause |
| [CC-INK-09](../areas/ink.md#cc-ink-09-persisted-keys-and-notification-names-are-declared-in-six-places) | INK | Low | Persisted keys and notification names are declared in six places |
| [CC-INK-10](../areas/ink.md#cc-ink-10-literal-thresholds-and-sizes-in-logic) | INK | Low | Literal thresholds and sizes in logic |
| [CC-INK-11](../areas/ink.md#cc-ink-11-comments-narrate-history-three-comments-are-stale-three-names-mislead) | INK | Low | Comments narrate history, three comments are stale, three names mislead |
| [CC-INK-12](../areas/ink.md#cc-ink-12-eleven-functions-exceed-40-code-lines) | INK | Low | Eleven functions exceed 40 code lines |
| [CC-INK-13](../areas/ink.md#cc-ink-13-dead-code) | INK | Low | Dead code |
| [CC-INK-15](../areas/ink.md#cc-ink-15-the-hosted-tests-that-pin-this-area-share-global-state-and-sleep) | INK | Low | The hosted tests that pin this area share global state and sleep |
| [CC-LECTURE-01](../areas/lecture.md#cc-lecture-01-comments-narrate-incidents-and-dates-instead-of-stating-the-rule) | LECTURE | Low | Comments narrate incidents and dates instead of stating the rule |
| [CC-LECTURE-08](../areas/lecture.md#cc-lecture-08-literal-sizes-ratios-and-delays-in-logic) | LECTURE | Low | Literal sizes, ratios and delays in logic |
| [CC-LECTURE-09](../areas/lecture.md#cc-lecture-09-force-unwraps-in-file-parsing-code) | LECTURE | Low | Force unwraps in file-parsing code |
| [CC-LECTURE-10](../areas/lecture.md#cc-lecture-10-tests-are-named-after-audit-rounds-assert-on-english-text-and-poll-with-sleeps) | LECTURE | Low | Tests are named after audit rounds, assert on English text and poll with sleeps |
| [CC-LECTURE-11](../areas/lecture.md#cc-lecture-11-code-no-production-path-uses) | LECTURE | Low | Code no production path uses |
| [CC-LECTURE-12](../areas/lecture.md#cc-lecture-12-a-bounded-sleep-loop-throttles-the-camera-queue-deliberate-and-the-rule-needs-an-exception) | LECTURE | Low | A bounded sleep loop throttles the camera queue (deliberate, and the rule needs an exception) |
| [CC-LECTURE-14](../areas/lecture.md#cc-lecture-14-swallowed-errors-hide-leftovers-in-the-recovery-folder) | LECTURE | Low | Swallowed errors hide leftovers in the recovery folder |
| [CC-LECTURE-15](../areas/lecture.md#cc-lecture-15-unsafe-concurrency-escapes-are-spread-across-files-each-with-a-stated-invariant) | LECTURE | Low | Unsafe concurrency escapes are spread across files, each with a stated invariant |
| [CC-MDCORE-03](../areas/mdcore.md#cc-mdcore-03-23-functions-exceed-40-code-lines-the-largest-is-176) | MDCORE | Low | 23 functions exceed 40 code lines; the largest is 176 |
| [CC-MDCORE-04](../areas/mdcore.md#cc-mdcore-04-nine-comments-narrate-history-instead-of-stating-the-rule) | MDCORE | Low | Nine comments narrate history instead of stating the rule |
| [CC-MDCORE-05](../areas/mdcore.md#cc-mdcore-05-dead-code-misattached-and-misleading-comments) | MDCORE | Low | Dead code, misattached and misleading comments |
| [CC-MDCORE-06](../areas/mdcore.md#cc-mdcore-06-tests-are-named-after-fix-rounds-and-live-in-unrelated-files) | MDCORE | Low | Tests are named after fix rounds and live in unrelated files |
| [CC-MDCORE-07](../areas/mdcore.md#cc-mdcore-07-limits-are-named-in-some-files-and-literal-in-others) | MDCORE | Low | Limits are named in some files and literal in others |
| [CC-MDCORE-08](../areas/mdcore.md#cc-mdcore-08-converted-html-is-always-lf-and-is-inserted-unchanged-into-crlf-notes) | MDCORE | Low | Converted HTML is always LF and is inserted unchanged into CRLF notes |
| [CC-PLUGIN-08](../areas/plugin.md#cc-plugin-08-duplicated-logic-across-the-area) | PLUGIN | Low | Duplicated logic across the area |
| [CC-PLUGIN-09](../areas/plugin.md#cc-plugin-09-literal-durations-caps-and-sizes-in-host-logic) | PLUGIN | Low | Literal durations, caps and sizes in host logic |
| [CC-PLUGIN-10](../areas/plugin.md#cc-plugin-10-stale-and-history-narrating-comments) | PLUGIN | Low | Stale and history-narrating comments |
| [CC-PLUGIN-11](../areas/plugin.md#cc-plugin-11-six-functions-over-40-code-lines) | PLUGIN | Low | Six functions over 40 code lines |
| [CC-PLUGIN-12](../areas/plugin.md#cc-plugin-12-names-that-break-the-naming-rule-or-describe-the-wrong-role) | PLUGIN | Low | Names that break the naming rule or describe the wrong role |
| [CC-PLUGIN-13](../areas/plugin.md#cc-plugin-13-a-plugins-network-response-is-read-one-byte-at-a-time) | PLUGIN | Low | A plugin's network response is read one byte at a time |
| [CC-PLUGIN-14](../areas/plugin.md#cc-plugin-14-the-theme-token-cache-grows-without-bound) | PLUGIN | Low | The theme token cache grows without bound |
| [CC-READING-03](../areas/reading.md#cc-reading-03-body-writes-state) | READING | Low | `body` writes state |
| [CC-READING-06](../areas/reading.md#cc-reading-06-unowned-tasks-started-from-views) | READING | Low | Unowned tasks started from views |
| [CC-READING-07](../areas/reading.md#cc-reading-07-incident-history-and-stale-or-misplaced-comments) | READING | Low | Incident history and stale or misplaced comments |
| [CC-READING-08](../areas/reading.md#cc-reading-08-duplicated-small-rules) | READING | Low | Duplicated small rules |
| [CC-READING-09](../areas/reading.md#cc-reading-09-magic-durations-and-thresholds) | READING | Low | Magic durations and thresholds |
| [CC-READING-10](../areas/reading.md#cc-reading-10-dead-code-and-test-names-after-fix-rounds) | READING | Low | Dead code and test names after fix rounds |
| [CC-RUNTIME-04](../areas/runtime.md#cc-runtime-04-about-twenty-durations-sizes-and-counts-are-unnamed-literals) | RUNTIME | Low | About twenty durations, sizes and counts are unnamed literals |
| [CC-RUNTIME-07](../areas/runtime.md#cc-runtime-07-comments-narrate-history-or-contradict-the-code) | RUNTIME | Low | Comments narrate history or contradict the code |
| [CC-RUNTIME-08](../areas/runtime.md#cc-runtime-08-conditionals-with-identical-branches) | RUNTIME | Low | Conditionals with identical branches |
| [CC-RUNTIME-10](../areas/runtime.md#cc-runtime-10-81-own-code-lines-exceed-160-characters) | RUNTIME | Low | 81 own-code lines exceed 160 characters |
| [CC-SHELL-03](../areas/shell.md#cc-shell-03-latest-answer-wins-is-implemented-five-different-ways) | SHELL | Low | "Latest answer wins" is implemented five different ways |
| [CC-SHELL-07](../areas/shell.md#cc-shell-07-literal-durations-caps-and-sizes-in-logic) | SHELL | Low | Literal durations, caps and sizes in logic |
| [CC-SHELL-08](../areas/shell.md#cc-shell-08-comments-narrate-incidents-and-dates) | SHELL | Low | Comments narrate incidents and dates |
| [CC-SHELL-10](../areas/shell.md#cc-shell-10-large-multi-concept-files-and-small-hygiene-issues) | SHELL | Low | Large multi-concept files and small hygiene issues |
| [CC-VAULT-04](../areas/vault.md#cc-vault-04-facts-and-small-algorithms-are-duplicated-across-files) | VAULT | Low | Facts and small algorithms are duplicated across files |
| [CC-VAULT-05](../areas/vault.md#cc-vault-05-thirteen-functions-exceed-40-code-lines) | VAULT | Low | Thirteen functions exceed 40 code lines |
| [CC-VAULT-06](../areas/vault.md#cc-vault-06-size-limit-errors-name-the-editor-whatever-the-caller) | VAULT | Low | Size-limit errors name the editor whatever the caller |
| [CC-VAULT-07](../areas/vault.md#cc-vault-07-production-code-kept-only-for-tests-or-for-an-unused-option) | VAULT | Low | Production code kept only for tests or for an unused option |
| [CC-VAULT-08](../areas/vault.md#cc-vault-08-some-names-state-a-narrower-or-different-role-than-the-type-has) | VAULT | Low | Some names state a narrower or different role than the type has |
| [CC-VAULT-09](../areas/vault.md#cc-vault-09-comments-narrate-incidents-instead-of-stating-the-rule) | VAULT | Low | Comments narrate incidents instead of stating the rule |
| [CC-VAULT-10](../areas/vault.md#cc-vault-10-tests-of-the-area-are-named-after-audit-rounds-and-mix-unrelated-subjects) | VAULT | Low | Tests of the area are named after audit rounds and mix unrelated subjects |
| [CC-VOICE-06](../areas/voice.md#cc-voice-06-seven-members-are-dead-or-test-only-in-production-code) | VOICE | Low | Seven members are dead or test-only in production code |
| [CC-VOICE-08](../areas/voice.md#cc-voice-08-thresholds-and-durations-are-literals-some-duplicated) | VOICE | Low | Thresholds and durations are literals, some duplicated |
| [CC-VOICE-09](../areas/voice.md#cc-voice-09-comments-narrate-history-instead-of-stating-the-rule) | VOICE | Low | Comments narrate history instead of stating the rule |
| [CC-VOICE-14](../areas/voice.md#cc-voice-14-preparation-state-grows-without-bound-and-a-rejected-passage-is-rendered-again-on-every-visit) | VOICE | Low | Preparation state grows without bound, and a rejected passage is rendered again on every visit |
| [CC-VOICE-15](../areas/voice.md#cc-voice-15-some-names-are-generic-or-abbreviated-against-rulesmd) | VOICE | Low | Some names are generic or abbreviated against RULES.md |

## 6. Rules for new code

Each rule has a number that later documents cite, one or two sentences with "must", a check a reviewer or a script runs, and the findings it answers. Checks use `grep -rnE` over `Sources` (and `Tests`, `App/Tests` where named); where a check lists "today" counts, the number is the baseline to reach zero.

### 6.1 Failures and errors

**CC 1. `try?` states why.** `try?` must appear only where failure and absence mean the same to the caller, and the same line carries a `//` comment saying why. A `try?` on a write, a safety copy, a delete, or a read whose empty result the person would see is a defect; an empty `catch {}` follows the same rule.
*Check:* `grep -rnE 'try\?' Sources | grep -v '//'` and `grep -rnE 'catch\s*(\w+\s*)?\{\s*\}' Sources` list only lines inside the static-pattern helper (today 628 `try?` and 5 empty catches).
*Answers:* `CC-ARCH-02`, `CC-SHELL-04`, `CC-CANVAS-07`, `CC-LECTURE-14`, `CC-READING-04`, `CC-EDITOR-09`, `CC-VOICE-11`, `CC-RUNTIME-06`, `CC-VAULT-01`.

**CC 2. A failed read is never an empty result.** A function that reads stored or external data must return or throw a typed state that separates `missing`, `contents` and `unreadable(Error)`; it must never turn a failed read into `[]`, `0`, `""` or defaults. Callers treat only `missing` as "use defaults" and show `unreadable` through the presenter (CC 7).
*Check:* `grep -rnE 'try\?.*\?\? (\[\]|0|""|\[:\])' Sources` has only hits that carry a CC 1 reason (today 24 hits); each new reader has a test for all three states.
*Answers:* `CC-VAULT-01`, `CC-READING-04`, `CC-EDITOR-09`, `CC-VOICE-11`, `CC-CANVAS-07`, `CC-ARCH-02`, `CC-RUNTIME-06`.

**CC 3. A destructive step stops when its safety copy fails, and writes report failure.** A delete, overwrite, restore, replace or quit-time save must run its safety copy and its write inside `do/catch`, stop when the safety copy fails, and report a failed write to the caller and the person. Application termination must wait for the save and report its outcome.
*Check:* every command that calls `trashItem`, `removeItem`, `overwrite` or `restore` has a `do/catch` before it that returns on failure; `grep -rnE 'try\? await .*(save|write|restore|remove)' Sources` returns nothing.
*Answers:* `CC-SHELL-04`, `CC-ARCH-02`, `CC-ARCH-01`, `CC-LECTURE-14`; BUG-SHELL-03, BUG-ARCH-02, BUG-ARCH-04.

**CC 4. Unreadable stored data is kept, never overwritten.** Lists of stored data must decode element by element; an element that does not decode is kept as `unknown(raw)` and written back, and a file that does not decode as a whole is moved aside under a versioned name. Code must never write defaults over data it failed to read.
*Check:* each `grep -rnE 'try\? (JSONDecoder|PropertyListDecoder)' Sources` hit has a nil branch that does not save; every persisted enum has an `unknown(raw)` case.
*Answers:* `CC-INK-07`, `CC-VAULT-01`, `CC-VOICE-11`, `CC-CANVAS-07`.

**CC 5. Constant patterns compile through one helper.** A constant regular expression must be compiled once through one `StaticPattern` helper that fails fast on a malformed literal, and one unit test must touch every pattern. `try?` stays only for patterns a person supplies.
*Check:* `grep -rnE 'try[?!] NSRegularExpression' Sources` hits are user-pattern code only (today 53 in MDCORE and 7 in BASES with `try?`, 2 `try!`).
*Answers:* `CC-MDCORE-01`, `CC-BASES-03`.

**CC 6. Errors are typed values that carry facts.** Core, Index, Apple and Voices code must throw and return typed values with facts (`.alreadyExists(VaultPath)`, `.tooLarge(limitBytes:)`, `ReadAloudNotice.skippedHeadersAndFooters`). Callers must branch on the case, never on message text, and one catch-all case must not stand for several failures.
*Check:* `grep -rnE 'GraphiteError\.(unavailable|invalidFile|oversized)\("' Sources` returns nothing (today 84 in Core); `grep -rnE 'hasSuffix\("|\.test\(error\.message\)' Sources` returns nothing.
*Answers:* `CC-VAULT-02`, `CC-VAULT-06`, `CC-PLUGIN-05`, `CC-RUNTIME-05`, `CC-INK-08`, `CC-BASES-07`, `CC-CANVAS-03`, `CC-VOICE-10`.

**CC 7. One presenter turns failures into words.** One presenter must map typed failures to catalogue strings and decide alert or banner; code must not show `error.localizedDescription` to the person, and a feature must not hold a bare `String?` outcome, so that a second failure never overwrites the first. Detail goes to the `Logger` only.
*Check:* `grep -rnE 'localizedDescription' Sources/GraphiteUI` hits are inside the presenter or a `Logger` call (today 208 in production); `grep -rnE 'errorMessage = ' Sources` assigns only presenter output.
*Answers:* `CC-ARCH-01`, `CC-READING-05`, `CC-EDITOR-09`, `CC-SHELL-06`, `CC-LECTURE-04`, `CC-VOICE-10`.

### 6.2 Waiting, ownership and state

**CC 8. A flow with more than two states is one enum.** A lifecycle with three or more phases must be an enum with associated values, changed only by intent methods. Stored Boolean groups, `didSet` resets and sentinel offsets must not encode phases; "dragging", "stopping" and "finished while paused" are derived from the enum.
*Check:* a type with three or more stored `is…`/`has…`/`pending…` Booleans read together in one guard is rejected in review; `grep -cE '(var|let) (is|has|needs|wasPending)\w+: Bool' <file>` over a single type flags candidates.
*Answers:* `CC-PLUGIN-01` (High), `CC-EDITOR-03`, `CC-LECTURE-07`, `CC-VOICE-12`, `CC-CANVAS-01`, `CC-INK-01`; BUG-PLUGIN-01.

**CC 9. Await completion; never sleep to order work.** Code must not sleep, poll or hop to the next run-loop turn to wait for other work; it must await the completion signal (an `AsyncStream`, a continuation resumed by the owner, `onDismiss`, the task's `value`). Two exceptions exist, each through one named primitive: a bounded wait on a dedicated media queue with named limits and a documented reason, and UIKit's documented "after the current update" hop, routed through one owned scheduler.
*Check:* `grep -rnE 'Task\.sleep|asyncAfter|DispatchQueue\.main\.async|usleep|Thread\.sleep' Sources` hits are debounces or deadlines inside the shared primitives or listed exceptions (today 51 sleeps and 10 `asyncAfter`).
*Answers:* `CC-ARCH-03`, `CC-SHELL-02`, `CC-READING-02`, `CC-VOICE-02`, `CC-VOICE-03`, `CC-PLUGIN-02`, `CC-RUNTIME-03`, `CC-INK-03`, `CC-CANVAS-02`, `CC-EDITOR-02`, `CC-LECTURE-05`; exception: `CC-LECTURE-12`.

**CC 10. Every task, timer and observer has an owner that ends it.** Each `Task`, timer, observer and subscription must be stored by an owner whose teardown cancels or removes it. A `View` closure calls one synchronous model method; the model starts and stores the task. `try? await Task.sleep` is forbidden because it keeps running after cancellation.
*Check:* `grep -nE 'Task\s*(\(priority[^)]*\))?\s*\{' Sources/GraphiteUI/*Pane*.swift Sources/GraphiteUI/*View*.swift` returns nothing; `grep -rnE 'try\? await Task\.sleep' Sources` returns nothing (today 28); each `addObserver(` has a stored token and a removal.
*Answers:* `CC-ARCH-05`, `CC-ARCH-03`, `CC-READING-06`, `CC-BASES-02`, `CC-CANVAS-02`, `CC-EDITOR-02`, `CC-LECTURE-05`, `CC-VOICE-03`, `CC-PLUGIN-03`, `CC-INK-06`, `CC-INK-14`.

**CC 11. One tested primitive per timing pattern.** Debounce, "latest answer wins" and "first outcome wins" must each use one shared, tested primitive (`Debouncer`, `LatestRequest`, `withTimeout`) on an injected clock, kept in the allow-listed concurrency primitives file. A feature must not write a generation counter or a timeout race by hand; the run-identifier behaviour of `WorkspaceModel` is the specification.
*Check:* `grep -rnE 'generation|requestIdentifier|runIdentifier' Sources` hits are adopters of the primitive; `grep -rnE 'withThrowingTaskGroup|withTaskGroup' Sources` hits only in the primitives file.
*Answers:* `CC-ARCH-04`, `CC-SHELL-03`, `CC-BASES-02`, `CC-READING-06`, `CC-PLUGIN-03`, `CC-CANVAS-02`, `CC-LECTURE-05`.

**CC 12. Outcomes are returned; flags are scoped; state advances after success.** A function must return its outcome (`MoveOutcome`, `NoteEditOutcome`, `PropertyRenameReport`) instead of leaving it in a field for a later callback. A "performing own edit" flag must be set by a scoped helper with `defer`. State derived from an operation (an ink tracker, a recorded drawing) must advance only after the operation succeeds, and the result of an `await` must be applied by identifier against the current value, never against a value read before the await.
*Check:* `grep -rnE 'isPerformingEdit = (true|false)' Sources` hits only inside the scoped helper; review every `await` followed by a write computed from a pre-await local; a mutating `update` that can precede a throwing call is rejected.
*Answers:* `CC-INK-02`, `CC-INK-14`, `CC-LECTURE-13`, `CC-EDITOR-03`, `CC-READING-05`, `CC-PLUGIN-02`.

### 6.3 One owner per rule

**CC 13. One owner per rule, copies deleted.** Every business rule, fact and small algorithm must have exactly one owner with tests: frontmatter location, conflict-copy name, file URL to vault path, link text, SHA-256 hex, page-number parsing, the audio session. A deliberate fast mirror stays only with a parity test over a shared corpus, as `NoteFolding.isListItem` has.
*Check:* `grep -rnE '\\\\A---' Sources` returns one pattern; `grep -rn 'Graphite edits' Sources` returns one definition (today 4 copies of each); a new helper is reviewed against `grep` for its verbs.
*Answers:* `CC-VAULT-03`, `CC-VAULT-04`, `CC-BASES-04`, `CC-BASES-05`, `CC-SHELL-05`, `CC-ARCH-08`, `CC-ARCH-10`, `CC-ARCH-11`, `CC-INK-04`, `CC-LECTURE-03`, `CC-READING-08`, `CC-CANVAS-06`, `CC-PLUGIN-08`, `CC-RUNTIME-02`, `CC-RUNTIME-09`, `CC-MDCORE-02`, `CC-MDCORE-07`, `CC-VOICE-07`.

**CC 14. iPad and Mac editors share their decisions.** A decision that the iPad and Mac coordinators both make must live in one shared type; the platform files hold only the calls into UIKit or AppKit. A fix to a shared decision lands once.
*Check:* in `NativeMarkdownEditor.swift`, two functions of more than five lines with the same name root on the iPad and Mac side are a finding (today about 14 pairs); a new `#if os` block contains platform calls only.
*Answers:* `CC-EDITOR-04`, `CC-EDITOR-10`.

**CC 15. Domain code carries facts; the UI module writes the words.** Core, Index, Apple and Voices code must carry facts and identities only: no user-visible sentence, colour name or label. UI text comes from a string catalogue with plurals; notices, issues and problems are typed values with associated data.
*Check:* `grep -rnE 'errorDescription|explanation' Sources/GraphiteCore Sources/GraphiteIndex Sources/GraphiteApple Sources/GraphiteVoices` hits are presenters-by-protocol only; a literal sentence in a `Text("…")` outside the catalogue is flagged.
*Answers:* `CC-BASES-07`, `CC-CANVAS-03`, `CC-LECTURE-04`, `CC-VOICE-10`, `CC-SHELL-06`, `CC-VAULT-02`, `CC-INK-08`.

**CC 16. A guard every caller must remember lives at one boundary.** A bound or check that all call sites must apply is applied inside one function that nobody can bypass: `BoundedMarkdownParser.document(parsing:)` is the only place `Document(parsing:)` appears, every recursive rewriter takes a depth parameter with a named maximum, and a filter of untrusted markup is an allow list of elements and attributes, not a deny list.
*Check:* `grep -rn 'Document(parsing' Sources` returns one hit (today 5); `sanitizeHTMLToDom` names allowed, not forbidden, elements.
*Answers:* `CC-MDCORE-09`, `CC-RUNTIME-12`; BUG-MDCORE-01, BUG-MDCORE-05.

### 6.4 Shape of code

**CC 17. Functions do one thing at one level.** A function must do one meaningful thing at one level of abstraction; an orchestrating function names its stages and holds none of their details. Over 40 code lines triggers a recorded design review, over 80 needs a reason in the pull request; nesting is at most 5, parameters at most 6, lines at most 160 characters. An exhaustive single-switch mapper and a long straightforward sequence may stay whole; a SwiftUI `body` is split into named subviews; a mapping table is data, not code.
*Check:* `python3 scripts/size-report.py --list` shows no new function over 40 code lines; `grep -rnE '^.{161,}$' Sources` returns no new line (JavaScript: the formatter in the Node test script).
*Answers:* `CC-SHELL-01`, `CC-EDITOR-01`, `CC-READING-01`, `CC-MDCORE-03`, `CC-VAULT-05`, `CC-BASES-01`, `CC-CANVAS-04`, `CC-INK-12`, `CC-LECTURE-02`, `CC-VOICE-01`, `CC-PLUGIN-11`, `CC-RUNTIME-01`, `CC-RUNTIME-10`.

**CC 18. Reads do not write.** A getter, predicate, `body`, view `init`, `layoutSubviews` or `updateUIView` must not write observed state, write a file, start a task, move a view or build a service. It may write an `@ObservationIgnored` memo cache. A refresh is a named intent method called from `.task`, `.onChange` or the owning model.
*Check:* every `grep -rnE 'let _ = ' Sources/GraphiteUI` hit is reviewed against this rule (today 4); a `@State private var x = SomeSession()` initial value is flagged; a computed property containing an assignment is flagged.
*Answers:* `CC-LECTURE-06`, `CC-READING-03`, `CC-VOICE-04`, `CC-BASES-06`, `CC-EDITOR-08`, `CC-CANVAS-08`.

**CC 19. Hot paths cost the change, not the collection.** Work on the typing, drawing and scrolling paths must be proportional to the change and must stay off the main actor when it is not UI work: layout passes place geometry only, menus are built when the selection changes, parsing, diffing, encoding and serialization of payloads run in a detached task, and overlap tests use a sorted range set.
*Check:* review `layoutSubviews`, `body`, per-keystroke and per-message functions for loops over a whole collection and for calls that decode, encode or hash a payload; run `GraphiteBenchmarks` for the touched path.
*Answers:* `CC-INK-05`, `CC-VOICE-13`, `CC-VOICE-14`, `CC-PLUGIN-06`, `CC-PLUGIN-13`, `CC-CANVAS-09`, `CC-RUNTIME-11`, `CC-MDCORE-02`.

### 6.5 Facts, names and constants

**CC 20. Persisted keys are declared once.** Every persisted key, notification name and file name must be declared once in a typed registry per feature (an enum whose raw values a test pins) under one prefix rule; `@AppStorage`, models and tests use the registry.
*Check:* `grep -rnE 'forKey: "|@AppStorage\("|Key = "|suiteName: "|Notification\.Name\("' Sources` hits are only in registry files.
*Answers:* `CC-INK-09`, `CC-VOICE-05`, `CC-CANVAS-08`, `CC-ARCH-11`.

**CC 21. Identity is structure, never display text or a hash.** An identity must be computed from structured values and compared by equality; it must not be a display title or a `hashValue`. A command is found by its identifier, and one concept has one name in code, UI and docs.
*Check:* `grep -rn 'hashValue' Sources` shows no identity or key use; `grep -rnE 'first\(where: \{ \w+ in \w+\.title ==' Sources` returns nothing.
*Answers:* `CC-EDITOR-10`, `CC-EDITOR-08`.

**CC 22. No literal duration, threshold or size in logic.** A duration, cap, ratio or size must be a named constant with its unit in the name (`…Milliseconds`, `…Bytes`, `…Points`) on the type that owns the policy, declared once; values that must agree share one name. Days, months and years use `Calendar`, never `N * 86_400`.
*Check:* `grep -rnE '\.(milliseconds|seconds)\([0-9]|asyncAfter.*[0-9]|\* ?86_?400|prefix\([0-9]' Sources` hits are constant declarations only (today `WorkspaceRecovery.swift:44` and `VaultIndex.swift:237` count days in seconds).
*Answers:* `CC-SHELL-07`, `CC-EDITOR-05`, `CC-CANVAS-05`, `CC-BASES-09`, `CC-INK-10`, `CC-LECTURE-08`, `CC-VOICE-08`, `CC-READING-09`, `CC-PLUGIN-09`, `CC-RUNTIME-04`, `CC-MDCORE-07`.

**CC 23. Embedded code lives in resource files.** JavaScript, HTML, CSS and template documents of more than a few lines must live in resource files that are linted and have behaviour tests (Node or jsdom for JavaScript); a Swift string holds a one-line expression at most. SQL beside its GRDB call is outside this rule.
*Check:* `grep -rnE '"""' Sources` hits followed by `<html`, `function` or `(function` are flagged; every resource script has a test in `Tests/CommunityPluginRuntimeTests`.
*Answers:* `CC-PLUGIN-04`, `CC-SHELL-10`.

**CC 24. Comments state the current rule.** A comment must state the rule the code keeps, in the present tense. It must not carry a date, a device, the owner, "used to", "an earlier version" or an incident story; the incident goes in the commit message and in the name of the regression test. A doc comment sits directly on its declaration, and a comment that contradicts the code is a defect.
*Check:* `grep -rnE '//.*(20[0-9]{2}-[0-9]{2}-[0-9]{2}|owner|used to|earlier version|reported)' Sources` returns no incident line (today 35 dated, 14 naming the owner, 5 "used to").
*Answers:* `CC-EDITOR-06`, `CC-BASES-08`, `CC-INK-11`, `CC-LECTURE-01`, `CC-MDCORE-04`, `CC-MDCORE-05`, `CC-PLUGIN-10`, `CC-READING-07`, `CC-RUNTIME-07`, `CC-SHELL-08`, `CC-VAULT-09`, `CC-VOICE-09`, `CC-ARCH-07`.

**CC 25. Names are full words that state the role.** A name must use complete descriptive words, state the type's real role and its units, and a Boolean must read as an assertion. Generic or abbreviated names are allowed only where a platform or file-format API names them.
*Check:* review type names ending in `Manager`, `Helper`, `Utils`, `Misc`, `Handler`; `grep -rnE '\b(var|let|func) (tmp|val|res|cb|mgr|idx)\b' Sources` returns nothing.
*Answers:* `CC-VOICE-15`, `CC-VAULT-08`, `CC-PLUGIN-12`, `CC-EDITOR-10`, `CC-INK-11`, `CC-CANVAS-08`.

### 6.6 Hygiene

**CC 26. Nothing unused ships.** A declaration without a production caller must be deleted; a member that only tests call lives in the test-support target. A dead-code scan runs in CI.
*Check:* the scan (Periphery or an equivalent script) reports no unused declaration; `grep -rn '<NewName>' Sources` shows a caller for every new member.
*Answers:* `CC-INK-13`, `CC-LECTURE-11`, `CC-MDCORE-05`, `CC-READING-10`, `CC-VOICE-06`, `CC-VAULT-07`, `CC-CANVAS-01`.

**CC 27. One concept per file, named after it.** A file is split by responsibility, never by size and never as `Part1`/`Part2`. Split when the file needs a name like `Manager` or `Helper`, holds unrelated types, its parts change for different reasons, or a section could be tested alone.
*Check:* `grep -cE '^(public |final |private |fileprivate )*(struct|class|enum|actor|protocol) ' <file>` above 5 needs a recorded reason; the file name equals its main type.
*Answers:* `CC-EDITOR-07`, `CC-SHELL-10`, `CC-MDCORE-05`.

**CC 28. Every concurrency escape names its invariant.** `@unchecked Sendable`, `nonisolated(unsafe)` and `MainActor.assumeIsolated` must carry a comment on the same or the preceding line naming the invariant that makes them safe. `assumeIsolated` is allowed only inside a callback the API documents as delivered on the main queue; elsewhere the code hops with `Task { @MainActor in … }`.
*Check:* `grep -rnE -B1 '@unchecked Sendable|nonisolated\(unsafe\)|assumeIsolated' Sources` shows a comment above or beside every hit (today 20, 4 and 41).
*Answers:* `CC-ARCH-06`, `CC-LECTURE-15`.

**CC 29. No trapping on file data.** Parsing and file-handling code must not use `try!` or a force unwrap (`RULES.md`, "File integrity and error handling"); a keyed lookup repeated after a sort is replaced by carrying the pair through the sort.
*Check:* `grep -rnE 'try!|[A-Za-z\]\)]!(\.|\)|,| )' Sources/GraphiteCore Sources/GraphiteApple` shows no hit in parsing or file code.
*Answers:* `CC-LECTURE-09`, `CC-MDCORE-01`.

**CC 30. Every cache has a bound and a truthful policy.** A cache, retained collection or per-document map must have a stated bound and an eviction policy that the code implements, and the comment must describe that policy; files written per input are pruned at write.
*Check:* each `private var <name>: [Key: Value] = [:]` in a long-lived type shows removal or a bound; a test fills the cache past its bound.
*Answers:* `CC-PLUGIN-14`, `CC-VOICE-14`, `CC-VOICE-11`, `CC-CANVAS-08`, `CC-INK-06`.

### 6.7 Tests

**CC 31. Shared test support, one `waitUntil`.** A `GraphiteTestSupport` target must provide temporary vaults, isolated `UserDefaults(suiteName:)`, an injected clock, fakes that keep production semantics, and one event-based `waitUntil`. No test file defines its own.
*Check:* `grep -rnE 'func waitUntil\b' Tests App/Tests` returns one hit (today 39 in 38 files); `Package.swift` lists the target.
*Answers:* `CC-ARCH-09` (High), `CC-SHELL-09`, `CC-INK-15`, `CC-LECTURE-10`, `CC-VAULT-10`.

**CC 32. Tests are named after the type they pin.** Tests are discovered, one test class per file, in a file named after the production type (`BaseEvaluatorTests.swift`), with method names that state a behaviour in a sentence. Names with `Fix`, `Regression`, `Handoff`, a round or a date are forbidden.
*Check:* `find Tests App/Tests -name '*.swift' | grep -E 'Fix|Regression|Handoff'` returns nothing (today 31); the file name equals the class name.
*Answers:* `CC-SHELL-09`, `CC-VAULT-10`, `CC-BASES-10`, `CC-MDCORE-06`, `CC-EDITOR-11`, `CC-READING-10`, `CC-LECTURE-10`.

**CC 33. Tests assert typed values.** A test must assert cases, numbers and structures, never message text or source text.
*Check:* `grep -rnE 'localizedDescription\.contains|errorDescription.*contains|XCTAssert.*\.contains\("' Tests App/Tests` returns nothing; in JavaScript, no assertion on `error.message` or on a CSS file's source.
*Answers:* `CC-CANVAS-03`, `CC-RUNTIME-05`, `CC-LECTURE-10`, `CC-SHELL-09`, `CC-LECTURE-04`.

**CC 34. Tests are hermetic and sleep-free.** A test must not touch `UserDefaults.standard`, the real keychain, the developer's caches or index folders, or the network, and must not sleep; time comes from the injected clock and waiting from `waitUntil`. A pure type takes explicit times, as `PalmRejection` does.
*Check:* `grep -rnE 'UserDefaults\.standard|Task\.sleep|Thread\.sleep|[^a-zA-Z]sleep\(' Tests App/Tests` returns nothing (today 261 sleeps and 101 `UserDefaults.standard`).
*Answers:* `CC-ARCH-09`, `CC-SHELL-09`, `CC-INK-15`, `CC-READING-02`, `CC-LECTURE-10`, `CC-BASES-02`, `CC-VOICE-02`.

**CC 35. A characterization test precedes every move, a regression test follows every fix, and CI runs all of it.** Before code moves, a test pins its behaviour; every fixed defect gets a regression test named after the behaviour; a CI workflow runs `swift test`, the hosted simulator suite for iPad and Mac, and the Node runtime suite on every change.
*Check:* the repository holds a workflow file (none today: no `.github` folder); a pull request that fixes a BUG ID adds a test whose name states the behaviour.
*Answers:* `CC-ARCH-09` (High), `CC-MDCORE-06`, `CC-EDITOR-11`, `CC-RUNTIME-05`.

## 7. Corrections

Where the area documents or earlier text of this page disagree with the snapshot, the snapshot decides.

| Item | Area document or earlier text | Snapshot (method) | Used here |
| --- | --- | --- | --- |
| Test files named after fix rounds | `metrics.md`: 20 files named `*FixTests` or `*RegressionTests` | `find Tests App/Tests` finds 24 `*FixTests` and 3 `*RegressionTests` (27), plus 4 `*HandoffTests` (31) | 27, and 31 with the Handoff files |
| `localizedDescription` uses | `CC-ARCH-01`: about 240 | `grep -rn localizedDescription Sources App --include='*.swift'` outside `App/Tests`: 208 | 208 |
| `waitUntil` definitions | Section 2.5 as first written: 21 times in 20 hosted test files; `CC-ARCH-09` evidence: 15 hosted files | `grep -rnE 'func waitUntil\b'`: 22 definitions in 21 files under `App/Tests`, 17 more in 17 files under `Tests` (39 in 38) | 22 in 21 hosted files; 39 in 38 overall |
| Functions over 40 code lines | `metrics.md` Sizes table: 189; area table sums to 190; the findings in section 5 add to 201 | the 11 extra in the findings are JavaScript functions in RUNTIME (`CC-RUNTIME-01`), not counted by the Swift counter | 189 for Swift, 11 for JavaScript |
| Types over 300 code lines | `metrics.md` Sizes table: 39; area table sums to 41 | the two tables count by different units; the Sizes table is the reference in `metrics.md` | 39 |
| SHELL duplicated logic | SHELL verdict row: 8 kinds | `CC-SHELL-05` lists 11 rows | 11 |
