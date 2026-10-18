import XCTest
@testable import GraphiteUI

/// When the content of a canvas card longer than the card scrolls.
final class CanvasCardContentScrollingTests: XCTestCase {
    func testTouchScrollsOnlyTheCardTappedInRead() {
        XCTAssertTrue(CanvasCardContentScrolling.isEnabled(isFocused: true, isWriting: false, hasPointerScrolling: false))
        XCTAssertFalse(CanvasCardContentScrolling.isEnabled(isFocused: false, isWriting: false, hasPointerScrolling: false),
                       "A drag on a card that was not tapped moves the board.")
        XCTAssertFalse(CanvasCardContentScrolling.isEnabled(isFocused: true, isWriting: true, hasPointerScrolling: false))
    }

    func testPointerScrollsAnyCardInReadWithoutATapFirst() {
        XCTAssertTrue(CanvasCardContentScrolling.isEnabled(isFocused: false, isWriting: false, hasPointerScrolling: true))
        XCTAssertTrue(CanvasCardContentScrolling.isEnabled(isFocused: true, isWriting: false, hasPointerScrolling: true))
    }

    func testNothingScrollsWhileWritingBecauseADragMovesTheCard() {
        XCTAssertFalse(CanvasCardContentScrolling.isEnabled(isFocused: false, isWriting: true, hasPointerScrolling: true))
        XCTAssertFalse(CanvasCardContentScrolling.isEnabled(isFocused: true, isWriting: true, hasPointerScrolling: true))
    }

    #if os(macOS)
    /// The Mac host registers no tap, so no card is ever tapped there.
    func testTheMacScrollsACardThatWasNeverTapped() {
        XCTAssertTrue(CanvasCardContentScrolling.platformHasPointerScrolling)
        XCTAssertTrue(CanvasCardContentScrolling.isEnabled(isFocused: false, isWriting: false))
    }
    #endif
}
