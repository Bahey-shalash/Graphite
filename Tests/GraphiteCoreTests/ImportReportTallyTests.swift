import Foundation
import XCTest
@testable import GraphiteCore

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
        tally.count(.element(.typedText))
        XCTAssertEqual(tally.report, [
            .highlighterNotMultiplied(strokeCount: 1), .pencilTextureNotKept(strokeCount: 1), .tapeLeftOut(strokeCount: 1),
            .olderVaryingWidthInkLeftOut(strokeCount: 1), .dashesNotKept(strokeCount: 1),
            .elementsNotYetConverted(kind: .shape, count: 1), .elementsNotYetConverted(kind: .typedText, count: 1)
        ])
    }

    func testElementKindsAreCountedSeparately() {
        var tally = ImportReportTally()
        tally.count(.element(.textBox))
        tally.count(.element(.stickyNote))
        tally.count(.element(.textBox))
        XCTAssertEqual(tally.report, [
            .elementsNotYetConverted(kind: .textBox, count: 2), .elementsNotYetConverted(kind: .stickyNote, count: 1)
        ])
    }
}
