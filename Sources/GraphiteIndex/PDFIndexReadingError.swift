import Foundation

/// Why the text of a PDF's text boxes was not read for Search; the next scan tries again.
enum PDFIndexReadingError: Error, LocalizedError, Equatable {
    /// Core Graphics could not open the file as a PDF.
    case unreadable
    /// The file coordination ended without reading the file.
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unreadable: "This PDF cannot be read."
        case .unavailable: "This PDF is unavailable."
        }
    }
}
