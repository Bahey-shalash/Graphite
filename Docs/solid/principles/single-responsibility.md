# Single responsibility (SRP)
Snapshot: b13dec3 (main, 2026-10-18).

This page is the synthesis of the single-responsibility findings (prefix `SRP`) of the twelve area audits and the cross-cutting architecture audit. It is written from those documents and from the code at b13dec3; every count of findings comes from [findings-index.md](../findings-index.md) (75 `SRP` findings: 13 High, 48 Medium, 14 Low), every size from [metrics.md](../metrics.md) or from the area document named beside it. Defect IDs below link to their verified verdicts and calibrated severities in [defects.md](../defects.md).

In Graphite's terms a single responsibility means: one type owns one aggregate (one open vault, one note's text, one canvas file, one reading) and one kind of work (deciding, storing, presenting, or adapting a platform API). The cleanup reads this page as the S part of the standard; the rules in section 6 are the ones review enforces.

## 1. Verdict by area

| Area | Area's own S verdict | High | Medium | Low | Total | Reason, with the area's numbers |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| [SHELL](../areas/shell.md) | Weak | 2 | 4 | 0 | 6 | `WorkspaceModel` holds 86 stored properties and 74 functions in its main file plus 24 `extension` blocks; `GraphiteRootView` holds 16 state properties, 12 presentations and a 172-code-line `body`. |
| [EDITOR](../areas/editor.md) | Weak | 1 | 3 | 1 | 5 | The iPad `NativeMarkdownEditor.Coordinator` holds 47 stored properties and 93 functions over 16 responsibilities; `MarkdownSession` holds 34 stored properties and 5 callback slots other objects fill. |
| [READING](../areas/reading.md) | Weak | 0 | 6 | 2 | 8 | `MarkdownPreview.swift` declares 64 types in 2,293 code lines; the `MarkdownPreview` view has 37 stored properties and 7 jobs; "edit a note, open or closed" is written 3 times with 3 save rules. |
| [MDCORE](../areas/mdcore.md) | Mixed | 0 | 4 | 2 | 6 | `MarkdownTable`, `Footnotes`, `DisplayMathLines` and `NoteFolding` do one job each; `ObsidianInlineMarkup` carries 11 duties, `HTMLToMarkdown.Converter` 18 stored properties, `MarkdownSemantics.swift` 18 types. |
| [VAULT](../areas/vault.md) | Mixed | 0 | 3 | 2 | 5 | 28 of 34 files hold one small value with one rule; `VaultStore` carries 10 responsibilities behind 24 public methods plus 8 in extensions, `VaultIndex` 12 responsibilities over 5 files. |
| [BASES](../areas/bases.md) | Mixed | 1 | 2 | 2 | 5 | `BaseEvaluator` holds 14 stored properties and 58 methods in 1,005 code lines; `BaseDocumentModel` holds 28 stored properties; link resolution has 5 implementations. |
| [CANVAS](../areas/canvas.md) | Mixed | 1 | 3 | 1 | 5 | The 7 Core files own one concern each; `CanvasSession` holds 34 stored properties over 8 responsibilities; views do file I/O in 5 places. |
| [INK](../areas/ink.md) | Mixed | 1 | 4 | 1 | 6 | 15 Core and Apple format files are cohesive; `HistoryCanvasView` holds 35 stored properties over 9 jobs, `InfiniteCanvasView` adds 27, `InkSelectionController` holds 21 in 658 code lines. |
| [LECTURE](../areas/lecture.md) | Weak | 2 | 5 | 0 | 7 | `PDFAnnotationCoordinator` holds 37 stored properties over 13 responsibilities in 735 code lines; `PDFSession` holds 46; `RecordingController` holds 26 and runs audio, video, publication and recovery. |
| [VOICE](../areas/voice.md) | Weak | 2 | 3 | 0 | 5 | `ReadAloudController` holds 39 stored properties over 8 jobs with 3 reset lists; `ReadAloudDocument.markdown` is 273 code lines; `ReadAloudNavigator` holds 19 over 7 jobs. |
| [PLUGIN](../areas/plugin.md) | Weak | 1 | 3 | 2 | 6 | `CommunityPluginHost` holds 63 stored properties and 88 members over 6 files with 12 responsibilities; `stopRuntime` resets 35 fields and misses 13. |
| [RUNTIME](../areas/runtime.md) | Weak | 1 | 4 | 1 | 6 | `plugins.js` is one 1,324-code-line closure with about 18 responsibilities and 28 handlers; the global `GraphitePluginRuntime` namespace has 50 members written from 11 files. |
| [ARCH](../cross-cutting/architecture.md) | Weak | 1 | 4 | 0 | 5 | `WorkspaceModel` spans 2,695 code lines over 23 files; `GraphiteUI` is one module of 153 files and 46,253 code lines (57 % of production code) holding every feature and the composition root. |
| **All** | — | **13** | **48** | **14** | **75** | |

**App-wide verdict: Weak.** Eight of thirteen audits rate single responsibility Weak and five Mixed; none rates it strong, and every one of the 13 High findings is an object or rule in the coordinating layer, not in the pure Core values. The pure parsers, file formats and decision values largely meet the principle, while each feature's coordinating object (workspace, editor coordinator, PDF coordinator and session, canvas session, history canvas, Read Aloud controller, plugin host, runtime namespace) is an aggregate of 34 to 86 stored properties that owns several workflows and their shared mutable state.

## 2. Systemic patterns

Seven patterns explain the 75 findings. They are ordered by cost: the first produces 10 of the 13 High findings, the last costs readability only. Counts of commits per file are the area auditors' reconnaissance figures (242 commits in the snapshot's history). Calibrated bug severities come from [defects.md](../defects.md).

### 2.1 Feature aggregates that own several workflows and their shared mutable state

**What it is.** One class, struct or closure holds the state of a whole feature (or of the whole app) and every workflow of it, so each workflow reads and writes the fields of all the others. The platform delegate, the view model and the feature's rules are the same object.

**Where it occurs.** Ten of the 13 High findings and 17 Medium findings: `SRP-SHELL-01`, `SRP-ARCH-01`, `SRP-SHELL-04`, `SRP-SHELL-06` (SHELL, ARCH); `SRP-EDITOR-01`, `SRP-EDITOR-02`, `SRP-EDITOR-04` (EDITOR); `SRP-READING-01`, `SRP-READING-04` (READING); `SRP-INK-01`, `SRP-INK-02`, `SRP-INK-04` (INK); `SRP-LECTURE-01`, `SRP-LECTURE-02`, `SRP-LECTURE-03` (LECTURE); `SRP-VOICE-01`, `SRP-VOICE-02`, `SRP-VOICE-03`, `SRP-VOICE-04`, `SRP-VOICE-05` (VOICE); `SRP-PLUGIN-01` (PLUGIN); `SRP-CANVAS-01` (CANVAS); `SRP-BASES-01`, `SRP-BASES-02` (BASES); `SRP-VAULT-01`, `SRP-VAULT-02` (VAULT); `SRP-RUNTIME-01` (RUNTIME, in JavaScript). Section 3 lists the sizes.

**Evidence.**

- `WorkspaceModel` declares its stored state at [WorkspaceModel.swift:12-209](../../../Sources/GraphiteUI/WorkspaceModel.swift#L12-L209) and in three more places further down, and 24 `extension WorkspaceModel` blocks in 23 other files add behaviour (grep at the snapshot).
- `CommunityPluginHost` declares 63 stored properties at [CommunityPluginHost.swift:166-291](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L166-L291); one switch, `receiveNotification`, writes into seven responsibility groups ([CommunityPluginHost.swift:936-1053](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L936-L1053)).
- The iPad editor coordinator spans [NativeMarkdownEditor.swift:771-2325](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L771-L2325) and conforms to five protocols; `textViewDidChangeSelection` alone moves the selection out of folds, records it, publishes it, reveals markup, schedules code formatting and updates suggestions ([NativeMarkdownEditor.swift:1692-1708](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L1692-L1708)).
- `PDFSession` holds 46 stored properties and weak references to views ([PDFSession.swift:212-339](../../../Sources/GraphiteUI/PDFSession.swift#L212-L339)); its `go(to:)` calls into `PDFView` ([PDFSession.swift:597-603](../../../Sources/GraphiteUI/PDFSession.swift#L597-L603)).
- `CanvasSession` holds 34 stored properties at [CanvasSession.swift:67-156](../../../Sources/GraphiteUI/CanvasSession.swift#L67-L156); undo, typed text, viewport and gestures share them.
- The same shape at function size: `ReadAloudDocument.markdown` runs masking, the leaf walk, assembly and character mapping in one 273-code-line function with four nested functions sharing mutable locals ([ReadAloudDocument.swift:296-589](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L296-L589)), and `pageText` does the same for PDF text in 149 ([ReadAloudDocument.swift:79-237](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L79-L237)); the reading view and Live Preview also call this builder for highlight mapping.
- The Pencil path: `HistoryCanvasView` ([HistoryCanvasView.swift:14](../../../Sources/GraphiteUI/HistoryCanvasView.swift#L14)) records history, binds tools, and runs shape recognition, the held shape, the even highlighter and the render cover in one `PKCanvasView` subclass that every PDF page and the drawing editor use.

**Cost.**

- Every feature change edits the same object: `NativeMarkdownEditor.swift` 41 of 242 commits, `MarkdownPane.swift` 36, `WorkspaceModel.swift` 29, `GraphiteRootView.swift` 28, `MarkdownPreview.swift` 25, `GraphitePDFView.swift` 23, `CommunityPluginHost.swift` 21, `PDFPane.swift` 19, `plugins.js` 16, `ReadAloudController.swift` 15 (the change hotspots of each area).
- Nothing is testable alone. The editor coordinator is declared under `#if canImport(UIKit)` ([NativeMarkdownEditor.swift:5](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift#L5)), so `swift test` on macOS never compiles it; the 11 plugin-host tests need a hosted app and a WebKit page; the `PDFSession` and `CanvasSession` tests must construct a store, a snapshot and an undo manager.
- `@Observable` makes the size a performance cost: a view that reads one property of `WorkspaceModel` is invalidated by writes to unrelated features, which is why the tab projections at [WorkspaceModel.swift:40-52](../../../Sources/GraphiteUI/WorkspaceModel.swift#L40-L52) exist.
- The top priorities of `OBJECTIVE.md` sit inside these objects: a change to the even highlighter is a change to the type that records the drawing's history (`SRP-INK-01`), and a change to the palette reopens the ink-recording path of `PDFAnnotationCoordinator` (`SRP-LECTURE-01`).

**Shared fix direction.** Keep the platform delegate (`UITextViewDelegate`, `PDFPageOverlayViewProvider`, `PKCanvasViewDelegate`) as a thin adapter that forwards to owned collaborators, each with its own state and its own test; split the application model into one aggregate per vault and per flow, composed by an object that holds no logic; move every pure decision into Core so it compiles on both platforms. A type that remains above 15 stored properties records why in its doc comment.

### 2.2 Teardown by hand-written reset lists

**What it is.** The end of a vault, runtime, reading or session is written as a list of field assignments inside one function. A new field joins its declaration and, separately, the list; the compiler checks neither.

**Where it occurs.** `SRP-SHELL-02` (High, SHELL), `SRP-ARCH-05` (ARCH), `SRP-PLUGIN-02` (PLUGIN), `SRP-VOICE-01` (High, VOICE); the same shape appears in `SRP-RUNTIME-04` (RUNTIME), where a leaf's presentation is three loose fields set by hand.

**Evidence.**

| Reset | Location | Fields reset | Fields missed |
| --- | --- | ---: | --- |
| `openVault` | [WorkspaceModel.swift:303-337](../../../Sources/GraphiteUI/WorkspaceModel.swift#L303-L337) | 33 fields plus 7 feature calls | `notice`, `fileRecoveryRequest`, `drawingEditorRequest`, `noteTextWhenDrawingBegan`, `lastThemeInputs`, `viewedImage`, `isGraphPresented`, `isMapPresented`, `recordingRecoveryOffer` |
| `stopRuntime` | [CommunityPluginHost.swift:515-557](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L515-L557) | 35 | 13, among them `pluginStyleSheets`, `pluginBodyClasses`, `pluginBodyStyle`; `vaultWillClose` resets 6 more ([CommunityPluginHost.swift:326-335](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L326-L335)) |
| `ReadAloudController.begin` | [ReadAloudController.swift:591-625](../../../Sources/GraphiteUI/ReadAloudController.swift#L591-L625) | 26 | — |
| `ReadAloudController.clear` | [ReadAloudController.swift:424-443](../../../Sources/GraphiteUI/ReadAloudController.swift#L424-L443) | 17 | `pdfRunningText`, `title`, `scopeDescription`, `sourceHighlightNotice` |
| `ReadAloudController.documentDidChange` | [ReadAloudController.swift:402-412](../../../Sources/GraphiteUI/ReadAloudController.swift#L402-L412) | 6 | most of the above |

The `openVault` list runs into the new vault's own assignments in the same function, and a vault removal is a second hand list ([WorkspaceModel.swift:244-258](../../../Sources/GraphiteUI/WorkspaceModel.swift#L244-L258)). Ordering constraints inside the list (`layoutVaultIdentifier` becomes `nil` before `layout` is replaced; `expandedFolders` is replaced only after `currentVaultIdentifier` changes) are documented by comments only.

**Cost.** Each missed field carries one session's state into the next: the removed vault's folds stay in the device preferences (`BUG-SHELL-02`, Low), Read Aloud resumes a note at the place remembered for a same-named note of another vault (`BUG-ARCH-07`, Medium), a drawing open during a vault switch is saved into the new vault (`BUG-ARCH-03`, Plausible, Low), Stop between two PDF pages does not stop (`BUG-VOICE-01`, Medium) and Stop during a fold change restarts reading (`BUG-VOICE-02`, Low), turning plugins off and on quickly leaves them off (`BUG-PLUGIN-01`, Medium). Every new per-vault field is a reviewer's memory task.

**Shared fix direction.** Per-vault state lives in one `OpenVault` value that the switcher replaces; per-runtime plugin state lives in a `CommunityPluginSession` that is released on stop; Read Aloud holds one optional active reading, so a reset is `activeReading = nil`. Cleanup duties that cannot live in the value (caches, singletons, platform observers) conform to a lifecycle protocol that the coordinator iterates without naming a feature.

### 2.3 One rule with several owners

**What it is.** A business rule is implemented in more than one place, with different details and different tests. The duplicate is either an independent re-implementation or a second consumer that decides again what the first already decided.

**Where it occurs.** `SRP-BASES-03` (High), `SRP-BASES-04` (BASES); `SRP-READING-06`, `SRP-READING-03`, `SRP-READING-08` (READING); `SRP-MDCORE-01`, `SRP-MDCORE-03`, `SRP-MDCORE-05` (MDCORE); `SRP-CANVAS-04` (CANVAS); `SRP-RUNTIME-05` (RUNTIME); `SRP-VAULT-05` (VAULT); `SRP-EDITOR-03`, `SRP-EDITOR-05` (EDITOR); `SRP-LECTURE-07` (LECTURE); `SRP-PLUGIN-03` (PLUGIN); `SRP-SHELL-04` (SHELL); `SRP-INK-03` (INK).

**Evidence.**

- Link resolution has five implementations: the in-memory provider ([BaseFileRecord.swift:260-282](../../../Sources/GraphiteCore/BaseFileRecord.swift#L260-L282)), the index query ([VaultIndex.swift:365-402](../../../Sources/GraphiteIndex/VaultIndex.swift#L365-L402)), the evaluator's rooted pre-checks ([BaseEvaluator.swift:158-159](../../../Sources/GraphiteCore/BaseEvaluator.swift#L158-L159), [BaseEvaluator.swift:484](../../../Sources/GraphiteCore/BaseEvaluator.swift#L484)), its name fallback ([BaseEvaluator.swift:460-466](../../../Sources/GraphiteCore/BaseEvaluator.swift#L460-L466)) and the document model's disk-first lookup ([BaseDocumentModel.swift:433-445](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L433-L445)). The index query allows aliases for Wikilinks only; the model asks the file system before the index.
- "Apply an edit to a note, open or closed" is written three times with three save rules: mentions never save an open note ([WorkspaceMentions.swift:70-83](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L70-L83)), task ticks save at once ([WorkspaceReadingTasks.swift:11-26](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L11-L26)), property renames save only when no editor is attached ([WorkspaceTagsAndProperties.swift:71-85](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L71-L85)). The closed-file branch (read with revision, decode, edit, encode with byte order mark, save expecting the revision) is copied in all three.
- Six passes of `ObsidianInlineMarkup` each start their own `CodeFenceTracker()` ([NotePreviewDocument.swift:405](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L405), [NotePreviewDocument.swift:427](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L427), [NotePreviewDocument.swift:477](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L477), [NotePreviewDocument.swift:521](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L521), [NotePreviewDocument.swift:543](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L543), [NotePreviewDocument.swift:737](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L737)), and `TextColorMarkup` and `MarkdownEditing.isInCodeOrFrontmatter` carry their own block detection beside the shared scanner.
- The graph view keeps a second viewport implementation with different limits (`0.05…6`, [GraphCanvas.swift:338](../../../Sources/GraphiteUI/GraphCanvas.swift#L338)) beside the tested `CanvasViewport` in Core.
- The runtime adapter has two per-path write queues and removal rules in two classes ([vault.js:201-261](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-vault.js#L201-L261)).
- The install outcome text is composed in two views with different wording ([CommunityPluginSettings.swift:93](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L93), [CommunityPluginSettings.swift:300-302](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L300-L302)).

**Cost.** The copies disagree in observable ways: `file.hasLink` leaves out notes at the vault root (`BUG-BASES-03`, Medium), a base resolves a Markdown link through an alias (`BUG-BASES-02`, Low), a link cell opens another file than the base resolves (`BUG-BASES-04`, Low), Return in a fenced block inside a quote adds list markup (`BUG-MDCORE-02`, Medium, caused by the duplicate code detector). A fix is made up to five times, and a fourth feature copies one of the three save rules by accident.

**Shared fix direction.** Name one owner per rule and make the others call it: one `BaseLinkResolution` per run, one note-text editing executor that takes a save policy, one code and math line classification per run, one `MarkdownLineSyntax`, one `GraphViewport` value in Core. A deliberate performance mirror stays only with a parity test (`NoteFolding.isListItem`, section 4).

### 2.4 State, requests and outcomes carried in shared mutable fields

**What it is.** A flow with more than two states is a set of booleans and optionals that must change together; a request travels as a field the receiver polls; an outcome travels as a write to a shared slot that another object reads later.

**Where it occurs.** `SRP-CANVAS-01` (High), `SRP-CANVAS-02` (CANVAS); `SRP-SHELL-03`, `SRP-SHELL-04` (SHELL); `SRP-ARCH-04` (ARCH); `SRP-BASES-02` (BASES); `SRP-EDITOR-02` (EDITOR); `SRP-INK-03`, `SRP-INK-04` (INK); `SRP-VAULT-03` (VAULT); `SRP-MDCORE-02` (MDCORE); `SRP-READING-01` (READING); `SRP-RUNTIME-04`, `SRP-RUNTIME-06` (RUNTIME); `SRP-LECTURE-07` (LECTURE); `SRP-PLUGIN-04` (PLUGIN).

**Evidence.**

- `errorMessage: String?` receives the outcome of 83 operations (85 `errorMessage = ` matches in the `Workspace*.swift` files, two of them on `pdfSession`), and views and other types write it too; a sheet hides the root's alert, so the alert is attached twice ([GraphiteRootView.swift:202](../../../Sources/GraphiteUI/GraphiteRootView.swift#L202), [SettingsView.swift:86-88](../../../Sources/GraphiteUI/SettingsView.swift#L86-L88)).
- `BaseDocumentModel.actionErrorMessage` has eight writers and any successful query clears it ([BaseDocumentModel.swift:233](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L233)).
- The index scan is `isScanning`, `activeScanGeneration` and `pathsRefreshedDuringScan` ([VaultIndex.swift:56-63](../../../Sources/GraphiteIndex/VaultIndex.swift#L56-L63)), set together at [VaultIndex.swift:574-576](../../../Sources/GraphiteIndex/VaultIndex.swift#L574-L576); `refresh` tests `activeScanGeneration != nil` where `reconcile` tests `isScanning` ([VaultIndex.swift:826](../../../Sources/GraphiteIndex/VaultIndex.swift#L826)).
- `HTMLToMarkdown.Converter` writes four position flags at 28 sites; `write` clears one silently and the quote branch sets it back ([HTMLToMarkdown.swift:665-669](../../../Sources/GraphiteCore/HTMLToMarkdown.swift#L665-L669), [HTMLToMarkdown.swift:347-350](../../../Sources/GraphiteCore/HTMLToMarkdown.swift#L347-L350)).
- The drawing canvas needs `showPicturesAndPaper()` called by hand at 18 sites ([DrawingEditor.swift:450-735](../../../Sources/GraphiteUI/DrawingEditor.swift#L450-L735)), and `InfiniteCanvasView` keeps its own copies of the arrangement state ([DrawingEditor.swift:849-858](../../../Sources/GraphiteUI/DrawingEditor.swift#L849-L858)).
- The board renderer writes `session.groupLabelFrames` while drawing ([CanvasBoardView.swift:117-121](../../../Sources/GraphiteUI/CanvasBoardView.swift#L117-L121)), and hit testing reads it.
- `applyFromHistory` clears the typed text without committing it ([CanvasSession.swift:238-241](../../../Sources/GraphiteUI/CanvasSession.swift#L238-L241)) although `save` and `endEditing` commit it ([CanvasSession.swift:286-295](../../../Sources/GraphiteUI/CanvasSession.swift#L286-L295)).
- Presentation is 14 `@State` values in the root view plus 13 optionals and booleans in the workspace and one in the plugin host (`SRP-ARCH-04`); graph and map are two booleans.
- `MarkdownSession` exposes five callback slots and four request fields (`startsEditingWhenShown`, `findRequest`, `hasPlacedCursor`, `isTyping`) that only the iPad editor answers ([MarkdownSession.swift:97-109](../../../Sources/GraphiteUI/MarkdownSession.swift#L97-L109)).

**Cost.** User text is lost when Undo is pressed while typing in a canvas text card (`BUG-CANVAS-01`, High); two failures close together overwrite each other; a tap on a group label hits only after a frame has been drawn at the current zoom; a new picture edit that forgets one projection call leaves stale pictures; a Mac editor answers none of the requests and nothing fails (`BUG-EDITOR-02`, `BUG-EDITOR-03`); a leaf opens a second tab or never shows (`BUG-RUNTIME-03`, Medium).

**Shared fix direction.** A flow with more than two states becomes an enum changed only through intent methods (`ScanPhase`, `LinePosition`, `PanelContent`, `PresentedScreen`, one `NoteEditorRequest` queue). Operations return typed outcomes; one `WorkspaceAlerts` queue holds typed alerts and one presenter turns them into words. Derived copies are projected from one place. A rule that spans two responsibilities (typed text is committed before a history step) belongs to the type that owns both.

### 2.5 Views and background tasks that do I/O and decide rules

**What it is.** A SwiftUI view, a view task or an invisible driver view reads files, constructs services, reads the pasteboard, runs an installer, parses a note or decides when to save. The rule exists only while that view is on screen and cannot be tested without hosting it.

**Where it occurs.** `SRP-SHELL-05` (SHELL); `SRP-CANVAS-03`, `SRP-CANVAS-05` (CANVAS); `SRP-EDITOR-05` (EDITOR); `SRP-INK-05` (INK); `SRP-LECTURE-04`, `SRP-LECTURE-05` (LECTURE); `SRP-READING-03`, `SRP-READING-04`, `SRP-READING-05`, `SRP-READING-07` (READING); `SRP-PLUGIN-03` (PLUGIN); `SRP-BASES-04` (BASES).

**Evidence.**

- `fileExists` runs in view bodies and menus at seven sites; the recent-files list checks every file on disk once per update ([WorkspaceModel.swift:1286-1296](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1286-L1296), called from [WorkspacePanes.swift:660-662](../../../Sources/GraphiteUI/WorkspacePanes.swift#L660-L662) and [QuickPalette.swift:246](../../../Sources/GraphiteUI/QuickPalette.swift#L246)).
- Canvas card views check file existence in a task ([CanvasCardViews.swift:250-255](../../../Sources/GraphiteUI/CanvasCardViews.swift#L250-L255)) and read notes with a constructed `AtomicFileWriter()` ([CanvasCardViews.swift:323-334](../../../Sources/GraphiteUI/CanvasCardViews.swift#L323-L334)); the Live Preview embed view does the same ([LivePreviewWidgets.swift:597](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L597), [LivePreviewWidgets.swift:629](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L629)).
- `installFromRepository` constructs `CommunityPluginInstaller(store:)` in the settings view and composes the outcome sentence there ([CommunityPluginSettings.swift:87-99](../../../Sources/GraphiteUI/CommunityPluginSettings.swift#L87-L99)).
- The drawing editor's `body` asks `UIPasteboard.general.hasImages` on every evaluation ([DrawingEditor.swift:300](../../../Sources/GraphiteUI/DrawingEditor.swift#L300)).
- Autosave is a `Color.clear` view with a 900 ms sleep ([MarkdownPane.swift:663-678](../../../Sources/GraphiteUI/MarkdownPane.swift#L663-L678)); a session whose pane is not on screen is not autosaved by it.
- `EmbeddedPDFViewer` saves, reloads and releases sessions inside a SwiftUI view ([EmbeddedPDFViewer.swift:113-137](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L113-L137), [EmbeddedPDFViewer.swift:489-514](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L489-L514)).

**Cost.** Main-thread I/O in view updates endangers editor responsiveness, a top priority, and on a cloud-backed vault `fileExists` can block on the file provider. The save policy is decided in three callers because the autosave rule lives in a view (`SRP-READING-05`, `SRP-READING-06`); embed resolution, missing-file, unreadable-note and locked-PDF behaviour have no unit test.

**Shared fix direction.** Each view event calls one model method; the model returns a typed result (`.text`, `.missingSection`, `.unreadable`, `.missingFile`, `.locked`, `InstallationOutcome`); the work that must happen regardless of the screen (autosave, release, background inspection) belongs to an owned model with a cancelled task. Views keep layout and drawing.

### 2.6 Boundaries that do not exist: one module, one namespace, one type spread over many files

**What it is.** The unit that should separate responsibilities (module, global namespace, closure, type) is one wide container, and separation is faked with `extension` blocks in other files.

**Where it occurs.** `SRP-ARCH-02`, `SRP-ARCH-03` (ARCH); `SRP-RUNTIME-01`, `SRP-RUNTIME-02`, `SRP-RUNTIME-03` (RUNTIME); `SRP-PLUGIN-04` (PLUGIN); `SRP-SHELL-01` and `SRP-ARCH-01` (24 extension blocks); `SRP-INK-06` (INK); `SRP-LECTURE-02` (LECTURE).

**Evidence.**

- `GraphiteUI` is one module of 153 files and 46,253 code lines ([metrics.md](../metrics.md)) that imports SwiftUI, UIKit, AppKit, WebKit, MapKit, PDFKit and PencilKit and holds every feature and the composition root.
- `GraphiteCore` is described as the pure layer, yet it reads and writes files (`FileManager.default` in 7 files, among them `VaultStore.swift`, `FileRecovery.swift`, `RecordingRecovery.swift`) and takes `URLSession = .shared` as a default argument ([ObsidianThemes.swift:131](../../../Sources/GraphiteCore/ObsidianThemes.swift#L131), [CommunityPluginInstaller.swift:48](../../../Sources/GraphiteCore/CommunityPluginInstaller.swift#L48), [CommunityPluginNetworkRequest.swift:27](../../../Sources/GraphiteCore/CommunityPluginNetworkRequest.swift#L27)).
- `GraphitePluginRuntime` is a global namespace of 50 members assigned from 9 of the 11 scripts and read as `runtime.app` on 57 lines (72 occurrences) in 6 files; earlier scripts call functions only later scripts define ([workspace.js:731-732](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L731-L732) uses [plugins.js:1053](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1053)); `runtime.markdownPostProcessors` is reassigned wholesale from two files ([plugins.js:481](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L481), [workspace.js:1036](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-workspace.js#L1036)).
- `plugins.js` is one closure from line 4 to line 1554 with 28 host handlers in one object ([plugins.js:1244-1521](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1244-L1521)).
- A plugin file extends the workspace: [CommunityPluginViews.swift:192-312](../../../Sources/GraphiteUI/CommunityPluginViews.swift#L192-L312) writes `host.liveViewPictures`, `host.hasRestoredViews`, `host.pluginViews`, while the host calls back into the extension; `LassoTools.swift` adds two `WorkspaceModel` extensions ([LassoTools.swift:72](../../../Sources/GraphiteUI/LassoTools.swift#L72), [LassoTools.swift:85](../../../Sources/GraphiteUI/LassoTools.swift#L85)) and `PencilToolbar.swift` a `PDFSession` extension ([PencilToolbar.swift:421](../../../Sources/GraphiteUI/PencilToolbar.swift#L421)).

**Cost.** Any edit rebuilds and re-tests the whole UI; internal types are visible everywhere, so features reach into each other (`MediaFileKind` is defined in `MarkdownPreview.swift` and used by panes, canvas cards and conflict sheets); a theme-installer or recovery-store test touches the real network or Application Support; a reordered `index.html` or a renamed runtime member fails only when the message that uses it arrives, and the Node harness must evaluate all eleven scripts in order ([runtime-harness.js:104-106](../../../Tests/CommunityPluginRuntimeTests/support/runtime-harness.js#L104-L106)). Neither type owns "which plugin view is in which tab" (`BUG-PLUGIN-06`, Medium).

**Shared fix direction.** Feature modules cut along the area boundaries over a Core that performs no file, network or keychain work (storage and network adapters in their own modules with the session injected); each runtime script exports one object and receives collaborators at construction; handlers register through a router; a feature owns its state in its own type, never in an extension of another feature's aggregate.

### 2.7 Files named for one concept that hold many

**What it is.** A file name promises one concept and the file holds several unrelated ones, so readers cannot find a rule by its file name and every change to one concept touches the history of the others.

**Where it occurs.** `SRP-READING-02`, `SRP-BASES-05`, `SRP-INK-06`, `SRP-LECTURE-06`, `SRP-MDCORE-04`, `SRP-MDCORE-06`, `SRP-PLUGIN-05`, `SRP-PLUGIN-06`, `SRP-VAULT-04`, `SRP-SHELL-06`, `SRP-BASES-01` (the evaluator file also holds the environment and the replacement template).

**Evidence.** `MarkdownPreview.swift` declares 64 top-level types in 2,293 code lines; `MarkdownSemantics.swift` holds 18 types, 11 unrelated to semantics ([MarkdownSemantics.swift:585-1080](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L585-L1080)); `SearchQuery.swift` holds 7 concepts in 944 code lines and `LinkRewriter.swift` 5 in 489; `DrawingEditor.swift` declares 12 top-level types; `GraphiteTheme.swift` holds eight concepts ([GraphiteTheme.swift:4-252](../../../Sources/GraphiteUI/GraphiteTheme.swift#L4-L252)); `PDFPageManager.swift` holds the edit vocabulary, the key registry, edit application, export, destinations and a file I/O actor, and the name says nothing ([PDFPageManager.swift:24-540](../../../Sources/GraphiteApple/PDFPageManager.swift#L24-L540)); `GraphitePreferences.swift` declares `CorePlugin`, five enums and `NotebookPaperSpacing` beside the preferences ([GraphitePreferences.swift:10-148](../../../Sources/GraphiteUI/GraphitePreferences.swift#L10-L148)).

**Cost.** Low per file, high in total: `MarkdownPreview.swift` is touched by 25 commits that belong to image caching, callouts, media players or links as much as to the reading view, and `CalloutView`, `ReadingImageCache`, `EmbeddedMediaPlayer` and `MediaFileKind` are used by Live Preview, panes, canvas cards and conflict sheets, so a diff does not say which area it affects.

**Shared fix direction.** One concept per file, named after it, no behaviour change; shared primitives move to files named after themselves. The split is by responsibility, never by size.

## 3. Largest offenders

### 3.1 The ten worst types

Counts are the area auditors' counts by reading, which I re-checked at the snapshot for the High findings (the stored-property ranges, the reset lists, the 28 handlers, the five link implementations). A type with a number above 15 needs a recorded reason under `SRP 1`.

| # | Type (file) | Stored properties | Responsibilities | Size and spread | Findings |
| ---: | --- | ---: | --- | --- | --- |
| 1 | `WorkspaceModel` ([WorkspaceModel.swift](../../../Sources/GraphiteUI/WorkspaceModel.swift)) | 86 | 22 rows in the SHELL map (about 15 workflows, ARCH groups them as 12) | 74 functions in the main file plus 24 extension blocks in 23 files, about 2,695 code lines; `openVault` resets 33 fields; 85 `errorMessage =` writes in `Workspace*.swift` | `SRP-SHELL-01`, `SRP-SHELL-02`, `SRP-SHELL-03`, `SRP-ARCH-01`, `SRP-ARCH-05` |
| 2 | `CommunityPluginHost` ([CommunityPluginHost.swift](../../../Sources/GraphiteUI/CommunityPluginHost.swift)) | 63 | 12 | 88 members over 6 files; about 20 view and helper types hold it whole; `stopRuntime` resets 35 fields and misses 13 | `SRP-PLUGIN-01`, `SRP-PLUGIN-02`, `SRP-PLUGIN-04` |
| 3 | iPad `NativeMarkdownEditor.Coordinator` ([NativeMarkdownEditor.swift](../../../Sources/GraphiteUI/NativeMarkdownEditor.swift)) | 47 | 16 | 93 functions in 1,555 lines (771-2325), 5 protocol conformances; 41 of 242 commits; never compiled by `swift test` on macOS | `SRP-EDITOR-01`, `SRP-EDITOR-03`, `SRP-EDITOR-04` |
| 4 | `PDFSession` ([PDFSession.swift](../../../Sources/GraphiteUI/PDFSession.swift)) | 46 | document editor, save controller, protection, undo history, view state | 4 files; holds `pdfView`, `livePlace`, `visiblePageCenter`, `inkCanvasProvider` | `SRP-LECTURE-02` |
| 5 | `ReadAloudController` ([ReadAloudController.swift](../../../Sources/GraphiteUI/ReadAloudController.swift)) | 39 | 8 | 3 reset lists of 26, 17 and 6 fields; 15 of 242 commits | `SRP-VOICE-01` |
| 6 | `PDFAnnotationCoordinator` ([GraphitePDFView.swift](../../../Sources/GraphiteUI/GraphitePDFView.swift)) | 37 plus 1 static dictionary | 13 | 735 code lines, 5 conformances; 23 commits, the most in LECTURE | `SRP-LECTURE-01`, `SRP-LECTURE-07` |
| 7 | `MarkdownPreview` view and file ([MarkdownPreview.swift](../../../Sources/GraphiteUI/MarkdownPreview.swift)) | 37 | 7 jobs in the view | `body` 127 code lines; the file declares 64 types in 2,293 code lines; 25 commits | `SRP-READING-01`, `SRP-READING-02` |
| 8 | `GraphitePreferences` ([GraphitePreferences.swift](../../../Sources/GraphiteUI/GraphitePreferences.swift)) | 36 | 9 feature areas | `init` 41 code lines; the file holds 8 unrelated concepts; every settings page takes the whole object | `SRP-SHELL-06` |
| 9 | `HistoryCanvasView` ([HistoryCanvasView.swift](../../../Sources/GraphiteUI/HistoryCanvasView.swift)) | 35 plus 2 static | 9 | every PDF page and the drawing editor inherit it; `InfiniteCanvasView` adds 27 and 8 callbacks | `SRP-INK-01`, `SRP-INK-04` |
| 10 | `CanvasSession` ([CanvasSession.swift](../../../Sources/GraphiteUI/CanvasSession.swift)) | 34 | 8 | 506 lines; typed text, history, viewport, gestures and persistence share the fields | `SRP-CANVAS-01`, `SRP-CANVAS-02` |

### 3.2 Other types above the 15-property limit, and the non-Swift offenders

| Type or file | Number | Findings |
| --- | --- | --- |
| `MarkdownSession` | 34 stored properties, 5 callback slots, 4 request fields | `SRP-EDITOR-02` |
| `SelectionFrameView` | 37 stored properties (no finding; named in the INK verdict) | — |
| `BaseDocumentModel` | 28 stored properties, 8 writers of one error field | `SRP-BASES-02` |
| `RecordingController` | 26 stored properties, audio, video, publication and recovery | `SRP-LECTURE-03` |
| `ReadAloudSession` | 24 stored properties in 5 groups | `SRP-VOICE-03` |
| `MarkdownPane` | 23 stored properties; uses 38 `WorkspaceModel` members; `body` 109 code lines | `SRP-READING-04` |
| `InkSelectionController` | 21 stored properties, 658 code lines, 8 groups | `SRP-INK-02` |
| `ReadAloudNavigator` | 19 stored properties, 7 jobs, untested | `SRP-VOICE-04` |
| `ReadAloudPassagePreparation`, `HTMLToMarkdown.Converter` | 18 stored properties each | `SRP-VOICE-05`, `SRP-MDCORE-02` |
| `GraphiteRootView` | 16 state properties, 12 presentations, `body` 172 code lines | `SRP-SHELL-04` |
| `plugins.js` | one closure of 1,324 code lines, 20 responsibility rows, 28 handlers | `SRP-RUNTIME-01` |
| `GraphitePluginRuntime` | 50 members assigned from 9 scripts | `SRP-RUNTIME-02` |
| `reading.js` | 8 responsibilities, 7 module-level variables | `SRP-RUNTIME-03` |

### 3.3 The largest functions

| Function | Lines (code lines where the area counted them) | Findings |
| --- | ---: | --- |
| `ReadAloudDocument.markdown` ([ReadAloudDocument.swift:296-589](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L296-L589)) | 273 | `SRP-VOICE-02` |
| `HTMLToMarkdown.Converter.handleTag` | 176 | `SRP-MDCORE-02` |
| `GraphiteRootView.body` ([GraphiteRootView.swift:62-252](../../../Sources/GraphiteUI/GraphiteRootView.swift#L62-L252)) | 172 | `SRP-SHELL-04` |
| `CodeLineScanner.scanSigil` ([CodeSyntaxHighlighting.swift:685-849](../../../Sources/GraphiteCore/CodeSyntaxHighlighting.swift#L685-L849)) | 160 | `SRP-MDCORE-06` |
| `ReadAloudDocument.pageText` ([ReadAloudDocument.swift:79-237](../../../Sources/GraphiteCore/ReadAloudDocument.swift#L79-L237)) | 149 | `SRP-VOICE-02` |
| `MarkdownPreview.body` | 127 | `SRP-READING-01` |
| `BaseEvaluator.callFunction` ([BaseEvaluator.swift:716-831](../../../Sources/GraphiteCore/BaseEvaluator.swift#L716-L831)) | 109 | `SRP-BASES-01` |
| `MarkdownPane.body` | 109 | `SRP-READING-04` |
| `PDFPaneContent.body` | 108 | `SRP-LECTURE-05` |
| `PDFPaneContent.moreMenuItems`, `PDFPageManager.apply` | 84, 80 | `SRP-LECTURE-05`, `SRP-LECTURE-06` |

## 4. What to keep for this principle

The cleanup imitates these. Each is a design the audits found already meeting single responsibility, with its evidence.

| Design | Area | Evidence | What to imitate |
| --- | --- | --- | --- |
| Pure Core value types that own one rule and do no I/O: `TabLayout`, `NavigationHistory`, `RecentFiles`, `DocumentPlaceMemory`, `VaultList`; 28 of 34 files in VAULT hold one small value with one rule | VAULT, SHELL | [TabLayout.swift:44-401](../../../Sources/GraphiteCore/TabLayout.swift#L44-L401), [WorkspaceTabs.swift:84-216](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L84-L216) (every layout decision delegates to `layout.*`) | A model adds documents around the value and wraps it, never absorbs it |
| The conflict-version feature: a feature model, an injected `ConflictVersionStore` seam with a test double, bounded background work, a wording enum | SHELL | [ConflictVersionsSheet.swift:8-65](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L8-L65), [WorkspaceConflictVersions.swift:25-63](../../../Sources/GraphiteUI/WorkspaceConflictVersions.swift#L25-L63), [WorkspaceModel.swift:165](../../../Sources/GraphiteUI/WorkspaceModel.swift#L165) | The template for every extraction out of `WorkspaceModel` |
| `DocumentPlaceStore`: read once, write on change, injected defaults | SHELL | [WorkspacePlaces.swift:79-112](../../../Sources/GraphiteUI/WorkspacePlaces.swift#L79-L112) | The shape of the per-vault device memory |
| Derived tab state projected from `layout` and written only on change; `WorkspaceFocusMode` as a small tested state machine | SHELL | [WorkspaceModel.swift:40-52](../../../Sources/GraphiteUI/WorkspaceModel.swift#L40-L52), [WorkspaceFocusMode.swift:4-23](../../../Sources/GraphiteUI/WorkspaceFocusMode.swift#L4-L23) | One source of truth with a guarded projection; keep both when splitting |
| Pure decision helpers with injected dates: `ExternalChangeRefresh`, `externalRefreshDeadline`, `MessageAlert.parts` | SHELL, ARCH | [WorkspaceModel.swift:1405-1453](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1405-L1453), [MessageAlert.swift:26-34](../../../Sources/GraphiteUI/MessageAlert.swift#L26-L34) | Decide, then do; move with their tests unchanged |
| Planner then executor: a compaction plan written into a sink; link rewrites planned before the move and written at their planned revision | LECTURE, VAULT | [PDFObjectCompaction.swift:98-174](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L98-L174), [VaultFileOperations.swift:88-143](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L88-L143) | The same plan serves memory and file; failures are reported per note |
| Pure, tested decision values: `UnansweredGestureCount`, `PDFResizeZoom`, `RecordingPreviewLayout`, `RecordingControlModel`, `PDFCitation`, `PDFEmbedOptions`, `PageCoordinates` | LECTURE | [PDFPaneHealth.swift:8-77](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L8-L77), [RecordingControls.swift:105-149](../../../Sources/GraphiteUI/RecordingControls.swift#L105-L149) | Inputs in, value out, no platform object |
| `RecordingState` predicates as the one place transitions are allowed; `VideoCaptureSource` as a real two-implementation seam | LECTURE | [RecordingState.swift:3-9](../../../Sources/GraphiteCore/RecordingState.swift#L3-L9), [VideoCapture.swift:81-102](../../../Sources/GraphiteApple/VideoCapture.swift#L81-L102) | A protocol only where a substitution exists |
| Pure Read Aloud policies (`ReadAloudAudioCachePolicy` and six more) and the two seams for rendering and alignment with one production implementation each | VOICE | [ReadAloudAudioCachePolicy.swift:8-70](../../../Sources/GraphiteCore/ReadAloudAudioCachePolicy.swift#L8-L70), [ReadAloudPassagePreparation.swift:8-13](../../../Sources/GraphiteVoices/ReadAloudPassagePreparation.swift#L8-L13), [ReadAloudSpeechAlignment.swift:8-11](../../../Sources/GraphiteVoices/ReadAloudSpeechAlignment.swift#L8-L11) | The model for the rest of VOICE: each seam names why it exists |
| Narrow editor ports (`MarkdownStyledTextView` with 5 members, `RetainableMarkdownEditor` with 3) and a small separately tested retention policy | EDITOR | [MarkdownEditorStyling.swift:12-22](../../../Sources/GraphiteUI/MarkdownEditorStyling.swift#L12-L22), [MarkdownEditorRetention.swift:10-18](../../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L10-L18), [MarkdownEditorRetention.swift:28-142](../../../Sources/GraphiteUI/MarkdownEditorRetention.swift#L28-L142) | Two production implementations each plus a test fake |
| Editing helpers and commands return one `MarkdownTextEdit`; the context-menu model is platform-neutral and rendered by UIKit and AppKit builders | EDITOR, MDCORE | [MarkdownEditing.swift:3-14](../../../Sources/GraphiteCore/MarkdownEditing.swift#L3-L14), [EditorKeyboardToolbar.swift:76-110](../../../Sources/GraphiteUI/EditorKeyboardToolbar.swift#L76-L110), [EditorContextMenu.swift:35-59](../../../Sources/GraphiteUI/EditorContextMenu.swift#L35-L59) | The decision is a value; the editor performs it through undo |
| Core types with one job: `MarkdownTable` edits, `DisplayMathLines` pairing, `NoteFolding` keys, `CodeFence` and `CodeFenceTracker` (9 consumers), `FrontmatterLocator` (one owner used by preview, session, templates, link rewriting, mentions and properties) | MDCORE, ARCH | [MarkdownTable.swift:434-535](../../../Sources/GraphiteCore/MarkdownTable.swift#L434-L535), [DisplayMathLines.swift:26-45](../../../Sources/GraphiteCore/DisplayMathLines.swift#L26-L45), [MarkdownSemantics.swift:661-679](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L661-L679) | The owner every duplicate (section 2.3) calls instead |
| A hand-written fast mirror with a parity test (`NoteFolding.isListItem` against `MarkdownEditing.listLine`, 34 lines) | MDCORE | [NoteFolding.swift:96-135](../../../Sources/GraphiteCore/NoteFolding.swift#L96-L135) | The only acceptable second implementation of a rule |
| The canvas file is the document: parser, editing as splices with inverse patches, geometry in Core; gestures decided in the session in view coordinates | CANVAS | [CanvasFile.swift:144-175](../../../Sources/GraphiteCore/CanvasFile.swift#L144-L175), [CanvasGeometry.swift:1-399](../../../Sources/GraphiteCore/CanvasGeometry.swift#L1-L399), [CanvasInteraction.swift:18-21](../../../Sources/GraphiteUI/CanvasInteraction.swift#L18-L21) | The 7 Core files own one concern each; finger, Pencil and pointer share one tested path |
| Ink format code is cohesive (15 Core and Apple files), recognizers and geometry are pure, Pencil activity is a pure state with an adapter holding UIKit objects weakly, the toolbox changes through intent methods | INK | [PalmRejection.swift:19-92](../../../Sources/GraphiteUI/PalmRejection.swift#L19-L92), [PencilToolbox.swift:128-143](../../../Sources/GraphiteUI/PencilToolbox.swift#L128-L143), [SelectionFrameView.swift:452-469](../../../Sources/GraphiteUI/SelectionFrameView.swift#L452-L469) (geometry as static functions) | The pattern the canvas views must adopt |
| Pure helpers already extracted from models as statics; a typed `FileChange` instead of booleans in the view editor | BASES | [BaseDocumentModel.swift:291-298](../../../Sources/GraphiteUI/BaseDocumentModel.swift#L291-L298), [BaseViewEditorSheet.swift:113-165](../../../Sources/GraphiteUI/BaseViewEditorSheet.swift#L113-L165) | Decide-then-do without a host |
| Capabilities passed as values: `PropertiesPanel(update:follow:)`, `ReadingTaskContext`, `ReadingImageActions`; toolbar layout as pure functions | READING | [PropertiesPanel.swift:8-15](../../../Sources/GraphiteUI/PropertiesPanel.swift#L8-L15), [ReadingTaskCheckbox.swift:6-13](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift#L6-L13), [DocumentModeToggle.swift:71-133](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L71-L133) | The shape `MarkdownPane` itself should take |
| The WebKit message receiver is a separate object holding the host weakly; bridge requests decode into private `Decodable` structs; `AccentLegibility` and the contrast guard are pure | PLUGIN | [CommunityPluginWebContent.swift:109-119](../../../Sources/GraphiteUI/CommunityPluginWebContent.swift#L109-L119), [CommunityPluginVaultBridge.swift:34-44](../../../Sources/GraphiteCore/CommunityPluginVaultBridge.swift#L34-L44) | Adapters hold no feature state |
| The runtime's host transport is the one injected seam, and the Node harness loads the real page; named limits with units; a new page per vault start, so registries live exactly one vault session | RUNTIME | [foundation.js:30-49](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-foundation.js#L30-L49), [CommunityPluginHost.swift:371-401](../../../Sources/GraphiteUI/CommunityPluginHost.swift#L371-L401) | Teardown by releasing a page is the model for `SRP 4` |
| Module direction Core ← Index, Apple ← Voices ← UI, a thin app target, `AtomicFileWriter`, `VaultPath` as the only path type | ARCH, VAULT | [Package.swift:24-38](../../../Package.swift#L24-L38), [project.pbxproj:305-312](../../../Graphite.xcodeproj/project.pbxproj#L305-L312) | The direction the feature modules of `SRP 18` extend |

## 5. Index of findings

All 75 `SRP` findings, generated from [findings-index.md](../findings-index.md), ordered by severity, then area.

| ID | Area | Severity | Title |
| --- | --- | --- | --- |
| [SRP-ARCH-01](../cross-cutting/architecture.md#srp-arch-01-workspacemodel-is-an-application-wide-aggregate-of-86-stored-properties-and-a-dozen-responsibilities) | ARCH | High | `WorkspaceModel` is an application-wide aggregate of 86 stored properties and a dozen responsibilities |
| [SRP-BASES-03](../areas/bases.md#srp-bases-03-link-resolution-has-five-implementations-with-different-rules) | BASES | High | Link resolution has five implementations with different rules |
| [SRP-CANVAS-01](../areas/canvas.md#srp-canvas-01-canvassession-holds-34-stored-properties-across-8-responsibilities-that-share-mutable-fields) | CANVAS | High | `CanvasSession` holds 34 stored properties across 8 responsibilities that share mutable fields |
| [SRP-EDITOR-01](../areas/editor.md#srp-editor-01-the-ipad-editor-coordinator-owns-sixteen-kinds-of-work-and-47-stored-properties) | EDITOR | High | The iPad editor coordinator owns sixteen kinds of work and 47 stored properties |
| [SRP-INK-01](../areas/ink.md#srp-ink-01-historycanvasview-is-one-class-for-nine-jobs-that-every-canvas-inherits) | INK | High | `HistoryCanvasView` is one class for nine jobs that every canvas inherits |
| [SRP-LECTURE-01](../areas/lecture.md#srp-lecture-01-pdfannotationcoordinator-owns-13-responsibilities-and-37-stored-properties) | LECTURE | High | `PDFAnnotationCoordinator` owns 13 responsibilities and 37 stored properties |
| [SRP-LECTURE-02](../areas/lecture.md#srp-lecture-02-pdfsession-is-the-pdfs-aggregate-root-save-controller-undo-history-and-view-state-at-once) | LECTURE | High | `PDFSession` is the PDF's aggregate root, save controller, undo history and view state at once |
| [SRP-PLUGIN-01](../areas/plugin.md#srp-plugin-01-communitypluginhost-is-one-aggregate-for-the-whole-plugin-runtime) | PLUGIN | High | `CommunityPluginHost` is one aggregate for the whole plugin runtime |
| [SRP-RUNTIME-02](../areas/runtime.md#srp-runtime-02-the-global-graphitepluginruntime-namespace-is-a-service-locator-and-a-shared-mutable-registry) | RUNTIME | High | The global `GraphitePluginRuntime` namespace is a service locator and a shared mutable registry |
| [SRP-SHELL-01](../areas/shell.md#srp-shell-01-workspacemodel-is-one-application-wide-aggregate-with-86-stored-properties-and-about-15-responsibilities) | SHELL | High | `WorkspaceModel` is one application-wide aggregate with 86 stored properties and about 15 responsibilities |
| [SRP-SHELL-02](../areas/shell.md#srp-shell-02-the-vault-switch-resets-per-vault-state-field-by-field-a-new-field-must-be-remembered-in-openvault) | SHELL | High | The vault switch resets per-vault state field by field; a new field must be remembered in `openVault` |
| [SRP-VOICE-01](../areas/voice.md#srp-voice-01-readaloudcontroller-is-the-reader-for-every-source-and-every-concern-of-reading) | VOICE | High | `ReadAloudController` is the reader for every source and every concern of reading |
| [SRP-VOICE-02](../areas/voice.md#srp-voice-02-readalouddocumentmarkdown-and-pagetext-each-do-several-jobs-through-shared-mutable-locals) | VOICE | High | `ReadAloudDocument.markdown` and `pageText` each do several jobs through shared mutable locals |
| [SRP-ARCH-02](../cross-cutting/architecture.md#srp-arch-02-graphiteui-is-one-module-holding-every-feature-every-platform-bridge-the-plugin-runtime-and-the-composition-root) | ARCH | Medium | `GraphiteUI` is one module holding every feature, every platform bridge, the plugin runtime and the composition root |
| [SRP-ARCH-03](../cross-cutting/architecture.md#srp-arch-03-graphitecore-mixes-pure-obsidian-format-policy-with-file-network-and-keychain-adjacent-io) | ARCH | Medium | `GraphiteCore` mixes pure Obsidian-format policy with file, network and keychain-adjacent I/O |
| [SRP-ARCH-04](../cross-cutting/architecture.md#srp-arch-04-presentation-state-is-split-between-the-root-view-and-the-workspace-as-a-set-of-booleans-and-optionals) | ARCH | Medium | Presentation state is split between the root view and the workspace, as a set of booleans and optionals |
| [SRP-ARCH-05](../cross-cutting/architecture.md#srp-arch-05-switching-vaults-is-a-hand-maintained-list-of-resets-that-every-feature-must-remember-to-join) | ARCH | Medium | Switching vaults is a hand-maintained list of resets that every feature must remember to join |
| [SRP-BASES-01](../areas/bases.md#srp-bases-01-baseevaluator-interprets-coerces-dispatches-16-functions-and-6-method-families-memoises-lookups-and-formats-errors-in-one-class) | BASES | Medium | `BaseEvaluator` interprets, coerces, dispatches 16 functions and 6 method families, memoises lookups and formats errors in one class |
| [SRP-BASES-02](../areas/bases.md#srp-bases-02-basedocumentmodel-holds-28-stored-properties-for-five-workflows-and-one-shared-error-field) | BASES | Medium | `BaseDocumentModel` holds 28 stored properties for five workflows and one shared error field |
| [SRP-CANVAS-02](../areas/canvas.md#srp-canvas-02-the-boards-renderer-writes-hit-testing-state-into-the-session-while-drawing) | CANVAS | Medium | The board's renderer writes hit-testing state into the session while drawing |
| [SRP-CANVAS-03](../areas/canvas.md#srp-canvas-03-card-views-perform-file-io-and-own-a-rendering-service) | CANVAS | Medium | Card views perform file I/O and own a rendering service |
| [SRP-CANVAS-04](../areas/canvas.md#srp-canvas-04-graphcanvas-keeps-its-viewport-and-fitting-policy-as-view-state) | CANVAS | Medium | `GraphCanvas` keeps its viewport and fitting policy as view state |
| [SRP-EDITOR-02](../areas/editor.md#srp-editor-02-markdownsession-mixes-persistence-edit-queue-view-state-folds-and-ui-requests) | EDITOR | Medium | `MarkdownSession` mixes persistence, edit queue, view state, folds and UI requests |
| [SRP-EDITOR-03](../areas/editor.md#srp-editor-03-the-ipad-text-view-runs-the-paste-and-drop-import-pipeline) | EDITOR | Medium | The iPad text view runs the paste and drop import pipeline |
| [SRP-EDITOR-04](../areas/editor.md#srp-editor-04-two-delegate-callbacks-each-perform-five-or-six-jobs) | EDITOR | Medium | Two delegate callbacks each perform five or six jobs |
| [SRP-INK-02](../areas/ink.md#srp-ink-02-inkselectioncontroller-mixes-gestures-rendering-stroke-editing-pasteboard-capture-and-menus) | INK | Medium | `InkSelectionController` mixes gestures, rendering, stroke editing, pasteboard, capture and menus |
| [SRP-INK-03](../areas/ink.md#srp-ink-03-drawingcanvascontroller-owns-history-picture-arrangement-paper-and-error-reporting-and-needs-18-manual-projection-calls) | INK | Medium | `DrawingCanvasController` owns history, picture arrangement, paper and error reporting, and needs 18 manual projection calls |
| [SRP-INK-04](../areas/ink.md#srp-ink-04-infinitecanvasview-adds-27-stored-properties-and-8-callbacks-to-the-shared-canvas) | INK | Medium | `InfiniteCanvasView` adds 27 stored properties and 8 callbacks to the shared canvas |
| [SRP-INK-05](../areas/ink.md#srp-ink-05-the-drawing-editor-view-reads-files-and-the-pasteboard-and-maps-errors-to-text) | INK | Medium | The drawing editor view reads files and the pasteboard and maps errors to text |
| [SRP-LECTURE-03](../areas/lecture.md#srp-lecture-03-recordingcontroller-runs-audio-video-publication-and-recovery-in-one-object) | LECTURE | Medium | `RecordingController` runs audio, video, publication and recovery in one object |
| [SRP-LECTURE-04](../areas/lecture.md#srp-lecture-04-embeddedpdfviewer-performs-saving-reloading-and-session-lifecycle-inside-a-swiftui-view) | LECTURE | Medium | `EmbeddedPDFViewer` performs saving, reloading and session lifecycle inside a SwiftUI view |
| [SRP-LECTURE-05](../areas/lecture.md#srp-lecture-05-pdfpanecontent-mixes-read-aloud-orchestration-banners-toolbar-and-input-policy) | LECTURE | Medium | `PDFPaneContent` mixes Read Aloud orchestration, banners, toolbar and input policy |
| [SRP-LECTURE-06](../areas/lecture.md#srp-lecture-06-pdfpagemanagerswift-holds-the-edit-vocabulary-the-key-registry-edit-application-export-destinations-and-a-file-io-actor) | LECTURE | Medium | `PDFPageManager.swift` holds the edit vocabulary, the key registry, edit application, export, destinations and a file I/O actor |
| [SRP-LECTURE-07](../areas/lecture.md#srp-lecture-07-the-health-monitor-repairs-production-state-from-inside-a-diagnostics-component) | LECTURE | Medium | The health monitor repairs production state from inside a diagnostics component |
| [SRP-MDCORE-01](../areas/mdcore.md#srp-mdcore-01-obsidianinlinemarkup-is-one-enum-with-11-unrelated-reading-view-duties) | MDCORE | Medium | `ObsidianInlineMarkup` is one enum with 11 unrelated reading-view duties |
| [SRP-MDCORE-02](../areas/mdcore.md#srp-mdcore-02-htmltomarkdownconverter-tracks-its-writing-position-with-four-flags-written-at-28-sites) | MDCORE | Medium | `HTMLToMarkdown.Converter` tracks its writing position with four flags written at 28 sites |
| [SRP-MDCORE-03](../areas/mdcore.md#srp-mdcore-03-textcolormarkup-contains-a-complete-private-block-parser) | MDCORE | Medium | `TextColorMarkup` contains a complete private block parser |
| [SRP-MDCORE-05](../areas/mdcore.md#srp-mdcore-05-markdownediting-owns-line-syntax-for-three-block-finders-and-carries-its-own-fence-tracker) | MDCORE | Medium | `MarkdownEditing` owns line syntax for three block finders and carries its own fence tracker |
| [SRP-PLUGIN-02](../areas/plugin.md#srp-plugin-02-stopping-the-runtime-depends-on-a-hand-reset-of-35-fields-that-misses-13) | PLUGIN | Medium | Stopping the runtime depends on a hand reset of 35 fields that misses 13 |
| [SRP-PLUGIN-03](../areas/plugin.md#srp-plugin-03-settings-and-reading-views-perform-network-installs-and-vault-reads) | PLUGIN | Medium | Settings and reading views perform network installs and vault reads |
| [SRP-PLUGIN-04](../areas/plugin.md#srp-plugin-04-a-workspacemodel-extension-in-a-plugin-file-writes-host-state-and-the-host-calls-back-into-it) | PLUGIN | Medium | A `WorkspaceModel` extension in a plugin file writes host state, and the host calls back into it |
| [SRP-READING-01](../areas/reading.md#srp-reading-01-markdownpreview-runs-seven-jobs-from-37-stored-properties-and-one-127-line-body) | READING | Medium | `MarkdownPreview` runs seven jobs from 37 stored properties and one 127-line `body` |
| [SRP-READING-02](../areas/reading.md#srp-reading-02-markdownpreviewswift-is-a-64-type-library-file-that-other-areas-depend-on) | READING | Medium | `MarkdownPreview.swift` is a 64-type library file that other areas depend on |
| [SRP-READING-03](../areas/reading.md#srp-reading-03-readingviewbuilder-mixes-block-assembly-with-file-io-and-a-link-rule-shared-with-live-preview) | READING | Medium | `ReadingViewBuilder` mixes block assembly with file I/O and a link rule shared with Live Preview |
| [SRP-READING-04](../areas/reading.md#srp-reading-04-markdownpane-owns-toolbar-menus-imports-read-aloud-rules-and-editor-wiring-for-one-note) | READING | Medium | `MarkdownPane` owns toolbar, menus, imports, Read Aloud rules and editor wiring for one note |
| [SRP-READING-05](../areas/reading.md#srp-reading-05-autosave-and-file-inspection-live-in-invisible-background-views) | READING | Medium | Autosave and file inspection live in invisible background views |
| [SRP-READING-06](../areas/reading.md#srp-reading-06-apply-an-edit-to-a-note-open-or-closed-is-implemented-three-times-with-three-save-rules) | READING | Medium | "Apply an edit to a note, open or closed" is implemented three times with three save rules |
| [SRP-RUNTIME-01](../areas/runtime.md#srp-runtime-01-pluginsjs-is-one-1324-code-line-closure-with-about-18-responsibilities) | RUNTIME | Medium | `plugins.js` is one 1324-code-line closure with about 18 responsibilities |
| [SRP-RUNTIME-03](../areas/runtime.md#srp-runtime-03-readingjs-mixes-a-global-prototype-patch-event-replay-dom-copying-style-reporting-view-placement-and-link-interception) | RUNTIME | Medium | `reading.js` mixes a global prototype patch, event replay, DOM copying, style reporting, view placement and link interception |
| [SRP-RUNTIME-04](../areas/runtime.md#srp-runtime-04-workspace-and-workspaceleaf-carry-graphites-host-protocol-as-loose-fields-alongside-obsidians-api) | RUNTIME | Medium | `Workspace` and `WorkspaceLeaf` carry Graphite's host protocol as loose fields alongside Obsidian's API |
| [SRP-RUNTIME-05](../areas/runtime.md#srp-runtime-05-the-adapter-has-two-per-path-serialization-queues-and-some-writes-use-neither) | RUNTIME | Medium | The adapter has two per-path serialization queues and some writes use neither |
| [SRP-SHELL-03](../areas/shell.md#srp-shell-03-outcomes-of-80-operations-are-reported-through-one-shared-errormessage-string-slot) | SHELL | Medium | Outcomes of 80 operations are reported through one shared `errorMessage: String?` slot |
| [SRP-SHELL-04](../areas/shell.md#srp-shell-04-graphiterootview-mixes-window-layout-twelve-presentations-the-deep-link-queue-scene-lifecycle-saving-and-draft-recovery) | SHELL | Medium | `GraphiteRootView` mixes window layout, twelve presentations, the deep-link queue, scene-lifecycle saving and draft recovery |
| [SRP-SHELL-05](../areas/shell.md#srp-shell-05-views-read-the-disk-while-drawing-and-two-model-functions-enumerate-folders-on-the-main-actor) | SHELL | Medium | Views read the disk while drawing, and two model functions enumerate folders on the main actor |
| [SRP-SHELL-06](../areas/shell.md#srp-shell-06-graphitepreferences-serves-nine-feature-areas-with-36-stored-properties-and-its-file-holds-eight-unrelated-concepts) | SHELL | Medium | `GraphitePreferences` serves nine feature areas with 36 stored properties, and its file holds eight unrelated concepts |
| [SRP-VAULT-01](../areas/vault.md#srp-vault-01-vaultstore-is-one-actor-for-file-io-file-management-naming-policy-and-six-obsidian-settings-files) | VAULT | Medium | `VaultStore` is one actor for file I/O, file management, naming policy and six Obsidian settings files |
| [SRP-VAULT-02](../areas/vault.md#srp-vault-02-vaultindex-owns-schema-cache-placement-scanning-refresh-and-five-query-families) | VAULT | Medium | `VaultIndex` owns schema, cache placement, scanning, refresh and five query families |
| [SRP-VAULT-03](../areas/vault.md#srp-vault-03-the-scans-state-is-a-boolean-an-optional-and-a-dictionary-that-must-change-together) | VAULT | Medium | The scan's state is a boolean, an optional and a dictionary that must change together |
| [SRP-VOICE-03](../areas/voice.md#srp-voice-03-readaloudsession-mixes-playback-voice-catalogue-highlight-projection-and-preference-storage) | VOICE | Medium | `ReadAloudSession` mixes playback, voice catalogue, highlight projection and preference storage |
| [SRP-VOICE-04](../areas/voice.md#srp-voice-04-readaloudnavigator-combines-queue-persistence-pen-range-taps-and-layout-frames) | VOICE | Medium | `ReadAloudNavigator` combines queue, persistence, pen, range taps and layout frames |
| [SRP-VOICE-05](../areas/voice.md#srp-voice-05-readaloudpassagepreparation-is-scheduler-render-retry-policy-and-status-in-one-observable-object) | VOICE | Medium | `ReadAloudPassagePreparation` is scheduler, render-retry policy and status in one observable object |
| [SRP-BASES-04](../areas/bases.md#srp-bases-04-image-reference-and-colour-classification-is-decided-in-core-and-again-in-the-view) | BASES | Low | Image-reference and colour classification is decided in Core and again in the view |
| [SRP-BASES-05](../areas/bases.md#srp-bases-05-basequeryswift-mixes-the-engine-with-result-types-summaries-and-coordinate-parsing) | BASES | Low | `BaseQuery.swift` mixes the engine with result types, summaries and coordinate parsing |
| [SRP-CANVAS-05](../areas/canvas.md#srp-canvas-05-canvaspane-assembles-workspace-services-and-runs-file-flows) | CANVAS | Low | `CanvasPane` assembles workspace services and runs file flows |
| [SRP-EDITOR-05](../areas/editor.md#srp-editor-05-rendered-block-views-read-files-and-construct-their-own-services) | EDITOR | Low | Rendered-block views read files and construct their own services |
| [SRP-INK-06](../areas/ink.md#srp-ink-06-files-hold-several-unrelated-concepts) | INK | Low | Files hold several unrelated concepts |
| [SRP-MDCORE-04](../areas/mdcore.md#srp-mdcore-04-markdownsemanticsswift-holds-18-types-11-of-them-unrelated-to-semantics) | MDCORE | Low | `MarkdownSemantics.swift` holds 18 types, 11 of them unrelated to semantics |
| [SRP-MDCORE-06](../areas/mdcore.md#srp-mdcore-06-codelinescanner-puts-three-grammars-in-one-734-line-struct) | MDCORE | Low | `CodeLineScanner` puts three grammars in one 734-line struct |
| [SRP-PLUGIN-05](../areas/plugin.md#srp-plugin-05-graphitethemeswift-holds-eight-unrelated-concepts) | PLUGIN | Low | `GraphiteTheme.swift` holds eight unrelated concepts |
| [SRP-PLUGIN-06](../areas/plugin.md#srp-plugin-06-communityplugineditorchangeswift-holds-a-text-diff-and-a-markdown-renderer) | PLUGIN | Low | `CommunityPluginEditorChange.swift` holds a text diff and a Markdown renderer |
| [SRP-READING-07](../areas/reading.md#srp-reading-07-notelinksinspector-parses-notes-and-queries-the-index-from-its-view-tasks) | READING | Low | `NoteLinksInspector` parses notes and queries the index from its view tasks |
| [SRP-READING-08](../areas/reading.md#srp-reading-08-property-text-parsing-rules-live-in-the-ui-target) | READING | Low | Property text parsing rules live in the UI target |
| [SRP-RUNTIME-06](../areas/runtime.md#srp-runtime-06-plugin-panel-presentation-is-derived-by-hand-from-four-fields) | RUNTIME | Low | Plugin panel presentation is derived by hand from four fields |
| [SRP-VAULT-04](../areas/vault.md#srp-vault-04-searchqueryswift-and-linkrewriterswift-hold-7-and-5-concepts-in-one-file-each) | VAULT | Low | `SearchQuery.swift` and `LinkRewriter.swift` hold 7 and 5 concepts in one file each |
| [SRP-VAULT-05](../areas/vault.md#srp-vault-05-vaultindexreconcile-mixes-enumeration-failure-policy-and-pruning-sql-in-56-lines) | VAULT | Low | `VaultIndex.reconcile` mixes enumeration, failure policy and pruning SQL in 56 lines |

## 6. Rules for new code

Each rule gives the requirement, the review check and the findings it answers.

**SRP 1. One aggregate and one kind of work per type.** A type that holds state must own one aggregate (an open vault, one note's text, one canvas file, one PDF, one reading, one plugin session) and one kind of work (deciding, storing, presenting or adapting a platform API). A class with more than 15 stored properties must record in its doc comment the responsibilities that justify it.
*Check:* count the stored `var` and `let` declarations of every new or changed class (a script counts them); more than 15 without a recorded reason blocks the change.
*Answers:* `SRP-SHELL-01`, `SRP-ARCH-01`, `SRP-PLUGIN-01`, `SRP-EDITOR-01`, `SRP-EDITOR-02`, `SRP-LECTURE-01`, `SRP-LECTURE-02`, `SRP-VOICE-01`, `SRP-VOICE-03`, `SRP-VOICE-04`, `SRP-VOICE-05`, `SRP-CANVAS-01`, `SRP-INK-01`, `SRP-INK-02`, `SRP-READING-01`, `SRP-BASES-01`, `SRP-BASES-02`, `SRP-VAULT-01`, `SRP-VAULT-02`.

**SRP 2. No application-wide model and no logic in the composition root.** A view or helper must receive the narrow model or the capability values it uses, never `WorkspaceModel` or `CommunityPluginHost` whole; the object that builds the graph holds no state and no rules.
*Check:* an initializer or property of a new type whose type is `WorkspaceModel`, `CommunityPluginHost` or `PDFSession` is justified by the number of members it reads (more than 7 is a finding); `GraphiteRootView` and the composition root gain no stored property.
*Answers:* `SRP-SHELL-01`, `SRP-ARCH-01`, `SRP-READING-04`, `SRP-PLUGIN-01`, `SRP-CANVAS-05`, `SRP-SHELL-04`.

**SRP 3. A feature never extends another feature's aggregate.** New behaviour of a feature must live in a type that the feature owns; an `extension` of `WorkspaceModel`, `PDFSession` or `CommunityPluginHost` must sit in a file of the aggregate's own group, and no extension may write another feature's state.
*Check:* `grep -n "^extension \(WorkspaceModel\|PDFSession\|CommunityPluginHost\)"` outside the aggregate's own files returns nothing new.
*Answers:* `SRP-ARCH-01`, `SRP-SHELL-01`, `SRP-PLUGIN-04`, `SRP-INK-06`, `SRP-LECTURE-02`.

**SRP 4. Teardown replaces or releases a value; it never resets fields.** State that lives for one vault, runtime, reading or session must be held in one value or object that the owner replaces or releases when the lifetime ends; a function that assigns five or more fields back to empty values is rejected. Cleanup duties that cannot live in that value must be opt-in by conformance to a lifecycle protocol, and the coordinator iterates conformers without naming a feature.
*Check:* grep new `reset`, `clear`, `stop`, `begin` and `openVault` bodies for runs of assignments to `nil`, `[]`, `[:]`, `false` or `""`; a coordinator body that names a feature type in its teardown is a finding.
*Answers:* `SRP-SHELL-02`, `SRP-ARCH-05`, `SRP-PLUGIN-02`, `SRP-VOICE-01`, `SRP-RUNTIME-04`.

**SRP 5. Decide, then do.** A function that decides (what to insert, which range, which repair, which classification, which retry) must be pure: inputs and `now` in, a value or plan out, in Core where it compiles on both platforms; a separate type performs the plan. An orchestrating function names its stages and holds none of their details.
*Check:* a function that contains both a `switch` or rule table producing a value and a call to I/O, a platform object or a task is split; each new decision type has a test that constructs it with plain values.
*Answers:* `SRP-EDITOR-03`, `SRP-EDITOR-04`, `SRP-INK-02`, `SRP-VOICE-02`, `SRP-VOICE-05`, `SRP-MDCORE-02`, `SRP-LECTURE-07`, `SRP-BASES-01`, `SRP-VAULT-02`, `SRP-VAULT-05`, `SRP-CANVAS-02`.

**SRP 6. Platform delegates are adapters.** A class that conforms to platform delegate protocols (`UITextViewDelegate`, `PDFPageOverlayViewProvider`, `PKCanvasViewDelegate`, `NSTextLayoutManagerDelegate`, `WKScriptMessageHandler`) must forward each callback to an owned collaborator and keep only the state needed to forward; a callback that does more than three jobs asks a policy for a decision value and performs it. A `PKCanvasView` subclass records history and nothing else.
*Check:* a class with two or more delegate conformances and more than 15 stored properties, or a delegate method with more than three statements of unrelated work, is rejected.
*Answers:* `SRP-EDITOR-01`, `SRP-EDITOR-04`, `SRP-LECTURE-01`, `SRP-INK-01`, `SRP-INK-02`, `SRP-INK-04`.

**SRP 7. UI code does no I/O and decides no rule.** A view, a view task, a `body` and a drawing closure must not touch `FileManager`, `AtomicFileWriter`, `ImageFileService`, `URLSession`, an installer, `UserDefaults`, the pasteboard or `Task.sleep` for a rule, and must not parse notes; each UI event calls one model method that returns a typed result, and the view renders it.
*Check:* grep the new view file for `FileManager|AtomicFileWriter\(|ImageFileService\(|Installer\(|UIPasteboard|UserDefaults|\.read\(|Task.sleep`; any hit outside a model is a finding.
*Answers:* `SRP-SHELL-05`, `SRP-CANVAS-03`, `SRP-CANVAS-05`, `SRP-EDITOR-05`, `SRP-INK-05`, `SRP-LECTURE-04`, `SRP-LECTURE-05`, `SRP-READING-03`, `SRP-READING-04`, `SRP-READING-07`, `SRP-PLUGIN-03`, `SRP-BASES-04`.

**SRP 8. Rendering and getters write nothing.** `body`, `draw`, `Canvas` closures, computed properties and predicates must not assign model state, start tasks or touch disk; geometry that both drawing and hit testing need is one pure function.
*Check:* an assignment to a property of a model or session inside `body`, `Canvas { }` or a computed getter is a finding.
*Answers:* `SRP-CANVAS-02`, `SRP-SHELL-05`, `SRP-INK-05`, `SRP-EDITOR-05`.

**SRP 9. Work that must happen has an owner that exists without a view.** Autosave, release, background inspection and any other duty must be started and cancelled by a model or session; a hidden view (`Color.clear`, a zero-size driver) must not own it.
*Check:* grep for `Color.clear` or `EmptyView` carrying `.task` or `.onChange` that calls a save or I/O method; a `Task { }` with no stored handle in a view closure is a finding.
*Answers:* `SRP-READING-05`, `SRP-READING-07`, `SRP-LECTURE-04`, `SRP-CANVAS-05`.

**SRP 10. Every business rule has exactly one owner.** A rule (link resolution, code-fence and block detection, applying an edit to a note open or closed, viewport and fitting, image-reference classification, write queueing, install outcome wording) must be implemented once, in the type that names it; a second implementation is allowed only as a documented performance mirror with a parity test. A rule that spans two responsibilities (typed text is committed before a history step) belongs to the type that owns both.
*Check:* before adding a function that classifies, resolves or rewrites, search for the rule's existing owner (`WikiLinkResolver`, `CodeFence`, `MarkdownLineSyntax`, `FrontmatterLocator`); a new copy without a parity test is rejected.
*Answers:* `SRP-BASES-03`, `SRP-BASES-04`, `SRP-READING-06`, `SRP-READING-03`, `SRP-READING-08`, `SRP-MDCORE-01`, `SRP-MDCORE-03`, `SRP-MDCORE-05`, `SRP-CANVAS-01`, `SRP-CANVAS-04`, `SRP-RUNTIME-05`, `SRP-VAULT-05`, `SRP-EDITOR-03`, `SRP-EDITOR-05`, `SRP-PLUGIN-03`, `SRP-LECTURE-07`, `SRP-SHELL-04`.

**SRP 11. A flow with more than two states is an enum; fields that change together are one value.** Booleans and optionals that must be set together (`isScanning` with `activeScanGeneration`, `isPresented` with the panel content, `hasBeenShown` with `isProbe`, four writing-position flags, twelve presentation booleans) must become one enum or struct changed only through intent methods.
*Check:* three or more `Bool` or optional properties of one type that appear in the same `didSet`, `defer` or assignment group are a finding; the replacement has a test per transition.
*Answers:* `SRP-VAULT-03`, `SRP-MDCORE-02`, `SRP-RUNTIME-04`, `SRP-RUNTIME-06`, `SRP-ARCH-04`, `SRP-SHELL-04`, `SRP-READING-01`, `SRP-INK-03`.

**SRP 12. Outcomes and requests travel as values.** An operation must return or throw a typed outcome; a request to another object must be a method call or an entry in a typed queue that the receiver must drain, never a field the receiver polls; one presenter turns typed alerts into words, and no shared `errorMessage` slot is written by more than one workflow.
*Check:* a `String?` or `Bool` property written by two or more functions of different workflows and read by a view is a finding; every new request type has a test that each editor variant drains it.
*Answers:* `SRP-SHELL-03`, `SRP-BASES-02`, `SRP-EDITOR-02`, `SRP-CANVAS-01`, `SRP-ARCH-04`, `SRP-LECTURE-07`, `SRP-PLUGIN-04`, `SRP-INK-05`.

**SRP 13. Derived state is a projection of its inputs.** A value that is a function of another (picture arrangement shown on the canvas, tab selection, a settings baseline) must be computed or projected from one place; no correctness may depend on a caller remembering a follow-up call, and no view keeps its own copy of controller state.
*Check:* a new method that mutates source state must not be followed by a manual `show…` or `refresh…` call at its call sites; the number of call sites of any projection function is 1.
*Answers:* `SRP-INK-03`, `SRP-INK-04`, `SRP-VAULT-01`, `SRP-READING-01`.

**SRP 14. A controller serving several kinds of work holds one active value of the current kind.** A controller for audio and video recording, or Markdown and PDF reading, must hold one optional active session whose type is the current kind, behind a protocol only where two production implementations exist; fields of one kind must not be live in the other.
*Check:* a controller with properties that are `nil` or unused in some of its modes (`camera` while recording audio, `pdfRunningText` while reading a note) is a finding.
*Answers:* `SRP-LECTURE-03`, `SRP-VOICE-01`, `SRP-VOICE-03`, `SRP-PLUGIN-01`.

**SRP 15. A settings store serves one feature area and one scope.** A preferences type must own the keys of one feature area over the typed key registry; per-vault state must not live in a per-device store, and a settings baseline must travel in the value the read returns.
*Check:* a preferences type with more than 15 stored properties or an `init` longer than 40 code lines is split; a key written by the workspace into a per-device store for per-vault data is a finding.
*Answers:* `SRP-SHELL-06`, `SRP-VAULT-01`, `SRP-ARCH-05`.

**SRP 16. A function does one meaningful thing at one level.** A function over 40 code lines, nesting deeper than 5, more than 6 parameters or a `body` over 60 code lines must carry a recorded design review in its doc comment (a long straightforward sequence may stay whole); a SwiftUI `body` composes named subviews and holds no logic.
*Check:* a script lists functions and `body` properties over 40 code lines in the diff; each needs the recorded reason or a split.
*Answers:* `SRP-VOICE-02`, `SRP-SHELL-04`, `SRP-READING-01`, `SRP-READING-04`, `SRP-LECTURE-05`, `SRP-LECTURE-06`, `SRP-BASES-01`, `SRP-BASES-02`, `SRP-MDCORE-02`, `SRP-MDCORE-06`, `SRP-EDITOR-04`.

**SRP 17. One concept per file, named after it.** A file must hold one concept and be named after it; a file that needs a name like Manager, Helper, Utils or Misc, or that holds unrelated types, is split by responsibility (never by size, never `Part1`). A primitive that other features use (a callout view, an image cache, a media player, a media-kind enum) lives in a file named after it, not in the file of its first user.
*Check:* a script lists files with more than one top-level type whose names share no concept, and files whose name differs from their primary type; the reviewer rejects `Manager`, `Helper`, `Utils` in a type or file name.
*Answers:* `SRP-READING-02`, `SRP-BASES-05`, `SRP-INK-06`, `SRP-LECTURE-06`, `SRP-MDCORE-04`, `SRP-MDCORE-06`, `SRP-PLUGIN-05`, `SRP-PLUGIN-06`, `SRP-VAULT-04`, `SRP-SHELL-06`.

**SRP 18. A module holds one layer.** `GraphiteCore` must contain values, parsers, policies and planners only: no `FileManager`, `URLSession` (not even as a default argument), keychain or Application Support access; storage, network and platform adapters live in modules that the consuming layer's ports describe. New feature code goes in a feature module, not in `GraphiteUI`; a Core type that two features need is promoted to Core once, not copied.
*Check:* grep new `GraphiteCore` files for `FileManager|URLSession|Keychain|applicationSupport`; a new file in `GraphiteUI` that is not a view, a model of a screen or a platform bridge is a finding; Property parsing rules (`PropertyNumberText`, `PropertyDateText`) belong beside `NoteProperties` in Core.
*Answers:* `SRP-ARCH-02`, `SRP-ARCH-03`, `SRP-READING-08`, `SRP-PLUGIN-04`, `SRP-VAULT-02`.

**SRP 19. A resource script is one object per responsibility.** In the plugin runtime each file must export one object with one responsibility, receive its collaborators at construction, register message handlers through a router, and hold no module-level mutable variable shared with another responsibility; no code may read or write the global `GraphitePluginRuntime` as a registry.
*Check:* `grep -n "runtime\.[a-zA-Z]* = "` in a new runtime script returns nothing; the Node harness loads the new file alone with a fake of its collaborators.
*Answers:* `SRP-RUNTIME-01`, `SRP-RUNTIME-02`, `SRP-RUNTIME-03`, `SRP-RUNTIME-04`, `SRP-RUNTIME-05`, `SRP-RUNTIME-06`.

**SRP 20. Every extracted responsibility is tested alone.** A split is finished only when each extracted type has a test that constructs it without a window, a `WorkspaceModel`, a real vault on disk, a `PDFView` or a running WebKit page, and the pure ones compile and run under `swift test` on macOS.
*Check:* the test file for a new type imports only the package modules and constructs the type with plain values or fakes from the test-support module; a hosted-only test for a pure rule is a finding.
*Answers:* `SRP-EDITOR-01`, `SRP-BASES-02`, `SRP-CANVAS-01`, `SRP-CANVAS-03`, `SRP-INK-01`, `SRP-INK-02`, `SRP-VOICE-04`, `SRP-PLUGIN-01`, `SRP-PLUGIN-03`, `SRP-LECTURE-02`, `SRP-READING-01`, `SRP-SHELL-01`.

## 7. Corrections

Disagreements between the area documents, or between a document and the snapshot, settled from the code.

| Subject | Documents say | The snapshot shows | Use |
| --- | --- | --- | --- |
| `WorkspaceModel` extension files | SHELL verdict: "22 more extension files"; `SRP-SHELL-01` and `SRP-ARCH-01`: 24 blocks in 23 files | `grep` finds 24 `extension WorkspaceModel` blocks in 23 files | 24 blocks in 23 files |
| `WorkspaceModel` responsibility count | SHELL: "about 15"; ARCH: 12; SHELL's own table: 22 rows | The 22 rows are the stored-state groups; the 15 and the 12 are coarser groupings of them | 22 mapped groups, quoted as "more than a dozen workflows" |
| `GraphiteUI` code lines | ARCH `SRP-ARCH-02`: 46,252 | [metrics.md](../metrics.md) line 20 and the ARCH verdict of section 1: 46,253 | 46,253 |
| Files that assign into `GraphitePluginRuntime` | `SRP-RUNTIME-02`: 11 files | Direct `runtime.member = ` assignments occur in 9 files (foundation 13, plugins 21, workspace 6, reading 4, bases 3, interface 2, vault 2, metadata 1, settings 1); `host-connection.js` only writes `runtime.hostBridge.transport`; `dom-extensions.js` never touches the namespace. Eleven is the number of scripts | 9 files assign members (10 including the transport), 50 distinct members |
| Reads of `runtime.app` | `SRP-RUNTIME-02`: 61 in 6 files | `grep` finds 72 occurrences on 57 lines in 6 files, one of them the assignment at [plugins.js:1247](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime-plugins.js#L1247) | 6 files; the count is of occurrences, not reads |
| Responsibilities of `plugins.js` | RUNTIME verdict: "about 18"; `SRP-RUNTIME-01` and §3.2: 20 rows | The §3.2 table has 20 rows | 20 |
| Assignments of `errorMessage` | `SRP-SHELL-03`: 82 (84 matches) | `grep "errorMessage = "` over `Workspace*.swift` finds 85 matches, 2 of them on `pdfSession` | 83 on the workspace slot |
| Fields reset by `openVault` | ARCH `SRP-ARCH-05`: about 25 at lines 303-323; SHELL `SRP-SHELL-02`: 33 at lines 303-337 | The function resets fields from line 303 through line 337 (the vault's own fields are assigned after line 323) | 33 (SHELL) |
