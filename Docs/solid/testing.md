# Testing

Snapshot: b13dec3 (main, 2026-10-18).

Scope: the whole test suite as it stands at the snapshot and the suite the cleanup needs. Method: read, not run. Counts come from `grep` over `Tests/` and `App/Tests/` (`func test`, `Task.sleep|Thread.sleep|usleep(|sleep(`, `UserDefaults.standard`, `temporaryDirectory`, `localizedDescription`, `XCTSkip`, `#filePath`, `Date()`), from `Graphite.xcodeproj/project.pbxproj`, and from reading `Package.swift`, the one named fake, the Node support files, `UiWorkspaceModelFixTests.swift`, `CoreLinksFixTests.swift` and a sample of every target. Where a number is a line count rather than an occurrence count, the text says so. The area audits, `metrics.md` and `Docs/solid/cross-cutting/architecture.md` (ARCH) are the cited sources for findings.

## 1. Verdict on today's suite

### 1.1 By target

| Target | Files | Test functions | What it protects | Hermeticity problems (counts) | Verdict |
| --- | ---: | ---: | --- | --- | --- |
| `GraphiteCoreTests` ([Package.swift:40](../../Package.swift#L40)) | 72 | 1,043 | Markdown semantics and parsers, the Bases evaluator, canvas file edits, tab layout, vault list, file recovery, Read Aloud text rules | Sleeps 0; `UserDefaults.standard` 0; `temporaryDirectory` 15 lines in 10 files; `Date()` 24; wall-clock thresholds 12; `XCTSkip` 3; error-text assertions 13; one test reads a gitignored folder ([CoreLinksFixTests.swift:209](../../Tests/GraphiteCoreTests/CoreLinksFixTests.swift#L209)); one reads another module's resource through `#filePath` ([NeuralReadAloudTests.swift:6-8](../../Tests/GraphiteCoreTests/NeuralReadAloudTests.swift#L6-L8)) | The strongest target and almost hermetic. Its weakness is naming (15 files after fix rounds) and a test double that production never runs (`LSP-BASES-01`, `LSP-MDCORE-03`). |
| `GraphiteIndexTests` ([Package.swift:41](../../Package.swift#L41)) | 19 | 140 | GRDB index, link resolution, search, file operations, the 36-file `BaseSampleVault` | Sleeps 2; `temporaryDirectory` 28 lines; wall-clock thresholds 5; `XCTSkip` 2; the index location takes an injected caches folder ([IndexTests.swift:160-168](../../Tests/GraphiteIndexTests/IndexTests.swift#L160-L168)) | Strong and hermetic. 4 files carry round names; 6 files carry a `Core` or `Ui` prefix naming another module (`UiBasesRecordReuseTests`, `CoreAreaIndexHandoffTests`, `CoreFilesSettingsIndexTests`, `CoreLinksFileOperationTests`, `CoreSearchQueryIndexSearchTests`, `CoreSemanticsRenameTests`). |
| `GraphiteAppleTests` ([Package.swift:42](../../Package.swift#L42)) | 25 | 272 | PDF annotations, drawing formats, recording, video parts, the Read Aloud session, real `NSFileVersion` objects | Sleeps 10 (3 in wait loops); `UserDefaults(suiteName:)` 5; `temporaryDirectory` 26 lines; real keychain 1 test ([CommunityPluginSecretStoreTests.swift:9](../../Tests/GraphiteAppleTests/CommunityPluginSecretStoreTests.swift#L9)); `XCTSkip` 7 (OS version, installed voice, hardware); error-text assertions 3 | Strong where it drives real frameworks. Hardware paths are reached through a test-only method (`adoptRecording`, 13 uses in 3 files). |
| `GraphiteUITests` ([Package.swift:43](../../Package.swift#L43)) | 66 | 641 | Workspace model, sessions, macOS editors, reading view, Bases model, conflict versions | Sleeps 76 (72 bare, 4 in loops, 32 files); `UserDefaults.standard` 26 in 7 files; four files snapshot and restore every `Graphite*` key; `temporaryDirectory` 93 lines in 45 files; the real index cache is written and removed at 6 sites; `XCTSkip` 10 (4 skip because a race did not happen); error-text assertions 7; wall-clock thresholds 5 | Valuable and the least hermetic package target. It runs against the developer's process state and wall time. |
| `GraphiteIntegrationTests` (hosted; `App/Tests`) | 26 (+ 15 `GraphiteAppleTests` and 3 `GraphiteUITests` files compiled in) | 214 | iPad UIKit behaviour: Pencil, palm rejection, PDF gestures, Live Preview placement, plugin host in WebKit, Bases views, Read Aloud highlighting | Sleeps 173 (158 bare, 15 in loops, 25 files); `UserDefaults.standard` 75 occurrences in 5 files (`PencilToolsTests.swift` alone 35); `.shared` 53 uses (46 `UIApplication.shared`); `Date()` 75; 22 private `waitUntil` copies; `XCTSkip` 7; runs inside the real app (`TEST_HOST`, [project.pbxproj:464](../../Graphite.xcodeproj/project.pbxproj#L464)) | The only coverage of iPad UIKit and WebKit behaviour, and the least reproducible. No configuration runs it automatically. |
| `Tests/CommunityPluginRuntimeTests` (Node, jsdom) | 12 test files + 2 support files (434 lines) | 85 `test(` cases | The plugin runtime against a folder on disk, 18 cases against real built plugins | `setTimeout`/`settle(` 80 uses; harness `settle()` sleeps 20 ms and `waitUntil` polls every 5 ms ([runtime-harness.js:148-165](../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L148-L165)); `--test-concurrency=1` ([package.json](../../Tests/CommunityPluginRuntimeTests/package.json)); the 18 real-plugin cases skip silently when `compatibility/built` is missing ([real-plugins.test.js:1-5](../../Tests/CommunityPluginRuntimeTests/tests/real-plugins.test.js#L1-L5)) | Broad coverage of the runtime, but it answers from a host that disagrees with production in 7 behaviours (`LSP-PLUGIN-01`, `LSP-RUNTIME-01`). |
| **Total** | 208 Swift files | 2,310 XCTest functions, 85 Node cases | | Sleeps 261; `UserDefaults.standard` 101 occurrences; `temporaryDirectory` 206 lines; `XCTSkip` 29; 25 wall-clock thresholds; 23 error-text assertions; 0 Swift Testing tests (`@Test`: 0) | Large and mostly meaningful; not discoverable by name, not hermetic above Core, not run by any CI. |

Totals check against `metrics.md` "Tests" (App 214, Apple 272, Core 1,043, Index 140, UI 641; sleeps 173/10/0/2/76; `UserDefaults.standard` 75/0/0/0/26). `metrics.md` counts occurrences; where this table says "lines" it counts matching lines.

### 1.2 What the verdict rests on

- **No shared support and no CI.** One named fake exists (`TestConflictVersionStore`). `waitUntil` is declared 41 times (22 declarations in 21 hosted files, 15 in `GraphiteUITests`, 4 in `GraphiteAppleTests`; grep `func waitUntil`). No `.github`, no workflow, no test plan in the repository (`CC-ARCH-09`). The hosted target is registered by hand: all 44 files are listed in the sources phase ([project.pbxproj:305-360](../../Graphite.xcodeproj/project.pbxproj#L305-L360)), so a new file under `App/Tests` does not run until someone edits the project.
- **Names do not locate tests.** 24 files end in `FixTests`, 3 in `RegressionTests`, 4 in `HandoffTests`, and `TestsExistingAppleServiceTests` carries a round name; 32 of 208 files. The same finding appears in five areas (`CC-BASES-10`, `CC-EDITOR-11`, `CC-MDCORE-06`, `CC-VAULT-10`, `CC-LECTURE-10`, `CC-READING-10`).
- **State and time are shared, not injected.** Four package workspace test classes copy the same `setUp`/`tearDown` that snapshots and restores every `Graphite*` default ([UiWorkspaceModelFixTests.swift:16-48](../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L16-L48), [WorkspaceConflictVersionsTests.swift:16-34](../../Tests/GraphiteUITests/WorkspaceConflictVersionsTests.swift#L16-L34), `UiSidebarPaletteFixTests`, `UiWorkspaceAreaHandoffTests`). The restore loop keys on the prefix `Graphite`, so the 19 unprefixed keys of `DIP-ARCH-03` leak. Fixed sleeps stand in for completion signals (`CC-ARCH-03`, `CC-SHELL-02`, `CC-EDITOR-02`, `CC-READING-02`, `CC-VOICE-03`); the most common delays are 300 ms (31 sites), 20 ms (30), 50 ms (29).
- **Where production accepts an instance, the suite is hermetic.** `UserDefaults(suiteName:)` appears in 22 places (UI 10, hosted 7, Apple 5), network is stubbed with `URLProtocol` where the session is injected ([UiBasesMapTilesTests.swift:22-25](../../Tests/GraphiteUITests/UiBasesMapTilesTests.swift#L22-L25), [BasesViewsTests.swift:100-109](../../App/Tests/BasesViewsTests.swift#L100-L109)), and Core stores take their folder (`FileRecoveryStore(directory:)`, [FileRecoveryTests.swift:16](../../Tests/GraphiteCoreTests/FileRecoveryTests.swift#L16)). The work is to make the same true of the rest, not to invent a new style.
- **Test names are good sentences.** `testTextTypedWhileAnotherVaultOpensIsSaved`, `testBooksGroupedGalleryAndList`, `testASecondRecordingShowsItsCameraInTheSamePreview`. The rename work is about files and homes, not test functions.

## 2. What the suite protects and what it cannot reach

### 2.1 What it protects, with examples

| Behaviour | Example | Why the test is strong |
| --- | --- | --- |
| Search tokenizing agrees with the index's tokenizer | [CoreSearchQueryUnicode61AgreementTests.swift:61](../../Tests/GraphiteCoreTests/CoreSearchQueryUnicode61AgreementTests.swift#L61) runs every assigned scalar outside ASCII through `SearchTextTokens` and through real SQLite `unicode61` | The oracle is the production dependency, not a hand-written expectation. |
| Two implementations of one rule stay equal | [NoteFoldingTests.swift:75-81](../../Tests/GraphiteCoreTests/NoteFoldingTests.swift#L75-L81) compares `NoteFolding.isListItem` with `MarkdownEditing.listLine` over 34 lines | A corpus parity test; the model for `MDCORE` (`LSP-MDCORE-01`). |
| Damaged files are refused with the file untouched | [CanvasFileTests.swift:185-198](../../Tests/GraphiteCoreTests/CanvasFileTests.swift#L185-L198) feeds 14 damaged canvas texts and compares typed `CanvasFileError` values | Table-driven and typed (the text check on the same lines is the weak part, `CC-CANVAS-03`). |
| Vault switching never loses typing | [UiWorkspaceModelFixTests.swift:115-148](../../Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift#L115-L148): a conflicted note refuses the switch with `GraphiteError.conflict`; text typed during a switch reaches the old vault's file | Exercises the production path with real files and asserts on bytes (`SHELL-INV-09`, `ARCH-INV-09`). |
| Conflict-version resolution against the real API | [FileVersionConflictTests.swift:1-40](../../Tests/GraphiteAppleTests/FileVersionConflictTests.swift#L1-L40) uses real `NSFileVersion` objects | The store runs the same code as for a provider's conflict versions. |
| Recorded movies | [VideoRecordingTests.swift:30-192](../../Tests/GraphiteAppleTests/VideoRecordingTests.swift#L30-L192) records synthetic frames and reads the MP4 back (codec, paused time, cut-off durations) | Asserts on the file a user would own. |
| Index migration and location | [IndexTests.swift:142](../../Tests/GraphiteIndexTests/IndexTests.swift#L142) (names, legacy move), `:208` (cancelled scan keeps records), `:231` (unlistable folder keeps records) | Failure paths with real SQLite files (`ARCH-INV-02`). |
| Byte preservation of Obsidian files | [BookmarkTests.swift](../../Tests/GraphiteCoreTests/BookmarkTests.swift) (`testWritingKeepsUnknownKindsKeysAndWholeNumbers`) | Pins `VAULT-INV-08`. |
| Main-thread budget on the iPad | [MainThreadResponsivenessTests.swift:51-192](../../App/Tests/MainThreadResponsivenessTests.swift#L51-L192) watches the main thread from another thread | The only guard against the freezes the owner reported; it depends on wall time (see 2.2). |
| Real plugins in the runtime | [real-plugins.test.js](../../Tests/CommunityPluginRuntimeTests/tests/real-plugins.test.js) loads built Dataview, Tasks and others at pinned commits ([compatibility-plugins.json](../../Tests/CommunityPluginRuntimeTests/compatibility/compatibility-plugins.json)) | Compatibility evidence the area cannot get from unit tests. |

Invariants whose blueprint names an existing test: 151 of 403 (section 3). That count is a lower bound: unnamed tests also cover some (for example `VaultTests.swift:5` covers parts of `VAULT-INV-04` and `-05`).

### 2.2 Tests that pass where production fails

Each row is a test double or hook that disagrees with production. These are the most dangerous tests in the suite because they report green for behaviour the app does not have.

| Double or hook | Divergence | Findings | Fix |
| --- | --- | --- | --- |
| `TestConflictVersionStore` ([TestConflictVersionStore.swift:13](../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L13)) | `replaceFile` returns success when the coordinator never ran its block (`try outcome?.get()`, [:87](../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L87)); production throws `GraphiteError.unavailable` for the same case ([FileVersionConflicts.swift:167](../../Sources/GraphiteApple/FileVersionConflicts.swift#L167)). `removeVersions` does no coordinated write ([:98-99](../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L98-L99)). Its own doc comment says it "does what `FileProviderConflictVersions` does". | `LSP-VAULT-02`, `LSP-ARCH-03` | Move to the support target, require a coordination outcome, coordinate removals, run one contract suite on both stores. |
| Node `TestVaultHost` ([test-vault-host.js](../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js)) | Seven behaviours differ from `CommunityPluginVaultBridge` (rename onto a taken name throws here, succeeds there; `vault.write` defaults to `replace` at [:186](../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L186), production refuses; `system` removal deletes permanently at [:211](../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L211)). `applyEditorChange` accepts any change with a matching snapshot identifier and never compares text ([:224-229](../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L224-L229)). The file's header claims "the two follow one contract". | `LSP-PLUGIN-01`, `LSP-RUNTIME-01`, `LSP-RUNTIME-02` | One JSON case table run by Swift against the bridge and by Node against the host. |
| `BaseInMemoryRecordProvider` ([BaseFileRecord.swift:246](../../Sources/GraphiteCore/BaseFileRecord.swift#L246)) | Disagrees with `BaseIndexRecordProvider` on four link rules; 21 Core call sites use only the in-memory provider, 4 index sites use the real one (`BaseEvaluator(formulas`/`BaseQueryEngine(` grep: 25). | `LSP-BASES-01` | Contract suite over both; in-memory provider moves to the support target and delegates name matching to the shared resolver. |
| Six private `ReadAloudSpeaking` fakes (`ControllerTestSpeech`, `PenTestSpeech`, `ReadingProbeSpeech`, `TestReadAloudSpeech`, `ScanHighlightSpeech`, `RecordingQuickSpeech`) | Each implements a subset and inherits the protocol's default `speak` that drops request fields; both production adapters implement `speak(_ request:)`. | `LSP-VOICE-02`, `LSP-VOICE-01` | One `ScriptedSpeech` in the support target that records the whole request, and a contract suite for the protocol. |
| `adoptRecording` ([RecordingController.swift:438-451](../../Sources/GraphiteApple/RecordingController.swift#L438-L451)) | A production method that exists "to reach finalization and publication without a microphone"; 13 test uses start from `.paused` or `.recording` with no recorder. | `LSP-LECTURE-03` | An `AudioRecorder` port with a fake; delete the method. |
| `drawsConcealedReplacements` ([MarkdownTextStyler.swift:198](../../Sources/GraphiteUI/MarkdownTextStyler.swift#L198)) and `NotePreviewDocument.section(of:headingAnchor:)` | A styling mode and a wrapper that only tests use; 9 assertions use the wrapper; the one `false` is [UiStylingFixTests.swift:43](../../Tests/GraphiteUITests/UiStylingFixTests.swift#L43), named after a Mac behaviour that does not exist. | `LSP-EDITOR-04`, `LSP-MDCORE-03`, `CC-VAULT-07` | Delete the hooks, point the tests at the production entry points. |
| `graphLinkResolver()`, `matchWithoutASCIIPath` | Test hooks in production types; `GraphLinkResolver` is kept equal to the SQL resolver only by a test. | `LSP-VAULT-03`, `DIP-INK-06` | Express both resolvers over one `LinkNameTable` and run one contract. |

Two further tests pass for the wrong reason. [CoreLinksFixTests.swift:209-212](../../Tests/GraphiteCoreTests/CoreLinksFixTests.swift#L209-L212) enumerates `Tests/test_vault`, which is gitignored ([.gitignore](../../.gitignore)) and absent in a clean checkout, so the loop adds no names and the assertion runs over 15 hand-written names. The Node test `the plugins page shares the default variable layer…` asserts on the CSS file's text ([themes.test.js:128-143](../../Tests/CommunityPluginRuntimeTests/tests/themes.test.js#L128-L143), `CC-RUNTIME-05`); it is a resource lint, not a behaviour test.

### 2.3 What it cannot reach

"Cannot reach" means no test can construct the type with a substitute for its I/O, clock or collaborators, so only its end-to-end path (a real vault, a real WebKit page, a real device) can pin it.

| Code | Why no seam exists | Findings |
| --- | --- | --- |
| `WorkspaceModel` (86 stored properties) | No initializer: every collaborator is a property default ([WorkspaceModel.swift:66-69](../../Sources/GraphiteUI/WorkspaceModel.swift#L66-L69), [:164-165](../../Sources/GraphiteUI/WorkspaceModel.swift#L164-L165)). Tests replace two collaborators after construction (`documentPlaceStore`, `conflictVersionStore`) and run everything else on a real vault folder, the real index cache and the shared defaults. | `DIP-ARCH-01`, `DIP-SHELL-01`, `ISP-SHELL-03` |
| Process-wide singletons and statics (11 singletons, 2 static service lets, 24 stored mutable statics) | `PencilToolbox.shared` (read in five files), `ReadingImageCache.shared`, `MainThreadWatchdog.shared`, `DocumentPlaceStore.shared`, Mac delegate's static weak workspace. Tests cannot run two instances (two windows, two palette modes) and state leaks between tests; hosted tests touch 53 `.shared` uses. | `DIP-ARCH-02`, `DIP-INK-01`, `DIP-INK-02`, `DIP-SHELL-04`, `DIP-LECTURE-01`, `CC-INK-15` |
| Time-driven logic (autosave 900 ms, save back-off, jump deadlines, external-change settle 500 ms/2 s, debounce copies) | The wall clock is read inline and 13 hand-written debounce/"latest wins" copies sleep. Tests wait for real time (261 sleeps) or assert on elapsed wall time (25 thresholds). | `DIP-CANVAS-04`, `DIP-SHELL-05`, `DIP-EDITOR-03`, `DIP-INK-05`, `DIP-LECTURE-04`, `CC-ARCH-04`, `CC-ARCH-03` |
| `GraphiteVoices` (12 files, 1,682 code lines) | The module has no test target ([Package.swift:31](../../Package.swift#L31) defines it; lines 40-43 list four test targets, none for it). No test names `NeuralVoiceDownloader`, `NeuralVoiceCatalog`, `MLXPassageRenderer`. One hosted file imports the module ([ReadAloudLectureHighlightTests.swift](../../App/Tests/ReadAloudLectureHighlightTests.swift)). The cache and downloader construct their file system, clock and session inline. | `DIP-VOICE-04`, `DIP-VOICE-02`, `BUG-VOICE-06`, `BUG-VOICE-07` |
| Plugin installers, themes and device storage | Default arguments build network sessions; no test names `CommunityPluginHost` session logic, the theme installer or the device-storage consent paths beyond one hosted file and one Core file. Start order, a hanging `plugin.load` and stop-during-start have no scripted channel. | `DIP-PLUGIN-02`, `DIP-PLUGIN-01`, `BUG-PLUGIN-01`, `BUG-PLUGIN-02` |
| Real recording path | `RecordingController` start, pause, stop with a recorder run only on hardware; `MoviePartWriter` is named by no test. | `LSP-LECTURE-03`, `CC-LECTURE-12` |
| The iPad editor coordinator | The UIKit coordinator is built by SwiftUI inside `NativeMarkdownEditor.swift`, so package tests reach only the Mac one; the iPad one is reached by 4 hosted files with sleeps. | `CC-EDITOR-11`, `LSP-EDITOR-01`, `LSP-EDITOR-02`, `LSP-EDITOR-03` |
| Failure paths of reads | A failed read answers an empty value in 7 plugin reads and in `bookmarks.json`; with no failing file access to inject, no test can distinguish "empty" from "unreadable". | `BUG-VAULT-02`, `BUG-VOICE-V01`, `CC-RUNTIME-06`, `LSP-PLUGIN-01` |
| Launch behaviour of the app | `GraphiteApp.init` starts diagnostics and the root view restores the developer's last vault; hosted tests inherit both ([GraphiteApp.swift:13](../../App/GraphiteApp.swift#L13)). No launch mode exists for tests. | `CC-ARCH-09`, `DIP-ARCH-01` |

## 3. Coverage map by area

Method. Production code lines come from `metrics.md` "Inventory by audit area" (code lines after comment and string stripping). Test functions are attributed by file name to one area (rough; the 4 `HandoffTests` files, the benchmark files and a few shared files are listed as "shared": 103 functions). Invariants are `<AREA>-INV-NN` from each area's blueprint. "Pinned" means the blueprint's test column names an existing test; "not pinned" means only a test idea is recorded. The highest-value unpinned invariants are named; the full list is in each area document.

| Area | Production code lines | Tests that cover it (functions) | Invariants pinned / total | Pinned | Not pinned (highest value first) |
| --- | ---: | --- | ---: | --- | --- |
| [SHELL](areas/shell.md) | 8,942 | `UiWorkspaceModelFixTests` (30), `UiWorkspaceAreaHandoffTests` (29, shared), `UiRootSettingsTests` (18), `UiFileManagementFixTests` (15), `TabLayoutTests` (18), `VaultListTests` (7), `DocumentPlacesTests` (4), `VaultURITests` (6), `MainThreadResponsivenessTests` (5); about 175 attributed | 20 / 32 | 02, 06, 07, 09-11, 15-24, 26, 28, 29, 31 | 01 per-vault key names, 03 preference defaults and ranges, 04 device keys and command identifiers, 05 drag types, 12 one tab per file, 13 tab close, 14 load-into-tab rule, 25 places before save, 27 Mac scenes |
| [EDITOR](areas/editor.md) | 8,062 | `UiEditor*` (11 files, about 111), `UiStylingFixTests` (16), `MarkdownEditorRetentionTests` (7), `MarkdownSession*` (11), `CoreSemanticsEditorScanningTests` (17), hosted `EditingContinuityTests` (22), `LivePreviewRevealTests` (10), `LivePreviewBlockPlacementTests` (6); about 268 attributed | 15 / 31 | 09, 12, 15-22, 25, 27, 28, 30, 31 | 01 text view creation order, 02 every edit recorded, 03 no styling during marked text, 05 every Graphite edit is one undo step, 06 undo applied exactly, 07/08 queued insertion order, 11 note bytes and BOM, 14 first responder outside updates, 29 touch within 1 s |
| [READING](areas/reading.md) | 5,431 | `UiReadingViewTests` (24), `UiReadingTaskTests` (12), `NotePreviewDocumentTests` (19), `CorePreviewFixTests` (26), `ReadingTaskTests` (16), hosted `ReadingTasksAndEquationsTests` (4); about 136 attributed | 9 / 30 | 06, 09, 13, 14, 21, 23, 24, 26, 27 | 01 fold keys, 02 fold persistence, 03 callout key, 04 link URLs, 10 closed-note edits never write over a changed file, 16 autosave, 17 `body` never reads session text, 22 image links stay in the vault |
| [MDCORE](areas/mdcore.md) | 6,895 | `CoreSemanticsParseTests` (17), `CoreSemanticsTextRulesTests` (6), `MarkdownTableTests` (51), `MarkdownInlineElementTests` (8), `MarkdownEdgeCaseRegressionTests` (16), `CrashLoopRegressionTests` (9), `CodeFormattingTests` (13), `CodeSyntaxHighlightingTests` (27), `CoreHtml*` (35), `NoteFoldingTests` (9); about 273 attributed | 5 / 26 | 02, 06, 07, 18, 25 | 01 fold keys, 04 block identifiers, 05 marker vocabulary, 08 edit ranges, 12 frontmatter bytes, 13 fence closing, 14 `$$` pairing, 15 depth limits, 24 checkpoint equivalence, 26 `%%` comments |
| [VAULT](areas/vault.md) | 7,303 | `VaultTests` (39), `CoreFilesSettingsFixTests` (23), `CoreLinksFixTests` (19), `SettingsAndAttachmentTests` (19), `ConflictVersionTests` (14), `FileRecoveryTests` (9), `BookmarkTests` (6), Index target (about 100), `FileVersionConflictTests` (13), `WorkspaceConflictVersionsTests` (20); about 298 attributed | 12 / 35 | 09, 12, 13, 18, 19, 21-23, 28, 30, 32, 34 | 01 write precondition, 03 `FileRevision` encoding, 06/07 `app.json` keys, 11 deletion rule, 14 file-name rules, 16/17 index location and migration names, 20 link resolution order, 24-26 persisted keys, 35 conflict discovery never downloads |
| [BASES](areas/bases.md) | 8,679 | `BaseEvaluatorTests` (26), `BaseQueryTests` (21), `BaseEditingTests` (18), `CoreBases*` (10 files, 157), `BaseIndexTests` (6), `BaseSampleVaultTests` (6), `UiBases*` (7 files, 54), hosted `BasesViewsTests` (4); about 294 attributed | 11 / 37 | 09, 16, 21, 26-29, 31-34 | 01-03 byte-for-byte save and read-back refusal, 10 prefilter never excludes a kept record (violated today), 11 provider link answer depends on folder, 12-20 sort, group, number and date semantics in a fixed time zone, 22 revision-checked saves, 35 scalar decode equals `JSONDecoder` |
| [CANVAS](areas/canvas.md) | 4,751 | `CanvasEditingTests` (16), `CanvasFileTests` (13), `CanvasGeometryTests` (15), `CanvasLinkTests` (9), `CanvasSessionTests` (19), hosted `CanvasTests` (10); about 82 attributed | 21 / 28 | 01-04, 06, 08-11, 13-17, 19, 20, 22, 23, 25, 26, 28 | 05 whole-number rounding and clamp, 07 connection keys, 12 duplicate `id` cards, 18 autosave 900 ms, 21 preference defaults, 24 tag and unresolved node, 27 accessibility identifiers used by hosted tests |
| [INK](areas/ink.md) | 8,118 | `DrawingGeometryTests` (20), `ShapeRecognizerTests` (17), `CoreDrawingDataFixTests` (8), `AppleDrawingFixTests` (33), `VectorDrawingTests` (13), `VectorPictureTests` (22), `PencilToolboxTests` (25), `PalmRejectionTests` (10), hosted `PencilToolsTests` (27), `PicturesAndPaperTests` (20), `InkSelectionTests` (19), `PencilWorkspaceTests` (12); about 274 attributed | 10 / 33 | 03, 08, 10, 14, 18, 19, 23-25, 33 | 01/02 PNG record chunk and digest, 04-07 payload keys, versions, limits, SVG record, 11 no file returned unless it reads back, 13 draft layout, 16 history step applies only to its drawing, 20-22 Pencil timing, hold and lasso thresholds |
| [LECTURE](areas/lecture.md) | 9,814 | `ApplePdfFixTests` (19), `PDFAnnotationTests` (16), `PDFObjectCompactionTests` (9), `UiPdfSessionFixTests` (23), `UiPdfViewsTests` (13), `PDFEditHistoryTests` (6), `VideoRecordingTests` (21), `AppleRecordingAccessFixTests` (19), `RecordingRecoveryTests` (6), hosted PDF files (24); about 200 attributed | 8 / 36 | 15, 18-20, 23, 24, 27, 30 | 01-07 PDF annotation keys and page ordering, 08 page-tree change, 10 bookmarks, 11 encrypted and signed PDFs never written, 12 save at read revision, 14 recovery folder, 21 recording transitions, 25 autosave schedule, 34 ink recorded before release |
| [VOICE](areas/voice.md) | 8,116 | `ReadAloudDocumentTests` (25), `NeuralReadAloudTests` (21), `ReadAloudSessionTests` (21), `ReadAloudControllerTests` (24), `ReadAloudPronunciationTests` (7), `PDFReadAloud*` (11), `ReadAloudMathematicsTests` (6), hosted `ReadAloudLectureHighlightTests` (17); about 164 attributed | 14 / 33 | 06, 10, 12, 15, 18-21, 25, 27, 28, 30, 31, 33 | 01-05 cache key, revision, folder, JSON shapes, 08/09 voice storage and download session, 11 preference keys, 13 remembered places, 14 pronunciation file, 23 audio-session ownership, 26 render attempt order |
| [PLUGIN](areas/plugin.md) | 4,968 | `CommunityPluginTests` (20), `ThemeTokenResolverTests` (4), `VaultThemeTokensTests` (6), `CommunityPluginSecretStoreTests` (1), hosted `CommunityPluginHostTests` (11); about 43 attributed | 17 / 37 | 02, 05, 09-11, 13, 14, 19-23, 29-31, 33, 34 | 01/03/04 `community-plugins.json` write rules, 06-08 release selection, URLs and size caps, 12 consent key, 17 all 83 operation names and 16 failure kinds, 24 start order, 25 timeouts, 28 network rules, 37 saved plugin views |
| [RUNTIME](areas/runtime.md) | 7,287 (JavaScript) | 85 Node cases in 12 files; hosted `CommunityPluginHostTests` | 7 / 28 | 07, 09, 12, 15, 17, 18, 22 | 02 source attribution, 03/04 write expectations and order, 05 `process` retry, 06 hidden paths, 08 `data.json` shape, 16 one `editor.apply` per turn, 21 `localStorage` keys, 23 unknown operation answer, 27 metadata cache limits |
| [ARCH](cross-cutting/architecture.md) | cross-cutting | `UiWorkspaceModelFixTests`, `IndexTests`, `CommunityPluginSecretStoreTests` | 2 / 17 | 02, 04 | 01 persisted key names, 03 paths outside the vault, 06 external identifiers, 07 command identifiers, 08 one workspace per process, 11 external-change deadlines, 13 queued links, 14 places before save, 15 generated file names, 17 diagnostics start |
| Shared | | The 4 `*HandoffTests`, `BugFixRegressionTests`, the benchmark, project and icon tests (103 functions) | | | |

Reading the table. Pure Core areas (MDCORE, BASES, CANVAS) have the most test functions per invariant but the lowest named pin rate in MDCORE (5 of 26) because the Markdown rules are spread over parallel implementations (`LSP-MDCORE-01`). VOICE and PLUGIN are covered mainly by tests that run through fakes the findings call unsound (2.2). INK and LECTURE persist formats the suite never pins with a golden file (section 4.4). SHELL has the highest pin rate (20 of 32) because its tests run through the real workspace; it is also the least hermetic.

## 4. Target test architecture

### 4.1 Targets

Module direction is the one in ARCH part 7.1; test targets follow it.

| Test target | Depends on | Holds | Runs |
| --- | --- | --- | --- |
| `GraphiteTestSupport` (library target in `Tests/GraphiteTestSupport`, not linked into the app) | `GraphiteCore`, `GraphiteIndex`, `GraphiteApple` ports | Fakes, builders, clock, contract suites (4.2-4.3) | Imported by every test target below |
| `GraphiteCoreTests` | `GraphiteCore`, `GraphiteTestSupport` | Pure planners, parsers, formats, corpus tests | `swift test`, macOS |
| `GraphiteStorageTests` (after the module split) | `GraphiteStorage`, support | `VaultStore`, `AtomicFileWriter`, recovery, `DeviceStateStore` over an isolated suite | `swift test` |
| `GraphiteIndexTests` | `GraphiteIndex`, support | Index, resolvers, migrations | `swift test` |
| `GraphiteAppleTests` | `GraphiteApple`, support | PDF, drawing formats, recording, conflict versions against real frameworks | `swift test` (macOS) and hosted (iPad) |
| `GraphiteVoicesTests` (new) | `GraphiteVoices`, support | Downloader with a stubbed session, cache with a clock, catalogue, render queue | `swift test` |
| `GraphiteUITests` | `GraphiteUI`, support | Models and sessions with fakes; macOS AppKit views | `swift test` (macOS) |
| `GraphiteIntegrationTests` (hosted) | app, support | iPad UIKit, WebKit, PencilKit, real touch synthesis | `xcodebuild test`, iPad simulator, in the hosted launch mode (4.5) |
| Node runtime tests | jsdom, `test-vault-host.js` | Runtime behaviour against the shared bridge case table | `npm test` |

Tests that must pass on both platforms live in one folder compiled by both the package target and the hosted target (today 18 files are compiled into both by listing them twice, [project.pbxproj:313-363](../../Graphite.xcodeproj/project.pbxproj#L313-L363)); the folder is declared once.

### 4.2 `GraphiteTestSupport` contents

Names follow `RULES.md` (full words, no abbreviations). A fake appears only where a real substitution or isolation need exists.

| Support type | Fakes or builds | Replaces today |
| --- | --- | --- |
| `TemporaryVault` | A folder with files, created per test, symlinks resolved, removed in teardown | 206 `temporaryDirectory` lines, `makeVault` copies in 45 UI files |
| `IsolatedDeviceState` | A `UserDefaults(suiteName:)` with a unique name behind the `DeviceStateStore` | The snapshot/restore in 4 classes; 101 `UserDefaults.standard` occurrences |
| `ManualClock` | The injected clock (`Clock` conformer); `advance(by:)` resumes sleepers in order | 261 sleeps and 25 elapsed-time assertions |
| `awaitCondition(timeout:_:)` | The one polling helper for platform events the test does not own (a WebKit load, an AVFoundation callback); fails with a message, never sleeps a fixed time | 41 `waitUntil` declarations |
| `FakeConflictVersionStore` | `ConflictVersionStore` (moved from `TestConflictVersionStore`; requires a coordination outcome, coordinates removals) | `LSP-VAULT-02` |
| `ScriptedSpeech` | `ReadAloudSpeaking`; records the whole `speak` request, scripted events | 6 private fakes |
| `FakePassageRenderer`, `FakeSpeechAligner` | `NeuralPassageRendering`, `ReadAloudSpeechAligning` (from `ToneRenderer`, `EvenAligner`) | Two private fakes in one hosted file |
| `ScriptedAudioRecorder` | The proposed `AudioRecorder` port | `adoptRecording` |
| `SyntheticCaptureSource` | `VideoCaptureSource` (moved from `VideoRecordingTestSupport.swift`) | A support class living inside one test target |
| `InMemoryBaseRecordProvider` | `BaseRecordProvider`; name matching delegated to the production resolver | `BaseInMemoryRecordProvider` in `GraphiteCore` |
| `InMemoryVaultFiles`, `FailingVaultFiles` | The proposed `VaultFiles` and `DocumentFileAccess` ports; the second injects a failure per operation | No fault injection today; `BUG-VAULT-02`, `BUG-VOICE-V01` |
| `ScriptedHTTPDownloader` | The proposed `HTTPDownloading` port | `DIP-PLUGIN-02`, `DIP-VOICE-04` |
| `InMemorySecretStore` | The proposed secret-storage port | The one real-keychain test |
| `ScriptedRuntimeChannel` | The proposed `CommunityPluginRuntimeChannel` | `BUG-PLUGIN-01`, `BUG-PLUGIN-02` |
| `HostedWindow`, `SynthesizedTouches` | A window with a root controller and teardown; touch synthesis (moved from `App/Tests/SynthesizedTouches.swift`) | Hand-rolled windows in 20+ hosted files |
| `CorpusFile` loader | Reads a fixture through `Bundle.module` | `#filePath` navigation in 4 tests |

### 4.3 Contract suites

A contract suite is one parameterised `XCTestCase` (or Node `describe`) that every implementation runs: production, fake and in-memory. Protocols with more than one implementation today, and cross-implementation rules without a protocol:

| Seam | Implementations today | Contract suite | Findings |
| --- | --- | --- | --- |
| `ConflictVersionStore` | `FileProviderConflictVersions`; `TestConflictVersionStore` | `ConflictVersionStoreContractTests`: stale replace, absent destination, missing version, refused coordination, failed removal | `LSP-VAULT-02`, `LSP-ARCH-03` |
| `BaseRecordProvider` ([BaseFileRecord.swift:234](../../Sources/GraphiteCore/BaseFileRecord.swift#L234)) | `BaseIndexRecordProvider`; `BaseInMemoryRecordProvider`; test wrapper `CountingRecordProvider` | `BaseRecordProviderContractTests`: aliases, duplicate names, rooted and relative links, non-ASCII case, failure injection | `LSP-BASES-01` |
| `ReadAloudSpeaking` | `AppleReadAloudSpeech`, `NeuralReadAloudSpeech`, 6 private test fakes | `ReadAloudSpeakingContractTests`: event order, stale request rejection, pause and resume, speed range, route-change pause, no `.cancelled` after the adapter's own stop | `LSP-VOICE-01`, `LSP-VOICE-02`, `BUG-VOICE-04`, `BUG-VOICE-08` |
| `ReadAloudSpeechAligning` | `OnDeviceSpeechAlignment`; `EvenAligner` | Alignment ranges monotonic and inside the passage | `LSP-VOICE-01` |
| `NeuralPassageRendering` | `MLXPassageRenderer`; `ToneRenderer` | Cancel releases the model; sample rate and duration reported | `BUG-VOICE-07` |
| `VideoCaptureSource` | `CameraCaptureSource`; `SyntheticCaptureSource` | Frame delivery order and format; camera runs it on device only | `CC-LECTURE-12` |
| `RetainableMarkdownEditor` | The UIKit and AppKit `Coordinator`s; `RecordingEditor` | Suspend releases block views on both coordinators | `LSP-EDITOR-02` |
| `MarkdownStyledTextView` (`UITextView`, `NSTextView`) | Two platform extensions | `TextViewEditApplierContractTests`: one edit is one undo step, selection mapped, viewport kept; the Mac fallback refuses and reports | `LSP-EDITOR-03` |
| `LassoCanvasContent` | `InfiniteCanvasView`, `PDFPageCanvasView`, `SelectedPicturesContent` | One lasso-picture-editing contract | `LSP-INK-01`, `OCP-INK-01` |
| Editor session duties (no protocol yet) | iPad and Mac coordinators serve different parts | `EditorSessionDutiesContractTests`: run by the package (Mac) and the hosted target (iPad) | `LSP-EDITOR-01` |
| Link resolution (no protocol yet) | SQL `resolvedPaths`, `GraphLinkResolver`, the workspace resolver, the reading-view resolver, the runtime's JavaScript | `LinkResolutionContractTests` over one fixture vault; the runtime row runs under Node | `LSP-ARCH-02`, `LSP-VAULT-03`, `LSP-READING-03`, `BUG-VAULT-01` |
| Name count (no protocol) | The planner's SQL count; the resolver's path list | Count equals the resolver's path count for the bare name | `LSP-VAULT-01` |
| Drawing format readers | PNG, SVG, PDF readers | `DrawingFormatReadingContractTests`: round trip, stale digest, corrupt record, oversize, unreadable all return the same reading enum | `LSP-INK-01`, `OCP-INK-01` |
| PDF signature detection | `PDFSignatureDetection` (used), `PDFStructureInspection.hasDigitalSignature` | One owner, one contract over `/Perms`, `/DSS`, `SigFlags` | `LSP-LECTURE-01` |
| Plugin vault bridge (cross-language) | `CommunityPluginVaultBridge` (Swift); `TestVaultHost` (Node) | One JSON case table of request and expected answer, run by a Swift test and a Node test | `LSP-PLUGIN-01`, `LSP-RUNTIME-01` |
| Document file access | `VaultStore`; the canvas and PDF document-file capabilities | One failure-injecting contract (save conflict, vanished file) | blueprint CANVAS |
| `LinkNameTable` (proposed) | SQL table; in-memory dictionary | Same lookups, same 50-result ordering (`sorted()` against `ORDER BY path`) | `LSP-VAULT-03` |

### 4.4 Golden tests for persisted formats

No golden file exists in the repository: the only non-Swift fixtures are `QwenBabbling.m4a` and the 36-file `Tests/BaseSampleVault`. Every format below is generated and re-read inside one test, so a change that alters both the writer and the reader passes. Each row gets a checked-in fixture per shipped version, a round-trip test, an unknown-field preservation test, and a corrupt-file test that proves the file is moved aside, not overwritten.

| Format | Owner | Invariants | Fixture to add |
| --- | --- | --- | --- |
| Drawing PNG with `grPK` chunk | Core drawing data, Apple drawing writer | `INK-INV-01`, `-02`, `-04`, `-05`, `-06` | PNG per payload version 3, 4, 5; digest recomputed from the visible chunks |
| Drawing SVG with `graphite-drawing` metadata | Apple vector writer | `INK-INV-07` | SVG per version; `urn:graphite:drawing:1` |
| Drawing PDF with embedded record | Apple PDF writer | `INK-INV-08`, `LECTURE-INV-01` | One-page PDF |
| PDF annotations (`GraphitePencilDrawingV1`, groups, stamps, highlights) | `PDFAnnotation` code | `LECTURE-INV-01` to `-08` | A PDF with ink, a picture and markup; load, change page tree, assert keys kept |
| Bookmarks (PDF outline `"Page "` items) | `PDFBookmark` code | `LECTURE-INV-10`, `LSP-LECTURE-04` | PDF outline with legacy labels |
| `bookmarks.json` | `Bookmark` model | `VAULT-INV-08` | JSON with unknown kinds and keys; `BUG-VAULT-02` unreadable file |
| `.base` | Bases editing | `BASES-INV-01` to `-03` | Unedited save is byte-identical; every `Tests/BaseSampleVault` file |
| `.canvas` | Canvas file | `CANVAS-INV-01` to `-07` | Obsidian specification sample plus damaged-file table |
| Tab layout (`GraphiteTabLayout.<UUID>`) | `TabLayout.saved` | `VAULT-INV-25`, `SHELL-INV-01` | JSON per shipped layout version |
| Vault list (`GraphiteKnownVaults`) | `VaultLibrary` | `VAULT-INV-24`, `SHELL-INV-02` | JSON with an undecodable entry and the legacy bookmark |
| Device-state keys | `DeviceStateKey` registry | `ARCH-INV-01`, `SHELL-INV-03`, `-04` | A table of key, type, default, encoding, written through the new store and read with the old literal |
| Document places | `DocumentPlaceStore` | `VAULT-INV-26`, `BUG-ARCH-07` | JSON keyed per vault |
| Recordings (recovery folder, CAF to M4A, names) | `RecordingRecovery` | `LECTURE-INV-14` to `-17`, `ARCH-INV-03`, `-15` | A recovery folder with converted M4A beside its CAF; part 10 ordering |
| Read Aloud cache `index.json` and details JSON | `ReadAloudAudioCache` | `VOICE-INV-01` to `-05` | Index with an unknown file; key golden for fixed input |
| Pronunciation file `.graphite/pronunciations.json` | Pronunciation store | `VOICE-INV-14`, `BUG-VOICE-V01`, `BUG-VOICE-10` | File with hand-written IPA kept after an edit |
| Neural voice manifest | `NeuralVoiceManifest` | `VOICE-INV-08` | Already tested ([NeuralReadAloudTests.swift:25](../../Tests/GraphiteCoreTests/NeuralReadAloudTests.swift#L25)); read it through the module bundle |
| `community-plugins.json`, plugin `data.json` | Plugin settings | `PLUGIN-INV-01`, `-03`, `RUNTIME-INV-08` | Exact bytes with two-space indent |
| Drawing drafts (`.svg` + `.json`) | `DrawingEditorDraftStore` | `INK-INV-13`, `ARCH-INV-03`, `BUG-INK-01` | Draft with a background colour |
| Index migrations | `VaultIndex` | `VAULT-INV-17`, `ARCH-INV-02` | The ordered migration-name list |

### 4.5 Hermetic, clock-driven tests

- **Hosted launch mode.** `GraphiteApp.init` reads a launch mode parsed once (ARCH part 7.2, `.hostedTests`): no vault restore, no diagnostics start, defaults in an isolated suite, `Caches` and `Application Support` redirected to a temporary root. The hosted target passes the argument; the app never reads it from a view.
- **Injected clock.** Every debounce, autosave, back-off and deadline takes the `Clock`. Tests advance a `ManualClock`. The shared `Debouncer` and `LatestRequest` primitives (`CC-ARCH-04`) get one test each; copies disappear.
- **No sleeps.** Waiting is awaiting the task or advancing the clock. The one allowed poll is `awaitCondition` for platform events the test does not own.
- **In-memory defaults.** Models take a `DeviceStateStore`; tests give each its own suite.
- **Parallel by default.** CI runs `swift test --parallel`; a test that touches a shared static fails there first.

### 4.6 Platform tests

| Framework behaviour | Where it runs | Why |
| --- | --- | --- |
| TextKit 2 layout, Live Preview block placement, first responder, input method marked text | Hosted iPad simulator for UIKit; package on macOS for AppKit | The text system differs per platform and cannot be faked. |
| PencilKit strokes, palm rejection, hold-to-straighten, lasso | Hosted iPad simulator with synthesized touches | `SynthesizedTouches` exists ([SynthesizedTouches.swift](../../App/Tests/SynthesizedTouches.swift)); it moves to the support target. |
| PDFKit documents, annotation writing, thumbnails | Package on macOS where the code is shared; hosted for `PDFView` gestures | Annotation bytes are checked on macOS; gesture priority only on iPad. |
| AVFoundation recording, movie parts, audio session | Package on macOS with `SyntheticCaptureSource`; device only for the camera and microphone | Hardware stays outside CI; the synthetic path covers writer logic. |
| `NSFileVersion`, coordination | Package on macOS (`#if os(macOS)`) | The API is macOS only; the fake covers iPad. |
| WebKit plugin host | Hosted iPad simulator | One real `WKWebView` page per test class, scripted channel elsewhere. |
| Keychain | One platform test per target with a real keychain; everything else uses `InMemorySecretStore` | Entitlement behaviour differs per platform. |

Shared logic must not need a platform test: if UIKit is required to test a rule, the rule is in the wrong layer (`LSP-EDITOR-01`, `CC-EDITOR-11`).

### 4.7 JavaScript runtime suite

- Keep jsdom and the real-plugin cases. Replace `TestVaultHost` answers with the shared case table and make the host keep snapshot text, refuse read-only notes, throw on rename onto a taken name, refuse an unexpected `vault.write` expectation, and send `vault.changes` in the shape production sends (`LSP-RUNTIME-01`, `LSP-RUNTIME-02`).
- Add a message-vocabulary test: every operation in `community-plugin-messages.json` has a handler in the runtime and a case in the Swift enum (`PLUGIN-INV-17`).
- Replace `settle()` (20 ms) and the 5 ms poll with an injected scheduler in the runtime's `coalescedNotifier`, as the RUNTIME blueprint specifies.
- The 18 real-plugin cases fail, not skip, in CI: the build step `npm run build-compatibility-plugins` runs in the nightly job and the test fails when a plugin is missing.

### 4.8 CI

| Job | Trigger | Command | Gate |
| --- | --- | --- | --- |
| `swift-test-macos` | every push | `swift test --parallel` with a scratch path outside iCloud for local runs | No failure; skip count not above the recorded baseline |
| `hosted-ipad` | every push | `xcodebuild test -scheme Graphite -destination <iPad simulator>` with `-only-testing:GraphiteIntegrationTests` | No failure; no `Task.sleep` added (grep gate) |
| `runtime-node` | every push | `npm ci && npm test` in `Tests/CommunityPluginRuntimeTests` | No failure |
| `size-report` | every push | `python3 scripts/size-report.py` | Exit status 0 |
| `nightly` | daily | `npm run build-compatibility-plugins && npm test`; `GRAPHITE_BENCHMARKS=1` benchmark runs on Mac and iPad | Real-plugin cases run; benchmark numbers recorded |
| `registration-check` | every push | Fails when a `func test` file under `App/Tests` is absent from the hosted target (until the folder is synchronized) | New hosted test files cannot be forgotten |

A red job blocks the commit that the owner pushes; sessions never disable a test to pass.

## 5. Migration backlog

Each item is its own commit, leaves the app building, and names the findings or invariants it answers. Phase 0 comes first and changes no production code except where a defect fix is the point.

### Phase 0: pin behaviour and prove the defects, before any structural change

| ID | Work | Files | Answers |
| --- | --- | --- | --- |
| T-01 | Run the three suites once; record pass, skip and failure counts per target and the list of 29 skipped sites in `Docs/Coverage.md`. Run `swift test --parallel` and record what fails. This is the baseline every later item is compared with. | `Docs/Coverage.md` | `CC-ARCH-09` (results not reproducible) |
| T-02 | Make the Core test that enumerates the gitignored `Tests/test_vault` self-contained: a constant corpus of names. | `Tests/GraphiteCoreTests/CoreLinksFixTests.swift:202-215` | `CC-ARCH-09` |
| T-03 | Make the Node host faithful where it hides defects: compare snapshot text and refuse read-only in `applyEditorChange`, throw on rename onto a taken name, refuse `vault.write` without an expectation. The tests that now fail are the regression tests of `BUG-RUNTIME-01` and `BUG-PLUGIN-03`; fix the production defect in the same commit series. | `Tests/CommunityPluginRuntimeTests/support/test-vault-host.js`, `tests/editor-commands.test.js`, `tests/vault.test.js` | `LSP-RUNTIME-01`, `LSP-PLUGIN-01` rows 1 and 4, `BUG-RUNTIME-01`, `BUG-PLUGIN-03` |
| T-04 | Regression tests for the five High defects (table 5.1). Each is written to fail on b13dec3 and pass on the fix. | See table | `BUG-SHELL-03`, `BUG-MDCORE-01`, `BUG-CANVAS-01`, `BUG-VOICE-V01`, `BUG-RUNTIME-01` |
| T-05 | Regression tests for the 33 Confirmed Medium defects (table 5.1). Where the table says "seam", write the test at the production entry point now and move it to the seam when T-20 to T-29 land. | See table | `defects.md` "Fix before the cleanup starts" |
| T-06 | Golden tests of persisted keys, defaults and paths written against literal strings: `GraphitePreferences` keys, per-vault keys, `GraphiteKnownVaults`, `GraphiteTabLayout`, `GraphiteDocumentPlaces`, `GraphiteRecentCommands` identifiers, `Application Support`/`Caches` paths, bundle and UTType identifiers (read `Info.plist`). Later pointed at the registry without editing the literals. | New `Tests/GraphiteUITests/PersistedIdentifierTests.swift`, `Tests/GraphiteCoreTests/PersistedPathTests.swift` | `ARCH-INV-01`, `-03`, `-06`, `-07`, `SHELL-INV-01` to `-05`, `VAULT-INV-24` to `-26` |
| T-07 | Characterization of link resolution: one fixture vault and a table of (source, target, expected) run against the SQL resolver, `GraphLinkResolver`, the workspace resolver and the reading-view resolver, recording today's answers; each divergence is a named row tagged with its defect. | New `Tests/GraphiteIndexTests/LinkResolutionCorpusTests.swift` plus a shared corpus file | `LSP-ARCH-02`, `LSP-VAULT-03`, `LSP-READING-03`, `BUG-VAULT-01`, `BUG-ARCH-05`, `BUG-READING-03` |
| T-08 | Characterization of Markdown line rules: one corpus (fences in quotes and callouts, `$$`, setext and ATX headings, lists, code spans) classified by each consumer (scanner, folding, reading view, index, typing helpers), recording today's answers. | New `Tests/GraphiteCoreTests/MarkdownRuleParityTests.swift` | `LSP-MDCORE-01`, `MDCORE-INV-13`, `-14`, `-24`, `BUG-MDCORE-02`, `-04` |
| T-09 | Golden fixtures for drawing PNG, SVG, PDF (one per shipped payload version), PDF annotations, `.base`, `.canvas`, `bookmarks.json`, `community-plugins.json`: generated once from the current writers, reviewed byte by byte, committed. | New `Tests/GraphiteAppleTests/Fixtures/`, `Tests/GraphiteCoreTests/Fixtures/` | `INK-INV-01` to `-07`, `LECTURE-INV-01` to `-08`, `BASES-INV-01` to `-03`, `CANVAS-INV-01` to `-07`, `VAULT-INV-08`, `PLUGIN-INV-01`, `-03` |
| T-10 | Characterization of the workspace invariants the first refactors touch: vault switching with a dirty note and a failing store, graphite links queued before restore, places before save, external-change deadlines (`externalRefreshDeadline`), generated file names under a non-Gregorian locale. Use the existing `UiWorkspaceModelFixTests` style until T-14. | `Tests/GraphiteUITests/UiWorkspaceModelFixTests.swift` (split by type at T-30) | `ARCH-INV-09` to `-15`, `SHELL-INV-09`, `-16`, `-25`, `BUG-ARCH-02`, `BUG-ARCH-04` |
| T-11 | Table-driven tests for the Bases evaluator in a fixed time zone and calendar, so results do not depend on the machine. | `Tests/GraphiteCoreTests/BaseEvaluatorTests.swift` | `BASES-INV-12` to `-20` |
| T-12 | Pin the unpinned high-value invariants of EDITOR, LECTURE, VOICE and PLUGIN with a test of the behaviour they state (the "Not pinned" column of section 3), one item per area. | Area test files named in section 3 | `EDITOR-INV-05`, `-06`, `-07`; `LECTURE-INV-11`, `-12`, `-21`; `VOICE-INV-01` to `-05`, `-13`; `PLUGIN-INV-17`, `-24` |

#### 5.1 Defect regression tests (Phase 0, T-04 and T-05)

Test names are behaviour sentences; the defect ID goes in the commit message, not the name. "Seam" means the clean test needs a port from T-13 to T-29; write the test through the production entry point now.

| Defect | Target and file | Behaviour pinned |
| --- | --- | --- |
| `BUG-SHELL-03` | UI package (macOS), new `GraphiteApplicationDelegateTests.swift` | Quitting with a note that cannot be saved asks instead of discarding (seam: `ARCH-INV-12` fake store) |
| `BUG-MDCORE-01` | UI package, `UiReadingViewTests.swift` | Deeply nested Markdown with a post-processing plugin on does not terminate; runs on a thread with a 512 KB stack |
| `BUG-CANVAS-01` | Hosted, `CanvasTests.swift` | Undo while typing in a text card keeps the typed text |
| `BUG-VOICE-V01` | Core, `ReadAloudPronunciationTests.swift` | An unreadable pronunciation file is never replaced by the one new entry |
| `BUG-RUNTIME-01` | Node, `editor-commands.test.js` | An asynchronous edit after a note switch goes to the original note or fails (needs T-03) |
| `BUG-SHELL-01` | UI package, new `WorkspaceDeepLinkTests.swift` | A `graphite://read` link that does not resolve reads nothing |
| `BUG-EDITOR-01` | UI package (macOS), `UiEditorMacEditorTests.swift` | Closing a tab stores the place shown on screen |
| `BUG-EDITOR-02` | UI package (macOS), new `WorkspaceCommandsTests.swift` | "Search current file" opens a search |
| `BUG-EDITOR-04` | UI package (macOS), `UiEditorMacEditorTests.swift` | Returning from reading view shows the passage that was read |
| `BUG-READING-01` | Core `NoteFoldingTests.swift` and UI `UiReadingViewTests.swift` | Reading-view fold keys equal `NoteFolding` keys for headings with links, highlights and comments |
| `BUG-READING-02` | UI package, `UiReadingViewTests.swift` | A callout with markup in its title keeps one expansion state across reading view and Live Preview |
| `BUG-READING-03` | UI package, `UiReadingViewTests.swift` | A folder is not a link target (seam: shared resolver, T-21) |
| `BUG-MDCORE-02` | Core, `CoreSemanticsEditorScanningTests.swift` | Return inside a fenced block in a quote adds no list markup |
| `BUG-MDCORE-04` | Core, `NotePreviewDocumentTests.swift` | Setext headings appear in the outline, heading links and section embeds |
| `BUG-VAULT-01` | Index, `FileOperationTests.swift` | Renaming to a name shared except for a non-ASCII capital does not rewrite bare links |
| `BUG-VAULT-02` | Core, `BookmarkTests.swift` | An unreadable `bookmarks.json` reports an error, not "no bookmarks" (seam: `FailingVaultFiles`) |
| `BUG-BASES-03` | Index, `BaseIndexTests.swift` | `file.hasLink(file("Name"))` includes notes when a root note has that name |
| `BUG-CANVAS-02` | UI package, `CanvasSessionTests.swift` | Edits made while the canvas moves are kept |
| `BUG-CANVAS-03` | UI package (macOS), new `CanvasBoardMacTests.swift` | A long card's content scrolls |
| `BUG-INK-01` | Hosted, `PicturesAndPaperTests.swift` | A recovered draft keeps the chosen background |
| `BUG-INK-02` | Hosted, `PencilToolsTests.swift` | The held shape equals the committed shape at zoom 0.5, 1 and 3 |
| `BUG-INK-03` | Hosted, `PicturesAndPaperTests.swift` | Two quick taps on Rotate Image Right turn the picture twice with two undo steps |
| `BUG-LECTURE-01` | Apple, `RecordingRecoveryTests.swift` | A lecture whose save failed is offered once and saved once |
| `BUG-VOICE-01` | UI package, `ReadAloudControllerTests.swift` | Stop between two PDF pages stops the next page |
| `BUG-VOICE-03` | Apple, `ReadAloudSessionTests.swift` | Sentence skips keep the audio session (seam: session owner) |
| `BUG-VOICE-04` | Apple, `ReadAloudSessionTests.swift` | High Quality honours the reported speed range (seam: contract suite T-20) |
| `BUG-VOICE-05` | Apple, `ReadAloudSessionTests.swift` | Under VoiceOver the speed control works (seam: accessibility flag) |
| `BUG-VOICE-07` | `GraphiteVoicesTests`, new | Cancel and delete release the model (T-27) |
| `BUG-VOICE-08` | `GraphiteVoicesTests`, new | A route change pauses High Quality reading (T-27, scripted audio session) |
| `BUG-VOICE-10` | Core, `ReadAloudPronunciationTests.swift` | Editing one pronunciation keeps hand-written IPA |
| `BUG-PLUGIN-01` | Hosted, `CommunityPluginHostTests.swift` | Off then on again leaves plugins on (seam: `ScriptedRuntimeChannel`) |
| `BUG-PLUGIN-02` | Hosted, `CommunityPluginHostTests.swift` | A plugin whose `onload` never settles does not stop later plugins |
| `BUG-PLUGIN-03` | Hosted and Node `vault.test.js` | `renameFile` onto an existing name answers `exists` |
| `BUG-PLUGIN-04` | Hosted, `CommunityPluginHostTests.swift` | A changed formula value with the same rows sends `basesView.update` |
| `BUG-PLUGIN-06` | Hosted, `CommunityPluginHostTests.swift` | Leaving a vault keeps the saved plugin views |
| `BUG-RUNTIME-02` | Node, `obsidian-conventions.test.js` | A `Mod` shortcut fires |
| `BUG-RUNTIME-03` | Node, `file-views.test.js` | A view opened in the current tab appears and closes |
| `BUG-ARCH-07` | UI package, `ReadAloudControllerTests.swift` | A remembered place belongs to one vault |

### Phase 1: support target and hermeticity

State of Phase 1 on the working tree of `solid-audit-standard`, 2026-10-19, uncommitted: no item is Done and none is Not started. The hosted iPad suite (`GraphiteIntegrationTests`) has not been run since these changes, and the CI workflow that runs it ([ci.yml](../../.github/workflows/ci.yml)) is configured, not yet run. The changes the hosted target needs (a reference to `GraphiteTestSupport`, the shared files in one folder, the iOS 27 deployment target, which the project still sets to 18.0) are not in the project file.

| ID | State | Work | Files | Answers |
| --- | --- | --- | --- | --- |
| T-13 | **Partly done.** `GraphiteTestSupport` is a target ([Package.swift:41](../../Package.swift#L41)), the fake keeps production semantics ([FakeConflictVersionStore.swift:95-131](../../Tests/GraphiteTestSupport/FakeConflictVersionStore.swift#L95-L131)), `TestConflictVersionStore.swift` is deleted and `ConflictVersionStoreContractTests` (8 cases, macOS only) runs against the fake and `FileProviderConflictVersions` ([ConflictVersionStoreContractTests.swift:34-53](../../Tests/GraphiteAppleTests/ConflictVersionStoreContractTests.swift#L34-L53)); the Xcode project has no reference to the target, so the hosted target cannot build it, and no run of the suite is recorded. | Create `GraphiteTestSupport` (target in `Package.swift`, reference in the project). Move `TestConflictVersionStore` as `FakeConflictVersionStore`, fix its two divergences, add `ConflictVersionStoreContractTests` run against `FileProviderConflictVersions` (`.everyOtherVersion`, macOS) and the fake. | `Package.swift`, `Graphite.xcodeproj/project.pbxproj`, `Tests/GraphiteUITests/TestConflictVersionStore.swift`, `Tests/GraphiteAppleTests/FileVersionConflictTests.swift` | `LSP-VAULT-02`, `LSP-ARCH-03`, `CC-ARCH-09` |
| T-14 | **Partly done.** `TemporaryVault` ([TemporaryVault.swift:13](../../Tests/GraphiteTestSupport/TemporaryVault.swift#L13)) is used by 135 test files and `IsolatedDeviceState` ([IsolatedDeviceState.swift:7](../../Tests/GraphiteTestSupport/IsolatedDeviceState.swift#L7)) by 25; package workspace tests build on `IsolatedWorkspaceDevice` ([IsolatedWorkspaceDevice.swift:16](../../Tests/GraphiteUITests/IsolatedWorkspaceDevice.swift#L16)) in place of the snapshot and restore pairs, and `ProcessServices` ([ProcessServices.swift:10](../../Sources/GraphiteUI/ProcessServices.swift#L10)) stands in for the `DeviceStateStore`; `temporaryDirectory` in tests is 79 lines (175), but the 25 hosted files keep 33 of them and 72 `UserDefaults.standard` lines, and 55 tests still call `WorkspaceModel()` on the live services. | `TemporaryVault` and `IsolatedDeviceState`; replace the four snapshot/restore `setUp` pairs, the `makeVault` copies and direct `temporaryDirectory` use (206 lines). The defaults part needs the `DeviceStateStore` of ARCH step 2; until then the helper wraps a suite and the model reads it through the existing `UserDefaults` parameters. | `Tests/GraphiteTestSupport/`, 45 UI files, 18 Index files, 14 Apple files, 23 hosted files | `CC-ARCH-09`, `CC-SHELL-09`, `DIP-ARCH-03` |
| T-15 | **Partly done.** `ManualClock` ([ManualClock.swift:15](../../Tests/GraphiteTestSupport/ManualClock.swift#L15)) drives 7 test files, and an injected `ApplicationClock` times the canvas autosave, the PDF save back-off and autosave and the workspace external-change debounce (`CanvasSessionAutosaveTests`, `PDFSessionAutosavePolicyTests`, `WorkspaceExternalRefreshTimingTests`); `func waitUntil` is declared twice, the support one ([WaitUntil.swift:13](../../Tests/GraphiteTestSupport/WaitUntil.swift#L13)) and the hosted target's copy ([HostedWaitUntil.swift:7](../../App/Tests/HostedWaitUntil.swift#L7)); `awaitCondition` is not built (`waitUntil` is the name); the editor's touch and heading-pin windows still read `systemUptime` ([NativeMarkdownEditor.swift:104](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L104), [NativeMarkdownEditor.swift:2334](../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L2334)); test sleeps are 229 raw lines (261). | `ManualClock` and `awaitCondition`; one `waitUntil` replaces the 41 declarations; inject the clock into canvas autosave, editor jump windows, PDF save back-off, external-change debounce first, then convert their sleeps. | `Tests/GraphiteTestSupport/`; `CanvasSessionTests`, `UiEditorEditTrackingTests`, `UiPdfSessionFixTests`, `UiWorkspaceModelFixTests` | `CC-ARCH-03`, `DIP-CANVAS-04`, `DIP-EDITOR-03`, `DIP-SHELL-05`, `CC-SHELL-02` |
| T-16 | **Partly done.** `GraphiteApp.init` parses `LaunchMode` once ([GraphiteApp.swift:17](../../App/GraphiteApp.swift#L17), [LaunchMode.swift:7-35](../../Sources/GraphiteCore/LaunchMode.swift#L7-L35)); a hosted launch restores no vault, starts no diagnostics and uses a private preferences suite and temporary Caches and Application Support folders ([ProcessServices.swift:41-54](../../Sources/GraphiteUI/ProcessServices.swift#L41-L54)), pinned by `LaunchModeTests` and `WorkspaceDeviceStateTests`; the scheme arguments are unchanged (XCTest's variables select the mode), the drawing draft store, voice catalogue, audio cache and theme token cache still use the system folders, and a test that builds its own `WorkspaceModel()` gets the live services. | Hosted launch mode: `GraphiteApp.init` parses `.hostedTests` once; no vault restore, no diagnostics, isolated defaults, temporary `Caches` and `Application Support`. | `App/GraphiteApp.swift`, `Graphite.xcodeproj` scheme arguments | `CC-ARCH-09`, `ARCH-INV-17`, `DIP-ARCH-01` |
| T-17 | **Partly done.** The hosted target takes `App/Tests` as a synchronised folder since commit `fc115f3` ([project.pbxproj:212-214](../../Graphite.xcodeproj/project.pbxproj#L212-L214)), which `scripts/check-test-registration.py` checks; the shared-folder move is not started: the project's exception set still lists 18 shared files, one the deleted `TestConflictVersionStore.swift` ([project.pbxproj:53-70](../../Graphite.xcodeproj/project.pbxproj#L53-L70)). | Hosted target: synchronized folder so files are discovered; move the 18 doubly-compiled files into one shared folder declared once. | `Graphite.xcodeproj/project.pbxproj`, `App/Tests/`, `Tests/GraphiteAppleTests/` | `CC-ARCH-09` |
| T-18 | **Partly done.** `DocumentPlaceStore` is passed in through `ProcessServices` ([ProcessServices.swift:16-21](../../Sources/GraphiteUI/ProcessServices.swift#L16-L21)); `PencilToolbox.shared`, `ReadingImageCache.shared` and `MainThreadWatchdog.shared` are still read in 8 test lines ([PencilToolsTests.swift:454](../../App/Tests/PencilToolsTests.swift#L454), [UiLivePreviewEmbedContinuityTests.swift:73](../../Tests/GraphiteUITests/UiLivePreviewEmbedContinuityTests.swift#L73), [MainThreadResponsivenessTests.swift:53](../../App/Tests/MainThreadResponsivenessTests.swift#L53)) and the hosted tests still write `UserDefaults.standard`. | Remove statics from tests: `PencilToolbox`, `DocumentPlaceStore`, `ReadingImageCache`, `MainThreadWatchdog` are passed in. Depends on ARCH steps 3 and 7. | `App/Tests/PencilToolsTests.swift`, `PencilWorkspaceTests.swift`, `Tests/GraphiteUITests/` | `DIP-ARCH-02`, `DIP-INK-01`, `DIP-INK-02`, `CC-INK-15` |

### Phase 2: contract suites and shared fakes

| ID | Work | Files | Answers |
| --- | --- | --- | --- |
| T-19 | `FakeSpeech`/`ScriptedSpeech` and `ReadAloudSpeakingContractTests`; delete the six private fakes. | `Tests/GraphiteUITests/ReadAloud*Tests.swift`, `Tests/GraphiteAppleTests/ReadAloudSessionTests.swift`, `App/Tests/ReadAloud*Tests.swift` | `LSP-VOICE-01`, `LSP-VOICE-02` |
| T-20 | `BaseRecordProviderContractTests`; move the in-memory provider to support; re-point the 21 Core call sites. | `Sources/GraphiteCore/BaseFileRecord.swift`, `Tests/GraphiteCoreTests/Base*Tests.swift`, `Tests/GraphiteIndexTests/BaseIndexTests.swift` | `LSP-BASES-01` |
| T-21 | `LinkResolutionContractTests` over the corpus of T-07, with one resolver policy and a `LinkNameTable`; the runtime row runs under Node. | `Tests/GraphiteIndexTests/`, `Tests/CommunityPluginRuntimeTests/tests/` | `LSP-ARCH-02`, `LSP-VAULT-03`, `LSP-READING-03`, `BUG-VAULT-01`, `BUG-READING-03` |
| T-22 | Shared plugin bridge case table (JSON) read by a Swift test against `CommunityPluginVaultBridge` and by Node against the host. | `Tests/CommunityPluginRuntimeTests/support/`, new `Tests/GraphiteCoreTests/CommunityPluginVaultBridgeTests.swift` | `LSP-PLUGIN-01`, `LSP-RUNTIME-01`, `LSP-RUNTIME-02` |
| T-23 | Editor contract suites run on the Mac coordinator (package) and the iPad coordinator (hosted): session duties, undo as one step, suspend releases views. | `Tests/GraphiteUITests/UiEditorMacEditorTests.swift`, `App/Tests/EditingContinuityTests.swift` | `LSP-EDITOR-01`, `LSP-EDITOR-02`, `LSP-EDITOR-03`, `CC-EDITOR-11` |
| T-24 | Drawing-format reading contract; PDF signature contract; lasso contract. | `Tests/GraphiteAppleTests/`, `Tests/GraphiteUITests/InkLassoTests.swift` | `LSP-INK-01`, `OCP-INK-01`, `LSP-LECTURE-01` |
| T-25 | `ScriptedAudioRecorder` and `RecordingController` start, pause, stop, publish through the production path; delete `adoptRecording` and its 13 uses. | `Sources/GraphiteApple/RecordingController.swift`, `Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift`, `RecordingControlsTests.swift`, hosted `VideoRecordingWorkspaceTests.swift` | `LSP-LECTURE-03`, `BUG-LECTURE-01` |
| T-26 | Delete test-only hooks and point tests at production entry points: `drawsConcealedReplacements`, `NotePreviewDocument.section(of:headingAnchor:)`, `graphLinkResolver()`, `matchWithoutASCIIPath`. | `Tests/GraphiteUITests/UiStylingFixTests.swift`, `Tests/GraphiteCoreTests/NotePreviewDocumentTests.swift`, `CorePreviewFixTests.swift`, `CoreLinksFixTests.swift` | `LSP-EDITOR-04`, `LSP-MDCORE-03`, `CC-VAULT-07`, `DIP-INK-06` |
| T-27 | `GraphiteVoicesTests`: downloader with a stubbed session (progress, checksum failure, resume, retry), cache with `ManualClock`, catalogue, render queue, route-change pause. | `Package.swift`, new `Tests/GraphiteVoicesTests/` | `DIP-VOICE-04`, `BUG-VOICE-06`, `BUG-VOICE-07`, `BUG-VOICE-08` |
| T-28 | Plugin installers, theme installer and device storage with `ScriptedHTTPDownloader` and `InMemorySecretStore`; keep one real-keychain test. | `Tests/GraphiteCoreTests/CommunityPluginTests.swift`, `Tests/GraphiteAppleTests/CommunityPluginSecretStoreTests.swift` | `DIP-PLUGIN-02`, `DIP-PLUGIN-01`, `BUG-PLUGIN-05` |
| T-29 | Scripted runtime channel for session lifecycle: start during stop, hanging `plugin.load`, start order, unknown operation answer. Node harness takes an injected scheduler in place of `settle()` and the 5 ms poll. | `Tests/GraphiteUITests/`, `Tests/CommunityPluginRuntimeTests/support/runtime-harness.js` | `BUG-PLUGIN-01`, `BUG-PLUGIN-02`, `PLUGIN-INV-24`, `CC-RUNTIME-03` |

### Phase 3: names and homes

| ID | Work | Files | Answers |
| --- | --- | --- | --- |
| T-30 | Rename and split the 32 round-named files so each file is named after one production type: for example `UiWorkspaceModelFixTests` becomes `WorkspaceModelVaultSwitchingTests`, `WorkspaceModelExternalChangeTests`, `WorkspaceModelAttachmentTests`; `CoreBasesEvaluatorFixTests` merges into `BaseEvaluatorTests`; `CoreAreaHandoffTests` splits by the type each test pins. Move `UiBasesRecordReuseTests` and the four `Core…` files in `GraphiteIndexTests` to the target of their type. Keep test functions; they are already behaviour sentences. | The 24 `*FixTests`, 3 `*RegressionTests`, 4 `*HandoffTests` and `TestsExistingAppleServiceTests` | `CC-BASES-10`, `CC-EDITOR-11`, `CC-MDCORE-06`, `CC-VAULT-10`, `CC-LECTURE-10`, `CC-READING-10`, `CC-SHELL-09` |
| T-31 | Move shared helpers repeated in three or more files (windows, vault builders, expectation helpers) into support; one production type per test file. | All five Swift test folders | `CC-ARCH-09` |

### Phase 4: remove fragile assertions and add gates

| ID | Work | Files | Answers |
| --- | --- | --- | --- |
| T-32 | Replace the 25 wall-clock thresholds with operation-count budgets (nodes visited, rows built) in correctness tests; keep time in the opt-in benchmark files. | `CoreAreaHandoffTests`, `CoreHtml*`, `LinkGraphTests`, `IndexSearchFixTests`, `UiFileTreeMacTests`, `MainThreadResponsivenessTests` and others | `CC-ARCH-03`, `TR 13` |
| T-33 | Replace the 23 error-text assertions with typed error or `WorkspaceAlert` case assertions once errors are typed (ARCH step 5). | `CoreAreaHandoffTests.swift:221,251`, `BaseEvaluatorTests.swift:204-210`, `CanvasSessionTests.swift:396-397`, `UiFileManagementFixTests.swift:66,159`, others | `CC-ARCH-01`, `CC-CANVAS-03`, `CC-SHELL-09` |
| T-34 | Turn the 4 race-dependent `XCTSkip` sites into gated tests (a gate the test releases) and keep skips only for missing platform capability with a reason constant. | `UiSidebarPaletteFixTests.swift:146`, `UiFileManagementFixTests.swift:142,155`, `UiWorkspaceModelFixTests.swift:309` | `CC-ARCH-03` |
| T-35 | CI workflow with the six jobs of 4.8, the registration check, and the skip-count gate. | New CI workflow definition (host chosen by the owner), `scripts/` | `CC-ARCH-09` |

## 6. Testing rules

Each rule is a "must", with how a reviewer checks it and the findings it answers.

**TR 1 Tests are discovered, not registered.** Every test file under a test folder runs without editing a project file; the hosted target uses a synchronized folder. Check: add an empty failing test under `App/Tests` and see CI fail. Answers `CC-ARCH-09`.

**TR 2 A test file is named after the production type it pins.** `WorkspaceModelVaultSwitchingTests`, never `UiWorkspaceModelFixTests`, `…HandoffTests`, `…RegressionTests` or a date. A test function is a behaviour sentence. Check: the file name appears as a type in `Sources/`. Answers `CC-BASES-10`, `CC-EDITOR-11`, `CC-MDCORE-06`, `CC-VAULT-10`, `CC-LECTURE-10`, `CC-READING-10`.

**TR 3 A test lives in the target of the module that owns the type.** No `GraphiteCore` type is tested from `GraphiteIndexTests`. Check: imports of the test file match its folder. Answers `CC-ARCH-09`.

**TR 4 Tests exercise the production path.** No production member exists for tests; a seam is an injected port with a fake in the support target. Check: grep the diff for `// tests`, `forTesting`, and a doc comment naming tests. Answers `LSP-LECTURE-03`, `LSP-EDITOR-04`, `LSP-MDCORE-03`, `DIP-INK-06`, `CC-VAULT-07`, `CC-VOICE-06`.

**TR 5 A fake lives once, in `GraphiteTestSupport`, and keeps production semantics.** It fails where production fails (coordination refused, stale revision, missing file) and records the whole request. No private fake of a shared protocol inside a test file. Check: the fake runs the protocol's contract suite. Answers `LSP-ARCH-03`, `LSP-VAULT-02`, `LSP-VOICE-02`, `LSP-BASES-01`.

**TR 6 Every interface with more than one implementation has one parameterised contract suite that every implementation runs.** Production, fake and in-memory alike. Check: a new conformer or a new fake appears in the suite's list of subjects in the same commit. Answers `LSP-VAULT-02`, `LSP-BASES-01`, `LSP-VOICE-01`, `LSP-EDITOR-01`, `LSP-INK-01`, `LSP-ARCH-02`.

**TR 7 A rule implemented in two languages has one case table that both run.** Swift and Node read the same JSON. Check: the Node host has no behaviour the table does not assert. Answers `LSP-PLUGIN-01`, `LSP-RUNTIME-01`, `LSP-RUNTIME-02`.

**TR 8 No sleeps.** Test code contains no `Task.sleep`, `Thread.sleep`, `usleep`, `sleep` or `setTimeout` used as a delay. Waiting is awaiting the task or advancing the `ManualClock`. The one exception is `awaitCondition` for a platform event the test does not own, with a deadline and a failure message. Check: grep the diff. Answers `CC-ARCH-03`, `CC-SHELL-02`, `CC-EDITOR-02`, `CC-READING-02`, `CC-VOICE-03`, `CC-CANVAS-02`, `CC-INK-15`.

**TR 9 Tests are hermetic.** No `UserDefaults.standard`, real keychain, `Caches`, `Application Support`, network, shared singleton or wall clock. Each test builds its own `DeviceStateStore` over an isolated suite, its own temporary folder and its own clock. The single exception is one real-keychain platform test per target. Check: grep the diff for the named APIs and `.shared`. Answers `CC-ARCH-09`, `DIP-ARCH-02`, `DIP-ARCH-03`, `CC-SHELL-09`, `DIP-SHELL-04`.

**TR 10 Temporary files come from `TemporaryVault`.** No direct `FileManager.default.temporaryDirectory`; the helper resolves symlinks and removes the folder in teardown. Check: grep. Answers `CC-ARCH-09`.

**TR 11 Assertions are on typed values.** Errors are compared as enum cases or `WorkspaceAlert` cases, never through `localizedDescription` or `errorMessage` text. A string catalogue test asserts the wording of each case once. Check: grep `localizedDescription` and `.errorMessage` in assertions. Answers `CC-ARCH-01`, `CC-CANVAS-03`, `CC-SHELL-09`, `CC-LECTURE-10`, `CC-RUNTIME-05`.

**TR 12 No test reads source text or navigates the repository.** No assertion on a `.swift` file's contents (none today); module resources are read through the module's bundle, not `#filePath` (4 tests today). A resource lint in Node may read a resource file. Check: grep `#filePath` outside assertion helpers. Answers `CC-RUNTIME-05`, `CC-ARCH-09`.

**TR 13 Correctness tests assert operation counts, not elapsed time.** Budgets of nodes, rows or steps replace seconds; time budgets live in the opt-in benchmark files and record numbers. Check: grep `timeIntervalSince`, `XCTAssertLessThan(` with a time. Answers `CC-ARCH-03`, `DIP-SHELL-05`.

**TR 14 A skip names a missing platform capability.** `XCTSkip` is for an OS version, an installed voice, hardware or a volume property, with the reason in one constant. A skip because a race did not happen is a defect in the test. The skip count is recorded and may not rise. Node real-plugin cases fail when unbuilt in CI. Check: the CI skip gate. Answers `CC-ARCH-09`.

**TR 15 Characterize before you move.** A refactor commit that moves behaviour is preceded by a commit that pins that behaviour and is green on the old code. Check: the pin commit exists and touches no `Sources/`. Answers every Phase 0 item.

**TR 16 Every fixed defect has a regression test named for the rule.** The test fails on the commit before the fix; the defect ID is in the commit message. Check: the fix commit contains a test file change. Answers `defects.md`.

**TR 17 Every persisted format has a golden fixture per shipped version.** Plus a round trip, an unknown-field preservation test, a corrupt-file test showing the file is moved aside, and an explicit date and number encoding. Check: the format appears in 4.4 with a checked-in file. Answers `ARCH-INV-01`, `INK-INV-01`, `LECTURE-INV-01`, `BASES-INV-01`, `CANVAS-INV-01`, `VAULT-INV-08`.

**TR 18 Platform behaviour is tested where it runs; shared logic is tested without a platform.** TextKit, PencilKit, PDFKit gesture and WebKit behaviour run on macOS in the package or on the iPad simulator hosted; if UIKit is needed to test a rule, the rule moves out of the view. Check: a hosted test names no pure rule. Answers `LSP-EDITOR-01`, `CC-EDITOR-11`, `CC-INK-15`.

**TR 19 A failed read is never an empty result in a test oracle either.** Every reader and writer has a failure-injection test (`FailingVaultFiles`) proving the error surfaces and the file is untouched. Check: each new reader has a test with a failing file access. Answers `BUG-VAULT-02`, `BUG-VOICE-V01`, `CC-RUNTIME-06`, `CC-ARCH-02`.

**TR 20 Pure planners are tested with values and an injected `now`.** No file system, no clock in the test of a decision. Check: the planner test imports no file API. Answers `DIP-SHELL-05`, `DIP-VAULT-01`, `ARCH-INV-11`.

**TR 21 Tests run in parallel.** CI passes with `swift test --parallel`; a test that needs serial execution is a defect (shared static). Check: the CI job. Answers `DIP-ARCH-02`, `CC-INK-15`.

**TR 22 Helpers repeated in three files move to the support target.** A helper copied into a third file is moved in the same commit. Check: grep for the helper's signature. Answers `CC-ARCH-09`.

**TR 23 CI runs the whole suite on every target on every push.** `swift test`, the hosted iPad suite, the Node suite and `scripts/size-report.py`; a red job blocks the push; no session disables a test to pass. Check: the workflow file. Answers `CC-ARCH-09`.

## 7. Corrections

Where the audit documents and the snapshot disagree, the snapshot decides.

| Document and claim | Snapshot | Decision |
| --- | --- | --- |
| ARCH `CC-ARCH-09`: "`*FixTests` 26, `BugFixRegressionTests` 1" | 24 files end in `FixTests` and 3 in `RegressionTests` (`BugFixRegressionTests`, `CrashLoopRegressionTests`, `MarkdownEdgeCaseRegressionTests`); the by-target split (Core 14, Index 3, Apple 3, UI 7) holds | The total 27 is right; the split between the two suffixes is 24 and 3. 4 `HandoffTests` and `TestsExistingAppleServiceTests` raise the round-named files to 32. |
| `metrics.md` "Tests": "20 test files are named after an audit round or fix" | `find` for `*FixTests.swift` gives 24, `*RegressionTests.swift` 3, `*HandoffTests.swift` 4 | 27 by the stated method (`*FixTests`, `*RegressionTests`); `metrics.md` is wrong by 7. |
| ARCH: "the `waitUntil` helper is redefined in 15 hosted test files" | `func waitUntil` is declared 41 times: 22 in 21 hosted files, 15 in `GraphiteUITests`, 4 in `GraphiteAppleTests` | 41 declarations; the 15 counted a single loop form (`while !condition(), Date() < deadline`). |
| ARCH: tests "snapshot and restore the real `UserDefaults.standard`"; "the developer's real preferences" | In `swift test` the standard domain belongs to the test runner process, shared by all tests of the run; in hosted tests it is the app's own domain | Both are shared mutable state; only the hosted run writes the app's preferences. Four package classes carry the same snapshot/restore code. |
| ARCH: "no `Scripts` folder" and "there is no CI configuration" | `scripts/size-report.py` and `scripts/solid-metrics.py` exist in the snapshot; their docstrings point to `Docs/solid/`, so they are audit tooling; no workflow, plan or `.github` exists | ARCH's CI claim stands. `size-report.py` becomes a CI job (4.8). |
| ARCH: "a test enumerates `Tests/test_vault`, which does not exist" | The folder is listed in [.gitignore](../../.gitignore) (`Tests/test_vault/`) | It is a developer-local folder: absent in a clean checkout, possibly present on the owner's machine, so the test's input differs per machine. |
| ARCH and `Docs/Coverage.md`: test counts "982 Core, 140 Index, 249 Apple", hosted "342 tests", Node "84" | `func test` declarations: Core 1,043, Index 140, Apple 272, UI 641, hosted 214; Node 85 `test(` cases | Declaration counts are verifiable by grep and agree with `metrics.md`; `Coverage.md` holds older run results. Run results (passed, skipped) remain unverifiable until T-01. |
| `LSP-BASES-01`: "21 call sites run without a provider against 4 index-provider sites" | Grep of `BaseEvaluator(formulas` and `BaseQueryEngine(` over Core and Index tests gives 25 sites | Consistent (21 + 4). |
| `LSP-PLUGIN-01` rows 1, 2, 4, 5 (Node host) and `LSP-VAULT-02` (`:87`, `:98-100`) | [test-vault-host.js:80](../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L80), [:186](../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L186), [:211](../../Tests/CommunityPluginRuntimeTests/support/test-vault-host.js#L211) and [TestConflictVersionStore.swift:87](../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L87), [:98-99](../../Tests/GraphiteUITests/TestConflictVersionStore.swift#L98-L99) match | Findings hold; the fake's range ends at line 99 (ARCH cites 98-100). |
| ARCH: the hosted target compiles "26 files from `App/Tests`, 15 from `GraphiteAppleTests` and 3 from `GraphiteUITests`" | The sources phase lists 26 + 15 + 3 = 44 test files (plus `GraphiteApp.swift` in the app phase) | Confirmed. |
