import XCTest
import CoreGraphics
import PDFKit
import PencilKit
import GraphiteCore
import GraphiteTestSupport
import Synchronization
@testable import GraphiteApple

/// An imported notebook written as a PDF and read back with PDFKit: its pages, sizes and backgrounds, standard ink
/// annotations in the planned shapes, and Graphite's re-editing record of the planned strokes.
final class NotebookImportWriterTests: XCTestCase {
    /// The notebook's files by path, as a reader of the notebook serves them; a path it lacks is a missing file.
    private struct NotebookFiles: ImportSourceFiles {
        struct MissingFile: Error, Equatable { let pathInSource: String }
        let contentsByPath: [String: [UInt8]]

        func contents(of file: ImportedSourceFile) throws -> [UInt8] {
            guard let contents = contentsByPath[file.pathInSource] else { throw MissingFile(pathInSource: file.pathInSource) }
            return contents
        }
    }

    /// The same files, counting how often each is read.
    private final class ReadCountingFiles: ImportSourceFiles {
        let files: NotebookFiles
        let readCountsByPath = Mutex<[String: Int]>([:])

        init(files: NotebookFiles) {
            self.files = files
        }

        func contents(of file: ImportedSourceFile) throws -> [UInt8] {
            readCountsByPath.withLock { readCounts in readCounts[file.pathInSource, default: 0] += 1 }
            return try files.contents(of: file)
        }
    }

    /// A source page: its size, a paper color filling it, and a red rectangle in top-left page coordinates.
    private struct SourcePage {
        let size: CGSize
        let paper: CGColor
        let redRectangle: CGRect
    }

    private let strokeCreationDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let templateFile = ImportedSourceFile(path: NotebookImportWriterTests.archivePath("attachments/template"))

    /// A path written in the test, which is a safe archive path.
    private static func archivePath(_ text: String) -> NotebookArchivePath {
        guard let path = NotebookArchivePath(validating: text) else { preconditionFailure("not a safe archive path: \(text)") }
        return path
    }
    private let paperYellow = NotebookImportColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let green = CGColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1)
    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    private func sourcePDF(_ pages: [SourcePage], rotation: Int = 0) throws -> [UInt8] {
        let output = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: nil, nil))
        for page in pages {
            var mediaBox = CGRect(origin: .zero, size: page.size)
            let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size) as CFData
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            context.setFillColor(page.paper)
            context.fill(mediaBox)
            context.setFillColor(red)
            let rectangle = page.redRectangle
            context.fill(CGRect(x: rectangle.minX, y: page.size.height - rectangle.maxY, width: rectangle.width, height: rectangle.height))
            context.endPDFPage()
        }
        context.closePDF()
        guard rotation != 0 else { return [UInt8](output as Data) }
        let document = try XCTUnwrap(PDFDocument(data: output as Data))
        for pageIndex in 0..<document.pageCount { document.page(at: pageIndex)?.rotation = rotation }
        return [UInt8](try XCTUnwrap(document.dataRepresentation()))
    }

    private func samples(from start: CGPoint, to end: CGPoint, width: Double, count: Int = 30) -> [ImportedStrokeSample] {
        (0..<count).map { sampleIndex in
            let progress = count > 1 ? Double(sampleIndex) / Double(count - 1) : 0
            return ImportedStrokeSample(location: CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress),
                                        width: width, force: 1, azimuthRadians: nil, altitudeRadians: nil)
        }
    }

    private func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> NotebookImportColor {
        NotebookImportColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// From x = `startX` to `endX` along `y`, without an outline.
    private func horizontalStroke(_ ink: ImportedStroke.Ink, _ strokeColor: NotebookImportColor, y: Double, width: Double,
                                  startX: Double = 60, endX: Double = 400) -> ImportedStroke {
        ImportedStroke(ink: ink, color: strokeColor, samples: samples(from: CGPoint(x: startX, y: y), to: CGPoint(x: endX, y: y), width: width), outline: nil)
    }

    /// A horizontal stroke of each ink, each a different width and color, and a dot.
    private var strokesOfEveryInk: [ImportedStroke] {
        [
            horizontalStroke(.monoline, color(0, 0, 0), y: 100, width: 1.5),
            horizontalStroke(.pen, color(0.1, 0.2, 0.7), y: 200, width: 3),
            horizontalStroke(.fountainPen, color(0.6, 0.1, 0.1), y: 300, width: 5),
            horizontalStroke(.pencil, color(0.3, 0.3, 0.3), y: 400, width: 4),
            horizontalStroke(.highlighter, color(1, 0.85, 0, 0.5), y: 500, width: 20),
            ImportedStroke(ink: .pen, color: color(0, 0.5, 0), samples: samples(from: CGPoint(x: 500, y: 700), to: CGPoint(x: 500, y: 700), width: 6, count: 1),
                           outline: nil)
        ]
    }

    /// Along y = 100 from x = 50 to 250, with an outline from (40, 90) to (260, 112) that is not the round-capped line.
    private var strokeWithOutline: ImportedStroke {
        ImportedStroke(ink: .fountainPen, color: color(0.2, 0.2, 0.6), samples: samples(from: CGPoint(x: 50, y: 100), to: CGPoint(x: 250, y: 100), width: 4),
                       outline: [[CGPoint(x: 40, y: 90), CGPoint(x: 260, y: 90), CGPoint(x: 260, y: 112), CGPoint(x: 40, y: 112)]])
    }

    /// Three pages of three sizes: plain yellow paper, a template page copied as it is, and a template page of another
    /// size stretched to its page.
    private var plans: [ImportedPagePlan] {
        [
            ImportedPagePlan(sourcePageNumber: 1, sizeInPoints: CGSize(width: 595, height: 842), background: .plainColor(paperYellow),
                             strokes: strokesOfEveryInk, report: [.paperRulingNotDrawn]),
            ImportedPagePlan(sourcePageNumber: 2, sizeInPoints: CGSize(width: 300, height: 400), background: .pdfPage(templateFile, pageNumber: 1),
                             strokes: [strokeWithOutline, horizontalStroke(.pen, color(0, 0, 0), y: 300, width: 2, startX: 50, endX: 250)],
                             report: []),
            ImportedPagePlan(sourcePageNumber: 3, sizeInPoints: CGSize(width: 400, height: 300), background: .pdfPage(templateFile, pageNumber: 2),
                             strokes: [], report: [.highlighterNotMultiplied(strokeCount: 1)])
        ]
    }

    private func templateFiles() throws -> NotebookFiles {
        let template = try sourcePDF([
            SourcePage(size: CGSize(width: 300, height: 400), paper: white, redRectangle: CGRect(x: 0, y: 0, width: 150, height: 200)),
            SourcePage(size: CGSize(width: 200, height: 200), paper: green, redRectangle: CGRect(x: 100, y: 100, width: 100, height: 100))
        ])
        return NotebookFiles(contentsByPath: [templateFile.pathInSource: template])
    }

    private func writeNotebook(_ plans: [ImportedPagePlan], files: NotebookFiles, to destination: URL) throws -> NotebookImportWriting {
        try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(pageCount: plans.count, planForPage: { pageIndex in plans[pageIndex] },
                                                                       sourceFiles: files, strokeCreationDate: strokeCreationDate, to: destination)
    }

    private func writtenDocument(_ plans: [ImportedPagePlan]) throws -> (document: PDFDocument, writing: NotebookImportWriting) {
        let vault = try TemporaryVault.make(prefix: "NotebookImportWriter", for: self)
        let destination = vault.location(of: "Imported notebook.pdf")
        let writing = try writeNotebook(plans, files: templateFiles(), to: destination)
        return (try XCTUnwrap(PDFDocument(url: destination)), writing)
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

    private func assertColor(_ drawnColor: [Int], _ expected: [Int], _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (drawnComponent, expectedComponent) in zip(drawnColor, expected) {
            XCTAssertEqual(drawnComponent, expectedComponent, accuracy: 6, "\(message): \(drawnColor)", file: file, line: line)
        }
    }

    /// PencilKit's drawing data stores a monoline stroke made from points as pen ink (iPadOS 27 and macOS 27), which
    /// draws stored points the same (`PencilInkRenderedWidth`).
    private func inkTypeAsStored(_ ink: ImportedStroke.Ink) -> PKInk.InkType {
        ink == .monoline ? .pen : ImportedStrokeBuilder.inkType(for: ink)
    }

    private func inkAnnotations(on page: PDFPage) -> [PDFAnnotation] {
        page.annotations.filter { annotation in annotation.type == "Ink" }
    }

    // MARK: Pages and backgrounds

    func testEachPlanIsAPageOfItsSizeOverItsBackground() throws {
        let (document, writing) = try writtenDocument(plans)
        XCTAssertEqual(document.pageCount, 3)
        for (pageIndex, plan) in plans.enumerated() {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            XCTAssertEqual(page.bounds(for: .cropBox).size, plan.sizeInPoints, "Page \(pageIndex + 1)")
            XCTAssertEqual(page.rotation, 0)
        }
        assertColor(try drawnColor(of: XCTUnwrap(document.page(at: 0)), at: CGPoint(x: 30, y: 30)), [255, 242, 179], "Plain yellow paper")
        let templatePage = try XCTUnwrap(document.page(at: 1))
        assertColor(try drawnColor(of: templatePage, at: CGPoint(x: 75, y: 50)), [255, 0, 0], "The template's red rectangle")
        assertColor(try drawnColor(of: templatePage, at: CGPoint(x: 225, y: 50)), [255, 255, 255], "The template's white paper")
        let stretchedPage = try XCTUnwrap(document.page(at: 2))
        assertColor(try drawnColor(of: stretchedPage, at: CGPoint(x: 100, y: 75)), [0, 204, 0], "The 200-point green page stretched to 400 by 300")
        assertColor(try drawnColor(of: stretchedPage, at: CGPoint(x: 300, y: 225)), [255, 0, 0], "Its red quarter, stretched with it")
        XCTAssertEqual(writing.pageReports.map(\.sourcePageNumber), [1, 2, 3])
        XCTAssertEqual(writing.pageReports.map(\.entries), plans.map(\.report))
        XCTAssertEqual(writing.revision, try FileRevision.read(XCTUnwrap(document.documentURL)))
    }

    func testATurnedSourcePageIsDrawnUprightAsItIsShown() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportWriter", for: self)
        let turnedTemplate = try sourcePDF([SourcePage(size: CGSize(width: 300, height: 400), paper: white,
                                                       redRectangle: CGRect(x: 0, y: 0, width: 150, height: 200))], rotation: 90)
        let plan = ImportedPagePlan(sourcePageNumber: 1, sizeInPoints: CGSize(width: 400, height: 300), background: .pdfPage(templateFile, pageNumber: 1),
                                    strokes: [], report: [])
        let destination = vault.location(of: "Turned.pdf")
        _ = try writeNotebook([plan], files: NotebookFiles(contentsByPath: [templateFile.pathInSource: turnedTemplate]), to: destination)
        let page = try XCTUnwrap(PDFDocument(url: destination)?.page(at: 0))
        XCTAssertEqual(page.rotation, 0)
        XCTAssertEqual(page.bounds(for: .cropBox).size, CGSize(width: 400, height: 300))
        // Turned a quarter clockwise, the top-left quarter is shown at the top right.
        assertColor(try drawnColor(of: page, at: CGPoint(x: 300, y: 75)), [255, 0, 0], "The red quarter")
        assertColor(try drawnColor(of: page, at: CGPoint(x: 100, y: 75)), [255, 255, 255], "White paper")
    }

    func testPagesOnOneTemplateReadItOnce() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportWriter", for: self)
        let countingFiles = ReadCountingFiles(files: try templateFiles())
        let pageCount = 40
        let plan = ImportedPagePlan(sourcePageNumber: 1, sizeInPoints: CGSize(width: 300, height: 400), background: .pdfPage(templateFile, pageNumber: 1),
                                    strokes: [], report: [])
        let destination = vault.location(of: "Forty pages.pdf")
        _ = try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(pageCount: pageCount, planForPage: { _ in plan }, sourceFiles: countingFiles,
                                                                           strokeCreationDate: strokeCreationDate, to: destination)
        XCTAssertEqual(countingFiles.readCountsByPath.withLock { readCounts in readCounts }, [templateFile.pathInSource: 1])
        XCTAssertEqual(PDFDocument(url: destination)?.pageCount, pageCount)
    }

    // MARK: Ink

    func testEveryStrokeIsOneInkAnnotationInGraphitesEditableGroup() throws {
        let (document, _) = try writtenDocument(plans)
        for (pageIndex, plan) in plans.enumerated() {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            XCTAssertEqual(inkAnnotations(on: page).count, plan.strokes.count, "Page \(pageIndex + 1)")
            guard !plan.strokes.isEmpty else {
                XCTAssertNil(PDFInkGroups.editableGroup(on: page))
                continue
            }
            let editableGroup = try XCTUnwrap(PDFInkGroups.editableGroup(on: page), "Page \(pageIndex + 1)")
            XCTAssertEqual(editableGroup.group, PDFInkGroups.defaultGroup)
            let drawing = try PKDrawing(data: editableGroup.record.drawingData)
            XCTAssertEqual(drawing.strokes.count, plan.strokes.count)
            XCTAssertEqual(editableGroup.record.strokeNames.filter { name in !name.isEmpty }.count, plan.strokes.count, "Every stroke has its annotation.")
            for (storedStroke, plannedStroke) in zip(drawing.strokes, plan.strokes) {
                XCTAssertEqual(storedStroke.ink.inkType, inkTypeAsStored(plannedStroke.ink))
                XCTAssertEqual(Array(storedStroke.path).count, plannedStroke.samples.count)
                let storedColor = PencilStrokeSampler.color(of: storedStroke)
                XCTAssertEqual(storedColor.red, plannedStroke.color.red, accuracy: 0.002)
                XCTAssertEqual(storedColor.green, plannedStroke.color.green, accuracy: 0.002)
                XCTAssertEqual(storedColor.blue, plannedStroke.color.blue, accuracy: 0.002)
                XCTAssertEqual(storedColor.alpha, plannedStroke.color.alpha, accuracy: 0.002)
            }
            XCTAssertNotNil(PDFPageInkTracker.restoring(editableGroup), "Graphite can edit the page's ink again.")
        }
    }

    /// The annotation's rectangle is the shape it shows with 1 point to spare and half the `/InkList` width around it.
    func testAnAnnotationShowsTheSourcesOutlineWhenThePlanHasOne() throws {
        let (document, _) = try writtenDocument(plans)
        let page = try XCTUnwrap(document.page(at: 1))
        let outlinedAnnotation = try XCTUnwrap(inkAnnotations(on: page).first)
        // The outline from (40, 90) to (260, 112) in top-left coordinates on a 400-point-high page.
        let outlineInPageSpace = CGRect(x: 40, y: 400 - 112, width: 220, height: 22)
        let expectedBounds = outlineInPageSpace.insetBy(dx: -(4 / 2 + 1), dy: -(4 / 2 + 1))
        XCTAssertEqual(outlinedAnnotation.bounds.minX, expectedBounds.minX, accuracy: 0.5)
        XCTAssertEqual(outlinedAnnotation.bounds.maxX, expectedBounds.maxX, accuracy: 0.5)
        XCTAssertEqual(outlinedAnnotation.bounds.minY, expectedBounds.minY, accuracy: 0.5)
        XCTAssertEqual(outlinedAnnotation.bounds.maxY, expectedBounds.maxY, accuracy: 0.5)
        XCTAssertEqual(outlinedAnnotation.border?.lineWidth ?? 0, 4, accuracy: 0.001)
    }

    /// Without an outline, the shape is the planned samples at their planned widths: a horizontal stroke's annotation
    /// is its width high, plus the margin, whatever point size PencilKit needs to draw that width.
    func testAnAnnotationWithoutOutlineShowsThePlannedWidth() throws {
        let (document, _) = try writtenDocument(plans)
        let page = try XCTUnwrap(document.page(at: 0))
        let annotations = inkAnnotations(on: page)
        for (annotation, plannedStroke) in zip(annotations, strokesOfEveryInk) {
            let plannedWidth = try XCTUnwrap(plannedStroke.samples.first).width
            XCTAssertEqual(annotation.bounds.height, plannedWidth + 2 * (plannedWidth / 2 + 1), accuracy: 0.5, "\(plannedStroke.ink)")
            XCTAssertEqual(annotation.border?.lineWidth ?? 0, max(plannedWidth, 0.5), accuracy: 0.001)
            let standardColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let annotationColor = try XCTUnwrap(annotation.color.cgColor.converted(to: standardColorSpace, intent: .defaultIntent, options: nil)?.components)
            // The color's alpha is in the appearance: the standard `/C` color has none.
            let plannedComponents = [plannedStroke.color.red, plannedStroke.color.green, plannedStroke.color.blue]
            for (writtenComponent, plannedComponent) in zip(annotationColor, plannedComponents) {
                XCTAssertEqual(Double(writtenComponent), plannedComponent, accuracy: 0.01, "\(plannedStroke.ink)")
            }
        }
    }

    // MARK: Refusals

    func testASecondWriteToTheSameDestinationLeavesTheFirstFileAsItWas() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportWriter", for: self)
        let destination = vault.location(of: "Imported notebook.pdf")
        _ = try writeNotebook(plans, files: templateFiles(), to: destination)
        let firstFile = try Data(contentsOf: destination)
        XCTAssertThrowsError(try writeNotebook(Array(plans.prefix(1)), files: templateFiles(), to: destination)) { error in
            guard case NotebookImportWriterError.destinationExists(let refusedDestination) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(refusedDestination, destination)
        }
        XCTAssertEqual(try Data(contentsOf: destination), firstFile)
    }

    func testAMissingSourceFileIsTheTypedErrorAndNothingIsWritten() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportWriter", for: self)
        let destination = vault.location(of: "Imported notebook.pdf")
        XCTAssertThrowsError(try writeNotebook(plans, files: NotebookFiles(contentsByPath: [:]), to: destination)) { error in
            guard case NotebookImportWriterError.sourceFileUnreadable(let file, let underlyingError) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(file, templateFile)
            XCTAssertEqual(underlyingError as? NotebookFiles.MissingFile, NotebookFiles.MissingFile(pathInSource: templateFile.pathInSource))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAPageTheSourcePDFLacksIsTheTypedError() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportWriter", for: self)
        let plan = ImportedPagePlan(sourcePageNumber: 1, sizeInPoints: CGSize(width: 300, height: 400), background: .pdfPage(templateFile, pageNumber: 9),
                                    strokes: [], report: [])
        XCTAssertThrowsError(try writeNotebook([plan], files: templateFiles(), to: vault.location(of: "Missing page.pdf"))) { error in
            guard case NotebookImportWriterError.sourcePageMissing(let file, let pageNumber, let sourcePageCount) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(file, templateFile)
            XCTAssertEqual(pageNumber, 9)
            XCTAssertEqual(sourcePageCount, 2)
        }
    }

    func testAFileThatIsNotAPDFAndAnUnusableSizeAreTypedErrors() throws {
        let vault = try TemporaryVault.make(prefix: "NotebookImportWriter", for: self)
        XCTAssertThrowsError(try writeNotebook(Array(plans.dropFirst()), files: NotebookFiles(contentsByPath: [templateFile.pathInSource: Array("text".utf8)]),
                                               to: vault.location(of: "Not a PDF.pdf"))) { error in
            guard case NotebookImportWriterError.sourceFileNotOpenablePDF(let file) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(file, templateFile)
        }
        let flatPlan = ImportedPagePlan(sourcePageNumber: 1, sizeInPoints: CGSize(width: 300, height: 0), background: .plainColor(paperYellow),
                                        strokes: [], report: [])
        XCTAssertThrowsError(try writeNotebook([flatPlan], files: templateFiles(), to: vault.location(of: "Flat.pdf"))) { error in
            guard case NotebookImportWriterError.unusablePageSize(let pageIndex, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(pageIndex, 0)
        }
        XCTAssertThrowsError(try writeNotebook([], files: templateFiles(), to: vault.location(of: "Empty.pdf"))) { error in
            guard case NotebookImportWriterError.noPages = error else { return XCTFail("\(error)") }
        }
    }
}
