import XCTest
import CoreGraphics
import PDFKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

final class NotebookCoverPageTests: XCTestCase {
    func testTheCoverIsAPageOfTheGivenSizeWithTheTitleAsText() throws {
        let data = try NotebookCoverPage.pageData(title: "Signals and Systems", color: .blue, pageSize: CGSize(width: 595, height: 842))
        let page = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 595, height: 842))
        let text = try XCTUnwrap(page.string).replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        XCTAssertTrue(text.contains("Signals and Systems"), "The title is text, so Preview and search read it.")
    }

    func testALongTitleIsWrappedAndWhole() throws {
        let title = "Introduction to the Theory of Computation and Complexity, Lecture Notes of the Autumn Semester"
        let data = try NotebookCoverPage.pageData(title: title, color: .graphite, pageSize: CGSize(width: 420, height: 595))
        let text = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0)?.string).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        XCTAssertTrue(text.contains("Introduction"))
        XCTAssertTrue(text.contains("Semester"))
    }

    func testALongWordIsMadeSmallerNotBrokenAcrossLines() throws {
        let data = try NotebookCoverPage.pageData(title: "Thermodynamics", color: .red, pageSize: CGSize(width: 420, height: 595))
        let text = try XCTUnwrap(PDFDocument(data: data)?.page(at: 0)?.string)
        XCTAssertTrue(text.contains("Thermodynamics"), "A word is never broken across two lines: \(text).")
    }

    func testAPageWithNoSizeIsRefused() {
        XCTAssertThrowsError(try NotebookCoverPage.pageData(title: "A", color: .red, pageSize: .zero))
    }

    func testTheCoverGoesFirstAtTheSizeOfThePagesAfterIt() throws {
        let paper = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled, width: 420, height: 595), pageCount: 3)
        let covered = try NotebookCoverPage.prepending(coverTitled: "Lab", color: .green, to: paper)
        let document = try XCTUnwrap(PDFDocument(data: covered))
        XCTAssertEqual(document.pageCount, 4)
        XCTAssertTrue(try XCTUnwrap(document.page(at: 0)?.string).contains("Lab"))
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 420, height: 595))
        XCTAssertEqual(document.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 420, height: 595))
    }

    func testTheCoverIsOfItsColorAndNotOnlyWhite() throws {
        let image = try XCTUnwrap(NotebookCoverPage.previewImage(title: "", color: .red, pageSize: CGSize(width: 100, height: 100), longerSidePixels: 50))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertGreaterThan(Int(pixels[0]), 150, "Red at a corner.")
        XCTAssertLessThan(Int(pixels[2]), 100)
    }

    func testTheTitleIsDarkOnLightColorsAndLightOnDarkOnes() {
        XCTAssertTrue(NotebookCoverColor.yellow.usesDarkTitle)
        XCTAssertFalse(NotebookCoverColor.blue.usesDarkTitle)
        XCTAssertFalse(NotebookCoverColor.graphite.usesDarkTitle)
    }

    func testEveryColorHasItsOwnHexAndName() {
        XCTAssertEqual(Set(NotebookCoverColor.allCases.map(\.colorHex)).count, NotebookCoverColor.allCases.count)
        XCTAssertTrue(NotebookCoverColor.allCases.allSatisfy { color in color.colorHex.hasPrefix("#") && color.colorHex.count == 7 })
        XCTAssertEqual(NotebookCoverColor.orange.title, "Orange")
    }
}
