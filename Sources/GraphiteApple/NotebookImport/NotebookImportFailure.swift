import Foundation
import NotebookImport

/// Why a notebook was not imported. Nothing is left in the vault for it, and its file is unchanged.
public enum NotebookImportFailure: Error, Sendable, Equatable {
    /// The file could not be read: it is gone, could not be downloaded, or Graphite may not read it.
    case sourceUnreadable
    /// The file has the app's extension but is not one of its notebooks.
    case notANotebook(NotebookFileFormat)
    /// The notebook is damaged, or written in a way the reader does not know, so it cannot be read.
    case damaged(NotebookFileFormat)
    /// A part of the notebook is larger than an import reads (`NotebookImportLimits`).
    case tooLarge(NotebookFileFormat)
    /// No page could be imported: a Notability note whose page size is not known (a note of typed text only, which
    /// reflows to each device), or a notebook whose every page has no paper.
    case noPages
    /// The PDF could not be written into the vault, such as on a full disk; nothing was left behind.
    case notWritten
}
