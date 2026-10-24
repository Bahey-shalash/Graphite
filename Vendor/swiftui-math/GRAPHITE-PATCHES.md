# Graphite changes to SwiftUIMath 0.1.0

Upstream: https://github.com/gonzalezreal/swiftui-math at tag 0.1.0 (commit 0b5c2cfaaec8d6193db206f675048eeb5ce95f71). License: MIT (see LICENSE); the math fonts in `Sources/SwiftUIMath/mathFonts.bundle` carry their own licenses (`OFL.txt`, `GUST-FONT-LICENSE.txt`, `LICENSE` there). Upstream tests, snapshots and the demo images are not vendored, so the manifest has no test target and no SnapshotTesting dependency. Graphite reaches this package only through its vendored Textual (`Vendor/textual/Package.swift`).

## 1. A formula is not broken into lines by its rounded frame

`Sources/SwiftUIMath/Internal/Display/DisplayProvider.swift`: `display(for:font:style:proposedWidth:)` typesets a formula on one line when it is wider than the proposed width by at most `lineBreakTolerance` (one point), and breaks it into lines only when it is wider than that.

`Math` measures its formula for the width it is offered, then draws it in a `Canvas` that typesets the formula again at the canvas's own width. That frame is rounded to whole pixels, so it can come out a fraction of a point narrower than the formula it was measured for. Upstream then broke the formula to fit: `g_m` became `g` over `m` (at 22 points, half a point too narrow is enough; `r_o`, `V_A` and `V_{ov}` break at a quarter of a point), and only one of the two lines showed where the formula belonged. In Graphite's reading view, inline formulas such as `$g_m$`, `$r_o$` and `$V_A$` showed only their subscripts, in some paragraphs and not others, since the rounding depends on where the formula lands. Rounding moves each edge of a frame by at most half a pixel, so a frame is at most one pixel (one point at 1x) narrower than asked, which the tolerance covers at every scale. Textual allows display math the same overhang (`MathAttachment.naturalWidthTolerance`).

Regression test: `AppProjectTextualPatchTests.testFormulaInAFrameNarrowerByAFractionOfAPointStaysOnOneLine` draws each formula in a frame 0.4 points narrower than it and checks that it stays on one line, and that a formula genuinely wider than its width still breaks.

## 2. A fraction late in a line breaks onto the next line

`Sources/SwiftUIMath/Internal/Display/Typesetter.swift`: `shouldBreakBeforeDisplay` measures the line from its start, `currentPosition.x` plus the text since the last display, as the interatom check already does, and treats a line that holds only earlier displays as not empty. Upstream measured only the text since the last fraction, radical or other display, so a fraction after earlier ones was never moved to a new line and was drawn past the width. In a callout, `\text{new time} = \frac{1-f}{s} + f, \qquad \text{memory share} = \frac{f}{…}, \qquad \text{overall speedup} = \frac{1}{\frac{1-f}{s} + f}` at 95 % of its width was not broken at all, and the last fraction was cut off at the callout's edge.

Regression test: `AppProjectTextualPatchTests.testFractionAfterEarlierFractionsBreaksOntoANewLine` measures that formula at 95, 80 and 60 % of its width and checks that it is broken into lines no wider than the width.

## 3. `\underbrace` and `\overbrace`

`Sources/SwiftUIMath/Internal/Syntax/Atoms/HorizontalBrace.swift` and `Internal/Display/DisplayHorizontalBrace.swift` (new), `Internal/Syntax/AtomList.swift`, `Internal/Syntax/Parser.swift`, `Internal/Display/Typesetter.swift`, `Internal/Display/CGContext+DisplayNode.swift`: `\underbrace{…}_{label}` and `\overbrace{…}^{label}` are typeset. Upstream did not know either command, so a formula using one could not be parsed and Graphite showed its LaTeX source (Textual patch 5).

The brace is drawn as a stroked path as wide as what it spans: the math fonts' brace glyphs come in a few fixed widths (Latin Modern's widest is 4 em) and the font tables carry no horizontal assembly to build a longer one. Its proportions follow Latin Modern's glyph, about 0.32 em tall and 0.06 em thick, and it stands 0.2 em from what it spans. The label is set in script style below an underbrace or above an overbrace, centred, with the gaps of an operator's limits (`DisplayLargeOperator`); the other script, if any, is an ordinary script at the right. A brace is an ordinary atom for spacing and line breaking.

## 4. A hyphen in `\text` is a hyphen

`Sources/SwiftUIMath/Internal/Syntax/Parser.swift`: inside `\text{…}`, `-` is an ordinary hyphen. Upstream turned it into a minus sign with a binary operator's spaces, so `\text{wear-out}` read "wear − out". A `-` outside `\text` is still a minus.

Regression tests: `AppProjectTextualPatchTests.testUnderbraceAndOverbraceAreTypesetWithTheirLabels` and `testHyphenInsideTextIsAHyphen`.

## 5. A formula is drawn as shapes, not into a `Canvas`

`Sources/SwiftUIMath/Math.swift`, `Internal/Display/DisplayNode+Outlines.swift`: `Math` shows a formula as SwiftUI `Path` shapes, one per color, filled with the foreground style (or, in multicolor mode, the formula's own colors and the base color). `MathOutlines` walks the display tree as `CGContext.draw(_:foregroundColor:)` does, turning each glyph into its outline (`CTFontCreatePathForGlyph`, and Core Text's glyph runs for text) and each rule, radical bar and brace into the area its stroke covers. SwiftUI draws a `Canvas` through RenderBox, which starts a Metal device that held about 200 MB of graphics memory while a note with formulas scrolled. The outlines are vector, so a formula stays sharp in a PDF. On the Mac the outlines are also stroked by 1.4 % of the font size (`Math.glyphThickening`), because Core Text thickens glyphs as it draws them there (font smoothing) and a filled outline looked thinner: a purple formula on black at 1× had 25 and 35 fully colored pixels in its halves against 58 and 55 when Core Text drew it, and 42 to 78 with a stroke of 1.2 to 1.6 %. `CGContext+DisplayNode.swift` and `GraphicsContext+DisplayNode.swift` are no longer called; the outlines follow the first, and a change to how a node is drawn goes in both.

## 6. The TeX class of a symbol, for Textual

`Sources/SwiftUIMath/Math+SymbolClass.swift` (new): `Math.symbolClass(ofCommand:)` and `symbolClass(ofCharacter:)` (`@_spi(Textual)`) give the TeX class of a symbol (ordinary, large operator, binary operator, relation, open, close, punctuation) from the typesetter's own tables, its aliases included. Textual uses it to find where a line may break inside inline math (its patch 21) without a second list of operators. Test: `AppProjectTextualPatchTests.testInlineMathBreaksAfterOperatorsAndRelationsAtItsOuterLevelOnly`.

## 7. A space at the end of a formula counts in its width

`Sources/SwiftUIMath/Internal/Display/Typesetter.swift` (`createLineForMathList`): a list's width reaches the end of its last line, explicit spaces included, as a TeX box does. Upstream measured only its drawn parts, so `a +\>` was as wide as `a +`. Textual's pieces of inline math (its patch 21) end with their operator's space, and side by side were narrower than the formula drawn whole, the operators touching the next piece. Test: `AppProjectTextualPatchTests.testFormulaInPiecesCopiesOnceAndKeepsItsWidth`.

## 8. KaTeX's other arrows

`Sources/SwiftUIMath/Internal/Syntax/AtomFactory.swift`: the arrows KaTeX lists beyond the plain ones are relations, each drawn with its Unicode arrow, for every arrow Latin Modern Math has a glyph for: the squiggly arrows (`\rightsquigarrow`, `\leadsto`, `\leftrightsquigarrow`), hooks, tails, loops, curves and circles, harpoons and their pairs (`\rightleftharpoons`), doubled and tripled arrows, the struck-through arrows (`\nrightarrow`, `\nRightarrow`, …), `\Lsh`, `\Rsh`, `\multimap`, `\longmapsto`, and the aliases `\impliedby` and `\restriction`. Upstream knew only the plain arrows, so a formula with any of these could not be parsed and Graphite showed its LaTeX source: a figure caption's `$R_G \rightsquigarrow R_G/4$` read as source in the reading view. The dashed arrows (`\dashrightarrow`, `\dashleftarrow`) are left out: Latin Modern has no glyph for them.

Regression test: `AppProjectTextualPatchTests.testKaTeXArrowsAreTypesetAsOneRelation` typesets each arrow between two letters and checks it is about as wide as `\rightarrow`, and that the caption's formula becomes one attachment.
