import Foundation
import GraphiteCore

/// What `NotebookImportWriter` wrote: the new file's revision and, page by page, what the import simplified or left out.
public struct NotebookImportWriting: Sendable, Equatable {
    public let revision: FileRevision
    /// One report for each written page, in page order.
    public let pageReports: [ImportedPageReport]
}

/// The report of one written page: its source page and the plan's entries, kept after the plan itself is released.
public struct ImportedPageReport: Sendable, Equatable {
    /// From 1, as in `ImportedPagePlan.sourcePageNumber`.
    public let sourcePageNumber: Int
    public let entries: [ImportReportEntry]
}
