import Foundation
import GraphiteCore
import NotebookImport

/// A notebook file opened for import: its reader, and what the import plans for the notebook as a whole. Opening reads
/// only the notebook's index (Goodnotes' event log, Notability's session); pages are read and planned one at a time as
/// `NotebookConversion` writes them. The file's bytes are memory-mapped, never copied whole, and never changed.
public struct OpenedNotebook: Sendable {
    private enum Reader: Sendable {
        case goodnotes(GoodnotesNotebookReader)
        case notability(NotabilityNoteReader)
    }

    private let reader: Reader
    public let format: NotebookFileFormat
    /// The source's pages, written or left out; 0 for a Notability note whose page size is not known.
    public let sourcePageCount: Int
    public let recordings: ImportedRecordingsPlan
    public let outline: ImportedOutlinePlan

    /// Opens the notebook at `location`, which the caller can read. The read is coordinated, so a file provider first
    /// downloads a file that is not on the device.
    public static func open(_ location: URL, format: NotebookFileFormat, limits: NotebookImportLimits) throws(NotebookImportFailure) -> OpenedNotebook {
        let bytes = try mappedBytes(of: location)
        switch format {
        case .goodnotes:
            do throws(GoodnotesReadingError) {
                let reader = try GoodnotesNotebookReader(archiveBytes: bytes, limits: limits)
                return OpenedNotebook(reader: .goodnotes(reader), format: format, sourcePageCount: reader.pageCount,
                                      recordings: GoodnotesRecordingPlanner.plan(reader.notebook.recordings),
                                      outline: GoodnotesOutlinePlanner.plan(reader.notebook))
            } catch {
                throw failure(of: error)
            }
        case .notability:
            do throws(NotabilityReadingError) {
                let reader = try NotabilityNoteReader(archiveBytes: bytes, limits: limits)
                return OpenedNotebook(reader: .notability(reader), format: format, sourcePageCount: reader.pageCount ?? 0,
                                      recordings: NotabilityRecordingPlanner.plan(reader.note), outline: .none)
            } catch {
                throw failure(of: error)
            }
        }
    }

    /// The plan of the source page at `pageIndex` (from 0), read now.
    func outcome(ofPageAt pageIndex: Int) throws -> ImportedPageOutcome {
        switch reader {
        case .goodnotes(let reader): GoodnotesPagePlanner.plan(try reader.page(at: pageIndex), pageNumber: pageIndex + 1)
        case .notability(let reader): NotabilityPagePlanner.plan(try reader.page(number: pageIndex + 1), note: reader.note)
        }
    }

    /// Reads the files the plans name: pictures, PDF pages and recordings.
    var sourceFiles: any ImportSourceFiles {
        switch reader {
        case .goodnotes(let reader): reader
        case .notability(let reader): reader
        }
    }

    var reportSource: NotebookImportReport.Source {
        switch reader {
        case .goodnotes: .goodnotes
        case .notability: .notability
        }
    }

    /// What the report says of the notebook as a whole: its recordings' entries, its outline's, and what the reader
    /// could not read outside the pages.
    var notebookEntries: [ImportReportEntry] {
        switch reader {
        case .goodnotes(let reader): NotebookImportReport.notebookEntries(of: reader.notebook, recordings: recordings) + outline.report
        case .notability(let reader): NotebookImportReport.notebookEntries(of: reader, recordings: recordings) + outline.report
        }
    }

    private static func mappedBytes(of location: URL) throws(NotebookImportFailure) -> Data {
        var coordinationError: NSError?
        var bytes: Data?
        NSFileCoordinator().coordinate(readingItemAt: location, options: [], error: &coordinationError) { coordinatedLocation in
            bytes = try? Data(contentsOf: coordinatedLocation, options: .alwaysMapped) // Unread bytes are reported below as an unreadable source.
        }
        guard coordinationError == nil, let bytes else { throw .sourceUnreadable }
        return bytes
    }

    private static func failure(of error: GoodnotesReadingError) -> NotebookImportFailure {
        switch error {
        case .notAGoodnotesNotebook: .notANotebook(.goodnotes)
        case .archive(let archiveError): failure(of: archiveError, format: .goodnotes)
        case .protocolBuffer, .compressedPayload, .tplImage, .eventLogMissing, .pageIndexOutOfRange, .attachmentFileNotValid, .emptyRecord,
             .eventBodyCount, .pathCodeOutOfPlace, .centerLineCodesNotKnown, .centerLineValuesUneven, .capRecordsUneven, .outlineCodeOutOfPlace,
             .outlineValuesRunOut:
            .damaged(.goodnotes)
        }
    }

    private static func failure(of error: NotabilityReadingError) -> NotebookImportFailure {
        switch error {
        case .topLevelFolderCount: .notANotebook(.notability)
        case .archive(let archiveError): failure(of: archiveError, format: .notability)
        case .session, .countNegative, .packedArrayLengthWrong, .curvePointCountsDisagree, .curvePointCountNotThreeKPlusOne, .knotCountsDisagree,
             .textRunRangeNotReadable, .textRunOutsideText, .recordingsLibrary, .recordingsLibraryLayoutNotRecognised, .curveIndexOutOfRange,
             .pageNumberOutOfRange, .pageCountUnknown:
            .damaged(.notability)
        }
    }

    /// An archive that is not a ZIP is not a notebook; an entry past the limits is too large; the rest is damage.
    private static func failure(of error: ZipArchiveError, format: NotebookFileFormat) -> NotebookImportFailure {
        switch error {
        case .endOfCentralDirectoryMissing: .notANotebook(format)
        case .entryTooLarge: .tooLarge(format)
        case .zip64NotSupported, .centralDirectoryDamaged, .entryMissing, .entryEncrypted, .compressionMethodNotSupported, .compressionRatioImpossible,
             .entryDataOutsideArchive, .entryDataDamaged, .checksumMismatch, .readOutsideArchive:
            .damaged(format)
        }
    }
}
