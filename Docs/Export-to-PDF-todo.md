# Export a note to PDF: TODO

Created: 2026-10-21.

Priority: highest. The owner called it "extremely important" on 2026-10-21.

Status: not started. Graphite can export PDF pages (`PDFPane` › Export Pages…) and drawings (`DrawingEditor` › Export a Copy), but nothing turns a Markdown note into a PDF. The reading view (`MarkdownPreview`, `ReadingBlocksView` on the vendored Textual renderer) is drawn in a `LazyVStack` inside a `ScrollView`, so it cannot be printed or rendered whole as it is.

## Request

Export a Markdown note to a PDF, as Obsidian's "Export to PDF" does: the note as the reading view shows it, laid out on pages, saved where the person picks or shared. Notes are mostly lecture notes, so math, callouts, tables, code, embedded pictures, drawings and diagrams must come out right.

## Decisions

- The PDF is a copy written where the person chooses (file exporter or share sheet). Graphite writes nothing into the vault unless the person saves it there; the note itself is never changed.
- It renders the reading view's blocks, not HTML: no web view and no second Markdown renderer, so the PDF looks like Graphite and the core stays small.
- Text stays vector and selectable in the PDF; pictures keep their resolution.

## 1. Export a note

- [ ] A renderer in GraphiteUI that lays the note's reading-view blocks out at the page's text width, without the scroll view, and draws them into a PDF context page by page (`ImageRenderer` into a `CGContext` PDF, or `UIGraphicsPDFRenderer`, whichever keeps text as text).
- [ ] Page breaks between blocks; a block taller than a page (a long table, code block or picture) is split at a line or row, or scaled to fit for a picture, never cut through a line of text. Headings are kept with the block that follows them.
- [ ] Runs off the main actor where it can and shows progress for long notes; cancelling leaves nothing behind.
- [ ] The PDF's title is the note's name, its author left empty, and its outline (bookmarks) follows the note's headings.

## 2. What the PDF shows

- [ ] Everything the reading view draws: headings, lists, tasks, quotes, callouts (collapsed callouts printed open), tables, code with its highlighting, math (inline and display), footnotes, horizontal rules, highlights, tags.
- [ ] Embeds: pictures, drawings (SVG and PNG), diagrams, embedded notes and note sections, a page of an embedded PDF; a video or audio embed is printed as its file name.
- [ ] Links: internal links are printed as their text; web links stay clickable in the PDF.
- [ ] Frontmatter properties are left out by default (as in Obsidian), with an option to include them.
- [ ] Light colours always (white page, dark text) whatever the app's theme; folded sections printed open.

## 3. Options

- [ ] The options sheet Obsidian has: include file name as title, page size (A4, Letter, A5, A3, Legal, Tabloid; A4 the default), portrait or landscape, margins (default, small, none), downscale percent. The last choice is remembered per device.
- [ ] A preview of the first pages in the sheet, so the person sees the result before saving.

## 4. Where to find it

- [ ] iPad and iPhone: More › Export to PDF… on a note, and the share sheet's Print, which uses the same renderer (`UIPrintPageRenderer`).
- [ ] Mac: File › Export as PDF… (⌘⇧E, free today) and File › Print… (⌘P), through `NSPrintOperation` with the same renderer.
- [ ] The command palette's "Export to PDF" command, and an "Export to PDF…" item in the file list's context menu for a note.

## 5. Verification

- [ ] Unit and hosted tests: page breaks never split a line; a heading is never last on a page; a page count and text for a sample note with math, callouts, tables, code and a picture; light colours in dark mode; the note's file is unchanged.
- [ ] A demo vault of a couple of course notes (no personal notes) exported on the iPad simulator and the Mac; the PDFs open in Preview, Files and Acrobat with selectable text and working web links.
- [ ] On the owner's iPad: a long lecture note exported and shared, checked page by page.
- [ ] `Architecture.md`, `Coverage.md`, `Obsidian-mobile-gaps.md` and `Docs/solid/invariants.md` updated once built and tested; `python3 scripts/size-report.py` passes.
