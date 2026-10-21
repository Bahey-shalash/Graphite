import Foundation
import GraphiteCore
import GraphiteApple
import NotebookImport

/// What a notebook import did, notebook by notebook, for its report.
struct NotebookImportSummary: Sendable, Equatable {
    var outcomes: [NotebookImportOutcome] = []
    /// Files of the chosen folders that are not notebooks; they were left where they are.
    var otherFileCount = 0
    /// Chosen folders with no notebook in them, by name; nothing was made for them.
    var foldersWithoutNotebooks: [String] = []
    /// Folders that could not be read, by name.
    var unreadableFolders: [String] = []
    var wasCancelled = false

    var importedCount: Int { outcomes.count { outcome in outcome.importedNotebook != nil } }
    var failedCount: Int { outcomes.count { outcome in if case .failed = outcome.result { true } else { false } } }
    var notStartedCount: Int { outcomes.count { outcome in outcome.result == .notStarted } }
}

/// One notebook of an import: imported, with what became of it, failed, with why, or not started because the import
/// was cancelled first.
struct NotebookImportOutcome: Sendable, Equatable, Identifiable {
    enum Result: Sendable, Equatable {
        case imported(ImportedNotebook)
        case failed(NotebookImportFailure)
        case notStarted
    }

    /// The notebook file's location, which is unique within one import.
    let id: URL
    /// The notebook's file name, as the person knows it.
    let sourceName: String
    let result: Result

    var importedNotebook: ImportedNotebook? {
        if case .imported(let notebook) = result { notebook } else { nil }
    }
}

/// A notebook written into the vault: its PDF, its recordings and the import report.
struct ImportedNotebook: Sendable, Equatable {
    let pdf: VaultPath
    let recordings: [VaultPath]
    let report: NotebookImportReport
}
