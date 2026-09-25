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

Remove this vendored copy and return to the upstream package once an upstream release contains equivalents of these changes.
