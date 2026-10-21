import Foundation
import CoreGraphics
import GraphiteCore

/// What Search reads of a PDF: the text of its text boxes (`PDFFreeTextContents`), not its
/// printed text. Core Graphics loads only the page and annotation dictionaries it is asked
/// for, so a large PDF is not read whole; what is read is bounded by `PDFFreeTextContents`.
enum PDFIndexText {
    /// A PDF this size or smaller is read for its text boxes; most of its bytes, the pages'
    /// content and images, are never loaded.
    static let maximumPDFBytes = 2 * 1_073_741_824

    /// The text of the PDF at a location that is already coordinated. An encrypted PDF has
    /// none Graphite can read without its password; one Core Graphics cannot open is a failure,
    /// read again by the next scan.
    static func reading(at location: URL) -> VaultIndex.NoteReading {
        guard let document = CGPDFDocument(location as CFURL) else {
            return .failed(PDFIndexReadingError.unreadable)
        }
        guard document.isUnlocked else { return .text("") }
        return .text(PDFFreeTextContents.searchableText(of: document))
    }

    /// The same, under a file coordination of its own, as a refresh of one file reads it.
    static func coordinatedReading(at location: URL) -> VaultIndex.NoteReading {
        var coordinationError: NSError?
        var reading: VaultIndex.NoteReading?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: location, options: [], error: &coordinationError) { coordinatedLocation in
            reading = Self.reading(at: coordinatedLocation)
        }
        if let coordinationError { return .failed(coordinationError) }
        return reading ?? .failed(PDFIndexReadingError.unavailable)
    }
}
