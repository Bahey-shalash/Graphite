import Foundation

/// The report of one source page: written, with what it holds, or left out, and the entries for what was simplified
/// or left out. Kept after the page's plan is released.
public struct ImportedPageReport: Sendable, Equatable {
    /// From 1, as in `ImportedPagePlan.sourcePageNumber`.
    public let sourcePageNumber: Int
    /// What the written page holds; nil when the page was left out.
    public let written: ImportedPageContents?
    public let entries: [ImportReportEntry]

    public init(sourcePageNumber: Int, written: ImportedPageContents?, entries: [ImportReportEntry]) {
        self.sourcePageNumber = sourcePageNumber
        self.written = written
        self.entries = entries
    }

    /// A page the planner left out (`ImportedPageOutcome.leftOut`).
    public static func leftOut(sourcePageNumber: Int, entries: [ImportReportEntry]) -> ImportedPageReport {
        ImportedPageReport(sourcePageNumber: sourcePageNumber, written: nil, entries: entries)
    }
}

/// What a written page holds, as converted: its strokes, the pictures and text boxes placed on it, and its bookmark.
public struct ImportedPageContents: Sendable, Equatable {
    public let strokeCount: Int
    public let pictureCount: Int
    public let textBoxCount: Int
    public let isBookmarked: Bool

    public init(strokeCount: Int, pictureCount: Int, textBoxCount: Int = 0, isBookmarked: Bool) {
        self.strokeCount = strokeCount
        self.pictureCount = pictureCount
        self.textBoxCount = textBoxCount
        self.isBookmarked = isBookmarked
    }
}
