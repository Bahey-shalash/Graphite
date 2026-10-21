import Foundation

/// A document page made from a page of an imported PDF (`richText.pageLayoutArray`). The PDF in the note is the
/// imported file unchanged.
public struct NotabilityImportedPDFPage: Sendable, Equatable {
    /// The note's page, from 1.
    public let documentPageNumber: Int?
    /// The PDF file relative to the note's folder, `PDFs/<name>`; nil when the layout names no file or a name that is
    /// not a safe file name (reported).
    public let pdfFile: NotebookArchivePath?
    /// The page of that PDF, from 1.
    public let pdfPageNumber: Int?
    public let isBookmarked: Bool

    public init(documentPageNumber: Int?, pdfFile: NotebookArchivePath?, pdfPageNumber: Int?, isBookmarked: Bool) {
        self.documentPageNumber = documentPageNumber
        self.pdfFile = pdfFile
        self.pdfPageNumber = pdfPageNumber
        self.isBookmarked = isBookmarked
    }
}
