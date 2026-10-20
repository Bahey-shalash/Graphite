# Import Phase 3: conversion to ordinary files (design)

Status: proposal of 2026-10-20 for review, nothing built. Phase 3 of [the import checklist](Goodnotes-Notability-import-todo.md), on top of the Phase 2 readers (`GoodnotesNotebookReader`, `NotabilityNoteReader`).

## Shape

An imported notebook becomes one ordinary PDF that Graphite's own PDF code wrote, so it opens, re-edits and saves like a notebook made in Graphite:
- Each source page is a PDF page of the source's size.
- The paper is page content.
- Ink is standard `/Ink` annotations, with Graphite's re-editing record (`GraphitePencilDrawingV1`) on each page's group.
- Pictures are Graphite's `/Stamp` pictures (`PDFPicture`).
- Recordings are `.m4a` files beside it.
- The original file is never changed.

The work is split in two, as `FR-05` asks:

1. **A planner in GraphiteCore** (pure, no PencilKit or PDFKit). `NotebookImportPlanner` turns each reader page into an `ImportedPage`:
   - the page size in points;
   - the background: an attachment's PDF page, a paper specification, or a plain colour;
   - strokes as sampled points in page points (top-left origin, the canvas's drawing space). Each sample carries a width and, when the source has them, force, azimuth and altitude. Each stroke carries an ink kind, a colour and, when the source stores one, its exact outline;
   - pictures with their file, frame, rotation and crop;
   - links, outline entries and audio;
   - an `ImportReport` entry for everything simplified or left out.

   All unit conversions live here, tested with plain values (`FR-98`): Goodnotes units at 6/11 point; Notability units at `s` points, with the 15.9375-point inset and the continuous document cut into pages. So does the sampling of quadratic and cubic Béziers.
2. **A writer in GraphiteApple** (PencilKit and PDFKit). `NotebookImportWriter` takes a plan and works one page at a time:
   - makes the page from its background (it copies the attachment's PDF page, or uses `PDFTemplateGenerator`);
   - builds a `PKDrawing` from the strokes;
   - turns the drawing into a `PDFInkUpdate` through `PDFPageInkTracker`, the path every Graphite save takes;
   - places pictures as `PDFEdit.addPicture`;
   - writes the file with `AtomicFileWriter` (`.absent`, never overwriting) after verification, as `PDFFileService.saveCopy` does.

   A stroke with a stored outline (Goodnotes' fountain and brush pens) gets that outline as its annotation's appearance (`PortableInkStroke.outline`). Every PDF reader then shows Goodnotes' exact shape, and Graphite's canvas shows PencilKit's rendering of the same points.

Pages are planned and written one at a time, so the source is never decoded whole. The PDFKit document being written still grows with the notebook; memory on a 500-page notebook is measured in Phase 5 before the import is offered.

## Order of work, and what each step needs

| Step | What | Needs from Graphite | Exact or reported |
|---|---|---|---|
| 1 | Planner types, page sizes, imported PDF pages, Goodnotes paper (its template PDF page as page content), Notability page cutting; writer skeleton that writes pages and backgrounds | Nothing new | Exact |
| 2 | Ink: Goodnotes ball pen, fountain and brush pen (with their outline), pencil (force, azimuth, altitude), highlighter; Notability pen and highlighter (width × knot factor, force) | Nothing new | Exact shape in PDF readers. Two differences go in the report: Graphite draws a highlighter normally where Goodnotes multiplies it, and Graphite's pencil is not Goodnotes' texture |
| 3 | Pictures: turned, Notability crop (the bitmap cropped before placing), GIF as its first frame | Pictures above ink for Goodnotes' free stacking (checklist: "Graphite features this needs first") | Under the ink until that exists; a picture that Goodnotes draws over ink is reported |
| 4 | Shapes: lines, arcs, rectangles, ellipses, Notability lines and curves, as ink strokes sampled from their geometry | Editable shapes, dashed ink, filled shapes | Shapes arrive as ink. Dashes and fills are reported |
| 5 | Notability paper (white or black, ruled every width / 17, grid, #A3B7D3, 0.5 and 0.4 points) | `PaperSpecification` with a free line colour and line width: a small addition to the paper system | Exact once added |
| 6 | Links, bookmarks, outline: a link on a Goodnotes text box becomes a `/Link` annotation, bookmarks become outline items (`PDFEdit.bookmark`), outline entries are reported (their target is not resolved yet) | Nothing new | Exact for links and bookmarks |
| 7 | Audio: Notability `.m4a` and Goodnotes MP4 audio copied as `.m4a` where the vault's attachment policy says, and optionally a Markdown note embedding the PDF and the recordings | Synchronised replay for stroke timing (not planned) | The audio is exact. Stroke timing is not kept |
| 8 | Text boxes, sticky notes, older RTF text boxes, Notability typed text | Text boxes on PDF pages | Blocked; see question 1 and "Text boxes" below |
| 9 | The import report value (per page: converted, simplified, skipped, with the reason), for Phase 4 to show | Nothing new | — |

Steps 1, 2 and 9 come first and stand alone. Steps 3, 4 and 6 follow with their reported limits. Step 5 needs its paper addition first. Step 7 is independent. Step 8 waits for the feature or for the owner's interim choice.

## Text boxes (step 8)

What a Goodnotes text box needs, from the text-box sample (2026-10-20) checked against its export:
- **Placement:** the box's top-left corner, a scale and an angle.
- **Geometry:** in points, the box is its stored size × scale × 6/11, turned clockwise about that corner. Font sizes and insets scale the same way: a 24-unit font at scale 11.02 is 144.3 points.
- **Text:** starts at the inset, with its first baseline at inset + 0.952 × the font size, in Helvetica Neue ("Modern") or Georgia ("Classic").
- **Links:** a run's link becomes a `/Link` annotation over the box.

Whichever way the owner chooses, the planner gives each text box as a value: text, runs, fonts, sizes in points, colours, links, and the box's frame with its angle. The writer then needs one of:
- a Graphite text box on PDF pages;
- a standard `/FreeText` annotation, which turned text needs drawn in its own appearance stream, since `/FreeText` has no angle of its own;
- only the report entry.

Notability's typed text is the note's body, laid out from the document's top left with no box. It would become one box the page's width at the top of the first page, flowing onto later pages as the export shows.

## Tests

- **Planner** (GraphiteCore): value tests on synthetic reader values. They cover every unit conversion, the page cutting, Bézier sampling within a stated tolerance and the report entries.
- **Writer** (GraphiteApple, macOS package tests): synthetic plans written to a temporary vault, then read back with PDFKit and with `PDFEditableInkGroup`. The checks: page count and sizes, `/Ink` count per page, the re-editing record decoding to the same number of strokes, pictures as stamps, links, and the source file unchanged.
- **Samples:** an opt-in test (the same `GRAPHITE_IMPORT_SAMPLES` skip) imports every sample and compares stroke, picture and page counts with the readers. The pixel comparison with each app's export is Phase 5.

No full or hosted suites run locally; only these classes, with `--filter`.

## Questions for the owner

1. **Text boxes:** until Graphite has text boxes on PDF pages, should text become standard `/FreeText` annotations (visible and editable in Preview and other readers, not yet in Graphite), or wait for the feature and only list the text in the report?
2. **Highlighter:** may an imported highlighter look lighter over coloured ink than in Goodnotes (Graphite does not multiply)?
3. **Stroke timing:** may the recordings' stroke timing be left out until Graphite has synchronised replay, or should it be kept in the optional companion note's properties?
4. **Companion note:** should the import also write a Markdown note per notebook (title, dates, an embed of the PDF and its recordings), or only the PDF and the audio?
