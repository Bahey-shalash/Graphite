import Foundation
import Markdown

/// The only way into swift-markdown's parser. Text nested deeper than
/// `MarkdownNesting.maximumContainerDepth` never reaches it, because the parser's recursion
/// would exhaust the thread's stack (see `MarkdownNesting`).
enum BoundedMarkdownParser {
    /// The parsed document, or nil when the text is nested too deeply to parse safely.
    static func document(parsing text: String) -> Document? {
        MarkdownNesting.exceedsSafeDepth(text) ? nil : Document(parsing: text)
    }
}
