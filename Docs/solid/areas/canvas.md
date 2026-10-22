# Canvas, JSON Canvas, graph view and maps (CANVAS)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteCore/{CanvasFile, CanvasFileEditing, CanvasGeometry, CanvasJSON, CanvasLinks, GraphLayout, PlacedNote}.swift` and `Sources/GraphiteUI/{CanvasBoardHost, CanvasBoardView, CanvasCardViews, CanvasInteraction, CanvasPane, CanvasSession, GraphCanvas, GraphViews, MapViews, NotesMapView, WorkspaceCanvas, WorkspaceGraph, WorkspaceMap}.swift`, 20 files, 5894 physical lines, 4751 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script).

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Mixed | The 7 Core files each own one concern; `CanvasSession` holds 34 stored properties across 8 responsibilities, and views do file I/O in 5 places. |
| O | Mixed | Card kinds are an exhaustive enum switched without `default:`; file-card kind dispatch is repeated in 4 places (2 with `default:`), and the JSON Canvas type vocabulary is spelled in 3 places. |
| L | Mostly strong | Byte-exact undo is pinned by contract tests; the Mac and UIKit board hosts behave differently (no tap on the Mac), an unreadable canvas reports zero links, and duplicate-`id` cards get identities that move when earlier entries are removed. |
| I | Mixed | `CanvasPane` and `CanvasFilePicker` take the whole `WorkspaceModel` to use about 20 members; the local graph and map panels take a `MarkdownSession` to read one property; views write 6 session fields directly. |
| D | Mixed | Core imports no UI and the session receives its store, but `UserDefaults.standard`, 2 singletons, `FileManager.default` in views and direct file reads in Core remain. |
| Clean code | Mixed | Names and comments are careful and state rules; 10 functions exceed 40 code lines, drag state is split across one enum and 4 loose fields, 3 loops are driven by `Task.sleep`, and Core carries English user text. |

## 1. Summary

**What the area does.** A `.canvas` file (JSON Canvas 1.0) is read by a hand-written, position-recording JSON parser ([CanvasJSON.swift:93-333](../../../Sources/GraphiteCore/CanvasJSON.swift#L93-L333)) into `CanvasFile`, which keeps the original bytes as the document and exposes the cards and connections it understands ([CanvasFile.swift:144-237](../../../Sources/GraphiteCore/CanvasFile.swift#L144-L237)). Every edit is a `CanvasChange` turned into byte splices; applying splices returns the inverse patch, which is the undo step ([CanvasFileEditing.swift:56-112](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L56-L112)). `CanvasGeometry` holds viewport, routing, hit testing, snapping and reading order as pure Core code. In the UI, `CanvasSession` (one `@Observable` class plus a 358-code-line extension) owns the open document, history, saving, viewport, selection, gestures and commands; `CanvasBoardHost` wraps the SwiftUI board in UIKit recognizers on iPadOS/iPhone and in SwiftUI gestures on the Mac; `CanvasBoardView` and `CanvasCardViews` draw it in level-of-detail layers. The graph view is d3's force layout in Core (`GraphLayout`) stepped by an actor (`GraphSimulator`) and drawn by `GraphCanvas`; the map view reads placing properties (`PlacedNote`) and shows them with MapKit (`NotesMapView`). `WorkspaceCanvas/Graph/Map.swift` are `WorkspaceModel` extensions that open sessions and cache graph and map results.

**The three biggest problems.**
1. `CanvasSession` is a 34-property aggregate whose history, text editing and persistence share mutable fields; the coupling produces a data-loss defect: the toolbar's Undo while typing in a text card drops the typed text and undoes an unrelated earlier step ([BUG-CANVAS-01](#bug-canvas-01-undo-while-typing-in-a-text-card-discards-the-typed-text-and-undoes-the-step-before-it)).
2. Canvas sessions are second-class in workspace lifecycles written for notes: edits made while the canvas (or its folder) moves are dropped when the tab unloads ([BUG-CANVAS-02](#bug-canvas-02-edits-made-to-an-open-canvas-while-it-or-its-folder-moves-are-lost)), and the Mac host has no tap, so long card content never scrolls there ([BUG-CANVAS-03](#bug-canvas-03-on-the-mac-the-content-of-a-text-note-or-base-card-longer-than-its-card-cannot-be-scrolled)).
3. Views perform I/O and write model state: the board's renderer assigns `session.groupLabelFrames` during drawing, which hit testing then reads ([CanvasBoardView.swift:121](../../../Sources/GraphiteUI/CanvasBoardView.swift#L121)); card views check file existence, read notes and render PDFs from `.task` blocks through `FileManager.default`, `AtomicFileWriter()` and two `.shared` singletons.

**The three best parts.**
1. Lossless JSON Canvas editing: splices at recorded byte ranges, layout-following insertion, inverse patches, and a re-parse of every result before it is adopted ([CanvasFileEditing.swift:93-112](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L93-L112)), pinned byte for byte by [CanvasEditingTests.swift:11-19](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L11-L19).
2. Decisions are separated from views: geometry is pure Core, and gestures are decided in view coordinates by `CanvasSession` methods that tests drive without a screen ([CanvasInteraction.swift:18-21](../../../Sources/GraphiteUI/CanvasInteraction.swift#L18-L21), [CanvasSessionTests.swift:60-68](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L60-L68)).
3. Save safety: a canvas only looked at is never written, saves are revision-checked, and a conflict offers "Save a Copy" or "Use Other Version" ([CanvasSession.swift:311-403](../../../Sources/GraphiteUI/CanvasSession.swift#L311-L403)).

**Earlier-pass claims.**

| Claim (source) | Verdict | Evidence |
| --- | --- | --- |
| `CanvasSession` receives a store instead of implementing atomic replacement (`Docs/SOLID.md` at b13dec3) | Holds | [CanvasSession.swift:68](../../../Sources/GraphiteUI/CanvasSession.swift#L68), [CanvasSession.swift:329](../../../Sources/GraphiteUI/CanvasSession.swift#L329) |
| Sessions receive the complete `VaultStore` (`Docs/SOLID.md` at b13dec3) | Holds | `CanvasSession` stores `VaultStore` ([CanvasSession.swift:68](../../../Sources/GraphiteUI/CanvasSession.swift#L68)) and uses 4 members: `read`, `save`, `fileExists`, `uniquePath` ([CanvasSession.swift:329](../../../Sources/GraphiteUI/CanvasSession.swift#L329), [352](../../../Sources/GraphiteUI/CanvasSession.swift#L352), [365](../../../Sources/GraphiteUI/CanvasSession.swift#L365), [392](../../../Sources/GraphiteUI/CanvasSession.swift#L392)) |
| `CanvasSession` uses `UserDefaults.standard` directly (`Docs/SOLID.md` at b13dec3) | Holds | [CanvasSession.swift:151-156](../../../Sources/GraphiteUI/CanvasSession.swift#L151-L156) |
| `CanvasSessionTests` assert retained edits and conflict behaviour (`Docs/SOLID.md` at b13dec3) | Holds | [CanvasSessionTests.swift:357-389](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L357-L389) |
| Unknown keys, card types, key order, whitespace, line endings and BOM stay in the bytes; edits are splices; new entries are written as Obsidian writes them with 16-hex-digit ids ([Architecture.md:290](../../../Docs/Architecture.md)) | Holds | [CanvasJSON.swift:92-117](../../../Sources/GraphiteCore/CanvasJSON.swift#L92-L117), [CanvasFileEditing.swift:232-345](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L232-L345), [CanvasFileEditing.swift:114-127](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L114-L127) |
| Undo gives the file back byte for byte; a canvas only looked at is never written ([Architecture.md:290](../../../Docs/Architecture.md)) | Holds | [CanvasFileEditing.swift:67-87](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L67-L87), [CanvasSession.swift:318-325](../../../Sources/GraphiteUI/CanvasSession.swift#L318-L325), tests [CanvasEditingTests.swift:241-269](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L241-L269), [CanvasSessionTests.swift:72-95](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L72-L95) |
| Untrusted input is bounded (16 MB, depth 64, 2,000,000 values, 50,000 cards, 100,000 connections, ±10⁷) ([Architecture.md:290](../../../Docs/Architecture.md)) | Holds, incomplete | Bounds at [CanvasFile.swift:149-155](../../../Sources/GraphiteCore/CanvasFile.swift#L149-L155) and [CanvasJSON.swift:96-97](../../../Sources/GraphiteCore/CanvasJSON.swift#L96-L97); the document omits the 1,000,000-pixel side limit, which [BUG-CANVAS-04](#bug-canvas-04-a-card-resized-or-grouped-beyond-1000000-pixels-disappears-from-the-board-after-the-edit) shows the writer does not respect |
| Detail below a third of full size or beyond the 60 cards nearest the middle is drawn as shapes ([Architecture.md:292](../../../Docs/Architecture.md)) | Holds | [CanvasSession.swift:59-64](../../../Sources/GraphiteUI/CanvasSession.swift#L59-L64) (0.3 and 60) |
| With VoiceOver or Switch Control on, "every card is an element in reading order" ([Architecture.md:292](../../../Docs/Architecture.md)) | Does not hold for large boards | Elements are capped at the first 1,000 in reading order ([CanvasBoardView.swift:493-503](../../../Sources/GraphiteUI/CanvasBoardView.swift#L493-L503)) |
| "The Mac app can look at a board; editing is iPad-only" ([Architecture.md:292](../../../Docs/Architecture.md)) | Does not hold as written | Editing is gated by `canImport(UIKit)`, so iPhone edits too ([WorkspaceCanvas.swift:14-17](../../../Sources/GraphiteUI/WorkspaceCanvas.swift#L14-L17), [CanvasPane.swift:145-150](../../../Sources/GraphiteUI/CanvasPane.swift#L145-L150)); "looking" on the Mac excludes scrolling card content ([BUG-CANVAS-03](#bug-canvas-03-on-the-mac-the-content-of-a-text-note-or-base-card-longer-than-its-card-cannot-be-scrolled)) |
| Renames rewrite canvases through `CanvasFile.replacing`, "and an open canvas takes the change in at once" ([Architecture.md:294](../../../Docs/Architecture.md)) | Holds when the canvas has no unsaved edits | [VaultFileOperations.swift:122-129](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L122-L129), [WorkspaceFileManagement.swift:158](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L158); with unsaved edits the canvas shows a conflict instead ([CanvasSession.swift:354-356](../../../Sources/GraphiteUI/CanvasSession.swift#L354-L356)) |
| Graph view: d3 forces with Barnes–Hut, stepped in an actor, cached per index change, positions kept while the app runs, filters and forces kept on the device ([Architecture.md:133](../../../Docs/Architecture.md)) | Holds | [GraphLayout.swift:120-182](../../../Sources/GraphiteCore/GraphLayout.swift#L120-L182), [GraphCanvas.swift:6-33](../../../Sources/GraphiteUI/GraphCanvas.swift#L6-L33), [WorkspaceGraph.swift:7-19](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L7-L19), [GraphViews.swift:8-14](../../../Sources/GraphiteUI/GraphViews.swift#L8-L14) |
| Map view: plugin properties first (`data.json` ≤ 1 MB), then `coordinates` and `location`; MapKit clustering; the open note stands apart ([Architecture.md:134](../../../Docs/Architecture.md)) | Holds | [PlacedNote.swift:20-45](../../../Sources/GraphiteCore/PlacedNote.swift#L20-L45), [NotesMapView.swift:52-88](../../../Sources/GraphiteUI/NotesMapView.swift#L52-L88) |

## 2. File inventory

| File | Physical | Code | Responsibility |
| --- | ---: | ---: | --- |
| `GraphiteCore/CanvasFile.swift` | 312 | 224 | Card, connection and colour values; reading a parsed file into them; lookups |
| `GraphiteCore/CanvasFileEditing.swift` | 500 | 405 | `CanvasChange` → byte splices, inverse patches, new-entry writing, object key edits |
| `GraphiteCore/CanvasGeometry.swift` | 399 | 288 | Viewport, connection routes, hit testing, selection, snapping, reading order |
| `GraphiteCore/CanvasJSON.swift` | 370 | 313 | Bounded RFC 8259 parser recording byte ranges; string and integer writer; read errors with messages |
| `GraphiteCore/CanvasLinks.swift` | 97 | 72 | Link sources of a canvas for the index; rewriting them after moves |
| `GraphiteCore/GraphLayout.swift` | 302 | 241 | d3 force simulation with a Barnes–Hut quadtree |
| `GraphiteCore/PlacedNote.swift` | 66 | 46 | Placed-note value; property names from plugin settings; coordinate from properties |
| `GraphiteUI/CanvasBoardHost.swift` | 233 | 181 | UIKit gesture host (iOS) and SwiftUI gesture host (Mac) around the board |
| `GraphiteUI/CanvasBoardView.swift` | 598 | 500 | Palette, card environment, backdrop renderer, group backgrounds loader, card layer, selection layer, accessibility layer, card descriptions |
| `GraphiteUI/CanvasCardViews.swift` | 528 | 435 | Card render cache, card view, Markdown/note/image/PDF/link card contents, PDF page renderer actor |
| `GraphiteUI/CanvasInteraction.swift` | 463 | 368 | `CanvasSession` extension: drags, taps, selection commands, adding cards, web-address checks |
| `GraphiteUI/CanvasPane.swift` | 576 | 503 | Tab pane, banner, toolbar, file-card sizing, zoom/add/selection bars, colour chooser, name alert, file picker |
| `GraphiteUI/CanvasSession.swift` | 506 | 369 | Open canvas: document, history, saving, conflict, viewport animation, level of detail |
| `GraphiteUI/GraphCanvas.swift` | 384 | 325 | Graph simulator actor, observable graph model, graph view with drawing, gestures and fitting |
| `GraphiteUI/GraphViews.swift` | 160 | 149 | Local graph panel and whole-vault graph screen with settings |
| `GraphiteUI/MapViews.swift` | 111 | 100 | Local map panel and whole-vault map screen |
| `GraphiteUI/NotesMapView.swift` | 172 | 137 | MapKit map with clustered note markers |
| `GraphiteUI/WorkspaceCanvas.swift` | 38 | 29 | Workspace: open a canvas session, create a canvas |
| `GraphiteUI/WorkspaceGraph.swift` | 55 | 46 | Workspace: cached vault graph, opening graph nodes, graph setting keys |
| `GraphiteUI/WorkspaceMap.swift` | 24 | 20 | Workspace: cached placed notes |
| **Total** | **5894** | **4751** | |

## 3. Responsibility maps of the major types

### 3.1 `CanvasSession` (CanvasSession.swift 334 code lines + CanvasInteraction.swift extension 358 code lines)

Declared at [CanvasSession.swift:54-55](../../../Sources/GraphiteUI/CanvasSession.swift#L54-L55), `@MainActor @Observable`. 34 stored properties (counted by reading lines 67-156), 8 static configuration constants ([CanvasSession.swift:56-65](../../../Sources/GraphiteUI/CanvasSession.swift#L56-L65)) and two nested constant enums ([CanvasInteraction.swift:23-43](../../../Sources/GraphiteUI/CanvasInteraction.swift#L23-L43)).

| Responsibility | Stored state | Functions |
| --- | --- | --- |
| A. Document and history | `path`, `file`, `changeVersion`, `undoManager`, `undoAvailability` ([67](../../../Sources/GraphiteUI/CanvasSession.swift#L67), [74-76](../../../Sources/GraphiteUI/CanvasSession.swift#L74-L76), [94-101](../../../Sources/GraphiteUI/CanvasSession.swift#L94-L101)) | `perform`, `registerUndo`, `applyFromHistory`, `adopt(_ newFile:)` ([214-260](../../../Sources/GraphiteUI/CanvasSession.swift#L214-L260)); lookups `frame(of:)`, `shownNodes`, `route(of:)`, `selectedNodes`, `selectedEdges` ([169-191](../../../Sources/GraphiteUI/CanvasSession.swift#L169-L191)) |
| B. Persistence and conflict | `store`, `didSave`, `savedVersion`, `savedData`, `revision`, `activeSave`, `autosave`, `errorMessage`, `hasExternalConflict` ([68-69](../../../Sources/GraphiteUI/CanvasSession.swift#L68-L69), [77-83](../../../Sources/GraphiteUI/CanvasSession.swift#L77-L83)) | `isSaving`, `hasUnsavedChanges`, `scheduleAutosave`, `save`, `checkExternalChange`, `reload`, `adopt(_ snapshot:)`, `saveSeparateCopy` ([103-104](../../../Sources/GraphiteUI/CanvasSession.swift#L103-L104), [299-403](../../../Sources/GraphiteUI/CanvasSession.swift#L299-L403)) |
| C. Viewport, animation, level of detail | `viewport`, `viewSize`, `hasShownWholeBoard`, `detailedNodes`, `viewportAnimation` ([109-124](../../../Sources/GraphiteUI/CanvasSession.swift#L109-L124)) | `setViewport`, `stopViewportAnimation`, `zoomToFit`, `zoomToSelection`, `zoom(toNodeWithIdentifier:)`, `zoom(by:)`, `resetZoom`, `reveal`, `visibleBoardFrame`, `updateDetailedNodes` ([409-505](../../../Sources/GraphiteUI/CanvasSession.swift#L409-L505)) |
| D. Mode, selection and focus | `isWriting`, `selectedNodeIdentifiers`, `selectedEdgeIdentifiers`, `focusedNodeIdentifier` ([85-92](../../../Sources/GraphiteUI/CanvasSession.swift#L85-L92), [132-136](../../../Sources/GraphiteUI/CanvasSession.swift#L132-L136)) | `hasSelection`, `selectionBounds` ([192-199](../../../Sources/GraphiteUI/CanvasSession.swift#L192-L199)); `toggleSelection` ×2, `clearSelection`, `selectAll` ([CanvasInteraction.swift:270-288](../../../Sources/GraphiteUI/CanvasInteraction.swift#L270-L288)) |
| E. Gesture state machine | `activeDrag`, `previewFrames`, `snapGuides`, `selectionRectangle`, `pendingConnection` ([138-148](../../../Sources/GraphiteUI/CanvasSession.swift#L138-L148)) | `nodeWithHandles`, `connectionDotPosition`, `target`, `connectionTarget`, `beginDrag`, `continueDrag`, `endDrag`, `framesToSnapTo`, `tap`, `doubleTap`, `longPress` ([CanvasInteraction.swift:48-268](../../../Sources/GraphiteUI/CanvasInteraction.swift#L48-L268)) |
| F. Text editing in place | `textEdit` ([146](../../../Sources/GraphiteUI/CanvasSession.swift#L146)) | `hasUncommittedText`, `beginEditingText`, `updateTextEdit`, `commitTextEdit`, `endEditing` ([264-295](../../../Sources/GraphiteUI/CanvasSession.swift#L264-L295)) |
| G. Commands and card creation | `nameRequest` ([147](../../../Sources/GraphiteUI/CanvasSession.swift#L147)) | `deleteSelection`, `duplicateSelection`, `setColorOfSelection`, `bringSelectionToFront`, `sendSelectionToBack`, `setEndsOfSelectedEdges`, `setGroupLabel`, `setEdgeLabel`, `frameForNewCard`, `add`, `addTextCard`, `addFileCard`, `addLinkCard`, `addGroup`; static URL checks `webAddress`, `browsableLocation` ([CanvasInteraction.swift:292-462](../../../Sources/GraphiteUI/CanvasInteraction.swift#L292-L462)) |
| H. Device preferences and view-supplied caches | `snapsToGrid`, `snapsToObjects` (written to `UserDefaults.standard`), `groupLabelFrames` (written by the renderer), `cachedReadingPositions` ([127-128](../../../Sources/GraphiteUI/CanvasSession.swift#L127-L128), [151-156](../../../Sources/GraphiteUI/CanvasSession.swift#L151-L156)) | `readingPositions` (memoising getter, [203-208](../../../Sources/GraphiteUI/CanvasSession.swift#L203-L208)) |

**Calls that cross responsibilities (the coupling a split must preserve).**
- A → D, F, C, B: `adopt(_ newFile:)` filters the selection, clears focus and text edit for vanished cards, recomputes detail and schedules autosave ([CanvasSession.swift:250-260](../../../Sources/GraphiteUI/CanvasSession.swift#L250-L260)).
- A → F: `applyFromHistory` clears `textEdit` before applying a history step ([CanvasSession.swift:240-241](../../../Sources/GraphiteUI/CanvasSession.swift#L240-L241)); this is the origin of BUG-CANVAS-01.
- B → F → A: `save()` commits typed text through `perform` before writing ([CanvasSession.swift:312](../../../Sources/GraphiteUI/CanvasSession.swift#L312)); `hasUnsavedChanges` reads F ([CanvasSession.swift:104](../../../Sources/GraphiteUI/CanvasSession.swift#L104)).
- B → A, D, E: `adopt(_ snapshot:)` clears history and every gesture field ([CanvasSession.swift:371-386](../../../Sources/GraphiteUI/CanvasSession.swift#L371-L386)).
- D → F, D: setting `isWriting` ends editing, clears the selection and focus ([CanvasSession.swift:85-92](../../../Sources/GraphiteUI/CanvasSession.swift#L85-L92)).
- C ↔ E: `previewFrames` changes recompute detail ([CanvasSession.swift:138-140](../../../Sources/GraphiteUI/CanvasSession.swift#L138-L140)); drags read `viewport` for every conversion ([CanvasInteraction.swift:134-135](../../../Sources/GraphiteUI/CanvasInteraction.swift#L134-L135)); `beginDrag` stops the viewport animation ([CanvasInteraction.swift:85](../../../Sources/GraphiteUI/CanvasInteraction.swift#L85)).
- E → F → A: `beginDrag`, `tap`, `longPress` call `endEditing` ([CanvasInteraction.swift:118](../../../Sources/GraphiteUI/CanvasInteraction.swift#L118), [219](../../../Sources/GraphiteUI/CanvasInteraction.swift#L219), [262](../../../Sources/GraphiteUI/CanvasInteraction.swift#L262)).
- E → H: hit testing reads `groupLabelFrames`, which only the renderer fills ([CanvasInteraction.swift:69-71](../../../Sources/GraphiteUI/CanvasInteraction.swift#L69-L71), [CanvasBoardView.swift:121](../../../Sources/GraphiteUI/CanvasBoardView.swift#L121)).

**Lifecycle and ordering rules it relies on.**
1. `viewSize` must be set before any zoom command: the first non-zero size triggers the one-time "show the whole board" fit ([CanvasSession.swift:113-120](../../../Sources/GraphiteUI/CanvasSession.swift#L113-L120)).
2. Typed text must be committed before any history step or save: `commitTextEdit` runs inside `save` and `endEditing`, but not inside `undo` ([CanvasSession.swift:286-295](../../../Sources/GraphiteUI/CanvasSession.swift#L286-L295)).
3. `endDrag` must reset `activeDrag`, `previewFrames`, `snapGuides`, `selectionRectangle`, `pendingConnection` together ([CanvasInteraction.swift:171-177](../../../Sources/GraphiteUI/CanvasInteraction.swift#L171-L177)); `adopt(_ snapshot:)` repeats the reset ([CanvasSession.swift:383](../../../Sources/GraphiteUI/CanvasSession.swift#L383)).
4. History steps are byte patches against the open version: any external reload must call `undoManager.removeAllActions()` ([CanvasSession.swift:378-380](../../../Sources/GraphiteUI/CanvasSession.swift#L378-L380)).
5. A save waits for any running save before starting ([CanvasSession.swift:313-317](../../../Sources/GraphiteUI/CanvasSession.swift#L313-L317)); `checkExternalChange` returns early while saving ([CanvasSession.swift:350](../../../Sources/GraphiteUI/CanvasSession.swift#L350)).
6. Group label frames must be drawn before a tap on a label can hit it ([CanvasBoardView.swift:117-121](../../../Sources/GraphiteUI/CanvasBoardView.swift#L117-L121)).

**Verdict.** Over the ~15-property bound by a factor of two. Responsibilities A, B and F are tightly bound by the commit/undo/save rules; C, E, G and H are separable.

**Proposed split.**

| New type | Members moved | Notes |
| --- | --- | --- |
| `CanvasDocument` | A + F: `file`, `changeVersion`, `undoManager`, `undoAvailability`, `textEdit`, `perform`, `registerUndo`, `applyFromHistory`, `adopt(file)`, text-edit functions | Owns the rule "commit typed text before any history step"; exposes `undo()`/`redo()` that commit first |
| `CanvasDocumentPersistence` | B: store, revision, saved state, autosave, conflict, `save`, `checkExternalChange`, `reload`, `saveSeparateCopy` | Talks to `CanvasDocument` through `currentData`, `commitPendingText()`, `replace(with snapshot:)` |
| `CanvasViewportModel` | C: `viewport`, `viewSize`, animation, `detailedNodes`, zoom commands, `reveal` | Animation driven by one injected frame clock, not `Task.sleep` |
| `CanvasSelection` (value) | D: selected node/edge identifiers, `focusedNodeIdentifier`, `hasSelection` | Pure struct with intent methods; pruned by `CanvasDocument` changes |
| `CanvasGesture` (enum) + `CanvasInteractionModel` | E: one enum whose cases carry the preview frames, guides, rectangle and pending connection | Replaces `activeDrag` + 4 fields |
| `CanvasCommands` | G | Builds `CanvasChange` lists from selection and document; no stored state except `nameRequest` |
| `CanvasSnapPreferences` | `snapsToGrid`, `snapsToObjects` | Injected key-value store |
| `CanvasGroupLabelLayout` (pure) | label frame computation now inside the renderer | Called by both the renderer and hit testing; removes `groupLabelFrames` |

### 3.2 `CanvasFile` with its extensions (CanvasFile.swift + CanvasFileEditing.swift + CanvasLinks.swift)

11 stored properties ([CanvasFile.swift:157-172](../../../Sources/GraphiteCore/CanvasFile.swift#L157-L172)); 224 + 405 + 72 code lines across three files.

| Responsibility | Members |
| --- | --- |
| Read model | `bytes`, `root`, `nodes`, `edges`, element-index arrays, unreadable counts, identifier maps; `init(data:)`, `init(validatedBytes:)`, `list(named:in:)`, `distinctIdentifier`, `frame(of:)`, `content(of:)` ([CanvasFile.swift:180-311](../../../Sources/GraphiteCore/CanvasFile.swift#L180-L311)) |
| Lookup | `node(withIdentifier:)`, `edge(withIdentifier:)`, `node(named:)`, `nodeIndex`, `edgeIndex`, `nodeValues`, `edgeValues`, `identifiersInFile` ([CanvasFile.swift:241-265](../../../Sources/GraphiteCore/CanvasFile.swift#L241-L265)) |
| Edit planning | `applying(_ changes:)`, `applying(_ patch:)`, `newIdentifier`, `splices(for:)`, `nodeValue`, `edgeValue`, `elementBytes` ×2, `objectBytes`, `appendingSplices`, `listBytes`, `removalSplices`, `removalRanges`, `reorderingSplices` ([CanvasFileEditing.swift:90-401](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L90-L401)) |
| Link sources for the index and moves | `linkSources`, `replacing` ([CanvasLinks.swift:20-66](../../../Sources/GraphiteCore/CanvasLinks.swift#L20-L66)) |

Ordering rules: splices within one step are sorted ascending and non-overlapping before application ([CanvasFileEditing.swift:97-99](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L97-L99), [CanvasFileEditing.swift:60-62](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L60-L62)); every multi-change edit re-parses after each change so the next change's ranges refer to fresh bytes ([CanvasFileEditing.swift:96-104](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L96-L104)); inverse steps are prepended so undo runs in reverse order ([CanvasFileEditing.swift:103](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L103)).

**Verdict.** Sound. One type, one aggregate (the file's bytes), split across files by responsibility. The only structural issue is the 84-code-line `splices(for:)` switch and the JSON Canvas vocabulary being spelled independently in reading, writing and link extraction ([OCP-CANVAS-02](#ocp-canvas-02-the-json-canvas-vocabulary-is-spelled-in-three-independent-places)). Proposed change: keep the type; extract one `CanvasSchema` declaration of type names and keys; split `splices(for:)` into one private function per change case.

### 3.3 `GraphCanvas` and `GraphCanvasModel` (GraphCanvas.swift, 325 code lines)

`GraphCanvasModel` has 9 stored properties ([GraphCanvas.swift:38-47](../../../Sources/GraphiteUI/GraphCanvas.swift#L38-L47)); `GraphCanvas` has 9 inputs and 9 `@State`/`@Environment` properties ([GraphCanvas.swift:131-155](../../../Sources/GraphiteUI/GraphCanvas.swift#L131-L155)).

| Responsibility | Where |
| --- | --- |
| Simulation scheduling (actor, run loop with 16 ms sleeps, pin/unpin/forces as unowned tasks) | [GraphCanvas.swift:6-126](../../../Sources/GraphiteUI/GraphCanvas.swift#L6-L126) |
| Viewport math (`screenPoint`, `graphPosition`, zoom around fingers, scale limits 0.05…6) | [GraphCanvas.swift:206-212](../../../Sources/GraphiteUI/GraphCanvas.swift#L206-L212), [328-344](../../../Sources/GraphiteUI/GraphCanvas.swift#L328-L344) |
| Fitting policy with label-width estimates | [GraphCanvas.swift:347-383](../../../Sources/GraphiteUI/GraphCanvas.swift#L347-L383) |
| Drawing | [GraphCanvas.swift:219-286](../../../Sources/GraphiteUI/GraphCanvas.swift#L219-L286) |
| Hit testing and gestures | [GraphCanvas.swift:290-326](../../../Sources/GraphiteUI/GraphCanvas.swift#L290-L326) |

Ordering rules: `load` cancels the previous run before replacing the simulator ([GraphCanvas.swift:50-51](../../../Sources/GraphiteUI/GraphCanvas.swift#L50-L51)); `pin` and `unpin` rely on unstructured main-actor tasks reaching the actor in creation order ([GraphCanvas.swift:78-87](../../../Sources/GraphiteUI/GraphCanvas.swift#L78-L87)); positions are kept on disappear ([GraphCanvas.swift:191-194](../../../Sources/GraphiteUI/GraphCanvas.swift#L191-L194)).

**Verdict.** Under the size threshold but untestable: the viewport and fit policy live in a `View` as `@State`. Proposed split: `GraphViewport` value type (scale, offset, `screenPoint`, `graphPosition`, `zoom(by:around:)`, `fitting(positions:labels:in:)`) in Core with tests; `GraphCanvasModel` keeps scheduling and owns one serial command stream to the simulator instead of a task per event.

## 4. Findings by principle

### S

#### SRP-CANVAS-01 `CanvasSession` holds 34 stored properties across 8 responsibilities that share mutable fields
- **Severity:** High
- **Evidence:** stored properties at [CanvasSession.swift:67-156](../../../Sources/GraphiteUI/CanvasSession.swift#L67-L156) (34, counted by reading); the 8 responsibilities and their cross-calls are listed in §3.1. History and text editing share `textEdit`: `applyFromHistory` clears it ([CanvasSession.swift:241](../../../Sources/GraphiteUI/CanvasSession.swift#L241)) while only `save` and `endEditing` commit it ([CanvasSession.swift:286-295](../../../Sources/GraphiteUI/CanvasSession.swift#L286-L295), [312](../../../Sources/GraphiteUI/CanvasSession.swift#L312)).
- **Why it matters:** the rule "typed text is committed before any history step" has no single owner, and the gap loses user text ([BUG-CANVAS-01](#bug-canvas-01-undo-while-typing-in-a-text-card-discards-the-typed-text-and-undoes-the-step-before-it)). Viewport animation, snapping preferences and gesture state are reachable only through the whole session, so a test of zoom-to-fit must construct a store, a snapshot and an undo manager ([CanvasSessionTests.swift:42-47](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L42-L47)).
- **Fix direction:** split as in §3.1: `CanvasDocument` owns file, history and the text being typed (and commits it before undo/redo); persistence, viewport, selection, gesture state and commands become separate types composed by a thin session.

#### SRP-CANVAS-02 The board's renderer writes hit-testing state into the session while drawing
- **Severity:** Medium
- **Evidence:** inside the `Canvas` closure, `session.groupLabelFrames = labelFrames` ([CanvasBoardView.swift:117-121](../../../Sources/GraphiteUI/CanvasBoardView.swift#L117-L121)); the label layout is computed only in `draw(_:in:viewport:backgroundImages:)` ([CanvasBoardView.swift:159-168](../../../Sources/GraphiteUI/CanvasBoardView.swift#L159-L168)); hit testing reads it ([CanvasInteraction.swift:69-71](../../../Sources/GraphiteUI/CanvasInteraction.swift#L69-L71), [CanvasGeometry.swift:303](../../../Sources/GraphiteCore/CanvasGeometry.swift#L303)); the property is documented as "Set by the view that draws the labels" ([CanvasSession.swift:125-127](../../../Sources/GraphiteUI/CanvasSession.swift#L125-L127)).
- **Why it matters:** a tap on a group label hits only after a frame has been rendered at the current zoom; the session tests cannot hit a label without a renderer, and the label geometry (font size from `@ScaledMetric`, padding `textSize * 0.35`, offset `4 * viewport.scale`) exists only in drawing code.
- **Fix direction:** a pure `CanvasGroupLabelLayout` function (label text size, measured size in, board frame out) used by both the renderer and `CanvasGeometry.target`; the renderer stops writing to the session.

#### SRP-CANVAS-03 Card views perform file I/O and own a rendering service
- **Severity:** Medium
- **Evidence:** 5 places, found by reading `CanvasCardViews.swift`, `CanvasBoardView.swift` and `CanvasPane.swift`: file existence check in a view task ([CanvasCardViews.swift:252-255](../../../Sources/GraphiteUI/CanvasCardViews.swift#L252-L255)); note read with a constructed `AtomicFileWriter()` ([CanvasCardViews.swift:323-334](../../../Sources/GraphiteUI/CanvasCardViews.swift#L323-L334)); image thumbnails through `ReadingImageCache.shared` ([CanvasCardViews.swift:352](../../../Sources/GraphiteUI/CanvasCardViews.swift#L352), [361-368](../../../Sources/GraphiteUI/CanvasCardViews.swift#L361-L368)); group backgrounds decoded by a model declared in the view file ([CanvasBoardView.swift:282-305](../../../Sources/GraphiteUI/CanvasBoardView.swift#L282-L305)); image header reads to size new cards ([CanvasPane.swift:190-215](../../../Sources/GraphiteUI/CanvasPane.swift#L190-L215)); a PDF rendering actor with its own cache declared among views ([CanvasCardViews.swift:415-470](../../../Sources/GraphiteUI/CanvasCardViews.swift#L415-L470)).
- **Why it matters:** none of these paths is testable without hosting SwiftUI views; missing-file, unreadable-note and locked-PDF behaviour has no unit test (no test in `Tests/**` references `CanvasPDFPageRenderer` or `CanvasNoteCardContent`, by grep).
- **Fix direction:** one `CanvasCardContentLoader` (or per-kind loaders) injected through `CanvasCardEnvironment`, returning typed results (`.text`, `.missingSection`, `.unreadable`, `.missingFile`, `.locked`); views render results only. Move `CanvasPDFPageRenderer` into its own file outside the view file.

#### SRP-CANVAS-04 `GraphCanvas` keeps its viewport and fitting policy as view state
- **Severity:** Medium
- **Evidence:** `scale`, `offset`, gesture anchors as `@State` ([GraphCanvas.swift:146-153](../../../Sources/GraphiteUI/GraphCanvas.swift#L146-L153)); fit algorithm with label-width estimate `Double(node.title.count) * 3.2` and a 6-pass shrink loop ([GraphCanvas.swift:347-383](../../../Sources/GraphiteUI/GraphCanvas.swift#L347-L383)); zoom clamping `0.05…6` inline ([GraphCanvas.swift:338](../../../Sources/GraphiteUI/GraphCanvas.swift#L338)).
- **Why it matters:** the canvas board has a tested Core viewport (`CanvasViewport`, [CanvasGeometryTests.swift:151-214](../../../Tests/GraphiteCoreTests/CanvasGeometryTests.swift#L151-L214)); the graph has a second, untested viewport implementation with different limits.
- **Fix direction:** a `GraphViewport` value in Core with `zoom(by:around:)` and `fitting(...)`, tested like `CanvasViewport`; the view holds one value.

#### SRP-CANVAS-05 `CanvasPane` assembles workspace services and runs file flows
- **Severity:** Low
- **Evidence:** builds `CanvasCardEnvironment` from 14 workspace members and closures that start unowned tasks ([CanvasPane.swift:63-91](../../../Sources/GraphiteUI/CanvasPane.swift#L63-L91)); runs "Save a Copy" then refresh then open ([CanvasPane.swift:176-182](../../../Sources/GraphiteUI/CanvasPane.swift#L176-L182)); resolves a file URL and measures the file before adding a card ([CanvasPane.swift:100-103](../../../Sources/GraphiteUI/CanvasPane.swift#L100-L103)).
- **Why it matters:** each UI event performs several model calls in view code, so the Save-a-Copy sequence (save, refresh, open) has no test.
- **Fix direction:** one workspace-level method per event (`saveCanvasCopy(of:)`, `addFileCard(_:to:)`); the pane calls it.

### O

#### OCP-CANVAS-01 File-card kind dispatch is repeated in four places, two with `default:`
- **Severity:** Medium
- **Evidence:** card content by extension and `DocumentKind` with `default:` ([CanvasCardViews.swift:261-285](../../../Sources/GraphiteUI/CanvasCardViews.swift#L261-L285)); new-card size by extension and `DocumentKind` with `default:` ([CanvasPane.swift:190-205](../../../Sources/GraphiteUI/CanvasPane.swift#L190-L205)); spoken label by nested ternaries ([CanvasBoardView.swift:558-559](../../../Sources/GraphiteUI/CanvasBoardView.swift#L558-L559)); picker filter ([CanvasPane.swift:511-516](../../../Sources/GraphiteUI/CanvasPane.swift#L511-L516)). Audio and video are recognised by `MediaFileKind` extension sets in two of them and by `DocumentKind.media` in the picker.
- **Why it matters:** a new embeddable kind (for example `.base` sizing, which falls to the note size today) needs four coordinated edits, and the two `default:` branches compile silently when one is missed.
- **Fix direction:** one `CanvasFileCardKind` enum mapped once from a `VaultPath` (with an explicit `.other`), carrying size, label and content choice; the four sites switch on it exhaustively.

#### OCP-CANVAS-02 The JSON Canvas vocabulary is spelled in three independent places
- **Severity:** Medium
- **Evidence:** type strings `"text"`, `"file"`, `"link"`, `"group"` in reading ([CanvasFile.swift:293-311](../../../Sources/GraphiteCore/CanvasFile.swift#L293-L311)), writing ([CanvasFileEditing.swift:236-253](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L236-L253)) and link extraction with its own `default:` ([CanvasLinks.swift:25-41](../../../Sources/GraphiteCore/CanvasLinks.swift#L25-L41)); key names (`"x"`, `"y"`, `"width"`, `"height"`, `"color"`, `"label"`, `"fromEnd"`, `"toEnd"`, `"file"`, `"background"`, `"text"`) as literals across [CanvasFile.swift:201-307](../../../Sources/GraphiteCore/CanvasFile.swift#L201-L307), [CanvasFileEditing.swift:136-191](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L136-L191) and [CanvasLinks.swift:28-57](../../../Sources/GraphiteCore/CanvasLinks.swift#L28-L57).
- **Why it matters:** the file format is a persisted, shared vocabulary; a typo in one site (for example `"backgroundStyle"`) produces a file Obsidian reads differently, and no compile-time link exists between reader, writer and link extractor.
- **Fix direction:** one `CanvasSchema` declaration (`enum CanvasNodeType: String` with `unknown(raw)` mapping, and a `CanvasKey` enum of member names) used by all three.

#### OCP-CANVAS-03 Graph and map features add their caches and reset lines to `WorkspaceModel`
- **Severity:** Low
- **Evidence:** `graphCache`, `graphPositions`, `isGraphPresented`, `placedNotesCache`, `isMapPresented` stored on the workspace ([WorkspaceModel.swift:145-154](../../../Sources/GraphiteUI/WorkspaceModel.swift#L145-L154)); vault switch resets them by name ([WorkspaceModel.swift:314](../../../Sources/GraphiteUI/WorkspaceModel.swift#L314)); `WorkspaceGraph.swift` and `WorkspaceMap.swift` are workspace extensions.
- **Why it matters:** each core-plugin view grows the application aggregate and the vault-switch coordinator, and the cache keyed only by `indexVersion` races a vault switch ([BUG-CANVAS-06](#bug-canvas-06-a-graph-or-map-from-the-previous-vault-can-be-shown-after-a-vault-switch)).
- **Fix direction:** a `VaultGraphProvider` (graph, positions, placed notes) owned per vault, keyed by index identity and version, opting into vault-switch cleanup by conformance.

### L

#### LSP-CANVAS-01 An unreadable canvas reports zero links instead of a failure
- **Severity:** Medium
- **Evidence:** `if let file = try? CanvasFile(...)` then an empty `NoteSemantics` ([CanvasLinks.swift:74-87](../../../Sources/GraphiteCore/CanvasLinks.swift#L74-L87)); a text card whose links fail to scan contributes none (`(try? NoteLinkScanner.links(in:)) ?? []`, [CanvasLinks.swift:82](../../../Sources/GraphiteCore/CanvasLinks.swift#L82)); the index stores these semantics like a note's ([VaultIndex.swift:278-280](../../../Sources/GraphiteIndex/VaultIndex.swift#L278-L280)).
- **Why it matters:** an empty result is indistinguishable from "no links", so moves skip the canvas without reporting it ([BUG-CANVAS-05](#bug-canvas-05-renaming-a-note-named-by-a-canvas-graphite-cannot-read-leaves-the-canvas-pointing-at-the-old-path-without-a-report)); the Markdown path throws instead (`try MarkdownSemantics.parse`, same line).
- **Fix direction:** return a typed result (`.links([NoteLink])` or `.unreadable(CanvasFileError)`) and let the index record the canvas as unreadable so moves can list it.

#### LSP-CANVAS-02 The Mac and UIKit variants of `CanvasBoardHost` offer different behaviour under one name
- **Severity:** Medium
- **Evidence:** UIKit host: two-finger pan, Command-scroll zoom, pinch, one-finger drag, tap, double tap, long press ([CanvasBoardHost.swift:75-92](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L75-L92)); Mac host: drag, magnify, double tap only ([CanvasBoardHost.swift:205-231](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L205-L231)); `isWriting` is set only under `canImport(UIKit)` ([WorkspaceCanvas.swift:14-17](../../../Sources/GraphiteUI/WorkspaceCanvas.swift#L14-L17), [33-35](../../../Sources/GraphiteUI/WorkspaceCanvas.swift#L33-L35)); the Mac menu still offers "New Canvas" ([GraphiteCommands.swift:68-69](../../../Sources/GraphiteUI/GraphiteCommands.swift#L68-L69)).
- **Why it matters:** read-mode focus and scrolling depend on `tap`, so the Mac variant breaks a session behaviour that the UIKit variant provides ([BUG-CANVAS-03](#bug-canvas-03-on-the-mac-the-content-of-a-text-note-or-base-card-longer-than-its-card-cannot-be-scrolled)); "New Canvas" on the Mac creates `{}` and opens a board with no way to add a card in Graphite.
- **Fix direction:** both hosts translate platform input into the same session calls (`tap`, `doubleTap`, `continueDrag`); the Mac host gains single click and scroll; "New Canvas" is offered only where editing exists, or the Mac gets editing.

#### LSP-CANVAS-03 Duplicate-`id` cards and connections get identities that change when earlier entries are removed
- **Severity:** Low
- **Evidence:** a repeated `id` becomes `id + "\u{1}" + elementIndex` ([CanvasFile.swift:203](../../../Sources/GraphiteCore/CanvasFile.swift#L203), [217](../../../Sources/GraphiteCore/CanvasFile.swift#L217), [278-282](../../../Sources/GraphiteCore/CanvasFile.swift#L278-L282)); the session keeps selection by these identifiers across edits ([CanvasSession.swift:254-255](../../../Sources/GraphiteUI/CanvasSession.swift#L254-L255)).
- **Why it matters:** removing an earlier entry shifts element indexes, so `"x\u{1}2"` can name a different card after the edit; the selection then moves silently to another card. `Identifiable.id` is documented as "Unique among the cards Graphite shows" but not stable across versions ([CanvasFile.swift:99-101](../../../Sources/GraphiteCore/CanvasFile.swift#L99-L101)).
- **Fix direction:** derive the distinct identifier from the occurrence count of the same `id` (second, third) rather than the element index, and state the stability rule in the type.

### I

#### ISP-CANVAS-01 `CanvasPane` and `CanvasFilePicker` take the whole `WorkspaceModel` for about 20 members
- **Severity:** Medium
- **Evidence:** `@Bindable var workspace: WorkspaceModel` ([CanvasPane.swift:11](../../../Sources/GraphiteUI/CanvasPane.swift#L11), [520](../../../Sources/GraphiteUI/CanvasPane.swift#L520)); members used, counted by reading the file: `preferences`, `folderAccess`, `index`, `activateTab`, `follow`, `open(_:)`, `open(_:pdfPageIndex:)`, `baseEmbedContext`, `viewedImageNote`, `viewedImage`, `vaultSettings`, `noteBaseFontSize`, `drawingVersion`, `indexVersion`, `errorMessage`, `refreshDirectory`, `openingLink`, `bookmarks`, `toggleBookmark`, `existingRecentFiles` (20).
- **Why it matters:** any pane test needs a full workspace; the pane can mutate any workspace state (it writes `viewedImageNote`, `viewedImage` and `errorMessage` directly, [CanvasPane.swift:79-80](../../../Sources/GraphiteUI/CanvasPane.swift#L79-L80), [53](../../../Sources/GraphiteUI/CanvasPane.swift#L53)).
- **Fix direction:** the pane receives a `CanvasPaneContext` value (root, index, reading configuration, navigation closures, bookmark state) built by the workspace; the picker receives a search capability.

#### ISP-CANVAS-02 Views write six session fields directly instead of calling intent methods
- **Severity:** Medium
- **Evidence:** `viewport` from gesture handlers ([CanvasBoardHost.swift:110](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L110), [115](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L115), [123](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L123), [218](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L218), [226](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L226)); `selectedNodeIdentifiers`/`selectedEdgeIdentifiers` from an accessibility action ([CanvasBoardView.swift:522](../../../Sources/GraphiteUI/CanvasBoardView.swift#L522)); `nameRequest` ([CanvasPane.swift:271](../../../Sources/GraphiteUI/CanvasPane.swift#L271), [341](../../../Sources/GraphiteUI/CanvasPane.swift#L341), [348](../../../Sources/GraphiteUI/CanvasPane.swift#L348)); `errorMessage` ([CanvasPane.swift:122](../../../Sources/GraphiteUI/CanvasPane.swift#L122)); `groupLabelFrames` ([CanvasBoardView.swift:121](../../../Sources/GraphiteUI/CanvasBoardView.swift#L121)); `isWriting` through bindings ([CanvasPane.swift:45](../../../Sources/GraphiteUI/CanvasPane.swift#L45), [148](../../../Sources/GraphiteUI/CanvasPane.swift#L148)).
- **Why it matters:** the accessibility action selects a card without `endEditing()`, unlike every touch path ([CanvasInteraction.swift:226](../../../Sources/GraphiteUI/CanvasInteraction.swift#L226) after [219](../../../Sources/GraphiteUI/CanvasInteraction.swift#L219)); gesture pans bypass `stopViewportAnimation` except at `.began`; invariants enforced by intent methods are optional for views.
- **Fix direction:** make these `private(set)` and add intent methods (`pan(by:)`, `zoom(by:around:)`, `select(node:)`, `requestName(_:)`, `dismissError()`).

#### ISP-CANVAS-03 The local graph and map panels take a `MarkdownSession` to read its path
- **Severity:** Low
- **Evidence:** `let session: MarkdownSession` used only as `session.path` ([GraphViews.swift:6](../../../Sources/GraphiteUI/GraphViews.swift#L6), [22](../../../Sources/GraphiteUI/GraphViews.swift#L22), [51-52](../../../Sources/GraphiteUI/GraphViews.swift#L51-L52); [MapViews.swift:7](../../../Sources/GraphiteUI/MapViews.swift#L7), [18](../../../Sources/GraphiteUI/MapViews.swift#L18), [41](../../../Sources/GraphiteUI/MapViews.swift#L41)); plus the whole workspace for 4 members (`hasCompletedIndexScan`, `open`, `indexVersion`, `vaultGraph`/`placedNotes`).
- **Why it matters:** the panels cannot show a canvas's or PDF's neighbourhood without a Markdown session, and tests need a note editor to show a graph.
- **Fix direction:** pass `centerPath: VaultPath` and a narrow graph/map source.

#### ISP-CANVAS-04 `CanvasSession` stores the whole `VaultStore` and uses four members
- **Severity:** Low
- **Evidence:** [CanvasSession.swift:68](../../../Sources/GraphiteUI/CanvasSession.swift#L68); uses `save` ([329](../../../Sources/GraphiteUI/CanvasSession.swift#L329), [393](../../../Sources/GraphiteUI/CanvasSession.swift#L393)), `read` ([352](../../../Sources/GraphiteUI/CanvasSession.swift#L352), [368](../../../Sources/GraphiteUI/CanvasSession.swift#L368)), `fileExists` ([365](../../../Sources/GraphiteUI/CanvasSession.swift#L365)), `uniquePath` ([392](../../../Sources/GraphiteUI/CanvasSession.swift#L392)).
- **Why it matters:** the session can move and delete vault files; failure paths (save throws mid-copy) are untested because no narrower seam exists.
- **Fix direction:** a four-member document-file capability shared with `MarkdownSession`, with one contract suite for the real store and a failure-injecting test double.

### D

#### DIP-CANVAS-01 Device preferences are read from `UserDefaults.standard` inside the session and views
- **Severity:** Medium
- **Evidence:** [CanvasSession.swift:151-156](../../../Sources/GraphiteUI/CanvasSession.swift#L151-L156); 11 `@AppStorage` graph settings ([GraphViews.swift:8-14](../../../Sources/GraphiteUI/GraphViews.swift#L8-L14), [66-73](../../../Sources/GraphiteUI/GraphViews.swift#L66-L73)); the tests clear the shared defaults in `setUp`/`tearDown` ([CanvasSessionTests.swift:32-39](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L32-L39)).
- **Why it matters:** tests share process-wide state, and a parallel test run that reads the same keys becomes order-dependent; the keys are persisted with two naming styles (see CC-CANVAS-08).
- **Fix direction:** inject a key-value store into `CanvasSnapPreferences` and a graph-settings model; register the keys in one typed registry.

#### DIP-CANVAS-02 Two process-wide singletons serve card content
- **Severity:** Low
- **Evidence:** `ReadingImageCache.shared` ([CanvasBoardView.swift:299](../../../Sources/GraphiteUI/CanvasBoardView.swift#L299), [CanvasCardViews.swift:352](../../../Sources/GraphiteUI/CanvasCardViews.swift#L352), [363](../../../Sources/GraphiteUI/CanvasCardViews.swift#L363)); `CanvasPDFPageRenderer.shared` ([CanvasCardViews.swift:399](../../../Sources/GraphiteUI/CanvasCardViews.swift#L399), declared [422](../../../Sources/GraphiteUI/CanvasCardViews.swift#L422)). 4 uses, by grep for `\.shared` in the scope.
- **Why it matters:** caches survive vault switches and cannot be cleared or replaced in tests; the PDF cache's 48 MB budget is invisible to any memory coordinator.
- **Fix direction:** both reach cards through `CanvasCardEnvironment`, constructed by the composition root, with cache release by conformance.

#### DIP-CANVAS-03 Core reads plugin settings files directly, as untyped dictionaries
- **Severity:** Low
- **Evidence:** `resourceValues`, `Data(contentsOf:)`, `JSONSerialization` → `[String: Any]` ([PlacedNote.swift:47-51](../../../Sources/GraphiteCore/PlacedNote.swift#L47-L51)); path built by `appendingPathComponent` from the vault root ([PlacedNote.swift:34-40](../../../Sources/GraphiteCore/PlacedNote.swift#L34-L40)); called from a detached task in the UI ([WorkspaceMap.swift:11](../../../Sources/GraphiteUI/WorkspaceMap.swift#L11)).
- **Why it matters:** the read bypasses `VaultStore`'s path validation and coordination; the policy (which keys, in which order) cannot be tested without a file system ([PlacedNotePropertyNamesTests.swift:24-45](../../../Tests/GraphiteCoreTests/PlacedNotePropertyNamesTests.swift#L24-L45) writes files).
- **Fix direction:** split into `propertyNames(geocodingSettings: Data?, mapViewSettings: Data?)` (pure, decoding into small `Decodable` structs) and a store read at the boundary.

#### DIP-CANVAS-04 Timing uses the real clock and real sleeps in session logic
- **Severity:** Low
- **Evidence:** `ContinuousClock()` and an 8 ms sleep loop for animation ([CanvasSession.swift:418-435](../../../Sources/GraphiteUI/CanvasSession.swift#L418-L435)); autosave sleep ([CanvasSession.swift:301-305](../../../Sources/GraphiteUI/CanvasSession.swift#L301-L305)); the hosted tests wait with real sleeps of 100–600 ms ([CanvasTests.swift:49](../../../App/Tests/CanvasTests.swift#L49), [58](../../../App/Tests/CanvasTests.swift#L58), [135](../../../App/Tests/CanvasTests.swift#L135)).
- **Why it matters:** autosave timing and animation end states are untestable without waiting in real time.
- **Fix direction:** inject one clock (and a frame source for animation) into the session.

### Clean code

#### CC-CANVAS-01 Drag state is one enum plus four loose fields that must be reset together
- **Severity:** Medium
- **Evidence:** `CanvasDrag.connecting` carries no data and documents "its state is `CanvasSession.pendingConnection`" ([CanvasInteraction.swift:12-13](../../../Sources/GraphiteUI/CanvasInteraction.swift#L12-L13)); `previewFrames`, `snapGuides`, `selectionRectangle`, `pendingConnection` are separate stored properties ([CanvasSession.swift:138-145](../../../Sources/GraphiteUI/CanvasSession.swift#L138-L145)); `endDrag` resets all five in a `defer` ([CanvasInteraction.swift:171-177](../../../Sources/GraphiteUI/CanvasInteraction.swift#L171-L177)) and `adopt(_ snapshot:)` repeats it ([CanvasSession.swift:383](../../../Sources/GraphiteUI/CanvasSession.swift#L383)); views infer "dragging" from three of them ([CanvasPane.swift:294](../../../Sources/GraphiteUI/CanvasPane.swift#L294)); `selecting(baseSelection:)` is always created with `[]` ([CanvasInteraction.swift:126](../../../Sources/GraphiteUI/CanvasInteraction.swift#L126)), so its documented "adding to `baseSelection`" never happens.
- **Why it matters:** a new reset path that forgets one field leaves a ghost selection rectangle or preview frame; the dead parameter suggests Shift-drag extension exists when it does not.
- **Fix direction:** one `CanvasGesture` enum whose cases carry their own preview, guides, rectangle and pending connection; derived "is dragging" from the enum; remove or implement `baseSelection`.

#### CC-CANVAS-02 Sleep-driven loops and unowned tasks
- **Severity:** Medium
- **Evidence:** 3 sleep-driven loops: viewport animation 8 ms ([CanvasSession.swift:422-433](../../../Sources/GraphiteUI/CanvasSession.swift#L422-L433)), graph stepping 16 ms ([GraphCanvas.swift:113-123](../../../Sources/GraphiteUI/GraphCanvas.swift#L113-L123)), file-picker debounce 150 ms ([CanvasPane.swift:566](../../../Sources/GraphiteUI/CanvasPane.swift#L566)). Unowned `Task {}` per gesture event in the graph model ([GraphCanvas.swift:78](../../../Sources/GraphiteUI/GraphCanvas.swift#L78), [86](../../../Sources/GraphiteUI/GraphCanvas.swift#L86), [91](../../../Sources/GraphiteUI/GraphCanvas.swift#L91)) and in 8 pane actions ([CanvasPane.swift:53](../../../Sources/GraphiteUI/CanvasPane.swift#L53), [56](../../../Sources/GraphiteUI/CanvasPane.swift#L56), [70](../../../Sources/GraphiteUI/CanvasPane.swift#L70), [75](../../../Sources/GraphiteUI/CanvasPane.swift#L75), [97](../../../Sources/GraphiteUI/CanvasPane.swift#L97), [113](../../../Sources/GraphiteUI/CanvasPane.swift#L113), [163](../../../Sources/GraphiteUI/CanvasPane.swift#L163), [168](../../../Sources/GraphiteUI/CanvasPane.swift#L168)). Total `Task {`/`Task.detached` in scope: 23 (reconnaissance count, confirmed by grep).
- **Why it matters:** `pin` and `unpin` ordering relies on unstructured tasks reaching the actor in creation order; a dropped `unpin` leaves a node pinned. Animations at 125 Hz rebuild the observable `viewport` independent of the display's refresh.
- **Fix direction:** an `AsyncStream` command queue into `GraphSimulator` owned by the model; a display-link frame source for animations; a shared debounce primitive for search.

#### CC-CANVAS-03 Core types carry English user text, and tests assert on it
- **Severity:** Medium
- **Evidence:** colour names "Red" … "Purple", "Custom color …" ([CanvasFile.swift:51-64](../../../Sources/GraphiteCore/CanvasFile.swift#L51-L64)); 11 error messages in `CanvasFileError.errorDescription` ([CanvasJSON.swift:22-38](../../../Sources/GraphiteCore/CanvasJSON.swift#L22-L38)); `CanvasFileError.invalidJSON` carries an English `reason` string built in the parser ([CanvasJSON.swift:119-121](../../../Sources/GraphiteCore/CanvasJSON.swift#L119-L121)); the test checks `localizedDescription.contains("damaged")` and `"left the file as it is"` ([CanvasSessionTests.swift:395-398](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L395-L398)).
- **Why it matters:** wording changes break tests; the strings cannot be localised; the parser's failure reason is not a typed value.
- **Fix direction:** `CanvasColor` exposes facts (`presetNumber`); a UI presenter names colours and errors; `invalidJSON` carries a typed `CanvasJSONFailure` case; tests assert on cases.

#### CC-CANVAS-04 Ten functions exceed 40 code lines
- **Severity:** Low
- **Evidence:** reconnaissance list, checked by reading: `CanvasFile.splices(for:)` 84 ([CanvasFileEditing.swift:131-218](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L131-L218)), `CanvasSelectionLayer.body` 65 ([CanvasBoardView.swift:374-438](../../../Sources/GraphiteUI/CanvasBoardView.swift#L374-L438)), `CanvasSelectionBar.body` 56 ([CanvasPane.swift:316-371](../../../Sources/GraphiteUI/CanvasPane.swift#L316-L371)), `drawEdges` 49 ([CanvasBoardView.swift:200-250](../../../Sources/GraphiteUI/CanvasBoardView.swift#L200-L250)), `CanvasFilePicker.body` 47 ([CanvasPane.swift:529-575](../../../Sources/GraphiteUI/CanvasPane.swift#L529-L575)), `CanvasFile.init(validatedBytes:)` 47 ([CanvasFile.swift:186-237](../../../Sources/GraphiteCore/CanvasFile.swift#L186-L237)), `VaultGraphScreen.body` 46 ([GraphViews.swift:89-134](../../../Sources/GraphiteUI/GraphViews.swift#L89-L134)), `GraphCanvas.body` 43 ([GraphCanvas.swift:159-202](../../../Sources/GraphiteUI/GraphCanvas.swift#L159-L202)), `beginDrag` 43 ([CanvasInteraction.swift:84-127](../../../Sources/GraphiteUI/CanvasInteraction.swift#L84-L127)), `VaultMapScreen.body` 41 ([MapViews.swift:70-110](../../../Sources/GraphiteUI/MapViews.swift#L70-L110)).
- **Why it matters:** `splices(for:)` mixes 12 change kinds at one level; `CanvasSelectionLayer.body` draws six independent overlays.
- **Fix direction:** one function per change kind and per overlay; split by responsibility, not size.

#### CC-CANVAS-05 Literal sizes, durations and thresholds in drawing, interaction and layout
- **Severity:** Low
- **Evidence (counted by reading, not exhaustive):** grid dot spacing floor 18 and cap 20,000 dots ([CanvasBoardView.swift:133](../../../Sources/GraphiteUI/CanvasBoardView.swift#L133), [137](../../../Sources/GraphiteUI/CanvasBoardView.swift#L137)); group culling margins −40/−60 ([118](../../../Sources/GraphiteUI/CanvasBoardView.swift#L118)); label width 320 ([241](../../../Sources/GraphiteUI/CanvasBoardView.swift#L241)); tile minimum 24 ([185](../../../Sources/GraphiteUI/CanvasBoardView.swift#L185)); handle size 12 ([452](../../../Sources/GraphiteUI/CanvasBoardView.swift#L452)); animation 260 ms ([CanvasSession.swift:421](../../../Sources/GraphiteUI/CanvasSession.swift#L421)); reveal margin 16 ([474](../../../Sources/GraphiteUI/CanvasSession.swift#L474)); new-card sizes 400×120 and 400×520 outside `NewCardSize` ([CanvasPane.swift:192](../../../Sources/GraphiteUI/CanvasPane.swift#L192), [201](../../../Sources/GraphiteUI/CanvasPane.swift#L201)); graph scale limits 0.05/6/2.2, label metrics 26 and 3.2, touch reach 22 ([GraphCanvas.swift:296](../../../Sources/GraphiteUI/GraphCanvas.swift#L296), [338](../../../Sources/GraphiteUI/GraphCanvas.swift#L338), [357-362](../../../Sources/GraphiteUI/GraphCanvas.swift#L357-L362)); maximum snap candidates 400 as a computed `static var` ([CanvasInteraction.swift:208](../../../Sources/GraphiteUI/CanvasInteraction.swift#L208)).
- **Why it matters:** values that must agree (handle size 12 drawn vs reach 22 hit; `CanvasSession.minimumDetailScale / 2` reused for straight edges, [CanvasBoardView.swift:207](../../../Sources/GraphiteUI/CanvasBoardView.swift#L207)) have no shared name.
- **Fix direction:** named constants with units beside `TouchMetrics` and `NewCardSize`, which already show the right pattern ([CanvasInteraction.swift:23-43](../../../Sources/GraphiteUI/CanvasInteraction.swift#L23-L43)).

#### CC-CANVAS-06 Duplicated code and duplicated facts
- **Severity:** Low
- **Evidence:** board anchoring (constant 4096 and the anchor formula) in two layers ([CanvasBoardView.swift:320-331](../../../Sources/GraphiteUI/CanvasBoardView.swift#L320-L331), [469-477](../../../Sources/GraphiteUI/CanvasBoardView.swift#L469-L477)); Bézier path construction three times ([CanvasBoardView.swift:214-217](../../../Sources/GraphiteUI/CanvasBoardView.swift#L214-L217), [392-395](../../../Sources/GraphiteUI/CanvasBoardView.swift#L392-L395), [428-431](../../../Sources/GraphiteUI/CanvasBoardView.swift#L428-L431)); the save-waiting loop copied from `MarkdownSession` ([CanvasSession.swift:313-317](../../../Sources/GraphiteUI/CanvasSession.swift#L313-L317), [MarkdownSession.swift:145](../../../Sources/GraphiteUI/MarkdownSession.swift#L145)); the `" Graphite edits"` copy suffix in 4 places ([CanvasSession.swift:392](../../../Sources/GraphiteUI/CanvasSession.swift#L392), [MarkdownSession.swift:227](../../../Sources/GraphiteUI/MarkdownSession.swift#L227), [WorkspaceFileManagement.swift:218](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L218), [PDFSession.swift:516](../../../Sources/GraphiteUI/PDFSession.swift#L516)); `CanvasPalette.color` and the colour chooser rebuild sRGB colours the same way ([CanvasBoardView.swift:21-22](../../../Sources/GraphiteUI/CanvasBoardView.swift#L21-L22), [CanvasPane.swift:436](../../../Sources/GraphiteUI/CanvasPane.swift#L436)).
- **Why it matters:** the save-serialisation rule and the copy-naming rule are each maintained in two or more sessions; a fix to one leaves the other.
- **Fix direction:** a shared `SerialSave` primitive for document sessions; one `ConflictCopyNaming` fact; a `Path(route:viewport:)` helper; one anchoring helper.

#### CC-CANVAS-07 Errors swallowed without a stated reason
- **Severity:** Low
- **Evidence:** 21 `try?` in scope (reconnaissance count, confirmed by grep). Without a same-line reason: unreadable group backgrounds skipped ([CanvasBoardView.swift:298-299](../../../Sources/GraphiteUI/CanvasBoardView.swift#L298-L299)); unreadable plugin settings ignored ([PlacedNote.swift:48-50](../../../Sources/GraphiteCore/PlacedNote.swift#L48-L50)); canvas link failures ([CanvasLinks.swift:76](../../../Sources/GraphiteCore/CanvasLinks.swift#L76), [82](../../../Sources/GraphiteCore/CanvasLinks.swift#L82)); "Save Now" ([CanvasPane.swift:163](../../../Sources/GraphiteUI/CanvasPane.swift#L163)) relies on `save` having set `errorMessage`, which it does not for the early conflict throw ([CanvasSession.swift:326](../../../Sources/GraphiteUI/CanvasSession.swift#L326)) (the conflict banner is already showing then). With a stated reason: autosave ([CanvasSession.swift:303-304](../../../Sources/GraphiteUI/CanvasSession.swift#L303-L304)), card Markdown builds ([CanvasCardViews.swift:183-186](../../../Sources/GraphiteUI/CanvasCardViews.swift#L183-L186)).
- **Why it matters:** a renamed or missing group background shows nothing and says nothing; a broken plugin setting silently changes which notes are on the map.
- **Fix direction:** typed outcomes or a same-line comment for each swallow; surface background and settings failures as notices.

#### CC-CANVAS-08 Naming and persisted-key inconsistencies
- **Severity:** Low
- **Evidence:** canvas keys `GraphiteCanvasSnapsToGrid`/`GraphiteCanvasSnapsToObjects` ([CanvasSession.swift:29-32](../../../Sources/GraphiteUI/CanvasSession.swift#L29-L32)) versus graph keys without prefix such as `graphShowsTags` ([WorkspaceGraph.swift:39-55](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L39-L55)); `selectedNodeIDs` beside `selectedNodeIdentifiers` ([CanvasInteraction.swift:321](../../../Sources/GraphiteUI/CanvasInteraction.swift#L321)); `CanvasCardRenderCache` documents "let go of the builds used longest ago" but evicts by insertion order because lookups never refresh age ([CanvasCardViews.swift:22-37](../../../Sources/GraphiteUI/CanvasCardViews.swift#L22-L37)); `readingPositions` is a getter that writes a cache ([CanvasSession.swift:203-208](../../../Sources/GraphiteUI/CanvasSession.swift#L203-L208)).
- **Why it matters:** two key styles invite a third; the cache comment describes a policy the code does not have.
- **Fix direction:** one key registry with one prefix rule; one name per concept; fix the comment or make eviction least-recently-used.

#### CC-CANVAS-09 Whole-collection work on every frame or update
- **Severity:** Low
- **Evidence:** `updateDetailedNodes` filters every node on every viewport change ([CanvasSession.swift:109-111](../../../Sources/GraphiteUI/CanvasSession.swift#L109-L111), [484-505](../../../Sources/GraphiteUI/CanvasSession.swift#L484-L505)); every tap computes routes for every connection ([CanvasInteraction.swift:66-72](../../../Sources/GraphiteUI/CanvasInteraction.swift#L66-L72)); the graph re-fits on every position update while following ([GraphCanvas.swift:175-177](../../../Sources/GraphiteUI/GraphCanvas.swift#L175-L177)); the graph exposes one accessibility button per node with no cap ([GraphCanvas.swift:197-201](../../../Sources/GraphiteUI/GraphCanvas.swift#L197-L201)); `LocalMapPanel` computes the neighbourhood inside `body` ([MapViews.swift:15-24](../../../Sources/GraphiteUI/MapViews.swift#L15-L24)).
- **Why it matters:** cost grows with the whole board or vault (50,000 cards, 100,000 connections allowed) during pans, against the "bounded results" rule; the canvas accessibility layer caps at 1,000 elements, the graph does not.
- **Fix direction:** a spatial index for nodes and routes in Core; cap graph accessibility children as the canvas does.

## 5. Defects and latent bugs

#### BUG-CANVAS-01 Undo while typing in a text card discards the typed text and undoes the step before it
- **Trigger:** in Write, the person double-taps an existing text card, types, and within 0.9 s of the last keystroke taps the toolbar's Undo (or the control row's Undo), with any earlier step in the canvas history (for example a moved card).
- **Path:**
  1. Undo is shown while writing ([CanvasPane.swift:147](../../../Sources/GraphiteUI/CanvasPane.swift#L147), [46](../../../Sources/GraphiteUI/CanvasPane.swift#L46)) and calls `availability.undo()` ([UndoRedoButtons.swift:21](../../../Sources/GraphiteUI/UndoRedoButtons.swift#L21)) → `followedUndoManager.undo()` ([UndoAvailability.swift:52-55](../../../Sources/GraphiteUI/UndoAvailability.swift#L52-L55)), which follows the session's history ([CanvasSession.swift:163](../../../Sources/GraphiteUI/CanvasSession.swift#L163)).
  2. Typed text lives only in `textEdit` until a commit: `updateTextEdit` stores it and schedules autosave after 900 ms ([CanvasSession.swift:279-283](../../../Sources/GraphiteUI/CanvasSession.swift#L279-L283), [58](../../../Sources/GraphiteUI/CanvasSession.swift#L58)); nothing on the undo path commits it.
  3. The registered undo runs `applyFromHistory`, which sets `textEdit = nil` and applies the previous step's inverse ([CanvasSession.swift:238-244](../../../Sources/GraphiteUI/CanvasSession.swift#L238-L244)).
  4. The pending autosave then runs `save()` → `commitTextEdit()`, whose guard finds no `textEdit` ([CanvasSession.swift:286-288](../../../Sources/GraphiteUI/CanvasSession.swift#L286-L288)); the editor view disappears because `isEdited` is false ([CanvasCardViews.swift:86-90](../../../Sources/GraphiteUI/CanvasCardViews.swift#L86-L90)).
- **Effect:** the text typed since the last pause is lost with no way back (Redo re-applies only the earlier step), and an unrelated earlier change (a move, a colour) is undone instead.
- **Platforms / reach:** iPad and iPhone (editing exists only under UIKit), normal path.
- **Confidence:** Traced.

#### BUG-CANVAS-02 Edits made to an open canvas while it or its folder moves are lost
- **Trigger:** the person renames or moves a canvas (or a folder containing it) that is open in a tab, and edits the canvas (moves a card, types in a card) while the move runs.
- **Path:**
  1. `completeMove` saves open documents, then awaits the move and its link rewrites ([WorkspaceFileManagement.swift:141-143](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L141-L143)); the editors stay usable during that await, which the code acknowledges for notes ("every keystroke made during the move is kept", [WorkspaceFileManagement.swift:144-146](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L144-L146)).
  2. Edits made meanwhile are collected for Markdown sessions only ([WorkspaceFileManagement.swift:194-199](../../../Sources/GraphiteUI/WorkspaceFileManagement.swift#L194-L199)).
  3. `followMoveInNavigation` unloads every tab inside the moved path ([WorkspaceModel.swift:1201-1202](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1201-L1202)), which sets `canvasSession = nil` ([WorkspaceTabs.swift:40-42](../../../Sources/GraphiteUI/WorkspaceTabs.swift#L40-L42)).
  4. The session's pending autosave holds it weakly and ends without saving ([CanvasSession.swift:301-305](../../../Sources/GraphiteUI/CanvasSession.swift#L301-L305)).
- **Effect:** the canvas reopens from its new place without the edits made during the move; nothing reports the loss.
- **Platforms / reach:** iPad and iPhone (editing); normal rename/move path, during the move's duration (longer for folder moves with many link rewrites).
- **Confidence:** Traced.

#### BUG-CANVAS-03 On the Mac, the content of a text, note or base card longer than its card cannot be scrolled
- **Trigger:** on the Mac, the person opens a canvas whose text card, note card or base card holds more than fits, and tries to scroll inside it.
- **Path:**
  1. The Mac host registers drag, magnify and double tap only, no single tap ([CanvasBoardHost.swift:205-231](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L205-L231)).
  2. `focusedNodeIdentifier` is set only by `tap` ([CanvasInteraction.swift:220-222](../../../Sources/GraphiteUI/CanvasInteraction.swift#L220-L222)); a grep for `focusedNodeIdentifier =` finds no other writer except resets ([CanvasSession.swift:90](../../../Sources/GraphiteUI/CanvasSession.swift#L90), [256](../../../Sources/GraphiteUI/CanvasSession.swift#L256)).
  3. Text cards disable scrolling unless focused ([CanvasCardViews.swift:106-109](../../../Sources/GraphiteUI/CanvasCardViews.swift#L106-L109)); file cards pass `isScrollable: isFocused && !isWriting` ([CanvasCardViews.swift:92](../../../Sources/GraphiteUI/CanvasCardViews.swift#L92)) to note and base contents, which disable scrolling ([CanvasCardViews.swift:313](../../../Sources/GraphiteUI/CanvasCardViews.swift#L313), [280](../../../Sources/GraphiteUI/CanvasCardViews.swift#L280)).
- **Effect:** the Mac shows only the top of each long card; the rest is unreachable on the board (the note can still be opened from the card's title).
- **Platforms / reach:** Mac, normal path.
- **Confidence:** Traced.

#### BUG-CANVAS-04 A card resized or grouped beyond 1,000,000 pixels disappears from the board after the edit
- **Trigger:** the person resizes a card past 1,000,000 board pixels (possible at the 0.01 minimum zoom, where 1 view point is 100 pixels), or groups selected cards whose bounds span more than that (cards may sit anywhere within ±10,000,000).
- **Path:**
  1. Resizing has no upper bound ([CanvasGeometry.swift:356-384](../../../Sources/GraphiteCore/CanvasGeometry.swift#L356-L384)); a new group takes the union of the selection plus padding ([CanvasInteraction.swift:447-451](../../../Sources/GraphiteUI/CanvasInteraction.swift#L447-L451)).
  2. The writer clamps sizes to ±10,000,000, not to the side limit ([CanvasJSON.swift:366-369](../../../Sources/GraphiteCore/CanvasJSON.swift#L366-L369), used by [CanvasFileEditing.swift:138-139](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L138-L139) and [255](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L255)).
  3. The re-read after the edit rejects sides over `maximumSideLength = 1_000_000` ([CanvasFile.swift:155](../../../Sources/GraphiteCore/CanvasFile.swift#L155), [289](../../../Sources/GraphiteCore/CanvasFile.swift#L289)), so the card becomes an unreadable entry ([CanvasFile.swift:232](../../../Sources/GraphiteCore/CanvasFile.swift#L232)) and is dropped from the selection ([CanvasSession.swift:254](../../../Sources/GraphiteUI/CanvasSession.swift#L254)).
- **Effect:** the card vanishes from the board, the banner says "1 card in this file cannot be shown" ([CanvasPane.swift:126-127](../../../Sources/GraphiteUI/CanvasPane.swift#L126-L127)); for a new group, the rename alert that follows targets a card that is not shown and reports "The card or connection is no longer in this canvas" ([CanvasInteraction.swift:460](../../../Sources/GraphiteUI/CanvasInteraction.swift#L460), [CanvasJSON.swift:35](../../../Sources/GraphiteCore/CanvasJSON.swift#L35)). Undo restores it.
- **Platforms / reach:** iPad and iPhone (editing); edge case of very large boards.
- **Confidence:** Traced.

#### BUG-CANVAS-05 Renaming a note named by a canvas Graphite cannot read leaves the canvas pointing at the old path without a report
- **Trigger:** a canvas under 8 MB that Graphite refuses (more than 50,000 cards or 100,000 connections, nesting deeper than 64, more than 2,000,000 values) names a note in a file card; the person renames the note in Graphite.
- **Path:**
  1. The index reads the canvas's text and asks `CanvasLinks.semantics`, which returns no links when `CanvasFile` throws ([VaultIndex.swift:278-280](../../../Sources/GraphiteIndex/VaultIndex.swift#L278-L280), [CanvasLinks.swift:74-87](../../../Sources/GraphiteCore/CanvasLinks.swift#L74-L87)).
  2. The move plan collects rewrite sources from the index's backlinks ([VaultFileOperations.swift:88-94](../../../Sources/GraphiteIndex/VaultFileOperations.swift#L88-L94)), so the canvas is not a source and is not listed in `notesNotUpdated`.
- **Effect:** after the rename, the canvas (readable in Obsidian) has a file card naming a path that no longer exists, and Graphite's move report says nothing about it.
- **Platforms / reach:** all platforms; only canvases beyond Graphite's bounds.
- **Confidence:** Partly traced: the step from `NoteSemantics.links` to the rows `index.linkingNotes(to:)` queries was not read in `VaultIndex`.

#### BUG-CANVAS-06 A graph or map from the previous vault can be shown after a vault switch
- **Trigger:** a graph or map query of the old vault is still running when the person switches vaults, and the graph or map view is opened in the new vault before its first index scan completes.
- **Path:**
  1. `vaultGraph()` captures `index` and `indexVersion`, awaits `index.linkGraph()`, then stores `graphCache = (version, graph)` without checking that the index is still current ([WorkspaceGraph.swift:7-14](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L7-L14)); `placedNotes()` does the same ([WorkspaceMap.swift:8-18](../../../Sources/GraphiteUI/WorkspaceMap.swift#L8-L18)).
  2. The vault switch clears the caches ([WorkspaceModel.swift:314](../../../Sources/GraphiteUI/WorkspaceModel.swift#L314)) but does not change `indexVersion`, which only increments when a scan or refresh completes ([WorkspaceModel.swift:531](../../../Sources/GraphiteUI/WorkspaceModel.swift#L531), [585](../../../Sources/GraphiteUI/WorkspaceModel.swift#L585)).
  3. The old query finishes after the reset and stores the old vault's graph under the current version; the new vault's `vaultGraph()` returns it as a cache hit ([WorkspaceGraph.swift:10](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L10)). Compare `refreshIndex`, which checks `self.index === index` before reporting ([WorkspaceModel.swift:586](../../../Sources/GraphiteUI/WorkspaceModel.swift#L586)).
- **Effect:** the new vault's graph or map shows the previous vault's notes until its first scan completes; tapping a node opens a path that does not exist in the new vault.
- **Platforms / reach:** all platforms; race window during a vault switch.
- **Confidence:** Partly traced: whether the old query completes rather than being cancelled (the panel's `.task` is cancelled when it disappears, and whether `VaultIndex.linkGraph` observes cancellation was not read).

## 6. What to keep

| Design | Evidence | Why it is sound |
| --- | --- | --- |
| The file's bytes are the document; Graphite's model is a view of them | [CanvasFile.swift:144-175](../../../Sources/GraphiteCore/CanvasFile.swift#L144-L175) | Unknown keys, types, number spellings and whitespace survive by construction, not by a serializer remembering them. |
| Position-recording, bounded JSON parser | [CanvasJSON.swift:93-333](../../../Sources/GraphiteCore/CanvasJSON.swift#L93-L333) | Byte ranges for every key and value make splicing possible; depth and value-count limits stop hostile files; duplicate keys follow `JSON.parse` (last wins, [CanvasJSON.swift:84-88](../../../Sources/GraphiteCore/CanvasJSON.swift#L84-L88)). |
| Edits as splices with inverse patches as undo steps | [CanvasFileEditing.swift:56-112](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L56-L112) | Undo is exact by construction and stores only changed bytes; a patch for another version is refused, not misapplied ([CanvasEditingTests.swift:271-275](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L271-L275)). |
| Re-parse after every change before adoption | [CanvasFileEditing.swift:101-102](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L101-L102), [CanvasLinks.swift:63-64](../../../Sources/GraphiteCore/CanvasLinks.swift#L63-L64) | A splice bug can never reach disk as invalid JSON. |
| No-op edits write nothing (`setNumber`/`setString` compare values, not bytes) | [CanvasFileEditing.swift:420-437](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L420-L437) | `10.0`, `-2e1` and `\u0041` stay as written ([CanvasEditingTests.swift:23-40](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L23-L40)). |
| New entries follow the file's own layout; Obsidian's layout for empty files | [CanvasFileEditing.swift:284-345](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L284-L345) | Diffs in Git and sync stay one line per change ([CanvasEditingTests.swift:92-122](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L92-L122)). |
| Removal and reordering keep separators in place | [CanvasFileEditing.swift:349-400](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L349-L400) | Remaining entries keep their own lines; reorder swaps whole entries. |
| Unknown card types are shown, preserved, copyable, never synthesised | [CanvasFile.swift:94-96](../../../Sources/GraphiteCore/CanvasFile.swift#L94-L96), [CanvasFileEditing.swift:250-252](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L250-L252) | Plugin card types survive; Graphite never invents fields it does not understand. |
| Pure Core geometry with tests | [CanvasGeometry.swift:1-399](../../../Sources/GraphiteCore/CanvasGeometry.swift#L1-L399), [CanvasGeometryTests.swift](../../../Tests/GraphiteCoreTests/CanvasGeometryTests.swift) | Hit testing, snapping, routing and reading order are testable without UI. |
| Gestures decided in the session in view coordinates | [CanvasInteraction.swift:18-21](../../../Sources/GraphiteUI/CanvasInteraction.swift#L18-L21) | Finger, Pencil and pointer share one path; `CanvasSessionTests` drives it without a screen. |
| Revision-checked saves; looking never writes; conflict → copy or other version | [CanvasSession.swift:311-403](../../../Sources/GraphiteUI/CanvasSession.swift#L311-L403) | Meets the "never silently overwrite external edits" contract; pinned by [CanvasSessionTests.swift:357-389](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L357-L389). |
| A damaged canvas opens nothing and is never rewritten | [CanvasSession.swift:158-164](../../../Sources/GraphiteUI/CanvasSession.swift#L158-L164), [WorkspaceCanvas.swift:9-13](../../../Sources/GraphiteUI/WorkspaceCanvas.swift#L9-L13) | Unreadable data is left alone. |
| Level-of-detail layers and board anchoring | [CanvasSession.swift:59-64](../../../Sources/GraphiteUI/CanvasSession.swift#L59-L64), [CanvasBoardView.swift:309-334](../../../Sources/GraphiteUI/CanvasBoardView.swift#L309-L334) | A pan changes one transform; float precision stays bounded far from the origin; at most 60 live card views. |
| Accessibility: reading order, colour names, off-screen elements, zoom-to-element | [CanvasGeometry.swift:252-283](../../../Sources/GraphiteCore/CanvasGeometry.swift#L252-L283), [CanvasBoardView.swift:459-538](../../../Sources/GraphiteUI/CanvasBoardView.swift#L459-L538) | Colour is never the only cue; every shown card is reachable. |
| Link cards accept and open only `http`/`https` | [CanvasInteraction.swift:416-431](../../../Sources/GraphiteUI/CanvasInteraction.swift#L416-L431) | `javascript:`, `file:` and app schemes are refused ([CanvasSessionTests.swift:344-353](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L344-L353)). |
| Canvas link targets escape `%` and `#` and start at the vault root | [CanvasLinks.swift:89-96](../../../Sources/GraphiteCore/CanvasLinks.swift#L89-L96) | File cards resolve exactly their file, never a same-named note beside the canvas. |
| `GraphLayout` is deterministic d3 with Barnes–Hut and a tested quadtree | [GraphLayout.swift:73-89](../../../Sources/GraphiteCore/GraphLayout.swift#L73-L89), [LinkGraphTests.swift:89-152](../../../Tests/GraphiteCoreTests/LinkGraphTests.swift) | Same graph → same layout; the approximation matches the exact force at threshold 0. |
| Simulation in an actor; drags go through it | [GraphCanvas.swift:4-33](../../../Sources/GraphiteUI/GraphCanvas.swift#L4-L33) | Layout work stays off the main thread; pins never race a step. |
| MapKit markers restyled only when highlight or accent changes | [NotesMapView.swift:127-136](../../../Sources/GraphiteUI/NotesMapView.swift#L127-L136) | Avoids re-clustering thousands of markers on unrelated updates. |
| Bounded reads of untrusted settings and PDF renders | [PlacedNote.swift:19-20](../../../Sources/GraphiteCore/PlacedNote.swift#L19-L20), [CanvasCardViews.swift:423-443](../../../Sources/GraphiteUI/CanvasCardViews.swift#L423-L443) | Settings over 1 MB are ignored; PDF pages are capped at 3,000 px with a 48 MB cache keyed by modification date. |
| `@unchecked Sendable` with a stated invariant | [CanvasCardViews.swift:407-408](../../../Sources/GraphiteUI/CanvasCardViews.swift#L407-L408) | The only escape in scope names why it is safe (immutable `CGImage`). |

## 7. Blueprint for this area

### Target shape

| Type | Layer | Single responsibility | Seam |
| --- | --- | --- | --- |
| `CanvasFile`, `CanvasJSONParser`, `CanvasJSONWriter`, `CanvasPatch` | Core | Read and edit the file's bytes | none (pure values) |
| `CanvasSchema` (`CanvasNodeType` with `unknown(raw)`, `CanvasKey`) | Core | The format's vocabulary, declared once | none |
| `CanvasGeometry`, `CanvasViewport`, `CanvasGroupLabelLayout` | Core | Pure geometry, including label frames | none |
| `CanvasDocument` | UI model | File + history + text being typed; commits text before any history step | none |
| `CanvasDocumentPersistence` | UI model | Autosave, revision-checked save, conflict, reload, save-a-copy | document-file capability (read, save, exists, unique path), shared with `MarkdownSession`, with one contract suite |
| `CanvasViewportModel` | UI model | Viewport, animation, level of detail | injected clock / frame source |
| `CanvasSelection` (value) | UI model | Selected nodes/edges, focus | none |
| `CanvasGesture` (enum) + `CanvasInteractionModel` | UI model | Gesture state machine with all transient data in its cases | none |
| `CanvasCommands` | UI model | Selection → `CanvasChange` lists | none |
| `CanvasSnapPreferences`, `GraphSettings` | UI model | Device preferences | injected key-value store |
| `CanvasCardContentLoader` | UI service | Existence, note sections, images, PDF pages as typed results | injected via `CanvasCardEnvironment` |
| `CanvasBoardHost` (iOS, Mac) | UI | Translate platform input into the same model calls | none |
| `GraphViewport` | Core | Graph pan/zoom/fit policy | none |
| `VaultGraphProvider` | UI service | Graph, positions and placed notes per vault, keyed by index identity and version | vault-switch cleanup by conformance |

### Ordered steps (each leaves the app building and behaving the same, except where a bug is fixed)

1. Add golden round-trip tests for the invariants below that are not yet pinned (INV-05, INV-09, INV-12, INV-17, INV-21, INV-23).
2. Introduce `CanvasSchema` and replace the type and key literals in `CanvasFile`, `CanvasFileEditing` and `CanvasLinks`; no behaviour change.
3. Move `CanvasColor.name` and `CanvasFileError` messages to a UI presenter; give `invalidJSON` a typed failure; change `CanvasSessionTests.testADamagedCanvasDoesNotOpenAndStaysAsItWas` to assert the case.
4. Fix BUG-CANVAS-01: `undo()`/`redo()` on the canvas commit pending text first (inside the history owner, not in the button).
5. Extract `CanvasGroupLabelLayout`; the renderer and `CanvasGeometry.target` both call it; delete `groupLabelFrames`.
6. Replace `activeDrag` + four fields with `CanvasGesture`; make session fields `private(set)` and add intent methods for viewport, selection, name requests and errors.
7. Split `CanvasSession` into `CanvasDocument`, `CanvasDocumentPersistence`, `CanvasViewportModel`, `CanvasSelection`, `CanvasCommands`, keeping `CanvasSession` as a thin composition so views change gradually.
8. Inject snap and graph preferences; remove `UserDefaults.standard` from tests.
9. Extract `CanvasCardContentLoader` and move `CanvasPDFPageRenderer` into its own file; views stop calling `FileManager`, `AtomicFileWriter` and `.shared`.
10. Introduce `CanvasFileCardKind` and replace the four file-kind dispatches.
11. Fix BUG-CANVAS-02 by giving canvas sessions the same "edits during move" treatment as notes (collect unsaved canvas data before unload, write it to the new path with the pre-move revision or as a copy).
12. Make the Mac host call `tap` (fix BUG-CANVAS-03) and decide the Mac's "New Canvas" offer.
13. Clamp written sides to `maximumSideLength` (fix BUG-CANVAS-04) or refuse the change with a typed error.
14. Return a typed unreadable result from `CanvasLinks` and record unreadable canvases so moves report them (BUG-CANVAS-05).
15. Move graph/map caches into `VaultGraphProvider` keyed by index identity (BUG-CANVAS-06); extract `GraphViewport`; replace per-event tasks with a command stream.

### Behaviour that must be preserved

| ID | Invariant | Test idea |
| --- | --- | --- |
| CANVAS-INV-01 | Opening, panning, zooming, tapping and saving a canvas that was not edited never writes the file ([CanvasSession.swift:318-325](../../../Sources/GraphiteUI/CanvasSession.swift#L318-L325)). | Existing [CanvasSessionTests.swift:72-95](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L72-L95); keep the modification-date assertion. |
| CANVAS-INV-02 | Every edit changes only the bytes of what it names; unknown keys, unknown types, key order, whitespace, CRLF and BOM are preserved. | Existing [CanvasEditingTests.swift:44-80](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L44-L80); add a BOM + CRLF file through every `CanvasChange` case. |
| CANVAS-INV-03 | Applying an edit's undo patch restores the original bytes exactly; redo restores the edit exactly. | Existing helper [CanvasEditingTests.swift:11-19](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L11-L19); property test over random change sequences. |
| CANVAS-INV-04 | An edit whose value is unchanged (however written: `10.0`, `-2e1`, `\u0041`) writes nothing and adds no undo step. | Existing [CanvasEditingTests.swift:23-40](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L23-L40). |
| CANVAS-INV-05 | Positions and sizes are written as whole numbers, rounded half away from zero, clamped to ±10,000,000; non-finite values write 0 ([CanvasJSON.swift:360-369](../../../Sources/GraphiteCore/CanvasJSON.swift#L360-L369)). | Table test of `wholeNumber` at ±0.5, ±1e8, NaN, ∞. |
| CANVAS-INV-06 | New card keys are written in order `id, type, text|file,subpath|url, x, y, width, height, color, label, background, backgroundStyle` on one line without spaces ([CanvasFileEditing.swift:233-258](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L233-L258)). | Golden strings per card kind (existing [CanvasEditingTests.swift:92-122](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L92-L122)). |
| CANVAS-INV-07 | New connection keys are `id, fromNode, fromSide?, fromEnd?, toNode, toSide?, toEnd?, color?, label?`; `fromEnd: none` and `toEnd: arrow` are omitted as defaults ([CanvasFileEditing.swift:260-270](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L260-L270)). | Golden string with all options and with defaults. |
| CANVAS-INV-08 | New identifiers are 16 lowercase hexadecimal digits, unique among all `id`s in the file and those just issued ([CanvasFileEditing.swift:114-127](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L114-L127)). | Existing [CanvasEditingTests.swift:124-141](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L124-L141). |
| CANVAS-INV-09 | An empty or whitespace-only file opens as an empty canvas; the first added card turns it into `{\n\t"nodes":[\n\t\t…\n\t]\n}`; a new canvas file is exactly `{}` ([CanvasFile.swift:177-178](../../../Sources/GraphiteCore/CanvasFile.swift#L177-L178), [CanvasFileEditing.swift:289-302](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L289-L302)). | Existing [CanvasEditingTests.swift:84-90](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L84-L90) and [CanvasTests.swift:209-223](../../../App/Tests/CanvasTests.swift#L209-L223); add whitespace-only input. |
| CANVAS-INV-10 | Colours are written `"1"`…`"6"` or lowercase `#rrggbb`; `#rgb`, `#rgba`, `#rrggbbaa` and numeric `3` are read; anything else is no colour and stays in the file ([CanvasFile.swift:13-49](../../../Sources/GraphiteCore/CanvasFile.swift#L13-L49)). | Existing [CanvasFileTests.swift:87-108](../../../Tests/GraphiteCoreTests/CanvasFileTests.swift); add "stays in the file after an unrelated edit". |
| CANVAS-INV-11 | When a key is written twice, the last occurrence counts for reading and editing. | Existing [CanvasEditingTests.swift:176-179](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L176-L179). |
| CANVAS-INV-12 | Cards sharing an `id` are all shown; connections name the first card with that `id`; a card whose `id` is shared cannot start a connection or be a connection target ([CanvasFile.swift:249-253](../../../Sources/GraphiteCore/CanvasFile.swift#L249-L253), [CanvasInteraction.swift:77](../../../Sources/GraphiteUI/CanvasInteraction.swift#L77), [101-104](../../../Sources/GraphiteUI/CanvasInteraction.swift#L101-L104)). | Session test: connect from and to a duplicate-`id` card; assert no connection. |
| CANVAS-INV-13 | Removing a card removes connections whose `fromNode`/`toNode` no remaining card has; entries Graphite cannot show stay ([CanvasFileEditing.swift:195-212](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L195-L212)). | Existing [CanvasEditingTests.swift:183-207](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L183-L207). |
| CANVAS-INV-14 | The last card in `nodes` is drawn on top; Bring to Front/Send to Back move whole entries and keep separators ([CanvasFileEditing.swift:383-400](../../../Sources/GraphiteCore/CanvasFileEditing.swift#L383-L400)). | Existing [CanvasEditingTests.swift:211-227](../../../Tests/GraphiteCoreTests/CanvasEditingTests.swift#L211-L227). |
| CANVAS-INV-15 | Untrusted bounds: 16 MiB, nesting 64, 2,000,000 values, 50,000 cards, 100,000 connections, coordinates within ±10⁷, sides within (0, 10⁶] ([CanvasFile.swift:149-155](../../../Sources/GraphiteCore/CanvasFile.swift#L149-L155), [CanvasJSON.swift:96-97](../../../Sources/GraphiteCore/CanvasJSON.swift#L96-L97)). | Existing [CanvasFileTests.swift:206-220](../../../Tests/GraphiteCoreTests/CanvasFileTests.swift); add a side-limit round trip after BUG-CANVAS-04's fix. |
| CANVAS-INV-16 | A damaged canvas throws, opens no session and is never written. | Existing [CanvasSessionTests.swift:391-400](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L391-L400), asserting the error case instead of text. |
| CANVAS-INV-17 | Saves are revision-checked; a conflict blocks saving until "Save a Copy" (named `<stem> Graphite edits.canvas`, unique) or "Use Other Version"; history is cleared on reload ([CanvasSession.swift:326-403](../../../Sources/GraphiteUI/CanvasSession.swift#L326-L403)). | Existing [CanvasSessionTests.swift:357-380](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L357-L380); add a second copy to pin the unique-name suffix. |
| CANVAS-INV-18 | Autosave fires 900 ms after the last edit or keystroke; each pause in typing commits one "Edit Text" step ([CanvasSession.swift:58](../../../Sources/GraphiteUI/CanvasSession.swift#L58), [299-305](../../../Sources/GraphiteUI/CanvasSession.swift#L299-L305)). | With an injected clock: advance 899 ms (no write), 1 ms (one write). |
| CANVAS-INV-19 | Canvas link sources: file cards and group backgrounds as `/`-rooted Markdown targets with `%`→`%25`, `#`→`%23`; text-card Markdown links; unreadable cards included ([CanvasLinks.swift:23-96](../../../Sources/GraphiteCore/CanvasLinks.swift#L23-L96)). | Existing [CanvasLinkTests.swift:57-140](../../../Tests/GraphiteIndexTests/CanvasLinkTests.swift); add `%` and `#` in a path. |
| CANVAS-INV-20 | A rename rewrites only the named values of a canvas; a canvas it does not mention stays byte for byte; an open canvas without edits takes the new bytes without reopening. | Existing [CanvasLinkTests.swift:88-140](../../../Tests/GraphiteIndexTests/CanvasLinkTests.swift), [CanvasTests.swift:181-199](../../../App/Tests/CanvasTests.swift#L181-L199). |
| CANVAS-INV-21 | Device preference keys and defaults: `GraphiteCanvasSnapsToGrid` = true, `GraphiteCanvasSnapsToObjects` = true; graph keys `graphShowsTags`, `graphShowsAttachments`, `graphShowsExistingFilesOnly`, `graphShowsOrphans`, `graphShowsArrows`, `graphLinkDistance`, `graphRepelStrength`, `graphCenterStrength`, `localGraphDepth`, `localGraphFollowsIncomingLinks`, `localGraphFollowsOutgoingLinks`, `localGraphShowsNeighborLinks`, `localGraphShowsTags`, `localGraphShowsAttachments`, `localGraphShowsExistingFilesOnly` with the defaults in [GraphViews.swift:8-14](../../../Sources/GraphiteUI/GraphViews.swift#L8-L14), [66-73](../../../Sources/GraphiteUI/GraphViews.swift#L66-L73). | Registry test: every key read once, defaults as listed, stored values from the previous build still read. |
| CANVAS-INV-22 | Map property order: Geocoding Properties' `properties.location.frontmatterKey` (unless `enabled` is `false`), then Map View's `frontMatterKey`, then `coordinates`, `location`; duplicates ignoring case dropped; settings files over 1,048,576 bytes ignored ([PlacedNote.swift:17-45](../../../Sources/GraphiteCore/PlacedNote.swift#L17-L45)). | Existing [PlacedNotePropertyNamesTests.swift:24-45](../../../Tests/GraphiteCoreTests/PlacedNotePropertyNamesTests.swift); keep after the pure split. |
| CANVAS-INV-23 | `GraphLayout` is deterministic for the same graph (phyllotaxis start, fixed offsets), cools from α = 1 (0.3 with previous positions) to below 0.001 in about 300 steps, and keeps previous positions for nodes that remain ([GraphLayout.swift:45-89](../../../Sources/GraphiteCore/GraphLayout.swift#L45-L89)). | Existing [LinkGraphTests.swift:89-119](../../../Tests/GraphiteCoreTests/LinkGraphTests.swift); add the 300-step count. |
| CANVAS-INV-24 | Opening a tag node searches `tag:#name`; an unresolved node follows the link from the current note ([WorkspaceGraph.swift:23-34](../../../Sources/GraphiteUI/WorkspaceGraph.swift#L23-L34)). | Workspace test with a fake search field. |
| CANVAS-INV-25 | Level of detail: card content only at scale ≥ 0.3 and for at most the 60 cards nearest the view's centre, plus the card being edited ([CanvasSession.swift:59-64](../../../Sources/GraphiteUI/CanvasSession.swift#L59-L64), [484-505](../../../Sources/GraphiteUI/CanvasSession.swift#L484-L505)). | Existing [CanvasSessionTests.swift:116](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L116). |
| CANVAS-INV-26 | Link cards keep and open only `http`/`https` addresses with a host; an address typed without a scheme gets `https://` ([CanvasInteraction.swift:416-431](../../../Sources/GraphiteUI/CanvasInteraction.swift#L416-L431)). | Existing [CanvasSessionTests.swift:344-353](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L344-L353). |
| CANVAS-INV-27 | Accessibility identifiers used by hosted tests: `canvasBoard`, `canvasCard-<id>`, `canvasCardEditor`, `canvasAddText`, `canvasDelete`, `canvasDoneEditing`, `canvasZoomToFit` ([CanvasBoardView.swift:84](../../../Sources/GraphiteUI/CanvasBoardView.swift#L84), [520](../../../Sources/GraphiteUI/CanvasBoardView.swift#L520), [CanvasCardViews.swift:221](../../../Sources/GraphiteUI/CanvasCardViews.swift#L221), [CanvasPane.swift:234](../../../Sources/GraphiteUI/CanvasPane.swift#L234), [268](../../../Sources/GraphiteUI/CanvasPane.swift#L268), [325](../../../Sources/GraphiteUI/CanvasPane.swift#L325), [329](../../../Sources/GraphiteUI/CanvasPane.swift#L329)). | Hosted tests already query them; a grep test keeps them declared once. |
| CANVAS-INV-28 | Grid snapping is 20 pixels; minimum resized side 40; connection control distance half the span within 70…150 ([CanvasGeometry.swift:162-169](../../../Sources/GraphiteCore/CanvasGeometry.swift#L162-L169)). | Existing [CanvasGeometryTests.swift:29-150](../../../Tests/GraphiteCoreTests/CanvasGeometryTests.swift). |

### Tests that become possible once the seams exist

- Undo during typing keeps the typed text (one step "Edit Text" then the earlier step), on `CanvasDocument` alone.
- Autosave timing and viewport animation end states with an injected clock, without real sleeps.
- Persistence failure paths (save throws during "Save a Copy", reload when the file vanished) with a failure-injecting document-file capability that runs the same contract suite as `VaultStore`.
- Group-label hit testing without rendering, through `CanvasGroupLabelLayout`.
- Card content results (missing file, missing section, oversized note, locked PDF) through `CanvasCardContentLoader` with an in-memory file source.
- Graph fit and zoom limits through `GraphViewport`.
- Vault-switch isolation of graph/map caches through `VaultGraphProvider` with two fake indexes.
- Gesture state machine transitions as a table over `CanvasGesture` cases, including cancellation from every state.
- Hermetic preference tests with an in-memory key-value store instead of `UserDefaults.standard`.

## 8. Appendix: raw metrics

**Reconnaissance numbers, checked.**

| Metric | Reconnaissance | Checked |
| --- | --- | --- |
| Files / physical / code lines | 20 / 5894 / 4751 | Accepted (script method; physical counts match `read_files` totals ±1 trailing line per file) |
| Functions > 40 code lines | 10 (list in CC-CANVAS-04) | Confirmed by reading each range |
| Types > 300 code lines | `extension CanvasSession` 358, `CanvasSession` 334 | Confirmed; combined 692 code lines for one class |
| Files > 400 code lines | `CanvasPane` 503, `CanvasBoardView` 500, `CanvasCardViews` 435, `CanvasFileEditing` 405 | Confirmed; the first three hold 7–9 types each |
| `try?` | 21 | Confirmed by grep: Core 5 (`CanvasLinks` 2, `PlacedNote` 3), Canvas UI 15 (two lines hold two each), `GraphCanvas` 1 |
| `Task.sleep` | 4 | Confirmed: [CanvasSession.swift:302](../../../Sources/GraphiteUI/CanvasSession.swift#L302), [432](../../../Sources/GraphiteUI/CanvasSession.swift#L432), [CanvasPane.swift:566](../../../Sources/GraphiteUI/CanvasPane.swift#L566), [GraphCanvas.swift:122](../../../Sources/GraphiteUI/GraphCanvas.swift#L122) |
| `.shared` | 4 | Confirmed (uses; plus the declaration at [CanvasCardViews.swift:422](../../../Sources/GraphiteUI/CanvasCardViews.swift#L422)) |
| `static var` | 1 | Confirmed: [CanvasInteraction.swift:208](../../../Sources/GraphiteUI/CanvasInteraction.swift#L208) (computed, holds a constant) |
| `@unchecked Sendable` | 1 | Confirmed, with an invariant comment |
| `MainActor.assumeIsolated` | 1 | Confirmed: [CanvasBoardHost.swift:95](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L95) (observer on `.main` queue) |
| `UserDefaults` | 4 | Confirmed: [CanvasSession.swift:151-155](../../../Sources/GraphiteUI/CanvasSession.swift#L151-L155); plus 11 `@AppStorage` properties in `GraphViews.swift` not counted by the pattern |
| `FileManager.default` | 2 | Confirmed: [CanvasCardViews.swift:253](../../../Sources/GraphiteUI/CanvasCardViews.swift#L253), [441](../../../Sources/GraphiteUI/CanvasCardViews.swift#L441) |
| `NotificationCenter.default` | 2 | Confirmed: [CanvasBoardHost.swift:54](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L54), [93](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L93) |
| `default:` in switch | 9 | Confirmed: 6 in Core over bytes or format strings (boundary mapping), 3 in UI: 2 over `DocumentKind` ([CanvasPane.swift:202](../../../Sources/GraphiteUI/CanvasPane.swift#L202), [CanvasCardViews.swift:281](../../../Sources/GraphiteUI/CanvasCardViews.swift#L281)), 1 over `UIGestureRecognizer.State` |
| `[String: Any]` | 4 | Confirmed: all in [PlacedNote.swift:36-50](../../../Sources/GraphiteCore/PlacedNote.swift#L36-L50); plus `[CFString: Any]` at [CanvasPane.swift:210](../../../Sources/GraphiteUI/CanvasPane.swift#L210) |
| `Task { }` (incl. `Task.detached`) | 23 | Confirmed by grep across the scope |
| `fatalError` | 1 | Confirmed: required `init(coder:)` marked unavailable ([CanvasBoardHost.swift:50-51](../../../Sources/GraphiteUI/CanvasBoardHost.swift#L50-L51)) |

**Counted by reading.**

| Item | Count |
| --- | --- |
| `CanvasSession` stored properties | 34 |
| `CanvasFile` stored properties | 11 |
| `WorkspaceModel` members used by `CanvasPane` + `CanvasFilePicker` | 20 |
| Session fields written directly by views | 6 (`viewport`, selection sets, `nameRequest`, `errorMessage`, `groupLabelFrames`, `isWriting`) |
| Places dispatching on file-card kind | 4 |
| Places spelling JSON Canvas type names | 3 |
| Places spelling the `" Graphite edits"` copy suffix (repository-wide) | 4 |
| Persisted `UserDefaults` keys in scope | 17 (2 canvas + 15 graph) |
| Tests covering the area | Core: `CanvasFileTests` 13, `CanvasEditingTests` 16, `CanvasGeometryTests` 14, `LinkGraphTests` 9, `PlacedNotePropertyNamesTests`; Index: `CanvasLinkTests` 9; UI: `CanvasSessionTests` 19; hosted: `CanvasTests` 10 (by `grep "func test"`) |
| Tests touching `UserDefaults.standard` | 1 class (`CanvasSessionTests`, [32-39](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L32-L39)) |
| Tests asserting on message text | 1 ([CanvasSessionTests.swift:396-397](../../../Tests/GraphiteUITests/CanvasSessionTests.swift#L396-L397)) |
| Unit tests with no test for: `GraphCanvasModel`, `NotesMapView` behaviour (only a benchmark, [PerformanceBenchmarkTests.swift:618](../../../Tests/GraphiteUITests/PerformanceBenchmarkTests.swift#L618)), `CanvasPDFPageRenderer`, card content views | by grep over `Tests/**` and `App/Tests/**` |

Correction to the test-count row above: `CanvasGeometryTests` has 15 test functions (by `grep "func test"`, lines 16–224 of [CanvasGeometryTests.swift](../../../Tests/GraphiteCoreTests/CanvasGeometryTests.swift)), not 14.

## 9. Since the snapshot

Delta audit of 2026-10-19 at `fff794b` (main), against `FR-01` to `FR-108`. Commits: `6cb0377` (canvas Undo while typing), `5fba6cd` (Mac card scrolling), `0c074d9` (autosave on the injected clock). Invariants touched: C-18.

### New findings

#### CC-CANVAS-10 `CanvasUndoManager` hooks history through a settable closure slot and lives in the session's file
- **Severity:** Low
- **Rule:** `FR-43`, `FR-77`
- **Evidence:** `var beforeHistoryStep: (() -> Void)?` on an `UndoManager` subclass ([CanvasSession.swift:514-526](../../../Sources/GraphiteUI/CanvasSession.swift#L514-L526)), assigned after construction ([:165](../../../Sources/GraphiteUI/CanvasSession.swift#L165)), at the end of `CanvasSession.swift`. Introduced in `6cb0377`.
- **Why it matters:** any holder of the undo manager can reassign or clear the slot; when it is nil, Undo silently brings back `BUG-CANVAS-01`.
- **Fix direction:** an initializer `let` or a weak owner; its own file.

#### CC-CANVAS-11 Card scrolling picks its platform fact through a default argument, and its comment excludes the iPad trackpad
- **Severity:** Low
- **Rule:** `FR-47`, `FR-80`, `FR-76`
- **Evidence:** `isEnabled(isFocused:isWriting:hasPointerScrolling: Bool = platformHasPointerScrolling)` ([CanvasCardViews.swift:64](../../../Sources/GraphiteUI/CanvasCardViews.swift#L64)), with both production callers on the default ([:113](../../../Sources/GraphiteUI/CanvasCardViews.swift#L113), [:129](../../../Sources/GraphiteUI/CanvasCardViews.swift#L129)); the doc speaks of "a pointer with a scroll wheel or trackpad" but the value is `#if os(macOS)` only ([:51-58](../../../Sources/GraphiteUI/CanvasCardViews.swift#L51-L58)), so an iPad with a trackpad counts as touch. Line 113 is 212 characters. Introduced in `5fba6cd`.
- **Fix direction:** the board passes the fact once; reword the comment or detect an attached pointer on iPadOS.

### State changes of earlier findings
- `SRP-CANVAS-01`: **Worse by one**: the session adds `clock` and has 35 stored properties (the dependency itself is the `DIP-CANVAS-04` fix).
- `SRP-CANVAS-04`: **Fixed** on the branch `graph-view-look` (2026-10-22): the graph's viewport and fit are `GraphViewport` in Core ([GraphViewport.swift](../../../Sources/GraphiteCore/GraphViewport.swift)), tested by `GraphViewportTests`; `GraphCanvas` holds one value.

### Patterns to keep
- Canvas autosave sleeps on an injected `ApplicationClock` with no default ([CanvasSession.swift:160-161](../../../Sources/GraphiteUI/CanvasSession.swift#L160-L161)), and the card-scrolling rule is a pure, tested function ([CanvasCardViews.swift:49-67](../../../Sources/GraphiteUI/CanvasCardViews.swift#L49-L67)).
