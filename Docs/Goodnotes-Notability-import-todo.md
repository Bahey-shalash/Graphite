# Reverse engineering Goodnotes and Notability files: TODO

Created: 2026-10-18.

Status: Phase 1 under way. The formats are decoded and written down in [Goodnotes-format.md](Goodnotes-format.md) and [Notability-format.md](Notability-format.md), with reference readers in `scripts/`: on 2026-10-18 from the owner's first samples, on 2026-10-19 from samples made for the purpose in the Mac apps and a selection from the owner's Goodnotes library, compared with each app's own PDF export. Phase 2 is built and tested: GraphiteCore reads both formats (`GoodnotesNotebookReader`, `NotabilityNoteReader`), and their counts equal the reference readers' on every sample of the `samples/import-formats` branch. Nothing converts an imported notebook into Graphite's files yet, and nothing in the app calls the readers (Phases 3 to 5).

This is a large piece of work: two undocumented, versioned formats, each with handwriting, typed text, images, PDFs and (for Notability) audio.

## Request

Reverse engineer the Goodnotes (`.goodnotes`) and Notability (`.note`) file formats so a student can move their existing notebooks into a Graphite vault without losing their handwriting, and keep using it.

## What the result must be: as if it had been made in Graphite

The goal is element-level fidelity, not a picture of each page. An imported notebook must open in Graphite as though it had been written there: every element is a separate object of the right kind, can be selected, moved and edited with Graphite's own tools, and sits on the same paper at the same size. Flattening a page into one image, or burning ink into the page, fails the import.

OBJECTIVE.md forbids a proprietary document format as the authoritative copy, so the result is Graphite's own notebook model (a PDF with paper as page content, ink and objects as standard annotations, plus Graphite's optional editing metadata), not a second storage format. The original file is never modified or deleted.

Each source element maps to its Graphite equivalent:

| Source element | Must arrive as | Kept exactly |
|---|---|---|
| Page size and orientation | The PDF page's size, per page (a notebook may mix sizes) | Size in points, orientation, page order, deleted pages left out |
| Paper template (blank, ruled, grid, dotted, Cornell, music, …) | Paper drawn as page content through Graphite's paper system, separate from the ink | Template type, line spacing, margins, line color and strength, paper color; a template Graphite lacks is added to the paper system, not baked in as a bitmap |
| Custom paper (an image or PDF the user chose as a template) | That image or PDF page as the page's content | The original file's quality, not a re-render |
| Imported PDF pages (slides, worksheets) | The original PDF page, untouched | Its text, links and vector content; still selectable and searchable |
| Pen and fountain pen strokes | PencilKit strokes, one per source stroke, and PDF ink annotations | Every point, pressure, width, color, opacity, tool type |
| Highlighter strokes | Highlighter strokes, drawn under text as in the source | Color, width, transparency |
| Shapes (lines, rectangles, ellipses, arrows, filled shapes) | Shapes, editable as shapes where Graphite has the shape | Geometry, stroke and fill colors, width |
| Images and stickers | Separate pictures: selectable, movable, resizable, turnable, croppable | The original image file, position, size, rotation, crop, and order relative to ink |
| Typed text boxes | Editable text boxes on the page | Text, font, size, color, alignment, box position and width |
| Tape, if the source has it | Tape, once Graphite has it; otherwise reported | Position and color |
| Links and page links | PDF link annotations | Target page or URL |
| Outline, bookmarks, page titles, dividers | PDF outline and bookmarks | Names and order |
| Element order (what is above what) | The same stacking | Z-order between ink, images, shapes and text |
| Notability audio | `.m4a` next to the PDF | The recording, and the stroke-to-audio timing for synchronized replay |
| Notebook metadata | Optionally a Markdown note with properties and an embed of the PDF | Title, created and modified dates, folder, cover |

Anything that cannot be kept exactly is named in the import report, never dropped silently.

## Graphite features this needs first

Element-level import can only be as good as Graphite's own editor: where Graphite has no native equivalent, the import would have to flatten. These have to exist in Graphite before the matching part of the import counts as done (status from `Premium-experience-plan.md` on 2026-10-18):

- [ ] Typed text boxes on PDF pages: listed there as still to build. Both formats use them: Goodnotes text boxes and sticky notes with fonts, sizes, colours and links; Notability's typed body text.
- [ ] Pictures above the ink, and free stacking between pictures, shapes, text and ink: today pictures always sit under the ink. Goodnotes stacks pictures and ink freely (with highlighter ink always under the rest); Notability, like Graphite, always draws pictures under the ink.
- [ ] Shapes as editable objects after drawing (today a snapped shape becomes a stroke; check whether that is enough to keep it editable as a shape).
- [ ] Any paper template, page size or paper color found in the samples that Graphite's paper system does not offer yet.
- [ ] Tape and stickers, if the owner wants them as native features.
- [ ] Synchronized audio replay for Notability recordings (a candidate in `Premium-experience-plan.md`, not planned yet).

## Phase 1: collect samples and document the formats

- [ ] Build a sample set from the owner's own notebooks and from files made for the purpose: every paper type, pen, highlighter, eraser, shapes, lasso-moved strokes, colors, widths, pressure, text boxes, images, imported PDFs, page reordering, deleted pages, outlines, links, and (Notability) recordings. Several app versions where possible. **Mostly done 2026-10-19**, on the `samples/import-formats` branch (personal notes, not to be merged): 45 Goodnotes notebooks (schemas 24, 25, 26 and 35; Goodnotes 7.1.28 for Mac and the owner's iPad library) and 10 Notability notes (14.3 and 16.13). A Goodnotes Pencil test written with an Apple Pencil came the same day (schema 27, with its export). **Still needed:** a Notability note written with an Apple Pencil, to show pressure, tilt and azimuth there; Notability rectangles and ellipses (shape recognition did not take mouse strokes), coloured papers, A4 and landscape notes, captions, underline and checklists; Goodnotes links to a page and turned text boxes.
- [ ] For each sample, export the same notebook to PDF from the app itself; these exports are the reference for visual comparison. **Done** for the 14 made-for-purpose samples and the first Notability note: each format document has a table of the pixel differences per page. Not done for the four first Goodnotes notebooks and the 35 library notebooks.
- [x] Unpack the container. Confirmed on the samples, with corrections: Goodnotes is a ZIP of length-prefixed protobuf records with no schema, an event log of last-writer-wins registers, ink paths compressed with Apple's LZ4 framing around Troy Hanson's tpl serialisation, and paper as a PDF attachment; Notability is a ZIP of keyed archives (`GLKeyedArchiver` for the session), ink as packed parallel arrays of cubic Bézier chains with per-knot width, force, altitude and azimuth.
- [x] Survey existing open-source readers and write-ups; record their licenses and what they cover. Reuse ideas and test data only where licenses allow. Recorded at the end of each format document: three MIT-licensed readers that claim the content the samples lack, one write-up for Notability. Nothing was taken from their code; their claims are leads for the samples still needed.
- [x] Write `Docs/Goodnotes-format.md` and `Docs/Notability-format.md`: container layout, schemas (recovered `.proto` definitions for Goodnotes, plist keys for Notability), stroke encoding (points, pressure, width, color, tool), coordinate systems and page sizes, text, images, PDF references, and how each changed across versions. **Written for everything in the samples**, each statement checked by the reference readers (`scripts/goodnotes-reader.py`, `scripts/notability-reader.py`, which list any record kind, field or key they do not know) and against the apps' exports. What the samples could not show is listed as unknown in each document and grows with each new sample.

## Phase 2: parsers

- [x] Pure Swift parsers in `GraphiteCore`, no third-party dependencies, streaming page by page so a 500-page notebook never sits in memory at once. **Done 2026-10-19** (`Sources/GraphiteCore/NotebookImport/`): both readers take the archive's bytes (memory-mapped by the caller) and inflate a ZIP entry only when asked for. Goodnotes: opening reads the schema and event log, `page(at:)` one page's layer. Notability: the session's packed curve arrays stay as slices of its bytes, and `curve(at:)` and `page(number:)` decode only the curves asked for. Memory and time were not measured: the largest sample has 39 pages (46,103 strokes), and no notebook of hundreds of pages was read; Phase 5 measures on the iPad.
- [x] A minimal protobuf wire-format reader for Goodnotes (no generated code from a full protobuf library) and a binary plist reader built on `PropertyListSerialization` plus `NSKeyedArchiver` object-graph resolution for Notability. **Done 2026-10-19**, with one change: `PropertyListSerialization` returns a keyed archive's UIDs as opaque `CFKeyedArchiverUID` objects whose number is reachable only through private API, so binary plists are read by Graphite's own bounded `bplist00` reader (`BinaryPropertyList`), and `PropertyListSerialization` reads only the XML `Recordings/library.plist`. Object-graph resolution (`KeyedArchive`) is lazy, one reference at a time, with cycle and depth protection.
- [x] Unknown fields and unknown versions are reported, never guessed: a page that cannot be read fully is imported as far as it can be and listed in an import report. Values read as strings (Goodnotes template ids, Notability paper identifiers, shape kinds) are decoded once into enums with an `unknown(raw)` case (`FR-20`). The reference readers in `scripts/` give the expected values for tests: element counts, sizes and decoded geometry per sample page. **Done 2026-10-19**: issues per format (`GoodnotesReadingIssue`, `NotabilityReadingIssue`) mirror every "unknown" category of the reference readers; a part the reference reader would stop on (an element, a record, a picture, a shape) is skipped and listed with its typed error, and the rest of its page is returned. Template ids, Notability paper attributes and shape kinds decode into enums with `unknown(raw)`. `GoodnotesNotebookReaderSampleTests` and `NotabilityNoteReaderSampleTests` compare the counts and unknown categories with `scripts/import-reference-counts.py` on the owner's samples, when `GRAPHITE_IMPORT_SAMPLES` and `GRAPHITE_IMPORT_REFERENCE_COUNTS` are set (skipped otherwise, as the samples are personal): equal on all 41 Goodnotes notebooks and 9 Notability notes of the branch (tables in each format document). The four Goodnotes notebooks of 2026-10-18 and the Pencil test are not on the branch and were not compared.
- [x] Fuzz and malformed-input tests: truncated archives, huge counts, cyclic object graphs. A broken file fails cleanly, never crashes or hangs. **Done 2026-10-19**: `ZipArchiveTests`, `ProtocolBufferMessageTests`, `AppleLZ4DecoderTests`, `TplImageTests`, `GoodnotesNotebookReaderTests`, `BinaryPropertyListTests`, `KeyedArchiveTests`, `NotabilityNoteReaderTests` and `NotabilityNoteReaderMalformedInputTests`, on synthetic files built in the tests: wrong magic numbers, cuts at every byte, declared sizes and counts up to 2^64 refused before any allocation, cyclic and exponentially shared object graphs, and seeded byte changes of valid files. Each ends in a typed error or a listed skipped part.

## Phase 3: conversion to ordinary files

Every row of the table above, one element at a time:

- [ ] Strokes to PencilKit strokes (for re-editing) and to PDF ink annotations (for every reader), one Graphite stroke per source stroke, with the source's points, pressure, width, color, opacity and tool.
- [ ] Paper as page content through Graphite's paper system, with the source's exact spacing, margins and colors; custom paper from its original file.
- [ ] Page sizes and orientation per page.
- [ ] Images as separate pictures from their original files, with position, size, rotation, crop and stacking.
- [ ] Text boxes as editable text boxes; shapes as shapes; links, outline and bookmarks.
- [ ] Notability audio and its timing.
- [ ] Folder structure of a Goodnotes or Notability library export kept as folders in the vault.

## Phase 4: import experience

- [ ] Import from the Files app, the share sheet (Graphite has no share extension yet; this would add one) and drag and drop, one file or a whole folder.
- [ ] A progress view for large libraries, cancellable, running off the main thread; the vault stays usable during import.
- [ ] An import report: what was converted, what was simplified, what was skipped and why.

## Phase 5: verification

- [ ] Visual comparison of every imported page against the app's own PDF export, with a pixel-difference threshold, as automated tests on the sample set.
- [ ] Element-level comparison, as automated tests: for each sample page, the count and kind of strokes, pictures, text boxes and shapes match the source, each picture is a separate object with its original image data, page size matches to the point, and the paper is page content, not part of the ink.
- [ ] On the iPad: open an imported notebook beside the same notebook in Goodnotes or Notability, and select, move, resize and edit each kind of element; erase ink without touching the paper; write on and continue the notebook as if it had been made in Graphite.
- [ ] Imported PDFs open correctly in Preview, Files, Obsidian and a third PDF reader.
- [ ] Re-editing an imported stroke in Graphite works and survives save and reopen.
- [ ] Memory and time measured on the largest sample notebook on the owner's iPad.
- [ ] `Architecture.md`, `Coverage.md` and the gaps list updated once each part is built and tested.

## Risks

- Both formats are undocumented and change with app updates. The parsers need version detection and a sample set that grows with each new app version.
- Some content may not map exactly to PDF annotations (textured brushes, Goodnotes' handwriting-recognition data, Notability's audio-linked replay). The import report must say so instead of dropping it silently.
- Legal: reverse engineering file formats for interoperability with the user's own files, without using either app's code. The owner should confirm this boundary before Phase 1.

## Open questions

- Which comes first, Goodnotes or Notability? (Goodnotes is the one OBJECTIVE.md names as the reference.)
- Import only, or also export back to either format? Export is not planned here.
- Should the editing metadata keep the source app's stroke data so a later, better converter can redo the import without the original file?
- One PDF per notebook, or one per Goodnotes/Notability "page group" or divider?
