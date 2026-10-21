# NotebookImport

Reads Goodnotes (`.goodnotes`) and Notability (`.note`) notebooks and plans each of their pages as plain values, so that an app can write them as ordinary files: a PDF page of the source's size, its background, its strokes as sampled points, its pictures with their original files, its bookmarks, the notebook's outline and its recordings. Everything the package cannot keep exactly is a typed entry of an import report, never dropped in silence.

The formats are undocumented. What is known about them, and how each statement was checked, is in Graphite's `Docs/Goodnotes-format.md` and `Docs/Notability-format.md`.

## Public API

- Readers: `GoodnotesNotebookReader(archiveBytes:limits:)` and `NotabilityNoteReader(archiveBytes:limits:)`. Pass memory-mapped bytes. Opening reads only the notebook's index (Goodnotes' schema and event log, Notability's `Session.plist` and recordings library); `page(at:)` and `page(number:)` decode one page; `contents(ofFileAt:)` and `copy(fileAt:to:)` read the notebook's own files (attachments, PDFs, pictures, recordings), a stored file as a slice of the archive's bytes.
- Planners: `GoodnotesPagePlanner.plan(_:pageNumber:)` and `NotabilityPagePlanner.plan(_:note:)` give an `ImportedPageOutcome` (an `ImportedPagePlan` or a page left out); `GoodnotesOutlinePlanner` gives a Goodnotes notebook's outline (`ImportedOutlinePlan`); `GoodnotesRecordingPlanner` and `NotabilityRecordingPlanner` the recordings (`ImportedRecordingsPlan`).
- `ImportSourceFiles`: how a writer reads the files a plan names; both readers conform.
- `NotebookFileFormat`: the two formats, by the file extension each app gives its notebooks.
- `NotebookImportName`: the name of the PDF a notebook becomes, from its file name.
- `NotebookImportReport`: every source page, written or left out, with its entries, and a summary with one line per kind of entry. The words are the caller's: the report holds facts only.

## Limits

`NotebookImportLimits.standard` bounds every size read from a file before anything of that size is allocated: 512 MiB per archive entry on the Mac and 256 MiB on the iPhone and iPad, 64 MiB per compressed payload, 64 levels of nesting and of keyed-archive references, and 250,000 plain values per property list. A file past a limit fails with a typed error. A damaged element, picture, shape, record or text run is skipped and listed as an issue; the rest of its page is read.

## Not converted

Typed text (Goodnotes text boxes, sticky notes, older RTF text boxes and Notability's typed text), tape, the older Goodnotes varying-width ink and the timing of strokes against a recording are counted in the report as left out. Shapes are planned as ink along their outline, and dashes as solid ink.

## What the package does not do

It imports Foundation, CoreGraphics and zlib only, does no file I/O of its own (the caller maps the notebook and hands its bytes in) and never writes a file. Writing the PDF and the recordings is the caller's.

## Tests

`swift test --package-path Packages/NotebookImport`. The tests build their notebooks synthetically. Tests against real notebooks (`*SampleTests`) run only when `GRAPHITE_IMPORT_SAMPLES` names a folder of samples and `GRAPHITE_IMPORT_REFERENCE_COUNTS` the reference readers' counts for it (`Tests/NotebookImportTests/Fixtures/NotebookImportSamples.swift`); they are skipped otherwise, because the only samples so far are personal notebooks that are never in the repository.
