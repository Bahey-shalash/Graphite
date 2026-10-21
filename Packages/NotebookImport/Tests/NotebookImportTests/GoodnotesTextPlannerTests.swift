import CoreGraphics
import Foundation
import XCTest
@testable import NotebookImport

/// Goodnotes' typed text planned as text boxes, on values like the samples' (`Docs/Goodnotes-format.md`, "Text boxes"):
/// everything in a box multiplied by its scale and by 6/11 point per unit.
final class GoodnotesTextPlannerTests: XCTestCase {
    private static let pointsPerUnit = 6.0 / 11.0
    private static let accuracy = 1e-9
    private static let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let red = NotebookImportColor(red: 0.953, green: 0.247, blue: 0.247, alpha: 1)
    private static let defaults = GoodnotesRichText.Attributes(color: black, link: nil, fontName: "Helvetica Neue", sizeInUnits: 24)

    func testATextBoxIsItsCornerWidthInsetAndFontSizeInPointsTimesItsScale() throws {
        let run = GoodnotesRichText.Attributes(color: Self.red, link: nil, fontName: "Georgia", sizeInUnits: 36)
        let textBox = GoodnotesTextBox(origin: CGPoint(x: 77.5, y: 827.8), rotationRadians: 0, scale: 2, size: CGSize(width: 131, height: 41),
                                       insets: [10, 10, 10, 10], richText: GoodnotesRichText(text: "Red two", runs: [run], defaultAttributes: Self.defaults))
        var tally = ImportReportTally()
        let planned = try XCTUnwrap(GoodnotesTextPlanner.textBox(for: textBox, tally: &tally))
        XCTAssertEqual(planned.origin.x, 77.5 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.origin.y, 827.8 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.width, 131 * 2 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertNil(planned.height, "a text box is as tall as its text")
        XCTAssertEqual(planned.padding, 10 * 2 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertNil(planned.fillColor)
        XCTAssertEqual(planned.content, .runs([ImportedTextRun(text: "Red two", font: .family("Georgia"), sizeInPoints: 36 * 2 * Self.pointsPerUnit,
                                                              color: Self.red, isUnderlined: false, link: nil)]))
        XCTAssertEqual(tally.report, [])
    }

    func testAnUnsetRunTakesTheDefaultsFontAndSizeAndKeepsItsLinkAndAngle() throws {
        let run = GoodnotesRichText.Attributes(color: nil, link: "https://example.com/graphite", fontName: nil, sizeInUnits: nil)
        let textBox = GoodnotesTextBox(origin: .zero, rotationRadians: .pi / 2, scale: 1, size: CGSize(width: 98, height: 29), insets: nil,
                                       richText: GoodnotesRichText(text: "Link here", runs: [run], defaultAttributes: Self.defaults))
        var tally = ImportReportTally()
        let planned = try XCTUnwrap(GoodnotesTextPlanner.textBox(for: textBox, tally: &tally))
        XCTAssertEqual(planned.rotationRadiansClockwise, .pi / 2)
        XCTAssertEqual(planned.padding, 10 * Self.pointsPerUnit, accuracy: Self.accuracy, "Goodnotes' inset of 10 units when none is stored")
        guard case .runs(let runs) = planned.content else { return XCTFail("expected runs") }
        XCTAssertEqual(runs.first?.font, .family("Helvetica Neue"))
        XCTAssertEqual(try XCTUnwrap(runs.first?.sizeInPoints), 24 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(runs.first?.color, Self.black)
        XCTAssertEqual(runs.first?.link, URL(string: "https://example.com/graphite"))
    }

    func testSeveralRunsAndASeeThroughColourAreCountedAsStylesNotKept() throws {
        let translucent = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        let runs = [GoodnotesRichText.Attributes(color: translucent, link: nil, fontName: nil, sizeInUnits: nil),
                    GoodnotesRichText.Attributes(color: Self.red, link: nil, fontName: "Georgia", sizeInUnits: 30)]
        var tally = ImportReportTally()
        let planned = GoodnotesTextPlanner.runs(of: GoodnotesRichText(text: "Two looks", runs: runs, defaultAttributes: Self.defaults),
                                                pointsPerUnit: Self.pointsPerUnit, tally: &tally)
        XCTAssertEqual(planned.map(\.text), ["Two looks"], "the whole text in the first run's look")
        XCTAssertEqual(planned.first?.color, translucent)
        XCTAssertEqual(tally.report, [.textStylesNotKept(runCount: 2)])
    }

    func testAStickyNoteIsAFilledBoxOfItsSizeAndIsCounted() {
        let paper = NotebookImportColor(red: 0.98, green: 0.906, blue: 0.471, alpha: 1)
        let stickyNote = GoodnotesStickyNote(origin: CGPoint(x: 256.6, y: 509.8), size: CGSize(width: 256, height: 256), paperColor: paper,
                                             richText: GoodnotesRichText(text: "Sticky one", runs: [], defaultAttributes: Self.defaults),
                                             authorName: "Author")
        var tally = ImportReportTally()
        let planned = GoodnotesTextPlanner.textBox(for: stickyNote, tally: &tally)
        XCTAssertEqual(planned.width, 256 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(try XCTUnwrap(planned.height), 256 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.fillColor, paper)
        XCTAssertEqual(planned.padding, GoodnotesTextPlanner.stickyNoteInsetInUnits * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(tally.report, [.stickyNotesAsTextBoxes(count: 1)])
    }

    func testAnOlderTextBoxKeepsItsRTFAndIsInsetByItsTextArea() {
        let frame = CGRect(x: 100, y: 200, width: 300, height: 80)
        let textBox = GoodnotesRTFTextBox(frame: frame, textFrame: frame.insetBy(dx: 10, dy: 10), rtf: "{\\rtf1 Hello}")
        let planned = GoodnotesTextPlanner.textBox(for: textBox)
        XCTAssertEqual(planned.content, .rtf("{\\rtf1 Hello}", pointsPerUnit: Self.pointsPerUnit))
        XCTAssertEqual(planned.origin.x, 100 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.width, 300 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(planned.padding, 10 * Self.pointsPerUnit, accuracy: Self.accuracy)
    }

    func testEmptyTextHasNoRuns() {
        var tally = ImportReportTally()
        XCTAssertEqual(GoodnotesTextPlanner.runs(of: GoodnotesRichText(text: "", runs: [], defaultAttributes: nil), pointsPerUnit: 1, tally: &tally), [])
    }
}
