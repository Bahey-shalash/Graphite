import Foundation
import CoreGraphics
import GraphiteCore
import NotebookImport

/// Why `NotebookImportWriter` wrote no file. Every case leaves the destination as it was and the source unchanged.
public enum NotebookImportWriterError: Error {
    /// A notebook needs at least one page, and at least one that its plan does not leave out.
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
    /// A picture's crop is not a finite rectangle of positive width and height.
    case pictureCropUnusable(ImportedSourceFile, cropRectangleInPixels: CGRect, pageIndex: Int)
    /// Even made smaller, the picture's image takes more than `PDFPicture.maximumImageBytes`; `byteCount` is the smallest tried.
    case pictureTooLarge(ImportedSourceFile, byteCount: Int, pageIndex: Int)
    /// A picture's frame is not finite with a positive size, or its angle is not finite.
    case pictureGeometryUnusable(ImportedSourceFile, frame: CGRect, rotationRadiansClockwise: Double, pageIndex: Int)
    /// The written PDF did not open again with every page, so it was not put in place.
    case verificationFailed(pageCount: Int)
    /// A recording's file is not MPEG-4 (no `ftyp` box first), so it would not play as an `.m4a`.
    case recordingNotMPEG4(ImportedSourceFile)
    /// The recording's copy could not be written at the destination's volume, such as a full disk.
    case recordingNotWritten(URL, underlyingError: any Error)
}
