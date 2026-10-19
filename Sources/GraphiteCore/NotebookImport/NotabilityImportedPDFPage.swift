import Foundation

/// A document page made from a page of an imported PDF (`richText.pageLayoutArray`). The PDF in the note is the
/// imported file unchanged.
public struct NotabilityImportedPDFPage: Sendable, Equatable {
    /// The note's page, from 1.
    public let documentPageNumber: Int?
    /// The PDF file relative to the note's folder: `PDFs/<name>`.
    public let pdfRelativePath: String
    /// The page of that PDF, from 1.
    public let pdfPageNumber: Int?
    public let isBookmarked: Bool

    public init(documentPageNumber: Int?, pdfRelativePath: String, pdfPageNumber: Int?, isBookmarked: Bool) {
        self.documentPageNumber = documentPageNumber
        self.pdfRelativePath = pdfRelativePath
        self.pdfPageNumber = pdfPageNumber
        self.isBookmarked = isBookmarked
    }
}
