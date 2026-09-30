# Premium experience implementation plan

This plan follows `OBJECTIVE.md`. It tracks the work toward a polished daily study application, not a claim that Graphite has reached Goodnotes or Obsidian parity. Community plugin installation, integrations, and runtime implementation remain deferred.

## Immediate priorities: images, paper, and Pencil interaction

Added on 2026-09-30 at the user's request. These are the next implementation priorities alongside workspace polish and physical-device Pencil validation, ahead of the later feature backlog. The requirements below are planned, not claims of completed behavior. Audit existing code first and extend the shared PDF and drawing tools rather than building separate implementations for embeds.

### 1. Insert and arrange images

Add image insertion from Photos, Files, and the clipboard into PDF pages (including embedded PDFs) and embedded drawing, handwriting, and sketch canvases. Support multiple pictures in one composition, selection, moving, resizing with preserved proportions, rotation, cropping, deletion, and arranging pictures relative to ink. All content edits must participate in the document's undo and redo history.

The fourth increment's ability to draw on one existing image is a starting point; it does not complete image placement inside an existing PDF or drawing. Preserve source images, follow the configured attachment policy where files are created, and keep inserted pictures visible in ordinary PDF, PNG, and supported vector exports without requiring Graphite metadata.

### 2. Customize drawing paper and separate editing guides from saved appearance

Offer background color and paper pattern choices for embedded drawings: blank/no grid, square grid, dots, and ruled paper, with configurable spacing and line color/strength. Provide remembered defaults in Settings and overrides for individual drawings that survive reopening.

Make two choices independent:

- **While editing:** the paper color and guides visible while drawing or handwriting with Apple Pencil.
- **In the Markdown embed and exported file:** keep that paper, use a plain white or chosen solid background, or use a transparent background where the format supports it.

For example, a user can write on a square grid, then return to Markdown and see only their handwriting on a transparent or white background. Returning to the drawing editor restores the chosen guides. Include a preview of the saved appearance and preserve ink contrast across light and dark viewing backgrounds. Editor-only guides must not be baked into the saved visible artwork. Store optional editing preferences in the existing embedded metadata model; standard viewers must still show the complete chosen output. For PDF notebooks, distinguish temporary writing guides from actual paper content; changing guides must not remove imported page content.

### 3. Choose floating or fixed Pencil tools

Add a Settings choice between the native Apple floating Pencil palette and a fixed, docked toolbar inspired by traditional Goodnotes and Notability layouts. Apply the choice consistently to PDF pages, embedded PDFs, and drawing editors. Both presentations must use the same ink engine, tool settings, and undo history. Keep tools reachable in narrow layouts, focus mode, and either writing hand, without covering the active writing area. Audit which native picker functions need explicit equivalents in the fixed toolbar and document any platform limits before calling the layouts equivalent.

### 4. Complete the native Pencil and Scribble audit

Use Apple's [Squeeze the most out of Apple Pencil (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10214/) as the starting reference. Audit configurable picker items, Scribble handwriting-to-text, ruler behavior, Pencil Pro squeeze, double-tap, hover, barrel roll, and supported haptic feedback against Graphite's actual implementation. Preserve system preferences and provide appropriate fallbacks by Pencil model and operating-system version. Verify text entry and drawing mode transitions in both toolbar layouts on physical devices; record supported, missing, and unavailable behaviors separately.

### 5. Investigate handwriting refinement like Apple Notes

Handwriting improvement is explicitly welcome: investigate optional refinement that makes handwritten strokes neater while retaining the user's writing and meaning. This is separate from Scribble's conversion to typed text. Establish whether current public Apple APIs expose the desired behavior, and record device, language, and operating-system constraints before choosing an implementation. Do not assume Apple Notes' handwriting refinement is available to third-party PencilKit canvases. Any implementation must be optional, undoable, preserve the original ink for recovery, and retain portable visible output. This request does not reopen scope for generative chat, summaries, or unrelated AI features.

### Status of these priorities on 2026-09-30

A first implementation landed the same day (the fifth increment); verification is in `Coverage.md` under "Images, paper, and the fixed tool bar". None of it was tried with a physical Pencil, so no priority is complete by the evidence asked for below.

1. **Images.** Implemented: inserting from Photos, Files and the clipboard into PDF pages, embedded PDFs and drawings; several pictures in one page or drawing; selecting (a finger tap, or "Move or Resize Images"), moving, resizing in proportion, deleting; undo and redo for each; pictures always under the ink; saved as a standard stamp annotation in PDFs and into the PNG of drawings. Not implemented: rotation, cropping, ordering pictures among themselves or over ink, and pictures in SVG or PDF drawings (a drawing with pictures is a PNG). The source image is only read; nothing is copied into the attachment folder, since the picture lives in the PDF or the drawing.
2. **Paper.** Implemented: plain, squared, ruled and dotted paper per drawing, kept with the drawing and restored in the editor; a default for new drawings in Settings; "Show Paper in the Note" per drawing and as a default, so the guide while drawing and the saved appearance are independent; white or transparent background per drawing; guides are never baked into a drawing that does not show them. Not implemented: configurable spacing, line color or strength; paper colors other than white; a preview of the saved appearance in the editor; anything about ink contrast on dark backgrounds for transparent drawings; temporary guides for PDF notebook pages, whose paper is page content.
3. **Floating or fixed tools.** Implemented: the Settings choice, applied to PDF pages, embedded PDFs and the drawing editor, with the same PencilKit canvases and the same undo history. Limits: the fixed bar keeps its own pens, colors and widths, separate from the palette's (PencilKit offers no way to read or set the palette's tools in full); it has pen, pencil, highlighter, eraser and lasso, not the palette's other pens; squeezing shows no tools and there is no undo slider; it sits above the page for either hand and scrolls sideways when narrow; compact widths always use the palette.
4. **Pencil and Scribble audit.** Recorded in `Architecture.md` ("What Graphite uses of Apple Pencil and PencilKit"). Added: squeeze starts a drawing in a note; the Pencil Pro's tap when a stroke snaps to a shape. Everything that needs a Pencil is unverified.
5. **Handwriting refinement.** Finding: the iOS 27 SDK has no public API for Apple Notes' refinement, and PencilKit reports its model as unavailable in the simulator. Nothing was implemented. The next step is a check on a supported iPad of what the lasso's own menu offers in Graphite's canvases.

Completion evidence for these priorities: documented capability findings; real-device review of both toolbar layouts and Pencil/Scribble interactions; image placement and background save/reopen checks; undo/redo and canceled-edit checks; and independent-viewer verification of saved files. Record implementation and actual validation in `Architecture.md` and `Coverage.md` as each feature lands.

## First increment: predictable reading and writing

Implemented in the current change; verification is recorded in `Coverage.md`:

- Explicit Read and Write controls in the iPad PDF pane. Read returns page touches to PDFKit and displays the standard PDF ink. Write restores the Pencil canvas. The choice belongs to the open session and does not edit the file.
- A separate Show/Hide Tools action while writing, so palette visibility no longer stands in for reading mode.
- Drawing editor controls for Show/Hide Tools, Draw with Finger, and Fit to Width. Export formats sit inside Drawing Options. Finger drawing is an explicit, remembered drawing-editor preference, defaulting to Pencil-only input. PDF finger drawing keeps its existing separate preference.
- New PDF canvases start with the native picker's current ruler state.

This increment does not establish Pencil latency, pressure fidelity, gesture quality on hardware, or a finished visual design.

## Second increment: shared controls, focus, and reading position

Implemented on 2026-09-30; targeted validation is recorded in `Coverage.md`:

- Markdown and PDF workspaces use the same Read/Write picker, sized with Dynamic Type. Compact layouts keep it in a row below navigation. Markdown's Live Preview and Source choices remain in More.
- Focus mode hides navigation panels, tab bars, and secondary navigation buttons while keeping document tools and recording controls available. Exiting restores the previous panel arrangement. Opening a panel or requesting sidebar search leaves focus mode. The command palette also exposes Toggle focus mode.
- Reading view retains a vertical-position checkpoint in the open note session and restores it when its view is recreated. A new heading request takes precedence. The checkpoint is lightweight and is not written into the note or kept across app relaunches. Changed text or layout can change which passage occupies that offset.
- Hiding and restoring the tab bar preserves the active native editor, selection, and undo history in hosted iPad and iPhone tests. This does not address undo across actual document switches.

## Third increment: editing continuity and consistent document controls

Implemented on 2026-09-30; verification is recorded in `Coverage.md` under "Undo continuity and workspace controls":

- Notes keep their undo history across tab switches, moving a tab to the other side, and reading view, for the three most recently hidden notes (`MarkdownEditorRetention`). Memory stays bounded by count, by text length, and by memory warnings; a note beyond the bound loses its history, never its text.
- Each PDF has its own undo history in its session, covering ink, markup, and page changes. It no longer depends on page canvases or the view, and never mixes two PDFs. Deleting pages copies them first so Undo can put them back; bookmark changes are not undoable.
- Undo and Redo appear in every workspace just before Read/Write (in the drawing editor, before its options and Insert or Done). When the documents area is too narrow for the whole toolbar, Read/Write, Undo and Redo move to the row below the tab bar instead of disappearing into the overflow menu. The Focus button uses the same neutral tint as the other navigation buttons, and the iPad keyboard toolbar no longer repeats Undo and Redo.

## Fourth increment: handwriting tools, drawing on images, and quieter colors

Implemented on 2026-09-30; verification is recorded in `Coverage.md` under "Handwriting tools, drawing on images, and colors". It was brought forward from "Then: essential handwriting tools" at the user's request, before the hardware comparison below, so nothing here says how these tools feel with a Pencil.

- One Pencil palette for PDF pages, embedded PDFs and the drawing editor with every tool Apple Notes has, each once. Each tool keeps its color and width, and the palette keeps the tool in use, across canvases and launches. (A first version with three preset pens showed three identical black pens on the iPad and was replaced the same day.)
- Favorite colors: a button at the end of the palette gives the pen in use one of the colors of Settings › Colors, the same list the notes' color menu uses.
- A shape tool, switched from the palette's button or the More menu: a stroke becomes the straight line, circle, ellipse, triangle, rectangle or polygon it was meant to be, in the same ink, as one undo step. Handwriting and open curves are left alone.
- The lasso, audited rather than rebuilt: PencilKit's own selection, menu (Cut, Copy, Delete, Duplicate, Insert Space Above) and dragging, now working with the document's undo history. Three defects found in the running app were fixed: selecting with a finger raised the keyboard, Undo after moving a selection left the page showing the moved strokes, and a selection stayed on screen over a drawing that Undo had changed.
- The drawing editor has its own undo history with the same Undo and Redo buttons as notes and PDFs.
- Drawing on an image: from an image in a note (press and hold, the toolbar button with the cursor on it, or the full-screen viewer) or an image file opened on its own. The result is a new ordinary PNG beside the note's other attachments; the original image is never changed, the note's embeds switch to the new file as one undoable edit, and the ink stays editable.
- Apple Pencil double-tap in a note starts a drawing where the Pencil hovers or at the cursor; on a drawing it opens it, on an image it draws on it. It can be turned off in Settings › Pencil drawings, and follows the iPadOS setting that ignores double-tap.
- Colors: an ink-blue default accent and muted presets instead of Obsidian's purple (still offered), lightened automatically in dark appearance for contrast; neutral toolbars and palette buttons; inline math source no longer indigo.

## Fifth increment: images, paper, a fixed tool bar, and more of Apple Pencil

Implemented on 2026-09-30 against the immediate priorities at the top of this plan, whose status section says what each priority still lacks:

- Images on PDF pages, in embedded PDFs and on drawings, from Photos, Files or the clipboard, under the ink, with moving, resizing, deleting and undo.
- Paper for drawings (plain, squared, ruled, dotted) as a guide while drawing or as part of the saved drawing, and a white or transparent background, per drawing and as defaults.
- A fixed tool bar as an alternative to the floating palette.
- A squeeze of Apple Pencil Pro starts a drawing in a note, and a stroke that snaps to a shape gives the Pencil Pro's tap.

## Remaining: coherent workspace design

Continue reviewing the Markdown workspace, PDF notebook workspace, and drawing editor together: typography, icon weights, popovers, menus, selection states, and light/dark appearance beyond the toolbars. Check landscape, Split View and Slide Over widths in the running app (the control-row threshold is estimated from portrait layouts), Dynamic Type extremes, hardware-keyboard use including ⌘Z for PDFs, and left- and right-handed writing. Extend accessibility validation of the shared controls and focus mode.

Remaining continuity limits: a note's undo history is lost beyond the three kept editors and when its tab opens another file; a PDF's history ends when its hidden session is released; neither history survives relaunch. Reading position is a pixel offset, not a semantic anchor.

Completion evidence: visual review of the three workspaces at representative widths and orientations, accessibility checks, and a sustained study session on a device without losing editing context.

## Next: Pencil quality on hardware

Compare the same handwriting exercises in Graphite, Apple Notes, Goodnotes, and Notability on the same physical iPad. Check small letters, curves, dots, stroke endings, pressure and tilt, palm rejection, finger scrolling, pinch zoom, page edges, and the supported double-tap, squeeze, hover, and barrel-roll interactions.

Measure responsiveness while autosaving, recording, switching pages, and reopening large documents. Investigate integration costs before considering a replacement for PencilKit. Verify saved appearance in independent viewers.

Completion evidence: recorded device and operating-system versions, repeatable exercises, latency and memory measurements, interaction defects resolved, and explicit remaining limitations.

## Then: essential handwriting tools

The full tool set, favorite colors, the shape tool, the lasso and drawing on images are implemented (fourth increment above). Favorite colors are not offered on the iPhone, where the palette shows no accessory button. Image placement, customizable drawing paper, separate editing/output backgrounds, toolbar layout choice, and the Pencil/Scribble and handwriting-refinement investigations have been brought forward into the immediate priorities above. Still to audit or build beyond those priorities: the pixel eraser and the ruler through the document history on hardware, resizing and recoloring a lasso selection, a shape tool that holds to snap instead of a mode, arrows and curves, zoom writing, typed text on drawings and PDF pages, paper choices for notebooks, and drawing on an image in the vector formats. Each addition needs a storage design that preserves complete visible content in ordinary files.

Recognition, handwriting-to-text, math conversion, synchronized audio replay, tape, and reusable elements remain candidates for discussion. Generative AI features are not part of this plan.

Completion evidence: agreed feature scope, device interaction checks, undo behavior, save/reopen checks, and portable output checks for every implemented tool. The fourth increment has the undo, save/reopen and output checks in the simulator; its device interaction checks are outstanding.

## Then: daily Obsidian workflows

Use `Obsidian-mobile-gaps.md` and a real course vault to prioritize remaining editor, table, Canvas, navigation, and settings gaps. Update `Coverage.md` as behavior is implemented and verified.

## Future: existing Obsidian plugin execution

After the premium experience work, investigate running existing packages from Obsidian's community directory, GitHub, and other sources without Graphite-specific versions. Preserve settings and file formats, document supported APIs and unsupported dependencies, and protect native input responsiveness. Universal compatibility is not yet validated.
