# Graphite changes to Textual 0.5.0

Upstream: https://github.com/gonzalezreal/textual at tag 0.5.0 (commit 01b51875a5406eefc95f52a058cb059e7bc94dc4). License: MIT (see LICENSE); third-party notices in LICENSE-3rdparty.csv. Upstream tests, examples and documentation are not vendored. Textual's SwiftUIMath dependency is Graphite's vendored copy (`Vendor/swiftui-math`, with its own `GRAPHITE-PATCHES.md`), not the remote package.

## 1. Math keeps its natural width

`Sources/Textual/Internal/Attachment/MathAttachment.swift`: inline math is measured without a width limit and drawn at its natural width (`fixedSize`). Upstream fits it to the proposed width. When a formula is the whole content of a table cell, the frame it receives is a fraction of a point narrower than the formula, so formulas such as `$k_n$` or `$x_n$` (letters with subscript kerning) line-broke inside the formula and rendered as garbled glyphs. Display math had the same problem (`E = mc^2` drew its exponent on a second line), so it is also measured and drawn at its natural width, and fitted to the proposed width only when it is wider than that by more than one point (`MathAttachment.naturalWidthTolerance`), the same tolerance the view draws with, so the size reserved is the size drawn.

## 2. List item styles can see the item's content

`Sources/Textual/StructuredText/Style/ListItemStyle.swift`, `Internal/StructuredText/UnorderedList.swift`, `Internal/StructuredText/OrderedList.swift`: `ListItemStyleConfiguration` gains a public `content` (the item's `AttributedSubstring`). Graphite's list item style uses it to draw a task's checkbox in place of the bullet, as Obsidian does.

## 3. Inline math for other text views

`Sources/Textual/InlineMathRendering.swift` (new): public `InlineMathRendering.metrics(for:fontSize:)` and `image(for:fontSize:color:scale:)`, which measure and draw a formula with the same font and typesetting as inline math in `StructuredText`. Graphite's Live Preview editor uses them to draw `$…$` formulas among its own text. They wrap SwiftUIMath API that is only available to Textual (`@_spi(Textual)`).

## 4. Obsidian's inline math delimiters

`Sources/Textual/Internal/MarkdownParser/PatternTokenizer.swift`: `$…$` is inline math only when no space follows the opening `$` or precedes the closing one, and no digit follows the closing one, as in Obsidian. Upstream treats any pair of dollar signs as math, so "It costs $5 and $10" rendered "5 and " as a formula.

## 5. Formulas that cannot be typeset stay as text

`Sources/Textual/MarkdownParser/SyntaxExtension.swift`, `Internal/Attachment/MathAttachment.swift`: when SwiftUIMath cannot parse a formula (for example an unknown command or environment), the math extension leaves its `$…$` source as text. Upstream made an attachment that measured zero and showed only the object replacement glyph.

## 6. No isolated-conformance warnings from attachments

`Sources/Textual/Internal/Attachment/WithAttachments.swift`: the main-actor model that resolves attachments is a top-level type (`AttachmentResolutionModel`) instead of being nested in the generic `WithAttachments<Content>` view. Nested, it carried the view's `Content: View` conformance, and Swift 6.2 warned five times that the conformance "may be isolated and cannot be passed to main actor-isolated context". Behavior is unchanged.

## 7. Tables fit the width they are offered

`Sources/Textual/Internal/StructuredText/TableColumnsLayout.swift` and `TableCellWidthProbe.swift` (new), `Internal/StructuredText/Table.swift`, `Internal/StructuredText/TableCell.swift`, `Internal/TextFragment/TextFragment.swift`, `Internal/TextFragment/TextBuilder.swift`: a table is laid out by `TableColumnsLayout` in place of SwiftUI's `Grid`. Upstream's table never adapted to its width in a usable way. `Grid` gives a column the width its widest cell asks for, and a `Text` accepts any width down to one letter per line, so a table offered less width than its content either kept its full width or broke words apart. An image in a cell was sized to the whole text container, not to its column, so three images side by side made a table three containers wide.

The layout sizes columns as a web browser sizes a table:

- A column is at most as wide as its widest cell on one line, and at least as wide as the widest word, formula, or smallest image in it.
- A table offered a width between those limits gives each column the same share of the width it can give up. Widths are whole points.
- A table offered less than its narrowest width keeps that width, so the style's scroll container scrolls.

The limits are measured on hidden copies of a cell (`TableCellWidthProbe`), because the visible cell cannot report them: the narrowest on a copy with each word on its own line and each attachment at its smallest, the widest on a copy on one line with each attachment at its full size. A cell of one word or formula needs no copy, and only a cell whose attachments shrink has the second one. The copies are plain `Text`, hidden from hit testing, accessibility and the text layout preference, so they take no part in selection or links.

A cell's content now fills its column (the column's alignment is applied inside the cell, where `Grid` aligned a cell of its content's width). A cell whose attachments fit the width they are offered passes its content width, in whole points, to its `TextFragment` through the `attachmentContainerWidth` environment value, and the fragment sizes attachments for that width in place of the text container's. `TextBuilder` accepts the proposal when it is created, so a fragment built again when an image loads starts at the column's size.

A table style decides the width to offer. Upstream's `Overflow` scroll container offers none along its scrolling direction, so a style that wants fitting tables offers the container's width itself, as Graphite's `ObsidianTableStyle` does.

## 8. Empty table cells keep their place

`Sources/Textual/Internal/StructuredText/Table.swift`: `Table.cellContents(in:tableIntent:columnCount:)` gives every row every column. A cell with nothing in it has no text, so the attributed string has no run for it, and a row of such cells has none either. Upstream laid out the cells that have runs one after another, so the header `| | Cutoff | Linear |` put "Cutoff" over the first column, and an empty header row (a common way to write a table without headings) made the first row of data the header. A cell now goes to the row and column its presentation intent names, and a place without a run gets an empty cell. `TableLayout` still receives bounds for every row and column, so the dividers a style draws stay in place.

## 9. Preserve explicit formula colors

`Sources/Textual/Internal/Attachment/MathAttachment.swift` and `Sources/Textual/InlineMathRendering.swift`: use SwiftUIMath's multicolor rendering for explicit LaTeX colors rather than discarding them in monochrome mode. Uncolored attachments keep the inherited foreground style; inline images use their supplied text color as the base. Graphite's `LaTeXCompatibility` separately converts scoped MathJax color declarations before these renderers receive them. A regression test parses and renders the reported purple rank equation and checks colored pixels in both halves.

## 10. Controls inside selectable text receive touches

`Sources/Textual/TextInteractionExclusion.swift` (new): public `textual.excludedFromTextInteraction()` reports a view's frame to the text selection overlay, which leaves it out of hit testing, as the overlay already does for the scrollable regions of `Overflow` (`OverflowFrameKey`). With text selection on, the overlay covers the whole text and takes every touch and click, so a control a style draws inside `StructuredText` was never reached. Graphite's list item style draws a task's checkbox as a button in place of the bullet and uses it.

## 11. Display math for views that lay out a formula themselves

`Sources/Textual/DisplayMathRendering.swift` (new), `Internal/Attachment/MathAttachment.swift`: public `DisplayMathRendering.metrics(for:fontSize:fittingWidth:)` measures a formula as block math is typeset, on one line or broken to a width, and `DisplayMathView` draws it at that size. Graphite lays out a formula with its equation numbers with them. The view draws the formula as a canvas symbol, as an attachment is drawn: a view's frame is rounded to whole pixels, and in a frame a fraction of a point narrower than the formula the typesetter broke `E = mc^2` into two lines, of which only the exponent showed. `NaturalWidthWhenItFits` is no longer private to `MathAttachment.swift`, so the view shares it.

## 12. Temporary reading highlights with exact source locations

`Sources/Textual/ReadingHighlight.swift` (new), `Internal/TextFragment/TextBuilder.swift`, `Internal/TextFragment/TextFragment.swift`: a host can attach a validated `ReadingSourceRangeAttribute` to each word or mathematical attachment. `TextBuilder` carries it into SwiftUI's public `Text.Layout` runs. The reading-highlight modifier draws noninteractive backgrounds from the matching run bounds and optionally reports geometry in the host's named coordinate space. It does not replace selection, change document text, search for repeated words, or reparse attributed text for every spoken-word callback. `AnyAttachment.isMathematics` lets the host distinguish formulas from images while validating its complete source-to-rendered token sequence. Graphite tests actual native layout geometry, repeated-word positions, visible highlight pixels, clearing on Stop, and rendered table/math/callout use. Formula attachments report whole-expression bounds, not individual mathematical terms.

## 13. Rounded backgrounds for runs

`Sources/Textual/RoundedRunBackground.swift` (new), `Internal/TextFragment/TextBuilder.swift`, `Internal/TextFragment/TextFragment.swift`: a host can attach a public `RoundedRunBackgroundAttribute` (a color, a corner radius, a padding and an optional border) to runs of its attributed string. `TextBuilder` carries it into `Text.Layout` runs as it carries the reading-highlight ranges, and the fragment draws one rounded shape per line behind the marked runs, joining neighbouring runs with the same background. The radius is limited to half the shape's height and width, so a large radius gives round ends. SwiftUI's own run background is a plain rectangle; Graphite uses this for an Obsidian theme's tag pills and rounded highlights.

## 14. A host tokenizer for code blocks

`Sources/Textual/CodeSegmenter.swift` (new), `Internal/Highlighter/HighlightedTextFragment.swift`: public `StructuredText.CodeSegment` and `textual.codeSegmenter(_:)`, a closure that splits a code block's text into segments with token types, or returns nil for a language it does not know. When it answers, the block is highlighted with those segments synchronously, kept while the block's text, language, highlighter theme and text environment stay the same; otherwise Textual's own Prism tokenizer runs, asynchronously, as upstream. Graphite's tokenizer is pure Swift and covers languages Prism's bundle lacks (C++, VHDL, Verilog, assembly, MATLAB, LaTeX, …), and colors code the same way as Graphite's editor. Upstream tokenized every block asynchronously in JavaScriptCore, so a block first showed uncolored.

## 15. Math patterns compiled once per thread

`Sources/Textual/Internal/MarkdownParser/PatternTokenizer.swift`: `Pattern.mathBlock` and `Pattern.mathInline` return patterns made once per thread (`CompiledMathPatterns`), with the same regular expressions. Upstream made a new value for every access, and a Swift regular expression literal is parsed and compiled again for each new value; the math syntax extension asks for both for every text it parses, which was about a third of the time spent parsing a rendered block's Markdown (Time Profiler, Live Preview scrolling, 2026-10-17). A `Regex` is not `Sendable` and Markdown is also parsed off the main thread, so each thread keeps its own copy in its thread dictionary.


## 16. Tables scroll only when wider than the column

`Sources/Textual/StructuredText/Style/Overflow.swift`: `Overflow(scrollsOnlyWhenWider:content:)` shows its content without a scroll view while the content fits the width it is offered, and moves it into the horizontal scroll view only when it is wider (by more than half a point); content in the scroll view leaves it once the scroll view is wider than the width the content was found wider than, as when the window grows (comparing the content's own widths in the scroll view switched a table in and out without end, since it passes through other widths there as it is laid out again). The space is measured with a layout that takes exactly the width offered: a flexible frame grew to wider content, which then never measured wider and was centered over the column's edges. Graphite's `ObsidianTableStyle` uses it: every table was in a scroll view, which cost layout and scrolling work for tables that never scroll, and took swipes meant for the note. Code block styles keep the plain initializer, since code wraps instead of growing wider and would never be measured wider. The horizontal scroll view also no longer moves vertically (`scrollBounceBehavior(.basedOnSize, axes: .vertical)`): its content's height, rounded to pixels, could exceed its frame by a fraction, and a swipe moved the table up and down.

## 17. Table overlays that take touches

`Sources/Textual/View+Textual.swift`: `textual.interactiveTableOverlay(content:)` is `tableOverlay(content:)` without `allowsHitTesting(false)`. Graphite's Live Preview places a cell editor and its tap target over a table's cells with it, as Obsidian edits a table's cells in place.

## 18. Attachments at hand are drawn at once

`Sources/Textual/Attachment/AttachmentLoader.swift`, `Internal/Attachment/WithAttachments.swift`: `AttachmentLoader` gains `readyAttachment(for:text:environment:)`, the attachment for a URL when the loader has it without loading (nil by default, as upstream). `WithAttachments` draws a text with those attachments until its asynchronous resolution finishes. Graphite's vault image loader answers from the reading view's image cache, so an image the cache holds shows in the first drawing of its text: a note exported to PDF draws each block a few times in quick succession, which do not wait for the asynchronous load, and a text scrolled back into view no longer shows without its images for a moment.

## 19. No `Canvas` in text: backgrounds, attachments and display math are views

`Sources/Textual/RoundedRunBackground.swift`, `Internal/Attachment/AttachmentView.swift`, `DisplayMathRendering.swift`: a run's rounded background is a `RoundedRectangle` per line, an attachment (an inline formula, an emoji) is its own view framed to its run's typographic bounds, and `DisplayMathView` shows SwiftUIMath's `Math` directly instead of drawing it as a canvas symbol. SwiftUI draws a `Canvas` through RenderBox, which starts a Metal device: a note's rendered blocks then held about 200 MB of graphics memory while the note scrolled on the Mac (twelve canvases in a window peak at 245 MB, the same rows drawn as shapes at 18 MB; measured 2026-10-21). The canvas symbol kept a display formula on one line in a frame a fraction of a point narrower than it; SwiftUIMath's typesetter keeps it on one line within a point of its natural width itself (`DisplayProvider.lineBreakTolerance`). Rendered beside the canvas versions, a formula, a table with inline math and code, and a callout match within anti-aliasing at glyph edges.

## 20. The selection model takes every layout of the text

`Sources/Textual/Internal/TextInteraction/Shared/TextSelectionInteraction.swift`, `TextSelectionModel.swift`, `TextSelectionCoordinator.swift`, `UIKit/UIKitTextLayoutModelUpdater.swift` and `AppKit/AppKitTextLayoutModelUpdater.swift` (new): the text's layouts reach the `TextSelectionModel` through a hidden platform view's `updateUIView` / `updateNSView`, which SwiftUI calls at every update with the latest values. Upstream passed them with `onChange`, and SwiftUI runs an `onChange` action at most once per frame ("onChange(of: AnyTextLayoutCollection) action tried to update multiple times per frame"). A text's layouts change several times in the frame it first appears in: each fragment is first an empty `Text` until its `TextBuilder` exists. The model kept the first, empty, layouts (no lines, so no fragment), and found no link and no text under a tap until some later change laid the text out again, such as opening and closing Settings. In Graphite's reading view on the iPad, a tap on a link right after switching from Live Preview, or after opening a note in the reading view, followed nothing. `.task(id:)` has the same limit (it is built on `onChange`), so it is not an alternative. The same change is proposed upstream in [gonzalezreal/textual#71](https://github.com/gonzalezreal/textual/pull/71).

A view update must not change observed state, so carrying a selection over to new layouts updates the stored range without notifying observers: it is the same text, the views that draw the selection read it again with their new layouts, and the platform view is told through `selectionWillChange` and `selectionDidChange`. The coordinator's list of registered models is not observed, since a model registers during an update and no view reads the list. Test: the hosted iPad `ReadingLinkFollowingTests.testTapOnALinkRightAfterSwitchingFromLivePreviewFollowsIt` (a tap delivered through UIKit's event path on a link of the reading view, right after the switch from Live Preview), which fails without the patch. A package test cannot show the defect: on the Mac, a selectable text hosted in a window, alone or as the reading view's text, with one paragraph or forty, has its layouts in one update, so `onChange` passed them too.

Remove this vendored copy and return to the upstream package once an upstream release contains equivalents of these changes.
