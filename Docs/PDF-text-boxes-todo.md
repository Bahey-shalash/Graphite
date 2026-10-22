# Text boxes on PDF pages: TODO

Created: 2026-10-20. Built 2026-10-21 (phases 1 to 4); the import (phase 5) and the checks on a device (phase 6) are left.

Status: Graphite writes, reads and edits typed text boxes on every PDF page, as standard `/FreeText` annotations. What was built, how it was checked and what was not checked is below, in `Architecture.md` ("Text boxes on PDF pages") and in `Coverage.md` ("Text boxes on PDF pages"). Nothing was tried on a device or with Apple Pencil.

## Request

The owner (2026-10-20): "allow text boxes in pdfs (not just for now but in general)". Typed text boxes are a feature of every PDF in Graphite, whether a notebook, lecture slides, a worksheet or an imported Goodnotes or Notability notebook. They are not only a target for the import.

The Goodnotes and Notability import leaves typed text out until this exists (owner decision, 2026-10-20). Its step 8 in `Goodnotes-Notability-import-phase-3-design.md` waited on this checklist; that section now lists the API the import uses.

## What the result must be

- **Ordinary PDF.** Each text box is a standard `/FreeText` annotation with its own appearance stream, stored in the PDF like Graphite's ink and pictures. Preview, Files, Acrobat, Obsidian and other PDF readers show it exactly as Graphite does, and no sidecar file or app database is needed (OBJECTIVE.md). Any editing data Graphite needs beyond the standard keys stays optional, in the PDF itself.
- **Round trip.** A `/FreeText` made by Preview or Acrobat opens in Graphite as an editable text box. One made by Graphite opens in them as text they can edit, as far as they support it.
- **What a box holds:**
  - text with font, size, colour, bold, italic and underline;
  - alignment and line spacing;
  - a box position and width, with the height growing with the text;
  - rotation about the box's origin, as Goodnotes stores it;
  - optional fill, border and padding;
  - links inside the text.
- **Editing in Graphite:**
  - create a box by tapping with a text tool;
  - type with the keyboard, or write into it with Scribble on the iPad;
  - select, move, resize, rotate, duplicate and delete it;
  - undo and redo each step;
  - the same on iPhone, iPad and Mac.
- **With the other content:**
  - the lasso takes text boxes together with ink and pictures;
  - stacking order is free between text, pictures and ink, once "pictures above ink" exists;
  - erasing ink never touches a text box.
- **Everywhere text is used:**
  - Search and the index find the text;
  - Read Aloud reads it in page order when its core plugin is on;
  - the outline and links work as they do for other PDF text.

## Decisions (2026-10-21, taken while the owner was away; to confirm)

1. **New boxes start with the last-used look** (open question 1): the font, size, colour, faces, alignment, fill and border last chosen in a box's format popover or in the text tool's options on the fixed bar, kept on the device (`PDFTextBoxDefaults`, key `GraphitePDFTextBoxStyle`). Typing does not change it. The first box ever is Helvetica 14 pt, black, left-aligned, no fill or border, 4 pt padding.
2. **No sticky notes for now** (open question 2): the collapsed `/Text` note needs an icon on the page, a popup to read and write it, and its own rules for moving and printing; that is a feature of its own, not a small addition. Sticky notes other applications made stay in the file untouched. An import can give a sticky note as a text box with a fill.
3. **iPhone: creating and editing, as on the iPad** (open question 3): the iPhone uses the same UIKit code. Its compact width has the floating palette, whose accessory menu has Text Box; the format popover and the bar under the page work there too. Not tried on an iPhone.
4. **Mac: reading only.** The Mac's PDF viewer has no annotation tools at all (no ink, pictures or markup), so it gets no text tool now: boxes show exactly as on the iPad (`PDFTextBoxAnnotation` draws them), Search finds them and Read Aloud reads them. Editing on the Mac waits for the Mac's PDF tools.
5. **Boxes draw above ink.** Free stacking needs "pictures above ink", which does not exist (pictures are under the ink, invariant M-15). So Graphite's boxes are over its ink and pictures, in the file (the page's last annotations) and on screen (`PDFPageTextBoxesView`, over the Pencil canvas). A box another application made stays where that application put it among the page's annotations, and is drawn by PDFKit from its own appearance, until Graphite writes it again.
6. **Rotation is about the box's top-left corner**, clockwise as the page is seen unturned, as Goodnotes stores it. The rotate handle turns a box about its middle on screen; the corner moves with it. A box made on a page shown turned is upright as the page is shown.
7. **Width is chosen, height follows the text.** Resizing from a corner changes the width; the height is fitted again. A box another application made keeps its height until it is typed in.
8. **Typing is one step.** A box typed in reaches the document when typing ends, and before every save (so autosave, closing and leaving the app save it too); all of that is one step of the PDF's history ("Add Text Box", "Edit Text", or "Delete Text Box" when all text was removed). While typing, ⌘Z undoes typing in the text view's own history.
9. **Rich text `/RC` is written by compaction.** PDFKit neither reads nor writes `/RC`, so Graphite keeps the rich text under `GraphiteRichTextV1` and the save's compaction renames it `/RC` (`TextBoxRichTextPromotion`). Should compaction not apply to a file (one PDFKit did not write in its usual form), the box has no `/RC`; every reader still draws its appearance and reads `/Contents`, and Graphite reads its record.
10. **Links** are `/Link` annotations over the linked text, marked as the box's (`GraphiteTextBoxLinkOwner`), and Graphite's record keeps them on the runs. The XFA rich text of `/RC` has no links.
11. **Other applications' keys are kept** when Graphite writes their box again, read from the file with Core Graphics, except the keys Graphite writes itself, references to other objects (`/Popup`, `/Parent`, `/IRT`, `/OC`, `/StructParent`), `/RD` and `/CA`, which would draw the box otherwise than its appearance, and Apple's markup copy.
12. **Search reads text boxes only.** The index did not read PDFs before; it now reads the `/Contents` of every `/FreeText`, bounded (10,000 pages, 2,000 annotations a page, 1 MiB of text) and off the main thread, as plain text with no links or tags. The pages' printed text is still not indexed.
13. **Read Aloud** reads a page's boxes after its printed text, each box a paragraph, in reading order as the page is shown (top to bottom, level boxes left to right). A page with only boxes is read from them. A scanned page's boxes are not read.

## Phases

### 1. Model and file format

Issue: [#39](https://github.com/Graphite-Note/Graphite/issues/39)

- [x] A `PDFTextBox` value in GraphiteCore: runs (`PDFTextRun`, `PDFTextAttributes`), top-left corner, width, height, rotation, style (`PDFTextBoxStyle`), and other applications' kept keys.
- [x] Writing and reading `/FreeText`:
  - `/Contents` the plain text, `/RC` the rich text (XHTML as Acrobat writes it), `/DA` (from the font PDFKit is given), `/DS`, `/Q`, `/Rect`, `/Rotate` for a quarter turn, `/BS`, `/C` for the fill;
  - an appearance stream drawn by Graphite with Core Text (embedded font subsets), so readers that ignore `/RC` draw it exactly; a turned box's appearance turns the text inside the rectangle around it.
- [x] Golden-file tests:
  - files written by Graphite, read back unchanged (`PDFTextBoxFileFormatTests`, and the checked-in `graphite-text-box-v1.pdf`);
  - samples made as Preview and Acrobat make them, read correctly (`PDFTextBoxSampleReadingTests`). Not real Preview or Acrobat files: Preview's sample was written by PDFKit's own `/FreeText`, which is what Preview uses, and Acrobat's was written by hand with the keys Acrobat writes. Real files from both are still to try;
  - unknown keys kept on save.
- [x] Malformed `/FreeText` (missing appearance, bad rich text, a damaged or outdated record) opens as plain text, never crashes.

### 2. Display and editing on the page

Issue: [#40](https://github.com/Graphite-Note/Graphite/issues/40)

- [x] Text boxes draw in Graphite's PDF view at every zoom, sharp and in the right place, including rotated ones (outlines in shape layers over the canvas on the iPad and iPhone; the annotation draws itself on the Mac and in thumbnails).
- [x] A text tool in the fixed bar (with the look of the next box), in the floating palette's accessory menu (Text Box), not on the Mac (decision 4): tap to create, then type.
- [x] Editing in place with the system text view (keyboard, Scribble, dictation), the selection frame with its corner and rotate handles, and a bar with Format, Edit Text, Duplicate, Delete and Done. Scribble and dictation are the system's and were not tried.
- [x] Undo and redo through the page's history, like ink.
- [x] Saving through the same path as ink and pictures (`PDFEdit`, `PDFFileService`, `AtomicFileWriter`), so autosave, conflict versions and file coordination apply unchanged.

### 3. Selection and stacking

Issue: [#41](https://github.com/Graphite-Note/Graphite/issues/41)

- [x] The lasso includes text boxes (as the lasso's pictures).
- [x] Moving and resizing several kinds of objects together: a box resized with ink is scaled, its text with it.
- [ ] Stacking order with pictures and ink: waits for "pictures above ink"; boxes are over the ink until then (decision 5).

### 4. Text everywhere

Issue: [#42](https://github.com/Graphite-Note/Graphite/issues/42)

- [x] The index and Search read text-box text.
- [x] Read Aloud reads text boxes in reading order (code only; no speech was run).
- [x] Links in text boxes open like other links (`/Link` annotations, which PDFKit and every reader open).

### 5. Import

Issue: [#43](https://github.com/Graphite-Note/Graphite/issues/43)

- [ ] Goodnotes text boxes and sticky notes, and Notability typed text, convert to these boxes: font, size, colour, box, rotation and links (Phase 3 step 8 of the import). The API is ready and listed in the design's "Text boxes (step 8)".

### 6. Verification

Issue: [#44](https://github.com/Graphite-Note/Graphite/issues/44)

- [x] Hosted tests on the iPad simulator: create, type, move, rotate, undo, save and reopen (`PDFTextBoxesTests`).
- [ ] Imported PDFs and boxes made in Graphite look the same in Preview, Files, Obsidian and Acrobat. Done for boxes made in Graphite with Quick Look, poppler and Ghostscript renders (`Coverage.md`); Acrobat, Files and Obsidian not tried, imports not built.
- [ ] On the owner's iPad: writing into a box with the Pencil, and editing a box on a lecture PDF.
- [x] `Architecture.md`, `Coverage.md` and `Obsidian-mobile-gaps.md` updated.

## Left, and known limits

- Editing on the Mac (decision 4) and sticky notes (decision 2).
- Free stacking with pictures and ink (decision 5).
- A page-tree change (inserting, deleting or moving pages) makes PDFKit write every annotation again and drop the keys it does not read. Graphite gives its own boxes their keys again; another application's box loses its `/RC` and is drawn plainly by PDFKit after such a change, as before this work.
- Style-only changes another application makes to a Graphite box (same text) are not seen: Graphite's record wins while `/Contents` is unchanged.
- Line spacing has no control in the format popover yet (it is read, written and kept).
- Emoji in a box are drawn as a picture of the box over the ink on the iPad, not as outlines.
