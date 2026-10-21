import XCTest
@testable import GraphiteUI

/// A text view as `MarkdownEditorStyling` sees it, over a plain text storage: it counts how
/// often the selection is set, so a test can tell whether styling touched it. It works on
/// every platform, which the real text views of the iPad and the Mac do not.
@MainActor
final class StubStyledTextView: MarkdownStyledTextView {
    let styledTextStorage: NSTextStorage
    private(set) var selectionSetCount = 0
    private var selection: NSRange
    var isComposingText = false
    var renderedBlockColumnWidth: CGFloat = 400
    var renderedBlockPaneWidth: CGFloat = 400
    var typingAttributes: [NSAttributedString.Key: Any] = [:]

    var styledSelection: NSRange {
        get { selection }
        set {
            selectionSetCount += 1
            selection = newValue
        }
    }

    init(text: String, selection: NSRange = NSRange(location: 0, length: 0)) {
        styledTextStorage = NSTextStorage(string: text)
        self.selection = selection
    }

    /// Moves the selection as a person does, without counting it as styling's doing.
    func moveSelection(to newSelection: NSRange) {
        selection = newSelection
    }
}
