# Import Phase 3: conversion to ordinary files (design)

Status: reviewed 2026-10-20, with the owner's decisions below. Steps 1 and 2 are built and tested ("Built so far" below); nothing calls them from the app yet. Phase 3 of [the import checklist](Goodnotes-Notability-import-todo.md), on top of the Phase 2 readers (`GoodnotesNotebookReader`, `NotabilityNoteReader`).

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

## Built so far (steps 1 and 2, 2026-10-20)

- **Planners (GraphiteCore):**
  - `GoodnotesPagePlanner` and `NotabilityPagePlanner` turn a reader page into an `ImportedPageOutcome`: a planned page or a page left out, with its `ImportReportEntry` list.
  - Curves are sampled to 0.1 point (`BezierFlattening`).
  - Goodnotes' fountain and brush outlines are flattened into the stroke's exact outline (`GoodnotesOutlineFlattening`).
  - A Notability curve that crosses a page edge is cut there (`NotabilityCurveSampling`).
  - Shapes, fills, pictures, text, tape and the older ink are counted in the report for their later steps.
- **Writer (GraphiteApple):** `NotebookImportWriter.write(pageCount:planForPage:sourceFiles:strokeCreationDate:to:)` writes one PDF, one page at a time:
  - the background is a copy of the source PDF page, or a page redrawn upright and stretched when its size or rotation differs, or plain paper;
  - the ink goes through `PDFPageInkTracker`, so the page carries Graphite's re-editing record;
  - the file is written with `AtomicFileWriter` (`.absent`) through `PDFFileService`'s verification.
- **PencilKit's point size is not the width it draws.** Measured on macOS 27 and the iOS 27 simulator:
  - the monoline and the pen draw 2 × size − 4;
  - the fountain pen with its nib across the stroke draws the same;
  - the pencil draws about 1.73 × size;
  - the highlighter, with its tip across the stroke, draws about 1.37 × size.

  `ImportedStrokeBuilder` picks each point's size from these measurements (`PencilInkRenderedWidth`), so the canvas draws the planned width. The writer then replaces each stroke's PDF appearance with the planned one (the source's outline, or the samples outlined at their planned widths), since `PDFPageInkTracker` takes the size as the width. Graphite's own PDF ink takes the size as the width too, which likely makes its saved ink thinner than the canvas shows: a follow-up outside the import.
- **Not exact:**
  - PencilKit's data stores a monoline stroke made from points as pen ink, which draws the same.
  - The highlighter's transparency is in the PDF appearance only, and it is not multiplied (owner decision 2).
  - The pencil's grain varies its edge by about 2%.
- **Tests:**
  - `GoodnotesPagePlannerTests`, `NotabilityPagePlannerTests`, `BezierFlatteningTests` and `ImportReportTallyTests` test the planners with values.
  - `GoodnotesPagePlannerSampleTests` and `NotabilityPagePlannerSampleTests` plan every page of every sample (opt-in).
  - `ImportedStrokeBuilderTests` and `NotebookImportWriterTests` write PDFs and read them back with PDFKit.
  - Not done yet: a sample notebook written end to end and compared with its export (Phase 5).

## Order of work, and what each step needs

| Step | What | Needs from Graphite | Exact or reported |
|---|---|---|---|
| 1 | Planner types, page sizes, imported PDF pages, Goodnotes paper (its template PDF page as page content), Notability page cutting; writer skeleton that writes pages and backgrounds | Nothing new | Exact |
| 2 | Ink: Goodnotes ball pen, fountain and brush pen (with their outline), pencil (force, azimuth, altitude), highlighter; Notability pen and highlighter (width × knot factor, force) | Nothing new | Exact shape in PDF readers. Two differences go in the report: Graphite draws a highlighter normally where Goodnotes multiplies it, and Graphite's pencil is not Goodnotes' texture |
| 3 | Pictures: turned, Notability crop (the bitmap cropped before placing), GIF as its first frame | Pictures above ink for Goodnotes' free stacking (checklist: "Graphite features this needs first") | Under the ink until that exists; a picture that Goodnotes draws over ink is reported |
| 4 | Shapes: lines, arcs, rectangles, ellipses, Notability lines and curves, as ink strokes sampled from their geometry | Editable shapes, dashed ink, filled shapes | Shapes arrive as ink. Dashes and fills are reported |
| 5 | Notability paper (white or black, ruled every width / 17, grid, #A3B7D3, 0.5 and 0.4 points) | `PaperSpecification` with a free line colour and line width: a small addition to the paper system | Exact once added |
| 6 | Links, bookmarks, outline: a link on a Goodnotes text box becomes a `/Link` annotation, bookmarks become outline items (`PDFEdit.bookmark`), outline entries are reported (their target is not resolved yet) | Nothing new | Exact for links and bookmarks |
| 7 | Audio: Notability `.m4a` and Goodnotes MP4 audio copied as `.m4a` where the vault's attachment policy says; no companion note (owner decision 4) | Synchronised replay for stroke timing (not planned) | The audio is exact. Stroke timing is not kept |
| 8 | Text boxes, sticky notes, older RTF text boxes, Notability typed text | Text boxes on PDF pages | Blocked; listed in the report until then (owner decision 1, and "Text boxes" below) |
| 9 | The import report value (per page: converted, simplified, skipped, with the reason), for Phase 4 to show | Nothing new | — |

Steps 1, 2 and 9 come first and stand alone. Steps 3, 4 and 6 follow with their reported limits. Step 5 needs its paper addition first. Step 7 is independent. Step 8 waits for text boxes on PDF pages (owner decision 1).

## Text boxes (step 8)

What a Goodnotes text box needs, from the text-box sample (2026-10-20) checked against its export:
- **Placement:** the box's top-left corner, a scale and an angle.
- **Geometry:** in points, the box is its stored size × scale × 6/11, turned clockwise about that corner. Font sizes and insets scale the same way: a 24-unit font at scale 11.02 is 144.3 points.
- **Text:** starts at the inset, with its first baseline at inset + 0.952 × the font size, in Helvetica Neue ("Modern") or Georgia ("Classic").
- **Links:** a run's link becomes a `/Link` annotation over the box.

Until Graphite has text boxes on PDF pages, text is left out and listed in the report (owner decision 1). When it has them, the planner gives each text box as a value (text, runs, fonts, sizes in points, colours, links, and the box's frame with its angle), and the writer makes a Graphite text box of it.

Notability's typed text is the note's body, laid out from the document's top left with no box. It would become one box the page's width at the top of the first page, flowing onto later pages as the export shows.

## Tests

- **Planner** (GraphiteCore): value tests on synthetic reader values. They cover every unit conversion, the page cutting, Bézier sampling within a stated tolerance and the report entries.
- **Writer** (GraphiteApple, macOS package tests): synthetic plans written to a temporary vault, then read back with PDFKit and with `PDFEditableInkGroup`. The checks: page count and sizes, `/Ink` count per page, the re-editing record decoding to the same number of strokes, pictures as stamps, links, and the source file unchanged.
- **Samples:** an opt-in test (the same `GRAPHITE_IMPORT_SAMPLES` skip) imports every sample and compares stroke, picture and page counts with the readers. The pixel comparison with each app's export is Phase 5.

No full or hosted suites run locally; only these classes, with `--filter`.

## Owner decisions (2026-10-20)

The owner's answer, word for word: "Leave typed text out until Graphite has real text boxes on PDF pages; a lighter highlighter is fine, drop audio timing for now, no companion note."

1. **Typed text** is not imported for now, and there is no `/FreeText` stand-in. Goodnotes text boxes, older RTF text boxes, sticky notes and Notability's typed text are listed in the import report as left out, with the reason. Step 8 stays blocked on real text boxes on PDF pages. The readers' text model, rotation included, stays ready for it.
2. **Highlighter:** a plain see-through highlighter is fine; the report notes that Graphite does not multiply it as Goodnotes does.
3. **Audio:** the `.m4a` is kept, and the timing of strokes during a recording is dropped for now.
4. **No companion Markdown note:** the import writes the PDF (and the audio), and its report is shown after the import.
