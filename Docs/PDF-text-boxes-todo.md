# Text boxes on PDF pages: TODO

Created: 2026-10-20.

Status: not started. Graphite can write ink, pictures and markup on a PDF page, but not typed text. Nothing below is implemented.

## Request

The owner (2026-10-20): "allow text boxes in pdfs (not just for now but in general)". Typed text boxes are a feature of every PDF in Graphite, whether a notebook, lecture slides, a worksheet or an imported Goodnotes or Notability notebook. They are not only a target for the import.

The Goodnotes and Notability import leaves typed text out until this exists (owner decision, 2026-10-20). Its step 8 in `Goodnotes-Notability-import-phase-3-design.md` waits on this checklist.

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

## Phases

### 1. Model and file format
- [ ] A `PDFTextBox` value in GraphiteCore or GraphiteApple: content, attributes, frame, rotation, style.
- [ ] Writing and reading `/FreeText`:
  - `/Contents` holds the plain text, `/RC` the rich text, `/DA` and `/DS` the default appearance and style, `/Rect`, `/Rotate` or a rotation matrix, and `/BS` and `/C` for border and fill;
  - a generated appearance stream so readers that ignore `/RC` still draw it exactly.
- [ ] Golden-file tests:
  - files written by Graphite, read back unchanged;
  - samples made in Preview and Acrobat, read correctly;
  - unknown keys kept on save.
- [ ] Malformed `/FreeText` (missing appearance, bad rich text) opens as plain text, never crashes.

### 2. Display and editing on the page
- [ ] Text boxes draw in Graphite's PDF view at every zoom, sharp and in the right place, including rotated ones.
- [ ] A text tool in the Pencil toolbar, and in the Mac's tools: tap to create, then type.
- [ ] Editing in place with the system text input (keyboard, Scribble, dictation), selection handles, rotation handle, delete.
- [ ] Undo and redo through the page's history, like ink.
- [ ] Saving through the same path as ink and pictures (`PDFPageInkTracker`, `PDFPageManager`, `AtomicFileWriter`), so autosave, conflict versions and file coordination apply unchanged.

### 3. Selection and stacking
- [ ] The lasso includes text boxes.
- [ ] Moving and resizing several kinds of objects together.
- [ ] Stacking order with pictures and ink (depends on "pictures above ink").

### 4. Text everywhere
- [ ] The index and Search read text-box text.
- [ ] Read Aloud reads text boxes in reading order.
- [ ] Links in text boxes open like other links.

### 5. Import
- [ ] Goodnotes text boxes and sticky notes, and Notability typed text, convert to these boxes: font, size, colour, box, rotation and links (Phase 3 step 8 of the import).

### 6. Verification
- [ ] Hosted tests on the iPad simulator: create, type, move, rotate, undo, save and reopen.
- [ ] Imported PDFs and boxes made in Graphite look the same in Preview, Files, Obsidian and Acrobat.
- [ ] On the owner's iPad: writing into a box with the Pencil, and editing a box on a lecture PDF.
- [ ] `Architecture.md`, `Coverage.md` and `Obsidian-mobile-gaps.md` updated once each part is built and tested.

## Open questions for the owner

- Should a text box start with the last-used font and size, or a fixed default?
- Are sticky notes (the collapsed `/Text` note icon) wanted as well, or only boxes on the page?
- On the iPhone, is creating text boxes needed, or only reading and light editing?
