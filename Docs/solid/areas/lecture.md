# Lecture: PDF notebooks, slides and annotations, recording and video, platform diagnostics (LECTURE)
Snapshot: b13dec3 (main, 2026-10-18).
Scope: `Sources/GraphiteApple/` (19 files: camera capture, diagnostics, paper renderer, watchdog, movie writer, PDF drawing file and stream decoder, PDF embed options, PDF ink, markup, compaction, page manager, Pencil ink, pictures, structure inspection, templates, recording controller, video capture and recording), `Sources/GraphiteCore/` (4 files: `PDFCitation`, `PageCoordinates`, `RecordingRecovery`, `RecordingState`), `Sources/GraphiteUI/` (14 files: `EmbeddedPDFViewer`, `GraphiteDiagnostics`, `GraphitePDFView`, `PDFEditHistory`, `PDFPageLasso`, `PDFPagesSidebar`, `PDFPane`, `PDFPaneHealth`, `PDFPictureControls`, `PDFSession`, `PDFSessionPictures`, `PDFThumbnailRenderer`, `RecordingControls`, `WorkspaceRecordingRecovery`), 37 files, 12852 physical lines, 9814 code lines (method: blank and comment-only lines and string contents removed by the reconnaissance script).

| Principle | Verdict | Reason |
| --- | --- | --- |
| S | Weak | `PDFAnnotationCoordinator` has 735 code lines, 37 stored properties and 13 responsibilities; `PDFSession` has 46 stored properties across 4 files; `RecordingController` has 26 stored properties and runs audio, video, publication and recovery. |
| O | Mixed | 3 `default:` branches over the app's own `PDFEdit`; audio/video branching in 9 `RecordingController` members; Graphite annotation keys listed in 2 separate places. Good: `PDFEdit` is one closed command vocabulary replayed everywhere. |
| L | Mixed | 2 digital-signature detectors with different rules; the Mac `GraphitePDFView` silently ignores 10 of its 15 inputs; bookmarks recognised by the display prefix `"Page "`. Good: the synthetic `VideoCaptureSource` drives the production writer. |
| I | Mixed | `PDFSession` exposes 10 writable fields that views set directly; `PDFPaneHealthMonitor` uses 9 members of the whole coordinator; 8 `[String: Any]` payloads. Good: `PDFInkCanvasProvider` has 2 requirements. |
| D | Mixed | 20 `.shared` uses (verified), 48 `FileManager.default`, 4 default arguments plus 2 inline constructions that create I/O. Good: `VideoCaptureSource` and `RecordingStorage` are injected seams. |
| Clean code | Mixed | 19 functions over 40 code lines, 64 `try?`, 49 `Task { }` with no owner, 3 `asyncAfter` used as timing, at least 10 comments narrating incidents. Good: precise names, units in constant names, and invariant comments on almost every non-obvious line. |

## 1. Summary

**What the area does.** It covers four product features and one developer feature:

1. **PDF notebooks, slides and annotation.** A PDF opens as a `PDFSession` ([PDFSession.swift:194-195](../../../Sources/GraphiteUI/PDFSession.swift#L194-L195)). The session applies every change to the live `PDFDocument` as an immutable `PDFEdit` ([PDFPageManager.swift:21-47](../../../Sources/GraphiteApple/PDFPageManager.swift#L21-L47)) and saves by replaying those edits on a private baseline copy in an actor ([PDFPageManager.swift:466-503](../../../Sources/GraphiteApple/PDFPageManager.swift#L466-L503)). After PDFKit writes, `PDFObjectCompaction` removes the objects nothing refers to ([PDFObjectCompaction.swift:30-53](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L30-L53)). Pencil ink is a PencilKit canvas over each page (`PDFPageCanvasView`, [GraphitePDFView.swift:582](../../../Sources/GraphiteUI/GraphitePDFView.swift#L582)). It is stored as standard `/Ink` annotations with an outline appearance and a re-editing record ([PDFInkAnnotation.swift:104-141](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L104-L141)). Text markup is standard `/Highlight`, `/Underline` and `/StrikeOut` ([PDFMarkup.swift:11-47](../../../Sources/GraphiteApple/PDFMarkup.swift#L11-L47)). Pictures are stamp annotations ([PDFPicture.swift:7-12](../../../Sources/GraphiteApple/PDFPicture.swift#L7-L12)). Page operations, outline, undo, thumbnails, the pages sidebar, the embedded viewer and a health monitor sit on top of these.
2. **Notebook paper.** `PDFTemplateGenerator` draws vector templates ([PDFTemplateGenerator.swift:55-149](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L55-L149)). `DrawingPaperRenderer` supplies the shared paper colours ([DrawingPaperRenderer.swift:16-34](../../../Sources/GraphiteApple/DrawingPaperRenderer.swift#L16-L34)).
3. **Vector drawing PDFs.** `PDFDrawingFile` and `PDFDrawingStreamDecoder` are the PDF format of Markdown drawings. They write XMP re-editing data and digest the page ([PDFDrawingFile.swift:6-38](../../../Sources/GraphiteApple/PDFDrawingFile.swift#L6-L38)). They live in this scope, but they serve the drawing feature.
4. **Lecture recording.** `RecordingController` records IMA4/CAF audio and fragmented MP4 video into a recovery folder, then publishes M4A/MP4 into the vault ([RecordingController.swift:31-32](../../../Sources/GraphiteApple/RecordingController.swift#L31-L32), [RecordingController.swift:369-374](../../../Sources/GraphiteApple/RecordingController.swift#L369-L374)). Recovery runs through `RecordingRecoveryFolder` ([RecordingRecovery.swift:47-163](../../../Sources/GraphiteCore/RecordingRecovery.swift#L47-L163)).
5. **Diagnostics.** `MainThreadWatchdog`, `MetricKitDiagnostics` and `DiagnosticRecords` write JSON evidence of freezes ([MainThreadWatchdog.swift:45-57](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L45-L57), [DiagnosticRecords.swift:10-12](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L10-L12)).

**Three biggest problems.**
1. **Two god objects carry the PDF experience.** `PDFAnnotationCoordinator` ([GraphitePDFView.swift:739-1696](../../../Sources/GraphiteUI/GraphitePDFView.swift#L739-L1696)) owns 37 stored properties. It mixes the canvas pool, ink recording, tool palette, first responder, gesture routing, text markup, Read Aloud pen, rendering scale, picture selection, health repair and paste. `PDFSession` ([PDFSession.swift:195-731](../../../Sources/GraphiteUI/PDFSession.swift#L195-L731)) owns 46 stored properties: document edits, saving, autosave, conflicts, undo, outline cache, protection, Read Aloud selection and view plumbing (`pdfView`, `livePlace`, `visiblePageCenter`, `viewGeneration`, `inkCanvasProvider`). This is where the Pencil experience lives, the owner's top priority, and neither type can be unit-tested without a live PDF view.
2. **One rule, several owners.** Digital signatures are detected twice, with different rules ([PDFSession.swift:93-147](../../../Sources/GraphiteUI/PDFSession.swift#L93-L147) vs [PDFStructureInspection.swift:34-71](../../../Sources/GraphiteApple/PDFStructureInspection.swift#L34-L71)). "A PDF keeps at least one page" is checked in 3 places with 2 messages. The typed page number is parsed 2 ways (one rejects non-ASCII digits, BUG-LECTURE-03). The annotation keys that must survive a page-tree rewrite are a second hand-written list ([PDFPageManager.swift:315-316](../../../Sources/GraphiteApple/PDFPageManager.swift#L315-L316)). `PDFEdit`'s derived properties hide new cases behind `default:` ([PDFPageManager.swift:50-73](../../../Sources/GraphiteApple/PDFPageManager.swift#L50-L73)).
3. **Recording flow state is spread over booleans and two code paths.** `RecordingController` keeps `state` plus `isPublishing`, `isAbandoningRecorder`, `startAttempt`, `pendingResume`, `resumesWhenInterruptionEnds`, and branches on `videoRecording`/`kind` in 9 members. The recovery listing treats a derived M4A as a separate lecture, so one lecture can be saved twice (BUG-LECTURE-01).

**Three best parts.**
1. **The save pipeline.** Immutable `PDFEdit`s are replayed off the main actor on a baseline snapshot. The file is replaced atomically only at the expected revision. The written bytes become the next baseline only after success ([PDFPageManager.swift:477-503](../../../Sources/GraphiteApple/PDFPageManager.swift#L477-L503), [PDFSession.swift:448-477](../../../Sources/GraphiteUI/PDFSession.swift#L448-L477)). Compaction falls back to PDFKit's own output for anything it does not fully understand ([PDFObjectCompaction.swift:219-225](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L219-L225), [PDFPageManager.swift:516-526](../../../Sources/GraphiteApple/PDFPageManager.swift#L516-L526)).
2. **Standard-annotation ink with safe re-editing.** Visible ink is standard `/Ink`. Re-editing data is accepted only when stroke names match annotations one to one, so another application's edits make the group read-only and never overwrite it ([PDFInkAnnotation.swift:260-300](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L260-L300)). The tracker converts only changed strokes ([PDFPencilInk.swift:132-163](../../../Sources/GraphiteApple/PDFPencilInk.swift#L132-L163)).
3. **The video capture seam and crash-tolerant media.** `VideoCaptureSource` is the one hardware boundary ([VideoCapture.swift:81-102](../../../Sources/GraphiteApple/VideoCapture.swift#L81-L102)). Fragmented MP4 parts and IMA4 CAF stay playable when the app dies ([MoviePartWriter.swift:6-12](../../../Sources/GraphiteApple/MoviePartWriter.swift#L6-L12), [RecordingController.swift:342-348](../../../Sources/GraphiteApple/RecordingController.swift#L342-L348)). The recovery copy is removed only after an atomic publish that expects no file at the destination ([RecordingController.swift:9-29](../../../Sources/GraphiteApple/RecordingController.swift#L9-L29)).

**Earlier-pass claims.**

| Claim (source) | Verdict | Evidence |
| --- | --- | --- |
| `VideoCaptureSource` specifies serial delivery and sample clocks; the synthetic source feeds the production writer (SOLID.md) | Holds | [VideoCapture.swift:85-88](../../../Sources/GraphiteApple/VideoCapture.swift#L85-L88); `VideoRecordingTests` (21 tests, for example `testAVideoRecordingIsAnOrdinaryMP4WithH264VideoAndAACSound`, [VideoRecordingTests.swift:30](../../../Tests/GraphiteAppleTests/VideoRecordingTests.swift#L30)) |
| `VideoRecording` receives a capture source and storage policy (SOLID.md) | Holds | [VideoRecording.swift:70-72](../../../Sources/GraphiteApple/VideoRecording.swift#L70-L72) |
| Workspace constructs the recording controller directly (SOLID.md) | Holds | [WorkspaceModel.swift:179](../../../Sources/GraphiteUI/WorkspaceModel.swift#L179) |
| PDF consumers reach `EmbeddedPDFSessions.shared` and `PencilToolbox.shared` (SOLID.md) | Holds | [EmbeddedPDFViewer.swift:558](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L558), [PDFPane.swift:77](../../../Sources/GraphiteUI/PDFPane.swift#L77), [PDFPane.swift:247](../../../Sources/GraphiteUI/PDFPane.swift#L247) |
| `PDFInkCanvasProvider` exposes two canvas queries (SOLID.md) | Holds | [PDFEditHistory.swift:78-83](../../../Sources/GraphiteUI/PDFEditHistory.swift#L78-L83) |
| Templates use an enum and a rendering switch (SOLID.md) | Holds | [PDFTemplateGenerator.swift:6-9](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L6-L9), [PDFTemplateGenerator.swift:108-144](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L108-L144) |
| Synthetic tests do not verify `CameraCaptureSource` (SOLID.md) | Holds | grep `CameraCaptureSource` over `Tests/**` and `App/Tests/**` finds no match |
| Graphite detects signatures with `PDFStructureInspection.hasDigitalSignature` (Architecture.md, paragraph on PDFKit page-tree rewrites) | Does not hold | The session uses `PDFSignatureDetection.hasDigitalSignatures` ([PDFSession.swift:81](../../../Sources/GraphiteUI/PDFSession.swift#L81)). `PDFStructureInspection.hasDigitalSignature(in:)` has no caller in `Sources/**` (grep `hasDigitalSignature\b`), only tests ([ApplePdfFixTests.swift:410](../../../Tests/GraphiteAppleTests/ApplePdfFixTests.swift#L410)). |
| Autosave waits 10× the last save, between 2 and 30 s; history keeps 100 steps (Architecture.md) | Holds | [PDFSession.swift:196-202](../../../Sources/GraphiteUI/PDFSession.swift#L196-L202), [PDFSession.swift:482-487](../../../Sources/GraphiteUI/PDFSession.swift#L482-L487) |
| Thumbnail cache at most 32 MiB; copy reopened every 64 pages (Architecture.md) | Holds | [PDFThumbnailRenderer.swift:27-29](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L27-L29), [PDFThumbnailRenderer.swift:262](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L262) |
| Diagnostics: at most 80 files; 0.5 s ping, 2 s stall; 30 events; off under a debugger (Architecture.md) | Holds | [DiagnosticRecords.swift:12](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L12), [MainThreadWatchdog.swift:59-60](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L59-L60), [DiagnosticRecords.swift:94](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L94), [MainThreadWatchdog.swift:86](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L86) |
| Health monitor: 3 in a row within 30 s; 20 pt or 5 % moved, back within 2 pt; covered record at most every 5 min (Architecture.md) | Holds | [PDFPaneHealth.swift:10-12](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L10-L12), [PDFPaneHealth.swift:42-46](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L42-L46), [PDFPaneHealth.swift:114](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L114) |
| Video: no start below 500 MB, stop below 250 MB; H.264 ≈2.2 bits/pixel, AAC mono 44.1 kHz, 1 s fragments (Architecture.md) | Holds | [VideoRecording.swift:10-12](../../../Sources/GraphiteApple/VideoRecording.swift#L10-L12), [MoviePartWriter.swift:12-29](../../../Sources/GraphiteApple/MoviePartWriter.swift#L12-L29) |
| Recording named after its note with a fixed 24-hour timestamp (Architecture.md) | Holds, with a nuance | The stem is `selection?.stem ?? title` ([WorkspaceModel.swift:1120](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1120)): the selected file's stem, else the vault title. The timestamp form is fixed ([WorkspaceModel.swift:1171-1174](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1171-L1174)). |
| Ink is recorded before any canvas goes and before every save (Architecture.md) | Holds | [GraphitePDFView.swift:1332-1338](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1332-L1338), [PDFSession.swift:438-439](../../../Sources/GraphiteUI/PDFSession.swift#L438-L439) |

## 2. File inventory

Physical and code lines come from the reconnaissance table. Every file was read completely.

| File | Physical | Code | Responsibility |
| --- | ---: | ---: | --- |
| [CameraCaptureSource.swift](../../../Sources/GraphiteApple/CameraCaptureSource.swift) | 234 | 186 | `AVCaptureSession` adapter for `VideoCaptureSource`: access, rotation, interruptions |
| [DiagnosticRecords.swift](../../../Sources/GraphiteApple/DiagnosticRecords.swift) | 121 | 83 | JSON freeze records in `Library/Diagnostics` and the shared `DiagnosticContext` |
| [DrawingPaperRenderer.swift](../../../Sources/GraphiteApple/DrawingPaperRenderer.swift) | 98 | 80 | Paper colours and paper patterns for drawings (bitmap and vector) |
| [MainThreadWatchdog.swift](../../../Sources/GraphiteApple/MainThreadWatchdog.swift) | 252 | 200 | MetricKit payload saver and the main-thread stall watchdog with stack capture |
| [MoviePartWriter.swift](../../../Sources/GraphiteApple/MoviePartWriter.swift) | 295 | 228 | One fragmented MP4 part (`AVAssetWriter`) and joining parts into one movie |
| [PDFDrawingFile.swift](../../../Sources/GraphiteApple/PDFDrawingFile.swift) | 343 | 264 | Vector drawing as a one-page PDF with XMP payload and content digest |
| [PDFDrawingStreamDecoder.swift](../../../Sources/GraphiteApple/PDFDrawingStreamDecoder.swift) | 328 | 246 | Bounded stream inflation for drawing PDFs (decompression-bomb guard) |
| [PDFEmbedOptions.swift](../../../Sources/GraphiteApple/PDFEmbedOptions.swift) | 52 | 37 | Parses `#page=` and `#height=` from a PDF embed |
| [PDFInkAnnotation.swift](../../../Sources/GraphiteApple/PDFInkAnnotation.swift) | 314 | 229 | Portable ink stroke, outlined `/Ink` annotation, ink update merge, editable group detection |
| [PDFMarkup.swift](../../../Sources/GraphiteApple/PDFMarkup.swift) | 373 | 288 | Markup kinds and colours, markup annotation building, annotation references |
| [PDFObjectCompaction.swift](../../../Sources/GraphiteApple/PDFObjectCompaction.swift) | 770 | 616 | Reachability compaction of PDFKit output, picture JPEG swap, PDF syntax scanner |
| [PDFPageManager.swift](../../../Sources/GraphiteApple/PDFPageManager.swift) | 569 | 430 | `PDFEdit` vocabulary, annotation keys, edit application, replay, export, destinations, `PDFFileService` actor |
| [PDFPencilInk.swift](../../../Sources/GraphiteApple/PDFPencilInk.swift) | 216 | 157 | Stroke fingerprints and the per-page ink tracker (PencilKit to standard ink) |
| [PDFPicture.swift](../../../Sources/GraphiteApple/PDFPicture.swift) | 295 | 183 | Picture value, stamp annotation drawing, display delegate |
| [PDFStructureInspection.swift](../../../Sources/GraphiteApple/PDFStructureInspection.swift) | 87 | 64 | Catalog entries a page change drops; a signature check |
| [PDFTemplateGenerator.swift](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift) | 273 | 221 | Paper templates and `PaperSpecification` (persisted `Codable`) |
| [RecordingController.swift](../../../Sources/GraphiteApple/RecordingController.swift) | 675 | 526 | Audio and video recording lifecycle, publication, recovery, preview routing, messages |
| [VideoCapture.swift](../../../Sources/GraphiteApple/VideoCapture.swift) | 102 | 68 | Capture vocabulary and the `VideoCaptureSource` protocol |
| [VideoRecording.swift](../../../Sources/GraphiteApple/VideoRecording.swift) | 282 | 210 | One video recording: parts, pause, interruptions, storage checks, preview output |
| [PDFCitation.swift](../../../Sources/GraphiteCore/PDFCitation.swift) | 63 | 44 | Page links and quotes in Obsidian syntax |
| [PageCoordinates.swift](../../../Sources/GraphiteCore/PageCoordinates.swift) | 23 | 20 | Overlay-to-PDF point mapping |
| [RecordingRecovery.swift](../../../Sources/GraphiteCore/RecordingRecovery.swift) | 163 | 118 | Recovery manifest, recovery folder layout, listing and removal |
| [RecordingState.swift](../../../Sources/GraphiteCore/RecordingState.swift) | 34 | 25 | Recording state and kind enums |
| [EmbeddedPDFViewer.swift](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift) | 731 | 585 | Embedded PDF view, its session lifecycle, and the app-wide `EmbeddedPDFSessions` registry |
| [GraphiteDiagnostics.swift](../../../Sources/GraphiteUI/GraphiteDiagnostics.swift) | 11 | 8 | Starts the diagnostics singletons |
| [GraphitePDFView.swift](../../../Sources/GraphiteUI/GraphitePDFView.swift) | 1808 | 1332 | PDF view bridge (iOS and Mac), page observer, resize handling, page canvas and overlay, `PDFAnnotationCoordinator` |
| [PDFEditHistory.swift](../../../Sources/GraphiteUI/PDFEditHistory.swift) | 325 | 239 | Session-owned undo: history pages, page operations, ink undo |
| [PDFPageLasso.swift](../../../Sources/GraphiteUI/PDFPageLasso.swift) | 171 | 130 | Lasso content of a PDF page (pictures, capture, paste) |
| [PDFPagesSidebar.swift](../../../Sources/GraphiteUI/PDFPagesSidebar.swift) | 314 | 258 | Thumbnails list, selection, outline list, page drag item |
| [PDFPane.swift](../../../Sources/GraphiteUI/PDFPane.swift) | 933 | 788 | PDF pane view, toolbar, banners, page commands model, dialogs, Read Aloud pen glue |
| [PDFPaneHealth.swift](../../../Sources/GraphiteUI/PDFPaneHealth.swift) | 544 | 415 | Unanswered-gesture counter, health monitor with repairs, passive touch observer |
| [PDFPictureControls.swift](../../../Sources/GraphiteUI/PDFPictureControls.swift) | 306 | 253 | Add-image menus, arrangement bar, picture selection frame controller |
| [PDFSession.swift](../../../Sources/GraphiteUI/PDFSession.swift) | 731 | 506 | Baseline snapshot, loader, signature detection, outline entries, `PDFSession` |
| [PDFSessionPictures.swift](../../../Sources/GraphiteUI/PDFSessionPictures.swift) | 226 | 164 | Picture add, move, rotate, crop, order as history steps |
| [PDFThumbnailRenderer.swift](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift) | 378 | 282 | Off-main page thumbnails with a shared byte-bounded cache |
| [RecordingControls.swift](../../../Sources/GraphiteUI/RecordingControls.swift) | 369 | 297 | Toolbar recording control, camera preview overlay and its layout |
| [WorkspaceRecordingRecovery.swift](../../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift) | 43 | 34 | Workspace offer, save and discard of unfinished recordings |
| **Total (37 files)** | **12852** | **9814** | |

## 3. Responsibility maps of the major types

### 3.1 `PDFAnnotationCoordinator` ([GraphitePDFView.swift:739-1696](../../../Sources/GraphiteUI/GraphitePDFView.swift#L739-L1696), plus `pasteFromPasteboard` in [PDFPageLasso.swift:155-170](../../../Sources/GraphiteUI/PDFPageLasso.swift#L155-L170))

735 code lines. 37 instance stored properties and 1 static mutable dictionary, counted by reading. It conforms to 5 protocols: `PDFPageOverlayViewProvider`, `PKCanvasViewDelegate`, `UIGestureRecognizerDelegate`, `UIEditMenuInteractionDelegate` and `PDFInkCanvasProvider` ([GraphitePDFView.swift:740-741](../../../Sources/GraphiteUI/GraphitePDFView.swift#L740-L741)).

| Responsibility | Stored state | Functions |
| --- | --- | --- |
| View lifecycle | `session`, `isEmbedded`, `pdfView`, `isDetached`, `hasAppliedInput`, `input` | `init`, `attach(to:)` (45 lines, [820-870](../../../Sources/GraphiteUI/GraphitePDFView.swift#L820-L870)), `detach` ([889-911](../../../Sources/GraphiteUI/GraphitePDFView.swift#L889-L911)), `update(input:)` ([1000-1027](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1000-L1027)), `windowDidChange` |
| Canvas pool (PDFKit overlays) | `canvasesByPage`, `displayedPages`, `hiddenCanvasOrder`, `retainedHiddenCanvasCount` | `pdfView(_:overlayViewFor:)`, `willDisplayOverlayView`, `willEndDisplayingOverlayView` ([1199-1242](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1199-L1242)), `makeCanvas`, `release`, `canvas(at:in:)`, `editingCanvas`, `isDisplaying` |
| Stored-ink restoration | (on the canvas) `hasRestoredStoredInk`, `isRestoringStoredInk` | `restoreStoredInkIfNeeded` ([1273-1303](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1273-L1303)), `configure` ([1316-1330](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1316-L1330)) |
| Ink recording into the session | none of its own (the tracker lives on the canvas) | `canvasViewDrawingDidChange` ([1354-1377](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1354-L1377)), `recordUnrecordedInk`, `writeDeferredInkRecords`, `writeDeferredInkRecord`, `setInkAnnotationsHidden` |
| Tool palette and first responder | `toolPicker`, `paletteAccessoryItem`, `toolPickerHost`, `presentedScreenObserver`, `toolboxObserver`, `hasPendingFirstResponderUpdate`, `reportPaletteFrame`, `paletteFrameObserver` | `updateToolPickerVisibility` ([1498-1520](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1498-L1520)), `updateFirstResponder`, `takeFixedToolFromToolbox`, `reportPaletteFrameNow` |
| Gesture routing and palm rejection | `pencilWhileReadingRecognizer`, `palmRejection`, `observedScrollRecognizers`, `restrictedEnclosingScrollViews`, static `enclosingScrollRestrictions` | `configureScrollGestures`, `makeWaitForPalmRejection`, `pageTapsAndPresses`, `handTouchesDidChange`, `scrollGestureChanged`, `configureEnclosingScrollViews`, `restoreEnclosingScrollViews` ([1066-1195](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1066-L1195)), `handlePencilTouchWhileReading`, gesture delegate methods |
| Text selection and markup menus | `markupTapRecognizer`, `textSelectionRecognizer`, `editMenuInteraction`, `tappedMarkup`, `selectionAnchor` | `handleTextSelection`, `presentSelectionMenu`, `selectionMenu`, `addMarkup`, `handleTap`, `markup(at:)`, `takesTap`, edit-menu delegate ([1536-1695](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1536-L1695)) |
| Read Aloud pen, markers, highlight forwarding | `readAloudPen`, `readAloudMarkers`, `pageObserver` | `highlightReading`, `handleReadAloudPenTap`, `showReadAloudMarkers`, `placeReadAloudMarkers` ([913-998](../../../Sources/GraphiteUI/GraphitePDFView.swift#L913-L998)) |
| Rendering scale | `zoomObserver`, `renderingScaleUpdate` | `scheduleRenderingScaleUpdate`, `updateRenderingScale` |
| Health and repair | `healthMonitor` | `repairCanvases`, `canvasDiagnostics`, `rebuildViewAfterRecordingInk`, `drawsWithFinger`, `isWriting` ([1387-1469](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1387-L1469)) |
| Picture selection hosting | `pictureSelection` | wiring of `session.visiblePageCenter` ([865](../../../Sources/GraphiteUI/GraphitePDFView.swift#L865)) |
| Link and lasso destinations | `linkActions`, `noteDestination`, `beginInteraction`, `beginWritingWithPencil` | set by the representable |
| Paste | none | `pasteFromPasteboard` |

**Calls that cross responsibilities (coupling a split must keep).**
- `configure(_:)` touches four responsibilities at once: restoration, tools, gesture enablement and ink annotation visibility ([1316-1330](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1316-L1330)).
- `release(_:)` records unrecorded ink, then the deferred record, then stops tool following, then shows the annotations again ([1332-1338](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1332-L1338)).
- `repairCanvases` (health) changes the canvas pool, the delegates and the configuration ([1404-1439](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1404-L1439)).
- `canvasViewDidBeginUsingTool` clears the text selection, ends the picture selection and takes first responder ([1484-1491](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1484-L1491)).
- `update(input:)` dismisses menus, reconfigures canvases, gestures and enclosing scroll views, and updates the picture selection ([1000-1027](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1000-L1027)).

**Lifecycle and ordering rules.**
- The overlay provider must be set before the document, because PDFKit asks for overlays only when it makes page views ([GraphitePDFView.swift:256-259](../../../Sources/GraphiteUI/GraphitePDFView.swift#L256-L259)).
- The restored drawing and `recordedDrawing` are set before `delegate`, so restoring is not recorded as an edit ([1296-1300](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1296-L1300)).
- A canvas PDFKit let go of is reused in a new overlay, never recreated, or strokes since the last save are lost ([1201-1210](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1201-L1210)).
- Ink annotations are shown again whenever no displayed canvas covers the page ([1236](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1236), [1337](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1337)).
- First-responder changes inside a SwiftUI update wait one main-queue turn ([1509-1519](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1509-L1519)).
- Every asynchronous callback checks `isDetached` ([884](../../../Sources/GraphiteUI/GraphitePDFView.swift#L884), [1500](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1500), [1524](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1524)).
- The static enclosing-scroll restriction is reference-counted by coordinator; the note's original gesture settings come back only when the last coordinator stops ([1161-1177](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1161-L1177)).
- `detach` unregisters the pending-ink writer and clears `session.inkCanvasProvider` only when it is still this coordinator ([899-901](../../../Sources/GraphiteUI/GraphitePDFView.swift#L899-L901)).

**Verdict.** Weak. One class decides the safety of every Pencil stroke and also hosts menus, the palette and diagnostics. The ink path cannot be tested without a `GraphitePDFDisplayView` in a window.

**Proposed split** (each a `@MainActor final class` owned by the coordinator, which stays the PDFKit overlay provider and wires them together):

| New type | Members moved |
| --- | --- |
| `PDFPageCanvasPool` | `canvasesByPage`, `displayedPages`, `hiddenCanvasOrder`, overlay provider callbacks, `makeCanvas`, `release`, `canvas(at:in:)`, `editingCanvas`, `isDisplaying`, `restoreStoredInkIfNeeded` |
| `PDFInkRecorder` | `canvasViewDrawingDidChange` body, `recordUnrecordedInk`, `writeDeferredInkRecord(s)`, `setInkAnnotationsHidden`. Takes a narrow `PDFInkSink` (apply an ink update, register a change) instead of the session. |
| `PDFToolPaletteController` | `toolPicker`, `paletteAccessoryItem`, `toolPickerHost`, `presentedScreenObserver`, `toolboxObserver`, `hasPendingFirstResponderUpdate`, `reportPaletteFrame`, `paletteFrameObserver`, `updateToolPickerVisibility`, `updateFirstResponder`, `takeFixedToolFromToolbox` |
| `PDFTouchRouting` | palm rejection, scroll gesture configuration, pencil-while-reading, enclosing scroll restriction. The static dictionary becomes an injected `EnclosingScrollRestrictionRegistry`. |
| `PDFTextMarkupInteraction` | selection recogniser, markup tap, edit menu, `selectionMenu`, `addMarkup` |
| `PDFReadAloudPenOverlay` | `readAloudPen`, `readAloudMarkers`, `handleReadAloudPenTap`, `placeReadAloudMarkers` |
| `PDFCanvasRepair` | `repairCanvases`, `canvasDiagnostics` (used by `PDFPaneHealthMonitor`) |

### 3.2 `PDFSession` ([PDFSession.swift:194-731](../../../Sources/GraphiteUI/PDFSession.swift#L194-L731), extensions in [PDFSessionPictures.swift:18-226](../../../Sources/GraphiteUI/PDFSessionPictures.swift#L18-L226), [PDFEditHistory.swift:86-325](../../../Sources/GraphiteUI/PDFEditHistory.swift#L86-L325), [PDFPageLasso.swift:143-153](../../../Sources/GraphiteUI/PDFPageLasso.swift#L143-L153))

About 880 code lines with extensions. 46 stored properties, counted by reading lines 212-339.

| Responsibility | Stored state | Functions |
| --- | --- | --- |
| Document and edit log | `location`, `document`, `edits`, `firstMergeableEditIndex`, `pageAppearances`, `changeVersion`, `pageListVersion`, `outlineVersion`, `pageCount`, `currentPageIndex` (also navigation) | `apply` ([365-384](../../../Sources/GraphiteUI/PDFSession.swift#L365-L384)), `record`, `appearanceVersion`, `appearance` |
| Saving and autosave | `revision`, `baseline`, `savedVersion`, `runningSave`, `autosaveTask`, `lastSaveDuration`, `consecutiveAutosaveFailures`, `writer`, `fileService`, `didSave`, `hasFailedSave` | `save`, `writePendingEdits`, `autosaveDelay`, `scheduleAutosave`, `saveBeforeClosing`, `saveSeparateCopy`, `export(pages:)`, `export(pageRuns:)` ([432-542](../../../Sources/GraphiteUI/PDFSession.swift#L432-L542)) |
| External change detection | `hasExternalConflict`, `unchangedStamp` | `hasChangedExternally`, `fileStamp`, `readRevision` ([544-593](../../../Sources/GraphiteUI/PDFSession.swift#L544-L593)) |
| Protection policy | `isPasswordProtected`, `hasDigitalSignatures`, `acceptsSignatureInvalidation`, `structureEntriesLostByPageChanges`, `acceptsStructureRewrite` | `isProtected` |
| Pending ink records | `pendingInkRecordWriters` | `registerPendingInkRecordWriter`, `unregisterPendingInkRecordWriter`, `writePendingInkRecords` |
| Undo history | `undoManager`, `undoAvailability`, `historyPages` | `registerStep`, `historyPage`, `currentIndex`, `rebind`, page operations, `registerInkChange`, `applyInkFromHistory` |
| Outline and bookmarks | `cachedOutlineEntries` | `outlineEntries`, `readOutlineEntries`, `bookmarkedPageIndices`, `addBookmark` |
| Markup | none | `addMarkup`, `removeMarkup`, `recolorMarkup` |
| Pictures | `selectedPicture`, `pictureCrop` | `addPicture`, `movePicture`, `removePicture`, `rotatePicture(Right)`, `cropPicture`, `movePictureInOrder`, `pastePicture` |
| View plumbing | `pdfView`, `keptPlace`, `livePlace`, `visiblePageCenter`, `isWriting`, `viewGeneration`, `inkCanvasProvider`, `identifier`, `errorMessage`, `contentDidChange` | `placeToRemember`, `go(to:)`, `rebuildView` |
| Read Aloud | `readAloudSelection` | cleared by `changeVersion.didSet` ([291-293](../../../Sources/GraphiteUI/PDFSession.swift#L291-L293)) |
| Pages | none | `insertPaper`, `importPages` |

**Cross-responsibility calls.**
- `apply` writes pending ink records before page-tree edits, bumps versions and schedules autosave ([369-383](../../../Sources/GraphiteUI/PDFSession.swift#L369-L383)).
- `save` writes pending ink records, which re-enter `apply` through the coordinator ([439](../../../Sources/GraphiteUI/PDFSession.swift#L439)).
- `writePendingEdits` clears `structureEntriesLostByPageChanges` after a page-tree save ([463-466](../../../Sources/GraphiteUI/PDFSession.swift#L463-L466)).
- `selectedPicture.didSet` clears `pictureCrop`, and `pictureCrop.didSet` posts a notification ([263-269](../../../Sources/GraphiteUI/PDFSession.swift#L263-L269)).

**Ordering rules.**
- Deferred ink records must be written before a page-tree edit (indices move) and before save, copy, export and deletion ([369](../../../Sources/GraphiteUI/PDFSession.swift#L369), [439](../../../Sources/GraphiteUI/PDFSession.swift#L439), [518](../../../Sources/GraphiteUI/PDFSession.swift#L518), [527](../../../Sources/GraphiteUI/PDFSession.swift#L527), [537](../../../Sources/GraphiteUI/PDFSession.swift#L537), [PDFEditHistory.swift:226](../../../Sources/GraphiteUI/PDFEditHistory.swift#L226)).
- Edits before `firstMergeableEditIndex` belong to a running save and must not be merged ([219-221](../../../Sources/GraphiteUI/PDFSession.swift#L219-L221), [408](../../../Sources/GraphiteUI/PDFSession.swift#L408)).
- The new baseline replaces the old one only after a successful save ([457-462](../../../Sources/GraphiteUI/PDFSession.swift#L457-L462)).
- A conflict stops autosave until the user decides ([494](../../../Sources/GraphiteUI/PDFSession.swift#L494), [501](../../../Sources/GraphiteUI/PDFSession.swift#L501)).
- `prepareForDisplay` must run before any annotation of a shown document is read ([PDFPageManager.swift:105-109](../../../Sources/GraphiteApple/PDFPageManager.swift#L105-L109), [PDFSession.swift:74](../../../Sources/GraphiteUI/PDFSession.swift#L74)).

**Verdict.** Weak. Every consumer, from the pane and sidebar to thumbnails, the health monitor, Read Aloud and the embed, receives the whole session.

**Proposed split.** `PDFSession` keeps identity and composition, with no forwarding methods. Consumers receive the part they use.

| New type | Members |
| --- | --- |
| `PDFDocumentEditor` | `document`, `edits`, merge rule, `apply`, page appearance versions, `changeVersion`, `pageListVersion`, `outlineVersion`, `pageCount`, pending-ink writers |
| `PDFSaveController` | baseline, revision, running save, autosave policy and failures, `fileService`, `didSave`, `hasFailedSave`, `hasExternalConflict`, `unchangedStamp`, `hasChangedExternally`, copy and export |
| `PDFProtection` (value) | `isPasswordProtected`, `hasDigitalSignatures`, `acceptsSignatureInvalidation`, `structureEntriesLostByPageChanges`, `acceptsStructureRewrite` |
| `PDFEditHistory` (class) | `undoManager`, `undoAvailability`, `historyPages`, the step functions of `PDFEditHistory.swift`, markup and picture steps |
| `PDFViewState` | `currentPageIndex`, `keptPlace`, `livePlace`, `isWriting`, `viewGeneration`, `selectedPicture`, `pictureCrop`, `visiblePageCenter`, `readAloudSelection`, `errorMessage` |
| `PDFOutlineModel` | outline cache, entries, bookmarks |

### 3.3 `RecordingController` ([RecordingController.swift:31-675](../../../Sources/GraphiteApple/RecordingController.swift#L31-L675))

501 code lines (single block). 26 stored properties, counted by reading lines 33-78.

| Responsibility | Stored state | Functions |
| --- | --- | --- |
| Public status | `state`, `message`, `destination`, `lastCompletedURL`, `recoveryURL`, `kind`, `accessProblem` | `elapsedSeconds`, `canStartRecording`, `dismissMessage` |
| Audio recording | `recorder`, `pendingResume`, `isAbandoningRecorder`, `retainedElapsedSeconds`, `startAttempt`, `finalizationTimeout` | `start` (42 lines, [106-154](../../../Sources/GraphiteApple/RecordingController.swift#L106-L154)), `cancelStart`, `startedRecorder`, `activateAudioSession`, `pause`, `resume`, `stop`, recorder delegate, `abandonRecorder`, `finish`, `deactivateAudioSession`, `retainElapsedSeconds`, `finishIfFinalizationStalls`, audio-session notifications ([653-674](../../../Sources/GraphiteApple/RecordingController.swift#L653-L674)) |
| Video recording | `videoRecording`, `camera`, `availableCameras`, `videoAspectRatio`, `makeVideoCaptureSource`, `videoStorage`, `previewRenderer`, `resumesWhenInterruptionEnds`, `interruptionStart` | `startVideo`, `discard`, `switchCamera`, `showPreview`, `stopShowingPreview`, `resumeVideo`, `resumedMessage`, `handle(_:fromRecordingAt:)`, `saveAfterStopping`, `finishClosingParts`, `finishVideo` |
| Publication | `publisher`, `filePresenter`, `isPublishing` | `saveAsM4A`, `convertedToM4A`, `publishVideo`, `saveAsMP4`, `retryPublication`, `discardRecoveredRecording` |
| Recovery | `recoveryFolderLocation` | `unfinishedRecordings`, `recover` |
| Test entry | none | `adoptRecording` (2 overloads, [440-451](../../../Sources/GraphiteApple/RecordingController.swift#L440-L451)) |

**Ordering rules.**
- `startAttempt` is checked after every `await` in `start` and `startVideo`. A stale start deletes its files and lets go of the audio session ([112](../../../Sources/GraphiteApple/RecordingController.swift#L112), [125-134](../../../Sources/GraphiteApple/RecordingController.swift#L125-L134), [478-482](../../../Sources/GraphiteApple/RecordingController.swift#L478-L482)).
- Stop must wait for `pendingResume` before touching the recorder ([231-237](../../../Sources/GraphiteApple/RecordingController.swift#L231-L237)).
- `retainElapsedSeconds` must run while `state == .recording`, before the recorder stops ([322-328](../../../Sources/GraphiteApple/RecordingController.swift#L322-L328)).
- `isPublishing` blocks a late callback or the timeout from publishing twice ([69-71](../../../Sources/GraphiteApple/RecordingController.swift#L69-L71)).
- The recovery file is removed only after the vault holds the copy ([24-27](../../../Sources/GraphiteApple/RecordingController.swift#L24-L27), [372-373](../../../Sources/GraphiteApple/RecordingController.swift#L372-L373)).

**Verdict.** Mixed. The transitions are careful and well tested ([AppleRecordingAccessFixTests.swift:54-247](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L54-L247)). Two media kinds and publication still share one object and one set of flags.

**Proposed split.**

| New type | Members |
| --- | --- |
| `RecordingSession` protocol (real substitution: audio, video and a test fake) with `AudioRecordingSession` and `VideoRecordingSession` | start, pause, resume, stop, elapsed time, interruption events |
| `RecordingPublisher` (extend the existing actor) | `saveAsM4A`, `convertedToM4A`, `saveAsMP4`, the publish step |
| `RecordingRecoveryInventory` | `unfinishedRecordings` and `recover`, with a throwing listing |
| `RecordingController` | one `RecordingFlow` enum with associated values (`.starting(attempt)`, `.recording(session)`, `.finalizing(session)`, `.failed(recovery, reason)` …) changed only by intent methods. Messages come from a presenter, not from string fields. |

### 3.4 `PDFPaneContent` ([PDFPane.swift:49-530](../../../Sources/GraphiteUI/PDFPane.swift#L49-L530))

427 code lines and 33 stored, state and environment properties (counted by reading lines 50-91). Responsibilities: Read Aloud pen orchestration and a marker cache ([107-162](../../../Sources/GraphiteUI/PDFPane.swift#L107-L162)); layout of the sidebar and the PDF view (`body`, 108 lines, [164-287](../../../Sources/GraphiteUI/PDFPane.swift#L164-L287)); mapping preferences to `PDFAnnotationInput` ([289-301](../../../Sources/GraphiteUI/PDFPane.swift#L289-L301)); protection and conflict banners ([303-348](../../../Sources/GraphiteUI/PDFPane.swift#L303-L348)); toolbar and More menu (84 lines, [399-483](../../../Sources/GraphiteUI/PDFPane.swift#L399-L483)); registration with the embed registry ([242-252](../../../Sources/GraphiteUI/PDFPane.swift#L242-L252)). Proposed split: `PDFPaneReadAloudModel` (pen, markers, reading start), a `PDFPaneBanner` view taking `PDFProtection` and save status, a `PDFPaneMoreMenu` view, and an `annotationInput(for:)` pure function in a `PDFAnnotationInputPolicy` shared with the embed (the embed repeats it, [EmbeddedPDFViewer.swift:288-299](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L288-L299)).

### 3.5 `EmbeddedPDFViewer` and `EmbeddedPDFSessions` ([EmbeddedPDFViewer.swift:15-527](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L15-L527), [EmbeddedPDFViewer.swift:556-681](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L556-L681))

The view has 28 stored and state properties (counted by reading lines 22-60) and 431 code lines. Inside a SwiftUI view it runs: loading a session ([463-485](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L463-L485)); the 1.5 s release timer and closing save ([489-514](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L489-L514)); scene-phase saves with background time ([113-126](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L113-L126)); external-change checks ([128-137](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L128-L137)); claiming annotation through the registry ([431-454](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L431-L454)); conflict notices; page-field parsing; zoom.

**Ordering rules.** The session is released only when the embed is still not visible after the delay ([495](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L495), [510](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L510)). A failed closing save keeps the session in the registry ([503-508](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L503-L508)). Annotation starts only after the other sessions of the file are saved ([650-668](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L650-L668)).

**Proposed split:** an `@Observable EmbeddedPDFViewerModel` owning load, release, annotate and conflict state, with the registry injected through the environment. The view keeps layout only.

### 3.6 Types that are large but sound

- `PDFObjectCompaction` (616 code lines) is already split by responsibility: `CompactionPlanner` decides ([PDFObjectCompaction.swift:180-303](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L180-L303)); `CompactionPlan.write` executes into a `CompactionSink` ([98-174](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L98-L174)); `PictureImageReplacement`, `PictureMarkupCopyRemoval` and `PDFSyntaxScanner` each do one job. It is a decide-then-do design and needs no split. Only `plan()` (74 lines) deserves extraction of its cross-reference reading.
- `GraphitePDFDisplayView` ([GraphitePDFView.swift:303-533](../../../Sources/GraphiteUI/GraphitePDFView.swift#L303-L533)) mixes resize, zoom keeping and touch routing. The zoom decision is a pure value `PDFResizeZoom` ([540-564](../../../Sources/GraphiteUI/GraphitePDFView.swift#L540-L564)), which is the right shape.

## 4. Findings by principle

### S

#### SRP-LECTURE-01 `PDFAnnotationCoordinator` owns 13 responsibilities and 37 stored properties
- **Severity:** High
- **Evidence:** stored state at [GraphitePDFView.swift:745-812](../../../Sources/GraphiteUI/GraphitePDFView.swift#L745-L812) and [GraphitePDFView.swift:921-940](../../../Sources/GraphiteUI/GraphitePDFView.swift#L921-L940) (37 instance properties and 1 static mutable dictionary, counted by reading); 5 protocol conformances ([740-741](../../../Sources/GraphiteUI/GraphitePDFView.swift#L740-L741)); 735 code lines (reconnaissance). The full map is in §3.1.
- **Why it matters:** every stroke's safety (record, deferred record, release) shares state with menus, palette visibility, scroll gesture restriction and diagnostics. A change to the palette or the text menu reopens the ink path, which has no unit-test seam. 23 commits touched this file (reconnaissance), the most in the area.
- **Fix direction:** keep the coordinator as the PDFKit overlay provider and the wiring point. Move ink recording, the canvas pool, the tool palette, touch routing, text markup and the Read Aloud pen into the types listed in §3.1. `PDFInkRecorder` depends on a two-method `PDFInkSink`, not on `PDFSession`.

#### SRP-LECTURE-02 `PDFSession` is the PDF's aggregate root, save controller, undo history and view state at once
- **Severity:** High
- **Evidence:** 46 stored properties at [PDFSession.swift:212-339](../../../Sources/GraphiteUI/PDFSession.swift#L212-L339) (counted by reading). View references live in the session: `pdfView` ([305](../../../Sources/GraphiteUI/PDFSession.swift#L305)), `livePlace` ([249](../../../Sources/GraphiteUI/PDFSession.swift#L249)), `visiblePageCenter` ([275](../../../Sources/GraphiteUI/PDFSession.swift#L275)), `inkCanvasProvider` ([324](../../../Sources/GraphiteUI/PDFSession.swift#L324)), `viewGeneration` ([281](../../../Sources/GraphiteUI/PDFSession.swift#L281)). Navigation calls the view: `go(to:)` calls `pdfView?.go(to:)` ([597-603](../../../Sources/GraphiteUI/PDFSession.swift#L597-L603)). Extensions add history, pictures and paste in three more files.
- **Why it matters:** the model holds weak references to views and closures views set. Session tests need a view or must leave half the state unset. Any consumer can change any part.
- **Fix direction:** split into `PDFDocumentEditor`, `PDFSaveController`, `PDFProtection`, `PDFEditHistory` and `PDFViewState` (§3.2). Navigation becomes a request the view observes (`PDFViewState.requestedPage`), not a call into `PDFView`.

#### SRP-LECTURE-03 `RecordingController` runs audio, video, publication and recovery in one object
- **Severity:** Medium
- **Evidence:** 26 stored properties at [RecordingController.swift:33-78](../../../Sources/GraphiteApple/RecordingController.swift#L33-L78); audio flow [106-340](../../../Sources/GraphiteApple/RecordingController.swift#L106-L340), publication [367-435](../../../Sources/GraphiteApple/RecordingController.swift#L367-L435), video [453-651](../../../Sources/GraphiteApple/RecordingController.swift#L453-L651), audio-session notifications [653-674](../../../Sources/GraphiteApple/RecordingController.swift#L653-L674).
- **Why it matters:** the only copy of a lecture moves through this object. Video fields (`camera`, `videoAspectRatio`, `interruptionStart`) and audio fields (`recorder`, `pendingResume`, `isAbandoningRecorder`) are all live in every state, so every member first works out which kind is current (OCP-LECTURE-02).
- **Fix direction:** an audio session and a video session behind one `RecordingSession` protocol (a real substitution with two production implementations and a test fake). Publication and recovery move into their own types (§3.3).

#### SRP-LECTURE-04 `EmbeddedPDFViewer` performs saving, reloading and session lifecycle inside a SwiftUI view
- **Severity:** Medium
- **Evidence:** a save on scene change ([EmbeddedPDFViewer.swift:113-126](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L113-L126)); an external check on each vault change ([128-137](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L128-L137)); a timed release with a closing save ([489-514](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L489-L514)); loading ([463-485](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L463-L485)); annotation claim ([431-454](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L431-L454)); a background task ([520-547](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L520-L547)).
- **Why it matters:** none of these flows can be tested without hosting the view. Their correctness depends on `@State` surviving SwiftUI's identity rules. The release task has no owner (CC-LECTURE-05).
- **Fix direction:** an `EmbeddedPDFViewerModel` owning load, release, claim and conflict state, with the registry injected. The view calls one model method per event.

#### SRP-LECTURE-05 `PDFPaneContent` mixes Read Aloud orchestration, banners, toolbar and input policy
- **Severity:** Medium
- **Evidence:** pen tap logic with text-context extraction ([PDFPane.swift:133-162](../../../Sources/GraphiteUI/PDFPane.swift#L133-L162)); marker cache ([120-129](../../../Sources/GraphiteUI/PDFPane.swift#L120-L129)); `body` 108 code lines ([164-287](../../../Sources/GraphiteUI/PDFPane.swift#L164-L287)); `moreMenuItems` 84 code lines ([399-483](../../../Sources/GraphiteUI/PDFPane.swift#L399-L483)); 33 properties ([50-91](../../../Sources/GraphiteUI/PDFPane.swift#L50-L91)).
- **Why it matters:** any SwiftUI update re-evaluates all of it. 19 commits touched the file (reconnaissance), the second change hotspot of the area.
- **Fix direction:** `PDFPaneReadAloudModel` for pen, markers and the reading start; separate banner and More-menu views; `PDFAnnotationInputPolicy` shared with the embed.

#### SRP-LECTURE-06 `PDFPageManager.swift` holds the edit vocabulary, the key registry, edit application, export, destinations and a file I/O actor
- **Severity:** Medium
- **Evidence:** `PDFEdit` ([PDFPageManager.swift:24-74](../../../Sources/GraphiteApple/PDFPageManager.swift#L24-L74)); keys ([77-103](../../../Sources/GraphiteApple/PDFPageManager.swift#L77-L103)); `apply`, 80 code lines ([114-199](../../../Sources/GraphiteApple/PDFPageManager.swift#L114-L199)); `replay` and `export` ([331-378](../../../Sources/GraphiteApple/PDFPageManager.swift#L331-L378)); `ResolvedDestinations` ([390-464](../../../Sources/GraphiteApple/PDFPageManager.swift#L390-L464)); `PDFFileService` with coordinated reads and atomic writes ([466-540](../../../Sources/GraphiteApple/PDFPageManager.swift#L466-L540)). The type is named "Manager".
- **Why it matters:** the persisted key registry, a pure edit interpreter and file I/O change for unrelated reasons in one file, and the name says nothing.
- **Fix direction:** `PDFEdit.swift` (vocabulary and derived properties), `PDFAnnotationKeys.swift` (registry), `PDFEditApplier.swift` (`apply` split per edit family), `PDFPageExport.swift` with `ResolvedDestinations`, `PDFFileService.swift`.

#### SRP-LECTURE-07 The health monitor repairs production state from inside a diagnostics component
- **Severity:** Medium
- **Evidence:** `checkStates` resets recognisers and calls `repairCanvases` every second ([PDFPaneHealth.swift:353-379](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L353-L379)). `repairCanvases` reassigns delegates, adds displayed pages, reconfigures and rebuilds the view, and returns English sentences as its result ([GraphitePDFView.swift:1404-1439](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1404-L1439)). `paneStoppedTakingTouches` rebuilds the view ([PDFPaneHealth.swift:339-349](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L339-L349)).
- **Why it matters:** a repair loop hides the real defect, and the "which states cannot last" policy lives in two classes. Repairs travel as strings, so no test can assert which repair ran.
- **Fix direction:** `PDFCanvasRepair` returns `[CanvasRepair]` (an enum carrying the page index); the monitor decides and records; the record encoder turns cases into text. Keep the pure `UnansweredGestureCount` as it is.

### O

#### OCP-LECTURE-01 `PDFEdit`'s derived properties use `default:`, so a new edit case is silently treated as no page-tree change and no changed page
- **Severity:** Medium
- **Evidence:** `changesPageTree` `default: false` ([PDFPageManager.swift:50-55](../../../Sources/GraphiteApple/PDFPageManager.swift#L50-L55)); `changesOutline` `default: false` ([57-62](../../../Sources/GraphiteApple/PDFPageManager.swift#L57-L62)); `changedPageIndex` `default: nil` ([65-73](../../../Sources/GraphiteApple/PDFPageManager.swift#L65-L73)). 3 sites, found by grep `\bdefault:` over `Sources/GraphiteApple/*.swift`.
- **Why it matters:** `changesPageTree` decides whether deferred ink records are written first ([PDFSession.swift:369](../../../Sources/GraphiteUI/PDFSession.swift#L369)) and whether Graphite keys are preserved at save ([PDFPageManager.swift:332](../../../Sources/GraphiteApple/PDFPageManager.swift#L332), [350](../../../Sources/GraphiteApple/PDFPageManager.swift#L350)). A new page-moving edit that falls into `default` loses stroke data and names at the next save.
- **Fix direction:** exhaustive switches with no `default:` in all three properties, plus a test that lists every case with its expected values.

#### OCP-LECTURE-02 Audio and video are branched by hand in 9 `RecordingController` members
- **Severity:** Medium
- **Evidence:** `elapsedSeconds` ([82](../../../Sources/GraphiteApple/RecordingController.swift#L82)), `pause` ([188](../../../Sources/GraphiteApple/RecordingController.swift#L188)), `resume` ([197](../../../Sources/GraphiteApple/RecordingController.swift#L197)), `stop` ([224](../../../Sources/GraphiteApple/RecordingController.swift#L224)), `abandonRecorder` ([268](../../../Sources/GraphiteApple/RecordingController.swift#L268)), `finish` ([294](../../../Sources/GraphiteApple/RecordingController.swift#L294)), `recover` ([360](../../../Sources/GraphiteApple/RecordingController.swift#L360)), `discardRecoveredRecording` ([424](../../../Sources/GraphiteApple/RecordingController.swift#L424)), `interruptRecording` ([670](../../../Sources/GraphiteApple/RecordingController.swift#L670)). Counted by reading every `if let videoRecording`, `kind ==` and `switch kind` in the file.
- **Why it matters:** a third capture kind, or a change to one kind's stop rule, touches nine places. Missing one makes the wrong kind's logic run.
- **Fix direction:** the `RecordingSession` protocol from SRP-LECTURE-03. The controller forwards intents to the current session.

#### OCP-LECTURE-03 Graphite's annotation keys are declared once but re-listed by hand for page-tree preservation
- **Severity:** Medium
- **Evidence:** declarations at [PDFPageManager.swift:77-103](../../../Sources/GraphiteApple/PDFPageManager.swift#L77-L103). The preservation list repeats all 10 keys ([315-316](../../../Sources/GraphiteApple/PDFPageManager.swift#L315-L316)). `isPicture` names both picture keys again instead of using `storedPictureKeys` ([244-247](../../../Sources/GraphiteApple/PDFPageManager.swift#L244-L247)), while `PDFPicture.init?(annotation:)` uses the list ([PDFPicture.swift:53](../../../Sources/GraphiteApple/PDFPicture.swift#L53)).
- **Why it matters:** a new key missing from the preservation list is dropped by PDFKit whenever pages change. The comment at [307-309](../../../Sources/GraphiteApple/PDFPageManager.swift#L307-L309) explains this, and nothing enforces it.
- **Fix direction:** one `enum PDFAnnotationKey: String, CaseIterable` holding every Graphite key, with preservation iterating `allCases`. A test that writes each key, moves a page, saves and reads every key back.

#### OCP-LECTURE-04 A paper template is added in three places
- **Severity:** Low
- **Evidence:** the enum ([PDFTemplateGenerator.swift:6-9](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L6-L9)), the rendering switch ([108-144](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L108-L144)) and `symbolName` in the UI ([PDFPane.swift:822-834](../../../Sources/GraphiteUI/PDFPane.swift#L822-L834)); `title` is `rawValue.capitalized` ([PDFTemplateGenerator.swift:9](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L9)).
- **Why it matters:** the switches are exhaustive, so the compiler finds them. The cost is low but real, and the title is derived from a persisted raw value.
- **Fix direction:** keep the enum. Move rendering per case into a `PaperPattern` value only when a template with options of its own appears. Titles go to the string catalogue.

#### OCP-LECTURE-05 Diagnostic record kinds are free strings shared with tests and a shell script
- **Severity:** Low
- **Evidence:** kinds `"MainThreadStallEnded"` and `"MainThreadStall"` ([MainThreadWatchdog.swift:139](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L139), [152](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L152)); `"PDFTouchesReachedAnotherView"`, `"PDFStoppedTakingTouches"`, `"PDFRepaired"` ([PDFPaneHealth.swift:288](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L288), [345](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L345), [378](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L378)); tests match file-name prefixes ([PDFGestureWinsTests.swift:548](../../../App/Tests/PDFGestureWinsTests.swift#L548)); the folder is fetched by a script named in the type's comment ([DiagnosticRecords.swift:8](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L8)).
- **Why it matters:** a renamed kind breaks the developer's fetch-and-read workflow and the tests without a compiler error.
- **Fix direction:** `enum DiagnosticRecordKind: String` with an `Encodable` payload struct per kind.

### L

#### LSP-LECTURE-01 Two digital-signature detectors apply different rules; production uses the one the documents do not name
- **Severity:** Medium
- **Evidence:** `PDFSignatureDetection.hasDigitalSignatures` checks `/Perms`, `SigFlags` bit 2, and a signature field with a dictionary `/V` ([PDFSession.swift:102-139](../../../Sources/GraphiteUI/PDFSession.swift#L102-L139)). `PDFStructureInspection.hasDigitalSignature` also treats `/DSS` as signed and accepts a `/V` of any type ([PDFStructureInspection.swift:39-71](../../../Sources/GraphiteApple/PDFStructureInspection.swift#L39-L71)). The session uses the first ([PDFSession.swift:81](../../../Sources/GraphiteUI/PDFSession.swift#L81)). The second decides the "digital signatures" entry of the page-change warning ([PDFStructureInspection.swift:27](../../../Sources/GraphiteApple/PDFStructureInspection.swift#L27)). Its public `hasDigitalSignature(in:)` is called only by tests ([ApplePdfFixTests.swift:410-434](../../../Tests/GraphiteAppleTests/ApplePdfFixTests.swift#L410-L434)).
- **Why it matters:** for a file with `/DSS` and no qualifying field, the page-change dialog warns about signatures while ink edits proceed without the "Edit and Invalidate Signature" confirmation. The tests pin both rules, including a path production never calls.
- **Fix direction:** one owner in GraphiteApple, `PDFSignatureInspection.hasDigitalSignature(catalog:)`, with the union of the rules. Delete `PDFSignatureDetection` and run one shared contract test.

#### LSP-LECTURE-02 The Mac `GraphitePDFView` accepts 15 inputs and ignores 10 of them
- **Severity:** Medium
- **Evidence:** properties at [GraphitePDFView.swift:1715-1735](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1715-L1735). `makeNSView` uses only `session` and `initialPageIndex` ([1744-1760](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1744-L1760)); `updateNSView` uses only the three reading values ([1762-1764](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1762-L1764)). Ignored: `input`, `isEmbedded`, `beginInteraction`, `linkActions`, `beginWritingWithPencil`, `reportReadingHighlightFrame`, `readAloudPen`, `readAloudMarkers`, `reportPaletteFrame`, `noteDestination` (counted by reading). Five carry the comment "accepted so both platforms share one call".
- **Why it matters:** on the Mac, `input.isEnabled` (markup) and `linkActions` (Copy Link to Page in the selection menu, which the iPad adds in `buildMenu`, [507-516](../../../Sources/GraphiteUI/GraphitePDFView.swift#L507-L516)) silently do nothing. Callers cannot tell from the type which inputs work.
- **Fix direction:** a shared `PDFViewConfiguration` value whose platform-specific parts are optional sub-values built only where supported, or two clearly named views. Inputs that have no effect are not accepted.

#### LSP-LECTURE-03 Tests drive `RecordingController` through `adoptRecording`, which sets states production never reaches that way
- **Severity:** Medium
- **Evidence:** `adoptRecording` writes `recoveryURL`, `destination`, `recorder`, `state`, `message` and `kind` directly ([RecordingController.swift:440-451](../../../Sources/GraphiteApple/RecordingController.swift#L440-L451)). Tests start from `.paused` with no recorder ([AppleRecordingAccessFixTests.swift:154](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L154)) and from `.recording` with no recorder ([169](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L169)). Production never holds `.paused` without a recorder (`pause` needs one, [186-195](../../../Sources/GraphiteApple/RecordingController.swift#L186-L195)).
- **Why it matters:** the tests prove publication from impossible states. Real start, pause and stop with a recorder are covered only by the hardware-dependent path.
- **Fix direction:** inject an `AudioRecorder` port (prepare and record, pause, stop, current time, finish callback) with a fake that keeps production semantics. Tests then drive `start`, `pause` and `stop`, and `adoptRecording` is deleted.

#### LSP-LECTURE-04 A bookmark's identity is read back from its display label
- **Severity:** Medium
- **Evidence:** `isBookmark` requires `label.hasPrefix("Page ")` ([PDFSession.swift:165-171](../../../Sources/GraphiteUI/PDFSession.swift#L165-L171)); `addBookmark` writes that label into the PDF outline ([666-670](../../../Sources/GraphiteUI/PDFSession.swift#L666-L670)); `toggleBookmark` removes the entry it finds ([PDFPane.swift:671-677](../../../Sources/GraphiteUI/PDFPane.swift#L671-L677)).
- **Why it matters:** a top-level, childless table-of-contents entry an author titled "Page 5" is shown as the user's bookmark and removed by "Remove Bookmark". Translating the label breaks recognition of every existing bookmark.
- **Fix direction:** recognise Graphite bookmarks by structure (top level, no children, destination at `visibleTopLeft`) in one function with tests. The persisted label keeps the literal `"Page "` prefix for compatibility (LECTURE-INV-10).

#### LSP-LECTURE-05 Failed folder reads in recording recovery are returned as empty results
- **Severity:** Medium
- **Evidence:** `recordings(in:)` returns `[]` when the folder cannot be listed ([RecordingRecovery.swift:122](../../../Sources/GraphiteCore/RecordingRecovery.swift#L122)); `laterPartLocations` returns `[]` on error ([101](../../../Sources/GraphiteCore/RecordingRecovery.swift#L101)); `unfinishedRecordings` returns `[]` when the folder location throws ([RecordingController.swift:352](../../../Sources/GraphiteApple/RecordingController.swift#L352)); `manifest(for:)` returns nil for unreadable and corrupt manifests alike ([RecordingRecovery.swift:70-75](../../../Sources/GraphiteCore/RecordingRecovery.swift#L70-L75)).
- **Why it matters:** `publishVideo` joins `[firstPart] + laterPartLocations` ([RecordingController.swift:635](../../../Sources/GraphiteApple/RecordingController.swift#L635)). A failed listing publishes only part 1 as if complete, and the other parts are offered later as separate recordings. An unreadable recovery folder looks like "nothing to recover".
- **Fix direction:** throwing listings with a typed error; callers show "Recordings could not be checked". A corrupt manifest is moved aside, not treated as absent.

### I

#### ISP-LECTURE-01 Recording views take the whole `WorkspaceModel` to use five members
- **Severity:** Low
- **Evidence:** `RecordingControl` and `RecordingPreviewOverlay` hold `@Bindable var workspace: WorkspaceModel` ([RecordingControls.swift:11](../../../Sources/GraphiteUI/RecordingControls.swift#L11), [156](../../../Sources/GraphiteUI/RecordingControls.swift#L156)). They use `recording`, `preferences.recordingCamera`, `showsRecordingPreview`, `startRecording` and `retryRecordingPublication` ([15](../../../Sources/GraphiteUI/RecordingControls.swift#L15), [44](../../../Sources/GraphiteUI/RecordingControls.swift#L44), [82-85](../../../Sources/GraphiteUI/RecordingControls.swift#L82-L85), [98-99](../../../Sources/GraphiteUI/RecordingControls.swift#L98-L99)). Counted by reading.
- **Why it matters:** the views observe the whole workspace and cannot be previewed or tested without one.
- **Fix direction:** a `RecordingCommands` value (start, retry, camera preference, preview toggle) plus the controller.

#### ISP-LECTURE-02 `PDFPaneHealthMonitor` receives the whole coordinator and uses 9 of its members
- **Severity:** Low
- **Evidence:** `coordinator.isEmbedded`, `.session.changeVersion`, `.session.pageCount`, `.drawsWithFinger`, `.isWriting`, `.repairCanvases()`, `.canvasDiagnostics()`, `.recordUnrecordedInk(of:)`, `.rebuildViewAfterRecordingInk()` ([PDFPaneHealth.swift:202](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L202), [219](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L219), [267](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L267), [348](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L348), [356-358](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L356-L358), [368](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L368), [419](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L419)).
- **Why it matters:** the monitor depends on the largest class in the area, so it cannot be exercised without it.
- **Fix direction:** a `PDFCanvasHealthPort` with those operations, the two session reads passed as a value.

#### ISP-LECTURE-03 Diagnostic payloads are untyped dictionaries
- **Severity:** Low
- **Evidence:** `write(kind:fields: [String: Any])` ([DiagnosticRecords.swift:28](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L28)); `snapshot() -> [String: Any]` ([117](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L117)); `describe(touchAt:) -> [String: Any]` ([PDFPaneHealth.swift:396](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L396)). There are 8 `[String: Any]` in the area (reconnaissance).
- **Why it matters:** a non-JSON value drops the whole record at run time ([DiagnosticRecords.swift:33-37](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L33-L37)).
- **Fix direction:** `Encodable` record structs.

#### ISP-LECTURE-04 Views write `PDFSession` state directly through 10 public setters
- **Severity:** Medium
- **Evidence:** written from outside: `isWriting` ([PDFPane.swift:180](../../../Sources/GraphiteUI/PDFPane.swift#L180)), `selectedPicture` ([238-239](../../../Sources/GraphiteUI/PDFPane.swift#L238-L239)), `pictureCrop` ([PDFPictureControls.swift:89](../../../Sources/GraphiteUI/PDFPictureControls.swift#L89), [130](../../../Sources/GraphiteUI/PDFPictureControls.swift#L130)), `errorMessage` ([PDFPane.swift:343](../../../Sources/GraphiteUI/PDFPane.swift#L343)), `acceptsSignatureInvalidation` ([283](../../../Sources/GraphiteUI/PDFPane.swift#L283)), `acceptsStructureRewrite` ([720](../../../Sources/GraphiteUI/PDFPane.swift#L720)), `currentPageIndex` ([EmbeddedPDFViewer.swift:477](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L477)), `keptPlace` ([GraphitePDFView.swift:296](../../../Sources/GraphiteUI/GraphitePDFView.swift#L296)), `pdfView` ([275](../../../Sources/GraphiteUI/GraphitePDFView.swift#L275)), `livePlace` ([266](../../../Sources/GraphiteUI/GraphitePDFView.swift#L266)). Counted by reading.
- **Why it matters:** accepting signature invalidation, a one-way decision to break signatures, is a boolean any view can set. No single method records the decision.
- **Fix direction:** intent methods (`acceptSignatureInvalidation()`, `beginWriting()`, `select(picture:)`) and `private(set)` storage.

### D

#### DIP-LECTURE-01 Feature code reaches singletons and static mutable state
- **Severity:** Medium
- **Evidence:** `EmbeddedPDFSessions.shared` on 8 lines of views ([PDFPane.swift:247](../../../Sources/GraphiteUI/PDFPane.swift#L247), [251](../../../Sources/GraphiteUI/PDFPane.swift#L251), [EmbeddedPDFViewer.swift:152](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L152), [422](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L422), [433](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L433), [458](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L458), [465](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L465), [496](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L496)); `PencilToolbox.shared` on 4 ([GraphitePDFView.swift:860](../../../Sources/GraphiteUI/GraphitePDFView.swift#L860), [1033](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1033), [PDFPane.swift:77](../../../Sources/GraphiteUI/PDFPane.swift#L77), [EmbeddedPDFViewer.swift:53](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L53)); the static `enclosingScrollRestrictions` ([GraphitePDFView.swift:812](../../../Sources/GraphiteUI/GraphitePDFView.swift#L812)); the static thumbnail cache ([PDFThumbnailRenderer.swift:30-34](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L30-L34)); the static `DiagnosticContext.state` ([DiagnosticRecords.swift:101](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L101)). 20 `.shared` uses in the area in total (grep `\.shared\b`, matching the reconnaissance count).
- **Why it matters:** two workspaces, windows or tests share embed claims and kept sessions. The registry also calls `WorkspaceModel.comparablePath` ([EmbeddedPDFViewer.swift:586](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L586)), which couples a PDF registry to the workspace type.
- **Fix direction:** the composition root builds one `EmbeddedPDFSessions` per scene and passes it through the environment. The stateless `PDFPictureDrawingDelegate.shared` ([PDFPicture.swift:285](../../../Sources/GraphiteApple/PDFPicture.swift#L285)) can stay. The watchdog stays a process-wide singleton, started only by the root ([GraphiteDiagnostics.swift:6-10](../../../Sources/GraphiteUI/GraphiteDiagnostics.swift#L6-L10)).

#### DIP-LECTURE-02 Recording and recovery call `FileManager.default` and Application Support directly
- **Severity:** Medium
- **Evidence:** the recovery folder is hard-coded to `Graphite/Recovery/Recordings` with the default file manager ([RecordingRecovery.swift:52-57](../../../Sources/GraphiteCore/RecordingRecovery.swift#L52-L57)). `RecordingController.swift` calls `FileManager.default` on 21 lines (grep `FileManager\.default`: lines 14, 19, 27, 131, 142, 143, 372, 373, 384, 391, 415, 416, 423, 427, 430, 431, 493, 503, 504, 649, 650). Tests can replace only the folder closure ([RecordingController.swift:59](../../../Sources/GraphiteApple/RecordingController.swift#L59)). The area has 48 `FileManager.default` (reconnaissance).
- **Why it matters:** the failure paths that keep "the only copy of a lecture" (undeletable recovery copy, missing folder, full disk) are tested by changing real permissions ([AppleRecordingAccessFixTests.swift:24](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L24)), not through a port.
- **Fix direction:** a `RecordingStore` port (list, write manifest, remove, move aside) with a file implementation and a fake that keeps the same error semantics.

#### DIP-LECTURE-03 Default arguments and inline constructors create I/O collaborators
- **Severity:** Medium
- **Evidence:** `PDFSession.open(…, writer: AtomicFileWriter = AtomicFileWriter())` ([PDFSession.swift:358](../../../Sources/GraphiteUI/PDFSession.swift#L358)); an inline `AtomicFileWriter()` for imports ([627](../../../Sources/GraphiteUI/PDFSession.swift#L627)); `PDFFileService(writer: AtomicFileWriter = AtomicFileWriter())` ([PDFPageManager.swift:468](../../../Sources/GraphiteApple/PDFPageManager.swift#L468)); the fallback writer in the registry ([EmbeddedPDFViewer.swift:597](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L597)); `storage: RecordingStorage = .system` ([VideoRecording.swift:70](../../../Sources/GraphiteApple/VideoRecording.swift#L70)); `makeVideoCaptureSource = { CameraCaptureSource() }` ([RecordingController.swift:56](../../../Sources/GraphiteApple/RecordingController.swift#L56)).
- **Why it matters:** an embed opened outside any registered vault writes without the vault's file presenter, so its own saves come back as external changes (the registry's comment states why the writer matters, [EmbeddedPDFViewer.swift:564-566](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L564-L566)).
- **Fix direction:** no defaults that construct I/O. The root passes the writer, storage and capture-source factory.

#### DIP-LECTURE-04 Logic reads clocks directly
- **Severity:** Low
- **Evidence:** `ContinuousClock.now` and `.now` in the controller ([RecordingController.swift:564](../../../Sources/GraphiteApple/RecordingController.swift#L564), [578](../../../Sources/GraphiteApple/RecordingController.swift#L578)); `ContinuousClock.now` for save duration ([PDFSession.swift:455](../../../Sources/GraphiteUI/PDFSession.swift#L455)); `ProcessInfo.processInfo.systemUptime` in the health monitor ([PDFPaneHealth.swift:264](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L264), [320](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L320), [359](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L359)); `Date()` defaults in diagnostics ([DiagnosticRecords.swift:28](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L28), [109](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L109)).
- **Why it matters:** the interruption length and gesture windows are testable only with real time. The pure parts (`autosaveDelay(afterSaveTaking:consecutiveFailures:)`, `UnansweredGestureCount.add(_:at:)`) already take time as input, which is the right shape.
- **Fix direction:** one injected clock for the controller, the monitor and the session.

### Clean code

#### CC-LECTURE-01 Comments narrate incidents and dates instead of stating the rule
- **Severity:** Low
- **Evidence:** 10 places found by reading: [GraphitePDFView.swift:354](../../../Sources/GraphiteUI/GraphitePDFView.swift#L354) ("reported by the owner, 2026-10-13"), [GraphitePDFView.swift:1206-1207](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1206-L1207) ("seen on the owner's iPad, 2026-10-13"), [PDFPaneHealth.swift:89-92](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L89-L92), [PDFPaneHealth.swift:101-102](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L101-L102), [PDFEditHistory.swift:9-12](../../../Sources/GraphiteUI/PDFEditHistory.swift#L9-L12) ("Before, PencilKit kept…"), [MoviePartWriter.swift:228](../../../Sources/GraphiteApple/MoviePartWriter.swift#L228) ("measured 2026-10-17"), [PDFPicture.swift:49-50](../../../Sources/GraphiteApple/PDFPicture.swift#L49-L50) ("a build of 2026-10-11"), [PDFMarkup.swift:301-303](../../../Sources/GraphiteApple/PDFMarkup.swift#L301-L303), [EmbeddedPDFViewer.swift:127](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L127) ("where it used to make it again"), [PDFPane.swift:851-853](../../../Sources/GraphiteUI/PDFPane.swift#L851-L853).
- **Why it matters:** history grows with every fix and buries the rule a reader needs. Several of these comments carry a real invariant ("a kept canvas is reused") inside the story.
- **Fix direction:** keep the current rule in the present tense; move the incident to the commit message and a regression test named after the behaviour. The compatibility facts about older builds' keys belong in LECTURE-INV-05.

#### CC-LECTURE-02 Nineteen functions exceed 40 code lines, the largest in SwiftUI bodies and edit application
- **Severity:** Medium
- **Evidence:** reconnaissance list, confirmed by reading: `PDFPaneContent.body` 108 ([PDFPane.swift:164](../../../Sources/GraphiteUI/PDFPane.swift#L164)), `moreMenuItems` 84 ([PDFPane.swift:399](../../../Sources/GraphiteUI/PDFPane.swift#L399)), `PDFPageManager.apply` 80 ([PDFPageManager.swift:114](../../../Sources/GraphiteApple/PDFPageManager.swift#L114)), `CompactionPlanner.plan` 74 ([PDFObjectCompaction.swift:196](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L196)), `EmbeddedPDFViewer.body` 70 ([EmbeddedPDFViewer.swift:81](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L81)), `PDFTemplateGenerator.render` 58 ([PDFTemplateGenerator.swift:90](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L90)), `MoviePartWriter.init` 52 and `append` 51 ([MoviePartWriter.swift:71](../../../Sources/GraphiteApple/MoviePartWriter.swift#L71), [133](../../../Sources/GraphiteApple/MoviePartWriter.swift#L133)), `RecordedMovie.playableMovie` 50 ([MoviePartWriter.swift:241](../../../Sources/GraphiteApple/MoviePartWriter.swift#L241)), `PDFAnnotationCoordinator.attach` 45 ([GraphitePDFView.swift:820](../../../Sources/GraphiteUI/GraphitePDFView.swift#L820)), `RecordingController.start` 42 ([RecordingController.swift:106](../../../Sources/GraphiteApple/RecordingController.swift#L106)), and 8 more listed in §8.
- **Why it matters:** `PDFPageManager.apply` is one switch over 15 edit kinds that must produce identical results on two documents; a long body makes divergence between cases hard to see.
- **Fix direction:** one function per edit family (pages, ink, markup, pictures, outline); split the SwiftUI bodies into named subviews.

#### CC-LECTURE-03 One behaviour is implemented several times
- **Severity:** Medium
- **Evidence (counted by reading):**
  - "keep at least one page": [PDFPageManager.swift:134](../../../Sources/GraphiteApple/PDFPageManager.swift#L134) ("A notebook must retain…"), [PDFEditHistory.swift:220](../../../Sources/GraphiteUI/PDFEditHistory.swift#L220) and [PDFPane.swift:652-653](../../../Sources/GraphiteUI/PDFPane.swift#L652-L653) ("A PDF must keep…"). 3 owners, 2 messages.
  - typed page number: [PDFPane.swift:548-558](../../../Sources/GraphiteUI/PDFPane.swift#L548-L558) (any script's decimal digits) and [EmbeddedPDFViewer.swift:370-377](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L370-L377) (`Int(_:)`, ASCII only). Their behaviour differs (BUG-LECTURE-03).
  - annotation input mapping: [PDFPane.swift:289-301](../../../Sources/GraphiteUI/PDFPane.swift#L289-L301) and [EmbeddedPDFViewer.swift:288-299](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L288-L299).
  - `#rrggbb` parsing: [DrawingPaperRenderer.swift:37-40](../../../Sources/GraphiteApple/DrawingPaperRenderer.swift#L37-L40) and [PDFTemplateGenerator.swift:187-190](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L187-L190).
  - signature detection: LSP-LECTURE-01.
  - nearest enclosing scroll view: [GraphitePDFView.swift:566-576](../../../Sources/GraphiteUI/GraphitePDFView.swift#L566-L576) and [PDFPaneHealth.swift:525-532](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L525-L532). There are 11 recursive view-tree walkers in the area (§8).
  - quarter-turn normalisation `((rotation / 90) % 4 + 4) % 4`: [PDFSessionPictures.swift:44](../../../Sources/GraphiteUI/PDFSessionPictures.swift#L44), [PDFPictureControls.swift:236](../../../Sources/GraphiteUI/PDFPictureControls.swift#L236), [PDFPageLasso.swift:122](../../../Sources/GraphiteUI/PDFPageLasso.swift#L122).
  - "Page N of M": [PDFPane.swift:862](../../../Sources/GraphiteUI/PDFPane.swift#L862) and [873](../../../Sources/GraphiteUI/PDFPane.swift#L873).
  - default A4 size: [PDFTemplateGenerator.swift:26](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L26) and [PDFSession.swift:611](../../../Sources/GraphiteUI/PDFSession.swift#L611); spacing range 4…144 at [PDFTemplateGenerator.swift:63](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L63) and [81](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L81).
- **Why it matters:** copies already disagree in two cases (page-number parsing, signature detection). Every further fix must find all copies.
- **Fix direction:** one owner each: `PDFPageCountRule`, `PageNumberInput.parse`, `PDFAnnotationInputPolicy`, `HexColor`, `PDFSignatureInspection`, `UIView.ancestors(of:)` and `descendants(of:)`, `PageRotation.quarterTurns`, `PaperSpecification.limits`.

#### CC-LECTURE-04 Domain and adapter types carry user-visible English; raw error text reaches the user
- **Severity:** Medium
- **Evidence:** `PDFMarkupKind.title` ([PDFMarkup.swift:17-23](../../../Sources/GraphiteApple/PDFMarkup.swift#L17-L23)), `PDFMarkupColor.title` ([57](../../../Sources/GraphiteApple/PDFMarkup.swift#L57)), `PaperTemplate.title` ([PDFTemplateGenerator.swift:9](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L9)), `CaptureInterruptionReason.explanation` ([VideoCapture.swift:31-46](../../../Sources/GraphiteApple/VideoCapture.swift#L31-L46)), `CaptureAccessProblem.errorDescription` ([54-63](../../../Sources/GraphiteApple/VideoCapture.swift#L54-L63)), `PDFStructureInspection.description(ofCatalogKey:)` returning phrases a test pins ([PDFStructureInspection.swift:73-86](../../../Sources/GraphiteApple/PDFStructureInspection.swift#L73-L86), [PDFAnnotationTests.swift:304](../../../Tests/GraphiteAppleTests/PDFAnnotationTests.swift#L304)). The controller composes sentences into `message` (for example [RecordingController.swift:115](../../../Sources/GraphiteApple/RecordingController.swift#L115), [302](../../../Sources/GraphiteApple/RecordingController.swift#L302), [590](../../../Sources/GraphiteApple/RecordingController.swift#L590)). The failure message shows the private recovery path ([312](../../../Sources/GraphiteApple/RecordingController.swift#L312), "Your recording remains at \(source.path)"). Views show `error.localizedDescription` directly, for example [PDFPane.swift:354](../../../Sources/GraphiteUI/PDFPane.swift#L354) and [GraphitePDFView.swift:1375](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1375).
- **Why it matters:** nothing can be localised, tests assert on English text, and an Application Support path in a menu is implementation jargon RULES.md forbids ("Keep user-facing copy free of implementation jargon").
- **Fix direction:** typed errors and reasons, one presenter that maps them to catalogue strings. `PDFStructureInspection` returns `[PDFCatalogEntryKind]`.

#### CC-LECTURE-05 Tasks have no owner, and fixed delays order work
- **Severity:** Medium
- **Evidence:** `Task { }` without a stored handle in the controller ([RecordingController.swift:226](../../../Sources/GraphiteApple/RecordingController.swift#L226), [232](../../../Sources/GraphiteApple/RecordingController.swift#L232), [276](../../../Sources/GraphiteApple/RecordingController.swift#L276), [335](../../../Sources/GraphiteApple/RecordingController.swift#L335), [510](../../../Sources/GraphiteApple/RecordingController.swift#L510), [548](../../../Sources/GraphiteApple/RecordingController.swift#L548), [601](../../../Sources/GraphiteApple/RecordingController.swift#L601), [609](../../../Sources/GraphiteApple/RecordingController.swift#L609)); in the embed ([EmbeddedPDFViewer.swift:115](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L115), [130](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L130), [396](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L396), [411](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L411), [434](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L434), [493](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L493)); in page commands ([PDFPane.swift:610](../../../Sources/GraphiteUI/PDFPane.swift#L610), [624](../../../Sources/GraphiteUI/PDFPane.swift#L624), [664](../../../Sources/GraphiteUI/PDFPane.swift#L664), [687](../../../Sources/GraphiteUI/PDFPane.swift#L687)). 49 in the area (reconnaissance). Timers as ordering: 0.4 s resize end ([GraphitePDFView.swift:405](../../../Sources/GraphiteUI/GraphitePDFView.swift#L405)), 0.2 s rendering scale ([880](../../../Sources/GraphiteUI/GraphitePDFView.swift#L880)), 1 s undo check ([PDFPaneHealth.swift:278](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L278)), a 30 s sleep before a fallback publish ([RecordingController.swift:335-339](../../../Sources/GraphiteApple/RecordingController.swift#L335-L339)), a 1.5 s sleep before release that ignores cancellation (`try?`, [EmbeddedPDFViewer.swift:494](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L494)); `DispatchQueue.main.async` as "after SwiftUI's update" ([GraphitePDFView.swift:449](../../../Sources/GraphiteUI/GraphitePDFView.swift#L449), [1507](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1507), [1515](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1515)).
- **Why it matters:** a page-command task that outlives its pane writes `errorMessage` into a session nobody shows. Two `switchCamera` taps race, and the later answer does not reliably win. Delays that work on the simulator are untested on a busy iPad.
- **Fix direction:** each model owns its tasks and cancels them on teardown; "latest answer wins" uses one shared primitive; the debounces become named constants owned by one scheduler type with an injectable clock.

#### CC-LECTURE-06 SwiftUI updates and view creation write model state
- **Severity:** Medium
- **Evidence:** `readAloudMarkers`, evaluated in `body` ([PDFPane.swift:186](../../../Sources/GraphiteUI/PDFPane.swift#L186)), writes the marker cache ([120-129](../../../Sources/GraphiteUI/PDFPane.swift#L120-L129), [927-931](../../../Sources/GraphiteUI/PDFPane.swift#L927-L931)). `updateUIView` calls `coordinator.update(input:)` ([GraphitePDFView.swift:286](../../../Sources/GraphiteUI/GraphitePDFView.swift#L286)), whose `defer` calls `pictureSelection?.update()` ([1005](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1005)), which sets the observable `session.selectedPicture = nil` ([PDFPictureControls.swift:221](../../../Sources/GraphiteUI/PDFPictureControls.swift#L221)). `makeUIView` sets `session.livePlace` and `session.pdfView` ([GraphitePDFView.swift:266](../../../Sources/GraphiteUI/GraphitePDFView.swift#L266), [275](../../../Sources/GraphiteUI/GraphitePDFView.swift#L275)).
- **Why it matters:** writing observed state during an update schedules another update. The file's own comment records an endless update loop of this family ([GraphitePDFView.swift:1493-1497](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1493-L1497)).
- **Fix direction:** selection pruning happens in the session when pages or pictures change; the marker cache moves into `PDFPaneReadAloudModel`. Rule refinement: a memo cache marked `@ObservationIgnored`, as `PDFSession.cachedOutlineEntries` is ([PDFSession.swift:303](../../../Sources/GraphiteUI/PDFSession.swift#L303)), is harmless in a getter. The rule should forbid writes to *observed* state, not every memo.

#### CC-LECTURE-07 Flows with more than two states are kept as sets of booleans
- **Severity:** Medium
- **Evidence:** the recording controller's `state` plus `isPublishing`, `isAbandoningRecorder`, `startAttempt`, `pendingResume`, `resumesWhenInterruptionEnds` ([RecordingController.swift:51-78](../../../Sources/GraphiteApple/RecordingController.swift#L51-L78)), combined in guards such as [268](../../../Sources/GraphiteApple/RecordingController.swift#L268), [293](../../../Sources/GraphiteApple/RecordingController.swift#L293) and [337](../../../Sources/GraphiteApple/RecordingController.swift#L337). `VideoRecording` has `acceptsSamples`, `isInterrupted` and `hasStopped` ([VideoRecording.swift:55-57](../../../Sources/GraphiteApple/VideoRecording.swift#L55-L57)). The page canvas has `hasRestoredStoredInk` and `isRestoringStoredInk`, three states in two booleans ([GraphitePDFView.swift:587-590](../../../Sources/GraphiteUI/GraphitePDFView.swift#L587-L590)). The embed has `isAnnotating`, `isPreparingToAnnotate` and `isVisible` ([EmbeddedPDFViewer.swift:33-37](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L33-L37)).
- **Why it matters:** impossible combinations are representable, for example `isRestoringStoredInk && !hasRestoredStoredInk`. Every guard must list the right subset, and the tests probe combinations by hand.
- **Fix direction:** enums with associated values: `RecordingFlow`, `VideoCaptureState { case accepting, paused, interrupted, stopped }`, `StoredInkRestoration { case notStarted, decoding, restored }`, `EmbedAnnotationState { case idle, preparing, annotating }`.

#### CC-LECTURE-08 Literal sizes, ratios and delays in logic
- **Severity:** Low
- **Evidence:** template line widths 0.4, 0.9 and 1, the Cornell ratios 0.2 and 0.3, and the greys 0.77 and 0.67 ([PDFTemplateGenerator.swift:104](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L104), [126](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L126), [135](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L135), [140-141](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L140-L141), [177-178](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L177-L178)); the size limits 72…2880 ([62](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L62)); word-hit insets −8/−6 ([GraphitePDFView.swift:972](../../../Sources/GraphiteUI/GraphitePDFView.swift#L972)); text context ±40 ([PDFPane.swift:142-143](../../../Sources/GraphiteUI/PDFPane.swift#L142-L143)); zoom tolerances 0.999 and 1.001 ([PDFPaneHealth.swift:335](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L335)); the 1 s timer ([180](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L180)).
- **Why it matters:** the template numbers define persisted page content, so they must not drift by accident.
- **Fix direction:** named constants with units, grouped in `PaperTemplateGeometry` and the respective owners. Most of the area already does this (for example [MoviePartWriter.swift:11-21](../../../Sources/GraphiteApple/MoviePartWriter.swift#L11-L21)).

#### CC-LECTURE-09 Force unwraps in file-parsing code
- **Severity:** Low
- **Evidence:** `inUseEntries[…]!` at [PDFObjectCompaction.swift:226](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L226) (twice), [231](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L231), [232](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L232) and [271](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L271). 5 force unwraps, counted by reading.
- **Why it matters:** RULES.md forbids force unwraps in file-handling code. These are safe by construction (the keys come from the same dictionary), but the next edit may not keep that true.
- **Fix direction:** carry `(number, entry)` pairs through the sort instead of looking keys up again.

#### CC-LECTURE-10 Tests are named after audit rounds, assert on English text and poll with sleeps
- **Severity:** Low
- **Evidence:** `AppleRecordingAccessFixTests.swift` holds `AppleRecordingAccessRecordingTests` and `AppleRecordingAccessFolderTests` ([AppleRecordingAccessFixTests.swift:10](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L10), [269](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L269)); `ApplePdfFixTests.swift` and `UiPdfSessionFixTests.swift` are named after fixes. Message assertions: [AppleRecordingAccessFixTests.swift:175](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L175), [PDFAnnotationTests.swift:304](../../../Tests/GraphiteAppleTests/PDFAnnotationTests.swift#L304), [RecordingControlsTests.swift:39-43](../../../Tests/GraphiteUITests/RecordingControlsTests.swift#L39-L43). Sleep polling: [AppleRecordingAccessFixTests.swift:46-52](../../../Tests/GraphiteAppleTests/AppleRecordingAccessFixTests.swift#L46-L52).
- **Why it matters:** the recording tests cannot be found by the type they pin, and any copy edit breaks them.
- **Fix direction:** `RecordingControllerPublicationTests`, `PDFSessionProtectionTests`; assert on typed reasons; await state changes through an observation helper.

#### CC-LECTURE-11 Code no production path uses
- **Severity:** Low
- **Evidence:** `PDFTemplateGenerator.pageData(template:matching:)` has no caller in `Sources/**` (grep `pageData\(template:`; [PDFTemplateGenerator.swift:72-74](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L72-L74)); public `PDFStructureInspection.hasDigitalSignature(in:)` is called only by tests ([PDFStructureInspection.swift:34-37](../../../Sources/GraphiteApple/PDFStructureInspection.swift#L34-L37)); a detached doc comment describes no declaration ([PDFPane.swift:848-853](../../../Sources/GraphiteUI/PDFPane.swift#L848-L853)); `PDFSession.pictures(on:)` only forwards to `PDFPageManager.pictures(on:)` ([PDFSessionPictures.swift:24-26](../../../Sources/GraphiteUI/PDFSessionPictures.swift#L24-L26)).
- **Why it matters:** dead public API keeps tests alive for paths production never takes.
- **Fix direction:** delete, or make the tests target the production entry.

#### CC-LECTURE-12 A bounded sleep loop throttles the camera queue (deliberate, and the rule needs an exception)
- **Severity:** Low
- **Evidence:** `Thread.sleep(forTimeInterval: readinessPollSeconds)` up to `maximumReadinessWaitSeconds` (0.1 s) per sample on the capture queue ([MoviePartWriter.swift:13-16](../../../Sources/GraphiteApple/MoviePartWriter.swift#L13-L16), [168-177](../../../Sources/GraphiteApple/MoviePartWriter.swift#L168-L177)).
- **Why it matters:** this is backpressure, which makes the camera drop frames instead of queueing them, and it is documented. A blanket "no sleep loops" rule would forbid it.
- **Fix direction:** keep it. Rule refinement: a bounded wait on a dedicated media queue, with named limits and a documented reason, is allowed; waiting for *other app work* is not.

#### CC-LECTURE-13 The ink tracker is advanced before the edit is known to succeed
- **Severity:** Medium
- **Evidence:** `canvas.inkTracker.update(…)` mutates the tracker ([GraphitePDFView.swift:1366](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1366)), then `try session.apply(.updateInk(update))` can throw ([1367](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1367); throws at [PDFSession.swift:366-367](../../../Sources/GraphiteUI/PDFSession.swift#L366-L367) and [PDFPageManager.swift:116](../../../Sources/GraphiteApple/PDFPageManager.swift#L116)). After a throw, `recordedDrawing` is not advanced but the tracker already maps the new strokes to names ([PDFPencilInk.swift:156-158](../../../Sources/GraphiteApple/PDFPencilInk.swift#L156-L158)), so the retry in `recordUnrecordedInk` finds no added strokes. The history path does it right: it updates a local copy ([PDFEditHistory.swift:309-312](../../../Sources/GraphiteUI/PDFEditHistory.swift#L309-L312)).
- **Why it matters:** if the throw ever becomes reachable, the strokes stay on the canvas and never reach the file. Today the canvas takes no touches while the PDF is protected ([GraphitePDFView.swift:1325](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1325), [PDFPane.swift:290](../../../Sources/GraphiteUI/PDFPane.swift#L290)), so this is a latent hazard, not a reproduced loss.
- **Fix direction:** `PDFPageInkTracker.update` becomes a pure function returning `(PDFInkUpdate, PDFPageInkTracker)`; the recorder commits the new tracker only after `apply` succeeds.

#### CC-LECTURE-14 Swallowed errors hide leftovers in the recovery folder
- **Severity:** Low
- **Evidence:** `try? RecordingRecoveryFolder.remove(recording)` after a recovery ([RecordingController.swift:364](../../../Sources/GraphiteApple/RecordingController.swift#L364)). `remove` throws at its first missing file and skips the later parts, the joined file and the manifest ([RecordingRecovery.swift:157-162](../../../Sources/GraphiteCore/RecordingRecovery.swift#L157-L162)). It is called after `saveAsM4A` or `saveAsMP4` has already deleted the media file ([RecordingController.swift:372-373](../../../Sources/GraphiteApple/RecordingController.swift#L372-L373), [649-650](../../../Sources/GraphiteApple/RecordingController.swift#L649-L650)), so it always throws at its first line. 64 `try?` in the area (reconnaissance).
- **Why it matters:** the call is dead in practice, and when it is not, leftovers are silently kept and offered again (see BUG-LECTURE-01).
- **Fix direction:** `remove` deletes every item it can and reports what failed; the caller states which leftovers are harmless.

#### CC-LECTURE-15 Unsafe concurrency escapes are spread across files, each with a stated invariant
- **Severity:** Low
- **Evidence:** 10 `@unchecked Sendable`, 3 `nonisolated(unsafe)` and 14 `MainActor.assumeIsolated` (reconnaissance), for example [CameraCaptureSource.swift:15-18](../../../Sources/GraphiteApple/CameraCaptureSource.swift#L15-L18), [MoviePartWriter.swift:217-220](../../../Sources/GraphiteApple/MoviePartWriter.swift#L217-L220), [VideoRecording.swift:158-159](../../../Sources/GraphiteApple/VideoRecording.swift#L158-L159), [RecordingController.swift:344](../../../Sources/GraphiteApple/RecordingController.swift#L344), [PDFSession.swift:48-50](../../../Sources/GraphiteUI/PDFSession.swift#L48-L50). Each states its invariant in a comment.
- **Why it matters:** the escapes are justified, but they cannot all live in one primitives file: a `CMSampleBuffer` handover must happen at the AVFoundation call. The `recordingSettings` dictionary ([RecordingController.swift:344-348](../../../Sources/GraphiteApple/RecordingController.swift#L344-L348)) needs no escape at all: it can be a `static func` or a typed struct.
- **Fix direction:** rule refinement: allow escapes next to the platform call, listed in a per-module allow-list with the invariant; remove the escapes that a value type avoids.

## 5. Defects and latent bugs

#### BUG-LECTURE-01 One lecture whose save failed is offered again as a second recording and can be saved twice
- **Trigger:** an audio recording stops while its destination folder is gone or the name is taken, so publication fails. The user then opens the vault again (switching away and back, or relaunching while the controller still holds the failure), and saves the offered recording. Afterwards they use Try Saving Again on the original.
- **Path:**
  1. Stop leads to `finish(successfully:)` ([RecordingController.swift:291-307](../../../Sources/GraphiteApple/RecordingController.swift#L291-L307)), then `saveAsM4A` ([369-371](../../../Sources/GraphiteApple/RecordingController.swift#L369-L371)). `convertedToM4A` writes `X.m4a` beside `X.caf` ([378-394](../../../Sources/GraphiteApple/RecordingController.swift#L378-L394)).
  2. `publish` throws for a missing folder or a taken name ([14-16](../../../Sources/GraphiteApple/RecordingController.swift#L14-L16), [21-23](../../../Sources/GraphiteApple/RecordingController.swift#L21-L23)) before anything is removed. `finish` sets `.failed` and keeps `recoveryURL = X.caf` ([310-313](../../../Sources/GraphiteApple/RecordingController.swift#L310-L313)). `X.m4a` stays in the recovery folder.
  3. Switching vaults is allowed in `.failed`, because the guard checks only `isActive` ([WorkspaceModel.swift:262](../../../Sources/GraphiteUI/WorkspaceModel.swift#L262), [RecordingState.swift:8](../../../Sources/GraphiteCore/RecordingState.swift#L8)). Opening a vault calls `checkForUnfinishedRecordings` ([WorkspaceModel.swift:343](../../../Sources/GraphiteUI/WorkspaceModel.swift#L343)), whose guard also passes in `.failed` ([WorkspaceRecordingRecovery.swift:16-19](../../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L16-L19)).
  4. `unfinishedRecordings` excludes only `recoveryURL` (`X.caf`) ([RecordingController.swift:351-354](../../../Sources/GraphiteApple/RecordingController.swift#L351-L354)). `recordings(in:)` lists `X.m4a`: `m4a` is a recovery media extension, it is larger than 4096 bytes and it is not a later part ([RecordingRecovery.swift:50](../../../Sources/GraphiteCore/RecordingRecovery.swift#L50), [126-141](../../../Sources/GraphiteCore/RecordingRecovery.swift#L126-L141)). Its manifest resolves to `X.json`, the original's ([147](../../../Sources/GraphiteCore/RecordingRecovery.swift#L147), [59-61](../../../Sources/GraphiteCore/RecordingRecovery.swift#L59-L61)), so the offer filter keeps it for the original vault ([WorkspaceRecordingRecovery.swift:7-12](../../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L7-L12)).
  5. Save to Vault calls `recover` ([WorkspaceRecordingRecovery.swift:23-31](../../../Sources/GraphiteUI/WorkspaceRecordingRecovery.swift#L23-L31)), then `RecordingController.recover` and `saveAsM4A(X.m4a)`, where `converted == source` ([RecordingController.swift:359-365](../../../Sources/GraphiteApple/RecordingController.swift#L359-L365), [381](../../../Sources/GraphiteApple/RecordingController.swift#L381)). The file is published and `X.json` is removed ([373](../../../Sources/GraphiteApple/RecordingController.swift#L373)).
  6. The controller still holds `X.caf` in `.failed`. Try Saving Again calls `retryRecordingPublication`, which picks a fresh unique path ([WorkspaceModel.swift:1148-1165](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1148-L1165)), and publishes the same lecture a second time.
  The code knows the converted M4A is offered as a separate recording: `discardRecoveredRecording` removes it for exactly that reason ([RecordingController.swift:421-428](../../../Sources/GraphiteApple/RecordingController.swift#L421-L428)). Only the discard path handles it.
- **Effect:** the recovery offer shows a lecture the toolbar also reports as waiting to be saved. Saving both produces two M4A files of the same lecture in the vault. After a relaunch (controller idle), `X.caf` and `X.m4a` are both offered; saving `X.m4a` first removes the shared manifest, so `X.caf` is then offered without a destination and saved as "Recovered recording …" in the attachment folder.
- **Platforms / reach:** iPad, iPhone and Mac; failure path only (the destination folder removed or renamed during recording, or the name taken).
- **Confidence:** Traced (every step read). The order in which the two files are offered after a relaunch depends on `sorted` over equal `startedAt` values ([RecordingRecovery.swift:152](../../../Sources/GraphiteCore/RecordingRecovery.swift#L152)) and was not settled.

#### BUG-LECTURE-02 A digitally signed PDF embedded in a note says it is password protected
- **Trigger:** embed a PDF that is digitally signed but not encrypted, `![[signed.pdf]]`, and view the note.
- **Path:** `isProtected` is true for a signed PDF that has not been accepted for editing ([PDFSession.swift:339](../../../Sources/GraphiteUI/PDFSession.swift#L339)). The embed's banner shows the password text for every protected session ([EmbeddedPDFViewer.swift:262-263](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L262-L263)). Annotate is disabled through `canStartAnnotating` ([283-286](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L283-L286)), and the embed offers no "Edit Anyway" (the pane does, [PDFPane.swift:313-319](../../../Sources/GraphiteUI/PDFPane.swift#L313-L319)).
- **Effect:** the user reads "This PDF is protected by a password…" for a file that has no password, and gets no hint that the signature is the reason.
- **Platforms / reach:** iPad and iPhone (the banner is shared, but Annotate exists only with UIKit, [EmbeddedPDFViewer.swift:180-198](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L180-L198)); also the Mac, where the banner shows; normal path for every signed PDF.
- **Confidence:** Traced.

#### BUG-LECTURE-03 The embedded viewer's page field rejects page numbers typed in non-ASCII digits
- **Trigger:** on an Arabic, Persian or Devanagari keyboard (or full-width CJK input), type a page number into the page field of an embedded PDF.
- **Path:** `goToTypedPage` parses with `Int(pageText…)` ([EmbeddedPDFViewer.swift:370-377](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L370-L377)). `Int(_:)` with a `String` accepts ASCII digits only, so it returns nil and the field is reset to the current page ([373](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L373)). The PDF pane's Go to Page accepts any script's decimal digits by design ([PDFPane.swift:545-558](../../../Sources/GraphiteUI/PDFPane.swift#L545-L558)). The number-pad keyboard is requested in both ([EmbeddedPDFViewer.swift:223](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L223), [PDFPane.swift:567](../../../Sources/GraphiteUI/PDFPane.swift#L567)).
- **Effect:** the typed page is ignored, with no message.
- **Platforms / reach:** iPad, iPhone and Mac; normal path for users of those keyboards.
- **Confidence:** Partly traced. The behaviour of `Int(_:)` for non-ASCII digits comes from the Swift standard library's documented parsing, not from code in the snapshot.

#### BUG-LECTURE-04 On the Mac, "Open Settings" for a denied microphone opens the camera privacy pane
- **Trigger:** on a Mac, start a video recording with microphone access denied, then choose Open Settings in the recording menu.
- **Path:** `requireAccess(to: .audio…)` throws `.microphoneDenied` ([CameraCaptureSource.swift:47](../../../Sources/GraphiteApple/CameraCaptureSource.swift#L47), [117-124](../../../Sources/GraphiteApple/CameraCaptureSource.swift#L117-L124)). `startVideo` stores it as `accessProblem` ([RecordingController.swift:497](../../../Sources/GraphiteApple/RecordingController.swift#L497)). `canBeChangedInSettings` is true for it ([VideoCapture.swift:66-70](../../../Sources/GraphiteApple/VideoCapture.swift#L66-L70)), so the menu shows Open Settings ([RecordingControls.swift:35-37](../../../Sources/GraphiteUI/RecordingControls.swift#L35-L37)). On macOS, `settingsLocation` is always `…?Privacy_Camera` ([RecordingControls.swift:107-112](../../../Sources/GraphiteUI/RecordingControls.swift#L107-L112)).
- **Effect:** System Settings opens on Camera, where the needed switch is not.
- **Platforms / reach:** Mac only; permission-denied path. On iPad and iPhone the URL opens Graphite's own settings page, which holds both switches.
- **Confidence:** Traced.

## 6. What to keep

| # | Sound design | Evidence | Why it is sound |
| --- | --- | --- | --- |
| 1 | Immutable `PDFEdit` commands applied to the live document and replayed on a baseline snapshot in an actor | [PDFPageManager.swift:21-24](../../../Sources/GraphiteApple/PDFPageManager.swift#L21-L24), [PDFPageManager.swift:331-351](../../../Sources/GraphiteApple/PDFPageManager.swift#L331-L351), [PDFPageManager.swift:477-503](../../../Sources/GraphiteApple/PDFPageManager.swift#L477-L503) | A live `PDFDocument` never crosses actors; the file and the open document cannot disagree, and undo is ordinary edits. |
| 2 | Revision-checked atomic save with a coordinated read; the written bytes become the baseline only on success | [PDFPageManager.swift:479-501](../../../Sources/GraphiteApple/PDFPageManager.swift#L479-L501), [PDFSession.swift:457-462](../../../Sources/GraphiteUI/PDFSession.swift#L457-L462) | External edits are never overwritten (OBJECTIVE.md), and a failed save keeps every edit. |
| 3 | Baseline copies named with the process identifier and cleaned once per launch | [PDFSession.swift:10-46](../../../Sources/GraphiteUI/PDFSession.swift#L10-L46) | iOS skips deinitialisers on termination; textbook-sized copies do not pile up, and a live copy is never removed. |
| 4 | Conservative compaction: only the single uncompressed cross-reference table; incremental updates, cross-reference streams and encrypted files are refused; the result must open with every page or PDFKit's output is kept | [PDFObjectCompaction.swift:196-225](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L196-L225), [PDFPageManager.swift:516-526](../../../Sources/GraphiteApple/PDFPageManager.swift#L516-L526), `PDFObjectCompactionTests` (9 tests, [PDFObjectCompactionTests.swift:108-329](../../../Tests/GraphiteAppleTests/PDFObjectCompactionTests.swift#L108-L329)) | A size optimisation that cannot corrupt a user's PDF. |
| 5 | Decide-then-do in compaction: a planner reads, a plan writes into a sink | [PDFObjectCompaction.swift:98-174](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L98-L174), [180-303](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L180-L303) | The same plan writes to memory (export) or to a file (save), and is testable without I/O. |
| 6 | Visible ink is standard `/Ink` with `/InkList` centre lines and a filled-outline appearance; the re-editing record sits on exactly one carrier annotation | [PDFInkAnnotation.swift:35-141](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L35-L141), [PDFPageManager.swift:276-305](../../../Sources/GraphiteApple/PDFPageManager.swift#L276-L305) | Every PDF reader shows the ink; Graphite metadata is never needed to render it (OBJECTIVE.md). |
| 7 | An ink group is editable only when stroke names match annotations one to one; otherwise it stays read-only and new ink goes into a new group | [PDFInkAnnotation.swift:260-300](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L260-L300) | Another application's edits are never overwritten by stale re-editing data. |
| 8 | Incremental ink conversion by stroke fingerprint at PencilKit's stored 32-bit precision | [PDFPencilInk.swift:19-76](../../../Sources/GraphiteApple/PDFPencilInk.swift#L19-L76), [132-163](../../../Sources/GraphiteApple/PDFPencilInk.swift#L132-L163) | Stroke cost does not grow with the page; undo survives a canvas being rebuilt. `hash` uses a subset of the fields `==` compares, so `Hashable` is consistent. |
| 9 | Ink update merging bounded by the running save | [PDFInkAnnotation.swift:222-242](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L222-L242), [PDFSession.swift:405-414](../../../Sources/GraphiteUI/PDFSession.swift#L405-L414) | The edit list grows with pages touched, and a save in progress never loses a merged stroke. |
| 10 | Kept canvas reused in a new overlay when PDFKit drops the page view | [GraphitePDFView.swift:1199-1211](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1199-L1211) | Strokes drawn since the last save survive scrolling. |
| 11 | Unrecorded ink is recorded at release, before saves and before rebuilds | [GraphitePDFView.swift:1332-1338](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1332-L1338), [1394-1398](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1394-L1398), [PDFSession.swift:438-440](../../../Sources/GraphiteUI/PDFSession.swift#L438-L440) | No path drops a stroke a canvas shows. |
| 12 | Session-owned undo naming pages through `PDFHistoryPage` boxes; steps are ordinary edits | [PDFEditHistory.swift:19-25](../../../Sources/GraphiteUI/PDFEditHistory.swift#L19-L25), [94-106](../../../Sources/GraphiteUI/PDFEditHistory.swift#L94-L106), [134-138](../../../Sources/GraphiteUI/PDFEditHistory.swift#L134-L138) | Undo survives view rebuilds and page moves, and two PDFs never share a history. |
| 13 | Deleting pages first copies them for Undo, and refuses to delete without the copy | [PDFEditHistory.swift:217-252](../../../Sources/GraphiteUI/PDFEditHistory.swift#L217-L252) | Undo can always restore exactly what saving would have written. |
| 14 | Outline and link destinations are resolved before pages move and restored after | [PDFPageManager.swift:381-464](../../../Sources/GraphiteApple/PDFPageManager.swift#L381-L464) | Works around PDFKit's lazy destinations that would point at page 1. |
| 15 | Page-tree rewrites re-set Graphite keys and back up `/NM` | [PDFPageManager.swift:307-328](../../../Sources/GraphiteApple/PDFPageManager.swift#L307-L328) | Re-editing data and names survive PDFKit's rewrite (keep the behaviour, fix the duplicated key list per OCP-LECTURE-03). |
| 16 | Encrypted and permission-restricted PDFs are never written; form widgets are made read-only | [PDFSession.swift:346](../../../Sources/GraphiteUI/PDFSession.swift#L346), [365-367](../../../Sources/GraphiteUI/PDFSession.swift#L365-L367), [GraphitePDFView.swift:182-189](../../../Sources/GraphiteUI/GraphitePDFView.swift#L182-L189) | PDFKit would drop encryption or typed form values silently. |
| 17 | Bounded stream decoding against decompression bombs | [PDFDrawingStreamDecoder.swift:26-89](../../../Sources/GraphiteApple/PDFDrawingStreamDecoder.swift#L26-L89), [292-327](../../../Sources/GraphiteApple/PDFDrawingStreamDecoder.swift#L292-L327) | A 1 MB embed cannot demand a gigabyte; RULES.md's "bound untrusted metadata". |
| 18 | Drawing PDF verified by reading the finished file back before returning it | [PDFDrawingFile.swift:31-37](../../../Sources/GraphiteApple/PDFDrawingFile.swift#L31-L37) | No unreadable drawing is ever saved. |
| 19 | Recording to crash-tolerant media: IMA4 CAF, 1 s MP4 fragments, a new part per interruption, parts joined by passthrough | [RecordingController.swift:342-348](../../../Sources/GraphiteApple/RecordingController.swift#L342-L348), [MoviePartWriter.swift:6-12](../../../Sources/GraphiteApple/MoviePartWriter.swift#L6-L12), [VideoRecording.swift:25-30](../../../Sources/GraphiteApple/VideoRecording.swift#L25-L30), [MoviePartWriter.swift:235-294](../../../Sources/GraphiteApple/MoviePartWriter.swift#L235-L294) | A lecture survives the app being killed; no re-encoding. |
| 20 | Publication into the vault is atomic with "expect absent", and the recovery copy is removed only after | [RecordingController.swift:9-29](../../../Sources/GraphiteApple/RecordingController.swift#L9-L29) | Never overwrites a vault file; never loses the only copy. |
| 21 | A recording that could not be saved blocks new recordings | [RecordingController.swift:86-88](../../../Sources/GraphiteApple/RecordingController.swift#L86-L88) | The only copy of a lecture cannot be replaced by accident. |
| 22 | Start-attempt token and recorder identity checks on callbacks | [RecordingController.swift:109-153](../../../Sources/GraphiteApple/RecordingController.swift#L109-L153), [243-261](../../../Sources/GraphiteApple/RecordingController.swift#L243-L261) | Cancelled or overtaken starts leave nothing; a stale recorder cannot finish the current recording. |
| 23 | `VideoCaptureSource` seam and injectable `RecordingStorage` | [VideoCapture.swift:81-102](../../../Sources/GraphiteApple/VideoCapture.swift#L81-L102), [VideoRecording.swift:8-20](../../../Sources/GraphiteApple/VideoRecording.swift#L8-L20) | A real substitution (camera vs synthetic) exercised by 21 tests through the production writer. |
| 24 | `RecordingState` predicates as the one place transitions are allowed | [RecordingState.swift:3-9](../../../Sources/GraphiteCore/RecordingState.swift#L3-L9) | Views and the controller ask the same questions (`canStart`, `canStop`, `canResume`). |
| 25 | Watchdog walks the main thread's frames into a preallocated buffer while it is suspended, and is off under a debugger | [MainThreadWatchdog.swift:79-81](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L79-L81), [159-193](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L159-L193), [86](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L86) | No allocation while another thread is stopped, so no deadlock. |
| 26 | Diagnostics written off the asking thread, outside the vault, bounded to 80 files | [DiagnosticRecords.swift:14-16](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L14-L16), [44-74](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L44-L74) | Evidence never touches user files and never grows without bound. |
| 27 | Pure, tested decision values: `UnansweredGestureCount`, `PDFResizeZoom`, `RecordingPreviewLayout`, `RecordingControlModel`, `PDFCitation`, `PDFEmbedOptions`, `PageCoordinates` | [PDFPaneHealth.swift:8-77](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L8-L77), [GraphitePDFView.swift:540-564](../../../Sources/GraphiteUI/GraphitePDFView.swift#L540-L564), [RecordingControls.swift:105-149](../../../Sources/GraphiteUI/RecordingControls.swift#L105-L149), [RecordingControls.swift:256-298](../../../Sources/GraphiteUI/RecordingControls.swift#L256-L298), [PDFCitation.swift:6-63](../../../Sources/GraphiteCore/PDFCitation.swift#L6-L63), [PDFEmbedOptions.swift:5-52](../../../Sources/GraphiteApple/PDFEmbedOptions.swift#L5-L52), [PageCoordinates.swift:6-23](../../../Sources/GraphiteCore/PageCoordinates.swift#L6-L23) | The shape the rest of the area should take: inputs in, value out. |
| 28 | Thumbnails: page content drawn off the main actor from a mapped copy reopened every 64 pages; byte-bounded shared cache with weak page keys | [PDFThumbnailRenderer.swift:12-34](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L12-L34), [161-187](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L161-L187), [260-305](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L260-L305) | No whole-textbook rasterising; a released PDF keeps nothing alive. |
| 29 | Page identity by object, not index, for selection, rows and drags; drag payload tied to its session | [PDFPagesSidebar.swift:205-231](../../../Sources/GraphiteUI/PDFPagesSidebar.swift#L205-L231), [PDFThumbnailRenderer.swift:321-331](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L321-L331), [PDFPagesSidebar.swift:299-313](../../../Sources/GraphiteUI/PDFPagesSidebar.swift#L299-L313) | Inserting or moving pages never moves a selection onto other pages. |
| 30 | Pictures as standard stamps whose appearance is the picture; bytes under a prefixed key; upright pictures stay under the key older builds read | [PDFPicture.swift:7-12](../../../Sources/GraphiteApple/PDFPicture.swift#L7-L12), [35-38](../../../Sources/GraphiteApple/PDFPicture.swift#L35-L38), [122-124](../../../Sources/GraphiteApple/PDFPicture.swift#L122-L124) | Every reader shows the picture; older builds keep working on upright ones. |
| 31 | The display-only delegate makes stamps draw smoothly without changing the file; written documents never get it | [PDFPicture.swift:278-295](../../../Sources/GraphiteApple/PDFPicture.swift#L278-L295), [PDFPageManager.swift:105-109](../../../Sources/GraphiteApple/PDFPageManager.swift#L105-L109), [PDFPageManager.swift:124](../../../Sources/GraphiteApple/PDFPageManager.swift#L124) | Display quality without writing anything. |
| 32 | One embed annotates a PDF at a time; other copies are saved first and a stale clean copy is refreshed | [EmbeddedPDFViewer.swift:644-668](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L644-L668) | Two copies never refuse each other's saves as external changes. |
| 33 | Autosave back-off as a pure static function | [PDFSession.swift:479-487](../../../Sources/GraphiteUI/PDFSession.swift#L479-L487) | Slow saves do not rewrite a textbook after every pause; testable with numbers alone. |

## 7. Blueprint for this area

### Target shape

| Type | Single responsibility | Seam |
| --- | --- | --- |
| `PDFEdit` (own file) | the closed vocabulary of document changes, with exhaustive derived properties | none (a value) |
| `PDFAnnotationKey` (enum, `CaseIterable`) | every Graphite annotation key and its persistence rule | none |
| `PDFEditApplier` | applies one edit to a `PDFDocument`, one function per edit family | none (pure over the document) |
| `PDFPageExport` + `ResolvedDestinations` | pages out as a PDF, destinations kept | none |
| `PDFFileService` (own file) | coordinated read, replay, write, compaction, atomic replace | `PDFFileSaving` protocol: production actor and a test fake (a real test need) |
| `PDFSignatureInspection` | the one signature rule | none |
| `PDFDocumentEditor` | live document plus edit log, versions, pending-ink writers | none |
| `PDFSaveController` | baseline, revision, autosave policy, conflicts, external checks | takes `PDFFileSaving` and a clock |
| `PDFEditHistory` | session undo with history pages | none |
| `PDFViewState` | page in view, kept place, writing mode, picture selection, requested navigation | none (views observe it) |
| `PDFProtection` | password, permissions, signatures, structure losses, and the accept intents | none (a value plus intents) |
| `PDFInkRecorder` | canvas drawing change → committed `PDFInkUpdate` + history step | `PDFInkSink` (2 members) |
| `PDFPageCanvasPool`, `PDFToolPaletteController`, `PDFTouchRouting`, `PDFTextMarkupInteraction`, `PDFReadAloudPenOverlay`, `PDFCanvasRepair` | one each, as in §3.1 | none beyond UIKit |
| `PDFAnnotationCoordinator` | PDFKit overlay provider and wiring only | none |
| `EmbeddedPDFViewerModel` | an embed's load, release, claim and conflict state | `EmbeddedPDFSessions` injected through the environment |
| `RecordingFlow` (enum) | the one recording state with associated values | none |
| `AudioRecordingSession`, `VideoRecordingSession` | one media kind each | `RecordingSession` protocol (two production implementations and a fake) |
| `AudioRecorder` port | wraps `AVAudioRecorder` and `AVAudioSession` | protocol with a production implementation and a fake |
| `RecordingPublisher` | convert, join, publish atomically | none |
| `RecordingRecoveryInventory` + `RecordingStore` | list, group, offer, remove unfinished recordings, throwing on failure | `RecordingStore` protocol (file implementation and a fake with the same errors) |
| `RecordingMessagePresenter` | typed reasons → catalogue strings | none |
| `DiagnosticRecordKind` + `Encodable` records | typed freeze evidence | `DiagnosticRecordWriter` injected (folder and clock) |

### Ordered steps (each leaves the app building and behaving the same)

1. **Safety net first.** Add the golden tests listed under the invariants (LECTURE-INV-01 to INV-08, INV-13 to INV-16) before any move.
2. **Registry and exhaustiveness.** Introduce `PDFAnnotationKey` and derive the preservation list from `allCases`; replace the three `default:` branches of `PDFEdit` with exhaustive switches (OCP-LECTURE-01, OCP-LECTURE-03).
3. **One owner per rule.** Merge the signature detectors into `PDFSignatureInspection` (LSP-LECTURE-01). Add `PDFPageCountRule`, `PageNumberInput.parse` (fixes BUG-LECTURE-03), `HexColor`, `PageRotation.quarterTurns` and the `UIView` ancestor/descendant walkers (CC-LECTURE-03).
4. **Split `PDFPageManager.swift` by responsibility** (pure file moves, then `PDFEditApplier` per edit family) (SRP-LECTURE-06).
5. **Ink recording.** Make `PDFPageInkTracker.update` return the new tracker instead of mutating; extract `PDFInkRecorder` behind `PDFInkSink`; commit the tracker after `apply` succeeds (CC-LECTURE-13).
6. **Coordinator split.** Extract the canvas pool, then the palette controller, touch routing (registry injected), markup interaction, Read Aloud pen overlay and canvas repair, one per step (SRP-LECTURE-01). Repairs become a typed enum (SRP-LECTURE-07).
7. **Session split.** Extract `PDFSaveController` with `PDFFileSaving`, then `PDFViewState` (navigation as an observed request), `PDFProtection` with intent methods, `PDFEditHistory`, `PDFOutlineModel`. Views receive the part they use (SRP-LECTURE-02, ISP-LECTURE-04, CC-LECTURE-06).
8. **Embed model.** Move lifecycle into `EmbeddedPDFViewerModel`; inject the registry per scene; show the protection reason from `PDFProtection` (fixes BUG-LECTURE-02) (SRP-LECTURE-04, DIP-LECTURE-01).
9. **Recording.** Add `RecordingStore` with throwing listings (LSP-LECTURE-05). Group a converted `X.m4a` with its `X.caf` as one recoverable recording, or write the conversion to a hidden file as the joined movie already is ([RecordingRecovery.swift:91-96](../../../Sources/GraphiteCore/RecordingRecovery.swift#L91-L96)) (fixes BUG-LECTURE-01). Add the `AudioRecorder` port and delete `adoptRecording` (LSP-LECTURE-03). Then `RecordingSession` with two implementations, then `RecordingFlow` replacing the flags (SRP-LECTURE-03, OCP-LECTURE-02, CC-LECTURE-07).
10. **Words.** Typed reasons and one presenter for recording, capture, PDF protection and structure losses; a per-problem settings destination (fixes BUG-LECTURE-04) (CC-LECTURE-04).
11. **Time and tasks.** Inject one clock; give every task an owner that cancels it; replace fixed delays with named debounces in one scheduler (CC-LECTURE-05, DIP-LECTURE-04).
12. **Diagnostics.** Typed record kinds and payloads; an injected writer (OCP-LECTURE-05, ISP-LECTURE-03).

### Behaviour that must be preserved

| ID | Invariant | Evidence | Test idea |
| --- | --- | --- | --- |
| LECTURE-INV-01 | Graphite annotation keys are exactly `GraphitePencilDrawingV1`, `GraphiteInkGroup`, `GraphiteInkStrokeNamesV1`, `GraphiteAnnotationName`, `GraphitePictureV1`, `GraphitePictureV2`, `GraphitePictureTurns`, `GraphitePictureRotation`, `GraphitePictureWidth`, `GraphitePictureHeight`. | [PDFPageManager.swift:77-103](../../../Sources/GraphiteApple/PDFPageManager.swift#L77-L103) | Golden list test over `PDFAnnotationKey.allCases`; a fixture PDF written by b13dec3 reads back editable. |
| LECTURE-INV-02 | Visible ink is standard `/Ink`: one `/InkList` path per visible segment (a one-point segment gets a second point 0.01 pt away), the appearance is the filled outline, the border width is at least 0.5, `shouldPrint` is set. | [PDFInkAnnotation.swift:111-141](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L111-L141) | Write a page with ink, reopen with CoreGraphics and count `/InkList` entries and `/AP` presence. |
| LECTURE-INV-03 | The re-editing record is on exactly one annotation, the group's first; stroke names are encoded as `"<count>:" + comma-joined names`. | [PDFPageManager.swift:285-304](../../../Sources/GraphiteApple/PDFPageManager.swift#L285-L304), [PDFInkAnnotation.swift:302-313](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L302-L313) | Replay the same edits twice and compare carrier and encoded names byte for byte. |
| LECTURE-INV-04 | The default ink group is `GraphitePageInkV1`; a page that already has it gets `GraphitePageInk-<UUID>`; a group is editable only when names and annotations match one to one; encoded drawings are bounded by `DrawingLimits.maximumPayloadBytes * 2`, names by 16 MiB. | [PDFInkAnnotation.swift:254-300](../../../Sources/GraphiteApple/PDFInkAnnotation.swift#L254-L300) | Remove one annotation of a group in another tool, then check the group is read-only and new ink goes to a new group. |
| LECTURE-INV-05 | Pictures are `/Stamp` annotations with bytes stored as `"base64:" + base64` under `GraphitePictureV1` when upright and `GraphitePictureV2` when turned; rotation, width and height are written only for turned pictures; at most 8 MiB per picture; a turned picture under V1 still reads turned. | [PDFPicture.swift:33-38](../../../Sources/GraphiteApple/PDFPicture.swift#L33-L38), [51-61](../../../Sources/GraphiteApple/PDFPicture.swift#L51-L61), [122-130](../../../Sources/GraphiteApple/PDFPicture.swift#L122-L130) | Round trip upright and turned pictures; read a fixture with a turned picture under V1. |
| LECTURE-INV-06 | Graphite's ink stays after its pictures in a page's annotation order; reordering touches only Graphite pictures and ink. | [PDFPageManager.swift:211-241](../../../Sources/GraphiteApple/PDFPageManager.swift#L211-L241) | Add a picture over ink and another app's stamp; assert annotation order after save. |
| LECTURE-INV-07 | Markup is standard `/Highlight`, `/Underline`, `/StrikeOut`, one quadrilateral per line in the order upper-left, upper-right, lower-left, lower-right as the text reads; names are set as `/NM` and in `GraphiteAnnotationName`. | [PDFMarkup.swift:224-260](../../../Sources/GraphiteApple/PDFMarkup.swift#L224-L260), [PDFPageManager.swift:557-568](../../../Sources/GraphiteApple/PDFPageManager.swift#L557-L568) | Highlight horizontal and vertical text; compare `QuadPoints` with expected arrays. |
| LECTURE-INV-08 | A page-tree change keeps every Graphite key and backs up `/NM`; outline and link destinations stay on their pages; entries to removed pages go (an entry with children loses only its destination). | [PDFPageManager.swift:307-351](../../../Sources/GraphiteApple/PDFPageManager.swift#L307-L351), [381-464](../../../Sources/GraphiteApple/PDFPageManager.swift#L381-L464) | Move and delete pages in a PDF with outline, links and all keys; reopen and assert. |
| LECTURE-INV-09 | Compaction runs only on a single uncompressed cross-reference table without `/Prev`, `/XRefStm` or `/Encrypt`; its output is used only when it opens with the same page count; otherwise PDFKit's file stays. | [PDFObjectCompaction.swift:196-225](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L196-L225), [PDFPageManager.swift:516-526](../../../Sources/GraphiteApple/PDFPageManager.swift#L516-L526), [PDFPageManager.swift:374-377](../../../Sources/GraphiteApple/PDFPageManager.swift#L374-L377) | Feed an incrementally updated file and an encrypted file; assert they are unchanged. |
| LECTURE-INV-10 | Bookmarks are written as top-level outline items labelled `"Page " + page label (or number)` with the destination at the page's visible top-left; that label prefix identifies them today. | [PDFSession.swift:165-171](../../../Sources/GraphiteUI/PDFSession.swift#L165-L171), [666-670](../../../Sources/GraphiteUI/PDFSession.swift#L666-L670), [PDFPageManager.swift:187-194](../../../Sources/GraphiteApple/PDFPageManager.swift#L187-L194), [546-554](../../../Sources/GraphiteApple/PDFPageManager.swift#L546-L554) | Bookmark pages rotated 0/90/180/270 and check the written destination point and label. |
| LECTURE-INV-11 | Encrypted, comment-forbidding or change-forbidding PDFs are never written; signed PDFs are not written until the user accepts invalidation. | [PDFSession.swift:333-339](../../../Sources/GraphiteUI/PDFSession.swift#L333-L339), [346](../../../Sources/GraphiteUI/PDFSession.swift#L346), [365-367](../../../Sources/GraphiteUI/PDFSession.swift#L365-L367), [PDFPageManager.swift:485-486](../../../Sources/GraphiteApple/PDFPageManager.swift#L485-L486) | Apply an edit to each kind; assert the error and an unchanged file. |
| LECTURE-INV-12 | A save replaces the file only at the revision read; the baseline moves only after success; edits being saved are not merged into. | [PDFPageManager.swift:477-503](../../../Sources/GraphiteApple/PDFPageManager.swift#L477-L503), [PDFSession.swift:448-477](../../../Sources/GraphiteUI/PDFSession.swift#L448-L477) | Change the file externally between edit and save; assert a conflict and that the edits remain. |
| LECTURE-INV-13 | Baseline copies are `tmp/Graphite-OpenPDF-<pid>-<UUID>.pdf`; copies of ended processes are removed at the first copy of a launch; history page copies over 1 MiB use the same naming. | [PDFSession.swift:11-43](../../../Sources/GraphiteUI/PDFSession.swift#L11-L43), [PDFEditHistory.swift:31-49](../../../Sources/GraphiteUI/PDFEditHistory.swift#L31-L49) | Create a file with a dead PID and one with the current PID; run `removeStaleBaselines`; assert only the dead one goes. |
| LECTURE-INV-14 | The recovery folder is `Application Support/Graphite/Recovery/Recordings`; media extensions `caf`, `m4a`, `mp4`; the manifest is `<stem>.json`, ISO 8601 dates, sorted keys, fields `vaultIdentifier`, `destinationPath`, `notePath`, `startedAt`; files of 4096 bytes or less are not offered. | [RecordingRecovery.swift:6-21](../../../Sources/GraphiteCore/RecordingRecovery.swift#L6-L21), [50-78](../../../Sources/GraphiteCore/RecordingRecovery.swift#L50-L78) | Golden manifest JSON round trip; a 4096-byte file is not listed. |
| LECTURE-INV-15 | Video parts are `Name.part-N.mp4` beside `Name.mp4` (part 1 is the file itself); the joined file is hidden `.Name.joined.mp4`; later parts are listed with their first part, or alone when it is gone. | [RecordingRecovery.swift:80-153](../../../Sources/GraphiteCore/RecordingRecovery.swift#L80-L153) | Extend `RecordingRecoveryTests` with a part 10 to check numeric (not lexical) ordering. |
| LECTURE-INV-16 | Recording file names are `<stem> Recording yyyy-MM-dd HH-mm.<m4a or mp4>` in the Gregorian calendar, made unique by the store. | [WorkspaceModel.swift:1120](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1120), [1171-1174](../../../Sources/GraphiteUI/WorkspaceModel.swift#L1171-L1174), [RecordingState.swift:19-24](../../../Sources/GraphiteCore/RecordingState.swift#L19-L24) | `recordingTimestamp(at:)` for a fixed date under several locales. |
| LECTURE-INV-17 | Audio records mono IMA4, 44.1 kHz in CAF and is published as AAC M4A via `AVAssetExportPresetAppleM4A`; a file with no playable duration is refused and kept. | [RecordingController.swift:342-348](../../../Sources/GraphiteApple/RecordingController.swift#L342-L348), [378-395](../../../Sources/GraphiteApple/RecordingController.swift#L378-L395) | Convert a short CAF and an empty CAF; check codec and refusal. |
| LECTURE-INV-18 | Video is H.264 without frame reordering at 2.2 bits/pixel, 30 fps expected, key frame at most every 2 s, AAC mono 44.1 kHz 96 kbit/s, MP4 with 1 s fragments; parts are joined by passthrough. | [MoviePartWriter.swift:12-29](../../../Sources/GraphiteApple/MoviePartWriter.swift#L12-L29), [81-94](../../../Sources/GraphiteApple/MoviePartWriter.swift#L81-L94), [277-281](../../../Sources/GraphiteApple/MoviePartWriter.swift#L277-L281) | Existing `testAVideoRecordingIsAnOrdinaryMP4WithH264VideoAndAACSound`, plus a check of the fragment interval. |
| LECTURE-INV-19 | A video does not start below 500 MiB free and stops itself below 250 MiB, checked every 60 frames. | [VideoRecording.swift:9-12](../../../Sources/GraphiteApple/VideoRecording.swift#L9-L12), [45](../../../Sources/GraphiteApple/VideoRecording.swift#L45), [247-255](../../../Sources/GraphiteApple/VideoRecording.swift#L247-L255) | Existing storage tests with an injected `RecordingStorage`. |
| LECTURE-INV-20 | Publication never overwrites (expects absent), checks the folder first, and removes the recovery copy only after success; a failed recording blocks new recordings. | [RecordingController.swift:9-29](../../../Sources/GraphiteApple/RecordingController.swift#L9-L29), [86-88](../../../Sources/GraphiteApple/RecordingController.swift#L86-L88) | Publish onto an existing name; assert both files survive and `canStartRecording` is false. |
| LECTURE-INV-21 | Recording transitions: `canStart` in `idle`/`failed`; `canResume` in `paused`/`interrupted`; `canStop` in `recording`/`paused`/`interrupted`; a finalisation without the recorder's report publishes after 30 s. | [RecordingState.swift:3-9](../../../Sources/GraphiteCore/RecordingState.swift#L3-L9), [RecordingController.swift:72-75](../../../Sources/GraphiteApple/RecordingController.swift#L72-L75) | Table test over every state and intent with the `AudioRecorder` fake. |
| LECTURE-INV-22 | Diagnostics live in `Library/Diagnostics`, at most 80 files (oldest by modification date removed), named `<Kind>-<ISO 8601 UTC with ms, colons as hyphens>.json`; MetricKit payloads `MetricKit-<begin>_<end>.json`; an existing name is never overwritten. | [DiagnosticRecords.swift:11-12](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L11-L12), [24-86](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L24-L86), [MainThreadWatchdog.swift:28-33](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L28-L33) | Write 81 records into an injected folder; assert 80 remain and names parse. |
| LECTURE-INV-23 | The watchdog pings every 0.5 s, reports after 2 s, keeps at most 96 frames, and does not start under a debugger. | [MainThreadWatchdog.swift:59-62](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L59-L62), [84-104](../../../Sources/GraphiteApple/MainThreadWatchdog.swift#L84-L104) | Existing `testAMainThreadStallLeavesARecordWithWhereTheMainThreadWas` ([MainThreadResponsivenessTests.swift:51](../../../App/Tests/MainThreadResponsivenessTests.swift#L51)). |
| LECTURE-INV-24 | The health monitor rebuilds after 3 unanswered gestures within 30 s (40 pt movement, 2 s Pencil quiet); undone means moved ≥20 pt or ≥5 % zoom, then back within 2 pt and 0.5 %; covered-view records at most every 300 s; embeds are never rebuilt. | [PDFPaneHealth.swift:8-77](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L8-L77), [110-114](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L110-L114), [GraphitePDFView.swift:1460-1465](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1460-L1465) | Existing `PDFPaneHealthTests`, plus an embed case. |
| LECTURE-INV-25 | Autosave waits `min(max(2 s, 10 × last save), 30 s)`, and after failures `2 s × 2^min(failures, 5)` capped at 60 s; a conflict stops autosave; history keeps 100 steps; deletion copies are attempted 3 times. | [PDFSession.swift:196-205](../../../Sources/GraphiteUI/PDFSession.swift#L196-L205), [482-487](../../../Sources/GraphiteUI/PDFSession.swift#L482-L487), [PDFEditHistory.swift:90](../../../Sources/GraphiteUI/PDFEditHistory.swift#L90) | Table test of `autosaveDelay(afterSaveTaking:consecutiveFailures:)`. |
| LECTURE-INV-26 | Save a Copy writes `<stem> Graphite edits <8 UUID characters>.pdf` beside the PDF; page export defaults to `<stem> page N` / `<stem> pages 1-3, 7` / `<stem> N pages` beyond 40 characters of ranges. | [PDFSession.swift:514-517](../../../Sources/GraphiteUI/PDFSession.swift#L514-L517), [PDFPane.swift:697-717](../../../Sources/GraphiteUI/PDFPane.swift#L697-L717) | Golden names for single, run, gapped and long selections. |
| LECTURE-INV-27 | Citations: `[[target#page=N|Name, p.N]]` with Wikilinks; otherwise `[Name, p.N](percent-encoded target#page=N)` with `[`/`]` escaped; quotes are `> ` paragraphs joined by `>` lines, then a blank line and the link. | [PDFCitation.swift:12-27](../../../Sources/GraphiteCore/PDFCitation.swift#L12-L27) | Existing `PDFCitationTests` ([VaultTests.swift:237-274](../../../Tests/GraphiteCoreTests/VaultTests.swift#L237-L274)). |
| LECTURE-INV-28 | Embed fragments: `page` ≥ 1 and `height` as a plain decimal clamped to 160…4000; malformed values never erase an earlier valid one; unknown keys are ignored. | [PDFEmbedOptions.swift:11-51](../../../Sources/GraphiteApple/PDFEmbedOptions.swift#L11-L51) | `page=3&height=1e3&height=400` gives page 3 and height 400. |
| LECTURE-INV-29 | New notebooks accept 72…2880 pt sides, 4…144 pt spacing and 1…1000 pages; inserted pages clamp to 3…14,400 pt; dotted paper is one coloured tiling cell; the default page is 595.28 × 841.89 pt; `PaperSpecification` decodes older data without colours as white paper with gray standard lines. | [PDFTemplateGenerator.swift:14-44](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L14-L44), [55-88](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L55-L88), [236-259](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L236-L259) | Golden JSON decode of an old specification; render each template and hash the page content. |
| LECTURE-INV-30 | Drawing PDFs carry the payload between `<graphite:drawing>` tags in XMP (namespace `urn:graphite:drawing:1`); a file is editable only when it has one page, no annotations, a matching page size within 0.01 and a matching content digest (with or without resources). | [PDFDrawingFile.swift:18-21](../../../Sources/GraphiteApple/PDFDrawingFile.swift#L18-L21), [61-91](../../../Sources/GraphiteApple/PDFDrawingFile.swift#L61-L91), [112-125](../../../Sources/GraphiteApple/PDFDrawingFile.swift#L112-L125) | Existing drawing round trips, plus a fixture that adds an annotation and must read as not editable. |
| LECTURE-INV-31 | Stroke fingerprints compare colour and transform at 32-bit precision; points, creation date, seed and mask compare exactly. | [PDFPencilInk.swift:36-66](../../../Sources/GraphiteApple/PDFPencilInk.swift#L36-L66) | Encode and decode a drawing with a hex colour and a moved stroke; fingerprints stay equal. |
| LECTURE-INV-32 | Overlay-to-PDF mapping is `x = minX + px·w/W`, `y = maxY − py·h/H` and its inverse, on the crop box; invalid geometry throws. | [PageCoordinates.swift:9-22](../../../Sources/GraphiteCore/PageCoordinates.swift#L9-L22) | Round trip on crop boxes with non-zero origins. |
| LECTURE-INV-33 | Persisted preferences: `GraphitePDFDrawsWithFinger`, `GraphitePDFShowsToolPicker`, `GraphiteDrawsShapes`, `GraphitePDFWritingGuidePattern`, `GraphitePDFWritingGuideSpacing`; the drag type `com.graphite.study.pdf-page`. | [PDFPane.swift:8-15](../../../Sources/GraphiteUI/PDFPane.swift#L8-L15), [PDFPagesSidebar.swift:310-313](../../../Sources/GraphiteUI/PDFPagesSidebar.swift#L310-L313) | Key registry golden test. |
| LECTURE-INV-34 | Ink is recorded before a canvas is released, before saves, copies, exports, deletions and page-tree edits, and a canvas whose overlay PDFKit dropped is reused. | [GraphitePDFView.swift:1199-1211](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1199-L1211), [1332-1338](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1332-L1338), [PDFSession.swift:369](../../../Sources/GraphiteUI/PDFSession.swift#L369), [439](../../../Sources/GraphiteUI/PDFSession.swift#L439) | With `PDFInkRecorder`: draw, release without a delegate callback, save; the file holds the stroke. |
| LECTURE-INV-35 | Thumbnails: cache cost limit `min(32 MiB, physical memory / 200)`; the content copy reopens every 64 pages; ink hidden under a canvas is still drawn in the thumbnail. | [PDFThumbnailRenderer.swift:27-34](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L27-L34), [104-119](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L104-L119), [262](../../../Sources/GraphiteUI/PDFThumbnailRenderer.swift#L262) | Render a page whose ink annotations have `shouldDisplay == false`; pixels show the ink. |
| LECTURE-INV-36 | Only one embed annotates a given PDF at a time; before it starts, the other sessions of that file are saved; a session whose closing save failed is kept until an embed shows it again. | [EmbeddedPDFViewer.swift:630-680](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L630-L680), [489-514](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L489-L514) | Model test with two embeds of one file and a failing save fake. |

### Tests that become possible once the seams exist

- `PDFInkRecorder` without UIKit views: a drawing change produces exactly one committed update; a failing sink leaves the tracker unchanged (CC-LECTURE-13).
- `PDFSaveController` with a `PDFFileSaving` fake: conflict, failure back-off, the baseline moving only on success, merge protection during a running save, all with an injected clock.
- `PDFEdit` exhaustiveness: every case's `changesPageTree`, `changesOutline` and `changedPageIndex` in one table.
- `RecordingController` with the `AudioRecorder` fake: start → pause → resume → stop → publish through the production path; media-services reset during resume; no `adoptRecording`.
- `RecordingRecoveryInventory` with a `RecordingStore` fake: unreadable folder reported, converted M4A grouped with its CAF (BUG-LECTURE-01), part ordering past 9.
- `EmbeddedPDFViewerModel`: release after 1.5 s only when still hidden, failed closing save kept, claim conflicts between two embeds, protection reason shown (BUG-LECTURE-02).
- One contract test run by both PDF view platforms for the inputs each declares (LSP-LECTURE-02).
- `PDFSignatureInspection` contract over `/Perms`, `/DSS`, `SigFlags`, inherited field types and value types.
- Diagnostics with an injected folder and clock: naming, pruning to 80, typed payload round trip.

## 8. Appendix: raw metrics

### Reconnaissance numbers (checked)

**Size.** 37 files, 12852 physical lines, 9814 code lines. Per-file figures are in §2. All 37 files were read completely.

**Functions over 40 code lines (19).** All were confirmed by reading their location.

| Function | Code lines | Location |
| --- | ---: | --- |
| `PDFPaneContent.body` | 108 | [PDFPane.swift:164](../../../Sources/GraphiteUI/PDFPane.swift#L164) |
| `PDFPaneContent.moreMenuItems` | 84 | [PDFPane.swift:399](../../../Sources/GraphiteUI/PDFPane.swift#L399) |
| `PDFPageManager.apply` | 80 | [PDFPageManager.swift:114](../../../Sources/GraphiteApple/PDFPageManager.swift#L114) |
| `CompactionPlanner.plan` | 74 | [PDFObjectCompaction.swift:196](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L196) |
| `EmbeddedPDFViewer.body` | 70 | [EmbeddedPDFViewer.swift:81](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L81) |
| `PDFTemplateGenerator.render` | 58 | [PDFTemplateGenerator.swift:90](../../../Sources/GraphiteApple/PDFTemplateGenerator.swift#L90) |
| `PDFObjectDescription.append` | 54 | [PDFDrawingFile.swift:273](../../../Sources/GraphiteApple/PDFDrawingFile.swift#L273) |
| `MoviePartWriter.init` | 52 | [MoviePartWriter.swift:71](../../../Sources/GraphiteApple/MoviePartWriter.swift#L71) |
| `MoviePartWriter.append` | 51 | [MoviePartWriter.swift:133](../../../Sources/GraphiteApple/MoviePartWriter.swift#L133) |
| `PDFPagesSidebar.pageRow` | 50 | [PDFPagesSidebar.swift:62](../../../Sources/GraphiteUI/PDFPagesSidebar.swift#L62) |
| `RecordedMovie.playableMovie` | 50 | [MoviePartWriter.swift:241](../../../Sources/GraphiteApple/MoviePartWriter.swift#L241) |
| `RecordingControl.control` | 49 | [RecordingControls.swift:26](../../../Sources/GraphiteUI/RecordingControls.swift#L26) |
| `CompactionPlan.write` | 48 | [PDFObjectCompaction.swift:117](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L117) |
| `PDFSyntaxScanner.readLiteralString` | 46 | [PDFObjectCompaction.swift:673](../../../Sources/GraphiteApple/PDFObjectCompaction.swift#L673) |
| `PDFAnnotationCoordinator.attach` | 45 | [GraphitePDFView.swift:820](../../../Sources/GraphiteUI/GraphitePDFView.swift#L820) |
| `PDFPaneContent.statusBanner` | 44 | [PDFPane.swift:303](../../../Sources/GraphiteUI/PDFPane.swift#L303) |
| `EmbeddedPDFViewer.toolbar` | 42 | [EmbeddedPDFViewer.swift:162](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L162) |
| `RecordingController.start` | 42 | [RecordingController.swift:106](../../../Sources/GraphiteApple/RecordingController.swift#L106) |
| `PDFDrawingFile.pageContentDigests` | 41 | [PDFDrawingFile.swift:146](../../../Sources/GraphiteApple/PDFDrawingFile.swift#L146) |

**Types over 300 code lines (single declaration blocks).** `PDFAnnotationCoordinator` 735, `RecordingController` 501, `EmbeddedPDFViewer` 431, `PDFPaneContent` 427, `PDFSession` 375. `PDFSession` grows with its extensions (see the corrections below).

**Files over 400 code lines.** `GraphitePDFView.swift` 1332, `PDFPane.swift` 788, `PDFObjectCompaction.swift` 616, `EmbeddedPDFViewer.swift` 585, `RecordingController.swift` 526, `PDFSession.swift` 506, `PDFPageManager.swift` 430, `PDFPaneHealth.swift` 415.

**Pattern counts** (reconnaissance regex over comment- and string-stripped code):

| Pattern | Count | Checked |
| --- | ---: | --- |
| `try?` | 64 | not recounted |
| `Task.sleep` / `sleep` | 6 | `Thread.sleep` in [MoviePartWriter.swift:175](../../../Sources/GraphiteApple/MoviePartWriter.swift#L175) seen; others not recounted |
| `asyncAfter` | 3 | yes: [GraphitePDFView.swift:405](../../../Sources/GraphiteUI/GraphitePDFView.swift#L405), [880](../../../Sources/GraphiteUI/GraphitePDFView.swift#L880), [PDFPaneHealth.swift:278](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L278) |
| `.shared` | 20 | yes, grep `\.shared\b` per module (8 `EmbeddedPDFSessions`, 4 `PencilToolbox`, 4 `UIApplication`, 1 `MXMetricManager`, 1 `PDFPictureDrawingDelegate`, 2 in `GraphiteDiagnostics`) |
| `static var` | 8 | not recounted |
| `@unchecked Sendable` | 10 | not recounted |
| `nonisolated(unsafe)` | 3 | yes: [MoviePartWriter.swift:219](../../../Sources/GraphiteApple/MoviePartWriter.swift#L219), [VideoRecording.swift:159](../../../Sources/GraphiteApple/VideoRecording.swift#L159), [RecordingController.swift:344](../../../Sources/GraphiteApple/RecordingController.swift#L344) |
| `MainActor.assumeIsolated` | 14 | not recounted |
| `Date()` / `Date.now` | 2 | yes: [DiagnosticRecords.swift:28](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L28), [109](../../../Sources/GraphiteApple/DiagnosticRecords.swift#L109) |
| `FileManager.default` | 48 | 21 of them in `RecordingController.swift` (grep) |
| `NotificationCenter.default` | 18 | not recounted |
| `default:` in switch | 23 | 5 of them over the app's own enums (see below); the rest over platform enums, strings or bytes |
| `[String: Any]` | 8 | not recounted |
| `Task { }` | 49 | 18 listed in CC-LECTURE-05 |
| `DispatchQueue.main` | 7 | not recounted |

**Commits touching each file** (reconnaissance, top 15): `GraphitePDFView.swift` 23, `PDFPane.swift` 19, `PDFSession.swift` 12, `PDFPageManager.swift` 10, `EmbeddedPDFViewer.swift` 8, `PDFPictureControls.swift` 7, `PDFPicture.swift` 7, `PDFSessionPictures.swift` 6, `PDFPagesSidebar.swift` 4, `PDFPageLasso.swift` 3, `RecordingController.swift` 3, `WorkspaceRecordingRecovery.swift` 2, `PDFPaneHealth.swift` 2, `PDFEditHistory.swift` 2, `RecordingState.swift` 2.

### Counted by this audit

| Measure | Value | Method |
| --- | ---: | --- |
| Stored properties, `PDFAnnotationCoordinator` | 37 instance + 1 static mutable | read [GraphitePDFView.swift:745-940](../../../Sources/GraphiteUI/GraphitePDFView.swift#L745-L940) |
| Stored properties, `PDFSession` | 46 | read [PDFSession.swift:212-339](../../../Sources/GraphiteUI/PDFSession.swift#L212-L339) |
| Stored properties, `RecordingController` | 26 | read [RecordingController.swift:33-78](../../../Sources/GraphiteApple/RecordingController.swift#L33-L78) |
| Stored, state and environment properties, `PDFPaneContent` | 33 | read [PDFPane.swift:50-91](../../../Sources/GraphiteUI/PDFPane.swift#L50-L91) |
| Stored and state properties, `EmbeddedPDFViewer` | 28 | read [EmbeddedPDFViewer.swift:22-60](../../../Sources/GraphiteUI/EmbeddedPDFViewer.swift#L22-L60) |
| `default:` over the app's own enums | 5 | [PDFPageManager.swift:53](../../../Sources/GraphiteApple/PDFPageManager.swift#L53), [60](../../../Sources/GraphiteApple/PDFPageManager.swift#L60), [71](../../../Sources/GraphiteApple/PDFPageManager.swift#L71) (`PDFEdit`), [RecordingControls.swift:64](../../../Sources/GraphiteUI/RecordingControls.swift#L64), [RecordingController.swift:540](../../../Sources/GraphiteApple/RecordingController.swift#L540) (`RecordingState`) |
| Audio/video branches in `RecordingController` | 9 members | read (OCP-LECTURE-02) |
| Mac `GraphitePDFView` inputs ignored | 10 of 15 | read (LSP-LECTURE-02) |
| Force unwraps in `PDFObjectCompaction.swift` | 5 | read (CC-LECTURE-09) |
| Recursive view-tree walkers | 11 | read: [GraphitePDFView.swift:568](../../../Sources/GraphiteUI/GraphitePDFView.swift#L568), [1102](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1102), [1179](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1179), [1190](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1190), [1305](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1305), [1467](../../../Sources/GraphiteUI/GraphitePDFView.swift#L1467); [PDFPaneHealth.swift:388](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L388), [452](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L452), [525](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L525), [534](../../../Sources/GraphiteUI/PDFPaneHealth.swift#L534); [PDFPictureControls.swift:298](../../../Sources/GraphiteUI/PDFPictureControls.swift#L298) |
| Comments narrating incidents or dates | at least 10 | read (CC-LECTURE-01) |
| `PDFEdit` cases | 15 | read [PDFPageManager.swift:24-47](../../../Sources/GraphiteApple/PDFPageManager.swift#L24-L47) |
| Signature detectors | 2 | read (LSP-LECTURE-01) |
| Tests pinning the area (named here) | `VideoRecordingTests` 21, `AppleRecordingAccessRecordingTests` 11, `RecordingRecoveryTests` 6, `PDFObjectCompactionTests` 9, plus `PDFPaneHealthTests`, `RecordingControlsTests`, `PDFCitationTests`, `MainThreadResponsivenessTests`, `PDFGestureWinsTests`, `PDFInkSafetyTests` | grep `func test\w+` over the named files |

### Corrections to figures in this document

- §3.2 gives "about 880 code lines with extensions" for `PDFSession`. The measured estimate is **about 740**: 375 for the main block (reconnaissance), plus about 158 of `PDFSessionPictures.swift`'s 164 code lines (all but `PDFPictureSelection`), about 199 of `PDFEditHistory.swift`'s 239 (all but `PDFHistoryPage`, `PDFHistoryPageContent`, `PDFRemovedPageRun` and `PDFInkCanvasProvider`), and about 8 in `PDFPageLasso.swift`. This figure supersedes the one in §3.2. The verdict does not change.
- The verdict table's "4 default arguments" (D row) means 3 default arguments (`PDFSession.open`, `PDFFileService.init`, `VideoRecording.init`) and 1 default property value (`makeVideoCaptureSource`), plus the 2 inline constructions listed in DIP-LECTURE-03.

### Findings and bugs by severity

| Prefix | High | Medium | Low |
| --- | ---: | ---: | ---: |
| SRP | 2 | 5 | 0 |
| OCP | 0 | 3 | 2 |
| LSP | 0 | 5 | 0 |
| ISP | 0 | 1 | 3 |
| DIP | 0 | 3 | 1 |
| CC | 0 | 7 | 8 |
| **Total (40)** | **2** | **24** | **14** |

Bugs: 4 (BUG-LECTURE-01 to 04). Invariants: 36 (LECTURE-INV-01 to 36).

## 9. Since the snapshot

Delta audit of 2026-10-19 at `fff794b` (main), against `FR-01` to `FR-108`. Phase 1 (`0c074d9`) put PDF autosave on the injected clock and the recording-recovery folder behind the device's folders; the system-27 floor (`f65a8dd`) removed the movie writer's and preview's older paths. Invariants touched: PDF-07, REC-07.

### New findings

#### DIP-LECTURE-05 `PDFSession.open` defaults its clock to the live one, and no production caller passes the workspace's clock
- **Severity:** Medium
- **Rule:** `FR-47`, `FR-50`, `FR-80`
- **Evidence:** `clock: any ApplicationClock = LiveApplicationClock()` ([PDFSession.swift:363-364](../../../Sources/GraphiteUI/PDFSession.swift#L363-L364)); its doc says the default "goes when the workspace is given its clock" ([:361-362](../../../Sources/GraphiteUI/PDFSession.swift#L361-L362)), and the same commit gives `WorkspaceModel` its `clock`, yet neither production caller passes it (`WorkspaceModel.swift:1352`, `EmbeddedPDFViewer.swift:597`). Introduced in `0c074d9`.
- **Why it matters:** a workspace on a manual clock still gets real-time PDF autosave (2 to 60 s waits, PDF-07), and the comment is already stale.
- **Fix direction:** pass the workspace's clock through both callers and remove the default.

#### DIP-LECTURE-06 `RecordingController.recoveryFolderLocation` is a public settable closure so the composition can rewire it after construction
- **Severity:** Low
- **Rule:** `FR-32`, `FR-46`, `FR-43`
- **Evidence:** `public var` with the comment "Public so the app's composition can point it at a temporary folder for hosted tests" ([RecordingController.swift:59-60](../../../Sources/GraphiteApple/RecordingController.swift#L59-L60)); reassigned after `init` by the workspace (`WorkspaceModel.swift:236`) and `App/Tests/VideoRecordingWorkspaceTests.swift:36`. Introduced in `0c074d9`.
- **Why it matters:** the folder that holds unsaved lectures can change between start and stop, and any module can redirect it.
- **Fix direction:** inject it through `init` from the composition root; `private let`.

#### CC-LECTURE-16 `MoviePartWriter.Track` keeps a struct of escaping closures that only its removed fallback needed, on the per-frame path
- **Severity:** Low
- **Rule:** `FR-107`, `FR-82`
- **Evidence:** `Track` holds `appendIfReady` and `finish` closures ([MoviePartWriter.swift:39-45](../../../Sources/GraphiteApple/MoviePartWriter.swift#L39-L45)); its only initializer now wraps a `SampleBufferReceiver` ([:197-205](../../../Sources/GraphiteApple/MoviePartWriter.swift#L197-L205)); the closure runs for every sample ([:154](../../../Sources/GraphiteApple/MoviePartWriter.swift#L154)). Introduced in `f65a8dd`.
- **Why it matters:** every frame pays an indirect call for an abstraction with one implementation.
- **Fix direction:** store the receiver directly.

### Patterns to keep
- `PDFSession` times saves and autosave on the injected clock ([PDFSession.swift:461-465](../../../Sources/GraphiteUI/PDFSession.swift#L461-L465), [:498-499](../../../Sources/GraphiteUI/PDFSession.swift#L498-L499)), tested on `ManualClock`.
