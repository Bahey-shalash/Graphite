import Foundation
import PDFKit
import GraphiteCore

/// A new notebook whose every page is a copy of one of the person's own paper templates.
public enum MyPaperTemplateNotebook {
    /// The PDF of `pageCount` pages, each a copy of the template's page. The page is copied as it
    /// is, not drawn again, so vector content stays vector and a picture keeps its data; the
    /// copies share the page's content in the file, so a template with a large picture does not
    /// make a large notebook.
    public static func documentData(templateAt templateLocation: URL, pageCount: Int) throws -> Data {
        guard NewNotebookOptions.pageCountRange.contains(pageCount) else { throw MyPaperTemplateError.pageCountOutOfRange }
        guard let template = PDFDocument(url: templateLocation), !template.isLocked, let page = template.page(at: 0) else {
            throw MyPaperTemplateError.unreadableTemplate
        }
        let notebook = PDFDocument()
        for pageIndex in 0..<pageCount {
            guard let pageCopy = page.copy() as? PDFPage else { throw MyPaperTemplateError.notDrawn }
            notebook.insert(pageCopy, at: pageIndex)
        }
        guard let notebookData = notebook.dataRepresentation() else { throw MyPaperTemplateError.notDrawn }
        return notebookData
    }

    /// The first page of a template as a picture, with the page's size in PDF points; nil when
    /// the file cannot be read as a PDF.
    public static func preview(ofTemplateAt templateLocation: URL, longerSidePixels: Int) -> MyPaperTemplatePreview? {
        guard let template = PDFDocument(url: templateLocation), !template.isLocked, let page = template.page(at: 0),
              let image = LibraryPreviewLoader.thumbnail(of: page, longerSidePixels: longerSidePixels) else { return nil }
        return MyPaperTemplatePreview(image: image, pageSize: page.bounds(for: .cropBox).size)
    }
}

/// A template's first page drawn small, with the size of the page.
public struct MyPaperTemplatePreview: Sendable {
    public let image: CGImage
    public let pageSize: CGSize
}
