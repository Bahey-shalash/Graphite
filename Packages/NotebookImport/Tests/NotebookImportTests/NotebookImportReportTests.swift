import Foundation
import XCTest
@testable import NotebookImport

/// The import report as plain values: every page written or left out, the notebook's own entries, and a summary with
/// one line per kind of entry, its total, and the pages it occurs on.
final class NotebookImportReportTests: XCTestCase {
    private static let written = ImportedPageContents(strokeCount: 12, pictureCount: 1, isBookmarked: false)

    func testTheSummaryAddsUpEachKindAcrossPagesAndKeepsItsPages() {
        let report = NotebookImportReport(source: .goodnotes, pages: [
            ImportedPageReport(sourcePageNumber: 3, written: Self.written,
                               entries: [.highlighterNotMultiplied(strokeCount: 2), .elementsNotYetConverted(kind: .textBox, count: 1)]),
            ImportedPageReport.leftOut(sourcePageNumber: 2, entries: [.pageWithoutPaper]),
            ImportedPageReport(sourcePageNumber: 1, written: Self.written,
                               entries: [.highlighterNotMultiplied(strokeCount: 3), .goodnotesReadingIssue(.eventKindNotKnown(999))])
        ], notebookEntries: [.recordingTimingNotKept(timedElementCount: 4), .goodnotesReadingIssue(.eventKindNotKnown(999))], recordingCount: 1)
        XCTAssertEqual(report.pages.map(\.sourcePageNumber), [1, 2, 3])
        XCTAssertEqual(report.summary, [
            ImportReportSummaryLine(kind: .highlighterNotMultiplied, totalCount: 5, occurrenceCount: 2, pageNumbers: [1, 3]),
            ImportReportSummaryLine(kind: .goodnotesReadingIssue(.eventKindNotKnown(999)), totalCount: nil, occurrenceCount: 2, pageNumbers: [1]),
            ImportReportSummaryLine(kind: .pageWithoutPaper, totalCount: nil, occurrenceCount: 1, pageNumbers: [2]),
            ImportReportSummaryLine(kind: .elementsNotYetConverted(.textBox), totalCount: 1, occurrenceCount: 1, pageNumbers: [3]),
            ImportReportSummaryLine(kind: .recordingTimingNotKept, totalCount: 4, occurrenceCount: 1, pageNumbers: [])
        ])
        XCTAssertEqual(report.summary.map(\.category), [.simplified, .readingIssue, .leftOut, .leftOut, .leftOut])
        XCTAssertEqual(report.writtenPageCount, 2)
        XCTAssertEqual(report.leftOutPageNumbers, [2])
        XCTAssertFalse(report.isComplete)
    }

    func testANotebookWithNothingToReportIsComplete() {
        let report = NotebookImportReport(source: .notability, pages: [ImportedPageReport(sourcePageNumber: 1, written: Self.written, entries: [])],
                                          notebookEntries: [], recordingCount: 0)
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.summary, [])
        XCTAssertFalse(NotebookImportReport(source: .notability, pages: [], notebookEntries: [], recordingCount: 0).isComplete,
                       "a notebook with no page written is never complete")
        let leftOutWithoutEntries = NotebookImportReport(source: .notability, pages: [.leftOut(sourcePageNumber: 1, entries: [])],
                                                         notebookEntries: [], recordingCount: 0)
        XCTAssertFalse(leftOutWithoutEntries.isComplete, "a page left out is never complete")
    }

    func testEachEntryHasItsKindCountAndCategory() {
        let expected: [(ImportReportEntry, ImportReportEntryKind, Int?, ImportReportCategory)] = [
            (.pencilTextureNotKept(strokeCount: 4), .pencilTextureNotKept, 4, .simplified),
            (.shapesDrawnAsInk(count: 2), .shapesDrawnAsInk, 2, .simplified),
            (.paperRulingNotDrawn, .paperRulingNotDrawn, nil, .simplified),
            (.tapeLeftOut(strokeCount: 1), .tapeLeftOut, 1, .leftOut),
            (.picturesNotDecodable(count: 3), .picturesNotDecodable, 3, .leftOut),
            (.recordingFilesMissing(count: 1), .recordingFilesMissing, 1, .leftOut),
            (.backgroundFileMissing, .backgroundFileMissing, nil, .leftOut),
            (.notabilityReadingIssue(.curveStyleUnknown(rawStyle: 7)), .notabilityReadingIssue(.curveStyleUnknown(rawStyle: 7)), nil, .readingIssue)
        ]
        for (entry, kind, count, category) in expected {
            XCTAssertEqual(entry.kind, kind, "\(entry)")
            XCTAssertEqual(entry.count, count, "\(entry)")
            XCTAssertEqual(entry.kind.category, category, "\(entry)")
        }
    }

    func testReadingIssuesOfOneCaseAreOneSummaryLineWhateverElementTheyName() {
        let report = NotebookImportReport(source: .goodnotes, pages: [
            ImportedPageReport(sourcePageNumber: 1, written: Self.written, entries: [
                .goodnotesReadingIssue(.elementMissingFromMemberList(elementIdentifier: "A")),
                .goodnotesReadingIssue(.elementMissingFromMemberList(elementIdentifier: "B")),
                .goodnotesReadingIssue(.eventKindNotKnown(7))
            ]),
            ImportedPageReport(sourcePageNumber: 2, written: Self.written, entries: [
                .goodnotesReadingIssue(.elementMissingFromMemberList(elementIdentifier: "C")), .goodnotesReadingIssue(.pencilPathTrailingArrayNotEmpty)
            ])
        ], notebookEntries: [.notabilityReadingIssue(.reflowStateUnknown(className: nil))], recordingCount: 0)
        XCTAssertEqual(report.summary, [
            ImportReportSummaryLine(kind: .goodnotesReadingIssue(.elementMissingFromMemberList(elementIdentifier: "A")), totalCount: nil,
                                    occurrenceCount: 3, pageNumbers: [1, 2]),
            ImportReportSummaryLine(kind: .goodnotesReadingIssue(.eventKindNotKnown(7)), totalCount: nil, occurrenceCount: 1, pageNumbers: [1]),
            ImportReportSummaryLine(kind: .goodnotesReadingIssue(.pencilPathTrailingArrayNotEmpty), totalCount: nil, occurrenceCount: 1, pageNumbers: [2]),
            ImportReportSummaryLine(kind: .notabilityReadingIssue(.reflowStateUnknown(className: nil)), totalCount: nil, occurrenceCount: 1, pageNumbers: [])
        ])
    }

    func testANoteWithoutPagesIsReportedAsLeftOutWhole() throws {
        var builder = NotabilityNoteBuilder()
        builder.reflowStateClassName = "NBReflowStateReflowable"
        builder.storedPageWidth = nil
        builder.paperFields = [("paperIdentifier", "Legacy:13"), ("paperSize", "letter"), ("paperSizingBehavior", "deviceBasedWidth")]
        let reader = try NotabilityNoteReader(archiveBytes: builder.noteArchiveBytes(), limits: .standard)
        XCTAssertNil(reader.pageCount)
        let recordings = NotabilityRecordingPlanner.plan(reader.note)
        let entries = NotebookImportReport.notebookEntries(of: reader, recordings: recordings)
        XCTAssertEqual(entries.first, .pageGeometryUnknown)
        let report = NotebookImportReport(source: .notability, pages: [], notebookEntries: entries, recordingCount: 0)
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.summary.first?.kind, .pageGeometryUnknown)
    }
}
