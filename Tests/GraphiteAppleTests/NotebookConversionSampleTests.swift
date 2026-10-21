import XCTest
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import GraphiteCore
import NotebookImport
import GraphiteTestSupport
@testable import GraphiteApple

/// Converts the owner's real Goodnotes and Notability samples end to end and reads every written PDF back: each page's
/// size, its strokes as `/Ink` annotations, its pictures as Graphite pictures with their files' own bytes, its typed text
/// as Graphite text boxes, its paper as page content rather than ink, and, where the sample folder holds the app's own
/// export (`export.pdf`), how much of the drawn page differs from it and where the export prints the typed text. The samples are personal notebooks, never in the repository: the test reads them
/// from the folder `GRAPHITE_IMPORT_SAMPLES` names and is skipped on a machine without them.
final class NotebookConversionSampleTests: XCTestCase {
    private static let samplesFolderVariable = "GRAPHITE_IMPORT_SAMPLES"
    private static let skipReason = "The owner's import samples are not on this machine: set GRAPHITE_IMPORT_SAMPLES to their folder."
    /// Rendering resolution of the visual comparison: 100 pixels per inch, as the format documents compared.
    private static let comparisonPixelsPerPoint = 100.0 / 72.0
    /// A pixel is content when it differs from white by at least this much (0 to 255) in either picture, and differs
    /// between the two when they differ by at least this much.
    private static let contentDifferenceThreshold = 64
    /// The largest share of content pixels that may differ between a written page and the app's export, on pages
    /// whose report neither leaves out nor redraws anything the export shows (typed text, tape and sticky notes are in the
    /// export; Goodnotes' pencil and highlighter look different). The largest share measured on such a page was 0.018.
    private static let maximumDifferingContentShare = 0.05
    /// The largest share of content pixels that may differ between a written page drawn without annotations and its
    /// source PDF page drawn the same way: antialiased edges of a dense page drawn small.
    private static let maximumDifferingBackgroundShare = 0.02

    private func samplesFolder() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment[Self.samplesFolderVariable] else { throw XCTSkip(Self.skipReason) }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func notebookFiles(in folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let location = enumerator?.nextObject() as? URL {
            if NotebookFileFormat(fileExtension: location.pathExtension) != nil { files.append(location) }
        }
        return files.sorted { first, second in first.path < second.path }
    }

    private struct Written {
        let notebook: OpenedNotebook
        let writing: NotebookImportWriting
        let document: PDFDocument
        /// The plan of each written page, in page order.
        let plans: [ImportedPagePlan]
    }

    private func convert(_ location: URL, into vault: TemporaryVault) throws -> Written {
        let format = try XCTUnwrap(NotebookFileFormat(fileExtension: location.pathExtension))
        let notebook = try OpenedNotebook.open(location, format: format, limits: .standard)
        let destination = vault.location(of: UUID().uuidString + ".pdf")
        let writing = try NotebookConversion(fileWriter: AtomicFileWriter()).writePDF(of: notebook, to: destination,
                                                                                     strokeCreationDate: Date(timeIntervalSinceReferenceDate: 0)) { _ in }
        var plans: [ImportedPagePlan] = []
        for pageIndex in 0..<notebook.sourcePageCount {
            if case .planned(let plan) = try notebook.outcome(ofPageAt: pageIndex) { plans.append(plan) }
        }
        return Written(notebook: notebook, writing: writing, document: try XCTUnwrap(PDFDocument(url: destination)), plans: plans)
    }

    func testEverySampleIsWrittenWithItsPagesStrokesPicturesAndPaperAsPlanned() throws {
        let folder = try samplesFolder()
        let vault = try TemporaryVault.make(prefix: "NotebookConversionSamples", for: self)
        var totals = (notebooks: 0, pages: 0, strokes: 0, pictures: 0, picturesKeptByteForByte: 0, textBoxes: 0)
        for location in notebookFiles(in: folder) {
            let name = location.lastPathComponent
            let written: Written
            do {
                written = try convert(location, into: vault)
            } catch NotebookImportFailure.noPages {
                print("NOTEBOOK-CONVERSION \(name): no pages (left out whole)")
                continue
            }
            XCTAssertEqual(written.document.pageCount, written.writing.pageReports.count { report in report.written != nil }, name)
            XCTAssertGreaterThanOrEqual(written.writing.pageReports.count, written.notebook.sourcePageCount, name)
            for (pageIndex, plan) in written.plans.enumerated() {
                guard let page = written.document.page(at: pageIndex) else { continue }
                let context = "\(name) page \(plan.sourcePageNumber)"
                let size = page.bounds(for: .cropBox).size
                XCTAssertEqual(size.width, plan.sizeInPoints.width, accuracy: 0.01, context)
                XCTAssertEqual(size.height, plan.sizeInPoints.height, accuracy: 0.01, context)
                try assertInkIsOneEditableGroupOfThePlannedStrokes(page, plan: plan, context: context)
                let pictures = PDFPageManager.pictures(on: page)
                let report = written.writing.pageReports.first { report in report.sourcePageNumber == plan.sourcePageNumber }
                XCTAssertEqual(pictures.count, report?.written?.pictureCount, context)
                let textBoxes = PDFPageManager.textBoxes(on: page)
                XCTAssertEqual(textBoxes.count, report?.written?.textBoxCount, context)
                XCTAssertGreaterThanOrEqual(textBoxes.count, plan.textBoxes.count { box in !ImportedTextRuns(box.content).isEmpty }, context)
                totals.textBoxes += textBoxes.count
                totals.picturesKeptByteForByte += try keptByteForByteCount(plan, pictures: pictures, sourceFiles: written.notebook.sourceFiles)
                try assertPaperIsPageContent(page, background: plan.background, sourceFiles: written.notebook.sourceFiles, context: context)
                totals.pages += 1
                totals.strokes += plan.strokes.count
                totals.pictures += pictures.count
            }
            totals.notebooks += 1
        }
        print("NOTEBOOK-CONVERSION totals \(totals)")
    }

    /// The pictures whose plan shows the whole file unflipped, from a PNG or JPEG file that is upright as stored and
    /// within `PDFPicture`'s limits, hold that file's bytes unchanged; returns how many did.
    private func keptByteForByteCount(_ plan: ImportedPagePlan, pictures: [PDFPicture], sourceFiles: any ImportSourceFiles) throws -> Int {
        let storedImages = Set(pictures.map(\.imageData))
        var keptCount = 0
        for picture in plan.pictures where picture.cropRectangleInPixels == nil && !picture.isFlippedHorizontally && !picture.isFlippedVertically {
            guard let bytes = try? sourceFiles.contents(of: picture.file), isUprightPNGOrJPEGWithinLimits(bytes) else { continue } // left out or converted
            XCTAssertTrue(storedImages.contains(bytes), "\(picture.file.pathInSource) is kept byte for byte")
            keptCount += 1
        }
        return keptCount
    }

    private func isUprightPNGOrJPEGWithinLimits(_ bytes: Data) -> Bool {
        guard bytes.starts(with: [0xFF, 0xD8]) || bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]), bytes.count <= PDFPicture.maximumImageBytes,
              let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1 && max(width, height) <= ImportedPictureImage.maximumSidePixels
    }

    /// The imported strokes are one ink group Graphite edits again, with one annotation and one named stroke of its
    /// record per planned stroke: the paper adds no ink. Ink a source PDF page carries itself stays outside the group.
    private func assertInkIsOneEditableGroupOfThePlannedStrokes(_ page: PDFPage, plan: ImportedPagePlan, context: String) throws {
        guard !plan.strokes.isEmpty else { return }
        let group = try XCTUnwrap(PDFInkGroups.editableGroup(on: page), "An editable ink group: \(context)")
        let groupAnnotations = page.annotations.filter { annotation in annotation.value(forAnnotationKey: PDFPageManager.groupKey) as? String == group.group }
        XCTAssertEqual(groupAnnotations.count, plan.strokes.count, context)
        XCTAssertTrue(groupAnnotations.allSatisfy { annotation in annotation.type == "Ink" }, context)
        XCTAssertEqual(group.record.strokeNames.count { name in !name.isEmpty }, plan.strokes.count, context)
    }

    /// Drawn without annotations, the page is its background: ruled paper shows its lines, and a page on a source PDF page
    /// draws as that page does, so the paper is page content and not ink.
    private func assertPaperIsPageContent(_ page: PDFPage, background: ImportedPageBackground, sourceFiles: any ImportSourceFiles,
                                          context: String) throws {
        let size = page.bounds(for: .cropBox).size
        let width = Int(size.width / 2), height = Int(size.height / 2)
        let drawnWithoutAnnotations = try rendered(page, drawsAnnotations: false, width: width, height: height)
        switch background {
        case .plainColor:
            return
        case .ruledPaper:
            XCTAssertGreaterThan(drawnWithoutAnnotations.count { value in value < 250 }, 0, "The ruling is page content: \(context)")
        case .pdfPage(let file, let pageNumber):
            let sourcePage = try XCTUnwrap(PDFDocument(data: sourceFiles.contents(of: file))?.page(at: pageNumber - 1), context)
            let source = try rendered(sourcePage, drawsAnnotations: false, width: width, height: height)
            let share = differingContentShare(drawnWithoutAnnotations, source, width: width, height: height)
            XCTAssertLessThanOrEqual(share, Self.maximumDifferingBackgroundShare, "The source page is the page's content: \(context)")
        }
    }

    func testWrittenPagesLookLikeEachAppsOwnExport() throws {
        let folder = try samplesFolder()
        let vault = try TemporaryVault.make(prefix: "NotebookConversionExports", for: self)
        for location in notebookFiles(in: folder) {
            let exportLocation = location.deletingLastPathComponent().appendingPathComponent("export.pdf")
            guard let export = PDFDocument(url: exportLocation) else { continue }
            guard let written = try? convert(location, into: vault) else { continue } // a notebook with no page to write has nothing to compare
            let name = location.lastPathComponent
            guard export.pageCount == written.document.pageCount else {
                print("NOTEBOOK-EXPORT \(name): \(written.document.pageCount) pages written, \(export.pageCount) exported; not compared")
                continue
            }
            for (pageIndex, plan) in written.plans.enumerated() {
                guard let page = written.document.page(at: pageIndex), let exportPage = export.page(at: pageIndex) else { continue }
                let share = try differingContentShare(page, exportPage)
                let leavesVisibleContentOut = plan.report.contains { entry in Self.changesWhatTheExportShows(entry) }
                print(String(format: "NOTEBOOK-EXPORT %@ page %d: %.4f of content pixels differ%@", name, plan.sourcePageNumber, share,
                             leavesVisibleContentOut ? " (the report names content drawn otherwise or left out)" : ""))
                if !leavesVisibleContentOut { XCTAssertLessThanOrEqual(share, Self.maximumDifferingContentShare, "\(name) page \(plan.sourcePageNumber)") }
            }
        }
    }

    /// Every text box's first line starts where the app's own export prints the same word: its left edge and its
    /// baseline within `maximumTextOffsetPoints`. Only upright boxes are compared, on pages of the samples with an export.
    func testTypedTextIsWhereEachAppsExportPrintsIt() throws {
        let folder = try samplesFolder()
        let vault = try TemporaryVault.make(prefix: "NotebookConversionText", for: self)
        var comparedCount = 0
        for location in notebookFiles(in: folder) {
            guard let export = PDFDocument(url: location.deletingLastPathComponent().appendingPathComponent("export.pdf")),
                  let written = try? convert(location, into: vault) else { continue }
            for pageIndex in 0..<min(export.pageCount, written.document.pageCount) {
                guard let page = written.document.page(at: pageIndex), let exportPage = export.page(at: pageIndex) else { continue }
                for box in PDFPageManager.textBoxes(on: page) where box.rotationRadians == 0 {
                    let context = "\(location.lastPathComponent) page \(pageIndex + 1) “\(box.plainText.prefix(24))”"
                    let start = try XCTUnwrap(Self.firstLineStart(of: box), context)
                    let exported = try XCTUnwrap(Self.exportedStart(of: box, on: exportPage), "The export prints the text: \(context)")
                    print(String(format: "NOTEBOOK-TEXT %@: first line at (%.2f, %.2f), export (%.2f, %.2f)", context, start.x, start.y,
                                 exported.x, exported.y))
                    XCTAssertEqual(start.x, exported.x, accuracy: Self.maximumTextOffsetPoints, context)
                    XCTAssertEqual(start.y, exported.y, accuracy: Self.maximumTextOffsetPoints, context)
                    comparedCount += 1
                }
            }
        }
        print("NOTEBOOK-TEXT compared \(comparedCount) text boxes")
    }

    /// How far a text box's first line may start from where the export prints it, in points.
    private static let maximumTextOffsetPoints = 1.5

    /// The start of the box's first line on its baseline, in page space.
    private static func firstLineStart(of box: PDFTextBox) -> CGPoint? {
        let layout = PDFTextBoxLayout(box: box)
        guard let origin = layout.lineOrigins.first else { return nil }
        return origin.applying(layout.boxToPage)
    }

    /// Where the export prints the box's first word: the left edge of its first character, on the baseline below the
    /// character's box by the font's descent (as Core Text measures it in the box's first font).
    private static func exportedStart(of box: PDFTextBox, on exportPage: PDFPage) -> CGPoint? {
        guard let firstWord = box.plainText.split(whereSeparator: \.isWhitespace).first, let exportText = exportPage.string,
              let wordRange = exportText.range(of: String(firstWord)) else { return nil }
        let characterIndex = exportText.utf16.distance(from: exportText.utf16.startIndex, to: wordRange.lowerBound.samePosition(in: exportText.utf16)
            ?? exportText.utf16.startIndex)
        let bounds = exportPage.characterBounds(at: characterIndex)
        let descent = Double(CTFontGetDescent(PDFTextBoxFonts.font(for: box.leadingAttributes)))
        return CGPoint(x: bounds.minX, y: bounds.minY + descent)
    }

    private static func changesWhatTheExportShows(_ entry: ImportReportEntry) -> Bool {
        switch entry {
        case .elementsNotYetConverted, .tapeLeftOut, .olderVaryingWidthInkLeftOut, .pictureFilesMissing, .picturesNotDecodable, .backgroundFileMissing,
             .paperRulingNotDrawn, .highlighterNotMultiplied, .pencilTextureNotKept, .textStylesNotKept, .fontsReplaced, .stickyNotesAsTextBoxes,
             .textBoxesNotPlaced:
            true
        case .shapesDrawnAsInk, .dashesNotKept, .picturesMovedUnderInk, .animatedPicturesKeptStill, .pageWidthAssumed,
             .recordingFilesMissing, .recordingsNotCopied, .recordingTimingNotKept, .outlineEntriesWithoutPage, .pageWithoutPaper, .pageGeometryUnknown,
             .goodnotesReadingIssue, .notabilityReadingIssue:
            false
        }
    }

    /// The share of content pixels (darker than white by the threshold in either page) whose grey differs by the
    /// threshold, each pixel compared with the closest grey within one pixel of it in the other page, so that
    /// antialiased edges a fraction of a pixel apart do not count.
    private func differingContentShare(_ page: PDFPage, _ exportPage: PDFPage) throws -> Double {
        let size = page.bounds(for: .cropBox).size
        let width = Int((size.width * Self.comparisonPixelsPerPoint).rounded()), height = Int((size.height * Self.comparisonPixelsPerPoint).rounded())
        let written = try rendered(page, drawsAnnotations: true, width: width, height: height)
        let exported = try rendered(exportPage, drawsAnnotations: true, width: width, height: height)
        return differingContentShare(written, exported, width: width, height: height)
    }

    private func differingContentShare(_ written: [UInt8], _ exported: [UInt8], width: Int, height: Int) -> Double {
        var contentCount = 0, differingCount = 0
        for row in 0..<height {
            for column in 0..<width {
                let writtenGrey = written[row * width + column], exportedGrey = exported[row * width + column]
                guard 255 - Int(writtenGrey) >= Self.contentDifferenceThreshold || 255 - Int(exportedGrey) >= Self.contentDifferenceThreshold else { continue }
                contentCount += 1
                let neighbors = neighborhood(of: column, row, width: width, height: height)
                let closest = neighbors.map { index in abs(Int(exported[index]) - Int(writtenGrey)) }.min() ?? 255
                if closest >= Self.contentDifferenceThreshold { differingCount += 1 }
            }
        }
        return contentCount == 0 ? 0 : Double(differingCount) / Double(contentCount)
    }

    private func neighborhood(of column: Int, _ row: Int, width: Int, height: Int) -> [Int] {
        var indices: [Int] = []
        for neighborRow in max(0, row - 1)...min(height - 1, row + 1) {
            for neighborColumn in max(0, column - 1)...min(width - 1, column + 1) { indices.append(neighborRow * width + neighborColumn) }
        }
        return indices
    }

    /// The page drawn in grey on white, top row first.
    private func rendered(_ page: PDFPage, drawsAnnotations: Bool, width: Int? = nil, height: Int? = nil) throws -> [UInt8] {
        let box = page.bounds(for: .cropBox)
        let pixelWidth = width ?? Int(box.width), pixelHeight = height ?? Int(box.height)
        var pixels = [UInt8](repeating: 255, count: pixelWidth * pixelHeight)
        page.displaysAnnotations = drawsAnnotations
        defer { page.displaysAnnotations = true }
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                                  bytesPerRow: pixelWidth, space: CGColorSpaceCreateDeviceGray(),
                                                  bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            context.scaleBy(x: CGFloat(pixelWidth) / box.width, y: CGFloat(pixelHeight) / box.height)
            page.draw(with: .cropBox, to: context)
        }
        // A bitmap context's first row in memory is the top of the page.
        return pixels
    }
}
