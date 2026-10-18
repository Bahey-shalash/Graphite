# Reverse engineering Goodnotes and Notability files: TODO

Created: 2026-10-18.

Status: not started. Nothing below is implemented. Graphite cannot read `.goodnotes` or `.note` files, and Phase 1 needs sample notebooks from the owner.

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

- [ ] Typed text boxes on PDF pages: listed there as still to build.
- [ ] Pictures above the ink, and free stacking between pictures, shapes, text and ink: today pictures always sit under the ink.
- [ ] Shapes as editable objects after drawing (today a snapped shape becomes a stroke; check whether that is enough to keep it editable as a shape).
- [ ] Any paper template, page size or paper color found in the samples that Graphite's paper system does not offer yet.
- [ ] Tape and stickers, if the owner wants them as native features.
- [ ] Synchronized audio replay for Notability recordings (a candidate in `Premium-experience-plan.md`, not planned yet).

## Phase 1: collect samples and document the formats

- [ ] Build a sample set from the owner's own notebooks and from files made for the purpose: every paper type, pen, highlighter, eraser, shapes, lasso-moved strokes, colors, widths, pressure, text boxes, images, imported PDFs, page reordering, deleted pages, outlines, links, and (Notability) recordings. Several app versions where possible.
- [ ] For each sample, export the same notebook to PDF from the app itself; these exports are the reference for visual comparison.
- [ ] Unpack the container. Both are reported by existing open-source readers to be ZIP archives: Goodnotes with protobuf-encoded page and stroke data plus attachment files, Notability with a binary property list (`NSKeyedArchiver`) describing the session, packed stroke point arrays, assets and recordings. Confirm each of these on our samples before relying on it.
- [ ] Survey existing open-source readers and write-ups; record their licenses and what they cover. Reuse ideas and test data only where licenses allow.
- [ ] Write `Docs/Goodnotes-format.md` and `Docs/Notability-format.md`: container layout, schemas (recovered `.proto` definitions for Goodnotes, plist keys for Notability), stroke encoding (points, pressure, width, color, tool), coordinate systems and page sizes, text, images, PDF references, and how each changed across versions.

## Phase 2: parsers

- [ ] Pure Swift parsers in `GraphiteCore`, no third-party dependencies, streaming page by page so a 500-page notebook never sits in memory at once.
- [ ] A minimal protobuf wire-format reader for Goodnotes (no generated code from a full protobuf library) and a binary plist reader built on `PropertyListSerialization` plus `NSKeyedArchiver` object-graph resolution for Notability.
- [ ] Unknown fields and unknown versions are reported, never guessed: a page that cannot be read fully is imported as far as it can be and listed in an import report.
- [ ] Fuzz and malformed-input tests: truncated archives, huge counts, cyclic object graphs. A broken file fails cleanly, never crashes or hangs.

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
