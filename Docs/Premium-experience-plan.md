# Premium experience implementation plan

This plan follows `OBJECTIVE.md`. It tracks the work toward a polished daily study application, not a claim that Graphite has reached Goodnotes or Obsidian parity. Community plugin installation, integrations, and runtime implementation remain deferred.

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

## Remaining: coherent workspace design

Continue reviewing the Markdown workspace, PDF notebook workspace, and drawing editor together: typography, icon weights, popovers, menus, selection states, and light/dark appearance beyond the toolbars. Check landscape, Split View and Slide Over widths in the running app (the control-row threshold is estimated from portrait layouts), Dynamic Type extremes, hardware-keyboard use including ⌘Z for PDFs, and left- and right-handed writing. Extend accessibility validation of the shared controls and focus mode.

Remaining continuity limits: a note's undo history is lost beyond the three kept editors and when its tab opens another file; a PDF's history ends when its hidden session is released; neither history survives relaunch. Reading position is a pixel offset, not a semantic anchor.

Completion evidence: visual review of the three workspaces at representative widths and orientations, accessibility checks, and a sustained study session on a device without losing editing context.

## Next: Pencil quality on hardware

Compare the same handwriting exercises in Graphite, Apple Notes, Goodnotes, and Notability on the same physical iPad. Check small letters, curves, dots, stroke endings, pressure and tilt, palm rejection, finger scrolling, pinch zoom, page edges, and the supported double-tap, squeeze, hover, and barrel-roll interactions.

Measure responsiveness while autosaving, recording, switching pages, and reopening large documents. Investigate integration costs before considering a replacement for PencilKit. Verify saved appearance in independent viewers.

Completion evidence: recorded device and operating-system versions, repeatable exercises, latency and memory measurements, interaction defects resolved, and explicit remaining limitations.

## Then: essential handwriting tools

Audit existing native tools before declaring them missing. Prioritize reliable erasing, lasso operations, tool and color presets, rulers, shapes, zoom writing, mixed text/image/ink pages, paper choices, and page management. Each addition needs a storage design that preserves complete visible content in ordinary files.

Recognition, handwriting-to-text, math conversion, synchronized audio replay, tape, and reusable elements remain candidates for discussion. Generative AI features are not part of this plan.

Completion evidence: agreed feature scope, device interaction checks, undo behavior, save/reopen checks, and portable output checks for every implemented tool.

## Then: daily Obsidian workflows

Use `Obsidian-mobile-gaps.md` and a real course vault to prioritize remaining editor, table, Canvas, navigation, and settings gaps. Update `Coverage.md` as behavior is implemented and verified.

## Future: existing Obsidian plugin execution

After the premium experience work, investigate running existing packages from Obsidian's community directory, GitHub, and other sources without Graphite-specific versions. Preserve settings and file formats, document supported APIs and unsupported dependencies, and protect native input responsiveness. Universal compatibility is not yet validated.
