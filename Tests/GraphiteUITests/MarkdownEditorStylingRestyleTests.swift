import XCTest
@testable import GraphiteUI

/// A restyle puts the selection back only when styling moved it, and resets what is typed
/// next to plain text.
@MainActor
final class MarkdownEditorStylingRestyleTests: XCTestCase {
    private func makeStyling() -> MarkdownEditorStyling {
        MarkdownEditorStyling(configuration: EditorConfiguration(), propertiesSource: .afterEditSource(isShown: false), detachedViewsBudgetMegabytes: 1)
    }

    private static let text = "# Heading\nSome **bold** text and `code`\nLast line"

    func testARestyleWithAStationaryCursorNeverSetsTheSelection() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.text, selection: NSRange(location: 12, length: 0))
        styling.restyle(NSRange(location: 0, length: (Self.text as NSString).length), in: textView)
        XCTAssertEqual(textView.selectionSetCount, 0)
        XCTAssertEqual(textView.styledSelection, NSRange(location: 12, length: 0))
        styling.restyle(NSRange(location: 10, length: 5), in: textView)
        XCTAssertEqual(textView.selectionSetCount, 0)
    }

    func testARestyleSetsTheSelectionBackOnlyWhenStylingMovedIt() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.text, selection: NSRange(location: 12, length: 3))
        // A text view whose selection moves when its attributes change, as UIKit's can.
        let observer = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification,
                                                              object: textView.styledTextStorage, queue: nil) { _ in
            MainActor.assumeIsolated { textView.moveSelection(to: NSRange(location: 0, length: 0)) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        styling.restyle(NSRange(location: 0, length: 9), in: textView)
        XCTAssertEqual(textView.selectionSetCount, 1)
        XCTAssertEqual(textView.styledSelection, NSRange(location: 12, length: 3))
    }

    func testARestyleResetsWhatIsTypedNextToPlainText() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.text)
        textView.typingAttributes = [.foregroundColor: PlatformColor.red]
        styling.restyle(NSRange(location: 0, length: 9), in: textView)
        XCTAssertTrue(NSDictionary(dictionary: textView.typingAttributes).isEqual(to: styling.baseAttributes))
        XCTAssertNil(textView.typingAttributes[.backgroundColor])
    }

    func testARestyleOfAnEmptyNoteChangesNothing() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: "", selection: NSRange(location: 0, length: 0))
        textView.typingAttributes = [.foregroundColor: PlatformColor.red]
        styling.restyle(NSRange(location: 0, length: 0), in: textView)
        XCTAssertEqual(textView.selectionSetCount, 0)
        XCTAssertNotNil(textView.typingAttributes[.foregroundColor])
        XCTAssertTrue(NSDictionary(dictionary: textView.typingAttributes).isEqual(to: [NSAttributedString.Key.foregroundColor: PlatformColor.red]))
    }

    func testRestylingEverythingResetsWhatIsTypedNextToo() {
        let styling = makeStyling()
        let textView = StubStyledTextView(text: Self.text, selection: NSRange(location: 3, length: 0))
        textView.typingAttributes = [.foregroundColor: PlatformColor.red]
        styling.restyleEverything(in: textView)
        XCTAssertTrue(NSDictionary(dictionary: textView.typingAttributes).isEqual(to: styling.baseAttributes))
        XCTAssertEqual(textView.selectionSetCount, 0)
    }
}
