import Foundation
import CoreGraphics
import GraphiteCore

/// Why `NotebookImportWriter` wrote no file. Every case leaves the destination as it was and the source unchanged.
public enum NotebookImportWriterError: Error {
    /// A notebook needs at least one page.
    case noPages
    /// Something is already at the destination; an import never replaces a file.
    case destinationExists(URL)
    /// The page's size is not positive and finite or, for plain paper, outside the sizes PDF allows (3 to 14,400 points).
    case unusablePageSize(pageIndex: Int, sizeInPoints: CGSize)
    /// The notebook's file that a page's background names could not be read; `underlyingError` is the reader's.
    case sourceFileUnreadable(ImportedSourceFile, underlyingError: any Error)
    /// The file is not a PDF PDFKit opens, or it is locked with a password.
    case sourceFileNotOpenablePDF(ImportedSourceFile)
    /// The background names a page the source PDF does not have.
    case sourcePageMissing(ImportedSourceFile, pageNumber: Int, sourcePageCount: Int)
    /// Core Graphics could not make a page of this size for the background.
    case backgroundNotDrawn(pageIndex: Int)
    /// The written PDF did not open again with every page, so it was not put in place.
    case verificationFailed(pageCount: Int)
}
