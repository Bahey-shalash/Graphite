# Reading view, note pane, properties panel and file previews (READING)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteUI/` — `CalloutFoldStore.swift`, `DocumentModeToggle.swift`, `FilePreviewPane.swift`, `MarkdownPane.swift`, `MarkdownPreview.swift`, `NoteThemeStyle.swift`, `NoteTypography.swift`, `NumberedEquationView.swift`, `PropertiesPanel.swift`, `ReadingTaskCheckbox.swift`, `WorkspaceFolds.swift`, `WorkspaceMentions.swift`, `WorkspaceReadingTasks.swift`, `WorkspaceTagsAndProperties.swift`; 14 files, 6,971 physical lines, 5,431 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script).

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Weak | `MarkdownPreview.swift` declares 64 top-level types in 2,293 code lines; the `MarkdownPreview` view has 37 stored properties and 7 jobs; `MarkdownPane` has 23 stored properties and uses 38 `WorkspaceModel` members; "edit a note, open or closed" is written 3 times with 3 different save rules. |
| O | Mixed | A new reading block kind touches 6 switches in `MarkdownPreview.swift` (3 behind `default:`) plus Core and Live Preview; callout types live in 4 tables; media extensions in 2 lists that disagree. |
| L | Weak | Reading view builds heading fold keys and callout fold keys from rewritten display text while the editor, Live Preview and Read Aloud build them from the source (2 bugs); two link resolvers disagree on folders; two Wikilink label rules disagree (1 bug each). |
| I | Mixed | `MarkdownPane` and `NoteLinksInspector` take the whole `WorkspaceModel` and write 6 of its fields; in contrast `PropertiesPanel`, `ReadingTaskContext` and `ReadingImageActions` take only closures. |
| D | Mixed | `ReadingViewBuilder` constructs `ImageFileService`, `AtomicFileWriter` and calls `FileManager.default`; `ReadingImageCache.shared` is used from 3 places in scope; folds use `UserDefaults.standard`; property parsing takes injected `now`, `locale` and `calendar`. |
| Clean code | Mixed | 18 functions over 40 code lines (largest 127); 8 sleeps, 2 of them used as layout ordering; 16 raw `localizedDescription` messages; failed index reads shown as empty lists; comments are precise but 3 carry incident dates and 6 are stale or misplaced. |

## 1. Summary

**What the area does.** The note pane (`MarkdownPane`) chooses between the reading view (`MarkdownPreview`) and the native editor, owns the note's toolbar, More menu, Read Aloud commands, attachment import, link picker, conflict banner, autosave and word count, and hosts the right-sidebar inspector (`NoteLinksInspector`). The reading view builds the note off the main actor (`ReadingViewBuilder`: frontmatter → properties, blocks, links, embeds, task locations, footnotes, Read Aloud token map), shows it in a lazy stack (`ReadingBlocksView`), restores and reports the scroll place (`ReadingPosition`), follows the word read aloud (`ReadingWordCells`), and draws every block with Textual styles (`ObsidianMarkdownText`, `ObsidianMarkdownParser`, table/code/heading/quote styles, `CalloutView`, `NumberedEquationView`). Around it: the properties editor (`PropertiesPanel` with its number and date parsers), the vault theme as native colors (`NoteThemeStyle`), fonts (`NoteTypography`), image/file previews (`ImagePane`, `ImageViewer`, `EmbeddedImageView`, `FilePreviewPane`), media embeds, and four `WorkspaceModel` extensions (folds, mentions, reading-view task ticks, tags/properties views).

**Shape.** The two most-changed files of the area (`MarkdownPane.swift` 36 commits, `MarkdownPreview.swift` 25) are also the largest. Many types in `MarkdownPreview.swift` are not reading-view types at all: `CalloutView`, `ObsidianMarkdownText`, `ThemedRule`, `ReadingImageCache`, `EmbeddedMediaPlayer` and `EmbeddedAudioPlayer` are used by Live Preview, canvases, panes and the conflict sheet ([LivePreviewWidgets.swift:272](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272), [WorkspacePanes.swift:538-541](../../../Sources/GraphiteUI/WorkspacePanes.swift#L538-L541), [CanvasCardViews.swift:263-266](../../../Sources/GraphiteUI/CanvasCardViews.swift#L263-L266), [ConflictVersionsSheet.swift:347-350](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L347-L350)).

**The three biggest problems.**
1. **Reading view re-implements rules the editor owns, from different input.** Heading fold keys are rebuilt twice in the reading view from the *rewritten* heading text ([MarkdownPreview.swift:1015-1018](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1015-L1018), [MarkdownPreview.swift:1368-1371](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1368-L1371)) while `NoteFolding` keys the raw line ([NoteFolding.swift:62](../../../Sources/GraphiteCore/NoteFolding.swift#L62)); callout fold keys use the rewritten title in reading view and the raw title in Live Preview and Read Aloud; link resolution and Wikilink labels also exist twice. Four bugs follow (BUG-READING-01, -02, -03, -05).
2. **Two god views.** `MarkdownPreview` mixes build scheduling, caching, scroll restoration (three loose state fields), heading jumps, Read Aloud following with sleep-polling, fold reveal and task-tick rebuild timing in one `body` of 127 lines; `MarkdownPane` mixes toolbars, menus, imports, Read Aloud commands, autosave and drawing detection and reaches into 38 members of `WorkspaceModel`.
3. **Outcomes and failures travel through shared fields.** Mentions, task ticks, property rename and pane actions report through `workspace.errorMessage` with raw `localizedDescription` text (16 sites); failed index reads become empty lists ("No other notes link here"); the inspector removes a mention from its list whether or not the link was written (BUG-READING-04).

**The three best parts.**
1. **Safe writes to closed notes.** Ticks, mention links and property renames read the file with its revision, keep its byte-order mark, and save only if unchanged ([WorkspaceReadingTasks.swift:20-24](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L20-L24), [WorkspaceMentions.swift:75-82](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L75-L82), [WorkspaceTagsAndProperties.swift:78-84](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L78-L84)); a tick lands only where the task still is (`ReadingTasks.Location` with a line checksum), and the checkbox reverts its optimistic state when it did not ([ReadingTaskCheckbox.swift:49-53](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift#L49-L53)).
2. **Read Aloud word updates touch only two texts.** `ReadingWordSource` → `ReadingWordTracker` → `ReadingWordCells` → one `ReadingWordCell` per text, with `ReadingNoteBlocks` compared by value and `ReadingBuildRequest` compared rather than hashed ([MarkdownPreview.swift:1058-1171](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1058-L1171), [MarkdownPreview.swift:1192-1243](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1192-L1243)).
3. **One encoder/decoder for the reading view's private link vocabulary and marker escaping** (`GraphiteOpenLink`, `PreviewImageFragment`, `ReadingMarkerEscaping`, [MarkdownPreview.swift:95-230](../../../Sources/GraphiteUI/MarkdownPreview.swift#L95-L230)), and pure, tested property parsers with injected `now`, `locale` and `calendar` ([PropertiesPanel.swift:392](../../../Sources/GraphiteUI/PropertiesPanel.swift#L392), [PropertiesPanel.swift:436](../../../Sources/GraphiteUI/PropertiesPanel.swift#L436), [PropertiesPanel.swift:530](../../../Sources/GraphiteUI/PropertiesPanel.swift#L530)).

**Earlier-pass claims.**

| Claim (document:line) | Holds? | Evidence |
| --- | --- | --- |
| `SOLID.md:17` — workspace feature extensions "share the same mutable object" | Holds | The four extensions in scope read `store`, `index`, `errorMessage`, `propertyTypesVersion` of `WorkspaceModel` ([WorkspaceTagsAndProperties.swift:46-52](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L46-L52)). |
| `SOLID.md:20` — views receive the broad workspace object | Holds, and extends to this area | `MarkdownPane` stores `@Bindable var workspace: WorkspaceModel` ([MarkdownPane.swift:9](../../../Sources/GraphiteUI/MarkdownPane.swift#L9)) and uses 38 members. |
| `SOLID.md:21` — workspace persistence uses `UserDefaults.standard` directly | Holds | [WorkspaceFolds.swift:14](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L14), [WorkspaceFolds.swift:18](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L18). |
| `Architecture.md:128` — "Reading view folds headings with the same keys" | Does not hold | Same formula, different input: rewritten heading text in reading view vs raw line in `NoteFolding` (BUG-READING-01). |
| `Architecture.md:249` — marker code points U+E000–U+E006 in a note "are shown as U+FFFD" | Does not hold for reading view | Reading view escapes U+E000–U+E00B before the rewrite and restores them after parsing ([MarkdownPreview.swift:201-230](../../../Sources/GraphiteUI/MarkdownPreview.swift#L201-L230), [MarkdownPreview.swift:1970-1991](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1970-L1991)); `UiReadingViewTests.testPrivateUseCharactersInTheNoteAreKept` ([UiReadingViewTests.swift:185](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L185)) pins that they are kept. |
| `Architecture.md:245` — `ReadingPosition` checkpoint, `offsetBeforeRestoring`, user scroll cancels restoration | Holds | [MarkdownPreview.swift:852-869](../../../Sources/GraphiteUI/MarkdownPreview.swift#L852-L869), [MarkdownPreview.swift:909-921](../../../Sources/GraphiteUI/MarkdownPreview.swift#L909-L921). |
| `Architecture.md:251` — a tick is applied only where the task still is; embedded note ticked through its session (saved at once) or a revision-checked rewrite keeping the BOM | Holds | [WorkspaceReadingTasks.swift:9-31](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L9-L31). |
| `Architecture.md:307` — word updates reach only `ReadingWordTracker` and two cells; build request compared, not hashed; `ReadingNoteBlocks` not `.equatable()` | Holds | [MarkdownPreview.swift:1067-1078](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1067-L1078), [MarkdownPreview.swift:1137-1146](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1137-L1146), [MarkdownPreview.swift:1192-1243](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1192-L1243). |
| `Architecture.md:235` — reading column 730 pt, margins 33 pt | Holds | [MarkdownPreview.swift:15-17](../../../Sources/GraphiteUI/MarkdownPreview.swift#L15-L17). |
| `Architecture.md:116` — reading view parses properties with `types.json` types loaded per open note | Holds | [MarkdownPane.swift:148](../../../Sources/GraphiteUI/MarkdownPane.swift#L148), [MarkdownPreview.swift:282-285](../../../Sources/GraphiteUI/MarkdownPreview.swift#L282-L285). |
| `Architecture.md:282` — callout colors by type with Obsidian's aliases, unknown type takes the note color | Holds | [MarkdownPreview.swift:2552-2558](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2552-L2558). |
| `Coverage.md:150` — a callout title without a link leaves the tap to the fold button | Holds | [MarkdownPreview.swift:2493](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2493). |
| `PropertiesPanel.swift:389` comment — "Graphite does not write `types.json`" (code comment acting as a claim) | Does not hold | `setPropertyType` writes it ([WorkspaceTagsAndProperties.swift:46-52](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L46-L52)); `Architecture.md:130` agrees with the code. |
| `ReadAloudFolding.swift:9` comment — callout key is "the same for the reading view and Live Preview" | Does not hold | BUG-READING-02. |

## 2. File inventory

Physical and code lines are the reconnaissance numbers (`read_files` reports one more physical line per file because it counts the line after the final newline). Type counts are top-level declarations counted by reading.

| File | Physical | Code | Types | Responsibility |
| --- | ---: | ---: | ---: | --- |
| [CalloutFoldStore.swift](../../../Sources/GraphiteUI/CalloutFoldStore.swift) | 31 | 21 | 2 | Session-only callout expansion per note, shared by reading view, Live Preview and Read Aloud; plus an unused `CalloutFoldScope`. |
| [DocumentModeToggle.swift](../../../Sources/GraphiteUI/DocumentModeToggle.swift) | 207 | 136 | 4 | Write toggle, the control row, toolbar layout thresholds, and the tab bar's Undo/Redo/Write for notes, canvases and PDFs. |
| [FilePreviewPane.swift](../../../Sources/GraphiteUI/FilePreviewPane.swift) | 502 | 398 | 9 | Image pane, full-screen image viewer, zooming scroll view, Quick Look fallback pane, embedded image view and its decode cache. |
| [MarkdownPane.swift](../../../Sources/GraphiteUI/MarkdownPane.swift) | 1,192 | 1,000 | 8 | The note pane (view switch, toolbar, menus, imports, Read Aloud commands), autosave, drawing-at-cursor detection, word count, link picker, right-sidebar inspector, completion overlay. |
| [MarkdownPreview.swift](../../../Sources/GraphiteUI/MarkdownPreview.swift) | 3,021 | 2,293 | 64 | Reading view build and display, link URL vocabulary, scroll place, Read Aloud word cells, Textual styles, callouts, image cache, media players. |
| [NoteThemeStyle.swift](../../../Sources/GraphiteUI/NoteThemeStyle.swift) | 381 | 318 | 2 | Vault theme tokens as dynamic, contrast-checked platform colors and shapes; page background view. |
| [NoteTypography.swift](../../../Sources/GraphiteUI/NoteTypography.swift) | 270 | 192 | 4 | Installed font lookup, resolved note/monospace/interface fonts, interface font modifier, note font size clamping. |
| [NumberedEquationView.swift](../../../Sources/GraphiteUI/NumberedEquationView.swift) | 227 | 166 | 4 | Display formula with `\tag` numbers laid out as MathJax does. |
| [PropertiesPanel.swift](../../../Sources/GraphiteUI/PropertiesPanel.swift) | 733 | 593 | 9 | Properties editor rows, pending-edit list, type conversion, number and date text parsing, list chips, wrapping layout. |
| [ReadingTaskCheckbox.swift](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift) | 110 | 82 | 4 | Tappable reading-view task checkbox and the themed checkbox shape shared with Live Preview. |
| [WorkspaceFolds.swift](../../../Sources/GraphiteUI/WorkspaceFolds.swift) | 55 | 46 | 0 (extension) | Per-vault fold keys in `UserDefaults`, following moves and deletions. |
| [WorkspaceMentions.swift](../../../Sources/GraphiteUI/WorkspaceMentions.swift) | 105 | 80 | 1 (+extension) | Linked and unlinked mentions, and turning an unlinked mention into a link. |
| [WorkspaceReadingTasks.swift](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift) | 32 | 25 | 0 (extension) | Ticking a reading-view task in the note, an open embedded note, or a closed file. |
| [WorkspaceTagsAndProperties.swift](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift) | 105 | 81 | 1 (+extension) | Vault tag and property lists, property type assignment, vault-wide property rename. |
| **Total** | **6,971** | **5,431** | **112** | |

`MarkdownPreview.swift` by concept (line ranges read):

| Lines | Concept | Used outside reading view? |
| --- | --- | --- |
| 9–43 | `ReadingConfiguration` | Yes ([MarkdownPane.swift:353](../../../Sources/GraphiteUI/MarkdownPane.swift#L353) for Live Preview) |
| 45–93 | `RenderedBlock`, `RenderedFootnote` | No |
| 95–230 | `PreviewImageFragment`, `GraphiteOpenLink`, `ReadingMarkerEscaping` | Yes (Live Preview, [LivePreviewWidgets.swift:422-445](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L422-L445)) |
| 232–235 | `MediaFileKind` | Yes (canvas, panes, Live Preview, conflicts) |
| 237–640 | `ReadingViewBuild`, `ReadingBlockLocation`, `ReadingViewBuilder` | Yes (canvas cards use the builder per `Architecture.md:292`) |
| 642–745 | `HeadingScrollRequest`, `ReadingPosition`, coordinate space, viewport | Yes (`HeadingScrollRequest` is the workspace's jump request) |
| 747–1056, 1288–1324 | `MarkdownPreview` view and its helpers | No |
| 1058–1171 | Read Aloud word source, tracker, follow state, word cells | No |
| 1173–1286 | Block actions, `ReadingNoteBlocks`, build request/key, blocks cache | `ReadingBlocksCache` is owned by `MarkdownSession` |
| 1326–1569 | `ReadingFolding`, `ReadingBlocksView`, `ReadingCallout`, position reporter | No |
| 1571–2114 | `ObsidianMarkdownText`, text content, theme colors, parser, list style, task attachment | Yes (Live Preview widgets) |
| 2116–2417 | Code, heading, table, cell, quote, rule styles | Yes |
| 2419–2559 | `CalloutView`, `CalloutAppearance` | Yes |
| 2561–2706 | Image loader/attachment, thumbnails, `ReadingImageCache` | Yes (Live Preview, [LivePreviewWidgets.swift:582](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L582)) |
| 2708–2958 | Media playback, players | Yes |
| 2961–3021 | `ReadingImageActions`, `ReadingImageBlock` | No |

## 3. Responsibility maps of the major types

### 3.1 `MarkdownPreview` (view, [MarkdownPreview.swift:747-1056](../../../Sources/GraphiteUI/MarkdownPreview.swift#L747-L1056) and [1288-1309](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1288-L1309))

37 stored properties (19 inputs, 2 environment values, 16 `@State`), counted by reading lines 748–812.

| Responsibility | Stored state | Functions |
| --- | --- | --- |
| Inputs: note and services | `source`, `path`, `root`, `index`, `configuration`, `baseContext`, `blocksCache`, `savedPosition` | — |
| Callbacks into the pane | `navigate`, `openPDF`, `updateProperties`, `folding`, `takeStartingLocation`, `toggleTask`, `suspendReadingFollow` | — |
| Build scheduling and display | `blocks`, `readingSourceTokensByBlock`, `errorMessage`, `hasMissingEmbeds`, `shownBuildKey`, `blocksVersion`, `embeddedNoteTaskEditCount`, `buildsWithoutDelay` | `.task(id: ReadingBuildRequest…)` ([930-953](../../../Sources/GraphiteUI/MarkdownPreview.swift#L930-L953)), `show(_:)` ([1029-1039](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1029-L1039)), `containsMissingEmbed`, `mediaLocations` |
| Scroll restoration | `scrollPosition`, `hasRestoredPosition`, `pendingRestorationOffset`, `offsetBeforeRestoring` | scroll geometry action ([840-862](../../../Sources/GraphiteUI/MarkdownPreview.swift#L840-L862)), restoration task ([900-921](../../../Sources/GraphiteUI/MarkdownPreview.swift#L900-L921)), `scrollToTop(of:scrollProxy:)` ([958-968](../../../Sources/GraphiteUI/MarkdownPreview.swift#L958-L968)) |
| Heading and match jumps | `headingScrollRequest`, `handledScrollToken` (bindings) | restoration task tail ([922-927](../../../Sources/GraphiteUI/MarkdownPreview.swift#L922-L927)), `blockActions.update(scrollToHeading:)` ([825-828](../../../Sources/GraphiteUI/MarkdownPreview.swift#L825-L828)) |
| Read Aloud following | `readingWord`, `followsReading`, `readingFollow`, `wordCells` | `wordDidMove(to:)` ([971-994](../../../Sources/GraphiteUI/MarkdownPreview.swift#L971-L994)), `followReadingWordIfNeeded()` ([996-1007](../../../Sources/GraphiteUI/MarkdownPreview.swift#L996-L1007)), `revealFoldedReadingSection` ([1009-1027](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1009-L1027)) |
| Task ticks | — (uses build state) | `toggle(_:in:with:)` ([1042-1055](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1042-L1055)) |
| Rendering context | `typography`, `theme`, `blockActions`, `mediaPlayers` | `body` environment block ([889-897](../../../Sources/GraphiteUI/MarkdownPreview.swift#L889-L897)), inline title ([818-824](../../../Sources/GraphiteUI/MarkdownPreview.swift#L818-L824)) |

**Calls that cross responsibilities (the coupling a split must keep).**
- `show(_:)` writes `savedPosition.blockLocations` (restoration), `wordCells.index` and `wordDidMove` (Read Aloud), `blocks`/`shownBuildKey` (build) and `mediaPlayers.keepPlaybacks` (media) in one step ([1029-1039](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1029-L1039)).
- `toggle` (tasks) writes build state: `shownBuildKey = nil`, `buildsWithoutDelay`, `embeddedNoteTaskEditCount` ([1045-1053](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1045-L1053)).
- Heading jumps and Read Aloud following both clear `pendingRestorationOffset` ([826](../../../Sources/GraphiteUI/MarkdownPreview.swift#L826), [923](../../../Sources/GraphiteUI/MarkdownPreview.swift#L923), [1003](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1003)); user scrolling clears it and suspends following ([863-869](../../../Sources/GraphiteUI/MarkdownPreview.swift#L863-L869)).
- `revealFoldedReadingSection` (Read Aloud) recomputes fold keys (folding) from `blocks` (build) and `savedPosition.blockLocations` (restoration).

**Lifecycle and ordering rules it relies on.**
1. `savedPosition.blockLocations` is set before `blocks` change, so `ReadingPosition` drops frames of blocks that no longer exist ([680](../../../Sources/GraphiteUI/MarkdownPreview.swift#L680), [1030](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1030)).
2. `wordCells.index` runs before `wordDidMove` re-shows the current word ([1032-1033](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1032-L1033)).
3. Until `hasRestoredPosition` is true, scroll offsets are kept aside in `offsetBeforeRestoring`, never written to the checkpoint ([852-855](../../../Sources/GraphiteUI/MarkdownPreview.swift#L852-L855)).
4. The restoration task runs again when `blocks.count` changes, because a link can ask to scroll before blocks exist ([898-901](../../../Sources/GraphiteUI/MarkdownPreview.swift#L898-L901)).
5. A starting location from the editor (`takeStartingLocation`) wins over the saved offset; a new heading request wins over both ([904-913](../../../Sources/GraphiteUI/MarkdownPreview.swift#L904-L913)).
6. The first build of a shown note is not delayed; later builds wait 150 ms, except one after a task tick ([940-942](../../../Sources/GraphiteUI/MarkdownPreview.swift#L940-L942)).
7. `blockActions.update` must run in every `body` evaluation before `ReadingNoteBlocks` is made, because the blocks read the closures from that object when tapped ([825-831](../../../Sources/GraphiteUI/MarkdownPreview.swift#L825-L831), [1221-1228](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1221-L1228)).
8. `ReadingBuildRequest` omits `path` and `root`; this is correct only because the pane is identified by its session ([WorkspacePanes.swift:510-512](../../../Sources/GraphiteUI/WorkspacePanes.swift#L510-L512)).

**Verdict.** Too many jobs for one view, and the restoration flow is a three-field state machine without a type. **Proposed split.**

| New type | Members that move | Kind |
| --- | --- | --- |
| `ReadingBuildModel` (`@MainActor @Observable`) | `blocks`, `readingSourceTokensByBlock`, `errorMessage`, `hasMissingEmbeds`, `shownBuildKey`, `blocksVersion`, `embeddedNoteTaskEditCount`, `buildsWithoutDelay`; the build task body; `show`; `taskWasToggled(in:didToggle:)` (today's `toggle` bookkeeping) | model, one per session (replaces `ReadingBlocksCache`) |
| `ReadingScrollRestoration` (value) | `enum Phase { case awaitingBlocks(offsetBeforeRestoring: CGFloat?), restoring(offset: CGFloat), restored }` with intent methods `blocksAppeared`, `viewportChanged`, `userScrolled`, `headingRequested` returning the scroll action to perform | pure decision value, unit-testable |
| `ReadingWordFollower` (`@MainActor` class) | `readingFollow`, `wordCells`, `wordDidMove`, `followReadingWordIfNeeded`, `revealFoldedReadingSection` | controller |
| `MarkdownPreview` | inputs, `scrollPosition`, environment injection, `body` | view |

### 3.2 `ReadingViewBuilder` (actor, [MarkdownPreview.swift:259-640](../../../Sources/GraphiteUI/MarkdownPreview.swift#L259-L640))

7 stored properties; 17 methods; 382 physical lines.

| Responsibility | State | Methods |
| --- | --- | --- |
| Per-build identity and heading numbering | `nextIdentifier`, `registeredHeadingAnchors`, `headingOccurrencesByAnchor`, `calloutDepth` | `identifier()`, `scrollTarget(forHeadingWithAnchor:)` |
| Frontmatter, footnotes, block locations | `hostNote` | `build(...)` lines 276–312 |
| Block rendering | — | `render(...)`, `sectioned(...)` |
| Embed classification and file reading | `imageService` | `renderEmbed(...)`, `embeddedNoteLink(...)`, `resolve(...)` |
| Link rewriting to Graphite URLs | — | `prepared(...)`, `readingText(...)`, `notePathDestinationRange`, `markdownLinkTarget`, `linkTarget`, `exactTarget`, `displayText`, `escapedLabel` |
| Task locations | — | `TaskSource` and the closure in `render` ([392-396](../../../Sources/GraphiteUI/MarkdownPreview.swift#L392-L396)) |
| Read Aloud token mapping | — | `build` lines 313–324, `sourceTokens(...)` |
| Unresolved-embed signal | `hasUnresolvedEmbeds` | set in `prepared` ([552](../../../Sources/GraphiteUI/MarkdownPreview.swift#L552)) |

**Lifecycle rules.** "One builder builds one note" ([258](../../../Sources/GraphiteUI/MarkdownPreview.swift#L258)): nothing resets the per-build state, so a second `build` on the same instance keeps old heading anchors and identifiers; every caller makes a new builder ([943](../../../Sources/GraphiteUI/MarkdownPreview.swift#L943); tests do the same, [UiReadingViewTests.swift:34](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L34)). `calloutDepth` must be incremented around the recursive `render` of a callout body ([410-413](../../../Sources/GraphiteUI/MarkdownPreview.swift#L410-L413)). `hostNote` must be set before any `prepared` call because relative targets of embedded notes depend on it ([276](../../../Sources/GraphiteUI/MarkdownPreview.swift#L276), [597](../../../Sources/GraphiteUI/MarkdownPreview.swift#L597)). Identifiers are assigned after a callout's body is rendered (post-order, [411-414](../../../Sources/GraphiteUI/MarkdownPreview.swift#L411-L414)), and `blockLocations` zips located blocks with rendered blocks in order ([300-304](../../../Sources/GraphiteUI/MarkdownPreview.swift#L300-L304)).

**Verdict.** A coherent "build" job, but it owns I/O (file existence, file reads, PDF inspection) and a link-rewriting rule that Live Preview implements a second time. **Proposed split:** `ReadingLinkRewriter` (pure: `prepared`, `displayText`, `escapedLabel`, target encoding; shared with `LivePreviewText.prepared`), `EmbedClassification` (pure: decides `.video/.audio/.pdf/.image/.note/.base/.link` from a resolved path and a "is editable drawing" fact; shared with `LivePreviewEmbedView.resolve`), a `ReadingFileLookup` port (`resolve(target:from:isWiki:)`, `isEditableDrawingPDF(at:)`, `readNote(at:maximumBytes:)`) implemented once over `VaultIndex`, `VaultStore` and `ImageFileService`, and `ReadingViewBuilder` keeping block assembly, numbering, locations and token mapping, with its per-build state in a `struct BuildState` created inside `build`.

### 3.3 `MarkdownPane` (view, [MarkdownPane.swift:7-659](../../../Sources/GraphiteUI/MarkdownPane.swift#L7-L659))

23 stored properties: 6 inputs, 11 `@State`, 6 `@Environment` (lines 8–35). 38 distinct `WorkspaceModel` members used (counted by reading the matches of `workspace\.[a-zA-Z]+` in lines 7–659); it writes `errorMessage`, `viewedImage`, `viewedImageNote`, `fileRecoveryRequest` and four `readAloudNavigator` fields.

| Responsibility | State | Members |
| --- | --- | --- |
| Reading view vs editor, and their configuration | `drawingAtCursor`, `imageAtCursor` (read by toolbar) | `body` lines 58–96, `readingConfiguration`, `editorConfiguration`, `livePreviewEnvironment`, `inlineTitle`, `paletteHexByName`, `quickFontSizeAdjustment` |
| Toolbar, Format/Insert/More menus | `showsLinksInspector` | `toolbarContent`, `formatMenuItems`, `insertMenuItems`, `drawButton`, `moreMenuItems`, `isWritingBinding`, `usesDocumentControlRow`, `isCompactWidth` |
| Editor commands and actions wiring | — | `editorActions`, `editorContextMenuActions`, `run`, `insertColor`, `selectedText` |
| Link following | — | `follow`, `openPDF`, `viewImage`, `imageDrawing`, `drawingEditor` |
| Attachments, photos, camera | `showsAttachmentPicker`, `showsPhotoPicker`, `showsCamera`, `pickedPhotos` | `insertPickedPhotos`, `insertCameraPhoto`, `.fileImporter`, `.photosPicker` |
| Link picker | `showsLinkPicker` | `.sheet` → `LinkPicker` |
| External change banner | `showsReloadConfirmation` | `banner`, `saveCopy` |
| Read Aloud commands and folding sync | `readingStartOffset`, `showsReadingSections`, `pendingReadingSection` | `readAloudMenu`, `startReading`, `readAloudHooks`, `foldedRanges`, `.onChange(of: session.foldedKeys)`, `.onChange(of: viewMode)` |
| Autosave, drawing detection, word count | — | `AutosaveDriver`, `DrawingAtCursorTracker`, `WordCountDisplay` attached in `body` |

**Crossings.** `AutosaveDriver` also clears the Read Aloud start (`readingStartOffset = nil`) on every text change ([143](../../../Sources/GraphiteUI/MarkdownPane.swift#L143)). The reading-view mode change writes the window-level Read Aloud navigator ([133-139](../../../Sources/GraphiteUI/MarkdownPane.swift#L133-L139)). The More menu's View picker writes `session.viewMode` directly ([525](../../../Sources/GraphiteUI/MarkdownPane.swift#L525)) while the Write toggle goes through `session.toggleReadingView(editingMode:)` ([614-618](../../../Sources/GraphiteUI/MarkdownPane.swift#L614-L618)).

**Ordering rules.** The pane's `body` must not read `session.text` or `session.selection` (only the small background views do), or every keystroke rebuilds the toolbar ([140-145](../../../Sources/GraphiteUI/MarkdownPane.swift#L140-L145), [491-494](../../../Sources/GraphiteUI/MarkdownPane.swift#L491-L494), [587-589](../../../Sources/GraphiteUI/MarkdownPane.swift#L587-L589)). The tab must be activated before following a link so the link opens on this side ([284-287](../../../Sources/GraphiteUI/MarkdownPane.swift#L284-L287)).

**Verdict and split.** `NoteToolbar` (view: toolbar, menus, Write binding; takes a `NoteCommands` value of closures), `NoteReadAloudCommands` (model: start/section/selection/start-end rules, returns a typed refusal instead of writing `errorMessage`), `NoteAttachmentImport` (photos, camera, file importer → one workspace call each), `NoteAutosave` moved out of the view into the session owner (see SRP-READING-05), `DrawingAtCursorTracker` and `WordCountDisplay`, `LinkPicker`, `NoteLinksInspector` and `CompletionPopupOverlay` to their own files. The pane keeps the view switch and receives narrow models instead of `WorkspaceModel`.

### 3.4 `NoteThemeStyle` (value, [NoteThemeStyle.swift:13-365](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L13-L365))

62 stored properties (counted by reading lines 14–105), one 122-line initializer, two static color builders. It is a resolved-token record: every property is an immutable value derived once per theme in `init` ([124-253](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L124-L253)). Groups visible in the declarations: page and text colors (7), headings (6 arrays + ornaments), links (3), tags (5), checkboxes (5), code (8), quotes (4), rules (3), tables (4), callouts (4), highlights (3), inline title (4), layout and fonts (6).

**Verdict.** Not a god object (no behaviour beyond derivation), but the flat list hides the groups each consumer uses. **Split:** nested values `HeadingTheme` (per level: color, scale, weight, family, italic, ornament), `CodeTheme`, `TagTheme`, `CheckboxTheme`, `CalloutTheme`, `TableTheme`, `QuoteTheme`, `RuleTheme`, `InlineTitleTheme`, each made by its own `init(light:dark:pages:)`. The rule "more than ~15 stored properties needs a recorded reason" should allow an immutable resolved record with a recorded reason, while still asking for groups.

### 3.5 Other types checked against the threshold

`NoteLinksInspector` (12 stored properties, [MarkdownPane.swift:888-1171](../../../Sources/GraphiteUI/MarkdownPane.swift#L888-L1171)) parses the note and loads mentions in view tasks (SRP-READING-07). `PropertyRow` (13 stored properties, [PropertiesPanel.swift:161-358](../../../Sources/GraphiteUI/PropertiesPanel.swift#L161-L358)) is one row editor; size is fine. `EmbeddedAudioPlayer` (8 stored) owns an `AVPlayer` observer lifecycle correctly (§6).

## 4. Findings by principle

### S

#### SRP-READING-01 `MarkdownPreview` runs seven jobs from 37 stored properties and one 127-line `body`
- **Severity:** Medium
- **Evidence:** stored properties [MarkdownPreview.swift:748-812](../../../Sources/GraphiteUI/MarkdownPreview.swift#L748-L812) (37, counted by reading); `body` [814-954](../../../Sources/GraphiteUI/MarkdownPreview.swift#L814-L954) (127 code lines per reconnaissance); restoration spread over three fields `hasRestoredPosition`, `pendingRestorationOffset`, `offsetBeforeRestoring` ([785-790](../../../Sources/GraphiteUI/MarkdownPreview.swift#L785-L790)) changed from 7 places ([826](../../../Sources/GraphiteUI/MarkdownPreview.swift#L826), [853-861](../../../Sources/GraphiteUI/MarkdownPreview.swift#L853-L861), [867](../../../Sources/GraphiteUI/MarkdownPreview.swift#L867), [905-919](../../../Sources/GraphiteUI/MarkdownPreview.swift#L905-L919), [923](../../../Sources/GraphiteUI/MarkdownPreview.swift#L923), [959](../../../Sources/GraphiteUI/MarkdownPreview.swift#L959), [1003](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1003)).
- **Why it matters:** the scroll-restoration rules (`Architecture.md:245`) are only testable through a hosted UI test; `Coverage.md:284` records that the one such test was flaky and its cause "was not seen". Every change to Read Aloud following, task ticks or builds edits the same struct.
- **Fix direction:** split as in §3.1: `ReadingBuildModel`, a `ReadingScrollRestoration` enum with intent methods that return the scroll to perform, `ReadingWordFollower`; the view only wires them.

#### SRP-READING-02 `MarkdownPreview.swift` is a 64-type library file that other areas depend on
- **Severity:** Medium
- **Evidence:** 64 top-level types (counted by reading; §2 table). Types used outside reading view: `CalloutView` ([LivePreviewWidgets.swift:272](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272)), `ReadingImageCache` ([LivePreviewWidgets.swift:582](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L582)), `EmbeddedMediaPlayer`/`EmbeddedAudioPlayer` ([WorkspacePanes.swift:538-541](../../../Sources/GraphiteUI/WorkspacePanes.swift#L538-L541), [CanvasCardViews.swift:263-266](../../../Sources/GraphiteUI/CanvasCardViews.swift#L263-L266), [ConflictVersionsSheet.swift:347-350](../../../Sources/GraphiteUI/ConflictVersionsSheet.swift#L347-L350)), `MediaFileKind` ([CanvasPane.swift:192-193](../../../Sources/GraphiteUI/CanvasPane.swift#L192-L193), [LivePreviewRenderedBlocks.swift:745](../../../Sources/GraphiteUI/LivePreviewRenderedBlocks.swift#L745)), `ReadingViewBuilder.escapedLabel` ([LivePreviewWidgets.swift:444](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L444)).
- **Why it matters:** 25 commits touch this file; a change to the image cache or callout drawing shows up as a reading-view change, and reviewers cannot see which area a diff affects.
- **Fix direction:** one concept per file (list in §7); shared drawing primitives (`CalloutView`, `ObsidianMarkdownText` and its styles, image cache, media players, `GraphiteOpenLink`) move to files named after them, not after the reading view.

#### SRP-READING-03 `ReadingViewBuilder` mixes block assembly with file I/O and a link rule shared with Live Preview
- **Severity:** Medium
- **Evidence:** file existence [MarkdownPreview.swift:488-494](../../../Sources/GraphiteUI/MarkdownPreview.swift#L488-L494); note read [458-459](../../../Sources/GraphiteUI/MarkdownPreview.swift#L458-L459); PDF inspection [453](../../../Sources/GraphiteUI/MarkdownPreview.swift#L453), [537](../../../Sources/GraphiteUI/MarkdownPreview.swift#L537); link rewriting [502-569](../../../Sources/GraphiteUI/MarkdownPreview.swift#L502-L569); Read Aloud tokens [313-358](../../../Sources/GraphiteUI/MarkdownPreview.swift#L313-L358).
- **Why it matters:** every builder test needs a real temporary vault and a real `VaultIndex` ([UiReadingViewTests.swift:34](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L34)); the link and embed rules cannot be shared with Live Preview, which re-implements them (LSP-READING-03, -04).
- **Fix direction:** §3.2 split: pure `ReadingLinkRewriter` and `EmbedClassification`, a `ReadingFileLookup` port, the builder keeping assembly.

#### SRP-READING-04 `MarkdownPane` owns toolbar, menus, imports, Read Aloud rules and editor wiring for one note
- **Severity:** Medium
- **Evidence:** 23 stored properties ([MarkdownPane.swift:8-35](../../../Sources/GraphiteUI/MarkdownPane.swift#L8-L35)); `body` 109 code lines ([57-176](../../../Sources/GraphiteUI/MarkdownPane.swift#L57-L176)); Read Aloud start/end rules with user messages inside menu buttons ([495-516](../../../Sources/GraphiteUI/MarkdownPane.swift#L495-L516)); photo encoding policy ([630-651](../../../Sources/GraphiteUI/MarkdownPane.swift#L630-L651)); 8 types in the file (§2).
- **Why it matters:** Read Aloud's selection rules ("Put the cursor after the reading start first") and photo extension mapping (`heic` → `jpg`) are untestable without UI; 36 commits touch this file.
- **Fix direction:** §3.3 split; Read Aloud range decisions become a pure function returning a range or a typed refusal.

#### SRP-READING-05 Autosave and file inspection live in invisible background views
- **Severity:** Medium
- **Evidence:** autosave 900 ms after typing in `AutosaveDriver.body` ([MarkdownPane.swift:663-678](../../../Sources/GraphiteUI/MarkdownPane.swift#L663-L678)); drawing metadata read from disk in `DrawingAtCursorTracker` ([704-746](../../../Sources/GraphiteUI/MarkdownPane.swift#L704-L746)); note parsing in `NoteLinksInspector`'s task ([976-986](../../../Sources/GraphiteUI/MarkdownPane.swift#L976-L986)).
- **Why it matters:** the autosave rule exists only while a `MarkdownPane` for the session is on screen. Text changed in a session whose pane is not shown (a hidden tab) is not autosaved by this driver; `toggleReadingTask` and `renameProperty` each work around it by saving explicitly ([WorkspaceReadingTasks.swift:13-15](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L13-L15), [WorkspaceTagsAndProperties.swift:74-76](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L74-L76)), while `linkMention` does not ([WorkspaceMentions.swift:70-73](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L70-L73)). The save policy is therefore decided in three callers.
- **Fix direction:** an autosave scheduler owned by the session (or the workspace's session registry), started when the text changes, cancelled on close; views stop deciding when to save.

#### SRP-READING-06 "Apply an edit to a note, open or closed" is implemented three times with three save rules
- **Severity:** Medium
- **Evidence:** [WorkspaceMentions.swift:70-83](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L70-L83) (open: apply, never save), [WorkspaceReadingTasks.swift:11-26](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L11-L26) (open: apply and save at once), [WorkspaceTagsAndProperties.swift:71-85](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L71-L85) (open: apply, save only when no editor is attached). The closed-file branch (read with revision → `NoteTextEncoding.decode` → edit → encode with BOM → save expecting revision) is copied in all three.
- **Why it matters:** a fourth feature will copy one of the three and pick a save rule by accident; a fix to the closed-file path (for example bounded size or a typed "changed since read" error) has to be made three times. None of the three paths has a test except task ticks (`UiReadingTaskTests`, [UiReadingTaskTests.swift:262-329](../../../Tests/GraphiteUITests/UiReadingTaskTests.swift#L262-L329)); `grep renameProperty|linkMention` over `Tests/**` finds nothing.
- **Fix direction:** one `NoteTextEditor` executor (`apply(_ edit: (String) throws -> MarkdownTextEdit?, to note: VaultPath, saving: SavePolicy) async throws -> NoteEditOutcome`) used by all three; the plan (the edit) stays in Core.

#### SRP-READING-07 `NoteLinksInspector` parses notes and queries the index from its view tasks
- **Severity:** Low
- **Evidence:** [MarkdownPane.swift:976-993](../../../Sources/GraphiteUI/MarkdownPane.swift#L976-L993), [1012-1040](../../../Sources/GraphiteUI/MarkdownPane.swift#L1012-L1040); 12 stored properties ([888-900](../../../Sources/GraphiteUI/MarkdownPane.swift#L888-L900)); declared in the note pane's file.
- **Why it matters:** the "show mentions only for the note they were found for" rule ([1009-1018](../../../Sources/GraphiteUI/MarkdownPane.swift#L1009-L1018)) and the link-then-remove flow (BUG-READING-04) are view code without tests.
- **Fix direction:** `NoteLinksInspectorModel` (`@Observable`) owning outline, links, tags, footnotes and mentions, with a "latest answer wins" load keyed by note path; the view only shows it. Own file.

#### SRP-READING-08 Property text parsing rules live in the UI target
- **Severity:** Low
- **Evidence:** `PropertyNumberText` ([PropertiesPanel.swift:435-494](../../../Sources/GraphiteUI/PropertiesPanel.swift#L435-L494)), `PropertyDateText` ([498-582](../../../Sources/GraphiteUI/PropertiesPanel.swift#L498-L582)), `PropertyValueKind.converted` ([392-428](../../../Sources/GraphiteUI/PropertiesPanel.swift#L392-L428)); Core's `NoteProperties` owns the YAML side.
- **Why it matters:** Bases' property editor needs the same rules (`UiSheetsEditorLogicTests` tests both, [UiSheetsEditorLogicTests.swift:135](../../../Tests/GraphiteUITests/UiSheetsEditorLogicTests.swift#L135)); keeping them in the UI target makes Core-level reuse impossible.
- **Fix direction:** move the three to Core beside `NoteProperties`, keeping the injected `now`, `locale` and `calendar`.

### O

#### OCP-READING-01 A new reading block kind touches six switches in one file, three hidden behind `default:`
- **Severity:** Medium
- **Evidence:** `RenderedBlock` cases ([MarkdownPreview.swift:46-75](../../../Sources/GraphiteUI/MarkdownPreview.swift#L46-L75)); `id` switch ([77-84](../../../Sources/GraphiteUI/MarkdownPreview.swift#L77-L84)); `render` ([391-424](../../../Sources/GraphiteUI/MarkdownPreview.swift#L391-L424)); `sourceTokens` with `default: break` ([346-355](../../../Sources/GraphiteUI/MarkdownPreview.swift#L346-L355)); `mediaLocations` with `default: break` ([1292-1296](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1292-L1296)); `containsMissingEmbed` with `default: false` ([1302-1306](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1302-L1306)); `blockView` ([1397-1503](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1397-L1503)). Outside the file: `NotePreviewDocument.Block` ([NotePreviewDocument.swift:13](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L13)) and Live Preview's block views ([LivePreviewWidgets.swift:167-214](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L167-L214)).
- **Why it matters:** a new kind that holds children (as `.callout` and `.transclusion` do) silently loses its media players, missing-embed rebuilds and Read Aloud tokens, because the three `default:` branches accept it.
- **Fix direction:** exhaustive switches (no `default:`), and a `children: [RenderedBlock]` accessor on `RenderedBlock` used by the three tree walks so containers are declared once.

#### OCP-READING-02 Callout type vocabulary is declared in four places
- **Severity:** Low
- **Evidence:** icons and colors [MarkdownPreview.swift:2531-2545](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2531-L2545); aliases and variables [VaultThemeTokens.swift:410-419](../../../Sources/GraphiteCore/VaultThemeTokens.swift#L410-L419); CSS [community-plugin-runtime.css:243](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/community-plugin-runtime.css#L243) and [graphite-default-variables.css:174](../../../Sources/GraphiteUI/Resources/CommunityPluginRuntime/graphite-default-variables.css#L174).
- **Why it matters:** `"note"` is in the Core table but falls to `default:` in `CalloutAppearance` (pencil icon, blue); a new alias added in one table and not the others draws with one color natively and another in plugin pages.
- **Fix direction:** one `ObsidianCalloutType` enum in Core (canonical type, aliases, CSS variable, symbol name) from which the Swift tables are derived and the CSS rule list is generated.

#### OCP-READING-03 Media extensions are listed twice, and the lists disagree
- **Severity:** Low
- **Evidence:** `MediaFileKind` video `mp4, mov, m4v, webm`, audio `m4a, mp3, wav, aac, ogg, flac, 3gp` ([MarkdownPreview.swift:232-235](../../../Sources/GraphiteUI/MarkdownPreview.swift#L232-L235)); `DocumentKind` media `m4a, mp4, mov, mp3, wav, aac` ([VaultPath.swift:168](../../../Sources/GraphiteCore/VaultPath.swift#L168)).
- **Why it matters:** an `.ogg` or `.m4v` embed plays inside a note, while the same file opened from the sidebar is classified `.other` by `DocumentKind`.
- **Fix direction:** one media classification in Core (`DocumentKind.media(MediaKind)` or a `MediaFileKind` there) used by both.

#### OCP-READING-04 `PropertyValue` is switched in six places of the properties editor, three with `default:`
- **Severity:** Low
- **Evidence:** [PropertiesPanel.swift:183-186](../../../Sources/GraphiteUI/PropertiesPanel.swift#L183-L186) (`default:`), [239-287](../../../Sources/GraphiteUI/PropertiesPanel.swift#L239-L287), [300-318](../../../Sources/GraphiteUI/PropertiesPanel.swift#L300-L318) (`default:`), [346-356](../../../Sources/GraphiteUI/PropertiesPanel.swift#L346-L356), [366-374](../../../Sources/GraphiteUI/PropertiesPanel.swift#L366-L374), [394-397](../../../Sources/GraphiteUI/PropertiesPanel.swift#L394-L397) (`default:`).
- **Why it matters:** a new value type compiles with no editor behaviour for commit and alignment.
- **Fix direction:** exhaustive switches; type metadata (symbol, title, alignment) as computed properties of `PropertyValueKind`.

#### OCP-READING-05 Inspector panels are declared in four places and the empty-state text names four of seven
- **Severity:** Low
- **Evidence:** enum [MarkdownPane.swift:936-950](../../../Sources/GraphiteUI/MarkdownPane.swift#L936-L950); `body` branch for graph/map [964-970](../../../Sources/GraphiteUI/MarkdownPane.swift#L964-L970); `panelContent` [1097-1170](../../../Sources/GraphiteUI/MarkdownPane.swift#L1097-L1170); text "Turn on Outline, Backlinks, Outgoing Links, or Tags View" [957](../../../Sources/GraphiteUI/MarkdownPane.swift#L957) while Footnotes, Graph and Map are also panels.
- **Why it matters:** the message misstates what the user can turn on; each new panel needs four edits.
- **Fix direction:** a panel descriptor (plugin, symbol, title, view) per case; the empty-state text built from the descriptors.

### L

#### LSP-READING-01 Reading view computes heading fold keys from rewritten text; `NoteFolding` from the source line
- **Severity:** High
- **Evidence:** reading key `"h\(level)|" + "#"×level + " " + text + "|" + occurrence` over the *prepared* heading text, twice: [MarkdownPreview.swift:1015-1018](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1015-L1018), [1368-1371](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1368-L1371); the text is prepared at [406](../../../Sources/GraphiteUI/MarkdownPreview.swift#L406). Editor key from the trimmed raw line [NoteFolding.swift:62](../../../Sources/GraphiteCore/NoteFolding.swift#L62). Shared set [MarkdownPane.swift:68-70](../../../Sources/GraphiteUI/MarkdownPane.swift#L68-L70). The comment at [1367](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1367) says "The editor's key: the heading line as written".
- **Why it matters:** wrong folding, wrong Read Aloud skipping and orphan keys persisted per device (BUG-READING-01). No test pins reading-view fold keys (`grep ReadingFolding|foldedKeys` over `Tests/**` finds only Core folding tests).
- **Fix direction:** one key function in Core (`NoteFolding.headingKey(rawLine:occurrence:)`), the raw heading line carried on `RenderedBlock.heading`, and the reading view asking `NoteFolding` for keys instead of formatting them.

#### LSP-READING-02 `CalloutView` keys its expansion by the displayed title in reading view and by the written title elsewhere
- **Severity:** Medium
- **Evidence:** `foldKeyTitle ?? title` ([MarkdownPreview.swift:2470](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2470)); reading view passes no `foldKeyTitle` ([1534-1536](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1534-L1536)) and a prepared title ([408-409](../../../Sources/GraphiteUI/MarkdownPreview.swift#L408-L409)); Live Preview passes the raw title ([LivePreviewWidgets.swift:272-277](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272-L277)); Read Aloud keys the raw title ([ReadAloudFolding.swift:43](../../../Sources/GraphiteCore/ReadAloudFolding.swift#L43)).
- **Why it matters:** BUG-READING-02.
- **Fix direction:** `RenderedBlock.callout` carries the written title; `CalloutView` takes a required `foldKey` computed by `ReadAloudFolding.calloutKey` at the call site, never a default.

#### LSP-READING-03 Two link resolvers with different answers
- **Severity:** Medium
- **Evidence:** builder [MarkdownPreview.swift:488-494](../../../Sources/GraphiteUI/MarkdownPreview.swift#L488-L494) (any existing path, folders included, written spelling); workspace [WorkspaceModel.swift:652-663](../../../Sources/GraphiteUI/WorkspaceModel.swift#L652-L663) (files only, stored spelling via `storedPath(for:)`). Live Preview embeds use the workspace one ([MarkdownPane.swift:344](../../../Sources/GraphiteUI/MarkdownPane.swift#L344), [LivePreviewWidgets.swift:589](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L589)).
- **Why it matters:** BUG-READING-03; a link drawn as resolved in reading view is followed by the other resolver.
- **Fix direction:** one resolver (Core function over a `fileKind(at:)` lookup and the index) used by the builder, the workspace and Live Preview.

#### LSP-READING-04 Wikilink display text is computed by two rules
- **Severity:** Medium
- **Evidence:** reading view `displayText(for:)` gives alias, else `Note > Heading`, drops `.md` and `^` ([MarkdownPreview.swift:626-633](../../../Sources/GraphiteUI/MarkdownPreview.swift#L626-L633)); Live Preview's rendered blocks label with `alias ?? target` minus a leading `#` ([LivePreviewWidgets.swift:438-445](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L438-L445)), with its own regular expression ([428](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L428)) instead of `MarkdownSemantics`.
- **Why it matters:** BUG-READING-05.
- **Fix direction:** one `LinkDisplayText.label(for:)` in Core used by both rewriters; one rewriter (`ReadingLinkRewriter`) for reading view and Live Preview blocks.

#### LSP-READING-05 `NoteThemeStyle` equality ignores one of its inputs
- **Severity:** Low
- **Evidence:** `==` compares `tokens.fingerprint` only ([NoteThemeStyle.swift:107](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L107)); `init` also takes `graphiteAccent`, used as the fallback of 9 colors ([146-172](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L146-L172)); `applyNoteTheme` skips an "equal" style ([WorkspaceTheme.swift:58-60](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L58-L60)).
- **Why it matters:** today the fingerprint includes the accent's HSL text ([ThemeTokenResolver.swift:22](../../../Sources/GraphiteUI/ThemeTokenResolver.swift#L22), [WorkspaceTheme.swift:38-40](../../../Sources/GraphiteUI/WorkspaceTheme.swift#L38-L40)), so the two agree by coincidence; an accent whose hex does not parse to HSL leaves `accentStyle` empty for every such accent, and a new style with a different fallback accent is then discarded as "equal".
- **Fix direction:** include the fallback accent in equality, or compute equality from all stored inputs.

#### LSP-READING-06 Block identity is positional, and build equality is a hash
- **Severity:** Low
- **Evidence:** `"block-\(id)"` from a per-build counter assigned in post-order ([MarkdownPreview.swift:77-84](../../../Sources/GraphiteUI/MarkdownPreview.swift#L77-L84), [360](../../../Sources/GraphiteUI/MarkdownPreview.swift#L360), [411-414](../../../Sources/GraphiteUI/MarkdownPreview.swift#L411-L414)); `ForEach(visibleBlocks, id: \.block.id)` ([1389](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1389)); `ReadingBuildKey.renderingHash = configuration.hashValueForReload` compared for equality ([1251](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1251), [1266](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1266), [1313-1323](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1313-L1323)).
- **Why it matters:** inserting one block near the top gives every later block a new identity, so SwiftUI rebuilds every row after an edit and `ReadingPosition` forgets their frames; a hash collision between two configurations shows a stale build.
- **Fix direction:** identity from the block's source location and kind (stable across edits elsewhere); `ReadingBuildKey` stores the configuration fields it depends on (an `Equatable` sub-struct), not their hash.

### I

#### ISP-READING-01 The note pane and the inspector take the whole `WorkspaceModel`
- **Severity:** Medium
- **Evidence:** [MarkdownPane.swift:9](../../../Sources/GraphiteUI/MarkdownPane.swift#L9), [890](../../../Sources/GraphiteUI/MarkdownPane.swift#L890), [846](../../../Sources/GraphiteUI/MarkdownPane.swift#L846); 38 members used by `MarkdownPane` (method in §3.3); writes to workspace fields at [116](../../../Sources/GraphiteUI/MarkdownPane.swift#L116), [365-366](../../../Sources/GraphiteUI/MarkdownPane.swift#L365-L366), [558](../../../Sources/GraphiteUI/MarkdownPane.swift#L558), [1104](../../../Sources/GraphiteUI/MarkdownPane.swift#L1104), [1164](../../../Sources/GraphiteUI/MarkdownPane.swift#L1164).
- **Why it matters:** the pane cannot be previewed or tested without a full workspace with a vault; any workspace change re-evaluates the pane's dependencies.
- **Fix direction:** the pane receives `NoteCommands` (link following, imports, drawings), a `NoteDisplaySettings` value, the Read Aloud model and the inspector model; `WorkspaceModel` builds them.

#### ISP-READING-02 Panes write the window's Read Aloud navigator directly; the last writer wins
- **Severity:** Medium
- **Evidence:** reading view sets `visibleLocation` and `supportsTapToRead` on mode change ([MarkdownPane.swift:133-139](../../../Sources/GraphiteUI/MarkdownPane.swift#L133-L139)); the editor's hooks set the same fields and the highlight frame ([591-598](../../../Sources/GraphiteUI/MarkdownPane.swift#L591-L598)).
- **Why it matters:** with two notes side by side, the navigator answers "where is the reader" with the closure of whichever pane changed mode last, not of the note being read; nothing clears it when the pane goes away.
- **Fix direction:** the navigator asks for the visible location of the note it reads (`visibleLocation(for path:)` registered per note and removed on disappear), instead of one shared closure.

#### ISP-READING-03 The builder takes a whole `VaultIndex` for one call and threads five parameters through every helper
- **Severity:** Low
- **Evidence:** `index` used only at [MarkdownPreview.swift:492](../../../Sources/GraphiteUI/MarkdownPreview.swift#L492); `note, root, index, configuration` passed through `render`, `renderEmbed`, `prepared`, `resolve` ([387](../../../Sources/GraphiteUI/MarkdownPreview.swift#L387), [441](../../../Sources/GraphiteUI/MarkdownPreview.swift#L441), [488](../../../Sources/GraphiteUI/MarkdownPreview.swift#L488), [502](../../../Sources/GraphiteUI/MarkdownPreview.swift#L502)).
- **Why it matters:** tests must build a real index ([UiReadingTaskTests.swift:53](../../../Tests/GraphiteUITests/UiReadingTaskTests.swift#L53)); signatures carry six parameters.
- **Fix direction:** the `ReadingFileLookup` port (§3.2) and per-build context stored in the builder's `BuildState`.

### D

#### DIP-READING-01 The reading builder and image cache construct their own file services
- **Severity:** Medium
- **Evidence:** `ImageFileService()` [MarkdownPreview.swift:261](../../../Sources/GraphiteUI/MarkdownPreview.swift#L261), [2693](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2693); `AtomicFileWriter()` [458](../../../Sources/GraphiteUI/MarkdownPreview.swift#L458); `FileManager.default` [490](../../../Sources/GraphiteUI/MarkdownPreview.swift#L490), [2685](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2685); also `ImageFileService()` in [FilePreviewPane.swift:125](../../../Sources/GraphiteUI/FilePreviewPane.swift#L125) and [220](../../../Sources/GraphiteUI/FilePreviewPane.swift#L220).
- **Why it matters:** the reading view reads embedded notes outside `VaultStore` (no coordinated read, no security-scope check beyond `path.url(in:)`), and no test can substitute a slow, failing or cloud-placeholder file.
- **Fix direction:** inject `ReadingFileLookup` and an `ImageDecoding` capability from the composition root; embedded notes read through `VaultStore`.

#### DIP-READING-02 `ReadingImageCache.shared` is a process-wide singleton reached from views
- **Severity:** Medium
- **Evidence:** [MarkdownPreview.swift:2651](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2651); uses [2571](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2571), [3001](../../../Sources/GraphiteUI/MarkdownPreview.swift#L3001), [3015](../../../Sources/GraphiteUI/MarkdownPreview.swift#L3015), [LivePreviewWidgets.swift:582](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L582), [601](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L601); tests use the shared instance too ([UiLivePreviewEmbedContinuityTests.swift:77](../../../Tests/GraphiteUITests/UiLivePreviewEmbedContinuityTests.swift#L77)).
- **Why it matters:** memory-warning and vault-switch cleanup cannot reach it through a declared owner; hosted tests share cached thumbnails between cases.
- **Fix direction:** one instance created by the composition root and passed through the environment (`@Entry var readingImageCache`); keep its `init(totalCostLimit:)` for tests.

#### DIP-READING-03 Folds and inspector choices are stored through `UserDefaults.standard` from feature code
- **Severity:** Medium
- **Evidence:** [WorkspaceFolds.swift:14](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L14), [18](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L18); `@AppStorage("GraphiteInspectorPanel")`, `@AppStorage("GraphiteShowsUnlinkedMentions")` [MarkdownPane.swift:891](../../../Sources/GraphiteUI/MarkdownPane.swift#L891), [895](../../../Sources/GraphiteUI/MarkdownPane.swift#L895); `@AppStorage` keys in [DocumentModeToggle.swift:159-160](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L159-L160).
- **Why it matters:** each fold toggle reads and rewrites the whole vault's fold dictionary from the shared defaults ([WorkspaceFolds.swift:26-31](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L26-L31)); tests of folds would write the developer's real defaults; the keys are not in one registry.
- **Fix direction:** a `FoldStore` (like `DocumentPlaceStore`, which the workspace already injects per `Architecture.md:126`) holding a vault's folds in memory and writing on change, constructed with a defaults instance; keys declared in a typed registry.

#### DIP-READING-04 Platform singletons and static mutable caches in view logic
- **Severity:** Low
- **Evidence:** `UIDevice.current` [MarkdownPane.swift:413](../../../Sources/GraphiteUI/MarkdownPane.swift#L413); `UIImagePickerController.isSourceTypeAvailable` [239](../../../Sources/GraphiteUI/MarkdownPane.swift#L239), [459](../../../Sources/GraphiteUI/MarkdownPane.swift#L459); `UIPasteboard.general` [FilePreviewPane.swift:421](../../../Sources/GraphiteUI/FilePreviewPane.swift#L421), [424](../../../Sources/GraphiteUI/FilePreviewPane.swift#L424); static mutable `familiesByLowercasedName` [NoteTypography.swift:15](../../../Sources/GraphiteUI/NoteTypography.swift#L15) and `cachedFormatters` [PropertiesPanel.swift:566](../../../Sources/GraphiteUI/PropertiesPanel.swift#L566).
- **Why it matters:** small; the two static caches are main-actor isolated and bounded, which is sound. The device checks make toolbar layout untestable on the Mac.
- **Fix direction:** read device capabilities once into an environment value; keep the two caches (documented, bounded) but declare them in the allow-listed primitives file the rules call for.

### Clean code

#### CC-READING-01 Eighteen functions exceed 40 code lines
- **Severity:** Medium
- **Evidence:** reconnaissance list (Appendix), confirmed by reading: `MarkdownPreview.body` 127 ([814](../../../Sources/GraphiteUI/MarkdownPreview.swift#L814)), `NoteThemeStyle.init` 122 ([NoteThemeStyle.swift:124](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L124)), `MarkdownPane.body` 109 ([MarkdownPane.swift:57](../../../Sources/GraphiteUI/MarkdownPane.swift#L57)), `ReadingBlocksView.blockView` 105 ([MarkdownPreview.swift:1395](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1395)).
- **Why it matters:** `blockView` is the 17-case switch every block change edits; `body` holds four async flows.
- **Fix direction:** one view per block kind (`ReadingHeadingBlock`, `ReadingTransclusionBlock`, `ReadingFootnotesBlock`, …) chosen by an exhaustive switch of one line per case; `NoteThemeStyle.init` split by the theme groups of §3.4.

#### CC-READING-02 Sleeps are used as layout ordering
- **Severity:** Medium
- **Evidence:** `scrollToTop` scrolls, sleeps 50 ms, then reads the block frame ([MarkdownPreview.swift:963-967](../../../Sources/GraphiteUI/MarkdownPreview.swift#L963-L967)); Read Aloud following scrolls and sleeps 80 ms up to three times waiting for a highlight frame ([987-992](../../../Sources/GraphiteUI/MarkdownPreview.swift#L987-L992)); `Coverage.md:284` records a flaky reading-position test. Other sleeps are debounces: 900 ms autosave ([MarkdownPane.swift:672](../../../Sources/GraphiteUI/MarkdownPane.swift#L672)), 150 ms ([705](../../../Sources/GraphiteUI/MarkdownPane.swift#L705), [877](../../../Sources/GraphiteUI/MarkdownPane.swift#L877), [MarkdownPreview.swift:942](../../../Sources/GraphiteUI/MarkdownPreview.swift#L942)), 250 ms ([MarkdownPane.swift:978](../../../Sources/GraphiteUI/MarkdownPane.swift#L978)), 300 ms ([781](../../../Sources/GraphiteUI/MarkdownPane.swift#L781)). Total 8 (`Task.sleep` grep).
- **Why it matters:** on a slow iPad the frame is not laid out after 50 ms and the note opens a few lines off; timing-based layout is the source of the flaky test.
- **Fix direction:** react to the block's reported frame (`ReadingBlockPositionReporter` already reports it, [1557-1561](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1557-L1561)) instead of sleeping; debounces use one named-duration debouncer.

#### CC-READING-03 `body` writes state
- **Severity:** Low
- **Evidence:** `let _ = blockActions.update(...)` inside the `LazyVStack` builder ([MarkdownPreview.swift:825-828](../../../Sources/GraphiteUI/MarkdownPreview.swift#L825-L828)); the reason is recorded at [1173-1176](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1173-L1176).
- **Why it matters:** correctness depends on SwiftUI evaluating that line before any tap; it is a hidden ordering rule (§3.1 rule 7).
- **Fix direction:** make the closures stable by construction (capture the session and workspace commands once in `ReadingBlockActions.init`, built by the pane), so nothing is assigned during `body`. The "body never writes state" rule holds; this design is the performance workaround it should replace.

#### CC-READING-04 Failed index reads become empty lists
- **Severity:** Medium
- **Evidence:** `(try? await index.backlinks(to: note)) ?? []` ([WorkspaceMentions.swift:27](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L27)); `guard let page = try? await index.search(...) else { return [] }` ([47](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L47)); `(try? Mentions.linkCandidates(...)) ?? []` ([32](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L32)); `(try? await index?.fileCount(named:)) ?? 0` makes an unknown count mean "unique" ([64-65](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L64-L65)); unreadable notes skipped silently ([30](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L30), [50](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L50)). 32 `try?` in scope (reconnaissance).
- **Why it matters:** the Backlinks panel says "No other notes link here" when the index failed; a failed count writes a bare-name link that can point at another note of the same name.
- **Fix direction:** the mention queries return `Result`/throw; the inspector model shows "Backlinks could not be read" distinctly from empty; `linkTarget` asks for a path-qualified link when the count is unknown.

#### CC-READING-05 Outcomes travel through `errorMessage` with raw error text
- **Severity:** Medium
- **Evidence:** 16 `localizedDescription` sites in scope (grep `localizedDescription`, filtered to the 14 files): [MarkdownPreview.swift:952](../../../Sources/GraphiteUI/MarkdownPreview.swift#L952), [MarkdownPane.swift:154](../../../Sources/GraphiteUI/MarkdownPane.swift#L154), [159](../../../Sources/GraphiteUI/MarkdownPane.swift#L159), [637](../../../Sources/GraphiteUI/MarkdownPane.swift#L637), [656](../../../Sources/GraphiteUI/MarkdownPane.swift#L656), [675](../../../Sources/GraphiteUI/MarkdownPane.swift#L675), [880](../../../Sources/GraphiteUI/MarkdownPane.swift#L880), [985](../../../Sources/GraphiteUI/MarkdownPane.swift#L985), [FilePreviewPane.swift:127](../../../Sources/GraphiteUI/FilePreviewPane.swift#L127), [223](../../../Sources/GraphiteUI/FilePreviewPane.swift#L223), [WorkspaceMentions.swift:84](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L84), [WorkspaceReadingTasks.swift:15](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L15), [28](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L28), [WorkspaceTagsAndProperties.swift:51](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L51), [88](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L88), [101](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L101). `linkMention` returns `Void` ([WorkspaceMentions.swift:61](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L61)).
- **Why it matters:** callers cannot tell success from failure (BUG-READING-04); messages from Foundation reach the user unchanged.
- **Fix direction:** typed outcomes returned to the caller (`NoteEditOutcome`, `PropertyRenameReport`), one presenter that turns them into words.

#### CC-READING-06 Unowned tasks started from views
- **Severity:** Low
- **Evidence:** 38 `Task {` in scope (reconnaissance); for example [MarkdownPane.swift:154](../../../Sources/GraphiteUI/MarkdownPane.swift#L154), [167](../../../Sources/GraphiteUI/MarkdownPane.swift#L167), [995](../../../Sources/GraphiteUI/MarkdownPane.swift#L995), [1031](../../../Sources/GraphiteUI/MarkdownPane.swift#L1031), [ReadingTaskCheckbox.swift:51](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift#L51), [MarkdownPreview.swift:2919](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2919).
- **Why it matters:** an unlinked-mention load started at [995](../../../Sources/GraphiteUI/MarkdownPane.swift#L995) is not cancelled when the note changes; its result is guarded by a path check ([1026](../../../Sources/GraphiteUI/MarkdownPane.swift#L1026)), which is the ad-hoc "latest answer wins" the rules want as one primitive.
- **Fix direction:** model methods own their tasks; one `LatestTask` primitive cancels the previous load.

#### CC-READING-07 Incident history and stale or misplaced comments
- **Severity:** Low
- **Evidence:** dated incidents [MarkdownPreview.swift:1232-1236](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1232-L1236), [NoteTypography.swift:25-27](../../../Sources/GraphiteUI/NoteTypography.swift#L25-L27), [DocumentModeToggle.swift:93-96](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L93-L96); "seen while this was written" [MarkdownPreview.swift:1194-1197](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1194-L1197). Stale: "Graphite does not write `types.json`" [PropertiesPanel.swift:389](../../../Sources/GraphiteUI/PropertiesPanel.swift#L389). Misplaced: the conflict banner documented as "Link and tag suggestions" [MarkdownPane.swift:178](../../../Sources/GraphiteUI/MarkdownPane.swift#L178); `viewImage` documented as "Opens a drawing in the editor" [361-362](../../../Sources/GraphiteUI/MarkdownPane.swift#L361-L362); two stacked doc comments on `WordCountDisplay` [749-754](../../../Sources/GraphiteUI/MarkdownPane.swift#L749-L754); `ReadingFolding` carries the comment of `ReadingBlocksView` [MarkdownPreview.swift:1326-1328](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1326-L1328); `CalloutView.foldKeyTitle` "The title as written in the note" is false in reading view [2452](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2452).
- **Why it matters:** a reader trusting [PropertiesPanel.swift:389](../../../Sources/GraphiteUI/PropertiesPanel.swift#L389) or [2452](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2452) reasons wrongly about persistence and folding.
- **Fix direction:** present-tense rules only; incident history into commit messages and test names; fix the five misplaced comments.

#### CC-READING-08 Duplicated small rules
- **Severity:** Low
- **Evidence:** Write binding twice ([MarkdownPane.swift:614-618](../../../Sources/GraphiteUI/MarkdownPane.swift#L614-L618), [DocumentModeToggle.swift:169-171](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L169-L171)); file version by modification date and size twice ([FilePreviewPane.swift:99-108](../../../Sources/GraphiteUI/FilePreviewPane.swift#L99-L108), [MarkdownPreview.swift:2685-2690](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2685-L2690)); embedded note decoded with `String(data:encoding:)` ([458-459](../../../Sources/GraphiteUI/MarkdownPreview.swift#L458-L459)) instead of `NoteTextEncoding.decode` ([MarkdownSession.swift:470-474](../../../Sources/GraphiteUI/MarkdownSession.swift#L470-L474)); property `[[link|alias]]` parsing by string slicing ([PropertiesPanel.swift:633-641](../../../Sources/GraphiteUI/PropertiesPanel.swift#L633-L641)) beside Core's link parser; property checkbox drawn without the theme ([241-249](../../../Sources/GraphiteUI/PropertiesPanel.swift#L241-L249)) while tasks use `ThemedCheckboxShape`.
- **Why it matters:** each pair drifts (two already have: fold keys and link labels, see LSP).
- **Fix direction:** one owner per rule; delete the second copy.

#### CC-READING-09 Magic durations and thresholds
- **Severity:** Low
- **Evidence:** [MarkdownPane.swift:672](../../../Sources/GraphiteUI/MarkdownPane.swift#L672) (900 ms), [705](../../../Sources/GraphiteUI/MarkdownPane.swift#L705), [877](../../../Sources/GraphiteUI/MarkdownPane.swift#L877), [978](../../../Sources/GraphiteUI/MarkdownPane.swift#L978); [MarkdownPreview.swift:998-1002](../../../Sources/GraphiteUI/MarkdownPreview.swift#L998-L1002) (80, 40, 120 pt); [2860](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2860) (1,600 px poster); [2918](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2918) (0.5 s observer); [MarkdownPane.swift:645](../../../Sources/GraphiteUI/MarkdownPane.swift#L645) (JPEG 0.85); [1182](../../../Sources/GraphiteUI/MarkdownPane.swift#L1182) (48 pt row). Counter-examples done right: `WordCountDisplay.typingPause` ([761](../../../Sources/GraphiteUI/MarkdownPane.swift#L761)), `DocumentToolbarLayout` thresholds ([DocumentModeToggle.swift:77-123](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L77-L123)).
- **Why it matters:** the autosave delay is a product rule hidden in a view.
- **Fix direction:** named constants with units beside their owner.

#### CC-READING-10 Dead code and test names after fix rounds
- **Severity:** Low
- **Evidence:** `CalloutFoldScope` is declared and never used ([CalloutFoldStore.swift:24-27](../../../Sources/GraphiteUI/CalloutFoldStore.swift#L24-L27); `grep CalloutFoldScope` over `Sources/**` finds only the declaration). Tests that pin this area are named after rounds: `UiMarkdownPaneFixTests`, `BugFixRegressionTests`, `UiEditorAreaHandoffTests`, `UiSheetsEditorLogicTests` ([UiMarkdownPaneFixTests.swift:351](../../../Tests/GraphiteUITests/UiMarkdownPaneFixTests.swift#L351), [BugFixRegressionTests.swift:16](../../../Tests/GraphiteUITests/BugFixRegressionTests.swift#L16), [UiEditorAreaHandoffTests.swift:52](../../../Tests/GraphiteUITests/UiEditorAreaHandoffTests.swift#L52), [UiSheetsEditorLogicTests.swift:13](../../../Tests/GraphiteUITests/UiSheetsEditorLogicTests.swift#L13)).
- **Why it matters:** a reader cannot find the tests of `NoteTextCounts`, `NoteFontSize` or `PropertyListEditing` by type name.
- **Fix direction:** delete `CalloutFoldScope`; rename/move tests to `<ProductionType>Tests`.

## 5. Defects and latent bugs

#### BUG-READING-01 A heading whose text reading view rewrites folds differently in reading view and in the editor, and Read Aloud reads a section folded in reading view
- **Trigger:** a note has a heading the reading build changes: a link (`## See [[Plan]]`), a highlight (`## ==Key== idea`), a closing sequence (`## Title ##`) or extra spaces (`##  Title`). The user folds it in Live Preview, or uses More › Fold All, then switches to reading view; or folds it in reading view and then reads the note aloud or switches to writing.
- **Path:**
  1. The pane shares one fold set between both views: [MarkdownPane.swift:68-70](../../../Sources/GraphiteUI/MarkdownPane.swift#L68-L70).
  2. The editor and Fold All key a heading by its trimmed source line: [NoteFolding.swift:62](../../../Sources/GraphiteCore/NoteFolding.swift#L62), [MarkdownSession.swift:306-308](../../../Sources/GraphiteUI/MarkdownSession.swift#L306-L308). For `## Title ##` the key is `h2|## Title ##|0`.
  3. Reading view's heading text is the regex's group 2 without the closing hashes ([NotePreviewDocument.swift:30](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L30), [NotePreviewDocument.swift:154-156](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L154-L156)), then rewritten by `prepared` ([MarkdownPreview.swift:406](../../../Sources/GraphiteUI/MarkdownPreview.swift#L406)), which turns `[[Plan]]` into `[Plan](graphite://open?target=Plan)` ([553-560](../../../Sources/GraphiteUI/MarkdownPreview.swift#L553-L560)) and highlights into private-use markers ([571-575](../../../Sources/GraphiteUI/MarkdownPreview.swift#L571-L575)).
  4. Reading view builds its key from that text: [MarkdownPreview.swift:1368-1371](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1368-L1371) → `h2|## Title|0`, or `h2|## See [Plan](graphite://open?target=Plan)|0`.
  5. The two keys never match, so `visibleBlocks` shows the section the editor folded ([1373-1383](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1373-L1383)), and a fold made in reading view inserts a key no `NoteFolding` region has ([1227](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1227), [MarkdownPane.swift:68-70](../../../Sources/GraphiteUI/MarkdownPane.swift#L68-L70)).
  6. Read Aloud hides only regions whose `NoteFolding` key is in the set ([MarkdownPane.swift:602-605](../../../Sources/GraphiteUI/MarkdownPane.swift#L602-L605), [ReadAloudFolding.swift:17](../../../Sources/GraphiteCore/ReadAloudFolding.swift#L17)), so the section folded in reading view is read aloud; a jump to a heading inside it does not unfold it ([MarkdownSession.swift:301-303](../../../Sources/GraphiteUI/MarkdownSession.swift#L301-L303)).
  7. The orphan key is persisted per vault on the device ([WorkspaceFolds.swift:26-31](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L26-L31)) and is removed only when the note is deleted ([48-54](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L48-L54)) or Unfold All runs.
- **Effect:** folding does not carry between views for such headings (contrary to `Architecture.md:128`); Read Aloud reads text the user folded away in reading view; an outline jump to a heading inside a section folded in reading view does nothing visible, because the target block is not in the lazy stack.
- **Platforms / reach:** iPad, iPhone, Mac; normal path, any heading with a link, highlight, color, closing hashes or repeated spaces. Headings inside `%%` comments also shift occurrence numbers, since reading view removes comments first and `NoteFolding` does not.
- **Confidence:** Traced.

#### BUG-READING-02 A callout expanded or collapsed in reading view keeps a different state in Live Preview and in Read Aloud when its title has markup
- **Trigger:** a callout like `> [!note]- See [[Plan]]` or `> [!tip]- ==Key== point` (title with a link, highlight or color). The user expands it in reading view and starts Read Aloud, or switches to Live Preview.
- **Path:**
  1. Reading view prepares the title ([MarkdownPreview.swift:408-409](../../../Sources/GraphiteUI/MarkdownPreview.swift#L408-L409)) and stores the prepared title in the block ([414](../../../Sources/GraphiteUI/MarkdownPreview.swift#L414)).
  2. `ReadingCallout` passes it to `CalloutView` without `foldKeyTitle` ([1440-1441](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1440-L1441), [1534-1536](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1534-L1536)), so the key title is the prepared text ([2470](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2470)).
  3. The expansion is stored under `note|<prepared title>` ([2447-2449](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2447-L2449), [CalloutFoldStore.swift:18-20](../../../Sources/GraphiteUI/CalloutFoldStore.swift#L18-L20)).
  4. Live Preview keys the same callout by the written title ([LivePreviewWidgets.swift:272-277](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272-L277)); Read Aloud by the written header title ([ReadAloudFolding.swift:43-44](../../../Sources/GraphiteCore/ReadAloudFolding.swift#L43-L44)), passed from the pane ([MarkdownPane.swift:602-605](../../../Sources/GraphiteUI/MarkdownPane.swift#L602-L605)).
  5. Neither finds the reading-view entry and both fall back to the `-` marker: collapsed.
- **Effect:** the user opens a folded callout in reading view, presses Read Document, and its body is skipped although it is on screen; switching to Live Preview shows it folded again. The reverse holds for a `+` callout collapsed in reading view (its body is read).
- **Platforms / reach:** iPad, iPhone, Mac; normal path for callouts whose title contains markup that `prepared` rewrites.
- **Confidence:** Traced.

#### BUG-READING-03 Reading view takes a folder for the target of a link or embed
- **Trigger:** a note contains `![[Projects]]` or `[[Projects]]` and a folder `Projects` exists beside the note or at the vault root, with no `Projects.md`.
- **Path:**
  1. `WikiLinkResolver.directCandidates` yields `Projects.md` and then `Projects` ([MarkdownSemantics.swift:873-875](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L873-L875), [898-901](../../../Sources/GraphiteCore/MarkdownSemantics.swift#L898-L901)).
  2. The builder accepts any existing path, folders included ([MarkdownPreview.swift:489-491](../../../Sources/GraphiteUI/MarkdownPreview.swift#L489-L491)); the workspace resolver refuses folders ([WorkspaceModel.swift:656-659](../../../Sources/GraphiteUI/WorkspaceModel.swift#L656-L659)).
  3. Embed: `renderEmbed` finds the folder, `DocumentKind` of an extensionless path is `.other` ([VaultPath.swift:169](../../../Sources/GraphiteCore/VaultPath.swift#L169)), so the `default:` branch rewrites it as Markdown ([MarkdownPreview.swift:476-478](../../../Sources/GraphiteUI/MarkdownPreview.swift#L476-L478)); `prepared` resolves the folder again and writes a link to it ([535](../../../Sources/GraphiteUI/MarkdownPreview.swift#L535), [542-548](../../../Sources/GraphiteUI/MarkdownPreview.swift#L542-L548)).
  4. Link with a vault theme: `marksUnresolvedLinks` checks `resolve(...) == nil` ([556-558](../../../Sources/GraphiteUI/MarkdownPreview.swift#L556-L558)); the folder makes it non-nil, so the link is drawn as resolved.
- **Effect:** reading view shows a link named "Projects" where Live Preview shows the embed as missing ([LivePreviewWidgets.swift:589-592](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L589-L592)); with a theme, a link that creates a new note when tapped (`WorkspaceModel.follow`, [WorkspaceModel.swift:656-657](../../../Sources/GraphiteUI/WorkspaceModel.swift#L656-L657) comment) is colored as an existing note.
- **Platforms / reach:** iPad, iPhone, Mac; normal path, vaults with a note link named like a folder (common for course folders).
- **Confidence:** Traced (rendering); what the tap on the folder link then does was not traced past `navigate`.

#### BUG-READING-04 "Link" on an unlinked mention removes the line from the list even when no link was written
- **Trigger:** in the Backlinks panel, the user taps Link on an unlinked mention after the mentioning note changed (another app, typing in another tab) or when its save fails.
- **Path:**
  1. `linkMention` (view) awaits `workspace.linkMention` and then filters the match out unconditionally ([MarkdownPane.swift:1030-1039](../../../Sources/GraphiteUI/MarkdownPane.swift#L1030-L1039)).
  2. `workspace.linkMention` returns `Void`; on a changed note it throws `mentionChanged` internally ([WorkspaceMentions.swift:71](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L71), [78](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L78)), and on a failed save the store throws; both are caught and turned into `errorMessage` ([84](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L84)).
- **Effect:** an alert says the note changed, and the mention disappears from Unlinked mentions although nothing was linked; it comes back only when the panel reloads (index version change, [MarkdownPane.swift:989](../../../Sources/GraphiteUI/MarkdownPane.swift#L989), or toggling the section).
- **Platforms / reach:** iPad, iPhone, Mac; failure path only.
- **Confidence:** Traced.

#### BUG-READING-05 The same Wikilink reads differently in reading view and in Live Preview's rendered blocks
- **Trigger:** a callout title, table cell or other rendered block in Live Preview contains `[[Lecture 3#Proof]]`, `[[Note.md]]` or `[[Note#^block]]`.
- **Path:**
  1. Reading view labels a Wikilink with `displayText(for:)`: `Lecture 3 > Proof`, `Note`, `Note > block` ([MarkdownPreview.swift:626-633](../../../Sources/GraphiteUI/MarkdownPreview.swift#L626-L633), used at [560](../../../Sources/GraphiteUI/MarkdownPreview.swift#L560)).
  2. Live Preview's rendered blocks go through `LivePreviewText.prepared` ([LivePreviewWidgets.swift:272](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L272), [376](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L376)), which labels with `alias ?? target` minus only a leading `#` ([438-445](../../../Sources/GraphiteUI/LivePreviewWidgets.swift#L438-L445)): `Lecture 3#Proof`, `Note.md`, `Note#^block`.
- **Effect:** a table or callout shows raw link syntax in Live Preview and Obsidian-style text in reading view; the text moves when the note switches views.
- **Platforms / reach:** iPad, iPhone, Mac; normal path in Live Preview's rendered blocks.
- **Confidence:** Traced.

## 6. What to keep

| Design | Evidence | Why it is sound |
| --- | --- | --- |
| Task ticks land only where the task still is | `ReadingTasks.Location` passed from the build ([MarkdownPreview.swift:392-396](../../../Sources/GraphiteUI/MarkdownPreview.swift#L392-L396)); tick through the session, the open embedded session, or a revision-checked rewrite ([WorkspaceReadingTasks.swift:9-31](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L9-L31)); optimistic checkbox reverts on `false` and resets when the task changes ([ReadingTaskCheckbox.swift:49-53](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift#L49-L53), [67](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift#L67)) | A tap on an out-of-date drawing changes nothing instead of another task; pinned by `UiReadingTaskTests.testTapOnAnOlderDrawingOfAChangedNoteChangesNothing` ([UiReadingTaskTests.swift:201](../../../Tests/GraphiteUITests/UiReadingTaskTests.swift#L201)). |
| Closed-file writes keep revision and byte-order mark | [WorkspaceMentions.swift:75-82](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L75-L82), [WorkspaceReadingTasks.swift:20-24](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L20-L24), [WorkspaceTagsAndProperties.swift:78-84](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L78-L84) | Never overwrites an external edit; bytes the user did not change stay (OBJECTIVE.md "never silently overwrite"). Keep the behaviour when the three copies become one. |
| Property rename reports what it could not do | saves open documents first, collects per-note reasons, moves the `types.json` entry only when something was renamed ([WorkspaceTagsAndProperties.swift:58-102](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L58-L102)) | Partial success is visible and nothing is half-renamed silently. |
| A mention is re-checked before linking | `mentionIsStill` compares the words at the range with the excerpt ([WorkspaceMentions.swift:91-97](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L91-L97)); results kept only for the note they were found for ([MarkdownPane.swift:1012-1028](../../../Sources/GraphiteUI/MarkdownPane.swift#L1012-L1028)) | Prevents writing a link into the wrong words or the wrong note. |
| Read Aloud word updates are confined | `ReadingWordSource`/`ReadingWordTracker` ([MarkdownPreview.swift:1058-1078](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1058-L1078)); per-text `ReadingWordCell` with binary search ([1100-1171](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1100-L1171)); `ObsidianMarkdownTextContent` equality without closures ([1696-1701](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1696-L1701)) | Measured: under 1 ms per word on a 0.8 MB note (`Architecture.md:307`). Any refactor must keep "only two texts update per word". |
| Build request compared, not hashed; blocks view compared by value and not `.equatable()` | [MarkdownPreview.swift:1192-1243](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1192-L1243) | Hashing the note at every update stalled the main thread; `.equatable()` made the lazy stack build every block. |
| Build cache per session | `ReadingBlocksCache` owned by `MarkdownSession` ([MarkdownSession.swift:115](../../../Sources/GraphiteUI/MarkdownSession.swift#L115)); reused only when `ReadingBuildKey.describesBuild` ([MarkdownPreview.swift:932-936](../../../Sources/GraphiteUI/MarkdownPreview.swift#L932-L936), [1264-1268](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1264-L1268)) | Switching from writing to reading shows the note at once; pinned by `testBuildKeyDescribesOnlyAnEqualBuild` ([UiReadingViewTests.swift:283](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L283)). |
| Reading place as a note offset | `ReadingPosition.topLocation` / `block(containing:)` ([MarkdownPreview.swift:697-731](../../../Sources/GraphiteUI/MarkdownPreview.swift#L697-L731)); session hands each view the other's place once ([MarkdownSession.swift:44-55](../../../Sources/GraphiteUI/MarkdownSession.swift#L44-L55)) | The note keeps its place across view switches and relaunch; pinned by `testTheReadingViewKnowsWhichCharacterOfTheNoteIsAtItsTop` ([UiReadingViewTests.swift:464](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L464)). |
| One vocabulary for Graphite's private links and image fragments | `GraphiteOpenLink` encodes and decodes `graphite://open?target=…&markdown=1&unresolved=1` and `footnote=` ([MarkdownPreview.swift:125-195](../../../Sources/GraphiteUI/MarkdownPreview.swift#L125-L195)), parentheses percent-encoded ([159-161](../../../Sources/GraphiteUI/MarkdownPreview.swift#L159-L161)); `PreviewImageFragment` ([96-120](../../../Sources/GraphiteUI/MarkdownPreview.swift#L96-L120)) | Encoder and decoder live together; tests pin unbalanced parentheses and trailing backslashes ([UiReadingViewTests.swift:128-140](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L128-L140)). |
| A note's private-use characters survive the marker rewrite | `ReadingMarkerEscaping` ([MarkdownPreview.swift:201-230](../../../Sources/GraphiteUI/MarkdownPreview.swift#L201-L230)) and restoration after parsing ([1970-1991](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1970-L1991)) | Icon-font glyphs are neither turned into checkboxes nor lost. |
| Vault boundary for images and file links | `VaultImageLoader` refuses files outside the vault after resolving symbolic links ([MarkdownPreview.swift:2565-2570](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2565-L2570)); `linkAction` maps file URLs only under the root, both spellings ([1622-1633](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1622-L1633)) | A crafted Markdown image cannot read outside the vault. |
| Thumbnail cache with honest invalidation | entry valid only for the same modification date and size, cost in decoded bytes, `NSCache` memory pressure, `@unchecked Sendable` with its reason ([MarkdownPreview.swift:2645-2706](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2645-L2706)); decode width bounded ([2631-2643](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2631-L2643)) | Bounded memory, no stale drawings after a save; tested ([UiReadingViewTests.swift:339](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L339), [UiEmbeddedImageDecodingTests.swift:54-62](../../../Tests/GraphiteUITests/UiEmbeddedImageDecodingTests.swift#L54-L62)). |
| Media players outlive lazy rows and stop with their embeds | `ReadingMediaPlayers.keep`/`keepPlaybacks` ([MarkdownPreview.swift:2722-2751](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2722-L2751)); `EmbeddedMediaPlayback.deinit` pauses ([2719](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2719)); audio observer removed and cancellation checked ([2915-2920](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2915-L2920), [2933-2940](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2933-L2940)) | A lecture recording keeps playing while the user scrolls, and never plays on unseen; tested ([UiReadingViewTests.swift:235](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L235)). |
| Pure, injected property parsing | `PropertyNumberText.number(from:locale:)`, `PropertyDateText.parse` with round-trip check ([PropertiesPanel.swift:514-521](../../../Sources/GraphiteUI/PropertiesPanel.swift#L514-L521)), `combining(...calendar:)`, `converted(...now:)`; `PropertyListEditing` builds on the last committed list ([124-159](../../../Sources/GraphiteUI/PropertiesPanel.swift#L124-L159)) | Refuses ambiguous numbers and impossible dates rather than guessing; two quick edits do not revert each other; tested ([UiSheetsEditorLogicTests.swift:13-79](../../../Tests/GraphiteUITests/UiSheetsEditorLogicTests.swift#L13-L79)). |
| Toolbar layout as pure functions | `DocumentToolbarLayout` ([DocumentModeToggle.swift:71-133](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L71-L133)) | Named thresholds with reasons; tested ([WorkspaceFocusModeTests.swift:30-36](../../../Tests/GraphiteUITests/WorkspaceFocusModeTests.swift#L30-L36), [PencilToolboxTests.swift:480-504](../../../Tests/GraphiteUITests/PencilToolboxTests.swift#L480-L504)). |
| Typing does not rebuild the pane | text read only by `AutosaveDriver`, `DrawingAtCursorTracker`, `WordCounter`, `CompletionPopupOverlay` ([MarkdownPane.swift:140-145](../../../Sources/GraphiteUI/MarkdownPane.swift#L140-L145), [771-789](../../../Sources/GraphiteUI/MarkdownPane.swift#L771-L789), [1173-1192](../../../Sources/GraphiteUI/MarkdownPane.swift#L1173-L1192)); counting off the main thread ([784](../../../Sources/GraphiteUI/MarkdownPane.swift#L784)); subtitle always present ([793-796](../../../Sources/GraphiteUI/MarkdownPane.swift#L793-L796)) | Editor responsiveness is a top priority; the split of autosave out of the view must keep "the pane body never reads the text". |
| Drawing check cancels its file read | detached read cancelled with the lookup ([MarkdownPane.swift:733-740](../../../Sources/GraphiteUI/MarkdownPane.swift#L733-L740)); result cached per link and versions ([689-698](../../../Sources/GraphiteUI/MarkdownPane.swift#L689-L698)) | Quick cursor moves do not stack disk reads. |
| Theme colors checked per appearance and contrast | `dynamicColor` with role targets and per-appearance fallback ([NoteThemeStyle.swift:300-315](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L300-L315)); text on its own surface checked over that surface ([133-139](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L133-L139)); Read Aloud blue reserved ([173-177](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L173-L177)) | A theme can never make note text unreadable or hide the reading highlight. |
| Numbered equations as pure layouts with fallback | `NumberedFormulaLayout`, `NumberedRowsLayout`, `ViewThatFits`, `canDraw` falls back to source ([NumberedEquationView.swift:21-23](../../../Sources/GraphiteUI/NumberedEquationView.swift#L21-L23), [120-227](../../../Sources/GraphiteUI/NumberedEquationView.swift#L120-L227)) | Nothing is cut off at narrow widths; a formula the typesetter cannot draw stays readable. |
| Table lines as separate rectangles | `FilledRectangles` ([MarkdownPreview.swift:2295-2312](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2295-L2312)); scroll view only when wider ([2250-2252](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2250-L2252)) | Long tables keep their lines (texture size limit), swipes stay with the note. |
| Unique heading scroll targets numbered as the outline numbers them | [MarkdownPreview.swift:429-439](../../../Sources/GraphiteUI/MarkdownPreview.swift#L429-L439), [656-669](../../../Sources/GraphiteUI/MarkdownPreview.swift#L656-L669), [MarkdownPane.swift:913-920](../../../Sources/GraphiteUI/MarkdownPane.swift#L913-L920) | Outline jumps to the second of two equal headings reach it; tested ([UiReadingViewTests.swift:214](../../../Tests/GraphiteUITests/UiReadingViewTests.swift#L214)). |
| Narrow capabilities passed as values | `PropertiesPanel(update:follow:)` ([PropertiesPanel.swift:8-15](../../../Sources/GraphiteUI/PropertiesPanel.swift#L8-L15)), `ReadingTaskContext` ([ReadingTaskCheckbox.swift:6-13](../../../Sources/GraphiteUI/ReadingTaskCheckbox.swift#L6-L13)), `ReadingImageActions` with identity-based equality ([MarkdownPreview.swift:2961-2977](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2961-L2977)) | These are the shape the pane itself should take (ISP-READING-01). |
| Font requests off the main actor | `requestFonts` is `nonisolated` so Core Text's callback does not trap ([NoteTypography.swift:57-65](../../../Sources/GraphiteUI/NoteTypography.swift#L57-L65)) | Documents a platform constraint and avoids a crash. |

## 7. Blueprint for this area

### Target shape

| Type (file) | Single responsibility | Seam |
| --- | --- | --- |
| `NoteFolding.headingKey(rawLine:occurrence:)` (Core, existing file) | The one heading fold key | Used by editor, reading view, Read Aloud |
| `ReadAloudFolding.calloutKey` (Core, existing) | The one callout fold key, always from the written title | `CalloutView` takes `foldKey` as a required parameter |
| `LinkDisplayText` (Core) | Obsidian's label for a Wikilink | Used by both rewriters |
| `VaultLinkResolution` (Core) | Direct candidates → first existing *file* → index; stored spelling | Takes a `fileKind(at:)` function and an index lookup; used by builder, workspace, Live Preview |
| `EmbedClassification` (Core) | Embed kind from resolved path and "editable drawing" fact | Shared with `LivePreviewEmbedView` |
| `ReadingFileLookup` (UI, protocol) | `resolve`, `isEditableDrawingPDF`, `readNote` | Real substitution: tests use an in-memory vault; production wraps `VaultStore`, `VaultIndex`, `ImageFileService` |
| `ReadingLinkRewriter` (UI) | Today's `prepared` and target encoding | Pure over a resolution result |
| `ReadingViewBuilder` (UI, own file) | Block assembly, heading numbering, locations, token mapping; per-build `BuildState` | Takes `ReadingFileLookup` |
| `ReadingBuildModel` (UI) | Build scheduling, debounce, cache, task-tick rebuild | Replaces `ReadingBlocksCache` in the session |
| `ReadingScrollRestoration` (UI, value) | Restoration phases as an enum with intent methods | Pure; unit tests |
| `ReadingWordFollower` (UI) | Read Aloud follow and fold reveal | — |
| `MarkdownPreview` (UI) | Wiring view | — |
| `ReadingBlocksView` + one view per block kind (UI) | Drawing | — |
| `NoteTextEditor` (UI service) | Apply an edit to an open or closed note with an explicit `SavePolicy`, return `NoteEditOutcome` | Used by mentions, ticks, property rename |
| `NoteAutosave` (UI, owned by session registry) | Save after a pause, for every session with changes | Clock and delay injected |
| `NoteLinksInspectorModel` (UI) | Outline, links, tags, footnotes, mentions, with latest-answer-wins loads | Takes index and mention queries as capabilities |
| `MarkdownPane`, `NoteToolbar`, `NoteReadAloudCommands`, `NoteAttachmentImport` (UI) | Per §3.3 | Receive narrow values, not `WorkspaceModel` |
| `FoldStore` (UI) | A vault's folds in memory, written on change | Injected defaults, like `DocumentPlaceStore` |
| Shared drawing files: `GraphiteOpenLink.swift`, `ObsidianMarkdownText.swift`, `ObsidianMarkdownParser.swift`, `ReadingTextStyles.swift`, `CalloutView.swift`, `ReadingImageCache.swift`, `EmbeddedMediaPlayers.swift`, `ReadingPosition.swift`, `ReadingWordCells.swift` | One concept per file | `ReadingImageCache` injected through the environment |

No protocol is proposed besides `ReadingFileLookup`, which has two real implementations (production and an in-memory test vault).

### Ordered steps (each leaves the app building and behaving the same, except steps 3–6 which fix the bugs they name)

1. Move the types of `MarkdownPreview.swift`, `MarkdownPane.swift`, `FilePreviewPane.swift`, `PropertiesPanel.swift` and `DocumentModeToggle.swift` into one file per concept (no code change). Delete `CalloutFoldScope`.
2. Add characterization tests for the invariants below that have none (fold keys across views, callout keys, mentions, property rename, link labels), with the bug cases marked as expected failures.
3. Introduce `NoteFolding.headingKey`; carry the raw heading line on `RenderedBlock.heading`; replace both reading-view key formulas (BUG-READING-01). Add a one-time migration that drops orphan keys from `GraphiteFolds.<vault>` that no region of the note produces (only when the note is next opened).
4. Carry the written callout title on `RenderedBlock.callout`; make `CalloutView.foldKey` required (BUG-READING-02).
5. Extract `VaultLinkResolution`; switch the builder and the workspace to it (BUG-READING-03).
6. Extract `LinkDisplayText` and `ReadingLinkRewriter`; make `LivePreviewText.prepared` call it (BUG-READING-05).
7. Make `linkMention`, `toggleReadingTask` and `renameProperty` return typed outcomes; build `NoteTextEditor` and route the three through it; the inspector removes a mention only on success (BUG-READING-04).
8. Introduce `ReadingFileLookup` and `EmbedClassification`; the builder stops constructing services; Live Preview's embed view uses the same classification.
9. Extract `ReadingScrollRestoration` as a value with intent methods; replace the three fields; replace the 50 ms sleep with a reaction to the block's reported frame.
10. Extract `ReadingBuildModel` and `ReadingWordFollower`; replace `let _ = blockActions.update` with stable closures built once by the pane.
11. Move autosave into `NoteAutosave`; delete `AutosaveDriver`.
12. Extract `NoteLinksInspectorModel`; mentions report failures distinctly from empty.
13. Narrow `MarkdownPane` inputs; move `PropertyNumberText`, `PropertyDateText`, `PropertyValueKind.converted` to Core.
14. Inject `ReadingImageCache` and `FoldStore` from the composition root.

### Behaviour that must be preserved

| ID | Invariant | Test idea |
| --- | --- | --- |
| READING-INV-01 | Fold keys are `h<level>|<trimmed heading line>|<occurrence>` and `l|<trimmed list line>|<occurrence>`, counted among equal bases ([NoteFolding.swift:42-46](../../../Sources/GraphiteCore/NoteFolding.swift#L42-L46), [62](../../../Sources/GraphiteCore/NoteFolding.swift#L62), [80](../../../Sources/GraphiteCore/NoteFolding.swift#L80)); existing users' stored keys stay valid. | Golden keys for a fixture note; reading view hides exactly the blocks `NoteFolding.foldedRegions` hides for the same set. |
| READING-INV-02 | Folds persist per vault under `GraphiteFolds.<vault UUID>` as `[notePath: sortedKeys]`, an empty set removes the entry ([WorkspaceFolds.swift:7-9](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L7-L9), [29](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L29)); moves carry them, deletions drop them ([35-54](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L35-L54)); never written into the note. | Round-trip through an injected defaults suite; rename a folder and check keys moved. |
| READING-INV-03 | Callout expansion key is `type.lowercased() + "|" + written title trimmed` ([ReadAloudFolding.swift:10-12](../../../Sources/GraphiteCore/ReadAloudFolding.swift#L10-L12)), session-only per note path ([CalloutFoldStore.swift:5-21](../../../Sources/GraphiteUI/CalloutFoldStore.swift#L5-L21)); without an entry the `-`/`+` marker decides. | Expand in reading view → Read Aloud hidden ranges exclude the body; same in Live Preview. |
| READING-INV-04 | Graphite link URLs: `graphite://open?target=<target>` with `&markdown=1` for Markdown links and `&unresolved=1` for unresolved Wikilinks; footnotes `graphite://open?footnote=<n>`; `(`/`)` percent-encoded ([MarkdownPreview.swift:125-195](../../../Sources/GraphiteUI/MarkdownPreview.swift#L125-L195)). Live Preview produces the same URLs. | Encode/decode round trip for targets with `#`, `(`, `\`, spaces, non-ASCII. |
| READING-INV-05 | Image fragment keys `graphite-width`, `graphite-height`, `graphite-version` ([MarkdownPreview.swift:96-120](../../../Sources/GraphiteUI/MarkdownPreview.swift#L96-L120)); the note is never changed. | `url(for:)` then `displaySize(in:)` returns the size. |
| READING-INV-06 | Private-use U+E000–U+E00B in a note are escaped with lead U+E009 and stand-in +0x10, and restored after parsing ([MarkdownPreview.swift:201-230](../../../Sources/GraphiteUI/MarkdownPreview.swift#L201-L230)); the marker ranges stay in step with `NotePreviewDocument`'s markers ([NotePreviewDocument.swift:340-350](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L340-L350)). | Note with every code point in range renders them unchanged (existing test, keep). |
| READING-INV-07 | Heading scroll targets: first heading with an anchor gets the anchor; repeated ones outside callouts get `anchor + "\n" + occurrence`; repeated ones in callouts and embedded notes get none ([MarkdownPreview.swift:429-439](../../../Sources/GraphiteUI/MarkdownPreview.swift#L429-L439), [656-669](../../../Sources/GraphiteUI/MarkdownPreview.swift#L656-L669)); the outline numbers the same way ([MarkdownPane.swift:913-920](../../../Sources/GraphiteUI/MarkdownPane.swift#L913-L920)). | Outline occurrence n scrolls to the n-th equal heading. |
| READING-INV-08 | Footnote anchor is `footnote-<n>` ([MarkdownPreview.swift:92](../../../Sources/GraphiteUI/MarkdownPreview.swift#L92)); block ids are `properties` and `block-<n>` until the identity change of LSP-READING-06 is made deliberately ([77-84](../../../Sources/GraphiteUI/MarkdownPreview.swift#L77-L84)). | Tap a footnote reference scrolls to its row. |
| READING-INV-09 | A reading-view tick changes one status character only if the line checksum still matches; an embedded note's open session saves at once; a closed embedded note is rewritten with its revision and BOM ([WorkspaceReadingTasks.swift:9-31](../../../Sources/GraphiteUI/WorkspaceReadingTasks.swift#L9-L31)). | Existing `UiReadingTaskTests`; keep them through `NoteTextEditor`. |
| READING-INV-10 | Closed-note edits (mentions, ticks, renames) never write when the file changed since it was read and keep a leading BOM ([WorkspaceMentions.swift:75-82](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L75-L82), [WorkspaceTagsAndProperties.swift:78-84](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L78-L84)). | Change the file between read and save → `changedSinceRead`, file bytes unchanged. |
| READING-INV-11 | Property rename changes only the name on its line, saves open documents first, writes `types.json` only if at least one note was renamed, and reports at most 5 unchanged notes by name plus a count ([WorkspaceTagsAndProperties.swift:58-102](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L58-L102)). | Vault with an unchanged-since-read conflict: report lists it, other notes renamed. |
| READING-INV-12 | `types.json` is written only by an explicit type change or a rename ([WorkspaceTagsAndProperties.swift:46-52](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L46-L52), [91-95](../../../Sources/GraphiteUI/WorkspaceTagsAndProperties.swift#L91-L95)); "Change Type" in a note rewrites the value only ([PropertiesPanel.swift:212-219](../../../Sources/GraphiteUI/PropertiesPanel.swift#L212-L219)). | Change type in the panel → `types.json` bytes unchanged. |
| READING-INV-13 | Property dates are written as `yyyy-MM-dd` / `yyyy-MM-dd'T'HH:mm` (or the form they were written in, with space or `T`, seconds and fraction kept), `en_US_POSIX`, Gregorian, current time zone ([PropertiesPanel.swift:507-508](../../../Sources/GraphiteUI/PropertiesPanel.swift#L507-L508), [549-581](../../../Sources/GraphiteUI/PropertiesPanel.swift#L549-L581)); impossible dates are text. | Existing date tests; add a time-zone change case. |
| READING-INV-14 | Numbers: comma or period decimal by locale, grouping validated, `nan`/`inf`/hex refused ([PropertiesPanel.swift:436-494](../../../Sources/GraphiteUI/PropertiesPanel.swift#L436-L494)). | Existing tests. |
| READING-INV-15 | Unlinked mention link: Wikilink or Markdown link per vault settings; Markdown destination percent-encoded with the unreserved set plus `/`, `.md` appended; bare name only when the name is unique ([WorkspaceMentions.swift:63-67](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L63-L67)); at most 200 notes per list ([16](../../../Sources/GraphiteUI/WorkspaceMentions.swift#L16)). | Two notes named alike → path-qualified link. |
| READING-INV-16 | Autosave runs 900 ms after the last text change and reports failure on the session ([MarkdownPane.swift:670-676](../../../Sources/GraphiteUI/MarkdownPane.swift#L670-L676)); a save in flight is awaited ([MarkdownSession.swift:144-151](../../../Sources/GraphiteUI/MarkdownSession.swift#L144-L151)). | Injected clock: edit, advance 899 ms → no save; 900 ms → one save. |
| READING-INV-17 | The pane's `body` never reads `session.text` or `session.selection`; a word read aloud updates only the text it leaves and the one it enters (`Architecture.md:307`). | Update-count test with a body-evaluation counter (as the hosted performance tests do). |
| READING-INV-18 | First build of a shown note is immediate; later builds wait 150 ms; a task tick rebuilds without delay; an embedded-note tick rebuilds even when the host text is unchanged ([MarkdownPreview.swift:937-950](../../../Sources/GraphiteUI/MarkdownPreview.swift#L937-L950), [1042-1055](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1042-L1055)). | `ReadingBuildModel` with an injected clock. |
| READING-INV-19 | Restoration order: editor's starting location, unless a new heading request; else saved offset; with nothing saved, the first settled offset becomes the checkpoint only after the view knows it has nothing to restore; user scroll cancels pending restoration ([MarkdownPreview.swift:852-869](../../../Sources/GraphiteUI/MarkdownPreview.swift#L852-L869), [900-927](../../../Sources/GraphiteUI/MarkdownPreview.swift#L900-L927)). | `ReadingScrollRestoration` unit tests for each transition. |
| READING-INV-20 | The reading column is at most 730 pt (or the theme's `--file-line-width` scaled by text size) with at least 33 pt margins ([MarkdownPreview.swift:15-17](../../../Sources/GraphiteUI/MarkdownPreview.swift#L15-L17), [NoteThemeStyle.swift:278-280](../../../Sources/GraphiteUI/NoteThemeStyle.swift#L278-L280)), matching Live Preview's 740 pt column less padding. | Snapshot both views' text origin at one width. |
| READING-INV-21 | Embedded notes larger than 1 MiB, unreadable or not UTF-8 show as a link, a missing section as a message, nested note embeds stop at one level ([MarkdownPreview.swift:455-472](../../../Sources/GraphiteUI/MarkdownPreview.swift#L455-L472), [NotePreviewDocument.swift:206](../../../Sources/GraphiteCore/NotePreviewDocument.swift#L206)). | Existing `testEmbeddedNoteTooLargeIsShownAsALink`; add mutual-embed fixture. |
| READING-INV-22 | Image and file links never leave the vault root (symlinks resolved) ([MarkdownPreview.swift:2565-2570](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2565-L2570), [1622-1633](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1622-L1633)). | `../../etc/x.png` and a symlink out of the vault → not loaded. |
| READING-INV-23 | Thumbnail cache key `kind|pixelWidth|standardized path`, valid only while modification date and size match; longest side 2,400 px (block) / 1,800 px (inline) ([MarkdownPreview.swift:2621](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2621), [2683-2705](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2683-L2705)). | Existing cache tests with an injected instance. |
| READING-INV-24 | A kept media player plays on out of view and stops when its embed leaves the note; an unkept one stops on disappear ([MarkdownPreview.swift:2737-2750](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2737-L2750), [2790-2795](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2790-L2795)). | Existing `testMediaPlayersOutliveRowsAndEndWithTheirEmbeds`. |
| READING-INV-25 | Persisted UI keys: `GraphiteInspectorPanel` with raw values `outline, backlinks, outgoingLinks, tags, footnotes, graph, map`; `GraphiteShowsUnlinkedMentions` ([MarkdownPane.swift:891-895](../../../Sources/GraphiteUI/MarkdownPane.swift#L891-L895), [936-938](../../../Sources/GraphiteUI/MarkdownPane.swift#L936-L938)). | Registry test listing keys and raw values. |
| READING-INV-26 | Toolbar thresholds: 1,100 pt (toolbar controls), 480 pt (tab bar controls), 760 pt (secondary actions), 380 + 160 + 80 + 160 pt (tools in tab bar); compact width never uses the control row ([DocumentModeToggle.swift:77-132](../../../Sources/GraphiteUI/DocumentModeToggle.swift#L77-L132)). | Existing tests. |
| READING-INV-27 | Word count: text after the frontmatter, words split on whitespace and newlines, characters as grapheme clusters ([MarkdownPane.swift:820-843](../../../Sources/GraphiteUI/MarkdownPane.swift#L820-L843)). | Existing `testWordCountMatchesTheParsedBodyCount`. |
| READING-INV-28 | `MarkdownPane` is identified by its session, so the reading build request may omit path and root ([WorkspacePanes.swift:510-512](../../../Sources/GraphiteUI/WorkspacePanes.swift#L510-L512), [MarkdownPreview.swift:1237-1243](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1237-L1243)). | Open two notes with equal text in one tab → second shows its own embeds. |
| READING-INV-29 | Photos: HEIC/HEIF and `jpeg` saved as `.jpg`; camera photos JPEG quality 0.85 encoded off the main thread ([MarkdownPane.swift:630-651](../../../Sources/GraphiteUI/MarkdownPane.swift#L630-L651)). | `NoteAttachmentImport` unit test of the extension mapping. |
| READING-INV-30 | Unknown callout types take the note color with Graphite's pencil icon; a theme's alias color applies via `ObsidianCalloutTypes.canonicalType` ([MarkdownPreview.swift:2544](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2544), [2552-2558](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2552-L2558)). | Table test over every alias against the Core table. |

### Tests that become possible once the seams exist

- Reading-view fold keys equal `NoteFolding` keys for headings with links, highlights, colors, closing hashes, extra spaces and `%%` comments (pins BUG-READING-01).
- Callout expansion in reading view changes Read Aloud's hidden ranges and Live Preview's state (BUG-READING-02).
- `VaultLinkResolution` contract suite run against the builder's and the workspace's lookups: folders refused, stored spelling, ambiguity (BUG-READING-03).
- `NoteTextEditor` contract: open-attached, open-detached, closed; changed-since-read; BOM; failure outcome (BUG-READING-04, SRP-READING-06).
- One label table run through reading view and Live Preview rewriters (BUG-READING-05).
- `ReadingScrollRestoration` transition tests without UI; `ReadingBuildModel` debounce with an injected clock.
- `ReadingViewBuilder` with an in-memory `ReadingFileLookup`: slow, failing and missing files, cloud placeholders, without a real index.
- `NoteLinksInspectorModel`: index failure shown as failure, latest-answer-wins on note switch.

## 8. Appendix: raw metrics

**Reconnaissance numbers, checked.**

| Metric | Reconnaissance | Checked | Note |
| --- | --- | --- | --- |
| Files / physical / code lines | 14 / 6,971 / 5,431 | Agree | `read_files` shows +1 physical line per file (line after the final newline). |
| Functions over 40 code lines | 18 | Agree (spot-checked the 6 largest by reading) | List below. |
| Types over 300 code lines | `MarkdownPane` 550 | Agree | `ReadingViewBuilder` spans 382 physical lines and is below the cutoff; `MarkdownPreview` (view) has 37 stored properties and is mapped in §3.1. |
| `try?` | 32 | Not recounted | Examples in CC-READING-04. |
| `Task.sleep` | 8 | Agree | [MarkdownPane.swift:672](../../../Sources/GraphiteUI/MarkdownPane.swift#L672), [705](../../../Sources/GraphiteUI/MarkdownPane.swift#L705), [781](../../../Sources/GraphiteUI/MarkdownPane.swift#L781), [877](../../../Sources/GraphiteUI/MarkdownPane.swift#L877), [978](../../../Sources/GraphiteUI/MarkdownPane.swift#L978); [MarkdownPreview.swift:942](../../../Sources/GraphiteUI/MarkdownPreview.swift#L942), [965](../../../Sources/GraphiteUI/MarkdownPreview.swift#L965), [990](../../../Sources/GraphiteUI/MarkdownPreview.swift#L990). |
| `.shared` | 5 | Agree | `ReadingImageCache.shared` ×3 (2571, 3001, 3015; declared 2651), `NSFontManager.shared` ×2 ([NoteTypography.swift:29](../../../Sources/GraphiteUI/NoteTypography.swift#L29), [49](../../../Sources/GraphiteUI/NoteTypography.swift#L49)). |
| `static var` | 7 | Agree | Mutable: 2 (`familiesByLowercasedName`, `cachedFormatters`); the other 5 are computed. |
| `@unchecked Sendable` | 2 | Agree | `ReadingThumbnail` (2601), `ReadingImageCache` (2649), both with a stated invariant. |
| `MainActor.assumeIsolated` | 2 | Agree | [MarkdownPreview.swift:872](../../../Sources/GraphiteUI/MarkdownPreview.swift#L872), [1211](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1211). |
| `UserDefaults` | 2 | Agree | [WorkspaceFolds.swift:14](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L14), [18](../../../Sources/GraphiteUI/WorkspaceFolds.swift#L18); plus 4 `@AppStorage` (not matched by the pattern). |
| `FileManager.default` | 2 | Agree | [MarkdownPreview.swift:490](../../../Sources/GraphiteUI/MarkdownPreview.swift#L490), [2685](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2685). |
| `default:` in switch | 13 | Agree (grep `default:` minus dictionary defaults) | Over the app's own enums: 7 ([MarkdownPreview.swift:354](../../../Sources/GraphiteUI/MarkdownPreview.swift#L354), [476](../../../Sources/GraphiteUI/MarkdownPreview.swift#L476), [1295](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1295), [1305](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1305); [PropertiesPanel.swift:185](../../../Sources/GraphiteUI/PropertiesPanel.swift#L185), [316](../../../Sources/GraphiteUI/PropertiesPanel.swift#L316), [396](../../../Sources/GraphiteUI/PropertiesPanel.swift#L396)); over external values: 6. |
| `Task { }` | 38 | Not recounted | |

**Functions over 40 code lines (reconnaissance):** `MarkdownPreview.body` 127, `NoteThemeStyle.init` 122, `MarkdownPane.body` 109, `ReadingBlocksView.blockView` 105, `NoteLinksInspector.panelContent` 70, `ReadingViewBuilder.prepared` 53, `ObsidianMarkdownParser.applyMarkers` 50, `EmbeddedAudioPlayer.body` 50, `PropertyRow.valueEditor` 49, `ReadingViewBuilder.build` 47, `ObsidianMarkdownParser.replaceTaskMarkers` 45, `MarkdownPane.editorActions` 45, `NoteLinksInspector.body` 44, `PropertyRow.body` 42, `ObsidianMarkdownTextContent.body` 42, `WorkspaceModel.renameProperty` 41, `ReadingViewBuilder.render` 41, `DrawingAtCursorTracker.findDrawingAtCursor` 41.

**Counted for this document.**

| Measure | Value | Method |
| --- | --- | --- |
| Top-level types in `MarkdownPreview.swift` | 64 | Read the whole file. |
| Types per file (all 14) | 112 | Read every file; extensions not counted. |
| `MarkdownPreview` stored properties | 37 | Read lines 748–812. |
| `MarkdownPane` stored properties | 23 | Read lines 8–35. |
| `WorkspaceModel` members used by `MarkdownPane` | 38 distinct | Grep `workspace\.[a-zA-Z]+` in `MarkdownPane.swift`, lines 7–659, deduplicated by reading. |
| `NoteThemeStyle` stored properties | 62 | Read lines 14–105. |
| Raw `localizedDescription` shown to users | 16 | Grep `localizedDescription` over `Sources/GraphiteUI/*.swift`, filtered to the 14 files. |
| Copies of "edit a note open or closed" | 3 | Read the three workspace extensions. |
| Copies of the heading fold-key formula | 3 (1 Core, 2 reading view) | Grep `"h\\\(` and reading. |
| Places a new reading block kind touches in `MarkdownPreview.swift` | 6 | Read every `switch` over `RenderedBlock`. |
| Incident-dated comments | 3 | Grep `2026-\d\d-\d\d|reported by the owner|the owner's` over `Sources/GraphiteUI/*.swift`, filtered to scope (date literals in examples excluded). |
| Tests pinning reading-view fold keys, property rename, mention linking | 0 | Grep `ReadingFolding|foldedKeys|renameProperty|linkMention` over `Tests/**`. |

**Commits per file (reconnaissance):** `MarkdownPane.swift` 36, `MarkdownPreview.swift` 25, `PropertiesPanel.swift` 6, `NoteTypography.swift` 4, `FilePreviewPane.swift` 4, `ReadingTaskCheckbox.swift` 3, `NoteThemeStyle.swift` 3, `DocumentModeToggle.swift` 3, `WorkspaceTagsAndProperties.swift` 2, `WorkspaceMentions.swift` 2, `WorkspaceReadingTasks.swift` 1, `WorkspaceFolds.swift` 1, `NumberedEquationView.swift` 1, `CalloutFoldStore.swift` 1.

## 9. Since the snapshot

Delta audit of 2026-10-19 at `fff794b` (main), against `FR-01` to `FR-108`. Commits `7ad8900` and `93d82a6` changed how the reading view keys folds and resolves links.

### New findings

#### SRP-READING-09 The reading builder gathers callout titles in an actor field as a side effect of rendering
- **Severity:** Low
- **Rule:** `FR-12`, `FR-04`
- **Evidence:** the stored actor property `calloutTitlesByBlock` ([MarkdownPreview.swift:288](../../../Sources/GraphiteUI/MarkdownPreview.swift#L288)) is reset in `build` ([:311](../../../Sources/GraphiteUI/MarkdownPreview.swift#L311)), written by the recursive `render` ([:440-441](../../../Sources/GraphiteUI/MarkdownPreview.swift#L440-L441)) and read afterwards ([:315](../../../Sources/GraphiteUI/MarkdownPreview.swift#L315)); callouts inside transcluded notes are recorded too. Introduced in `7ad8900`.
- **Why it matters:** `render`'s output is split between its return value and a field; it is correct only because each build makes a fresh builder ([:971](../../../Sources/GraphiteUI/MarkdownPreview.swift#L971)).
- **Fix direction:** carry the written title on `RenderedBlock.callout` (as `LSP-READING-02` proposes), or return the titles from `render` with the blocks.

### State changes of earlier findings
- `LSP-READING-01`: Open → **Fixed**. Reading-view fold keys come from `NoteFolding.headingKeysByLineStart(in:)`, matched by line start ([NoteFolding.swift:118-129](../../../Sources/GraphiteCore/NoteFolding.swift#L118-L129), [MarkdownPreview.swift:316-324](../../../Sources/GraphiteUI/MarkdownPreview.swift#L316-L324)); both hand-built key strings are gone. Pinned by `NoteFoldingHeadingKeyTests`.
- `LSP-READING-02`: Open → **Partly fixed**. The reading view passes the written title as `foldKeyTitle` ([MarkdownPreview.swift:1463](../../../Sources/GraphiteUI/MarkdownPreview.swift#L1463)); `CalloutView` still defaults it to `nil` and falls back to `foldKeyTitle ?? title` ([:2495](../../../Sources/GraphiteUI/MarkdownPreview.swift#L2495)).
- `LSP-READING-03`: Open → **Partly fixed**. The builder and the workspace share `existingDirectFile`, so both exclude folders; the workspace still applies `storedPath(for:)` and the builder does not, so two resolvers remain.

### Patterns to keep
- Fold keys come from their owner (`NoteFolding`), matched by source position, never by display text (`FR-10`, `FR-28`).

### Notebook library (9040705)

#### CC-READING-11 `NotePreviewSummary` is another Markdown reader with its own fence, task, embed and picture-extension rules
- **Severity:** Medium
- **Rule:** `FR-10`, `FR-24`
- **Evidence:** fence detection ignores the fence character and length ([NotePreviewSummary.swift:48](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L48)); tasks are five literal markers, missing `* [X]` and `+ [ ]` ([:72](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L72)); `pictureExtensions` repeats `DocumentKind`'s list ([:29](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L29), [VaultPath.swift:167](../../../Sources/GraphiteCore/VaultPath.swift#L167)); its own inline-Markdown stripping ([NotePreviewSummary.swift:102-129](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L102-L129)); frontmatter correctly goes through `FrontmatterLocator`. Introduced in `7f56e00`.
- **Why it matters:** a note with a four-backtick fence containing three-backtick lines shows its code on the tile; every Markdown rule change now has one more reader to update.
- **Fix direction:** use the shared recognizers (fence state, task markers), or a parity test over the reading view's test notes; picture extensions from `DocumentKind`.

### State changes at 5aae924
- `CC-READING-11`: **Worse**. In `6a6dae3` `NotePreviewSummary` became a fuller Markdown reader: a fence still ignores its character and length, so inside a four-backtick fence a three-backtick line ends the block ([NotePreviewSummary.swift:72-75](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L72-L75)); task markers are still five literals ([:118](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L118)); it adds its own callout and quote parsing, list depth, ordered lists and rules ([:102-112](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L102-L112)), a second inline parser through `AttributedString(markdown:)` ([:155](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L155)), and keeps a private picture-extension list ([:42](../../../Sources/GraphiteCore/NotePreviewSummary.swift#L42)).
