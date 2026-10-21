import Foundation
import GraphiteCore
import NotebookImport

/// What `NotebookImportWriter` wrote: the new file's revision and, page by page, what the import simplified or left out.
public struct NotebookImportWriting: Sendable, Equatable {
    public let revision: FileRevision
    /// One report for each source page, in page order: what a written page got (`ImportedPageReport.written`), or a page
    /// its plan left out.
    public let pageReports: [ImportedPageReport]
    /// What the writing left out of the notebook as a whole: outline entries whose page was not written.
    public let notebookEntries: [ImportReportEntry]
}
