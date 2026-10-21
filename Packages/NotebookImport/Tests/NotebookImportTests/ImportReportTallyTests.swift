import Foundation
import XCTest
@testable import NotebookImport

/// The import report tally: plain entries once in first-reported order, counted kinds aggregated into one entry each.
final class ImportReportTallyTests: XCTestCase {
    func testAnEmptyTallyHasAnEmptyReport() {
        let tally = ImportReportTally()
        XCTAssertEqual(tally.report, [])
    }

    func testPlainEntriesAreKeptOnceInTheOrderTheyWereAdded() {
        var tally = ImportReportTally()
        tally.add(.paperRulingNotDrawn)
        tally.add(.backgroundFileMissing)
        tally.add(.paperRulingNotDrawn)
        tally.add(.backgroundFileMissing)
        XCTAssertEqual(tally.report, [.paperRulingNotDrawn, .backgroundFileMissing])
    }

    func testPlainEntriesComeBeforeCountedOnesWhateverTheOrderTheyWereReportedIn() {
        var tally = ImportReportTally()
        tally.count(.pencil)
        tally.add(.pageWithoutPaper)
        tally.count(.dashes)
        tally.add(.paperRulingNotDrawn)
        XCTAssertEqual(tally.report, [
            .pageWithoutPaper, .paperRulingNotDrawn, .pencilTextureNotKept(strokeCount: 1), .dashesNotKept(strokeCount: 1)
        ])
    }

    func testCountsAggregatePerKindInTheOrderEachKindWasFirstCounted() {
        var tally = ImportReportTally()
        tally.count(.tape)
        tally.count(.highlighter)
        tally.count(.tape)
        tally.count(.element(.picture))
        tally.count(.highlighter)
        tally.count(.highlighter)
        tally.count(.element(.picture))
        XCTAssertEqual(tally.report, [
            .tapeLeftOut(strokeCount: 2), .highlighterNotMultiplied(strokeCount: 3), .elementsNotYetConverted(kind: .picture, count: 2)
        ])
    }

    func testEveryCountedKindBecomesItsOwnReportEntry() {
        var tally = ImportReportTally()
        tally.count(.highlighter)
        tally.count(.pencil)
        tally.count(.tape)
        tally.count(.olderVaryingWidthInk)
        tally.count(.dashes)
        tally.count(.element(.shape))
        tally.count(.element(.textWithoutFrame))
        tally.count(.textStyle)
        tally.count(.stickyNote)
        tally.count(.textBoxNotPlaced)
        XCTAssertEqual(tally.report, [
            .highlighterNotMultiplied(strokeCount: 1), .pencilTextureNotKept(strokeCount: 1), .tapeLeftOut(strokeCount: 1),
            .olderVaryingWidthInkLeftOut(strokeCount: 1), .dashesNotKept(strokeCount: 1),
            .elementsNotYetConverted(kind: .shape, count: 1), .elementsNotYetConverted(kind: .textWithoutFrame, count: 1),
            .textStylesNotKept(runCount: 1), .stickyNotesAsTextBoxes(count: 1), .textBoxesNotPlaced(count: 1)
        ])
    }

    func testElementKindsAreCountedSeparately() {
        var tally = ImportReportTally()
        tally.count(.element(.textWithoutFrame))
        tally.count(.element(.shapeFill))
        tally.count(.element(.textWithoutFrame))
        XCTAssertEqual(tally.report, [
            .elementsNotYetConverted(kind: .textWithoutFrame, count: 2), .elementsNotYetConverted(kind: .shapeFill, count: 1)
        ])
    }
}
