import XCTest
@testable import GraphiteUI

/// The attribute names the Markdown styler writes and the Live Preview layout fragment
/// reads: a renamed key leaves bullets, checkboxes, quote bars and theme shapes undrawn
/// without any compile error.
@MainActor
final class ConcealedReplacementAttributeKeysTests: XCTestCase {
    func testTheStylerAndTheFragmentShareTheseAttributeNames() {
        XCTAssertEqual(ConcealedReplacement.attributeKey.rawValue, "GraphiteConcealedReplacement")
        XCTAssertEqual(ConcealedReplacement.colorAttributeKey.rawValue, "GraphiteConcealedReplacementColor")
        XCTAssertEqual(ConcealedReplacement.mathAttributeKey.rawValue, "GraphiteConcealedReplacementMath")
        XCTAssertEqual(ConcealedReplacement.roundedBackgroundKey.rawValue, "GraphiteThemedRoundedBackground")
        XCTAssertEqual(ConcealedReplacement.checkboxStyleKey.rawValue, "GraphiteThemedCheckbox")
        XCTAssertEqual(ConcealedReplacement.headingOrnamentKey.rawValue, "GraphiteThemedHeadingOrnament")
        XCTAssertEqual(ConcealedReplacement.quoteBackgroundKey.rawValue, "GraphiteThemedQuoteBackground")
        XCTAssertEqual(MarkdownTextStyler.codeLineStateKey.rawValue, "GraphiteCodeLineState")
    }

    func testTheReplacementKindsAreStoredUnderTheseNames() {
        let storedNames: [(ConcealedReplacement, String)] = [
            (.bullet, "bullet"), (.uncheckedTask, "uncheckedTask"), (.checkedTask, "checkedTask"),
            (.subpathSeparator, "subpathSeparator"), (.inlineMath, "inlineMath"), (.quoteBar, "quoteBar"),
        ]
        for (replacement, storedName) in storedNames {
            XCTAssertEqual(replacement.rawValue, storedName)
            XCTAssertEqual(ConcealedReplacement(rawValue: storedName), replacement)
        }
        XCTAssertEqual(storedNames.count, 6)
        XCTAssertNil(ConcealedReplacement(rawValue: "checkbox"))
    }
}
