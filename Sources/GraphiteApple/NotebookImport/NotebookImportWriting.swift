import Foundation
import GraphiteCore

/// What `NotebookImportWriter` wrote: the new file's revision and, page by page, what the import simplified or left out.
public struct NotebookImportWriting: Sendable, Equatable {
    public let revision: FileRevision
    /// One report for each written page, in page order (`ImportedPageReport.written` holds what each page got). The
    /// caller adds the pages the planner left out and the notebook's entries to make a `NotebookImportReport`.
    public let pageReports: [ImportedPageReport]
}
