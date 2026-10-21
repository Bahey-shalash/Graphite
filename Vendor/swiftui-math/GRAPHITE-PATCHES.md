# Graphite changes to SwiftUIMath 0.1.0

Upstream: https://github.com/gonzalezreal/swiftui-math at tag 0.1.0 (commit 0b5c2cfaaec8d6193db206f675048eeb5ce95f71). License: MIT (see LICENSE); the math fonts in `Sources/SwiftUIMath/mathFonts.bundle` carry their own licenses (`OFL.txt`, `GUST-FONT-LICENSE.txt`, `LICENSE` there). Upstream tests, snapshots and the demo images are not vendored, so the manifest has no test target and no SnapshotTesting dependency. Graphite reaches this package only through its vendored Textual (`Vendor/textual/Package.swift`).

## 1. A formula is not broken into lines by its rounded frame

`Sources/SwiftUIMath/Internal/Display/DisplayProvider.swift`: `display(for:font:style:proposedWidth:)` typesets a formula on one line when it is wider than the proposed width by at most `lineBreakTolerance` (one point), and breaks it into lines only when it is wider than that.

`Math` measures its formula for the width it is offered, then draws it in a `Canvas` that typesets the formula again at the canvas's own width. That frame is rounded to whole pixels, so it can come out a fraction of a point narrower than the formula it was measured for. Upstream then broke the formula to fit: `g_m` became `g` over `m` (at 22 points, half a point too narrow is enough; `r_o`, `V_A` and `V_{ov}` break at a quarter of a point), and only one of the two lines showed where the formula belonged. In Graphite's reading view, inline formulas such as `$g_m$`, `$r_o$` and `$V_A$` showed only their subscripts, in some paragraphs and not others, since the rounding depends on where the formula lands. Rounding moves each edge of a frame by at most half a pixel, so a frame is at most one pixel (one point at 1x) narrower than asked, which the tolerance covers at every scale. Textual allows display math the same overhang (`MathAttachment.naturalWidthTolerance`).

Regression test: `AppProjectTextualPatchTests.testFormulaInAFrameNarrowerByAFractionOfAPointStaysOnOneLine` draws each formula in a frame 0.4 points narrower than it and checks that it stays on one line, and that a formula genuinely wider than its width still breaks.

## 2. A fraction late in a line breaks onto the next line

`Sources/SwiftUIMath/Internal/Display/Typesetter.swift`: `shouldBreakBeforeDisplay` measures the line from its start, `currentPosition.x` plus the text since the last display, as the interatom check already does, and treats a line that holds only earlier displays as not empty. Upstream measured only the text since the last fraction, radical or other display, so a fraction after earlier ones was never moved to a new line and was drawn past the width. In a callout, `\text{new time} = \frac{1-f}{s} + f, \qquad \text{memory share} = \frac{f}{…}, \qquad \text{overall speedup} = \frac{1}{\frac{1-f}{s} + f}` at 95 % of its width was not broken at all, and the last fraction was cut off at the callout's edge.

Regression test: `AppProjectTextualPatchTests.testFractionAfterEarlierFractionsBreaksOntoANewLine` measures that formula at 95, 80 and 60 % of its width and checks that it is broken into lines no wider than the width.
