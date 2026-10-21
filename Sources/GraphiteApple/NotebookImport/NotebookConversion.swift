import Foundation
import GraphiteCore
import NotebookImport

/// Converts one opened notebook into ordinary files: its PDF (`NotebookImportWriter`), then each recording as an `.m4a`
/// file (`NotebookImportRecordingWriter`), and the import report of the two. Where the files go is the caller's.
///
/// Synchronous and long: run it away from the main actor. It stops between pages when its task is cancelled, and then
/// leaves no PDF.
public struct NotebookConversion: Sendable {
    private let pdfWriter: NotebookImportWriter
    private let recordingWriter: NotebookImportRecordingWriter

    public init(fileWriter: AtomicFileWriter) {
        pdfWriter = NotebookImportWriter(fileWriter: fileWriter)
        recordingWriter = NotebookImportRecordingWriter(fileWriter: fileWriter)
    }

    /// Writes the notebook's PDF at `destination`. `pagesDone` hears how many source pages are done, before each page
    /// and once at the end. Throws `CancellationError` when the task is cancelled.
    public func writePDF(of notebook: OpenedNotebook, to destination: URL, strokeCreationDate: Date,
                         pagesDone: (Int) -> Void) throws -> NotebookImportWriting {
        guard notebook.sourcePageCount > 0 else { throw NotebookImportFailure.noPages }
        do {
            let writing = try pdfWriter.write(sourcePageCount: notebook.sourcePageCount, outcomeForPage: { pageIndex in
                pagesDone(pageIndex)
                return try notebook.outcome(ofPageAt: pageIndex)
            }, outline: notebook.outline.entries, sourceFiles: notebook.sourceFiles, strokeCreationDate: strokeCreationDate, to: destination)
            pagesDone(notebook.sourcePageCount)
            return writing
        } catch let error as CancellationError {
            throw error
        } catch let error as NotebookImportWriterError {
            throw Self.failure(of: error, format: notebook.format)
        } catch is GoodnotesReadingError, is NotabilityReadingError {
            // A page the reader could not give: the notebook is damaged where its index said it had a page.
            throw NotebookImportFailure.damaged(notebook.format)
        } catch {
            // The file system's own error while the PDF was staged or moved into place, such as a full disk.
            throw NotebookImportFailure.notWritten
        }
    }

    /// Writes the recording at `recordingIndex` of `notebook.recordings` to `destination`; false when it could not be
    /// copied (its file is not MPEG-4 audio, is damaged, or the disk is full), which the report then counts.
    public func writeRecording(at recordingIndex: Int, of notebook: OpenedNotebook, to destination: URL) -> Bool {
        let recordings = notebook.recordings.recordings
        guard recordings.indices.contains(recordingIndex) else { return false }
        do {
            try recordingWriter.write(recordings[recordingIndex], from: notebook.sourceFiles, to: destination)
            return true
        } catch {
            return false
        }
    }

    /// The import report of a written notebook: every source page from the writing, and the notebook's own entries.
    public func report(of notebook: OpenedNotebook, writing: NotebookImportWriting, copiedRecordingCount: Int) -> NotebookImportReport {
        let notCopiedCount = notebook.recordings.recordings.count - copiedRecordingCount
        let recordingEntries: [ImportReportEntry] = notCopiedCount > 0 ? [.recordingsNotCopied(count: notCopiedCount)] : []
        return NotebookImportReport(source: notebook.reportSource, pages: writing.pageReports,
                                    notebookEntries: notebook.notebookEntries + writing.notebookEntries + recordingEntries,
                                    recordingCount: copiedRecordingCount)
    }

    /// A file of the notebook a plan names that cannot be used is damage in the notebook; a PDF that cannot be put in
    /// place is the vault's.
    private static func failure(of error: NotebookImportWriterError, format: NotebookFileFormat) -> NotebookImportFailure {
        switch error {
        case .noPages: .noPages
        case .destinationExists, .verificationFailed, .recordingNotWritten: .notWritten
        case .unusablePageSize, .sourceFileUnreadable, .sourceFileNotOpenablePDF, .sourcePageMissing, .backgroundNotDrawn, .pictureCropUnusable,
             .pictureTooLarge, .pictureGeometryUnusable, .recordingNotMPEG4:
            .damaged(format)
        }
    }
}
