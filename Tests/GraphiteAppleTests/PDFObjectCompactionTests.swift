import XCTest
import PDFKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteApple

/// Saved PDFs hold only what their pages and catalog still use: a picture moved, turned or
/// cropped, erased ink and removed markup leave no copies behind, and nothing a reader or
/// Graphite uses is lost.
final class PDFObjectCompactionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("GraphitePDFCompaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Fixtures

    /// A photo-like JPEG of random 4-point blocks, which compresses about as badly as a photo.
    private static func photoJPEG(width: Int = 600, height: Int = 400, colorSpaceName: CFString = CGColorSpace.sRGB) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: colorSpaceName))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        var generator = SystemRandomNumberGenerator()
        for row in stride(from: 0, to: height, by: 4) {
            for column in stride(from: 0, to: width, by: 4) {
                context.setFillColor(CGColor(colorSpace: colorSpace, components: [.random(in: 0...1, using: &generator), .random(in: 0...1, using: &generator),
                                                                                   .random(in: 0...1, using: &generator), 1])!)
                context.fill(CGRect(x: column, y: row, width: 4, height: 4))
            }
        }
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func stroke(named name: String, at height: CGFloat) -> PortableInkStroke {
        let start = CGPoint(x: 100, y: height), end = CGPoint(x: 400, y: height)
        let outline = [[CGPoint(x: start.x, y: start.y - 2), CGPoint(x: end.x, y: end.y - 2), CGPoint(x: end.x, y: end.y + 2), CGPoint(x: start.x, y: start.y + 2)]]
        return PortableInkStroke(name: name, segments: [[start, end]], width: 1, red: 0, green: 0, blue: 0, alpha: 1, outline: outline)
    }

    /// A PDF written by hand, with a correct cross-reference table, from object bodies
    /// numbered from 1.
    private static func handWrittenPDF(objects: [String], trailerExtras: String = "") -> Data {
        var text = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R \(trailerExtras) >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(text.utf8)
    }

    /// Two pages with an outline, page labels, a link, a filled form field, named
    /// destinations, viewer settings, document information and another application's
    /// annotation with a key of its own.
    private static func richPDF() -> Data {
        handWrittenPDF(objects: [
            // 1: catalog
            "<< /Type /Catalog /Pages 2 0 R /Outlines 5 0 R /PageLabels << /Nums [0 << /S /r >> 1 << /S /D /St 7 >>] >> /AcroForm << /Fields [8 0 R] >> /Names << /Dests 10 0 R >> /ViewerPreferences << /DisplayDocTitle true >> /PageLayout /OneColumn >>",
            // 2: pages
            "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
            // 3: first page, with a link, a form field and another application's square
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [7 0 R 8 0 R 9 0 R] >>",
            // 4: second page
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
            // 5: outline root and 6: its one entry
            "<< /Type /Outlines /First 6 0 R /Last 6 0 R /Count 1 >>",
            "<< /Title (Chapter Two) /Parent 5 0 R /Dest [4 0 R /XYZ 0 792 0] >>",
            // 7: link to the second page
            "<< /Type /Annot /Subtype /Link /Rect [50 700 150 720] /Border [0 0 0] /Dest [4 0 R /Fit] >>",
            // 8: a filled text field
            "<< /Type /Annot /Subtype /Widget /FT /Tx /T (Student) /V (Ada) /Rect [50 600 250 620] /P 3 0 R >>",
            // 9: another application's annotation
            "<< /Type /Annot /Subtype /Square /Rect [300 300 400 400] /C [1 0 0] /NM (other-square) /OtherApplicationKey (kept) >>",
            // 10: named destinations
            "<< /Names [(second) [4 0 R /Fit]] >>",
            // 11: document information
            "<< /Title (Lecture Notes) /Author (Graphite Tests) >>",
        ], trailerExtras: "/Info 11 0 R")
    }

    private func save(_ edits: [PDFEdit], to location: URL, revision: FileRevision) async throws -> FileRevision {
        try await PDFFileService().save(url: location, revision: revision, edits: edits)
    }

    private func fileSize(_ location: URL) throws -> Int {
        try XCTUnwrap(location.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    // MARK: Growth

    func testMovingTurningAndCroppingAPictureKeepsTheFileSizeBoundedAndStoresTheJPEG() async throws {
        let location = directory.appendingPathComponent("Notebook.pdf")
        var revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
        let emptySize = try fileSize(location)
        let jpegData = try Self.photoJPEG()
        var picture = PDFPicture(imageData: jpegData, bounds: CGRect(x: 100, y: 300, width: 300, height: 200), quarterTurns: 0)
        revision = try await save([.addPicture(page: 0, picture: picture)], to: location, revision: revision)
        let sizeWithPicture = try fileSize(location)
        // The JPEG is in the file as it is, once as the appearance and once (base64) for
        // re-editing, rather than as inflated pixels and a second base64 copy.
        XCTAssertLessThan(sizeWithPicture - emptySize, jpegData.count * 5 / 2, "The picture is stored at about its own size.")
        let savedBytes = try Data(contentsOf: location)
        XCTAssertEqual(savedBytes.ranges(of: Data("/GraphitePictureV1".utf8)).count, 1, "The picture's bytes for re-editing are stored once.")
        XCTAssertNotNil(savedBytes.range(of: jpegData), "The appearance image is the picture's own JPEG.")
        XCTAssertNil(savedBytes.range(of: Data("/SMask".utf8)), "No soft mask is kept for an opaque JPEG.")

        for moveIndex in 1...5 {
            let newBounds = CGRect(x: 100 + CGFloat(moveIndex) * 10, y: 300, width: 300, height: 200)
            revision = try await save([.movePicture(picture.reference(onPageAt: 0), to: newBounds)], to: location, revision: revision)
            picture.bounds = newBounds
        }
        // Turning and cropping replace the picture with another one of the same size.
        let turned = PDFPicture(name: picture.name, imageData: jpegData, bounds: picture.bounds, quarterTurns: 1)
        revision = try await save([.replacePicture(picture.reference(onPageAt: 0), with: turned, order: .unchanged)], to: location, revision: revision)
        XCTAssertLessThan(try fileSize(location), sizeWithPicture + 4_096, "Earlier copies of the picture are gone after five moves and a turn.")

        let savedPage = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
        XCTAssertEqual(PDFPageManager.pictures(on: savedPage), [turned], "Graphite reads its picture back exactly.")
        XCTAssertEqual(savedPage.annotations.map(\.type), ["Stamp"])
    }

    /// A picture turned by hand is stored under `turnedPictureKey`, with its angle, and its
    /// appearance draws the image through a rotation: it is stored as small as an upright
    /// one, and read back with its angle and bytes.
    func testATurnedPictureMovedFiveTimesStaysAsSmallAsAnUprightOneAndIsReadBackWithItsAngle() async throws {
        let jpegData = try Self.photoJPEG()
        // A hand-turned angle, a quarter turn, and a hand-turned angle on a page shown turned.
        let cases: [(label: String, rotationRadians: Double, quarterTurns: Int)] = [
            ("30 degrees", .pi / 6, 0), ("quarter turn", .pi / 2, 0), ("30 degrees on a page turned once", .pi / 6, 1),
        ]
        for testCase in cases {
            let location = directory.appendingPathComponent("Turned-\(UUID().uuidString).pdf")
            var revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1), at: location)
            let emptySize = try fileSize(location)
            var picture = PDFPicture(imageData: jpegData, bounds: CGRect(x: 150, y: 300, width: 300, height: 200), quarterTurns: testCase.quarterTurns,
                                     rotationRadians: testCase.rotationRadians)
            revision = try await save([.addPicture(page: 0, picture: picture)], to: location, revision: revision)
            let sizeWithPicture = try fileSize(location)
            XCTAssertLessThan(sizeWithPicture - emptySize, jpegData.count * 5 / 2, "The turned picture is stored at about its own size, \(testCase.label).")
            for moveIndex in 1...5 {
                let newBounds = CGRect(x: 150 + CGFloat(moveIndex) * 10, y: 300, width: 300, height: 200)
                revision = try await save([.movePicture(picture.reference(onPageAt: 0), to: newBounds)], to: location, revision: revision)
                picture.bounds = newBounds
            }
            XCTAssertLessThan(try fileSize(location), sizeWithPicture + 4_096, "Five moves add nothing, \(testCase.label).")
            XCTAssertLessThan(try fileSize(location) - emptySize, jpegData.count * 5 / 2, "Still about the picture's own size, \(testCase.label).")

            let savedBytes = try Data(contentsOf: location)
            XCTAssertEqual(savedBytes.ranges(of: Data("/GraphitePictureV2".utf8)).count, 1, "The picture's bytes for re-editing are stored once, \(testCase.label).")
            XCTAssertNotNil(savedBytes.range(of: jpegData), "The appearance image is the picture's own JPEG, \(testCase.label).")
            XCTAssertNil(savedBytes.range(of: Data("/SMask".utf8)), "No soft mask is kept for an opaque JPEG, \(testCase.label).")

            let savedPage = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
            XCTAssertEqual(savedPage.annotations.map(\.type), ["Stamp"])
            let readBack = try XCTUnwrap(PDFPageManager.pictures(on: savedPage).first, testCase.label)
            XCTAssertEqual(readBack.name, picture.name)
            XCTAssertEqual(readBack.imageData, jpegData, "Graphite reads its picture's bytes back, \(testCase.label).")
            XCTAssertEqual(readBack.rotationRadians, testCase.rotationRadians, accuracy: 0.0001, "and its angle, \(testCase.label)")
            XCTAssertEqual(readBack.quarterTurns, testCase.quarterTurns)
            for (readEdge, expectedEdge) in zip([readBack.bounds.minX, readBack.bounds.minY, readBack.bounds.width, readBack.bounds.height],
                                                [picture.bounds.minX, picture.bounds.minY, picture.bounds.width, picture.bounds.height]) {
                XCTAssertEqual(readEdge, expectedEdge, accuracy: 0.01, "and its frame, \(testCase.label)")
            }
        }
    }

    func testATurnedPictureStoredAsItsJPEGLooksTheSameAsThePixelsPDFKitWrote() throws {
        for (rotationRadians, quarterTurns) in [(Double.pi / 6, 0), (.pi / 2, 0), (-.pi / 3, 1), (.pi / 2, 3)] {
            // Shown at three quarters of its pixels, where it is resampled; much smaller, a reader
            // that draws a JPEG at reduced size shows it differently from one that draws pixels.
            let jpegData = try Self.photoJPEG(width: 480, height: 320)
            let blank = try XCTUnwrap(PDFDocument(data: try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1)))
            let picture = PDFPicture(imageData: jpegData, bounds: CGRect(x: 150, y: 300, width: 360, height: 240), quarterTurns: quarterTurns,
                                     rotationRadians: rotationRadians)
            try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: blank)
            let pixelsPDF = try XCTUnwrap(blank.dataRepresentation())
            let compacted = try XCTUnwrap(PDFObjectCompaction.compacted(pixelsPDF), "PDFKit wrote the turned picture as pixels (\(rotationRadians), \(quarterTurns))")
            XCTAssertEqual(compacted.report.picturesStoredAsJPEG, 1)
            XCTAssertEqual(compacted.report.pictureMarkupCopiesRemoved, 1)
            XCTAssertLessThan(compacted.data.count, pixelsPDF.count)
            let pixelsImage = try Self.rendered(pixelsPDF), jpegImage = try Self.rendered(compacted.data)
            XCTAssertLessThanOrEqual(try Self.largestChannelDifference(pixelsImage, jpegImage), 3, "Rendered the same, turned \(rotationRadians), page turned \(quarterTurns)")
            let emptyPage = try Self.rendered(try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1))
            XCTAssertGreaterThan(try Self.largestChannelDifference(emptyPage, jpegImage), 50, "The picture is on the page that was compared.")
            // Reopened, Graphite still reads the picture's bytes and angle.
            let reopenedDocument = try XCTUnwrap(PDFDocument(data: compacted.data))
            PDFPageManager.prepareForDisplay(reopenedDocument)
            let reopenedPicture = try XCTUnwrap(PDFPageManager.pictures(on: try XCTUnwrap(reopenedDocument.page(at: 0))).first)
            XCTAssertEqual(reopenedPicture.rotationRadians, rotationRadians, accuracy: 0.0001)
            XCTAssertEqual(reopenedPicture.imageData, jpegData)
        }
    }

    func testErasedInkAndRemovedMarkupLeaveNoCopiesBehind() async throws {
        let location = directory.appendingPathComponent("Notebook.pdf")
        var revision = try await PDFFileService().create(documentData: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 2), at: location)
        let keptInk = PDFEdit.updateInk(PDFInkUpdate(pageIndex: 1, group: "kept", removal: .strokes([]), addedStrokes: [Self.stroke(named: "K", at: 200)],
                                                     editableRecord: PDFEditableInkRecord(drawingData: Data([7, 7]), strokeNames: ["K"])))
        revision = try await save([keptInk], to: location, revision: revision)
        let sizeBefore = try fileSize(location)
        for round in 0..<4 {
            let strokes = (0..<20).map { strokeIndex in Self.stroke(named: "S\(round)-\(strokeIndex)", at: 300 + CGFloat(strokeIndex) * 10) }
            revision = try await save([.updateInk(PDFInkUpdate(pageIndex: 0, group: "ink", removal: .strokes([]), addedStrokes: strokes,
                                                               editableRecord: PDFEditableInkRecord(drawingData: Data(repeating: 1, count: 50_000),
                                                                                                    strokeNames: strokes.compactMap(\.name))))],
                                      to: location, revision: revision)
            revision = try await save([.updateInk(PDFInkUpdate(pageIndex: 0, group: "ink", removal: .entireGroup, addedStrokes: [], editableRecord: nil))],
                                      to: location, revision: revision)
            let markup = PDFMarkup(name: "H\(round)", kind: .highlight, color: .yellow, lineBounds: [CGRect(x: 100, y: 500, width: 200, height: 20)])
            revision = try await save([.addMarkup(page: 0, markup: markup)], to: location, revision: revision)
            let reference = PDFAnnotationReference(pageIndex: 0, name: markup.name, annotationType: "Highlight", bounds: .zero)
            revision = try await save([.removeAnnotation(reference)], to: location, revision: revision)
        }
        XCTAssertLessThan(try fileSize(location), sizeBefore + 1_024, "Erased strokes and removed markup are not kept in the file.")
        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertTrue(try XCTUnwrap(saved.page(at: 0)).annotations.isEmpty)
        let inkPage = try XCTUnwrap(saved.page(at: 1))
        XCTAssertEqual(PDFInkGroups.editableGroup(on: inkPage)?.record.strokeNames, ["K"], "The re-editing record of the ink that stays is kept.")
        XCTAssertEqual(PDFInkGroups.editableGroup(on: inkPage)?.record.drawingData, Data([7, 7]))
    }

    // MARK: Nothing is lost

    func testSavingKeepsOutlineLinksFormsPageLabelsMetadataAndOtherApplicationsAnnotations() async throws {
        let location = directory.appendingPathComponent("Lecture.pdf")
        try Self.richPDF().write(to: location)
        XCTAssertEqual(PDFDocument(url: location)?.pageCount, 2, "The hand-written PDF is valid.")
        var revision = try FileRevision.read(location)
        let catalogKeysBefore = try Self.catalogKeys(of: location)
        var picture = PDFPicture(imageData: try Self.photoJPEG(width: 200, height: 100), bounds: CGRect(x: 300, y: 500, width: 200, height: 100), quarterTurns: 0)
        revision = try await save([.addPicture(page: 0, picture: picture)], to: location, revision: revision)
        for moveIndex in 1...3 {
            let newBounds = picture.bounds.offsetBy(dx: 0, dy: CGFloat(moveIndex) * 5)
            revision = try await save([.movePicture(picture.reference(onPageAt: 0), to: newBounds)], to: location, revision: revision)
            picture.bounds = newBounds
        }

        XCTAssertEqual(try Self.catalogKeys(of: location), catalogKeysBefore, "Every catalog entry is kept.")
        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(saved.page(at: 0)?.label, "i")
        XCTAssertEqual(saved.page(at: 1)?.label, "7")
        let chapter = try XCTUnwrap(saved.outlineRoot?.child(at: 0))
        XCTAssertEqual(chapter.label, "Chapter Two")
        XCTAssertEqual(chapter.destination?.page.map(saved.index(for:)), 1)
        XCTAssertEqual(saved.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Lecture Notes")
        XCTAssertEqual(saved.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String, "Graphite Tests")
        let annotations = try XCTUnwrap(saved.page(at: 0)).annotations
        let link = try XCTUnwrap(annotations.first { annotation in annotation.type == "Link" })
        XCTAssertEqual(link.destination?.page.map(saved.index(for:)), 1)
        let field = try XCTUnwrap(annotations.first { annotation in annotation.type == "Widget" })
        XCTAssertEqual(field.fieldName, "Student")
        XCTAssertEqual(field.widgetStringValue, "Ada")
        let square = try XCTUnwrap(annotations.first { annotation in annotation.type == "Square" })
        XCTAssertEqual(square.persistentName, "other-square")
        XCTAssertEqual(square.value(forAnnotationKey: PDFAnnotationKey(rawValue: "OtherApplicationKey")) as? String, "kept")
        XCTAssertEqual(PDFPageManager.pictures(on: try XCTUnwrap(saved.page(at: 0))), [picture])
        try Self.withCatalog(of: location) { catalog in
            var names: CGPDFDictionaryRef?, destinations: CGPDFDictionaryRef?, destinationNames: CGPDFArrayRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(catalog, "Names", &names))
            XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(names), "Dests", &destinations))
            XCTAssertTrue(CGPDFDictionaryGetArray(try XCTUnwrap(destinations), "Names", &destinationNames), "Named destinations are kept.")
            var form: CGPDFDictionaryRef?, fields: CGPDFArrayRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form))
            XCTAssertTrue(CGPDFDictionaryGetArray(try XCTUnwrap(form), "Fields", &fields))
            XCTAssertEqual(CGPDFArrayGetCount(try XCTUnwrap(fields)), 1, "The form still lists its field.")
        }
    }

    func testAnUneditedSaveOfAFileWithoutUnusedObjectsIsLeftAsPDFKitWroteIt() throws {
        let pdfData = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .grid), pageCount: 3)
        let written = try XCTUnwrap(PDFDocument(data: pdfData)?.dataRepresentation())
        XCTAssertNil(PDFObjectCompaction.compacted(written), "Nothing is rewritten when every object is used.")
    }

    func testFilesNotWrittenAsPDFKitWritesThemAreLeftAlone() throws {
        // A file whose objects are all used, an incremental update, an encrypted file, a
        // cross-reference stream, and bytes that are not a PDF.
        let plain = Self.handWrittenPDF(objects: ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                                                  "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>", "<< /Unused true >>"])
        XCTAssertEqual(PDFObjectCompaction.compacted(plain)?.report.removedObjectCount, 1, "A plain table with an unused object is understood.")
        let updated = Self.handWrittenPDF(objects: ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                                                    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>", "<< /Unused true >>"], trailerExtras: "/Prev 9")
        XCTAssertNil(PDFObjectCompaction.compacted(updated))
        let encrypted = Self.handWrittenPDF(objects: ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                                                      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>", "<< /Filter /Standard >>"], trailerExtras: "/Encrypt 4 0 R")
        XCTAssertNil(PDFObjectCompaction.compacted(encrypted))
        let streamCrossReference = Data("%PDF-1.7\n1 0 obj\n<< /Type /XRef /Size 2 /W [1 2 1] >>\nstream\n\nendstream\nendobj\nstartxref\n9\n%%EOF\n".utf8)
        XCTAssertNil(PDFObjectCompaction.compacted(streamCrossReference))
        XCTAssertNil(PDFObjectCompaction.compacted(Data("not a PDF at all".utf8)))
        XCTAssertNil(PDFObjectCompaction.compacted(plain.prefix(plain.count / 2)))
    }

    func testCompactedFileIsReadByCoreGraphicsWithTheSameObjects() throws {
        let plain = Self.handWrittenPDF(objects: ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                                                  "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Annots [5 0 R] >>", "<< /Unused (a \\) 9 0 R string) >>",
                                                  "<< /Type /Annot /Subtype /Text /Rect [0 0 10 10] /Contents (6 0 R is not a reference) >>", "<< /AlsoUnused [4 0 R] >>"])
        let compacted = try XCTUnwrap(PDFObjectCompaction.compacted(plain))
        XCTAssertEqual(compacted.report.removedObjectCount, 2, "Objects referred to only by unused ones, or only from inside strings, are unused.")
        let document = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: compacted.data as CFData))))
        XCTAssertEqual(document.numberOfPages, 1)
        let reopened = try XCTUnwrap(PDFDocument(data: compacted.data))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.first?.contents, "6 0 R is not a reference")
        let text = String(decoding: compacted.data, as: UTF8.self)
        XCTAssertFalse(text.contains("/Unused"))
        XCTAssertFalse(text.contains("/AlsoUnused"))
        XCTAssertTrue(text.contains("0000000004 65535 f\r\n0000000"), "The free list starts at the first removed number.")
        XCTAssertTrue(text.contains("0000000006 00001 f\r\n"), "A removed number leads to the next one, with its generation raised.")
    }

    // MARK: Pictures as JPEG

    func testPictureStoredAsItsJPEGLooksTheSameAsThePixelsPDFKitWrote() throws {
        for colorSpaceName in [CGColorSpace.sRGB, CGColorSpace.displayP3] {
            let jpegData = try Self.photoJPEG(width: 120, height: 80, colorSpaceName: colorSpaceName)
            let blank = try XCTUnwrap(PDFDocument(data: try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 1)))
            let picture = PDFPicture(imageData: jpegData, bounds: CGRect(x: 100, y: 300, width: 360, height: 240), quarterTurns: 0)
            try PDFPageManager.replay([.addPicture(page: 0, picture: picture)], on: blank)
            let pixelsPDF = try XCTUnwrap(blank.dataRepresentation())
            let compacted = try XCTUnwrap(PDFObjectCompaction.compacted(pixelsPDF), "PDFKit wrote the picture as pixels")
            XCTAssertEqual(compacted.report.picturesStoredAsJPEG, 1)
            XCTAssertLessThan(compacted.data.count, pixelsPDF.count)
            let pixelsImage = try Self.rendered(pixelsPDF), jpegImage = try Self.rendered(compacted.data)
            XCTAssertLessThanOrEqual(try Self.largestChannelDifference(pixelsImage, jpegImage), 3, "Rendered the same in \(colorSpaceName)")
        }
    }

    // MARK: Helpers

    private static func rendered(_ pdfData: Data) throws -> CGImage {
        let page = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data: pdfData as CFData)))?.page(at: 1))
        let mediaBox = page.getBoxRect(.mediaBox)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(mediaBox.width), height: Int(mediaBox.height), bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: mediaBox.size))
        // Annotations are drawn from their appearance streams, as any reader draws them.
        let reopened = try XCTUnwrap(PDFDocument(data: pdfData)?.page(at: 0))
        reopened.draw(with: .mediaBox, to: context)
        return try XCTUnwrap(context.makeImage())
    }

    private static func largestChannelDifference(_ firstImage: CGImage, _ secondImage: CGImage) throws -> Int {
        func bytes(of image: CGImage) throws -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return pixels
        }
        let firstPixels = try bytes(of: firstImage), secondPixels = try bytes(of: secondImage)
        XCTAssertEqual(firstPixels.count, secondPixels.count)
        return zip(firstPixels, secondPixels).reduce(0) { largest, pair in max(largest, abs(Int(pair.0) - Int(pair.1))) }
    }

    private static func withCatalog(of location: URL, body: (CGPDFDictionaryRef) throws -> Void) throws {
        let document = try XCTUnwrap(CGPDFDocument(location as CFURL))
        try withExtendedLifetime(document) { try body(try XCTUnwrap(document.catalog)) }
    }

    private static func catalogKeys(of location: URL) throws -> Set<String> {
        var keys: Set<String> = []
        try withCatalog(of: location) { catalog in
            CGPDFDictionaryApplyBlock(catalog, { key, _, _ in
                keys.insert(String(cString: key))
                return true
            }, nil)
        }
        return keys
    }
}
