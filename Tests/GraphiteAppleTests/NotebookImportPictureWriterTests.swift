import XCTest
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

/// Imported pictures written as Graphite's picture stamps and read back with PDFKit: their frames and angles in PDF
/// space, their order under the ink, the crop, flips and first GIF frame in the stored image, and the refusals.
final class NotebookImportPictureWriterTests: XCTestCase {
    /// The notebook's files by path; a path it lacks is a missing file.
    private struct NotebookFiles: ImportSourceFiles {
        struct MissingFile: Error { let pathInSource: String }
        let contentsByPath: [String: [UInt8]]

        func contents(of file: ImportedSourceFile) throws -> Data {
            guard let contents = contentsByPath[file.pathInSource] else { throw MissingFile(pathInSource: file.pathInSource) }
            return Data(contents)
        }
    }

    private static let pageSize = CGSize(width: 300, height: 400)
    private static let red: [Int] = [255, 0, 0]
    private static let blue: [Int] = [0, 0, 255]
    private let pngFile = NotebookImportPictureWriterTests.sourceFile("Images/two-halves.png")
    private let jpegFile = NotebookImportPictureWriterTests.sourceFile("Images/two-halves.jpg")

    private static func sourceFile(_ text: String) -> ImportedSourceFile {
        guard let path = NotebookArchivePath(validating: text) else { preconditionFailure("not a safe archive path: \(text)") }
        return ImportedSourceFile(path: path)
    }

    // MARK: Synthetic images

    /// 40 × 20 pixels: the left half red and the right half blue, or the top half red and the bottom half blue.
    private func twoHalvesImage(width: Int = 40, height: Int = 20, splitsVertically: Bool = true) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        // Core Graphics counts up: the top half is the upper one.
        context.fill(splitsVertically ? CGRect(x: 0, y: 0, width: width / 2, height: height) : CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        return try XCTUnwrap(context.makeImage())
    }

    private func encoded(_ images: [CGImage], as type: UTType, properties: [CFString: Any]? = nil) throws -> [UInt8] {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, images.count, nil))
        for image in images { CGImageDestinationAddImage(destination, image, properties as CFDictionary?) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return [UInt8](output as Data)
    }

    /// The stored image's size in pixels and its color at a pixel from its top-left corner, as 0 to 255 sRGB.
    private func storedImage(_ imageData: Data, colorAt pixel: (x: Int, y: Int)) throws -> (width: Int, height: Int, color: [Int]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(imageData as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixelBytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixelBytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                                  bytesPerRow: image.width * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (pixel.y * image.width + pixel.x) * 4
        return (image.width, image.height, (0..<3).map { component in Int(pixelBytes[offset + component]) })
    }

    private func assertColor(_ drawnColor: [Int], _ expected: [Int], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (drawnComponent, expectedComponent) in zip(drawnColor, expected) {
            XCTAssertEqual(drawnComponent, expectedComponent, accuracy: 12, "\(message): \(drawnColor)", file: file, line: line)
        }
    }

    // MARK: Writing

    private func picture(_ file: ImportedSourceFile, frame: CGRect, rotation: Double = 0, crop: CGRect? = nil, isFlippedHorizontally: Bool = false,
                         isFlippedVertically: Bool = false) -> ImportedPicture {
        ImportedPicture(file: file, frame: frame, rotationRadiansClockwise: rotation, cropRectangleInPixels: crop,
                        isFlippedHorizontally: isFlippedHorizontally, isFlippedVertically: isFlippedVertically)
    }

    private func plan(pictures: [ImportedPicture], strokes: [ImportedStroke] = [], report: [ImportReportEntry] = []) -> ImportedPagePlan {
        let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)
        return ImportedPagePlan(sourcePageNumber: 1, sizeInPoints: Self.pageSize, background: .plainColor(white), strokes: strokes, pictures: pictures,
                                report: report)
    }

    private func write(_ plan: ImportedPagePlan, files: NotebookFiles,
                       named name: String = "Pictures.pdf") throws -> (page: PDFPage, writing: NotebookImportWriting) {
        let vault = try TemporaryVault.make(prefix: "NotebookImportPictureWriter", for: self)
        let destination = vault.location(of: name)
        let writing = try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(pageCount: 1, planForPage: { _ in plan }, sourceFiles: files,
                                                                                     strokeCreationDate: Date(timeIntervalSinceReferenceDate: 0),
                                                                                     to: destination)
        return (try XCTUnwrap(PDFDocument(url: destination)?.page(at: 0)), writing)
    }

    private func twoHalvesFiles() throws -> NotebookFiles {
        let image = try twoHalvesImage()
        let bestQuality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
        return NotebookFiles(contentsByPath: [pngFile.pathInSource: try encoded([image], as: .png),
                                              jpegFile.pathInSource: try encoded([image], as: .jpeg, properties: bestQuality)])
    }

    private func onlyPicture(on page: PDFPage) throws -> PDFPicture {
        let pictures = PDFPageManager.pictures(on: page)
        XCTAssertEqual(pictures.count, 1)
        return try XCTUnwrap(pictures.first)
    }

    // MARK: Placement and order

    func testPicturesAreGraphiteStampsInPlanOrderWithTheirFramesInPageSpaceAndTheInkOverThem() throws {
        let stroke = ImportedStroke(ink: .pen, color: NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1), samples: [
            ImportedStrokeSample(location: CGPoint(x: 10, y: 50), width: 2, force: nil, azimuthRadians: nil, altitudeRadians: nil),
            ImportedStrokeSample(location: CGPoint(x: 290, y: 50), width: 2, force: nil, azimuthRadians: nil, altitudeRadians: nil)
        ], outline: nil)
        let upright = picture(pngFile, frame: CGRect(x: 20, y: 30, width: 100, height: 50))
        let turned = picture(jpegFile, frame: CGRect(x: 150, y: 200, width: 80, height: 40), rotation: 0.5)
        let (page, _) = try write(plan(pictures: [upright, turned], strokes: [stroke]), files: twoHalvesFiles())
        XCTAssertEqual(page.annotations.map(\.type), ["Stamp", "Stamp", "Ink"], "Pictures first, so the ink is drawn over them (M-15).")
        let pictures = PDFPageManager.pictures(on: page)
        XCTAssertEqual(pictures.count, 2)
        // Top-left (20, 30) to (120, 80) on a 400-point page is (20, 320) to (120, 370) in PDF space.
        XCTAssertEqual(pictures[0].bounds.minX, 20, accuracy: 0.01)
        XCTAssertEqual(pictures[0].bounds.minY, 320, accuracy: 0.01)
        XCTAssertEqual(pictures[0].bounds.width, 100, accuracy: 0.01)
        XCTAssertEqual(pictures[0].bounds.height, 50, accuracy: 0.01)
        XCTAssertEqual(pictures[0].rotationRadians, 0)
        XCTAssertNotNil(page.annotations[0].value(forAnnotationKey: PDFPageManager.pictureKey), "An upright picture is under V1 (M-14).")
        XCTAssertNil(page.annotations[0].value(forAnnotationKey: PDFPageManager.pictureRotationKey))
        // The turned picture keeps its own size about its center, (190, 220) top-left, (190, 180) in PDF space.
        XCTAssertEqual(pictures[1].bounds.midX, 190, accuracy: 0.01)
        XCTAssertEqual(pictures[1].bounds.midY, 180, accuracy: 0.01)
        XCTAssertEqual(pictures[1].bounds.width, 80, accuracy: 0.01)
        XCTAssertEqual(pictures[1].bounds.height, 40, accuracy: 0.01)
        XCTAssertEqual(pictures[1].rotationRadians, 0.5, accuracy: 1e-9)
        XCTAssertNotNil(page.annotations[1].value(forAnnotationKey: PDFPageManager.turnedPictureKey), "A turned picture is under V2 (M-14).")
        XCTAssertEqual((page.annotations[1].value(forAnnotationKey: PDFPageManager.pictureRotationKey) as? NSNumber)?.doubleValue ?? 0, 0.5, accuracy: 1e-9)
        // As every PDF reader draws the stamps' appearance: the upright picture's halves, and the turned one's center.
        assertColor(try drawnColor(of: page, at: CGPoint(x: 45, y: 40)), Self.red, "The upright picture's left half")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 95, y: 70)), Self.blue, "The upright picture's right half")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 180, y: 215)), Self.red, "Left of the turned picture's center")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 200, y: 225)), Self.blue, "Right of the turned picture's center")
    }

    /// The color of the page as drawn, at a point in top-left page coordinates, as 0 to 255 sRGB components.
    private func drawnColor(of page: PDFPage, at point: CGPoint) throws -> [Int] {
        let size = page.bounds(for: .mediaBox).size
        let pixelWidth = Int(size.width), pixelHeight = Int(size.height)
        var pixelBytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        try pixelBytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                                  bytesPerRow: pixelWidth * 4, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            page.draw(with: .mediaBox, to: context)
        }
        let offset = (Int(point.y) * pixelWidth + Int(point.x)) * 4
        return (0..<3).map { component in Int(pixelBytes[offset + component]) }
    }

    func testAnUncroppedPNGOrJPEGKeepsItsBytes() throws {
        let files = try twoHalvesFiles()
        for file in [pngFile, jpegFile] {
            let (page, _) = try write(plan(pictures: [picture(file, frame: CGRect(x: 0, y: 0, width: 40, height: 20))]), files: files)
            XCTAssertEqual([UInt8](try onlyPicture(on: page).imageData), files.contentsByPath[file.pathInSource], file.pathInSource)
        }
    }

    // MARK: Crop, flips and formats

    func testACropKeepsTheShownPixelsAtTheirSizeAndAJPEGStaysAJPEG() throws {
        let files = try twoHalvesFiles()
        let rightHalf = picture(jpegFile, frame: CGRect(x: 0, y: 0, width: 40, height: 40), crop: CGRect(x: 20, y: 0, width: 20, height: 20))
        let (page, _) = try write(plan(pictures: [rightHalf]), files: files)
        let imageData = try onlyPicture(on: page).imageData
        XCTAssertTrue(imageData.starts(with: [0xFF, 0xD8]))
        let stored = try storedImage(imageData, colorAt: (x: 10, y: 10))
        XCTAssertEqual(stored.width, 20)
        XCTAssertEqual(stored.height, 20)
        assertColor(stored.color, Self.blue, "The right half")
    }

    func testACropReachingPastTheImageIsAPNGWithAClearMarginAndFractionalPixelsKeepTheirSize() throws {
        let files = try twoHalvesFiles()
        let widened = picture(jpegFile, frame: CGRect(x: 0, y: 0, width: 60, height: 20), crop: CGRect(x: -20.25, y: 0, width: 60.5, height: 20))
        let (page, _) = try write(plan(pictures: [widened]), files: files)
        let imageData = try onlyPicture(on: page).imageData
        XCTAssertTrue(imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let stored = try storedImage(imageData, colorAt: (x: 30, y: 10))
        XCTAssertEqual(stored.width, 61, "60.5 pixels rounded")
        XCTAssertEqual(stored.height, 20)
        assertColor(stored.color, Self.red, "The image's left half, 20.25 pixels in")
        assertColor(try storedImage(imageData, colorAt: (x: 5, y: 10)).color, [0, 0, 0], "The clear margin, transparent black")
    }

    func testFlipsMirrorTheStoredImage() throws {
        let files = try twoHalvesFiles()
        let (horizontalPage, _) = try write(plan(pictures: [picture(pngFile, frame: CGRect(x: 0, y: 0, width: 40, height: 20), isFlippedHorizontally: true)]),
                                            files: files, named: "Horizontal.pdf")
        let horizontal = try onlyPicture(on: horizontalPage).imageData
        assertColor(try storedImage(horizontal, colorAt: (x: 5, y: 10)).color, Self.blue, "Left after a horizontal flip")
        assertColor(try storedImage(horizontal, colorAt: (x: 35, y: 10)).color, Self.red, "Right after a horizontal flip")
        let topAndBottom = NotebookFiles(contentsByPath: [pngFile.pathInSource: try encoded([twoHalvesImage(splitsVertically: false)], as: .png)])
        let (verticalPage, _) = try write(plan(pictures: [picture(pngFile, frame: CGRect(x: 0, y: 0, width: 40, height: 20), isFlippedVertically: true)]),
                                          files: topAndBottom, named: "Vertical.pdf")
        let vertical = try onlyPicture(on: verticalPage).imageData
        assertColor(try storedImage(vertical, colorAt: (x: 20, y: 2)).color, Self.blue, "Top after a vertical flip")
        assertColor(try storedImage(vertical, colorAt: (x: 20, y: 17)).color, Self.red, "Bottom after a vertical flip")
    }

    func testAnAnimatedGIFBecomesItsFirstFrameAsAPNG() throws {
        let firstFrame = try twoHalvesImage(width: 20, height: 20)
        let secondFrame = try twoHalvesImage(width: 20, height: 20, splitsVertically: false)
        let gifFile = Self.sourceFile("attachments/ANIMATED")
        let files = NotebookFiles(contentsByPath: [gifFile.pathInSource: try encoded([firstFrame, secondFrame], as: .gif)])
        let (page, _) = try write(plan(pictures: [picture(gifFile, frame: CGRect(x: 0, y: 0, width: 20, height: 20))]), files: files)
        let imageData = try onlyPicture(on: page).imageData
        XCTAssertTrue(imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        assertColor(try storedImage(imageData, colorAt: (x: 15, y: 2)).color, Self.blue, "The first frame's right half")
    }

    func testAJPEGTurnedByItsOrientationIsStoredUpright() throws {
        let turnedFile = Self.sourceFile("Images/turned.jpg")
        let files = NotebookFiles(contentsByPath: [turnedFile.pathInSource: try encoded([twoHalvesImage()], as: .jpeg,
                                                                                        properties: [kCGImagePropertyOrientation: 6])])
        let (page, _) = try write(plan(pictures: [picture(turnedFile, frame: CGRect(x: 0, y: 0, width: 20, height: 40))]), files: files)
        let stored = try storedImage(try onlyPicture(on: page).imageData, colorAt: (x: 10, y: 5))
        XCTAssertEqual(stored.width, 20)
        XCTAssertEqual(stored.height, 40)
        // Orientation 6 shows the stored image turned a quarter clockwise: its left (red) half is on top.
        assertColor(stored.color, Self.red, "The top after the orientation")
    }

    // MARK: Missing files and refusals

    func testAMissingPictureFileIsLeftOutAndAddedToThePagesReport() throws {
        let missing = picture(Self.sourceFile("Images/absent.png"), frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let present = picture(pngFile, frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        let (page, writing) = try write(plan(pictures: [missing, present], report: [.pictureFilesMissing(count: 1), .paperRulingNotDrawn]),
                                        files: twoHalvesFiles())
        XCTAssertEqual(PDFPageManager.pictures(on: page).count, 1)
        XCTAssertEqual(writing.pageReports.first?.entries, [.pictureFilesMissing(count: 2), .paperRulingNotDrawn])
        XCTAssertEqual(writing.pageReports.first?.written?.pictureCount, 1, "only the placed picture counts as written")
        XCTAssertEqual(ImportedPagePictures.report([.paperRulingNotDrawn], adding: ImportedPagePictures.LeftOut(missingFileCount: 1)),
                       [.paperRulingNotDrawn, .pictureFilesMissing(count: 1)])
        XCTAssertEqual(ImportedPagePictures.report([.paperRulingNotDrawn], adding: ImportedPagePictures.LeftOut()), [.paperRulingNotDrawn])
    }

    func testAFileThatIsNotAnImageIsLeftOutAndReported() throws {
        let files = NotebookFiles(contentsByPath: [pngFile.pathInSource: Array("not an image".utf8)])
        let pagePlan = plan(pictures: [picture(pngFile, frame: CGRect(x: 0, y: 0, width: 10, height: 10)),
                                       picture(pngFile, frame: CGRect(x: 20, y: 0, width: 10, height: 10))],
                            report: [.pictureFilesMissing(count: 1)])
        let (page, writing) = try write(pagePlan, files: files)
        XCTAssertTrue(PDFPageManager.pictures(on: page).isEmpty)
        XCTAssertEqual(writing.pageReports.first?.entries, [.pictureFilesMissing(count: 1), .picturesNotDecodable(count: 2)])
        XCTAssertEqual(writing.pageReports.first?.written?.pictureCount, 0)
    }

    func testAnUnusableFrameAngleOrCropIsTheTypedError() throws {
        let files = try twoHalvesFiles()
        let flat = picture(pngFile, frame: CGRect(x: 0, y: 0, width: 10, height: 0))
        XCTAssertThrowsError(try write(plan(pictures: [flat]), files: files, named: "Flat.pdf")) { error in
            guard case NotebookImportWriterError.pictureGeometryUnusable(let file, let frame, _, 0) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(file, self.pngFile)
            XCTAssertEqual(frame, flat.frame)
        }
        let spinning = picture(pngFile, frame: CGRect(x: 0, y: 0, width: 10, height: 10), rotation: .infinity)
        XCTAssertThrowsError(try write(plan(pictures: [spinning]), files: files, named: "Spinning.pdf")) { error in
            guard case NotebookImportWriterError.pictureGeometryUnusable = error else { return XCTFail("\(error)") }
        }
        let emptyCrop = picture(pngFile, frame: CGRect(x: 0, y: 0, width: 10, height: 10), crop: CGRect(x: 0, y: 0, width: 0, height: 10))
        XCTAssertThrowsError(try write(plan(pictures: [emptyCrop]), files: files, named: "Empty crop.pdf")) { error in
            guard case NotebookImportWriterError.pictureCropUnusable(_, let crop, 0) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(crop, emptyCrop.cropRectangleInPixels)
        }
    }
}
