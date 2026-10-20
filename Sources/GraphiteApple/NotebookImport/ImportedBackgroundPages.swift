import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore

/// Makes the PDF page under an imported page's ink, of the plan's size, from its background. Lives for one write.
///
/// A page of a source PDF whose crop box already has the plan's size and is not turned is copied as it is, with its
/// annotations. Any other is drawn into a new page of the plan's size, stretched along each axis to fill it and turned
/// upright, since the plan's positions are in the page as shown; that page's annotations become part of its content.
///
/// Source PDFs are opened through `ImportSourceFiles` and the most recently used stay open, so a notebook whose pages
/// all use one template PDF reads and opens it once.
struct ImportedBackgroundPages {
    /// Source PDFs kept open at once; the least recently used is closed first.
    static let maximumOpenSourceDocuments = 4
    /// Sizes closer than this, in points, are the same size: rounding in the source's units.
    static let sizeTolerancePoints = 0.01

    private let sourceFiles: any ImportSourceFiles
    /// The most recently used last.
    private var openSourceDocuments: [(file: ImportedSourceFile, document: PDFDocument)] = []

    init(sourceFiles: any ImportSourceFiles) {
        self.sourceFiles = sourceFiles
    }

    mutating func page(for plan: ImportedPagePlan, pageIndex: Int) throws -> PDFPage {
        let size = plan.sizeInPoints
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            throw NotebookImportWriterError.unusablePageSize(pageIndex: pageIndex, sizeInPoints: size)
        }
        switch plan.background {
        case .plainColor(let color):
            return try plainPage(color: color, size: size, pageIndex: pageIndex)
        case .pdfPage(let file, let pageNumber):
            let sourcePage = try page(numbered: pageNumber, of: file)
            if sourcePage.rotation % 360 == 0, Self.isSameSize(sourcePage.bounds(for: .cropBox).size, size),
               let copiedPage = sourcePage.copy() as? PDFPage {
                return copiedPage
            }
            return try redrawnPage(sourcePage, size: size, pageIndex: pageIndex)
        }
    }

    private static func isSameSize(_ firstSize: CGSize, _ secondSize: CGSize) -> Bool {
        abs(firstSize.width - secondSize.width) <= sizeTolerancePoints && abs(firstSize.height - secondSize.height) <= sizeTolerancePoints
    }

    /// Opaque paper: the color's alpha is not used.
    private func plainPage(color: NotebookImportColor, size: CGSize, pageIndex: Int) throws -> PDFPage {
        let paper = PaperSpecification(template: .blank, width: size.width, height: size.height, paperColorHex: Self.hexadecimalText(of: color))
        let pageData = try PDFTemplateGenerator.pageData(paper: paper, matching: size)
        // The generator brings a size PDF does not allow into the allowed range; such a page is not the plan's.
        guard let page = PDFDocument(data: pageData)?.page(at: 0), Self.isSameSize(page.bounds(for: .cropBox).size, size) else {
            throw NotebookImportWriterError.unusablePageSize(pageIndex: pageIndex, sizeInPoints: size)
        }
        return page
    }

    private static func hexadecimalText(of color: NotebookImportColor) -> String {
        let components = [color.red, color.green, color.blue].map { component in
            Int((min(max(component.isFinite ? component : 0, 0), 1) * 255).rounded())
        }
        return "#" + components.map { component in String(format: "%02x", component) }.joined()
    }

    private mutating func page(numbered pageNumber: Int, of file: ImportedSourceFile) throws -> PDFPage {
        let document = try openDocument(file)
        guard pageNumber >= 1, pageNumber <= document.pageCount, let page = document.page(at: pageNumber - 1) else {
            throw NotebookImportWriterError.sourcePageMissing(file, pageNumber: pageNumber, sourcePageCount: document.pageCount)
        }
        return page
    }

    private mutating func openDocument(_ file: ImportedSourceFile) throws -> PDFDocument {
        if let openIndex = openSourceDocuments.firstIndex(where: { openDocument in openDocument.file == file }) {
            let reused = openSourceDocuments.remove(at: openIndex)
            openSourceDocuments.append(reused)
            return reused.document
        }
        let contents: [UInt8]
        do {
            contents = try sourceFiles.contents(of: file)
        } catch {
            throw NotebookImportWriterError.sourceFileUnreadable(file, underlyingError: error)
        }
        guard let document = PDFDocument(data: Data(contents)), !document.isLocked else {
            throw NotebookImportWriterError.sourceFileNotOpenablePDF(file)
        }
        if openSourceDocuments.count >= Self.maximumOpenSourceDocuments { openSourceDocuments.removeFirst() }
        openSourceDocuments.append((file, document))
        return document
    }

    /// The source page as it is shown (its crop box, turned by its rotation), stretched to `size`.
    private func redrawnPage(_ sourcePage: PDFPage, size: CGSize, pageIndex: Int) throws -> PDFPage {
        let shownBounds = sourcePage.bounds(for: .cropBox).applying(sourcePage.transform(for: .cropBox))
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        guard shownBounds.width > 0, shownBounds.height > 0, let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NotebookImportWriterError.backgroundNotDrawn(pageIndex: pageIndex)
        }
        context.beginPDFPage(nil)
        context.scaleBy(x: size.width / shownBounds.width, y: size.height / shownBounds.height)
        sourcePage.draw(with: .cropBox, to: context)
        context.endPDFPage()
        context.closePDF()
        guard let page = PDFDocument(data: output as Data)?.page(at: 0) else {
            throw NotebookImportWriterError.backgroundNotDrawn(pageIndex: pageIndex)
        }
        return page
    }
}
