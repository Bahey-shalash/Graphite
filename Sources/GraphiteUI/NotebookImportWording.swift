import Foundation
import GraphiteApple
import NotebookImport

/// The words of a notebook import's progress and report: the one place that turns the import's facts into sentences.
enum NotebookImportWording {
    /// How many page numbers a report line lists before it says how many more there are.
    private static let listedPageNumberCount = 8

    static func title(of summary: NotebookImportSummary) -> String {
        summary.wasCancelled ? "Import Stopped" : "Import Finished"
    }

    /// "3 notebooks imported. 1 could not be imported. 2 were not started."
    static func headline(of summary: NotebookImportSummary) -> String {
        var sentences = [count(summary.importedCount, "notebook", "notebooks") + " imported."]
        if summary.failedCount > 0 { sentences.append(count(summary.failedCount, "notebook", "notebooks") + " could not be imported.") }
        if summary.notStartedCount > 0 { sentences.append(count(summary.notStartedCount, "notebook was", "notebooks were") + " not started.") }
        return sentences.joined(separator: " ")
    }

    /// What the chosen folders held besides notebooks, one sentence each.
    static func folderNotes(of summary: NotebookImportSummary) -> [String] {
        var notes: [String] = []
        if summary.otherFileCount > 0 {
            notes.append(count(summary.otherFileCount, "file that is not a notebook was", "files that are not notebooks were") + " left where they are.")
        }
        for folder in summary.foldersWithoutNotebooks { notes.append("“\(folder)” has no Goodnotes or Notability notebooks.") }
        for folder in summary.unreadableFolders { notes.append("“\(folder)” could not be read.") }
        return notes
    }

    /// Where the notebook went, or why it did not.
    static func status(of outcome: NotebookImportOutcome) -> String {
        switch outcome.result {
        case .imported(let notebook):
            let recordings = notebook.recordings.isEmpty ? "" : ", with " + count(notebook.recordings.count, "recording", "recordings")
            return "Saved as “\(notebook.pdf.rawValue)”\(recordings)."
        case .failed(let failure): return reason(failure)
        case .notStarted: return "Not imported: the import was stopped first."
        }
    }

    static func reason(_ failure: NotebookImportFailure) -> String {
        switch failure {
        case .sourceUnreadable: "The file could not be read. If it is in iCloud Drive or another cloud, check that it can be downloaded."
        case .notANotebook(let format): "This file is not a \(appName(format)) notebook."
        case .damaged(let format): "The notebook is damaged, or was saved by a version of \(appName(format)) that Graphite cannot read yet."
        case .tooLarge: "The notebook holds a file too large to import on this device."
        case .noPages: "The notebook has no page Graphite can import yet. A note of typed text only waits for text on PDF pages."
        case .notWritten: "The PDF could not be saved in the vault. Check that the device has free space."
        }
    }

    /// One line of a notebook's report: what was simplified or left out, how many, and on which pages.
    static func line(_ summaryLine: ImportReportSummaryLine) -> String {
        let pages = pageList(summaryLine.pageNumbers)
        return description(of: summaryLine.kind, totalCount: summaryLine.totalCount, occurrenceCount: summaryLine.occurrenceCount)
            + (pages.isEmpty ? "." : ", " + pages + ".")
    }

    static func progressDetail(_ progress: NotebookImportProgress) -> String {
        guard let name = progress.currentNotebookName else { return "Finding notebooks…" }
        let position = "\(progress.finishedNotebookCount + 1) of \(progress.notebookCount)"
        guard progress.currentPageCount > 0 else { return "\(name) · \(position)" }
        return "\(name) · \(position) · page \(min(progress.finishedPageCount + 1, progress.currentPageCount)) of \(progress.currentPageCount)"
    }

    private static func description(of kind: ImportReportEntryKind, totalCount: Int?, occurrenceCount: Int) -> String {
        let total = totalCount ?? occurrenceCount
        switch kind {
        case .highlighterNotMultiplied: return "Highlighter drawn see-through instead of blended into the ink under it: " + count(total, "stroke", "strokes")
        case .pencilTextureNotKept: return "Pencil drawn without Goodnotes' grain: " + count(total, "stroke", "strokes")
        case .tapeLeftOut: return "Tape left out: " + count(total, "piece", "pieces")
        case .olderVaryingWidthInkLeftOut: return "Ink of an older Goodnotes that Graphite cannot read yet left out: " + count(total, "stroke", "strokes")
        case .shapesDrawnAsInk: return "Shapes drawn as ink: " + count(total, "shape", "shapes")
        case .dashesNotKept: return "Dashed lines drawn solid: " + count(total, "line", "lines")
        case .elementsNotYetConverted(let elementKind): return leftOutElements(elementKind, count: total)
        case .picturesMovedUnderInk: return "Pictures moved under the ink: " + count(total, "picture", "pictures")
        case .animatedPicturesKeptStill: return "Animated pictures kept as their first frame: " + count(total, "picture", "pictures")
        case .pictureFilesMissing: return "Pictures missing from the notebook left out: " + count(total, "picture", "pictures")
        case .picturesNotDecodable: return "Pictures that could not be read left out: " + count(total, "picture", "pictures")
        case .recordingFilesMissing: return "Recordings missing from the notebook: " + count(total, "recording", "recordings")
        case .recordingsNotCopied: return "Recordings that could not be copied: " + count(total, "recording", "recordings")
        case .recordingTimingNotKept: return "Recordings kept without the timing of what was written during them: " + count(total, "stroke", "strokes")
        case .outlineEntriesWithoutPage: return "Outline entries of deleted pages left out: " + count(total, "entry", "entries")
        case .paperRulingNotDrawn: return "Paper lines Graphite does not know drawn as plain paper"
        case .pageWithoutPaper: return "Pages without paper left out: " + count(occurrenceCount, "page", "pages")
        case .backgroundFileMissing: return "Page backgrounds missing from the notebook, drawn as plain paper"
        case .pageGeometryUnknown: return "The note's page size is not known, so its pages were left out"
        case .goodnotesReadingIssue, .notabilityReadingIssue: return "Parts Graphite could not read left out: " + count(total, "part", "parts")
        }
    }

    private static func leftOutElements(_ kind: ImportElementKind, count total: Int) -> String {
        switch kind {
        case .textBox: "Text boxes left out until Graphite has text on PDF pages: " + count(total, "text box", "text boxes")
        case .stickyNote: "Sticky notes left out until Graphite has text on PDF pages: " + count(total, "note", "notes")
        case .typedText: "Typed text left out until Graphite has text on PDF pages"
        case .shape: "Shapes Graphite could not draw left out: " + count(total, "shape", "shapes")
        case .shapeFill: "Shape fills left out: " + count(total, "fill", "fills")
        case .picture: "Pictures left out: " + count(total, "picture", "pictures")
        case .unknownKind: "Elements of a kind Graphite does not know left out: " + count(total, "element", "elements")
        case .strokeInUnknownLayout: "Strokes saved in a way Graphite does not know left out: " + count(total, "stroke", "strokes")
        }
    }

    /// "page 3", "pages 1, 2 and 5", or the first few and how many more.
    private static func pageList(_ pageNumbers: [Int]) -> String {
        guard !pageNumbers.isEmpty else { return "" }
        guard pageNumbers.count > 1 else { return "page \(pageNumbers[0])" }
        let listed = pageNumbers.prefix(listedPageNumberCount).map(String.init)
        let remaining = pageNumbers.count - listed.count
        if remaining > 0 { return "pages " + listed.joined(separator: ", ") + " and \(remaining) more" }
        return "pages " + listed.dropLast().joined(separator: ", ") + " and " + (listed.last ?? "")
    }

    private static func appName(_ format: NotebookFileFormat) -> String {
        switch format {
        case .goodnotes: "Goodnotes"
        case .notability: "Notability"
        }
    }

    private static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }
}
