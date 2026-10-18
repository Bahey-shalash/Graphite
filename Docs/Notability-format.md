# The Notability file format (`.note`)

Status: Phase 1 of [the import checklist](Goodnotes-Notability-import-todo.md). Recovered on 2026-10-18 from one of the owner's notes, by reading the file only; no part of Notability was run, decompiled or copied. Nothing here is implemented in Graphite yet.

What was checked: a reference reader written for this (`scripts/notability-reader.py`) decoded the note's 3,036 curves, 52 shapes and 6 pictures. All 71,886 points and 25,986 per-knot values were accounted for. The first page drawn from what it read matched the note's own thumbnail by eye: ink position, colour and varying width, straight-line shapes, and the black paper. Later pages were checked only for plausibility, since the note carries no picture of them. No Notability PDF export was available, so there are no pixel-difference tests yet.

## The sample

One note, four letter-size pages of continuous writing on black paper, made with Notability 14.3 (`NBNoteTakingSessionBundleVersionNumberKey`), session format 9. It has pen and highlighter ink in 15 colours, varying width, recognised straight lines, one dashed line and six pictures. **Not in the sample, so not documented here:** typed text, imported PDFs, recordings and their timing, paper with lines or a grid, other shapes (rectangles, ellipses), turned or cropped pictures, pages set up as separate pages instead of a continuous scroll, and other format versions. Each needs a note made for it (Phase 1).

## Container

A ZIP archive (stored, not compressed) with one top-level folder named after the note:

```
<name>/Session.plist                    the note: ink, pictures, text, paper (keyed archive)
<name>/metadata.plist                   name, subject, dates, tags, UUID (keyed archive, class SessionInfo)
<name>/HandwritingIndex/index.plist     recognised text per page: text, character boxes, a hash per page (version 7)
<name>/Recordings/library.plist         recordings (XML property list; empty in the sample)
<name>/Images/                          one file per picture, PNG or JPEG
<name>/PDFs/  <name>/Assets/            empty in the sample
<name>/thumb.png … thumb12x.png         the first page at several sizes
```

## Encoding

`Session.plist` and `metadata.plist` are binary property lists in Apple's keyed-archive layout (`$archiver`, `$objects`, `$top`), with objects referred to by UID. `metadata.plist` names the archiver `NSKeyedArchiver`; `Session.plist` names it `GLKeyedArchiver`, with the same layout. Strings are `NSString`, or `NSMutableString` with its UTF-8 bytes under `NS.bytes`. Points, sizes and rectangles are strings such as `{-13.6, 1815.0}` and `{{0, 0}, {520, 304}}`. Dates are seconds since 2001-01-01. The archive's root is `$top.$0`, a `NoteTakingSession`.

**Coordinates.** One continuous document, origin at the top left of the first page, y downwards. The width is fixed by the paper: `paperSizingBehavior` `lockedWidth:583.8:iPad` makes a letter page 583.8 units wide, so one unit is 612 / 583.8 PDF points. Pages follow one another at the paper's height for that width (755.5 units for letter portrait). The handwriting index has pages `0`, `1` and `2`, so pages exist in the data, not only on screen. The sample's ink reaches y = 2,296, within page 4.

## The session (`NoteTakingSession`)

| Key | Meaning |
|---|---|
| `name`, `packagePath`, `subject`, `tags`, `creationDate` | The note's name, folder, subject (`unsortedNotesKey`), tags and creation date |
| `sessionFormatVersion` | 9 |
| `NBNoteTakingSessionDocumentPaperLayoutModelKey` | Paper: `documentPaperAttributes` (below) and `pageLayoutArray` (empty) |
| `NBNoteTakingSessionIsHighlighterBehindTextKey` | True; by its name, highlighter ink is drawn behind text (not checked: the sample has no typed text) |
| `NBNoteTakingSessionHandwritingLanguageKey` | `fr_FR` |
| `contentPlaybackEventManager` | Stroke-to-recording timing (`NBCPEventManager`): event UUIDs, timestamps, recording ids and durations as packed arrays, all empty in the sample |
| `richText` | Everything on the pages (`FormattedString`, below) |

**Paper** (`GLModel.PaperAttributes`): `paperIdentifier` `Legacy:15` (black, no lines, in the sample), `paperSize` `letter`, `paperOrientation` `portrait`, `paperSizingBehavior`, `lineStyle2` `No Lines`, `alignsTextToLines`, `drawRotatedForOrientation`. Notability draws the paper itself from these; the note contains no picture or PDF of it.

## Page content (`richText`, a `FormattedString`)

| Key | Meaning |
|---|---|
| `attributedString`, `NBAttributedBackingString` | Typed text (empty in the sample) |
| `Handwriting Overlay` | The ink: a `HandwritingObject` whose `SpatialHash` holds every curve |
| `mediaObjects` | Pictures |
| `pdfFiles` | Imported PDFs (empty in the sample) |
| `reflowState` | `NBReflowStateLocked`, `pageWidthInDocumentCoordsKey` 583.8 |
| `recordingTimestampString` | Empty |

### Ink (`InkedSpatialHash`)

The curves are parallel arrays of packed little-endian values, one entry per curve or per knot. Curves are stored in the order they were written: consecutive curves are on average 21 units apart, against 832 in a random order.

| Key | Per | Type | Meaning |
|---|---|---|---|
| `numcurves` | | integer | Number of curves (3,036) |
| `numpoints` | | integer | Total points (71,886) |
| `numfractionalwidths` | | integer | Total knots (25,986) |
| `curvesnumpoints` | curve | uint32 | Points in the curve, always 3k + 1 |
| `curvespoints` | point | 2 × float32 | x, y |
| `curveswidth` | curve | float32 | Width |
| `curvescolors` | curve | 4 × uint8 | Red, green, blue, alpha (the highlighter's transparency is here) |
| `curvesstyles` | curve | uint8 | 3 for pen (3,021 curves, width up to 2.28); 4 for highlighter (15 curves, width 4.6 to 5.7, colour alpha 107/255) |
| `curveUUIDs` | curve | 16 bytes | Curve UUID |
| `options` | curve | 8 bytes | All zero in the sample |
| `curvesfractionalwidths` | knot | float32 | Width factor at the knot, 0.53 to 1.58 |
| `curvesforces` | knot | float32 | Pencil force; 1.0 throughout the sample |
| `curvesaltitudeangles` | knot | float32 | Pencil altitude; π/2 throughout the sample |
| `curvesazimuthunitvector` | knot | 2 × float32 | Pencil azimuth |
| `groupsArrays` | | array | Empty |
| `bezierPathsDataDictionary` | | dictionary | Empty |
| `shapes` | | binary plist | Recognised shapes (below) |

A curve's points are a chain of cubic Bézier segments: knot, control, control, knot, and so on, so a curve of 3k + 1 points has k segments and k + 1 knots. The knots of all curves, in order, index the four per-knot arrays. The stroke is drawn along the chain with width `curveswidth × curvesfractionalwidths`, interpolated between knots, with round ends.

### Shapes (`shapes`)

An embedded binary property list: `{shapes, kinds, indices}`, three arrays of the same length. `kinds` is `line` for all 52 shapes in the sample. Each shape has `startPt`, `endPt`, `rect`, `uuid`, `options` (0) and `appearance` `{style, strokeColor: {rgba}, strokeWidth, dashStyle: {pattern}}`. A shape is not one of the curves. `indices` gives its place in the drawing order: shape with index n is drawn just before curve n. Without the shapes the first page lost its underlines, fraction bars and the arrows of a field diagram that its thumbnail shows.

### Pictures (`ImageMediaObject`)

| Key | Meaning |
|---|---|
| `documentOrigin` | Top-left corner, in document coordinates |
| `unscaledContentSize` | Size on the page |
| `rotationDegrees` | 0 in the sample (some values are about 1e-14) |
| `zIndex` | Order among the pictures, 0 to 5 |
| `figure.FigureCropRectKey` | Crop in the image's pixels; the whole image in the sample |
| `figure.FigureBackgroundObjectKey.kImageObjectSnapshotKey.relativePath` | The file, such as `Images/Image 1.png` |
| `assetsIdKey`, `UUID` | Identifiers |
| `isCaptionEnabled`, `captionFieldText`, `captionFont…` | Caption, off in the sample |
| `textWrapMode`, `cornerMode`, `minDimension`, `maxDimension` | Layout options |

The picture file is the original image. In this check pictures were drawn under all ink, by `zIndex`; the sample has no picture overlapping ink, so the relative order of pictures and ink is not confirmed.

## What this means for the import

- Pages: the continuous document is cut at the paper's height into pages of the paper's size, converted to PDF points.
- Paper: drawn by Graphite's paper system from `paperIdentifier`, `paperSize`, `paperOrientation` and `lineStyle2`. This needs a table from Notability's paper identifiers to colours and rulings, built from samples with each paper.
- Ink: one PencilKit stroke per curve, its points sampled along the Bézier chain, with width from the per-knot factors and force, azimuth and altitude when they vary. PencilKit strokes take a size per point, so the varying width can be kept.
- Shapes: straight lines as strokes until Graphite has editable shapes; dashed lines need dashed ink, which Graphite lacks.
- Pictures: separate pictures from the original files, with their position, size, crop and rotation.
- Recordings and their timing: not in the sample.

## Other readers

- Julia Evans, [Reverse engineering the Notability file format](https://jvns.ca/blog/2018/03/31/reverse-engineering-notability-format/) (2018): the ZIP and binary plist layout, written for an older version; her [svg2notability](https://github.com/jvns/svg2notability) writes notes and shows no licence.
- [jakubfabrici/notability-goodnotes](https://github.com/jakubfabrici/notability-goodnotes) (MIT) says it reads Notability 4 to 16, with text boxes, and drops audio. Not checked.
