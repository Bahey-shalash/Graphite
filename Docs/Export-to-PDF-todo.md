# Export a note to PDF: TODO

Created: 2026-10-21.

Priority: highest. The owner called it "extremely important" on 2026-10-21.

Status: sections 1 and 3 done, 2 and 4 in part, on branch `export-note-to-pdf` (2026-10-21): More › Export to PDF… on a note makes a PDF of its reading view and saves it where the person picks. Before that, Graphite could export PDF pages (`PDFPane` › Export Pages…) and drawings (`DrawingEditor` › Export a Copy), but nothing turns a Markdown note into a PDF. The reading view (`MarkdownPreview`, `ReadingBlocksView` on the vendored Textual renderer) is drawn in a `LazyVStack` inside a `ScrollView`, so it cannot be printed or rendered whole as it is.

## Request

Export a Markdown note to a PDF, as Obsidian's "Export to PDF" does: the note as the reading view shows it, laid out on pages, saved where the person picks or shared. Notes are mostly lecture notes, so math, callouts, tables, code, embedded pictures, drawings and diagrams must come out right.

## Decisions

- The PDF is a copy written where the person chooses (file exporter or share sheet). Graphite writes nothing into the vault unless the person saves it there; the note itself is never changed.
- It renders the reading view's blocks, not HTML: no web view and no second Markdown renderer, so the PDF looks like Graphite and the core stays small.
- Text stays vector and selectable in the PDF; pictures keep their resolution.

## 1. Export a note

- [x] A renderer in GraphiteUI that lays the note's reading-view blocks out at the page's text width, without the scroll view, and draws them into a PDF context page by page (`ImageRenderer` into a `CGContext` PDF, or `UIGraphicsPDFRenderer`, whichever keeps text as text).
  Done 2026-10-21: `NotePDFRenderer` builds the note with `ReadingViewBuilder` (Markdown divided into sections), draws each block with the reading view's own views through `ImageRenderer` into a `CGContext` PDF at the layout width (text width ÷ (0.75 × downscale), so 16-point text prints at 12 points). Textual updates its state after each drawing, so a block is drawn until its height holds (3 to 10 drawings); two Textual changes make a one-shot drawing complete (patch 18: images the cache holds draw at once; code and wide tables wrap instead of sitting in a scroll view). Text is vector and selectable; formulas are Textual canvas symbols, drawn at 4 pixels per point. Tests: `NotePDFRendererTests` (7, Mac), hosted `NotePDFExportHostedTests` (4, iPad Pro 11-inch simulator, iOS 27.0).
- [x] Page breaks between blocks; a block taller than a page (a long table, code block or picture) is split at a line or row, or scaled to fit for a picture, never cut through a line of text. Headings are kept with the block that follows them.
  Done 2026-10-21: `NotePageFlow` (Core) places the blocks; lists, tables, code blocks, callouts, embedded notes and footnotes are divided between their parts (`MarkdownSectionUnits`: tables repeat their header, code its fences, ordered lists keep counting); a block or part still taller than a page is cut in a gap between lines found in a picture of it (`PrintedLineGaps`), at the page's height only when it has none; pictures and PDF pages taller than a page are scaled onto a page of their own. Tests: `NotePageFlowTests` (15), `MarkdownSectionUnitsTests` (7), `PrintedLineGapsTests` (2), `NotePDFRendererTests` (every line printed once, header repeated, heading on its list's page, a paragraph taller than a page cut between lines), hosted `NotePDFExportHostedTests`. Known: a cut band's hidden lines inside the page margins can be found twice by a PDF reader's search.
- [x] Runs off the main actor where it can and shows progress for long notes; cancelling leaves nothing behind.
  Done 2026-10-21: building the blocks, reading pictures and embedded PDFs, scanning links and finishing the PDF run off the main actor; measuring and drawing run on it (SwiftUI draws only there) block by block with a turn of the main actor between drawings. The sheet shows a progress bar with Stop; the PDF lives in memory until saved, so a cancelled export leaves nothing. Tests: `NotePDFRendererTests.testCancellingStopsTheExportWithoutAResult`, hosted sheet test (export to the saving step). Timing on the iPad simulator: a 34-page lecture note with 40 figures in 3.3 to 4.6 s.
- [x] The PDF's title is the note's name, its author left empty, and its outline (bookmarks) follows the note's headings.
  Done 2026-10-21: `NotePDFFinishing` (PDFKit, off the main actor); PDFKit writes a new outline only with a rewritten page tree, so the first page is taken out and put back first. Tests: `NotePDFRendererTests` (title, no author, nested outline), hosted test (outline).

## 2. What the PDF shows

- [ ] Everything the reading view draws: headings, lists, tasks, quotes, callouts (collapsed callouts printed open), tables, code with its highlighting, math (inline and display), footnotes, horizontal rules, highlights, tags.
  In part 2026-10-21: all of these print as the reading view draws them (checked page by page in PDFs made on the iPad simulator from the demo vault's sampler note and `9_Static logic`; text checked by `NotePDFRendererTests` and the hosted tests). Open: very wide display formulas break oddly at the print width, with a stray bar at their right edge (`9_Static logic`, last pages), and a formula is a 4× bitmap, not vector.
- [ ] Embeds: pictures, drawings (SVG and PNG), diagrams, embedded notes and note sections, a page of an embedded PDF; a video or audio embed is printed as its file name.
  In part 2026-10-21: pictures (full size, the hosted test checks their pixels), embedded notes (divided between pages, their title repeated) and an embedded PDF's page (drawn by PDFKit with its annotations, its text kept) checked on the simulator. Not yet checked: a Graphite drawing (SVG and PNG), a video or audio embed (printed as its name in code), diagrams. An SVG from another app prints as its name, as the reading view cannot show it. Pictures print at the column's width as in the reading view, which can leave a large figure alone on a page.
- [x] Links: internal links are printed as their text; web links stay clickable in the PDF.
  Done 2026-10-21: web links get PDFKit link annotations over their words (`NotePDFTextScan`, `NotePDFFinishing`); internal links print as accent-coloured text. Tests: `NotePDFRendererTests` and the hosted test read back exactly one link annotation with the URL. Not yet opened in Acrobat.
- [x] Frontmatter properties are left out by default (as in Obsidian), with an option to include them.
  Done 2026-10-21: printed as a read-only list of names and values (the reading view's panel edits in text fields, which cannot be drawn). Test: `NotePDFRendererTests.testPropertiesArePrintedOnlyWhenAskedFor`.
- [x] Light colours always (white page, dark text) whatever the app's theme; folded sections printed open.
  Done 2026-10-21: blocks are drawn in light appearance with Graphite's theme; headings are not folded and callouts are printed open. Tests: `NotePDFRendererTests` (dark appearance on the Mac), hosted `testThePDFIsLightWhenTheAppIsDark` (dark windows and traits).

## 3. Options

- [x] The options sheet Obsidian has: include file name as title, page size (A4, Letter, A5, A3, Legal, Tabloid; A4 the default), portrait or landscape, margins (default, small, none), downscale percent. The last choice is remembered per device.
  Done 2026-10-21: `NotePDFExportSheet` with `NotePDFOptions` (Core) and `NotePDFExportDefaults` (key `GraphiteNotePDFOptions`, JSON; invariant ST-29); downscale goes from 50 to 100 percent in steps of 5; Include Properties as well. Tests: `NotePDFOptionsTests` (geometry, golden JSON, missing keys), hosted sheet test (landscape exported and remembered).
- [x] A preview of the first pages in the sheet, so the person sees the result before saving.
  Done 2026-10-21: the first two pages, drawn again when an option changes. Test: hosted sheet test (two pages, portrait then landscape; its screenshot of the sheet was looked at).

## 4. Where to find it

- [ ] iPad and iPhone: More › Export to PDF… on a note, and the share sheet's Print, which uses the same renderer (`UIPrintPageRenderer`).
  In part 2026-10-21: More › Export to PDF… and More › Print… (`NotePDFExportButton`). One presentation per window (`NotePDFExportPresentation`) makes the PDF: Export shows the options sheet and hands the PDF to the file exporter; Print makes it with the last options, shows its progress with Stop, then the system's print panel (`NotePDFPrinting`: `UIPrintInteractionController` with the PDF, so the same renderer prints). Tests: `NotePDFExportTests` (printing uses and keeps the remembered options, Stop ends it), hosted `NotePDFExportHostedTests`. Not tapped by hand yet (the simulator tool had no access); the print panel itself has no automated test.
- [ ] Mac: File › Export as PDF… (⌘⇧E, free today) and File › Print… (⌘P), through `NSPrintOperation` with the same renderer.
  In part 2026-10-21: File › Export as PDF… and File › Print… ⌘P (the owner asked for ⌘P to print on the Mac; the command palette moves to ⇧⌘P there, the iPad keeps ⌘P for it). Print hands the PDF to `NSPrintOperation` (`PDFDocument.printOperation`, paper the PDF's page size, nothing scaled), whose panel also saves a PDF. Export as PDF… has no shortcut yet. The Mac app builds; not yet tried by hand on the Mac. The two are the commands `workspace:export-pdf` (Obsidian's identifier) and `graphite:print-file` of Settings › Keyboard Shortcuts, so a vault can give Export as PDF… a shortcut or move Print; `GraphiteCommandTests` checks ⌘P is Print on the Mac and the palette on the iPad.
- [x] The command palette's "Export to PDF" command, and an "Export to PDF…" item in the file list's context menu for a note.
  Done 2026-10-21: the palette lists Export to PDF and Print current file while a note is in front (`NotePDFPaletteCommands`); the file list's menu of a note has Export to PDF…, which prints that note from its file (or as it is now when it is the note in front; a note read from its file prints without its vault's declared property types). Built for the iPad and the Mac; not tapped by hand.

## 5. Verification

- [x] Unit and hosted tests: page breaks never split a line; a heading is never last on a page; a page count and text for a sample note with math, callouts, tables, code and a picture; light colours in dark mode; the note's file is unchanged.
  Done 2026-10-21: `NotePageFlowTests`, `MarkdownSectionUnitsTests`, `PrintedLineGapsTests`, `NotePDFOptionsTests`, `NotePDFRendererTests` (the note's bytes and date unchanged, nothing written into the vault), hosted `NotePDFExportHostedTests`; all pass, with 712 package tests of the reading view, Markdown and preferences and 23 hosted reading, Live Preview and code tests run again.
- [ ] A demo vault of a couple of course notes (no personal notes) exported on the iPad simulator and the Mac; the PDFs open in Preview, Files and Acrobat with selectable text and working web links.
  In part 2026-10-21: a demo vault (two course notes of the test vault, `9_Static logic` and `Lecture_L01_Shannon`, and a sampler note with every kind of block) was exported in the iPad simulator's app process and its PDFs read back with PDFKit and looked at page by page. Not yet: through the app's own menu, on the Mac, in Files and Acrobat.
- [ ] On the owner's iPad: a long lecture note exported and shared, checked page by page.
- [x] `Architecture.md`, `Coverage.md`, `Obsidian-mobile-gaps.md` and `Docs/solid/invariants.md` updated once built and tested; `python3 scripts/size-report.py` passes.
  Done 2026-10-21 for what is built: Architecture (Markdown views), Coverage ("Export a note to PDF"), Obsidian-mobile-gaps (Media, PDFs and files), invariants ST-29, PDF-14 and PDF-15; `size-report.py` and `check-rules.py` pass for these changes. To update again as sections 2, 4 and 5 finish.
