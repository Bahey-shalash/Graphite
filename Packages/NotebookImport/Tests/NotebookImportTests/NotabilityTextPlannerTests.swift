import CoreGraphics
import Foundation
import XCTest
@testable import NotebookImport

/// Notability's typed text planned as text that flows from the top of the first page (`Docs/Notability-format.md`,
/// "Typed text"), on values like the typed-text sample's: Helvetica Neue 12, then bold 20 in red.
final class NotabilityTextPlannerTests: XCTestCase {
    private static let pointsPerUnit = 612.0 / 572.0
    private static let accuracy = 1e-9
    private static let letterPageSize = CGSize(width: 612, height: 803.25)
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let red = NotebookImportColor(red: 0.929, green: 0.212, blue: 0.141, alpha: 1)

    private static func run(_ location: Int, _ length: Int, font: String? = "HelveticaNeue", size: Double? = 12, color: NotebookImportColor? = black,
                            isUnderlined: Bool = false, isStruckThrough: Bool = false, lineSpacing: Double? = nil,
                            baselineOffset: Double? = nil) -> NotabilityTextRun {
        NotabilityTextRun(utf16Location: location, utf16Length: length, fontName: font, fontSize: size, color: color, isUnderlined: isUnderlined,
                          isStruckThrough: isStruckThrough, lineSpacing: lineSpacing, baselineOffset: baselineOffset)
    }

    func testRunsAreCutAtTheirRangesInTheirFontsSizesAndColours() throws {
        let text = NotabilityTypedText(text: "Typed text one\nRed bold twenty",
                                       runs: [Self.run(0, 15), Self.run(15, 15, font: "HelveticaNeue-Bold", size: 20, color: Self.red, isUnderlined: true)])
        var tally = ImportReportTally()
        let runs = NotabilityTextPlanner.runs(of: text, pointsPerUnit: Self.pointsPerUnit, tally: &tally)
        XCTAssertEqual(runs.map(\.text), ["Typed text one\n", "Red bold twenty"])
        XCTAssertEqual(runs.map(\.font), [.postScriptName("HelveticaNeue"), .postScriptName("HelveticaNeue-Bold")])
        XCTAssertEqual(runs[0].sizeInPoints, 12 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(runs[1].sizeInPoints, 20 * Self.pointsPerUnit, accuracy: Self.accuracy)
        XCTAssertEqual(runs.map(\.color), [Self.black, Self.red])
        XCTAssertEqual(runs.map(\.isUnderlined), [false, true])
        XCTAssertEqual(tally.report, [])
    }

    func testTextNoRunCoversTakesTheLookBeforeItOrTheDefault() {
        let text = NotabilityTypedText(text: "abcdefgh", runs: [Self.run(2, 2, size: 30)])
        var tally = ImportReportTally()
        let runs = NotabilityTextPlanner.runs(of: text, pointsPerUnit: 1, tally: &tally)
        XCTAssertEqual(runs.map(\.text), ["ab", "cd", "efgh"])
        XCTAssertEqual(runs.map(\.sizeInPoints), [12, 30, 30])
        XCTAssertEqual(runs.first?.font, .postScriptName("HelveticaNeue"))
    }

    func testStrikeThroughRaisedTextLineSpacingAndSeeThroughColourAreCounted() {
        let translucent = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 0.4)
        let text = NotabilityTypedText(text: "abcdefghij", runs: [
            Self.run(0, 2, isStruckThrough: true), Self.run(2, 2, baselineOffset: 3), Self.run(4, 2, lineSpacing: 6), Self.run(6, 2, color: translucent),
            Self.run(8, 2, lineSpacing: 0, baselineOffset: 0)
        ])
        var tally = ImportReportTally()
        _ = NotabilityTextPlanner.runs(of: text, pointsPerUnit: 1, tally: &tally)
        XCTAssertEqual(tally.report, [.textStylesNotKept(runCount: 4)])
    }

    func testTheTextFlowsFromTheTopOfThePageBetweenEqualMarginsOntoPagesOfThePaper() throws {
        let text = NotabilityTypedText(text: "Words", runs: [Self.run(0, 5)])
        var tally = ImportReportTally()
        let flowing = try XCTUnwrap(NotabilityTextPlanner.flowingText(of: text, pageSize: Self.letterPageSize, pointsPerUnit: Self.pointsPerUnit,
                                                                      continuationBackground: .plainColor(Self.white), tally: &tally))
        XCTAssertEqual(flowing.left, NotabilityPageGeometry.leftInsetPoints)
        XCTAssertEqual(flowing.top, 0)
        XCTAssertEqual(flowing.width, 612 - 2 * NotabilityPageGeometry.leftInsetPoints, accuracy: Self.accuracy)
        XCTAssertEqual(flowing.continuationPageSize, Self.letterPageSize)
        XCTAssertEqual(flowing.continuationBackground, .plainColor(Self.white))
        XCTAssertNil(NotabilityTextPlanner.flowingText(of: NotabilityTypedText(text: "", runs: []), pageSize: Self.letterPageSize, pointsPerUnit: 1,
                                                       continuationBackground: .plainColor(Self.white), tally: &tally))
    }

    func testAReflowableNoteIsLaidOutAtTheMacsWidthAndSaysSo() throws {
        let paper = NotabilityPaper(identifier: .legacyWhite, size: .letter, orientation: .portrait, sizingBehaviour: nil, lineStyle: nil)
        let geometry = NotabilityPageGeometry(pageWidthInUnits: NotabilityPageGeometry.macPageWidthInUnits, paper: paper)
        let note = NotabilityNote(name: nil, sessionFormatVersion: 9, applicationVersion: nil, paper: paper, reflowState: .reflowable,
                                  pageGeometry: geometry, shapes: [], pictures: [], typedText: NotabilityTypedText(text: "Words", runs: [Self.run(0, 5)]),
                                  importedPDFPages: [], recordings: [], playbackEvents: [])
        let outcome = NotabilityPagePlanner.plan(NotabilityPage(pageNumber: 1, topInUnits: 0, curves: [], shapes: [], pictures: []), note: note)
        guard case .planned(let plan) = outcome else { return XCTFail("expected a planned page") }
        XCTAssertEqual(plan.report, [.pageWidthAssumed])
        XCTAssertEqual(try XCTUnwrap(plan.flowingText?.runs.first?.sizeInPoints), 12 * Self.pointsPerUnit, accuracy: Self.accuracy)
    }
}
