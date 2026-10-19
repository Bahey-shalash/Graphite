import XCTest
import PDFKit
import GraphiteCore
@testable import GraphiteApple

/// The bounds `PDFTemplateGenerator` holds new notebooks and inserted pages to, the
/// defaults of a paper, and how older saved paper specifications are read.
final class PDFTemplateGeneratorLimitsTests: XCTestCase {
    private func accepts(_ paper: PaperSpecification, pageCount: Int = 1) -> Bool {
        (try? PDFTemplateGenerator.documentData(paper: paper, pageCount: pageCount)) != nil
    }

    func testNewNotebooksAcceptSidesFrom72To2880Points() {
        for side in [72.0, 72.5, 595.28, 2_879.5, 2_880] {
            XCTAssertTrue(accepts(PaperSpecification(template: .blank, width: side, height: 400)), "width \(side)")
            XCTAssertTrue(accepts(PaperSpecification(template: .blank, width: 400, height: side)), "height \(side)")
        }
        for side in [71.99, 0, -1, 2_880.01, 100_000, Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(accepts(PaperSpecification(template: .blank, width: side, height: 400)), "width \(side)")
            XCTAssertFalse(accepts(PaperSpecification(template: .blank, width: 400, height: side)), "height \(side)")
        }
    }

    func testNewNotebooksAcceptSpacingFrom4To144Points() {
        for spacing in [4.0, 4.5, 18, 143.5, 144] { XCTAssertTrue(accepts(PaperSpecification(template: .grid, spacing: spacing)), "spacing \(spacing)") }
        for spacing in [3.99, 0, -4, 144.01, 1_000, Double.nan, .infinity] { XCTAssertFalse(accepts(PaperSpecification(template: .grid, spacing: spacing)), "spacing \(spacing)") }
    }

    func testNewNotebooksAcceptOneToAThousandPages() throws {
        for pageCount in [-1, 0, 1_001, 5_000] { XCTAssertFalse(accepts(PaperSpecification(template: .blank), pageCount: pageCount), "\(pageCount) pages") }
        for pageCount in [1, 2, 1_000] {
            let data = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount)
            XCTAssertEqual(PDFDocument(data: data)?.pageCount, pageCount)
        }
    }

    func testInsertedPagesAreHeldTo3Through14400PointsWithTheSpacingStillChecked() throws {
        let cases: [(requested: CGSize, expected: CGSize)] = [
            (CGSize(width: 3, height: 14_400), CGSize(width: 3, height: 14_400)),
            (CGSize(width: 2.5, height: 14_400.5), CGSize(width: 3, height: 14_400)),
            (CGSize(width: 1, height: 1), CGSize(width: 3, height: 3)),
            (CGSize(width: 100_000, height: 7), CGSize(width: 14_400, height: 7)),
        ]
        for testCase in cases {
            let data = try PDFTemplateGenerator.pageData(template: .blank, matching: testCase.requested)
            let mediaBox = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0)?.bounds(for: .mediaBox))
            XCTAssertEqual(mediaBox.width, testCase.expected.width, accuracy: 0.01, "\(testCase.requested)")
            XCTAssertEqual(mediaBox.height, testCase.expected.height, accuracy: 0.01, "\(testCase.requested)")
        }
        for size in [CGSize(width: 0, height: 100), CGSize(width: 100, height: -1), CGSize(width: CGFloat.nan, height: 100), CGSize(width: 100, height: CGFloat.infinity)] {
            XCTAssertThrowsError(try PDFTemplateGenerator.pageData(template: .blank, matching: size), "\(size)")
        }
        for spacing in [3.99, 144.01] {
            XCTAssertThrowsError(try PDFTemplateGenerator.pageData(paper: PaperSpecification(template: .grid, spacing: spacing), matching: CGSize(width: 100, height: 100)), "spacing \(spacing)")
        }
    }

    func testThePaperDefaultsAreAnA4PageOfDottedPaperWithEighteenPointSpacing() throws {
        let paper = PaperSpecification()
        XCTAssertEqual(paper.template, .dotted)
        XCTAssertEqual(paper.width, 595.28)
        XCTAssertEqual(paper.height, 841.89)
        XCTAssertEqual(paper.spacing, 18)
        XCTAssertEqual(PaperSpecification.standardSpacing, 18)
        XCTAssertNil(paper.paperColorHex)
        XCTAssertEqual(paper.lineColor, .gray)
        XCTAssertEqual(paper.lineStrength, .standard)
        let mediaBox = try XCTUnwrap(PDFDocument(data: PDFTemplateGenerator.documentData(paper: paper))?.page(at: 0)?.bounds(for: .mediaBox))
        XCTAssertEqual(mediaBox.width, 595.28, accuracy: 0.01)
        XCTAssertEqual(mediaBox.height, 841.89, accuracy: 0.01)
    }

    func testASpecificationSavedBeforePaperColorsReadsAsWhitePaperWithGrayStandardLines() throws {
        let older = Data(#"{"template":"ruled","width":420,"height":595,"spacing":24}"#.utf8)
        let decoded = try JSONDecoder().decode(PaperSpecification.self, from: older)
        XCTAssertEqual(decoded.template, .ruled)
        XCTAssertEqual(decoded.width, 420)
        XCTAssertEqual(decoded.height, 595)
        XCTAssertEqual(decoded.spacing, 24)
        XCTAssertNil(decoded.paperColorHex, "No color means white paper.")
        XCTAssertEqual(decoded.lineColor, .gray)
        XCTAssertEqual(decoded.lineStrength, .standard)

        let newer = Data(##"{"template":"grid","width":420,"height":595,"spacing":24,"paperColorHex":"#fbf7ea","lineColor":"blue","lineStrength":"strong"}"##.utf8)
        let decodedNewer = try JSONDecoder().decode(PaperSpecification.self, from: newer)
        XCTAssertEqual(decodedNewer.paperColorHex, "#fbf7ea")
        XCTAssertEqual(decodedNewer.lineColor, .blue)
        XCTAssertEqual(decodedNewer.lineStrength, .strong)
    }

    func testThePaperTemplatesAreNamedByTheseEightWords() {
        XCTAssertEqual(PaperTemplate.allCases.map(\.rawValue), ["blank", "dotted", "grid", "ruled", "cornell", "engineering", "isometric", "music"])
    }

    func testDottedPaperIsOneTilingCellNotOnePathPerDot() throws {
        let dotted = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .dotted), pageCount: 50)
        let blank = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 50)
        // A path for each of the roughly 1,400 dots on a page would add hundreds of kilobytes for fifty pages.
        XCTAssertLessThan(dotted.count - blank.count, 20_000)
        let text = String(decoding: dotted, as: UTF8.self)
        XCTAssertTrue(text.contains("/PatternType 1"), "The dots are a tiling pattern.")
        XCTAssertEqual(text.components(separatedBy: "/PatternType 1").count - 1, 1, "Fifty pages share one pattern cell.")
    }
}
