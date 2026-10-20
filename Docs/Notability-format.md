# The Notability file format (`.note`)

Status: Phase 1 of [the import checklist](Goodnotes-Notability-import-todo.md). Recovered on 2026-10-18 and 2026-10-19 from ten of the owner's notes and Notability's own PDF export of each, by reading the files only; Notability's code was not inspected, decompiled or copied. Phase 2 added a Swift reader in GraphiteCore (`NotabilityNoteReader`, see Swift reader below); nothing converts a note into Graphite's files yet (Phase 3).

What was checked: a reference reader written for this (`scripts/notability-reader.py`) reads all ten notes with nothing unknown, and accounts for every point, per-knot value, shape, picture, text run, PDF page and timed curve. Pages drawn from what it read were compared with each note's PDF export, rendered at 100 pixels per inch (see "Comparison with Notability's PDF export" below). They line up with no offset; the differences are the antialiased edges of strokes and, for typed text, the substitute font.

## The samples

| Note | Notability | Paper | Content |
|---|---|---|---|
| First sample | 14.3, iPad | Black, no lines, letter, 583.8 units wide | 3 pages of handwriting: 3,036 curves (15 highlighter), 52 straight lines, 6 pictures |
| Typed text | 16.13, Mac | White, no lines, letter, reflowable | Two lines of typed text in two styles |
| Ruled paper | 16.13, Mac | White ruled, letter, 572 units wide | One pen curve |
| Grid paper | 16.13, Mac | White grid, letter | One pen curve |
| Shapes | 16.13, Mac | White, letter | Two shapes made by holding a stroke still (both curved lines) |
| Pictures | 16.13, Mac | White, letter | One curve, three pictures: one over the curve, one turned, one cropped |
| Imported PDF | 16.13, Mac | One imported A4 PDF page | One pen curve across the PDF's content |
| Recording | 16.13, Mac | White, letter | Two curves written during a 19-second recording |
| Separate pages | 16.13, Mac | White, letter | One curve on each of two pages, view set to single pages |

All are session format 9. The 16.13 notes were made on a Mac with a mouse (no pressure, tilt or azimuth). **Not in the samples, so not documented here:** pressure-sensitive ink from the Apple Pencil, rectangles, ellipses and other recognised shapes, coloured papers and paper identifiers other than `Legacy:13` and `Legacy:15`, paper sizes other than letter and the A4 of an imported PDF, landscape pages, flipped pictures, picture captions, typed text with underline, strike-through, lists or checklists, several imported PDFs or PDF pages, several recordings, and other format versions. Each needs a note made for it (Phase 1).

## Container

A ZIP archive (stored, not compressed) with one top-level folder named after the note:

```
<name>/Session.plist                    the note: ink, pictures, text, paper, PDF pages, stroke timing (keyed archive)
<name>/metadata.plist                   name, subject, dates, tags, UUID (keyed archive, class SessionInfo)
<name>/HandwritingIndex/index.plist     recognised text per page: text, character boxes, a hash per page (version 7)
<name>/Recordings/library.plist         the recordings (XML property list)
<name>/Recordings/Recording 1.m4a       a recording: AAC, 22,050 Hz, mono in the sample
<name>/Images/                          one file per picture, PNG or JPEG
<name>/PDFs/<UUID>.pdf                  an imported PDF, byte for byte the file that was imported
<name>/NBPDFIndex/                      search data for imported PDFs (PDFIndex.zip with text, layout and image indexes, and NoteDocumentPDFMetadataIndex.plist): derived, not needed
<name>/Assets/                          empty in every sample
<name>/thumb.png … thumb12x.png         the first page at several sizes (16.13 writes only thumb12x.png)
```

## Encoding

`Session.plist` and `metadata.plist` are binary property lists in Apple's keyed-archive layout (`$archiver`, `$objects`, `$top`), with objects referred to by UID. `metadata.plist` names the archiver `NSKeyedArchiver`; `Session.plist` names it `GLKeyedArchiver`, with the same layout. Strings are `NSString`, or `NSMutableString` with its UTF-8 bytes under `NS.bytes`. Points, sizes and rectangles are strings such as `{-13.6, 1815.0}` and `{{0, 0}, {520, 304}}`. Dates are seconds since 2001-01-01. The archive's root is `$top.$0`, a `NoteTakingSession`.

## Coordinates and pages

One continuous document in its own units, origin at the top left of the first page's content, y downwards. The export of every sample maps it to PDF points the same way, with `s` = export page width / page width in units:

- x in points = 15.9375 + x × s: the document's x = 0 sits 15.9375 points in from the page's left edge, so a page shows x from −15.9375 / s (the first sample has pictures at x = −14.8);
- y in points, from the top of page n = y × s − (n − 1) × export page height.

| Paper | Page width in units | Export page in points | s (points per unit) | Page height in units |
|---|---|---|---|---|
| Letter, made on an iPad | 583.8 | 612 × 803.25 | 1.04830 | 766.24 |
| Letter, made on a Mac | 572 | 612 × 803.25 | 1.06993 | 750.75 |
| A4, imported PDF | 593.33 | 595.2756 × 842.7541 | 1.00328 | 840.00 |

The page width is `richText.reflowState.pageWidthInDocumentCoordsKey` when the layout is locked (`NBReflowStateLocked`, which also names the device: `iPad`, `Mac`, or `A4` for the imported PDF), and the number in the paper's `paperSizingBehavior` (`lockedWidth:572.0:Mac`). It depends on the device the note was made on. The note with only typed text was `NBReflowStateReflowable`, with `paperSizingBehavior` `deviceBasedWidth`, and stores no width: its text reflows to the device that opens it, and its export used the Mac's 572.

Notability's letter page is "Letter (Optimized)", 612 × 803.25 points (16:21), not 612 × 792. Pages follow one another at that height: the first sample's ink reaches y = 2,296, so it has three pages of 766.24 units, as its export does. (This document said four pages of 755.5 units before the exports showed the real height.) The A4 export page is 0.86 points taller than the imported A4 PDF page, which is drawn at its bottom; where 840 units comes from is not known, the value is read from the export.

Choosing single pages instead of continuous scrolling changed nothing in the note apart from its name: it is a view setting, not stored in the file.

## The session (`NoteTakingSession`)

| Key | Meaning |
|---|---|
| `name`, `packagePath`, `subject`, `tags`, `creationDate` | The note's name, folder, subject (`unsortedNotesKey`), tags and creation date |
| `sessionFormatVersion` | 9 in both 14.3 and 16.13 |
| `NBNoteTakingSessionBundleVersionNumberKey` | The app version that saved it: `14.3`, `16.13` |
| `NBPaperMajorVersionNumber`, `NBPaperMinorVersionNumber` | 2 and 1 in 14.3, 3 and 0 in 16.13 |
| `NBNoteTakingSessionDocumentPaperLayoutModelKey` | Paper: `documentPaperAttributes` (below) and `pageLayoutArray` (the imported PDF's pages) |
| `NBNoteTakingSessionIsHighlighterBehindTextKey` | True; by its name, highlighter ink is drawn behind text (not checked) |
| `NBNoteTakingSessionHandwritingLanguageKey` | `fr_FR`, `en_US` |
| `contentPlaybackEventManager` | Stroke timing for recordings (below) |
| `richText` | Everything on the pages (`FormattedString`, below) |
| `kNBNoteTakingSessionNoteLinkStoreKey` | Empty; only in the 14.3 note |

**Paper** (`GLModel.PaperAttributes`): `paperIdentifier`, `paperSize` (`letter`, `a4`), `paperOrientation` (`portrait`), `paperSizingBehavior` (`lockedWidth:<width>:<device>`, `deviceBasedWidth`, or `staticWidth` for the imported PDF), `lineStyle2`, `alignsTextToLines`, `drawRotatedForOrientation`. Notability draws the paper from these; the note contains no picture or PDF of it. What the exports show:

| `paperIdentifier` | `lineStyle2` | Export |
|---|---|---|
| `Legacy:13` | `No Lines` | White (254 of 255 once rendered: the export draws the paper as a tiled 512 × 512 image) |
| `Legacy:15` | `No Lines` | Black |
| `Legacy:13` | `Lines:false:false:0.5` | White with horizontal rules every page width / 17 units (33.647 for 572), the first one rule down from the top, from x = 0 to page width − 2 × 15.9375 / s; colour #A3B7D3, 0.5 points wide |
| `Legacy:13` | `Grid:false:true:0.5` | White with the same horizontal rules from x = 0 to the page's right edge, and vertical rules the page's full height at the same spacing, one of them at the middle of the document's width (x = page width / 2 units: 321.94 points on letter paper); #A3B7D3, 0.4 points wide |

The two booleans and the 0.5 in `lineStyle2` are not understood (the grid is drawn 0.4 points wide). Whether the spacing is always page width / 17 is known only for these two notes.

## Page content (`richText`, a `FormattedString`)

| Key | Meaning |
|---|---|
| `attributedString` | Typed text (below); `NBAttributedBackingString` holds the same text and runs twice (backing and layout) |
| `Handwriting Overlay` | The ink: a `HandwritingObject` whose `SpatialHash` holds every curve |
| `mediaObjects` | Pictures |
| `pageLayoutArray`, `pdfFiles` | Imported PDF pages (below) |
| `reflowState` | `NBReflowStateLocked` with the page width, or `NBReflowStateReflowable` |
| `recordingTimestampString` | The typed text again with one run and no attributes; empty when there is no text |

### Typed text

`attributedString` is `{stringKey, subRangesKey}`: the whole text and its runs. A run's `subRangeRangeKey` is `{location, length}` (an `NSRange`, counted in UTF-16 units; the sample is all ASCII). Each run has `subRangeFontKey` (`NSFontNameAttribute`, and `NSFontSizeAttribute` in document units), the colour as `subRangeColorCrossPlatformKey` (`"r,g,b,a"`, 0 to 1) and as a `UIColor`, and `subRangeOtherAttributesKey` (`NSUnderline`, `NSStrikethrough`, `NSBaselineOffset`, `line-spacing`, `checklist-checked`). Bold is a font name (`HelveticaNeue-Bold`), not an attribute. In the sample: `HelveticaNeue` 12 black, then `HelveticaNeue-Bold` 20 in #ED3624; the text ends with nine empty lines.

The text has no position or box: it is the note's body, laid out by the text system from the document's top left, x = 0 and the first line's top at y = 0. In the export the first baseline is at the font's ascent (11.424 units for Helvetica Neue 12, 0.952 em), and each line advances by its font's line height. Typed text and ink are positioned independently.

### Ink (`InkedSpatialHash`)

The curves are parallel arrays of packed little-endian values, one entry per curve or per knot. Curves are stored in the order they were written: in the first sample consecutive curves are on average 21 units apart, against 832 in a random order.

| Key | Per | Type | Meaning |
|---|---|---|---|
| `numcurves` | | integer | Number of curves |
| `numpoints` | | integer | Total points |
| `numfractionalwidths` | | integer | Total knots |
| `curvesnumpoints` | curve | uint32 | Points in the curve, always 3k + 1 |
| `curvespoints` | point | 2 × float32 | x, y |
| `curveswidth` | curve | float32 | Width: up to 2.28 for the first sample's pen, 2.979 or 3.09 for the Mac samples |
| `curvescolors` | curve | 4 × uint8 | Red, green, blue, alpha (the highlighter's transparency is here: 107/255) |
| `curvesstyles` | curve | uint8 | 3 for pen, 4 for highlighter (15 curves in the first sample, width 4.6 to 5.7) |
| `curveUUIDs` | curve | 16 bytes | Curve UUID; recordings refer to curves by it |
| `options` | curve | 8 bytes | All zero in the samples |
| `curvesfractionalwidths` | knot | float32 | Width factor at the knot, 0.37 to 1.58 in the samples |
| `curvesforces` | knot | float32 | Pencil force; 1.0 throughout the samples |
| `curvesaltitudeangles` | knot | float32 | Pencil altitude; π/2 throughout the samples |
| `curvesazimuthunitvector` | knot | 2 × float32 | Pencil azimuth |
| `groupsArrays` | | array | Empty |
| `bezierPathsDataDictionary` | | dictionary | Empty |
| `shapes` | | binary plist | Recognised shapes (below) |

A curve's points are a chain of cubic Bézier segments: knot, control, control, knot, and so on, so a curve of 3k + 1 points has k segments and k + 1 knots. The knots of all curves, in order, index the four per-knot arrays. The stroke is drawn along the chain with width `curveswidth × curvesfractionalwidths`, interpolated between knots, with round ends. Notability's export draws each curve as a filled outline.

### Shapes (`shapes`)

An embedded binary property list: `{shapes, kinds, indices}`, three arrays of the same length. `kinds` is `line` for every shape in the samples. Each shape has `startPt`, `endPt`, `rect` (its bounding box, grown by half the stroke width), `uuid`, `options` (0) and `appearance` `{style, strokeColor: {rgba}, strokeWidth, dashStyle: {pattern}}`. A `line` may also have `controlPoint1`: it is then a quadratic Bézier from `startPt` through that control point to `endPt`. Both shapes of the shapes sample are such curves (the thin "angles" Notability made from mouse strokes), and each curve's extremes match its `rect`. A shape is not one of the curves: `indices` gives its place in the drawing order, the shape with index n being drawn just before curve n.

### Pictures (`ImageMediaObject`)

| Key | Meaning |
|---|---|
| `documentOrigin` | Top-left corner of the unturned picture, in document units |
| `unscaledContentSize` | Size on the page of the shown (cropped) part |
| `rotationDegrees` | Despite its name, an angle in radians, clockwise on the page, about the picture's centre: 0.443 is the 25.4° the export shows |
| `figure.FigureCropRectKey` | The part shown, in the image's pixels from its top left: `{{0, 0}, {226.7, 174.7}}` keeps the top-left part of a 400 × 300 image |
| `figure.FigureBackgroundObjectKey.kImageObjectSnapshotKey.relativePath` | The file, such as `Images/Image 1.jpg`; `saveAsJPEG` tells whether Notability stored it as JPEG (a pasted PNG became a JPEG) |
| `zIndex` | Order among the pictures, from 0 |
| `isFlippedHorizontal`, `isFlippedVertical`, `locked` | False in the samples; absent from the 14.3 note |
| `handwritingZIndecesKey` | Empty in the samples |
| `assetsIdKey`, `UUID` | Identifiers |
| `isCaptionEnabled`, `captionFieldText`, `captionFont…` | Caption, off in the samples |
| `textWrapMode`, `cornerMode`, `minDimension`, `maxDimension` | Layout options |

The scale is `unscaledContentSize` / crop size (0.5 units per image pixel in the sample): the export draws the whole image at that scale with its top left at `documentOrigin`, and clips it to the crop. **Pictures are drawn under all ink**, whatever order they were made in: the first picture of the pictures sample was pasted after its curve and covers part of it, and the export draws the curve over it.

### Imported PDF pages

`richText.pageLayoutArray` has one entry per document page made from a PDF: `kPageLayoutDocumentPageNumberKey` (1), `kPageLayoutPDFFileNameKey` (`<UUID>.pdf`, under `PDFs/`), `kPageLayoutPDFPageNumberKey` (1), `kPageLayoutPDFIsOriginalPageKey`, `kPageLayoutPageIsBookmarkedKey`, and `kPageLayoutPDFFileKey` (a `PDFFile`: `pdfFileName`, `highlights`, `type`, `version`, `contentBoxVersion`). The paper layout model's `pageLayoutArray` repeats it without the `PDFFile`. `pdfFiles` lists the files. The PDF in `PDFs/` is the imported file unchanged (same MD5). The note's paper is then `a4` with `staticWidth`, 593.33 units wide; the export draws the original vector page at its own size (scale 0.9999926, x −0.336 points) and the ink over it with the same mapping as other notes.

## Recordings and stroke timing

`Recordings/library.plist` is an XML property list: `application version` (`7176`), `library-format-version` (`1.0`) and `recordings`, keyed by identifier, each with `filepath` (`Recording 1.m4a`), `duration` (18.9 seconds; the file itself lasts 19.04), `filesize`, `filetype` (`m4a`), `createddate`, `name`, `userFacingName` and an `assethash`.

`contentPlaybackEventManager` (`NBCPEventManager`) times curves against recordings, as parallel packed arrays of `NBCPTimeManagerSOANumEventsKey` entries:

| Key | Type | Meaning |
|---|---|---|
| `NBCPTimeManagerSOAEventUUIDsKey` | 16 bytes | The curve's UUID (from `curveUUIDs`) |
| `NBCPTimeManagerSOATimestampsKey` | float32 | When the curve was written, in seconds from the recording's start |
| `NBCPTimeManagerSOARecordingIDsKey` | uint32 | The recording's identifier in `library.plist` |
| `NBCPTimeManagerSOADurationsKey` | float32 | How long the curve took to write, in seconds |

In the sample: the zigzag at 10.8 s for 0.5 s and the line at 15.4 s for 0.3 s, both in recording 1, 4.6 seconds apart (the person writing noted "about 4 seconds later").

## Swift reader

`NotabilityNoteReader` (GraphiteCore, `Sources/GraphiteCore/NotebookImport/`) reads what `scripts/notability-reader.py` reads, into plain values for the conversion of Phase 3. It takes the note's bytes (memory-mapped by the caller), reads `Session.plist` with its own bounded `bplist00` reader (`BinaryPropertyList`) and resolves the keyed archive lazily, one reference at a time (`KeyedArchive`): `PropertyListSerialization` returns an archive's UIDs as opaque `CFKeyedArchiverUID` objects whose number is reachable only through private API, so it reads only the XML `Recordings/library.plist` here. Following references carries a visiting set and a depth limit, and the reader only follows the format's own key paths, so a cyclic object graph cannot make it loop. The packed curve arrays stay as slices of the session's bytes: opening builds a small per-curve index (offsets and lowest and highest y), and `curve(at:)` and `page(number:)` decode only the curves asked for.

Unknown keys, classes, styles, kinds and versions are reported as `NotabilityReadingIssue` cases, one per kind of "unknown" the reference reader prints. Where the reference reader stops with an error, the Swift reader skips only the picture or shape it cannot read and lists it. It also reads the per-knot altitude angles and azimuth vectors, which the reference reader does not, and reports them as an issue when their length does not match the knots. A page lists every curve whose lowest and highest points span it, where the reference reader lists only curves with a point on the page; on the first sample both give the same pages (1,295, 827 and 914 curves).

Its counts equal the reference reader's on all nine notes of the `samples/import-formats` branch, with no unknown category on either side (`NotabilityNoteReaderSampleTests` against `scripts/import-reference-counts.py`, 2026-10-19). "Pages" is the reference reader's "pages reached by content"; the typed-text note is reflowable and stores no page width, so neither reader computes its pages.

| Note | Curves | Points | Highlighter | Shapes | Pictures | Text runs | Text (UTF-16) | PDF pages | Recordings | Timed curves | Pages |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| First sample | 3,036 | 71,886 | 15 | 52 | 6 | 0 | 0 | 0 | 0 | 0 | 3 |
| Grid paper | 1 | 40 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| Imported PDF | 1 | 37 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 |
| Recording | 2 | 35 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 2 | 1 |
| Pictures | 1 | 37 | 0 | 0 | 3 | 0 | 0 | 0 | 0 | 0 | 1 |
| Ruled paper | 1 | 40 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| Separate pages | 2 | 32 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 |
| Shapes | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| Typed text | 0 | 0 | 0 | 0 | 0 | 3 | 40 | 0 | 0 | 0 | none |

## Comparison with Notability's PDF export

Each page of each note was drawn from the reference reader's output (paper, imported PDF page, pictures, curves, shapes; typed text in Liberation Sans in place of Helvetica Neue) at 100 pixels per inch, and compared with the export rendered at the same size. "Content" pixels are those that differ from the paper by at least 64 of 255 in either picture; the table gives the share of them that differ by 64 or more between the two, and the shift (in pixels, up to ±2) that makes that share smallest.

| Note, page | Content pixels | Differing | Best shift |
|---|---|---|---|
| First sample, 1 | 72,836 | 15.6% | 0, 0 |
| First sample, 2 | 68,738 | 11.6% | 0, 0 |
| First sample, 3 | 165,182 | 5.7% | 0, 0 |
| Grid paper | 37,808 | 0.1% | 0, 0 |
| Ruled paper | 18,244 | 0.1% | 0, 0 |
| Pictures | 124,346 | 3.3% | 0, 0 |
| Imported PDF | 57,287 | 10.3% (5.0% shifted) | −1, 0 |
| Recording | 1,844 | 8.0% | 0, 0 |
| Shapes | 5,685 | 10.0% | 0, 0 |
| Separate pages, 1 | 367 | 0.8% | 0, 0 |
| Separate pages, 2 | 511 | 6.7% | −1, 0 |
| Typed text | 3,399 | 51.3% | 1, −1 |

What remains is the edges of thin strokes and lines (one or two pixels wide at this resolution), the PDF page's 0.336-point shift, and for typed text the substitute font. Positions, page breaks, the turned and cropped pictures, the shapes' curves and the order of pictures and ink all match. The ink's total darkness is within 5 to 17% of the export's.

## What this means for the import

- Pages: the continuous document is cut into pages of the export's height in units (table above), each a PDF page of the export's size, with the 15.9375-point inset. A reflowable note's page width is not in the file, so the import has to choose one (572 as the Mac export did, or 583.8 as on an iPad).
- Paper: drawn by Graphite's paper system from `paperIdentifier` and `lineStyle2`, with the rules' spacing, colour and width above. Other papers need samples.
- Imported PDF pages: the original PDF page from `PDFs/`, unchanged.
- Ink: one PencilKit stroke per curve, its points sampled along the Bézier chain, with width from the per-knot factors, and force, azimuth and altitude when they vary. PencilKit strokes take a size per point, so the varying width can be kept.
- Shapes: straight and curved lines as strokes until Graphite has editable shapes; dashed lines need dashed ink, which Graphite lacks.
- Pictures: separate pictures from the stored files (which may be JPEG copies of the originals), with their position, size, crop and rotation, under the ink as in Notability.
- Typed text: needs text boxes on PDF pages in Graphite; the note's body text would become one text box the width of the page at its top, in the stored fonts, sizes and colours.
- Recordings: the `.m4a` beside the PDF, and each curve's time and duration for synchronised replay.

## Other readers

- Julia Evans, [Reverse engineering the Notability file format](https://jvns.ca/blog/2018/03/31/reverse-engineering-notability-format/) (2018): the ZIP and binary plist layout, written for an older version; her [svg2notability](https://github.com/jvns/svg2notability) writes notes and shows no licence.
- [jakubfabrici/notability-goodnotes](https://github.com/jakubfabrici/notability-goodnotes) (MIT) says it reads Notability 4 to 16, with text boxes, and drops audio. Not checked.
