import Foundation
import PDFKit
import GraphiteCore
import NotebookImport

/// Writes an imported notebook as a new ordinary PDF that Graphite's own PDF code wrote: each planned page is a PDF
/// page of its size with its background as page content (`ImportedBackgroundPages`), its pictures are Graphite's
/// picture stamps (`ImportedPagePictures`), and its strokes are standard `/Ink` annotations over them with Graphite's
/// re-editing record (`ImportedPageInk`), so the PDF opens, re-edits and saves like a notebook made in Graphite. A page
/// whose plan leaves it out is not written, and the notebook's outline entries become the PDF's first outline items
/// (`ImportedOutlineItems`).
///
/// Pages are planned, made and applied one at a time; a page's plan and PencilKit drawing are released once the page
/// has its ink. The PDFKit document being written still grows with the notebook. The file is written as
/// `PDFFileService` writes a copy: verified and compacted, then moved into place only when nothing is at the
/// destination. The notebook's files are only read.
///
/// Synchronous and long: run it away from the main actor. It stops between pages when its task is cancelled.
public struct NotebookImportWriter: Sendable {
    private let fileWriter: AtomicFileWriter

    public init(fileWriter: AtomicFileWriter) {
        self.fileWriter = fileWriter
    }

    /// - Parameters:
    ///   - sourcePageCount: How many pages the source has; `outcomeForPage` is asked for each index from 0, in order. A
    ///     page its outcome leaves out is not written and keeps its report.
    ///   - outline: The notebook's outline entries, written before the bookmarks.
    ///   - sourceFiles: Reads the files the plans' backgrounds and pictures name.
    ///   - strokeCreationDate: The PencilKit creation date of every imported stroke.
    public func write(sourcePageCount: Int, outcomeForPage: (Int) throws -> ImportedPageOutcome, outline: [ImportedOutlineEntry],
                      sourceFiles: any ImportSourceFiles, strokeCreationDate: Date, to destination: URL) throws -> NotebookImportWriting {
        guard sourcePageCount > 0 else { throw NotebookImportWriterError.noPages }
        // Checked first so a notebook is not converted only to be refused; the writer checks again as it moves the file.
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NotebookImportWriterError.destinationExists(destination) }
        var pageReports: [ImportedPageReport] = []
        var notebookEntries: [ImportReportEntry] = []
        do {
            let revision = try fileWriter.replace(destination, expecting: .absent) { staging in
                let document = PDFDocument()
                var backgrounds = ImportedBackgroundPages(sourceFiles: sourceFiles)
                var pageIndexBySourcePageNumber: [Int: Int] = [:]
                for sourcePageIndex in 0..<sourcePageCount {
                    try Task.checkCancellation()
                    let pageReport = try autoreleasepool {
                        switch try outcomeForPage(sourcePageIndex) {
                        case .planned(let plan):
                            pageIndexBySourcePageNumber[plan.sourcePageNumber] = document.pageCount
                            return try appendPage(plan, at: document.pageCount, to: document, backgrounds: &backgrounds, sourceFiles: sourceFiles,
                                                  strokeCreationDate: strokeCreationDate)
                        case .leftOut(let sourcePageNumber, let report):
                            return ImportedPageReport.leftOut(sourcePageNumber: sourcePageNumber, entries: report)
                        }
                    }
                    pageReports.append(pageReport)
                }
                guard document.pageCount > 0 else { throw NotebookImportWriterError.noPages }
                let outlineEntriesWithoutPage = ImportedOutlineItems.insert(outline, into: document, pageIndexBySourcePageNumber: pageIndexBySourcePageNumber)
                if outlineEntriesWithoutPage > 0 { notebookEntries.append(.outlineEntriesWithoutPage(count: outlineEntriesWithoutPage)) }
                guard PDFFileService.write(document, to: staging) else { throw NotebookImportWriterError.verificationFailed(pageCount: document.pageCount) }
            }
            return NotebookImportWriting(revision: revision, pageReports: pageReports, notebookEntries: notebookEntries)
        } catch GraphiteError.conflict {
            throw NotebookImportWriterError.destinationExists(destination)
        }
    }

    /// The pictures go on the page before its ink, so the ink is over them (invariant M-15). A bookmarked page gets the
    /// outline item Graphite adds for a bookmark, so the PDF's bookmarks follow the pages' order.
    private func appendPage(_ plan: ImportedPagePlan, at pageIndex: Int, to document: PDFDocument, backgrounds: inout ImportedBackgroundPages,
                            sourceFiles: any ImportSourceFiles, strokeCreationDate: Date) throws -> ImportedPageReport {
        document.insert(try backgrounds.page(for: plan, pageIndex: pageIndex), at: pageIndex)
        if plan.isBookmarked {
            try PDFPageManager.apply(.bookmark(page: pageIndex, label: PDFPageManager.bookmarkLabelPrefix + "\(pageIndex + 1)"), to: document)
        }
        let picturesLeftOut = try ImportedPagePictures.place(plan.pictures, onPageAt: pageIndex, of: document, pageSize: plan.sizeInPoints,
                                                                     sourceFiles: sourceFiles)
        try ImportedPageInk.apply(plan.strokes, toPageAt: pageIndex, of: document, pageSize: plan.sizeInPoints, strokeCreationDate: strokeCreationDate)
        let placedPictureCount = plan.pictures.count - picturesLeftOut.missingFileCount - picturesLeftOut.notDecodableCount
        return ImportedPageReport(sourcePageNumber: plan.sourcePageNumber,
                                  written: ImportedPageContents(strokeCount: plan.strokes.count, pictureCount: placedPictureCount,
                                                                isBookmarked: plan.isBookmarked),
                                  entries: ImportedPagePictures.report(plan.report, adding: picturesLeftOut))
    }
}
