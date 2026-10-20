import XCTest
import Observation
import GraphiteCore
@testable import GraphiteUI

/// The word read aloud in the reading view: a new word updates the text it leaves and the
/// text it enters, and no other.
@MainActor
final class ReadingWordCellsTests: XCTestCase {
    private func token(_ text: String, at location: Int) -> ReadAloudSourceToken {
        ReadAloudSourceToken(text: text, sourceRange: NSRange(location: location, length: text.utf16.count))
    }

    /// Three texts of the note, each with two words: the words start at 0, 20 and 40.
    private func threeTexts() -> [String: [ReadAloudSourceToken]] {
        [
            "first": [token("alpha", at: 0), token("beta", at: 6)],
            "second": [token("gamma", at: 20), token("delta", at: 26)],
            "third": [token("epsilon", at: 40), token("zeta", at: 48)],
        ]
    }

    /// Whether a cell's word was written since the watch began.
    private final class Watch: @unchecked Sendable {
        private(set) var wasWritten = false
        func record() { wasWritten = true }
    }

    private func watch(_ cell: ReadingWordCell) -> Watch {
        let watch = Watch()
        withObservationTracking({ _ = cell.range }, onChange: { watch.record() })
        return watch
    }

    /// Whether the cell's word was written while `body` ran.
    private func rangeWasWritten(in cell: ReadingWordCell, during body: () -> Void) -> Bool {
        let watch = watch(cell)
        body()
        return watch.wasWritten
    }

    func testAWordUpdatesOnlyTheTextItLeavesAndTheTextItEntersAndTheCurrentWord() throws {
        let cells = ReadingWordCells()
        let tokens = threeTexts()
        cells.index(tokens)
        let firstCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["first"])))
        let secondCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["second"])))
        let thirdCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["third"])))
        cells.show(NSRange(location: 6, length: 4))
        XCTAssertEqual(firstCell.range, NSRange(location: 6, length: 4))

        let thirdCellWatch = watch(thirdCell)
        let firstCellWritten = rangeWasWritten(in: firstCell) { cells.show(NSRange(location: 26, length: 5)) }

        XCTAssertTrue(firstCellWritten, "The text the word left is cleared.")
        XCTAssertNil(firstCell.range)
        XCTAssertEqual(secondCell.range, NSRange(location: 26, length: 5), "The text the word entered shows it.")
        XCTAssertEqual(cells.current.range, NSRange(location: 26, length: 5))
        XCTAssertFalse(thirdCellWatch.wasWritten, "A text the word neither left nor entered is not updated.")
        XCTAssertNil(thirdCell.range)
    }

    func testAWordInTheSameTextAsTheLastOneDoesNotTouchTheOtherTexts() throws {
        let cells = ReadingWordCells()
        let tokens = threeTexts()
        cells.index(tokens)
        let firstCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["first"])))
        let secondCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["second"])))
        cells.show(NSRange(location: 0, length: 5))

        let secondCellWatch = watch(secondCell)
        cells.show(NSRange(location: 6, length: 4))

        XCTAssertEqual(firstCell.range, NSRange(location: 6, length: 4))
        XCTAssertFalse(secondCellWatch.wasWritten)
    }

    func testShowingTheSameWordAgainWritesNothing() throws {
        let cells = ReadingWordCells()
        let tokens = threeTexts()
        cells.index(tokens)
        let firstCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["first"])))
        cells.show(NSRange(location: 0, length: 5))

        let wasWritten = rangeWasWritten(in: firstCell) { cells.show(NSRange(location: 0, length: 5)) }
        let currentWasWritten = rangeWasWritten(in: cells.current) { cells.show(NSRange(location: 0, length: 5)) }

        XCTAssertFalse(wasWritten)
        XCTAssertFalse(currentWasWritten)
    }

    func testNoWordClearsTheTextThatShowedOneAndALocationInNoTextShowsNowhere() throws {
        let cells = ReadingWordCells()
        let tokens = threeTexts()
        cells.index(tokens)
        let firstCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["first"])))
        cells.show(NSRange(location: 0, length: 5))

        cells.show(NSRange(location: 15, length: 2))
        XCTAssertNil(firstCell.range, "A location between texts leaves the earlier text.")
        XCTAssertEqual(cells.current.range, NSRange(location: 15, length: 2))

        cells.show(NSRange(location: 0, length: 5))
        cells.show(nil)
        XCTAssertNil(firstCell.range)
        XCTAssertNil(cells.current.range)
    }

    func testATextWithoutWordsHasNoCellAndANewBuildClearsTheCellsOfTextsThatWentAway() throws {
        let cells = ReadingWordCells()
        let tokens = threeTexts()
        cells.index(tokens)
        XCTAssertNil(cells.cell(forTextWith: []))
        let thirdCell = try XCTUnwrap(cells.cell(forTextWith: try XCTUnwrap(tokens["third"])))
        cells.show(NSRange(location: 40, length: 7))
        XCTAssertEqual(thirdCell.range, NSRange(location: 40, length: 7))

        cells.index(["first": try XCTUnwrap(tokens["first"])])

        XCTAssertNil(thirdCell.range, "The text of the earlier build is gone, so it shows no word.")
    }
}
