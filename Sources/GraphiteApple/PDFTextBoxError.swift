import Foundation

/// Why a change of a text box was not made.
public enum PDFTextBoxError: Error, LocalizedError, Equatable {
    /// The page the change names is no longer in the document.
    case pageMissing
    /// The box the change names is no longer on its page, as after an undo.
    case boxMissing
    /// The box's position, size, angle or text is not one a page can hold.
    case cannotBePlaced

    public var errorDescription: String? {
        switch self {
        case .pageMissing: "This page no longer exists."
        case .boxMissing: "This text box no longer exists."
        case .cannotBePlaced: "This text box cannot be placed on the page."
        }
    }
}
