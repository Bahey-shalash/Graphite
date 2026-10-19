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

## Experiments, on the iPad

Each is cheap and answers one question before anything bigger is built.

1. **A Goodnotes-like ball pen.** Give a tool monoline ink at 0.85, 1.56 and 2.55 points and write the same lines with it, with Graphite's pen, and in Goodnotes. If monoline feels like Goodnotes' ball pen, the difference was the pen's varying width, and the fix is a default tool. This needs no code beyond a preset.
2. **Latency.** Film fast straight strokes in both apps at 240 frames per second, with the same iPad, zoom and ink. Count the frames between the tip and the end of the ink, and look for any change at the lift. If Graphite trails by more, the cause is in drawing, not in the shape of the stroke.
3. **Stabilisation.** Write the same slow wavy line in Goodnotes with stabilisation at 0% and at 100%, export both notebooks, and compare the stored samples with the reference reader. That shows whether, and how much, Goodnotes filters samples before storing them.
4. **Only if 1 and 2 leave a difference:** draw the live stroke in Graphite itself as Goodnotes stores it, a quadratic B-spline through every coalesced and predicted sample, round-capped, over or instead of PencilKit's live stroke. Graphite already follows every sample of the drawing touch for the even highlighter (`DrawnStrokeFollower`). This is a large change with real costs, since PencilKit's live drawing, lasso and Pencil interactions would have to be matched, and it is the owner's decision, after the measurements.

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
