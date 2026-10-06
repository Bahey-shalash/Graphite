import XCTest
import PDFKit
import ImageIO
import CoreGraphics
import CryptoKit
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
import WebKit
#endif
import GraphiteCore
@testable import GraphiteApple

/// Pictures in SVG and PDF drawings: the picture of a drawing made on an image and pictures
/// placed on a drawing. The files are read back by independent readers (Foundation's XML
/// parser, Core Graphics and PDFKit for PDF, Apple's SVG renderer and WebKit for SVG), and by
/// Graphite for editing and for previews.
final class VectorPictureTests: XCTestCase {
    private static let drawingSize = CGSize(width: 400, height: 300)
    private static let black = VectorInkColor(red: 0, green: 0, blue: 0, alpha: 1)
    private let standardColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Pictures and drawings

    private struct PictureColor {
        let red: Double, green: Double, blue: Double
        static let red = PictureColor(red: 0.9, green: 0.1, blue: 0.1)
        static let green = PictureColor(red: 0.1, green: 0.75, blue: 0.2)
        static let blue = PictureColor(red: 0.1, green: 0.2, blue: 0.9)
    }

    /// A picture of one color. With `transparentRightHalf`, the right half has no pixels at all.
    private func pictureData(width: Int = 200, height: Int = 100, color: PictureColor, type: UTType, transparentRightHalf: Bool = false) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: standardColorSpace,
                                              bitmapInfo: (type == .jpeg ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue))
        context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: transparentRightHalf ? width / 2 : width, height: height))
        return try encoded(try XCTUnwrap(context.makeImage()), type: type)
    }

    /// A PNG of random pixels, which no encoder can make smaller: `height` rows of 1,024
    /// opaque pixels, about 3,073 bytes each.
    private func noisePictureData(height: Int) throws -> Data {
        let width = 1_024
        var pixelBytes = [UInt8](repeating: 0, count: width * height * 4)
        pixelBytes.withUnsafeMutableBytes { buffer in arc4random_buf(buffer.baseAddress, buffer.count) }
        let image = try pixelBytes.withUnsafeMutableBytes { buffer in
            try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: standardColorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        }
        return try encoded(image, type: .png)
    }

    /// Three pictures that together are just within the 16 MB a drawing holds.
    private func picturesFillingTheBudget() throws -> [DrawingBackgroundImage] {
        let budgetPerPicture = DrawingLimits.maximumBackgroundImageBytes / 3
        var rowCount = budgetPerPicture / 3_073
        var pictureBytes = try noisePictureData(height: rowCount)
        while pictureBytes.count > budgetPerPicture {
            rowCount -= 4
            pictureBytes = try noisePictureData(height: rowCount)
        }
        let allPictureBytes = [pictureBytes, try noisePictureData(height: rowCount), try noisePictureData(height: rowCount)]
        let totalBytes = allPictureBytes.reduce(0) { total, imageData in total + imageData.count }
        XCTAssertLessThanOrEqual(totalBytes, DrawingLimits.maximumBackgroundImageBytes)
        XCTAssertGreaterThan(totalBytes, DrawingLimits.maximumBackgroundImageBytes - 100_000, "The pictures use the whole budget.")
        return allPictureBytes.enumerated().map { pictureIndex, imageData in
            DrawingBackgroundImage(imageData: imageData, frame: CGRect(x: 10 + Double(pictureIndex) * 130, y: 20, width: 120, height: 160))
        }
    }

    private func encoded(_ image: CGImage, type: UTType) throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func band(fromX startX: Double, toX endX: Double, atY centerY: Double, width strokeWidth: Double = 8) throws -> VectorShape {
        let samples = stride(from: startX, through: endX, by: 2).map { x in VectorStrokeSample(point: CGPoint(x: x, y: centerY), width: strokeWidth) }
        return try XCTUnwrap(StrokeOutliner.shape(forSegments: [samples], color: Self.black))
    }

    /// Ruled paper, lines 32 points apart, as a drawing that shows its paper has it.
    private var ruledPaper: VectorShape {
        get throws { try XCTUnwrap(DrawingPaperRenderer.shape(for: DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true), in: CGRect(origin: .zero, size: Self.drawingSize))) }
    }

    /// A red photo (JPEG) at (40, 40, 120, 80) with ink across it at y 80, a blue PNG whose
    /// right half is transparent at (200, 40, 160, 80), ink across the page at y 200, and
    /// ruled paper under everything.
    private struct Scene {
        let drawing: VectorDrawing
        let photo: DrawingBackgroundImage
        let cutOut: DrawingBackgroundImage
    }

    private func scene(paper: Bool = true) throws -> Scene {
        let photo = DrawingBackgroundImage(imageData: try pictureData(color: .red, type: .jpeg), frame: CGRect(x: 40, y: 40, width: 120, height: 80))
        let cutOut = DrawingBackgroundImage(imageData: try pictureData(width: 100, height: 50, color: .blue, type: .png, transparentRightHalf: true),
                                            frame: CGRect(x: 200, y: 40, width: 160, height: 80))
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, shapesUnderPictures: paper ? [try ruledPaper] : [],
                                    pictures: [photo, cutOut], shapes: [try band(fromX: 20, toX: 180, atY: 80), try band(fromX: 20, toX: 380, atY: 200)])
        return Scene(drawing: drawing, photo: photo, cutOut: cutOut)
    }

    private func payload(for drawing: VectorDrawing, backgroundImage: DrawingBackgroundImage? = nil, pictures: [DrawingBackgroundImage]? = nil,
                         paper: DrawingPaper = DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true)) -> DrawingPayload {
        DrawingPayload(width: drawing.size.width, height: drawing.size.height, background: drawing.background, strokes: Data("pencil strokes".utf8),
                       backgroundImage: backgroundImage, pictures: pictures ?? drawing.pictures, paper: paper)
    }

    // MARK: Reading pixels

    private struct Rendering {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let drawingSize: CGSize

        /// The color at a point of the drawing, counted from its top-left corner.
        func color(at point: CGPoint) -> (red: Int, green: Int, blue: Int, alpha: Int) {
            let column = min(width - 1, Int(point.x / drawingSize.width * Double(width)))
            let row = min(height - 1, Int(point.y / drawingSize.height * Double(height)))
            let offset = (row * width + column) * 4
            return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]), Int(pixels[offset + 3]))
        }
    }

    /// Draws `image` over white, as a viewer shows a drawing, and reads its pixels.
    private func rendering(of image: CGImage, drawingSize: CGSize = VectorPictureTests.drawingSize) throws -> Rendering {
        var pixelBytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixelBytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: standardColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Rendering(pixels: pixelBytes, width: image.width, height: image.height, drawingSize: drawingSize)
    }

    /// The first page as Core Graphics draws it, independent of Graphite, at twice its size.
    private func pdfRendering(of fileData: Data) throws -> Rendering {
        let page = try XCTUnwrap(CGDataProvider(data: fileData as CFData).flatMap(CGPDFDocument.init)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(box.width * 2), height: Int(box.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: standardColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: box.width * 2, height: box.height * 2))
        context.scaleBy(x: 2, y: 2)
        context.drawPDFPage(page)
        return try rendering(of: try XCTUnwrap(context.makeImage()), drawingSize: box.size)
    }

    /// The page as PDFKit draws it for a thumbnail.
    private func pdfKitRendering(of fileData: Data) throws -> Rendering {
        let page = try XCTUnwrap(PDFDocument(data: fileData)?.page(at: 0))
        let size = page.bounds(for: .mediaBox).size
        let thumbnail = page.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .mediaBox)
        #if canImport(AppKit)
        var proposedRect = CGRect(origin: .zero, size: thumbnail.size)
        return try rendering(of: try XCTUnwrap(thumbnail.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)), drawingSize: size)
        #else
        return try rendering(of: try XCTUnwrap(thumbnail.cgImage), drawingSize: size)
        #endif
    }

    #if canImport(AppKit)
    /// The SVG as Apple's own SVG renderer (CoreSVG, behind `NSImage`) draws it, at twice its size.
    private func coreSVGRendering(of fileData: Data, drawingSize: CGSize = VectorPictureTests.drawingSize) throws -> Rendering {
        let image = try XCTUnwrap(NSImage(data: fileData), "Apple's SVG renderer did not read the file.")
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(drawingSize.width * 2), height: Int(drawingSize.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: standardColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: drawingSize.width * 2, height: drawingSize.height * 2))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: drawingSize.width * 2, height: drawingSize.height * 2))
        NSGraphicsContext.restoreGraphicsState()
        return try rendering(of: try XCTUnwrap(context.makeImage()), drawingSize: drawingSize)
    }
    #endif

    private func isClose(_ color: (red: Int, green: Int, blue: Int, alpha: Int), to expected: PictureColor, tolerance: Int = 40) -> Bool {
        abs(color.red - Int(expected.red * 255)) <= tolerance && abs(color.green - Int(expected.green * 255)) <= tolerance
            && abs(color.blue - Int(expected.blue * 255)) <= tolerance
    }

    private func isBlack(_ color: (red: Int, green: Int, blue: Int, alpha: Int)) -> Bool { color.red < 60 && color.green < 60 && color.blue < 60 }
    private func isWhite(_ color: (red: Int, green: Int, blue: Int, alpha: Int)) -> Bool { color.red > 240 && color.green > 240 && color.blue > 240 }
    /// The ruled paper's light blue-grey line color, `#ccd4e0`, or half of it where a
    /// renderer smooths the one-point line over two pixel rows.
    private func isPaperLine(_ color: (red: Int, green: Int, blue: Int, alpha: Int)) -> Bool {
        (180...240).contains(color.red) && color.blue >= color.red + 4
    }

    /// Checks what every reader must show of `scene()`: the ink over the photo, the photo
    /// over the paper, the paper through the transparent half of the cut-out, the ink over
    /// the paper, and white elsewhere.
    private func assertShowsScene(_ rendering: Rendering, reader: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(isClose(rendering.color(at: CGPoint(x: 60, y: 56)), to: .red), "\(reader): the photo \(rendering.color(at: CGPoint(x: 60, y: 56)))", file: file, line: line)
        XCTAssertTrue(isClose(rendering.color(at: CGPoint(x: 60, y: 64)), to: .red), "\(reader): the photo covers the paper line", file: file, line: line)
        XCTAssertTrue(isBlack(rendering.color(at: CGPoint(x: 100, y: 80))), "\(reader): the ink is over the photo", file: file, line: line)
        XCTAssertTrue(isClose(rendering.color(at: CGPoint(x: 230, y: 64)), to: .blue), "\(reader): the cut-out covers the paper line", file: file, line: line)
        XCTAssertTrue(isPaperLine(rendering.color(at: CGPoint(x: 320, y: 64))), "\(reader): the paper shows through the transparent half \(rendering.color(at: CGPoint(x: 320, y: 64)))", file: file, line: line)
        XCTAssertTrue(isWhite(rendering.color(at: CGPoint(x: 320, y: 90))), "\(reader): nothing is drawn between the lines", file: file, line: line)
        XCTAssertTrue(isBlack(rendering.color(at: CGPoint(x: 300, y: 200))), "\(reader): the ink", file: file, line: line)
        XCTAssertTrue(isPaperLine(rendering.color(at: CGPoint(x: 300, y: 256))), "\(reader): the paper under the ink", file: file, line: line)
        XCTAssertTrue(isWhite(rendering.color(at: CGPoint(x: 380, y: 240))), "\(reader): the white background", file: file, line: line)
    }

    // MARK: SVG

    /// What an independent XML parser finds in the file: the elements in order and the pictures.
    private final class SVGElementCollector: NSObject, XMLParserDelegate {
        var elementNames: [String] = []
        var pictureAttributes: [[String: String]] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            elementNames.append(elementName)
            if elementName == "image" { pictureAttributes.append(attributes) }
        }
    }

    private func collectedElements(of fileData: Data) throws -> SVGElementCollector {
        let collector = SVGElementCollector()
        let parser = XMLParser(data: fileData)
        parser.delegate = collector
        XCTAssertTrue(parser.parse(), "Foundation's XML parser must read the SVG: \(String(describing: parser.parserError))")
        return collector
    }

    func testSVGDrawingShowsItsPicturesInEveryReaderAndReadsThemBackExactly() throws {
        let scene = try scene()
        let drawingPayload = payload(for: scene.drawing)
        let fileData = try SVGDrawingFile.encode(scene.drawing, payload: drawingPayload)

        // An independent parser: paper, then the photo and the cut-out, then the ink.
        let collector = try collectedElements(of: fileData)
        let drawnElements = collector.elementNames.filter { name in ["rect", "path", "image"].contains(name) }
        XCTAssertEqual(drawnElements, ["rect", "path", "image", "image", "path", "path"])
        XCTAssertEqual(collector.pictureAttributes.count, 2)
        let text = try XCTUnwrap(String(data: fileData, encoding: .utf8))
        XCTAssertTrue(text.contains("xmlns:xlink=\"http://www.w3.org/1999/xlink\""))
        for (attributes, picture) in zip(collector.pictureAttributes, [scene.photo, scene.cutOut]) {
            XCTAssertEqual(attributes["preserveAspectRatio"], "none")
            XCTAssertNil(attributes["href"], "Only the SVG 1.1 attribute, which every renderer reads.")
            XCTAssertEqual(["x", "y", "width", "height"].compactMap { name in attributes[name].flatMap(Double.init) },
                           [picture.frame.minX, picture.frame.minY, picture.frame.width, picture.frame.height])
            let dataURI = try XCTUnwrap(attributes["xlink:href"])
            let isJPEG = picture.imageData.starts(with: [0xFF, 0xD8])
            let prefix = isJPEG ? "data:image/jpeg;base64," : "data:image/png;base64,"
            XCTAssertTrue(dataURI.hasPrefix(prefix))
            XCTAssertEqual(Data(base64Encoded: String(dataURI.dropFirst(prefix.count))), picture.imageData, "The stored bytes, not a new encoding.")
        }

        // Graphite reads the editing record back: the same bytes, the same frames.
        let reading = SVGDrawingFile.readMetadata(fileData)
        XCTAssertFalse(reading.metadataWasDiscarded)
        let readPayload = try XCTUnwrap(reading.payload)
        XCTAssertEqual(readPayload.pictures, [scene.photo, scene.cutOut])
        XCTAssertEqual(readPayload.version, 3)

        // Graphite's own preview reads the visible pictures and shows what viewers show.
        let reread = try SVGDrawingFile.vectorDrawing(from: fileData)
        XCTAssertEqual(reread.pictures, scene.drawing.pictures)
        XCTAssertEqual(reread.shapesUnderPictures.count, 1)
        XCTAssertEqual(reread.shapes.count, 2)
        let preview = try VectorDrawingRenderer.image(for: reread, maximumPixelDimension: 800)
        assertShowsScene(try rendering(of: preview), reader: "Graphite's SVG preview")
        #if canImport(AppKit)
        assertShowsScene(try coreSVGRendering(of: fileData), reader: "Apple's SVG renderer")
        #endif
    }

    func testDrawingWithoutPicturesKeepsItsSVGAsBefore() throws {
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, shapesUnderPictures: [try ruledPaper], shapes: [try band(fromX: 20, toX: 380, atY: 200)])
        let fileData = try SVGDrawingFile.encode(drawing, payload: nil)
        let text = try XCTUnwrap(String(data: fileData, encoding: .utf8))
        XCTAssertFalse(text.contains("xlink"))
        XCTAssertEqual(text.components(separatedBy: "<g ").count, 2, "Paper and ink stay in one group, as drawings without pictures always were.")
        let reread = try SVGDrawingFile.vectorDrawing(from: SVGDrawingFile.encode(drawing, payload: payload(for: drawing)))
        XCTAssertEqual(reread.shapes.count, 2, "Without pictures, the paper reads back as the first shape.")
    }

    func testSVGOfADrawingMadeOnAnImageShowsThePictureUnderTheInk() throws {
        let photo = DrawingBackgroundImage(imageData: try pictureData(width: 800, height: 600, color: .green, type: .jpeg), frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: [photo], shapes: [try band(fromX: 20, toX: 380, atY: 150)])
        let drawingPayload = DrawingPayload(width: 400, height: 300, background: .white, strokes: Data("strokes".utf8), backgroundImage: photo)
        XCTAssertEqual(drawingPayload.version, 2, "A drawing made on an image keeps the record it always had.")
        let fileData = try SVGDrawingFile.encode(drawing, payload: drawingPayload)
        let readPayload = try XCTUnwrap(SVGDrawingFile.readMetadata(fileData).payload)
        XCTAssertEqual(readPayload.backgroundImage, photo)
        XCTAssertTrue(readPayload.pictures.isEmpty)
        #if canImport(AppKit)
        let shown = try coreSVGRendering(of: fileData)
        XCTAssertTrue(isClose(shown.color(at: CGPoint(x: 200, y: 60)), to: .green))
        XCTAssertTrue(isClose(shown.color(at: CGPoint(x: 395, y: 295)), to: .green), "The picture fills the drawing to its corner.")
        XCTAssertTrue(isBlack(shown.color(at: CGPoint(x: 200, y: 150))))
        #endif
        let preview = try rendering(of: VectorDrawingRenderer.image(for: SVGDrawingFile.vectorDrawing(from: fileData), maximumPixelDimension: 800))
        XCTAssertTrue(isClose(preview.color(at: CGPoint(x: 200, y: 60)), to: .green))
        XCTAssertTrue(isBlack(preview.color(at: CGPoint(x: 200, y: 150))))
    }

    func testSVGWithTheMostPicturesADrawingHoldsRoundTrips() throws {
        let tile = try pictureData(width: 20, height: 20, color: .blue, type: .png)
        let pictures = (0..<SVGDrawingFile.maximumPictureCount).map { pictureIndex in
            DrawingBackgroundImage(imageData: tile, frame: CGRect(x: Double(pictureIndex % 11) * 36, y: Double(pictureIndex / 11) * 36, width: 30, height: 30))
        }
        let backgroundImage = try XCTUnwrap(pictures.first)
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: pictures, shapes: [])
        let fileData = try SVGDrawingFile.encode(drawing, payload: payload(for: drawing, backgroundImage: backgroundImage, pictures: Array(pictures.dropFirst())))
        XCTAssertEqual(try collectedElements(of: fileData).pictureAttributes.count, 33)
        let readPayload = try XCTUnwrap(SVGDrawingFile.readMetadata(fileData).payload)
        XCTAssertEqual([readPayload.backgroundImage].compactMap { picture in picture } + readPayload.pictures, pictures)
        XCTAssertEqual(try SVGDrawingFile.vectorDrawing(from: fileData).pictures.count, 33)
    }

    /// The whole picture budget, 16 MB, fits in one SVG, readable by Foundation's parser;
    /// a single picture too large for an XML attribute is refused with a clear message.
    func testSVGWithTheWholePictureBudgetFitsAndAnOversizedPictureIsRefused() throws {
        let pictures = try picturesFillingTheBudget()
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: pictures, shapes: [try band(fromX: 20, toX: 380, atY: 100)])
        let fileData = try SVGDrawingFile.encode(drawing, payload: payload(for: drawing))
        XCTAssertLessThan(fileData.count, SVGDrawingFile.maximumFileBytes)
        XCTAssertEqual(try XCTUnwrap(SVGDrawingFile.readMetadata(fileData).payload).pictures, pictures)
        XCTAssertEqual(try SVGDrawingFile.vectorDrawing(from: fileData).pictures, pictures)

        let oversized = DrawingBackgroundImage(imageData: try noisePictureData(height: SVGDrawingFile.maximumPictureBytes / 3_072 + 16),
                                               frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertGreaterThan(oversized.imageData.count, SVGDrawingFile.maximumPictureBytes)
        XCTAssertThrowsError(try SVGDrawingFile.encode(VectorDrawing(size: Self.drawingSize, background: .white, pictures: [oversized], shapes: []), payload: nil)) { error in
            XCTAssertEqual(error as? GraphiteError, .oversized("An image on this drawing is too large for an SVG file. Save the drawing as PNG or PDF."))
        }
    }

    func testSVGWhosePicturesAnotherAppChangedIsNoLongerEditableAndStillShowsThem() throws {
        let scene = try scene()
        let fileData = try SVGDrawingFile.encode(scene.drawing, payload: payload(for: scene.drawing))
        let text = try XCTUnwrap(String(data: fileData, encoding: .utf8))
        let photoElement = try XCTUnwrap(text.components(separatedBy: "\n").first { line in line.hasPrefix("<image") && line.contains("image/jpeg") })

        let withoutPhoto = Data(text.replacingOccurrences(of: photoElement + "\n", with: "").utf8)
        let removedReading = SVGDrawingFile.readMetadata(withoutPhoto)
        XCTAssertNil(removedReading.payload)
        XCTAssertTrue(removedReading.metadataWasDiscarded)
        XCTAssertEqual(try collectedElements(of: withoutPhoto).pictureAttributes.count, 1, "The other picture is still in the file.")
        XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: withoutPhoto), "Graphite hands a changed file to the system preview.")

        let moved = Data(text.replacingOccurrences(of: "<image x=\"40\" y=\"40\"", with: "<image x=\"60\" y=\"40\"").utf8)
        XCTAssertNotEqual(moved, fileData)
        XCTAssertNil(SVGDrawingFile.readMetadata(moved).payload)
        XCTAssertTrue(SVGDrawingFile.readMetadata(moved).metadataWasDiscarded)
        #if canImport(AppKit)
        let shownAfterMove = try coreSVGRendering(of: moved)
        XCTAssertTrue(isClose(shownAfterMove.color(at: CGPoint(x: 170, y: 56)), to: .red), "The moved photo is where the other app put it.")
        #endif
    }

    // MARK: SVG reader bounds

    /// A file as `SVGDrawingFile.encode` lays it out, with a record whose digest matches
    /// the visible content given, so the reader goes on to read that content.
    private func graphiteSVG(visibleContent: String, payload drawingPayload: DrawingPayload) throws -> Data {
        let head = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\""
                         + " version=\"1.1\" width=\"400\" height=\"300\" viewBox=\"0 0 400 300\">\n" + visibleContent).utf8)
        let tail = Data("\n</svg>\n".utf8)
        var hash = SHA256()
        hash.update(data: head)
        hash.update(data: tail)
        let encodedPayload = try drawingPayload.replacingVisibleContentDigest(Data(hash.finalize())).encoded().base64EncodedString()
        let metadata = "<metadata id=\"graphite-drawing\"><graphite:drawing xmlns:graphite=\"urn:graphite:drawing:1\" encoding=\"base64-binary-property-list\">"
            + encodedPayload + "</graphite:drawing></metadata>"
        return head + Data(metadata.utf8) + tail
    }

    private func imageElement(href: String, preserveAspectRatio: String? = "none", attribute: String = "xlink:href") -> String {
        let aspect = preserveAspectRatio.map { value in " preserveAspectRatio=\"\(value)\"" } ?? ""
        return "<image x=\"10\" y=\"10\" width=\"100\" height=\"100\"\(aspect) \(attribute)=\"\(href)\"/>\n"
    }

    func testSVGReaderShowsOnlyPicturesEmbeddedInTheFileWithinItsBounds() throws {
        let tile = try pictureData(width: 20, height: 20, color: .blue, type: .png)
        let drawingPayload = DrawingPayload(width: 400, height: 300, background: .white, strokes: Data("strokes".utf8))
        let embedded = "data:image/png;base64," + tile.base64EncodedString()

        // The file Graphite would write reads, with either link attribute.
        for attribute in ["xlink:href", "href"] {
            let file = try graphiteSVG(visibleContent: imageElement(href: embedded, attribute: attribute), payload: drawingPayload)
            XCTAssertNotNil(SVGDrawingFile.readMetadata(file).payload)
            XCTAssertEqual(try SVGDrawingFile.vectorDrawing(from: file).pictures.first?.imageData, tile)
        }

        // Nothing outside the file is ever read: other files, web addresses, other data.
        let refusedLinks = ["Diagram.png", "file:///etc/hosts", "https://example.com/picture.png", "data:image/svg+xml;base64,PHN2Zy8+",
                            "data:text/html;base64,PGgxPkE8L2gxPg==", "data:image/png,rawtext", "data:image/png;base64,***not base64***",
                            "data:image/png;base64,"]
        for link in refusedLinks {
            let file = try graphiteSVG(visibleContent: imageElement(href: link), payload: drawingPayload)
            XCTAssertNotNil(SVGDrawingFile.readMetadata(file).payload, "The record matches; only the picture is refused.")
            XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: file), link)
        }
        // A picture drawn in its own proportions is not one Graphite wrote.
        for aspect in [nil, "xMidYMid meet"] {
            XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: graphiteSVG(visibleContent: imageElement(href: embedded, preserveAspectRatio: aspect), payload: drawingPayload)))
        }
        // No more pictures than a drawing holds.
        let tooMany = String(repeating: imageElement(href: embedded), count: SVGDrawingFile.maximumPictureCount + 1)
        XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: graphiteSVG(visibleContent: tooMany, payload: drawingPayload)))
        let most = String(repeating: imageElement(href: embedded), count: SVGDrawingFile.maximumPictureCount)
        XCTAssertEqual(try SVGDrawingFile.vectorDrawing(from: graphiteSVG(visibleContent: most, payload: drawingPayload)).pictures.count, SVGDrawingFile.maximumPictureCount)
    }

    func testSVGReaderRefusesOversizedPicturesBeforeDecodingThem() throws {
        let drawingPayload = DrawingPayload(width: 400, height: 300, background: .white, strokes: Data("strokes".utf8))
        // The text of the largest picture Graphite writes, and four characters more.
        let largestText = Data(count: SVGDrawingFile.maximumPictureBytes).base64EncodedString()
        XCTAssertEqual(try SVGPictureSource.imageData(fromDataURI: "data:image/png;base64," + largestText).count, SVGDrawingFile.maximumPictureBytes)
        let justTooLong = "data:image/png;base64," + largestText + "AAAA"
        XCTAssertThrowsError(try SVGPictureSource.imageData(fromDataURI: justTooLong))
        XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: graphiteSVG(visibleContent: imageElement(href: justTooLong), payload: drawingPayload)))
        // Text within the length whose decoded bytes are more than a picture holds.
        let paddingFree = String(repeating: "A", count: largestText.count)
        XCTAssertThrowsError(try SVGPictureSource.imageData(fromDataURI: "data:image/png;base64," + paddingFree))

        // Pictures that each fit but together exceed a drawing's budget.
        let largePicture = "data:image/jpeg;base64," + largestText
        let overBudget = String(repeating: imageElement(href: largePicture), count: 3)
        XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: graphiteSVG(visibleContent: overBudget, payload: drawingPayload)))

        // An attribute longer than XML parsers accept fails as invalid XML, without crashing.
        let unparseable = "data:image/png;base64," + String(repeating: "A", count: 12_000_000)
        XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: graphiteSVG(visibleContent: imageElement(href: unparseable), payload: drawingPayload)))

        // A frame outside what a drawing can hold.
        let tile = "data:image/png;base64," + (try pictureData(width: 4, height: 4, color: .red, type: .png)).base64EncodedString()
        let badFrame = "<image x=\"0\" y=\"0\" width=\"1e12\" height=\"nan\" preserveAspectRatio=\"none\" xlink:href=\"\(tile)\"/>\n"
        XCTAssertThrowsError(try SVGDrawingFile.vectorDrawing(from: graphiteSVG(visibleContent: badFrame, payload: drawingPayload)))
    }

    func testPreviewOfAnSVGWithPicturesDecodesThemNoLargerThanShown() async throws {
        // A 1,600-pixel photo shown in a 100-point frame of a 200-pixel preview.
        let photo = DrawingBackgroundImage(imageData: try pictureData(width: 1_600, height: 1_200, color: .red, type: .jpeg), frame: CGRect(x: 0, y: 0, width: 100, height: 75))
        let previewImage = try VectorDrawingRenderer.previewImage(of: photo, pixelsPerPoint: 0.5)
        XCTAssertLessThanOrEqual(max(previewImage.width, previewImage.height), 50)
        XCTAssertThrowsError(try VectorDrawingRenderer.previewImage(of: DrawingBackgroundImage(imageData: Data("not a picture".utf8), frame: photo.frame), pixelsPerPoint: 1))

        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: [photo], shapes: [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VectorPictureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("Drawing.svg")
        try SVGDrawingFile.encode(drawing, payload: payload(for: drawing, pictures: [photo], paper: .plain)).write(to: location)
        // The path a note's embed takes.
        let shown = try rendering(of: await ImageFileService().displayImage(at: location, maximumPixelDimension: 400))
        XCTAssertTrue(isClose(shown.color(at: CGPoint(x: 50, y: 40)), to: .red))
        XCTAssertTrue(isWhite(shown.color(at: CGPoint(x: 200, y: 200))))
    }

    // MARK: PDF

    func testPDFDrawingShowsItsPicturesInEveryReaderAndReadsThemBackExactly() throws {
        let scene = try scene()
        let drawingPayload = payload(for: scene.drawing)
        let fileData = try PDFDrawingFile.encode(scene.drawing, payload: drawingPayload)

        assertShowsScene(try pdfRendering(of: fileData), reader: "Core Graphics")
        assertShowsScene(try pdfKitRendering(of: fileData), reader: "PDFKit")
        // The photo is stored as its own JPEG bytes (DCTDecode), not decoded pixels.
        XCTAssertNotNil(fileData.range(of: scene.photo.imageData), "The JPEG is in the file unchanged.")
        let text = String(decoding: fileData, as: UTF8.self)
        XCTAssertTrue(text.contains("/Filter /DCTDecode"))
        XCTAssertTrue(text.contains("/SMask"), "The cut-out keeps its transparency.")

        let reading = PDFDrawingFile.readMetadata(fileData)
        XCTAssertFalse(reading.metadataWasDiscarded)
        XCTAssertEqual(try XCTUnwrap(reading.payload).pictures, [scene.photo, scene.cutOut])

        // A drawing made on an image, alone.
        let photo = DrawingBackgroundImage(imageData: try pictureData(width: 800, height: 600, color: .green, type: .jpeg), frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let onImage = VectorDrawing(size: Self.drawingSize, background: .white, pictures: [photo], shapes: [try band(fromX: 20, toX: 380, atY: 150)])
        let onImageFile = try PDFDrawingFile.encode(onImage, payload: DrawingPayload(width: 400, height: 300, background: .white, strokes: Data("strokes".utf8), backgroundImage: photo))
        XCTAssertEqual(PDFDrawingFile.readMetadata(onImageFile).payload?.backgroundImage, photo)
        let shown = try pdfRendering(of: onImageFile)
        XCTAssertTrue(isClose(shown.color(at: CGPoint(x: 200, y: 60)), to: .green))
        XCTAssertTrue(isClose(shown.color(at: CGPoint(x: 398, y: 298)), to: .green))
        XCTAssertTrue(isBlack(shown.color(at: CGPoint(x: 200, y: 150))))
    }

    func testPDFWithTheWholePictureBudgetFitsAndRoundTrips() throws {
        let pictures = try picturesFillingTheBudget()
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: pictures, shapes: [try band(fromX: 20, toX: 380, atY: 250)])
        let fileData = try PDFDrawingFile.encode(drawing, payload: payload(for: drawing))
        XCTAssertLessThan(fileData.count, PDFDrawingFile.maximumFileBytes)
        XCTAssertEqual(try XCTUnwrap(PDFDrawingFile.readMetadata(fileData).payload).pictures, pictures)
        XCTAssertTrue(isBlack(try pdfRendering(of: fileData).color(at: CGPoint(x: 200, y: 250))))
    }

    func testPDFWithTheMostPicturesADrawingHoldsRoundTrips() throws {
        let pictures = try (0..<SVGDrawingFile.maximumPictureCount).map { pictureIndex in
            // Each a different picture, so none is merged with another.
            let color = PictureColor(red: Double(pictureIndex) / 40, green: 0.3, blue: 0.6)
            return DrawingBackgroundImage(imageData: try pictureData(width: 20, height: 20, color: color, type: pictureIndex.isMultiple(of: 2) ? .jpeg : .png),
                                          frame: CGRect(x: Double(pictureIndex % 11) * 36, y: Double(pictureIndex / 11) * 36, width: 30, height: 30))
        }
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: pictures, shapes: [])
        let drawingPayload = payload(for: drawing, backgroundImage: pictures[0], pictures: Array(pictures.dropFirst()))
        let fileData = try PDFDrawingFile.encode(drawing, payload: drawingPayload)
        let readPayload = try XCTUnwrap(PDFDrawingFile.readMetadata(fileData).payload)
        XCTAssertEqual([readPayload.backgroundImage].compactMap { picture in picture } + readPayload.pictures, pictures)
    }

    /// Renders a drawing with an editing record written for another drawing, the way
    /// `PDFDrawingFile` writes one: the same page commands and resources, other pictures.
    private func pdf(drawing: VectorDrawing, carrying drawingPayload: DrawingPayload) throws -> Data {
        let packet = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:graphite="urn:graphite:drawing:1"><graphite:drawing>\(try drawingPayload.encoded().base64EncodedString())</graphite:drawing></rdf:Description>
        </rdf:RDF></x:xmpmeta><?xpacket end="w"?>
        """
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: drawing.size)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, [kCGPDFContextCreator as String: "Graphite"] as CFDictionary))
        context.addDocumentMetadata(Data(packet.utf8) as CFData)
        context.beginPDFPage(nil)
        context.translateBy(x: 0, y: drawing.size.height)
        context.scaleBy(x: 1, y: -1)
        try VectorDrawingRenderer.draw(drawing, in: context)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    /// Another app that puts other pixels in a picture's image object changes neither the
    /// page's commands nor its resource dictionaries; only the image data shows it.
    func testPDFWhosePictureDataAnotherAppChangedIsNoLongerEditableAndStillShowsIt() throws {
        for type in [UTType.jpeg, .png] {
            let original = DrawingBackgroundImage(imageData: try pictureData(color: .red, type: type), frame: CGRect(x: 40, y: 40, width: 120, height: 80))
            let replacement = DrawingBackgroundImage(imageData: try pictureData(color: .green, type: type), frame: original.frame)
            let ink = [try band(fromX: 20, toX: 380, atY: 200)]
            let originalDrawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: [original], shapes: ink)
            let writtenPayload = try XCTUnwrap(PDFDrawingFile.readMetadata(PDFDrawingFile.encode(originalDrawing, payload: payload(for: originalDrawing))).payload)

            // The same record over the same drawing is accepted, so the file is written as Graphite writes it.
            XCTAssertEqual(PDFDrawingFile.readMetadata(try pdf(drawing: originalDrawing, carrying: writtenPayload)).payload, writtenPayload, "\(type)")
            let changedFile = try pdf(drawing: VectorDrawing(size: Self.drawingSize, background: .white, pictures: [replacement], shapes: ink), carrying: writtenPayload)
            let changedReading = PDFDrawingFile.readMetadata(changedFile)
            XCTAssertNil(changedReading.payload, "\(type)")
            XCTAssertTrue(changedReading.metadataWasDiscarded, "\(type)")
            let shown = try pdfKitRendering(of: changedFile)
            XCTAssertTrue(isClose(shown.color(at: CGPoint(x: 80, y: 60)), to: .green), "The other app's picture is shown: \(type)")
            XCTAssertTrue(isBlack(shown.color(at: CGPoint(x: 300, y: 200))))
        }
    }

    func testPDFWithABytePatchedPictureOrAMovedPictureIsNoLongerEditable() throws {
        let scene = try scene()
        let fileData = try PDFDrawingFile.encode(scene.drawing, payload: payload(for: scene.drawing))
        let photoRange = try XCTUnwrap(fileData.range(of: scene.photo.imageData))
        // A byte in the middle of the compressed picture, patched in place: the file's
        // structure and every length stay the same.
        var patched = fileData
        let patchedIndex = photoRange.lowerBound + scene.photo.imageData.count / 2
        patched[patchedIndex] = patched[patchedIndex] ^ 0x55
        XCTAssertNotNil(PDFDocument(data: patched), "The patched file is still a PDF.")
        let patchedReading = PDFDrawingFile.readMetadata(patched)
        XCTAssertNil(patchedReading.payload)
        XCTAssertTrue(patchedReading.metadataWasDiscarded)

        var movedPictures = scene.drawing.pictures
        movedPictures[0] = scene.photo.offsetBy(dx: 30, dy: 0)
        let movedDrawing = VectorDrawing(size: Self.drawingSize, background: .white, shapesUnderPictures: scene.drawing.shapesUnderPictures,
                                         pictures: movedPictures, shapes: scene.drawing.shapes)
        let writtenPayload = try XCTUnwrap(PDFDrawingFile.readMetadata(fileData).payload)
        XCTAssertNil(PDFDrawingFile.readMetadata(try pdf(drawing: movedDrawing, carrying: writtenPayload)).payload)
    }

    /// Two different photos of exactly the same length: whichever one Core Graphics resolves
    /// for either image, a change to either is seen.
    func testPDFWithTwoPicturesOfTheSameLengthSeesAChangeToEither() throws {
        // Photos of one color and the same size are usually the same length whatever the color.
        var photosByLength: [Int: Data] = [:]
        var samePhotoLength: (first: Data, second: Data)?
        for redStep in 0..<40 where samePhotoLength == nil {
            let photo = try pictureData(color: PictureColor(red: 0.5 + Double(redStep) / 100, green: 0.1, blue: 0.1), type: .jpeg)
            if let earlierPhoto = photosByLength[photo.count], earlierPhoto != photo { samePhotoLength = (earlierPhoto, photo) }
            photosByLength[photo.count] = photo
        }
        let (firstPhoto, secondPhoto) = try XCTUnwrap(samePhotoLength)
        let pictures = [DrawingBackgroundImage(imageData: firstPhoto, frame: CGRect(x: 20, y: 20, width: 100, height: 50)),
                        DrawingBackgroundImage(imageData: secondPhoto, frame: CGRect(x: 200, y: 20, width: 100, height: 50))]
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: pictures, shapes: [])
        let fileData = try PDFDrawingFile.encode(drawing, payload: payload(for: drawing))
        XCTAssertNotNil(PDFDrawingFile.readMetadata(fileData).payload)
        for photo in [firstPhoto, secondPhoto] {
            let range = try XCTUnwrap(fileData.range(of: photo))
            var patched = fileData
            patched[range.lowerBound + photo.count / 2] ^= 0x42
            XCTAssertNil(PDFDrawingFile.readMetadata(patched).payload)
        }
    }

    func testPDFRewrittenByPDFKitWithoutChangesKeepsItsPicturesEditable() throws {
        let scene = try scene()
        let fileData = try PDFDrawingFile.encode(scene.drawing, payload: payload(for: scene.drawing))
        let rewritten = try XCTUnwrap(PDFDocument(data: fileData)?.dataRepresentation())
        XCTAssertEqual(PDFDrawingFile.readMetadata(rewritten).payload?.pictures, [scene.photo, scene.cutOut])
    }

    func testImageStreamsFoundInTheFileDecodeAsCoreGraphicsDecodesThem() throws {
        let scene = try scene()
        let fileData = try PDFDrawingFile.encode(scene.drawing, payload: payload(for: scene.drawing))
        let page = try XCTUnwrap(CGDataProvider(data: fileData as CFData).flatMap(CGPDFDocument.init)?.page(at: 1))
        var resources: CGPDFDictionaryRef?, externalObjects: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(page.dictionary), "Resources", &resources))
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(resources), "XObject", &externalObjects))
        var streams: [CGPDFStreamRef] = []
        CGPDFDictionaryApplyBlock(try XCTUnwrap(externalObjects), { _, object, _ in
            var stream: CGPDFStreamRef?
            if CGPDFObjectGetValue(object, .stream, &stream), let stream {
                streams.append(stream)
                var maskStream: CGPDFStreamRef?
                if let dictionary = CGPDFStreamGetDictionary(stream), CGPDFDictionaryGetStream(dictionary, "SMask", &maskStream), let maskStream { streams.append(maskStream) }
            }
            return true
        }, nil)
        XCTAssertEqual(streams.count, 3, "The photo, the cut-out and the cut-out's transparency.")
        let file = PDFFileBytes(byteCount: fileData.count, readBytes: { fileData })
        for stream in streams {
            var format = CGPDFDataFormat.raw
            let expected = try XCTUnwrap(CGPDFStreamCopyData(stream, &format)) as Data
            var decoded = Data()
            let decodedByteCount = PDFDrawingStreamDecoder.decodeEveryCandidate(of: stream, in: file, maximumDecodedBytes: 10_000_000, into: &decoded) { decoded, chunk in decoded.append(chunk) }
            XCTAssertEqual(decoded, expected, "Format \(format.rawValue)")
            XCTAssertEqual(decodedByteCount, expected.count)
            var bounded = Data()
            XCTAssertNil(PDFDrawingStreamDecoder.decodeEveryCandidate(of: stream, in: file, maximumDecodedBytes: expected.count - 1, into: &bounded) { bounded, chunk in bounded.append(chunk) })
            XCTAssertTrue(bounded.isEmpty)
        }
        XCTAssertTrue(streams.contains { stream in
            var format = CGPDFDataFormat.raw
            _ = CGPDFStreamCopyData(stream, &format)
            return format == .jpegEncoded
        })
    }

    /// Found on iPad: a picture's length, counted from the start of the next image's data,
    /// ran over that image and its mask's header and ended exactly at the mask's end. The
    /// numbering of objects decides that, and it differs once the metadata is added, so the
    /// finished file no longer matched its own digest.
    func testAStreamLengthThatRunsIntoALaterStreamIsNotACandidate() throws {
        let firstObject = "1 0 obj\n<< /Type /XObject /Subtype /Image /Length 12 >>\nstream\nfirst image!\nendstream\nendobj\n"
        let secondObject = "2 0 obj\n<< /Type /XObject /Subtype /Image /Length 6 >>\nstream\nmask..\nendstream\nendobj\n"
        let fileBytes = Data((firstObject + secondObject).utf8)
        let rawStreams = PDFDrawingStreamDecoder.rawStreams(in: fileBytes)
        XCTAssertEqual(rawStreams.count, 2)
        let keys: Set<String> = ["Type", "Subtype", "Length"]
        let firstDataStart = try XCTUnwrap(rawStreams.first).dataStart
        let secondDataEnd = try XCTUnwrap(rawStreams.last).dataStart + 6
        let spanningLength = secondDataEnd - firstDataStart
        XCTAssertTrue(PDFDrawingStreamDecoder.rawStreamCandidates(in: fileBytes, rawStreams: rawStreams, declaredLength: spanningLength, keys: keys).isEmpty,
                      "A length that runs past the first stream's end is no stream at all.")
        XCTAssertEqual(PDFDrawingStreamDecoder.rawStreamCandidates(in: fileBytes, rawStreams: rawStreams, declaredLength: 12, keys: keys).map { range in fileBytes[range] },
                       [Data("first image!".utf8)])
        XCTAssertEqual(PDFDrawingStreamDecoder.rawStreamCandidates(in: fileBytes, rawStreams: rawStreams, declaredLength: 6, keys: keys).map { range in fileBytes[range] },
                       [Data("mask..".utf8)])
    }

    func testPicturesThatCannotBeReadAreNotWritten() {
        let unreadable = DrawingBackgroundImage(imageData: Data("not a picture".utf8), frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let drawing = VectorDrawing(size: Self.drawingSize, background: .white, pictures: [unreadable], shapes: [])
        XCTAssertThrowsError(try PDFDrawingFile.encode(drawing, payload: nil))
        XCTAssertThrowsError(try SVGDrawingFile.encode(drawing, payload: nil))
    }

    // MARK: WebKit

    #if canImport(AppKit)
    /// The SVG as WebKit (Safari, and Obsidian on iPad) shows it.
    @MainActor
    private func webKitRendering(of fileData: Data) async throws -> Rendering {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VectorPictureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = directory.appendingPathComponent("Drawing.svg")
        try fileData.write(to: location)
        let webView = WKWebView(frame: CGRect(origin: .zero, size: Self.drawingSize))
        let navigationWaiter = NavigationWaiter()
        webView.navigationDelegate = navigationWaiter
        webView.loadFileURL(location, allowingReadAccessTo: directory)
        try await navigationWaiter.waitForLoad()
        // Pictures in data URIs are decoded after the load finishes.
        var lastRendering: Rendering?
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: .zero, size: Self.drawingSize)
            let snapshot = try await webView.takeSnapshot(configuration: configuration)
            var proposedRect = CGRect(origin: .zero, size: snapshot.size)
            let rendering = try rendering(of: try XCTUnwrap(snapshot.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)))
            lastRendering = rendering
            if isClose(rendering.color(at: CGPoint(x: 60, y: 56)), to: .red) { break }
        }
        return try XCTUnwrap(lastRendering)
    }

    @MainActor
    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, any Error>?
        private var outcome: Result<Void, any Error>?

        func waitForLoad() async throws {
            if let outcome { return try outcome.get() }
            try await withCheckedThrowingContinuation { continuation in self.continuation = continuation }
        }

        private func finish(_ result: Result<Void, any Error>) {
            if let continuation {
                self.continuation = nil
                continuation.resume(with: result)
            } else {
                outcome = result
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    }

    @MainActor
    func testSVGDrawingWithPicturesShowsInWebKit() async throws {
        let scene = try scene()
        let fileData = try SVGDrawingFile.encode(scene.drawing, payload: payload(for: scene.drawing))
        assertShowsScene(try await webKitRendering(of: fileData), reader: "WebKit")
    }
    #endif
}
