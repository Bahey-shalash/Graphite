import Foundation

/// How far a notebook import is: which notebook it is converting, and how many of its pages are done.
struct NotebookImportProgress: Sendable, Equatable {
    /// All the notebooks the import found, once the chosen folders are listed.
    var notebookCount: Int
    var finishedNotebookCount: Int
    /// The notebook being converted; nil while the chosen folders are listed.
    var currentNotebookName: String?
    var currentPageCount: Int
    var finishedPageCount: Int

    static let listing = NotebookImportProgress(notebookCount: 0, finishedNotebookCount: 0, currentNotebookName: nil, currentPageCount: 0,
                                                finishedPageCount: 0)

    /// 0 to 1: finished notebooks, plus the share of the current one's pages.
    var fractionCompleted: Double {
        guard notebookCount > 0 else { return 0 }
        let currentShare = currentPageCount > 0 ? Double(min(finishedPageCount, currentPageCount)) / Double(currentPageCount) : 0
        return min(1, (Double(finishedNotebookCount) + currentShare) / Double(notebookCount))
    }
}
