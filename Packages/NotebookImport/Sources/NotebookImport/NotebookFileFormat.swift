import Foundation

/// The two notebook formats the package reads, by the file extension each app gives its notebooks.
public enum NotebookFileFormat: Sendable, Hashable, CaseIterable {
    case goodnotes, notability

    /// `goodnotes` and `note`, without the dot.
    public var fileExtension: String {
        switch self {
        case .goodnotes: "goodnotes"
        case .notability: "note"
        }
    }

    /// The format of a file with this extension, compared without regard to case; nil for any other file. Only the
    /// extension is compared: a reader still refuses a file that is not that app's notebook.
    public init?(fileExtension: String) {
        guard let format = Self.allCases.first(where: { format in format.fileExtension.caseInsensitiveCompare(fileExtension) == .orderedSame })
        else { return nil }
        self = format
    }
}
