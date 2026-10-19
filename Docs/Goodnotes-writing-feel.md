# How writing in Goodnotes feels, from its files

Status: findings, recorded on 2026-10-19. Nothing here is implemented in Graphite.

The owner wrote in the Pencil test notebook that Goodnotes' writing "feels much smoother" than Graphite's, and asked to copy how it feels. This document records what Goodnotes' files show about how it turns Apple Pencil input into ink, what files cannot show, and the experiments that would tell what Graphite should change. The format itself is in [Goodnotes-format.md](Goodnotes-format.md).

Source: the owner's Pencil test notebook (Goodnotes on the iPad, iPadOS 27.0.1, schema 27), written with an Apple Pencil, and Goodnotes' PDF export of it. It has ball pen writing at the owner's three favourite sizes, fountain pen and brush pen strokes pressed lightly and hard, pencil writing and shading, and highlighters. The numbers below were measured with `scripts/goodnotes-reader.py` on that file.

## What a stroke is made of

**The Pencil's samples are kept, not thinned.** The points of a stroke are not reduced to a minimum distance: in the 4,297 gaps between consecutive points of the owner's ball pen writing, gaps go down to zero (ten are under 0.01 units) and spread smoothly up from there, with a median of 3.48 units (0.67 mm). In all the notebook's constant-width strokes, 26,161 gaps, the picture is the same. Goodnotes stores the samples it receives, not a simplified line; whether it filters them first is one of the open questions below.

**The line is a smooth curve through the midpoints of the samples.** Each stored curve is a quadratic Bézier whose control point is a sample and whose end is exactly halfway to the next sample: the median distance from the halfway point is 0.000015 units over 3,129 curves of ball pen, and 98% of the fountain and brush curves are exact halfway points too (the others lie on the same line, a little off centre). This is the quadratic B-spline of the samples: it never passes through a sample, only near it, and it turns without a corner at every joint whatever the samples do. A jittery sample bends the line less than half as much as a line through the samples would.

**The ball pen has one width for the whole stroke.** It does not follow pressure, tilt or speed. The owner's favourite sizes are stored exactly as 0.3, 0.55 and 0.9 mm (1.559, 2.858 and 4.677 units; 0.85, 1.56 and 2.55 points). Ends and joins are round.

**The fountain pen and brush pen follow pressure, and only pressure.** Each sample has its own width, and the width at each curve's end is exactly the average of its two samples', so it changes smoothly along the stroke:

- The width runs between a floor (0.51 to 0.59 units for the thin fountain pen, about 1.5 for the others) and a cap (12.1 units for the thickest brush, where long stretches sit at the cap).
- 21 of the 25 strokes start at their narrowest and widen over their first five or so samples, which is the Pencil's force rising as it lands. Ends are not tapered on purpose: a stroke lifted while pressing ends wide.
- The width does not follow speed: within strokes, the correlation between width and the distance between samples (which grows with speed, since every sample is kept) is between −0.33 and +0.12, mostly near 0.
- It does not follow the stroke's direction either (the nib was set to round).

Goodnotes stores the outline it fills, too: per segment, the two sides as cubic Béziers and round arcs around the segment's ends. Joints are covered by those arcs, so there are no seams or notches where the width changes.

**The pencil keeps the Pencil's every value.** Each sample has x, y, azimuth, altitude and force (0 to 4.17, the Pencil's maximum), and the stroke has one width (4.68 units in every sample). Goodnotes draws it textured, darker with force, and broader for shading when the Pencil lies on its side (altitude 0.19 to 0.27 radians in the shading strokes).

**The highlighter is laid over everything and multiplied into it.** Writing under a highlight stays as dark as it was, and coloured ink under it is tinted (green over pink turns brown in the export). Its width is constant, like the ball pen's.

## What the files cannot show

How writing feels on the glass depends on more than the finished stroke, and none of it is stored:

- **Latency**: how far the ink trails behind the tip. It depends on the renderer, on predicted touches and on frame pacing.
- **The live stroke**: whether what is drawn while writing is the same as what stays after the lift. A stroke that changes at the lift feels unstable; Graphite had this with the highlighter (`Architecture.md`, the even highlighter).
- **Smoothing while writing**: Goodnotes' "stroke stabilisation" setting. Whether it filters the samples before they are stored can only be seen by writing the same stroke with it at 0% and 100%.
- **Sampling**: whether Goodnotes uses every coalesced Pencil sample (240 per second) or one per frame. The files have no times per point.

## Graphite now

Graphite draws with PencilKit (`PencilToolbox.swift`, `HistoryCanvasView.swift`). Its first tool is PencilKit's **pen**, whose width PencilKit varies as the Pencil is pressed. Apple does not document by how much, or whether speed changes it too. PencilKit's stroke path is, by Apple's documentation, a uniform cubic B-spline through its points, so PencilKit smooths the line in a similar way to Goodnotes, if anything more. The difference the files point to is therefore the width: Goodnotes' ball pen never changes width, and Graphite's pen does.

Graphite already offers PencilKit's **monoline** ink, which has one width whatever the pressure and tilt, from 0.5 to 4 points. That range holds all three of the owner's Goodnotes ball pen sizes (0.85, 1.56 and 2.55 points).

## Zoom: the same width on the page

**Goodnotes writes at the pen's width on the page, at any zoom.** In the owner's A3 formula sheet, a whole course in small writing on two pages, 69% of the ball pen strokes have exactly one of the pen's sizes (6,925 of them 0.55 mm), and every one of the 4,668 strokes never edited after it was written has a pen size. The other 3,516 strokes, in 42 other widths, were all edited afterwards (their version counter is past 2): they are strokes resized with the lasso, whose widths Goodnotes scaled with them. So zooming in to write small makes the ink look thicker on screen but keeps it as thick on the page as everything else, and the sheet stays even; resizing a selection keeps its proportions.

**A sample made for it confirms this.** The owner wrote on an A3 landscape page (1,190.55 × 841.89 points; one Goodnotes unit is 0.1924 mm on the sheet), all with the ball pen at 0.9 mm, once with the page shown whole ("no zoom") and once at Goodnotes' largest zoom ("allows super detailed writing, very helpful for cheat sheets"), then copied a word and resized it. On the A3 sheet:

| Writing | Ink width | Letter height (median stroke) | Gap between samples (median) |
|---|---|---|---|
| Page shown whole | 0.90 mm | 4.4 mm | 1.22 mm |
| Largest zoom | 0.90 mm | 2.6 mm | 0.61 mm |
| A word shrunk to 0.456 of its size | 0.41 mm (×0.455) | | |
| The same word enlarged 5.47 times | 4.91 mm (×5.46) | | |

The ink is 0.9 mm on the paper at both zooms; zooming in only lets the hand make smaller letters with it, and the Pencil's samples land twice as close on the paper, because they are taken on the screen. Resizing scales the ink with the word, to within 0.002 of the same factor, which is why a shrunk or enlarged copy is not distorted. Every stroke of the page that was not resized has exactly the 0.9 mm width.

**Graphite does the same on PDF pages, within limits, and not in drawings:**

- On a PDF page the canvas draws at a zoom of 1 to 3 in steps of a half (`PDFPageOverlayView.renderingScale`), and the tool's width is multiplied by it (`PDFPageCanvasView.toolForDrawing`), so the width on the page stays the same. But PencilKit clamps each ink's width (`PencilInk.widthRange`): monoline at 4 points, pencil at 16, the pen at 25. A 3-point monoline at a zoom of 3 asks for 9 and gets 4, so it lands on the page 1.33 points wide instead of 3: the narrow inks write thinner as the page is zoomed in, which is the opposite of an even cheat sheet. The pen's 25 is only reached by its widest settings.
- The drawing editor (`InfiniteCanvasView`, zoom up to 4 times its fitted size) does not correct the width. By the note on `PDFPageCanvasView.toolForDrawing`, PencilKit keeps a tool as wide on screen at any zoom, so a drawing written zoomed in comes out finer on the drawing, up to a quarter of the tool's width. This is read from the code and needs confirming on the iPad.

## Fixed tool bar and floating palette

The owner finds that writing feels different with the fixed tool bar than with the floating palette. The two give the canvas its tool in different ways (`HistoryCanvasView.takeTool`):

- **Bar:** Graphite builds the tool from the bar's preset (`InkPreset.inkingTool`: the ink, colour and width, nothing else) and sets it on the canvas itself, through `toolForDrawing`.
- **Palette:** the canvas observes PencilKit's tool picker, so PencilKit sets the palette's tool on the canvas as it is. One turn of the main queue later `PaletteToolCorrection` replaces it with what `toolForDrawing` makes of it (the width multiplied by the page canvas's zoom, the even highlighter's stand-in). The correction runs only when the palette's selection changes or the zoom step changes.

What can therefore differ, by reading the code (none of it has been checked on the iPad):

1. **The width.** The bar's pen starts at 1.6, 2.8 and 4.8 points; the palette's pen has the system's own widths. The same ink at another width feels different, more so with the pen, whose width also follows pressure.
2. **The tool's other properties.** The palette's tool is PencilKit's own object, which may carry properties the bar's does not set (on iOS 26 and later an inking tool also has an azimuth; the bar's is built without one). The scaled tool keeps the azimuth.
3. **Moments with the palette's raw tool.** Whenever PencilKit gives the canvas the palette's tool without a selection change Graphite hears of, the canvas draws with the width not multiplied by the page's zoom until the next correction: on a page zoomed to a canvas scale of 2, strokes would be half as thick on the page.

Ruled out by reading the code: the drawing policy (Pencil only, or any input with Draw with Finger) is set the same way in both (`GraphitePDFView`, `DrawingEditor`); the page keeps first responder by the same rule (`PDFAnnotationInput.holdsFirstResponder`, which follows focus); and the bar does not redraw while writing, since everything in `PencilToolbox` that changes during a stroke is excluded from observation and the rest changes only when a tool is chosen. What remains is the tool itself: its width, its other properties, and the moments the palette's unscaled tool is on the canvas.

Which of these it is shows at once in a log of the tool the canvas has when each stroke begins (ink, width, azimuth, the canvas's zoom), written with the bar and with the palette at the same zoom and the same chosen width.

## Experiments, on the iPad

Each is cheap and answers one question before anything bigger is built.

1. **A Goodnotes-like ball pen.** Give a tool monoline ink at 0.85, 1.56 and 2.55 points and write the same lines with it, with Graphite's pen, and in Goodnotes, at the page's own zoom. If monoline feels like Goodnotes' ball pen, the difference was the pen's varying width, and the fix is a default tool. Zoomed in, monoline's 4-point limit makes it thinner on the page (Zoom, above), so a ball pen for cheat sheets also needs that limit worked around, for example by drawing the page canvas at a lower scale while a narrow ink is in use.
2. **Latency.** Film fast straight strokes in both apps at 240 frames per second, with the same iPad, zoom and ink. Count the frames between the tip and the end of the ink, and look for any change at the lift. If Graphite trails by more, the cause is in drawing, not in the shape of the stroke.
3. **Stabilisation.** Write the same slow wavy line in Goodnotes with stabilisation at 0% and at 100%, export both notebooks, and compare the stored samples with the reference reader. That shows whether, and how much, Goodnotes filters samples before storing them.
4. **Bar against palette.** Log the canvas's tool at the start of each stroke (above), write with the bar and with the palette at the same zoom and width, and compare.
5. **Zoom.** On a PDF page and in a drawing, write the same word at 1×, 2× and 3× with the pen and with monoline, export, and measure the widths on the page.
6. **Only if 1 and 2 leave a difference:** draw the live stroke in Graphite itself as Goodnotes stores it, a quadratic B-spline through every coalesced and predicted sample, round-capped, over or instead of PencilKit's live stroke. Graphite already follows every sample of the drawing touch for the even highlighter (`DrawnStrokeFollower`). This is a large change with real costs, since PencilKit's live drawing, lasso and Pencil interactions would have to be matched, and it is the owner's decision, after the measurements.

## Numbers

| What | Value |
|---|---|
| Gap between samples, ball pen writing | median 3.48 units (0.67 mm) over 4,297 gaps, down to 0, no minimum |
| Curve ends at the halfway point between samples | ball pen: median error 0.000015 units over 3,129 curves; fountain and brush: 98% exact |
| Ball pen sizes (the owner's) | 0.3, 0.55, 0.9 mm = 1.559, 2.858, 4.677 units = 0.85, 1.56, 2.55 points |
| Fountain and brush width | floor 0.5 to 1.6 units, cap up to 12.1; 21 of 25 strokes start at their narrowest and widen over ~5 samples |
| Width against speed | correlation −0.33 to +0.12 within strokes |
| Pencil per sample | azimuth −π to π, altitude 0.19 to 1.50 radians, force 0 to 4.17 |
| Pencil width | 4.68 units for every pencil stroke |
| A3 sample, ball pen 0.9 mm | 0.90 mm on the sheet with the page shown whole and at the largest zoom; letters 4.4 and 2.6 mm; samples every 1.22 and 0.61 mm |
| A3 sample, resized copies | ink ×0.455 and ×5.46 for words ×0.456 and ×5.47 |
| Formula sheet, strokes at a pen size | 7,699 of 11,215 (69%); every stroke never edited (4,668) has a pen size; all 3,516 others were edited later |
