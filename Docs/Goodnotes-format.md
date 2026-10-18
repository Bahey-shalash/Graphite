# The Goodnotes file format (`.goodnotes`)

Status: Phase 1 of [the import checklist](Goodnotes-Notability-import-todo.md). Recovered on 2026-10-18 from four of the owner's notebooks, by reading the files only; no part of Goodnotes was run, decompiled or copied. Nothing here is implemented in Graphite yet.

What was checked: a reference reader written for this (`scripts/goodnotes-reader.py`) decoded every record of the four notebooks, 32,390 stroke records, 14 picture records and 42 fill records (27,768 strokes, 9 pictures and 12 fills not erased), with nothing left over in any stroke payload. Pages drawn from what it read matched each notebook's own thumbnail and, by eye, its content: ink position, colour and width, shapes and fills, pictures, template paper and imported PDF pages. That was a visual comparison only. The Goodnotes PDF exports the checklist asks for, and pixel-difference tests, are still to do.

## The samples

| Sample | Pages | Paper | Content |
|---|---|---|---|
| A | 20 | Black grid template, Goodnotes "Standard" size | 9,724 pen strokes in several colours; lines, dashed lines, ellipses and turned ellipses; 7 fills; 4 pictures; erased and lasso-moved strokes; elements with an order id (field 6) |
| B | 17 | Black grid template, Standard size | 6,738 pen and 7 highlighter strokes; lines, dashed lines, ellipses; 2 fills; 3 pictures, of them 2 stickers (JPEG 2000); erased and lasso-moved strokes |
| C | 3 | Two A3 white template pages, landscape, and one page of an imported 19-page PDF | 11,293 pen and 6 highlighter strokes (6,143 on one page); lines, ellipses, a dashed freehand stroke; 3 fills; 2 pictures; erased and lasso-moved strokes |
| D | 2 | Both pages of an imported A3 PDF | No ink |

Every sample is schema 24. **Not in the samples, so not documented here:** typed text boxes, rotated or cropped pictures, fountain, brush and pencil inks with varying width, tape, links, outlines and bookmarks, audio, sticky notes, and other schema versions. Each needs a sample made for it (Phase 1).

## Container

A ZIP archive (deflate). One notebook:

```
schema.pb                 schema version
document.info.pb          empty in every sample
index.notes.pb            ink layer id -> "notes/<id>"
index.attachments.pb      attachment id -> "attachments/<file id>"
index.search.pb           search record id -> "search/<id>"
index.events.pb           the notebook's event log: document, attachments, paper, pages and their order, page members
notes/<layer id>          one file per page with ink: that page's elements
attachments/<file id>     template PDFs, imported PDFs, pictures (PNG, JPEG, JPEG 2000), with no extension
search/<id>               handwriting recognition results (word candidates, boxes, stroke ids): derived, not needed
thumbnail.jpg             the first page
```

Empty files are normal: a page with no ink has an empty `notes/<id>`.

## Encoding

**Protocol Buffers without a schema.** Every `.pb` file and every `notes/` file is a sequence of protobuf messages, each preceded by its length as a varint. Field numbers below are protobuf field numbers; their names are this document's. Floats are 32-bit (wire type 5) unless marked `double`. A field equal to its default (zero, empty) is left out, as in proto3: a colour with no red component has no field 1.

**`schema.pb`** is one message without a length prefix: `{1: 24}`.

**Versioned registers.** Most editable values are wrapped as a last-writer-wins register, `{1: value, 2: clock}`, where the clock is `{1: counter, 2: replica hash}`. Several records may set the same register; the highest counter wins.

**Derived ids.** A page's ink layer id is the page id with 1 added to its last byte, without carry: `…25FF` becomes `…2500`, not `…2600`. Several record kinds use this.

**Coordinates.** Origin at the top-left corner of the page, y downwards. One unit is 6/11 of a PDF point (132 units per inch, the first iPad's screen density): an A4 page is 1,091.35 × 1,543.46 units, A3 landscape 2,182.68 × 1,543.46, and the Standard size 834.24 × 1,078.82 (455.04 × 588.45 points).

**Stroke payloads** are compressed with Apple's LZ4 framing (Compression framework, `COMPRESSION_LZ4`): blocks of `bv41`, the decoded and encoded sizes as little-endian 32-bit integers, then a raw LZ4 block; `bv4-` for a stored block; `bv4$` ends the stream. The decoded bytes are a [tpl](https://troydhanson.github.io/tpl/) image (Troy Hanson's serialisation library): `tpl`, a flags byte (0: little-endian), the total size as a 32-bit integer, a NUL-terminated format string, then the values. Each `A(…)` array starts with its element count as a 32-bit integer.

## The event log (`index.events.pb`)

Each message is `{1: entity id, <kind>: body}`, with exactly one body field. The kinds seen:

| Kind | Meaning | Body fields used |
|---|---|---|
| 30 | Document created | 1 id; 2 title (register); 9 locale; 10 created (double, milliseconds since 1970); 20 schema. Also 3, 6 (`"P"`), 7 and 19, meaning unknown |
| 31 | Document renamed | 2 title (register) |
| 34 | Document changed | 2 (register, empty in the samples) |
| 6 | Attachment | 1 id; 2 file id (the name under `attachments/`); 5 size in bytes; 6 document; 12 `{1: 1, 2: page count}` for a PDF, absent for a picture |
| 2 | Paper (background) | see below |
| 54 | Page created | 1 document; 2 page id; 3 paper (register of a paper id); 4 position (register of a string) |
| 3 | Page paper changed | 3 paper (register) |
| 57 | Page changed | 3 (register, empty in the samples) |
| 102 | Ink layer created | id = page id + 1 |
| 106 | Ink layer members | 2 repeated: the page's element ids (registers). Not the drawing order: see Drawing order below |
| 10 | Last page viewed | 2 page; 3 `"PagingViewServiceUpdater:<id>"` |
| 103, 104, 105 | Search index bookkeeping | not needed |

**Paper (kind 2).** A page's paper is a separate record, and many pages share one. Fields: 4 attachment (a PDF); 5 page number in that PDF, from 1; 8 page size `{1: width, 2: height}` in units; 9 template id (empty for an imported PDF); 18 ruling `{1: {1: origin, 2: size} (the writing area), 2: line spacing, 3: unknown, 5: unknown}`; 6, 7 (double 29.33), 12 (register, 29.33), 13 (register, 1), 17 (register, 1 or 2) and 19 are not understood.

The paper is drawn by the attachment, never by Goodnotes from the template id. Template paper is a one-page vector PDF made by svg2pdf (the grid, rules and paper colour), and an imported PDF page is the original PDF. Template ids read `<catalogue UUID>_<size>_<orientation>_<design>`: `a4`, `a3` and `standard` sizes, orientation 1 portrait and 2 landscape, and a design that is a number with a colour (`2 - White`) or a UUID.

**Pages and their order.** The notebook's pages are the kind 54 records, sorted by position, comparing the position strings byte by byte (fractional indexing: `4!Wfh` < `AxSGV` < `_-KWPko01`). A page of a 19-page PDF that the notebook does not use has no record: there is nothing to skip. No sample has a page deleted after it was made, so how deletion is recorded is not known yet (other readers report tombstone records).

## Page elements (`notes/<layer id>`)

Each element is two messages: a header, then its body.

**Header:** `{1: element id, 2: clock, 3: 1 if deleted, 4: attachment (pictures), 6: order id, 8: replica, 9: counter, 14: 5381, 16: schema}`. An element is drawn when its header is not deleted; erased strokes stay in the file. The page's member list (kind 106) names each element by its order id (field 6) when it has one and by its element id otherwise; in the samples field 6 is set on all elements of three neighbouring pages and on some of a fourth, which suggests copied or pasted elements (not confirmed). In every sample each live element was in the member list exactly once, and each header had a body.

**Body:** one field, 7 for a stroke, 1 for a picture, 9 for a shape's fill.

**Drawing order.** Each body has a position, `{1: {1: counter, 2: replica}}`: field 7 of a stroke, 5 of a picture, 3 of a fill. Elements are drawn sorted by counter, then replica. Neither the member list nor the order of records in the file is the drawing order. The evidence: in the 37 pages with at least 50 strokes, consecutive strokes sorted by position are on average 47.5 units apart, as handwriting written in sequence is, against 467 in member-list order, 468 in file order and 466 in a random order. The position does not decide everything: 751 of the 27,789 live elements share both counter and replica with another element on their page, and how Goodnotes orders those is not known (the reference reader keeps them in file order). Within a tie the order only shows where the tied elements overlap in different colours.

### Strokes (body field 7)

| Field | Meaning |
|---|---|
| 1 | Element id |
| 2 | The path: LZ4, then tpl, see below |
| 4 | Colour `{1: red, 2: green, 3: blue, 4: alpha}`, 0 to 1 |
| 5 | 1 for the highlighter (alpha 0.5, width 12 to 36 in the samples) |
| 6 | Offset `{1: x, 2: y}` added to every point: a lasso move |
| 9 | Shape, when the stroke was drawn as one (below) |
| 14 | 1 when erased; the path is then empty |
| 15 | Version clock (equals the header's field 2) |
| 7 | Position in the drawing order |
| 20, 21 | Empty, schema |

The tpl format string is `vuA(v)A(S(uu))A(S(uuuu))vA(f)`:

| Value | Meaning |
|---|---|
| `v` | 2 in every sample |
| `u` | The width, a 32-bit float stored in a `u` |
| `A(v)` | One code per path element: 0 starts a subpath, 1 is a curve |
| `A(S(uu))` | One start point (x, y) per subpath |
| `A(S(uuuu))` | One quadratic Bézier per curve: control point, then end point |
| `v` | 1 in every sample |
| `A(f)` | The dash pattern (dash, gap), each a 32-bit float in the low half of a double; empty for a solid line |

The path is the stroke's centre line, drawn at the width with round ends. Every stroke in the samples has one width for its whole length (common widths 2.86, 4.68 and 1.56 units). How varying-width inks are stored is still unknown.

### Shapes (stroke field 9)

A stroke that is a shape has an empty path and its geometry here. Its colour, offset and the rest are the stroke's.

| Field | Geometry |
|---|---|
| 1 | Polyline `{1: point, 1: point, …}`: a line has two points |
| 2 | Three points `{1, 2, 3}`, meaning not confirmed (an arc or a triangle); 3 strokes in the samples, drawn as a polyline in the check |
| 3 | Ellipse `{1: centre, 2: radii}` |
| 4 | Turned ellipse `{1: centre, 2: radii, 3: angle in radians}` |
| 5 | Line style `{1: dash pattern (two floats), 2: 1}` |
| 15 | Width |

### Shape fills (body field 9)

A fill is its own element, drawn in its place in the order: 1 id; 2 bounding box `{1: origin, 2: size}` (NaN when erased); 3 position; 4 geometry, as in a shape (1 polygon, 3 ellipse, 4 turned ellipse); 5 the outline stroke's id, repeated when it belongs to several; 6 offset; 7 colour (alpha 0.1 in every sample); 14 1 when erased.

### Pictures (body field 1)

1 id; 2 frame `{1: origin, 2: size}`; 3 the same frame as `{1: centre, 2: size}`; 4 the attachment; 5 position; 6 2 for the JPEG 2000 stickers, absent otherwise; 7 an id not found among the attachments; 14 1 when deleted. The picture file is the original, at its own resolution (up to 1,097 × 1,017 pixels in the samples), drawn stretched to the frame. No sample has a turned or cropped picture.

## What this means for the import

How each kind of element found in the samples would arrive in Graphite's notebook model:

- Paper: the template PDF page is vector content the size of the page, so it can become the page's content as it is. Mapping it onto Graphite's own paper system instead needs the template catalogue, which these files do not contain (only an id and the ruling numbers).
- Imported PDF pages: the original PDF page from the attachment.
- Strokes: one PencilKit stroke per Goodnotes stroke, with points sampled along the quadratic curves at a constant width; the offset applied; erased strokes left out.
- Shapes, dashes and fills: Graphite has no dashed ink, no editable shapes and no filled shapes yet (see the checklist's "Graphite features this needs first").
- Pictures: separate pictures from the original files. Drawing order mixes pictures and ink freely, and Graphite's pictures always sit under the ink.
- Highlighter: a PencilKit highlighter stroke, drawn in its place in the order in this check. Whether Goodnotes draws highlighter ink under other ink regardless of order is not known; it needs a sample written for it.

## Other readers

These projects read the format too. They are MIT-licensed; their claims below are from their own pages and were not checked:

- [Kaih1825/parser-for-goodnotes](https://github.com/Kaih1825/parser-for-goodnotes): Goodnotes 5 and 6; fountain pen, ballpoint, brush and highlighter, text, pictures, shapes, audio with stroke timing.
- [Taylor-Nilsen/goodnotes-codec](https://github.com/Taylor-Nilsen/goodnotes-codec): Python, reads and writes; text boxes with fonts, turned pictures, stickers, filled shapes, varying-width inks.
- [jakubfabrici/notability-goodnotes](https://github.com/jakubfabrici/notability-goodnotes): converts between Goodnotes (schema 24, 25 and 35) and Notability; text boxes with rotation.
- [RobinSp5/FileConverter](https://github.com/RobinSp5/FileConverter): page order and pictures only, no handwriting.

They are leads for the samples still to make (text boxes, turned pictures, other inks, schema 25 and 35), not a substitute for checking each claim against a real file.
