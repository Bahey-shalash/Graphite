import XCTest
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

final class MyPaperTemplateBuilderTests: XCTestCase {
    /// A PDF of `pageTexts.count` pages, each with its text drawn as text, so that PDFKit can read it back.
    private func textPDF(_ pageTexts: [String]) throws -> Data {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for text in pageTexts {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 24, nil)]))
            context.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// A picture split down the middle, `leftColor` and `rightColor`, as JPEG or PNG with an orientation.
    private func picture(type: UTType, width: Int = 60, height: Int = 30, orientation: Int = 1, noise: Bool = false) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var generator = SystemRandomNumberGenerator()
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let isLeft = column < width / 2
                pixels[offset] = isLeft ? 255 : 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = isLeft ? 0 : 255
                if noise { for channel in 0..<3 { pixels[offset + channel] = UInt8.random(in: 0...255, using: &generator) } }
            }
        }
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// The color of the page at a point given as fractions of its width and height from the top left.
    private func color(of pdf: Data, atX fractionX: Double, y fractionY: Double) throws -> (red: Int, blue: Int) {
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let image = try XCTUnwrap(LibraryPreviewLoader.thumbnail(of: page, longerSidePixels: 200))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let column = Int(fractionX * Double(image.width)), row = Int(fractionY * Double(image.height))
        let offset = (row * context.bytesPerRow) + column * 4
        _ = bounds
        return (Int(pixels[offset]), Int(pixels[offset + 2]))
    }

    // MARK: PDF pages

    func testAPageOfAPDFStaysTextNotABitmapAndIsTheOnlyPage() throws {
        let source = try textPDF(["First page", "Second page", "Third page"])
        XCTAssertEqual(try MyPaperTemplateBuilder.pageCount(ofPDF: source), 3)
        let template = try MyPaperTemplateBuilder.templateData(fromPDF: source, pageIndex: 1)
        let document = try XCTUnwrap(PDFDocument(data: template))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertTrue(try XCTUnwrap(document.page(at: 0)?.string).contains("Second page"), "The page's text is still text.")
        XCTAssertLessThan(template.count, 20_000, "A page drawn into a bitmap would be far larger.")
    }

    func testMarkupOnAPageIsLeftOutOfThePaper() throws {
        let source = try textPDF(["Page"])
        let document = try XCTUnwrap(PDFDocument(data: source))
        let page = try XCTUnwrap(document.page(at: 0))
        page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 100, height: 20), forType: .highlight, withProperties: nil))
        let template = try MyPaperTemplateBuilder.templateData(fromPDF: try XCTUnwrap(document.dataRepresentation()), pageIndex: 0)
        XCTAssertEqual(PDFDocument(data: template)?.page(at: 0)?.annotations.count, 0)
    }

    func testAPageThatIsNotThereAndAFileThatIsNotAPDFAreRefused() throws {
        let source = try textPDF(["Only"])
        XCTAssertThrowsError(try MyPaperTemplateBuilder.templateData(fromPDF: source, pageIndex: 1)) { error in
            XCTAssertEqual(error as? MyPaperTemplateError, .noSuchPage(1))
        }
        XCTAssertThrowsError(try MyPaperTemplateBuilder.templateData(fromPDF: source, pageIndex: -1))
        XCTAssertThrowsError(try MyPaperTemplateBuilder.pageCount(ofPDF: Data("not a pdf".utf8))) { error in
            XCTAssertEqual(error as? MyPaperTemplateError, .notAPDF)
        }
    }

    func testALockedPDFIsRefused() throws {
        let document = try XCTUnwrap(PDFDocument(data: try textPDF(["Secret"])))
        let location = try TemporaryVault.make(prefix: "LockedPDF", for: self).root.appendingPathComponent("Locked.pdf")
        XCTAssertTrue(document.write(to: location, withOptions: [.userPasswordOption: "open sesame", .ownerPasswordOption: "owner"]))
        let lockedData = try Data(contentsOf: location)
        XCTAssertThrowsError(try MyPaperTemplateBuilder.templateData(fromPDF: lockedData, pageIndex: 0)) { error in
            XCTAssertEqual(error as? MyPaperTemplateError, .locked)
        }
    }

    // MARK: Pictures

    func testAJPEGIsEmbeddedAsItIsOnAPageOfItsShape() throws {
        let jpeg = try picture(type: .jpeg, width: 1200, height: 800, noise: true)
        let template = try MyPaperTemplateBuilder.templateData(fromPicture: jpeg)
        XCTAssertLessThan(template.count, jpeg.count + 5_000, "The JPEG data is embedded, not drawn again and encoded again.")
        let page = try XCTUnwrap(PDFDocument(data: template)?.page(at: 0))
        let size = page.bounds(for: .mediaBox).size
        XCTAssertEqual(size.width, MyPaperTemplateBuilder.pictureLongerSidePoints, accuracy: 0.01)
        XCTAssertEqual(size.width / size.height, 1.5, accuracy: 0.01)
    }

    func testAPNGIsEmbeddedLosslessly() throws {
        let png = try picture(type: .png)
        let template = try MyPaperTemplateBuilder.templateData(fromPicture: png)
        let colorAtLeft = try color(of: template, atX: 0.2, y: 0.5)
        XCTAssertGreaterThan(colorAtLeft.red, 200)
        let colorAtRight = try color(of: template, atX: 0.8, y: 0.5)
        XCTAssertGreaterThan(colorAtRight.blue, 200)
    }

    func testAPictureOfATypePDFCannotHoldIsStoredAsJPEG() throws {
        let tiff = try picture(type: .tiff)
        let template = try MyPaperTemplateBuilder.templateData(fromPicture: tiff)
        XCTAssertNotNil(PDFDocument(data: template)?.page(at: 0))
    }

    func testThePicturesOrientationIsApplied() throws {
        // Stored 60 by 30, red on the left and blue on the right; orientation 6 shows it turned a quarter clockwise.
        let turned = try picture(type: .jpeg, orientation: 6)
        let template = try MyPaperTemplateBuilder.templateData(fromPicture: turned)
        let size = try XCTUnwrap(PDFDocument(data: template)?.page(at: 0)?.bounds(for: .mediaBox).size)
        XCTAssertLessThan(size.width, size.height, "A picture turned a quarter makes a page taller than wide.")
        let top = try color(of: template, atX: 0.5, y: 0.2)
        let bottom = try color(of: template, atX: 0.5, y: 0.8)
        XCTAssertGreaterThan(top.red, 200, "The left of the stored picture is at the top of the page.")
        XCTAssertGreaterThan(bottom.blue, 200)
    }

    func testSomethingThatIsNotAPictureIsRefused() {
        XCTAssertThrowsError(try MyPaperTemplateBuilder.templateData(fromPicture: Data("text".utf8))) { error in
            XCTAssertEqual(error as? MyPaperTemplateError, .notAPicture)
        }
    }

    // MARK: A notebook of a template

    func testEveryPageOfTheNotebookIsTheTemplatesPage() throws {
        let location = try TemporaryVault.make(prefix: "TemplateNotebook", for: self).root.appendingPathComponent("Template.pdf")
        try MyPaperTemplateBuilder.templateData(fromPDF: try textPDF(["Planner"]), pageIndex: 0).write(to: location)
        let notebook = try MyPaperTemplateNotebook.documentData(templateAt: location, pageCount: 12)
        let document = try XCTUnwrap(PDFDocument(data: notebook))
        XCTAssertEqual(document.pageCount, 12)
        for pageIndex in 0..<12 { XCTAssertTrue(try XCTUnwrap(document.page(at: pageIndex)?.string).contains("Planner"), "Page \(pageIndex + 1) is still text.") }
    }

    func testAPictureTemplateIsNotKeptOncePerPage() throws {
        let location = try TemporaryVault.make(prefix: "TemplateNotebook", for: self).root.appendingPathComponent("Template.pdf")
        let template = try MyPaperTemplateBuilder.templateData(fromPicture: try picture(type: .jpeg, width: 1200, height: 1600, noise: true))
        try template.write(to: location)
        let notebook = try MyPaperTemplateNotebook.documentData(templateAt: location, pageCount: 10)
        XCTAssertLessThan(notebook.count, template.count * 2, "Ten pages share the page's content, so the file stays about the size of one.")
        XCTAssertEqual(PDFDocument(data: notebook)?.pageCount, 10)
    }

    func testAnUnreadableTemplateAndAnImpossiblePageCountAreRefused() throws {
        let folder = try TemporaryVault.make(prefix: "TemplateNotebook", for: self).root
        let missing = folder.appendingPathComponent("Missing.pdf")
        XCTAssertThrowsError(try MyPaperTemplateNotebook.documentData(templateAt: missing, pageCount: 1))
        let location = folder.appendingPathComponent("Template.pdf")
        try MyPaperTemplateBuilder.templateData(fromPDF: try textPDF(["Planner"]), pageIndex: 0).write(to: location)
        XCTAssertThrowsError(try MyPaperTemplateNotebook.documentData(templateAt: location, pageCount: 0))
        XCTAssertThrowsError(try MyPaperTemplateNotebook.documentData(templateAt: location, pageCount: 1001))
    }

    func testAPreviewHasTheTemplatesPageSize() throws {
        let location = try TemporaryVault.make(prefix: "TemplatePreview", for: self).root.appendingPathComponent("Template.pdf")
        try MyPaperTemplateBuilder.templateData(fromPDF: try textPDF(["Planner"]), pageIndex: 0).write(to: location)
        let preview = try XCTUnwrap(MyPaperTemplateNotebook.preview(ofTemplateAt: location, longerSidePixels: 200))
        XCTAssertEqual(preview.pageSize, CGSize(width: 595, height: 842))
        XCTAssertEqual(max(preview.image.width, preview.image.height), 200)
    }
}
