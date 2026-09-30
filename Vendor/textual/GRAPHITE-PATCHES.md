# Graphite changes to Textual 0.5.0

Upstream: https://github.com/gonzalezreal/textual at tag 0.5.0 (commit 01b51875a5406eefc95f52a058cb059e7bc94dc4). License: MIT (see LICENSE); third-party notices in LICENSE-3rdparty.csv. Upstream tests, examples and documentation are not vendored.

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

Remove this vendored copy and return to the upstream package once an upstream release contains equivalents of these changes.
