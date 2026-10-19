# The Goodnotes file format (`.goodnotes`)

Status: Phase 1 of [the import checklist](Goodnotes-Notability-import-todo.md). Recovered from the owner's notebooks, on 2026-10-18 and 2026-10-19, by reading the files only; no part of Goodnotes was run, decompiled or copied. Nothing here is implemented in Graphite yet.

What was checked:

- A reference reader written for this, `scripts/goodnotes-reader.py`, reads all 46 sample notebooks with no record kind, field or path layout it does not know. The one exception is a single element missing from its page's member list (see Page elements). In total that is 134,264 live strokes, 175 pictures, 177 fills, 27 text boxes (5 newer, 22 older), a sticky note and one other text element.
- Pages drawn from what it reads were compared with the PDF that Goodnotes exported for the six notebooks made for the purpose and for the Pencil test (see Comparison with Goodnotes' own export). The four notebooks of 2026-10-18 and the 35 library notebooks have no export; those were compared by eye with the thumbnail each notebook carries.

## The samples

| Set | Notebooks | Made with | Schema | What they cover |
|---|---|---|---|---|
| First samples (2026-10-18) | 4 | Goodnotes on the iPad, version not recorded | 24 | Pen, highlighter, lines, ellipses, fills, dashes, pictures, stickers, erasing, lasso moves, copied pages, template paper, imported PDFs |
| Made for the purpose (2026-10-19) | 6 | Goodnotes 7.1.28 for Mac, with a mouse | 24, 25, 35 | Text boxes in two fonts; fountain pen, brush pen, pencil, ball pen and highlighter over writing; a turned and a cropped picture; tape, a sticky note, a link and a bookmark; a deleted page; a recording with writing; a cover page |
| Pencil test (2026-10-19) | 1 | Goodnotes on the iPad with an Apple Pencil, iPadOS 27.0.1 | 27 | Ball pen at 0.3, 0.55 and 0.9 mm, fountain pen, brush pen, pencil shading with tilt, highlighter presets, rectangles, ellipses, an arc, fills, two animated GIFs, two stickers, two saved drawings; with Goodnotes' PDF export. How the writing feels is in [Goodnotes-writing-feel.md](Goodnotes-writing-feel.md) |
| Library selection (2026-10-19) | 35 | Goodnotes on the iPad, versions not recorded | 24, 25, 26 | Chosen from the owner's 691-notebook semester library to cover every schema and every unknown the first reader reported there: older text boxes, older varying-width ink, outline entries, page moves, recordings and their deletion |

The made-for-purpose samples and the library selection are kept on the owner's Mac only, in the local `samples/import-formats` branch under `ImportSamples/Goodnotes/`, each with a README saying what was done. They hold personal notebooks, so they are not on GitHub. **Still not in any sample:** text box rotation; a link to a page; and the meaning of several fields marked unknown below.

## Container

A ZIP archive (deflate). One notebook:

```
schema.pb                 schema version
document.info.pb          empty in every sample
index.notes.pb            ink layer id -> "notes/<id>"
index.attachments.pb      attachment id -> "attachments/<file id>"
index.search.pb           search record id -> "search/<id>"
index.events.pb           the notebook's event log: document, attachments, paper, pages, outline, recordings
notes/<layer id>          one file per page with content: that page's elements
attachments/<file id>     template PDFs, imported PDFs, pictures (PNG, JPEG, JPEG 2000), recordings (MP4 audio), with no extension
search/<id>               handwriting recognition results (word candidates, boxes, stroke ids): derived, not needed
thumbnail.jpg             the first page
```

Empty files are normal: a page with no content has an empty `notes/<id>`. Imported PDFs with no writing on them have only empty notes files; in the library selection these are 5 notebooks, which the first reader showed as having no elements.

## Encoding

**Protocol Buffers without a schema.** Every `.pb` file and every `notes/` file is a sequence of protobuf messages, each preceded by its length as a varint. Field numbers below are protobuf field numbers; their names are this document's. Floats are 32-bit (wire type 5) unless marked `double`. A field equal to its default (zero, empty) is left out, as in proto3: a colour with no red component has no field 1.

**`schema.pb`** is one message without a length prefix, `{1: version}`: 24, 25, 26, 27 or 35 in the samples. Every record also carries the schema it was written with, so a notebook started in an older Goodnotes mixes record versions (a schema 35 notebook has schema 24 strokes next to schema 35 text boxes). What each version adds, as far as the samples show: 25 the fountain pen, brush pen and pencil layouts; 26 outline entries; 27 a group on strokes (field 10); 35 the newer text boxes and sticky notes. Schema 27 came from the iPad and 35 from the Mac on the same day, so the number may follow the platform's build rather than time.

**Versioned registers.** Most editable values are wrapped as a last-writer-wins register, `{1: value, 2: clock}`, where the clock is `{1: counter, 2: replica hash}`. Several records may set the same register; the highest counter wins.

**Derived ids.** A page's ink layer id is the page id with 1 added to its last byte, without carry: `…25FF` becomes `…2500`, not `…2600`.

**Coordinates.** Origin at the top-left corner of the page, y downwards. One unit is 6/11 of a PDF point (132 units per inch, the first iPad's screen density): an A4 page is 1,091.35 × 1,543.46 units, A3 landscape 2,182.68 × 1,543.46, and the Standard size 834.24 × 1,078.82 (455.04 × 588.45 points). Font sizes and text box sizes are in the same units: a 24-unit font is 13.1 points.

**Compressed payloads** (ink paths, rich text) use Apple's LZ4 framing (Compression framework, `COMPRESSION_LZ4`): blocks of `bv41`, the decoded and encoded sizes as little-endian 32-bit integers, then a raw LZ4 block; `bv4-` for a stored block; `bv4$` ends the stream. Ink paths are then a [tpl](https://troydhanson.github.io/tpl/) image (Troy Hanson's serialisation library): `tpl`, a flags byte (0: little-endian), the total size as a 32-bit integer, a NUL-terminated format string, then the values. Each `A(…)` array starts with its element count as a 32-bit integer. Rich text is protobuf again.

**Times.** Record timestamps are doubles in milliseconds since 1970. Recording times are in flicks, 1/705,600,000 of a second: a recording's duration of 33,304,320,000 flicks is its MP4's 1,040,760 samples at 22,050 Hz, 47.2 seconds.

## The event log (`index.events.pb`)

Each message is `{1: entity id, <kind>: body}`, with exactly one body field. The kinds seen:

| Kind | Meaning | Body fields used |
|---|---|---|
| 30 | Document created | 1 id; 2 title (register); 9 locale; 10 created (double, milliseconds since 1970); 20 schema. Also 3, 6 (`"P"`), 7 and 19, meaning unknown |
| 31 | Document renamed | 2 title (register) |
| 33 | Sharing record | id `Shared-<id>:<id>:<id>`; registers like the document's. Not needed for the import |
| 34 | Document changed | 2 (register, empty in the samples) |
| 6 | Attachment | 1 id; 2 file id (the name under `attachments/`); 5 size in bytes; 6 document; 12 `{1: 1, 2: page count}` for a PDF, absent for a picture or recording |
| 2 | Paper (background) | see below |
| 54 | Page created | 1 document; 2 page id; 3 paper (register of a paper id); 4 position (register of a string) |
| 3 | Page paper changed | 3 paper (register) |
| 55 | Page moved | 3 new position (register, higher counter than the page's first) |
| 56 | Page deleted | 3 register; 1 means deleted. The page's records stay in the file |
| 57 | Page bookmarked | 3 register; 1 means bookmarked ("Add to Favorites"), empty means the bookmark was removed |
| 63 | Page flag | 3 register, 1 in its one sample; meaning unknown |
| 62 | Outline entry | 5 title; 6 position among the entries (a fractional index); 3 `{1: point}` on the target page; 2 the target, which matches no record in the samples |
| 102 | Ink layer created | id = page id + 1 |
| 106 | Ink layer members | 2 repeated: the page's element ids (registers). Not the drawing order, and absent from some notebooks (see Page elements) |
| 160 | Recording | 2 the audio attachment; 3 document; 4 duration in flicks; 5 `{1: {1: element id, 2: {1: time in flicks from the start, 2: page id}}, …}`, one entry per element written during the recording |
| 163 | Recording deleted | the recording's id |
| 10 | Last page viewed | 2 page; 3 `"PagingViewServiceUpdater:<id>"` |
| 103, 104, 105 | Search index bookkeeping | not needed |

**Paper (kind 2).** A page's paper is a separate record, and many pages share one. Fields: 4 attachment (a PDF); 5 page number in that PDF, from 1; 8 page size `{1: width, 2: height}` in units; 9 template id (empty for an imported PDF); 18 ruling `{1: {1: origin, 2: size} (the writing area), 2: line spacing, 3: unknown, 5: unknown}`; 6, 7 (double 29.33), 12 (register, 29.33), 13 (register, 1), 17 (register, 1 or 2) and 19 are not understood.

The paper is drawn by the attachment, never by Goodnotes from the template id. Template paper is a one-page vector PDF made by svg2pdf (the grid, rules and paper colour), and an imported PDF page is the original PDF. Template ids read `<catalogue UUID>_<size>_<orientation>_<design>`: `a4`, `a3` and `standard` sizes, orientation 1 portrait and 2 landscape, and a design that is a number with a colour (`2 - White`, `1 - Yellow`) or a UUID. A cover is the first page with a cover template (`…_standard_1_1 - Blue` from another catalogue).

**Pages and their order.** The notebook's pages are the kind 54 records that are not deleted (kind 56 with value 1), sorted by position, comparing the position strings byte by byte (fractional indexing: `4!Wfh` < `AxSGV` < `_-KWPko01`). A move (kind 55) replaces the position. A page of an imported PDF that the notebook does not use has no record.

## Page elements (`notes/<layer id>`)

Each element is two messages: a header, then its body.

**Header:** `{1: element id, 2: clock, 3: 1 if deleted, 4: attachment (pictures), 6: order id, 7: a second id (meaning unknown), 8: replica, 9: counter, 10: 1 on the one text element of kind 12, 14: 5381, 16: schema}`. An element is drawn when its header is not deleted; erased strokes stay in the file.

The layer file is the authority on which elements a page has. The member list (kind 106) names each element by its order id (header field 6) when it has one and by its element id otherwise. But it is missing from all six made-for-purpose notebooks (and from notebooks with no content), and in one library notebook one element is missing from a member list that exists. In the 2026-10-18 samples, field 6 is set on all elements of three neighbouring pages and on some of a fourth, which suggests copied or pasted elements (not confirmed).

**Body:** one field naming the kind:

| Body | Element |
|---|---|
| 7 | Stroke, including shapes, highlighter and tape |
| 1 | Picture |
| 9 | A shape's fill |
| 21 | Text box (schema 35) |
| 8 | Text box (older, RTF) |
| 20 | Sticky note |
| 12 | A text element in RTF with no frame; one sample, empty and bold, purpose unknown |

**Drawing order.** Each body has a position, `{1: {1: counter, 2: replica}}`: field 7 of a stroke, text box and sticky note, 5 of a picture and of an older text box, 3 of a fill, 13 of a kind 12 element. Elements are drawn sorted by counter, then replica. Neither the member list nor the order of records in the file is the drawing order. The evidence: in the 37 first-sample pages with at least 50 strokes, consecutive strokes sorted by position are on average 47.5 units apart, as handwriting written in sequence is, against 467 in member-list order, 468 in file order and 466 in a random order. The position does not decide everything: 751 of 27,789 live elements in the first samples share both counter and replica with another element on their page, and how Goodnotes orders those is not known (the reference reader keeps them in file order).

**Highlighter ink is drawn after all other ink and multiplied into it**, as a real highlighter: black writing under it stays black, and colours under it are tinted. In the Pencil test's export a green highlighter over yellow and pink ink turns them yellow-green and brown, which only multiplying on top gives; drawing highlighters first (an earlier reading of this document, from a sample with black ink only) gives the wrong colours.

### Strokes (body field 7)

| Field | Meaning |
|---|---|
| 1 | Element id |
| 2 | The path: LZ4, then tpl, in one of four layouts (below) |
| 3 | Ink: absent (0) for ball pen and highlighter; 1 for fountain pen, brush pen and tape; 4 for an older varying-width ink; 5 for pencil |
| 4 | Colour `{1: red, 2: green, 3: blue, 4: alpha}`, 0 to 1 |
| 5 | 1 for the highlighter (alpha 0.5) |
| 6 | Offset `{1: x, 2: y}` added to every point: a lasso move |
| 7 | Position in the drawing order |
| 9 | Shape, when the stroke was drawn as one (below) |
| 10 | A group id (a UUID string), the same on every stroke of a saved drawing put on the page (schema 27); its strokes are ordinary vector strokes, so resizing it loses nothing |
| 14 | 1 when erased; the path is then empty |
| 15 | Version clock (equals the header's field 2) |
| 20 | `{1: ""}` on tape, empty otherwise |
| 21 | Schema |

The fountain pen and the brush pen have the same ink number and layout; the samples tell them apart only by width.

**Constant width** (`vuA(v)A(S(uu))A(S(uuuu))vA(f)`; ball pen, highlighter, shapes):

| Value | Meaning |
|---|---|
| `v` | 2 in every sample |
| `u` | The width, a 32-bit float stored in a `u` |
| `A(v)` | One code per path element: 0 starts a subpath, 1 is a curve |
| `A(S(uu))` | One start point (x, y) per subpath |
| `A(S(uuuu))` | One quadratic Bézier per curve: control point, then end point |
| `v` | 1 in every sample |
| `A(f)` | The dash pattern (dash, gap), each a 32-bit float in the low half of a double; empty for a solid line |

The path is the centre line, drawn at the width with round ends.

**Varying width** (`vA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)`, schema 25 on; fountain pen, brush pen, tape). It holds both the centre line with a width at each point, and the outline Goodnotes fills:

| Value | Meaning |
|---|---|
| `v` | 2 |
| `A(v)` | Centre line codes: 0 (or 4 on tape) starts, 1 (or 5) is a curve |
| `A(u)` | Start: x, y, width (tape adds one more value, 0) |
| `A(u)` | Per curve: control x, y, width; end x, y, width (tape adds three more values, 0, 0, 0.1) |
| `A(v)` | Outline commands per centre-line segment |
| `A(v)` | Outline codes: 0 move to the segment's outline start; 2 cubic Bézier (three points from the outline points); 3 arc (the next cap record); 6 flat cap (tape) |
| `A(u)` | Outline start, x and y, one per segment |
| `A(u)` | Empty in every sample |
| `A(u)` | Outline points, x and y |
| `A(u)` | Cap records, one per cap command, in order: centre x, y, radius, start angle, end angle (seven numbers on tape) |
| `A(v)` | 1 per cap record |

Each centre-line segment has its own closed outline. Most often it is one side as cubics, an arc around the segment's end, the other side back and an arc around its start (1,606 of the Pencil test's 2,723 segments); 908 segments are all cubics, and the rest have the arcs elsewhere or more of them. An arc continues from the current point, which lies on its circle at the start angle (all 3,651 arcs checked), to the end angle, mostly half a turn. A flat cap is a straight edge through the record's point. Filled this way, the fountain and brush strokes match the export (see the comparison below).

**Older varying width** (`vuA(v)A(u)A(u)A(v)A(v)A(u)A(u)A(u)A(u)A(v)`, ink 4, 90 strokes in three library notebooks): the same arrays after a leading width, but the outline codes are 2 for move and 4 for cubic, there are no caps, and the centre line uses codes 0 to 3 whose meaning is not worked out. Drawn from the outline, the strokes look like clean lines and boxes over a circuit diagram; there is no export to compare with.

**Pencil** (`vuA(v)A(S(uuuuu))A(S(uuuuuuuuuuu))A(S(uu))A(v)A(S(uu))A(S(uuuu))A(u)`, schema 25 on, tpl version 1): a width, codes as in the constant-width layout, start points of five numbers (x, y and three more), and curves of eleven: a first 32-bit value that is not a sensible float (perhaps a texture seed), then the control point and the end point, each x, y and three more numbers. The three numbers are the Apple Pencil's azimuth (radians, −π to π), altitude (radians, 0 to π/2: 0.19 to 0.27 while shading with the pencil on its side) and force (0 to 4.17, the Pencil's maximum), as written with a real Pencil in the Pencil test; the mouse gave 0.524, 1.047 and 0 at every point. The five trailing arrays were empty. Every pencil stroke in the samples has the same width (4.68 units); Goodnotes draws it textured, darker with force and broader as the Pencil tilts, and with the mouse's force of 0 very pale. The reference renderer does not imitate the texture.

### Shapes (stroke field 9)

A stroke that is a shape has an empty path and its geometry here. Its colour, offset and the rest are the stroke's.

| Field | Geometry |
|---|---|
| 1 | Polyline `{1: point, 1: point, …}`: a line has two points |
| 2 | An arc of a circle through three points `{1, 2, 3}`, from the first through the second to the third (the export of the Pencil test draws it so) |
| 3 | Rectangle `{1: centre, 2: width and height}` (the export's square is the stored size plus the line width) |
| 4 | Ellipse `{1: centre, 2: radii, 3: angle in radians}` (the export's circles have the stored radius to half a unit) |
| 5 | Line style `{1: dash pattern (two floats), 2: 1}` |
| 15 | Width |

### Shape fills (body field 9)

A fill is its own element, drawn in its place in the order: 1 id; 2 bounding box `{1: origin, 2: size}` (NaN when erased); 3 position; 4 geometry, as in a shape (1 polygon, 3 rectangle, 4 ellipse); 5 the outline stroke's id, repeated when it belongs to several; 6 offset; 7 colour (alpha 0.1 in every sample); 14 1 when erased.

### Pictures (body field 1)

1 id; 2 the bounding box of the picture as drawn `{1: origin, 2: size}`; 3 the placement `{1: centre, 2: size before turning, 3: angle in radians}`, clockwise on the page; 4 the attachment; 5 position; 6 the kind of picture as far as seen: 2 a JPEG 2000 sticker, 5 an animated GIF (kept as the original GIF file), 1 on the turned picture, absent on photos and on a PNG sticker; 7 an id not found among the attachments; 14 1 when deleted. The picture file is drawn stretched to the placement's size, turned about its centre. A turned picture's angle in the sample was 0.5087 radians (29.1°) for a drag to "about 30 degrees clockwise".

**Cropping replaces the file.** A cropped picture points to a new PNG of the kept part (201 × 150 pixels from a 400 × 300 original), with no crop rectangle; the original stays among the attachments. An import keeps the cropped bitmap, which is at the original's resolution.

### Text boxes (body field 21, schema 35)

| Field | Meaning |
|---|---|
| 20 | `{1: origin, 3: scale}` |
| 21 | `{3: {1: 32, 2: 600, 3: 32, 4: infinity}}`, probably the minimum and maximum width and height |
| 32 | Layout and text: `{1: {2: rich text (LZ4), 3: hash}, 2: size, 5: {1: default attributes, 2: paragraph}, 10: insets {1, 2, 3, 4}}` |
| 30, 31, 33 | Background and border colours, shadow (alpha 0.2, offset 5); not checked against an export |
| 7, 3 | Position, version clock |

The rich text, once decompressed, is `{1: {1: text, 2: attributes, 3: paragraph}}`. Attributes and defaults share one layout: 3 colour (RGBA, 0 to 1), 4 link (a URL), 30 font name, 40 size in units; −404 in a size or a related field means "not set, use the default". The samples' text boxes each have one attribute run; how several runs mark their ranges is not known yet. Goodnotes calls the fonts "Modern" (Helvetica Neue) and "Classic" (Georgia), as the export's embedded fonts show.

Placement, checked against the export's text layer: the text starts at the origin plus the inset (10 units), in points 216.1 + 5.45 = 221.6 and 296.5 + 5.45 = 302.0 for "Graphite one", exactly where the export puts the word. The box is 140 × 29 units (76.4 points wide), the width of the line of text.

**Links.** A link on a text box is the run attribute 4: `https://example.com/graphite` in the sample.

### Older text boxes (body field 8)

22 in three library notebooks. 2 the box `{1: origin, 2: size}`; 3 the text area, the box inset by 10 on each side; 6 the text as Cocoa RTF (fonts, sizes in half-points, colours, and `HYPERLINK` fields for links); 7 and 9 colours; 10 the inset; 14 1 when deleted; 18 and 19 the shadow. The RTF is the only copy of the text, so an importer needs an RTF reader (Foundation's on Apple platforms).

### Sticky notes (body field 20)

20 `{1: origin}`; 21 `{2: {1: width, 2: height}}`, 256 × 256 in the sample; 30 paper colour; 31 rich text as in a text box; 32 the author's account id; 33 the author's name, which Goodnotes prints at the bottom of the note; 40, 41 1. The note appears in the export at its origin and size.

## Comparison with Goodnotes' own export

Each page of the six made-for-purpose notebooks was drawn from what the reader decoded, at one pixel per unit, and compared with the same page of the export rendered at the same size. The share of pixels differing by more than 60 of 255:

| Sample | Pages | Differing | What differs |
|---|---|---|---|
| Inks | 1 | 0.15% | The pencil: Goodnotes draws it textured and pale, the check solid; antialiasing |
| Turned and cropped pictures | 1 | 0.08% | Picture edges |
| Recording with writing | 1 | 0.01% | Stroke edges |
| Deleted page | 2 | 0.07%, 0.09% | The typed text, which the check does not draw |
| Text boxes | 2 | 0%, 0.21% | The typed text |
| Tape, sticky note, link | 1 | 0.25% | The typed text; the tape's slightly rounded ends and faint shadow |
| Pencil test | 6 | 0.44%, 2.2%, 0.44%, 0.79%, 0.14%, 0.78% | Page 2 is pencil shading, which the check draws solid; page 4 the GIFs, drawn from their first frame; elsewhere stroke edges |

The Pencil test was compared at 0.6 pixel per unit; the others at 1. The paper, the page count (the deleted page left out), ink positions and widths, the fountain and brush outlines with their arcs, the highlighter multiplied over the other ink, rectangles, ellipses and arcs, the turned picture's angle and the tape all match. Text was checked separately against the export's text layer, as above.

## What this means for the import

How each kind of element found in the samples would arrive in Graphite's notebook model:

- Paper: the template PDF page is vector content the size of the page, so it can become the page's content as it is. Mapping it onto Graphite's own paper system instead needs the template catalogue, which these files do not contain (only an id and the ruling numbers).
- Imported PDF pages: the original PDF page from the attachment.
- Pages: in position order, deleted pages left out, bookmarks as PDF bookmarks.
- Ball pen and highlighter: one PencilKit stroke per Goodnotes stroke, points sampled along the quadratic curves at a constant width; the offset applied; erased strokes left out. Goodnotes multiplies highlighter ink over the rest; Graphite draws a highlighter normally (see `Architecture.md`), so colours under a highlight will look lighter than in Goodnotes.
- Fountain and brush pen: the centre line with its width at each point gives PencilKit strokes with a size per point; the stored outline is the exact shape for the PDF annotation.
- Pencil: a PencilKit pencil stroke with the stored force, azimuth and altitude at each point.
- Tape: Graphite has no tape (checklist, "Graphite features this needs first").
- Shapes, dashes and fills: Graphite has no dashed ink, no editable shapes and no filled shapes yet.
- Pictures: separate pictures from the files, with their turn. A cropped picture arrives already cropped. An animated GIF can only be a still picture in a PDF; the import report has to say so.
- Saved drawings: their strokes, as any others. Drawing order mixes pictures and ink freely, and Graphite's pictures always sit under the ink.
- Text boxes and sticky notes: Graphite has no text boxes yet. The text, fonts, sizes, colours and links are all readable; older text boxes need an RTF reader.
- Recordings: the MP4 audio as an `.m4a`, with the time of each element written during it (elements since deleted included, so the timings must be matched to live elements).
- Outline entries: titles and order are readable, but their target is not resolved yet.

## Other readers

These projects read the format too. They are MIT-licensed; their claims below are from their own pages and were not checked:

- [Kaih1825/parser-for-goodnotes](https://github.com/Kaih1825/parser-for-goodnotes): Goodnotes 5 and 6; fountain pen, ballpoint, brush and highlighter, text, pictures, shapes, audio with stroke timing.
- [Taylor-Nilsen/goodnotes-codec](https://github.com/Taylor-Nilsen/goodnotes-codec): Python, reads and writes; text boxes with fonts, turned pictures, stickers, filled shapes, varying-width inks.
- [jakubfabrici/notability-goodnotes](https://github.com/jakubfabrici/notability-goodnotes): converts between Goodnotes (schema 24, 25 and 35) and Notability; text boxes with rotation.
- [RobinSp5/FileConverter](https://github.com/RobinSp5/FileConverter): page order and pictures only, no handwriting.

Nothing in this document was taken from them.
