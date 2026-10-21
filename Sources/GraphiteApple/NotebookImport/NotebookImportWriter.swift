import Foundation
import PDFKit
import GraphiteCore
import NotebookImport

/// Writes an imported notebook as a new ordinary PDF that Graphite's own PDF code wrote: each planned page is a PDF
/// page of its size with its background as page content (`ImportedBackgroundPages`), its pictures are Graphite's
/// picture stamps (`ImportedPagePictures`), and its strokes are standard `/Ink` annotations over them with Graphite's
/// re-editing record (`ImportedPageInk`), so the PDF opens, re-edits and saves like a notebook made in Graphite.
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
    ///   - pageCount: How many pages the notebook has; `planForPage` is asked for each index from 0, in order.
    ///   - sourceFiles: Reads the files the plans' backgrounds and pictures name.
    ///   - strokeCreationDate: The PencilKit creation date of every imported stroke.
    public func write(pageCount: Int, planForPage: (Int) throws -> ImportedPagePlan, sourceFiles: any ImportSourceFiles,
                      strokeCreationDate: Date, to destination: URL) throws -> NotebookImportWriting {
        guard pageCount > 0 else { throw NotebookImportWriterError.noPages }
        // Checked first so a notebook is not converted only to be refused; the writer checks again as it moves the file.
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw NotebookImportWriterError.destinationExists(destination) }
        var pageReports: [ImportedPageReport] = []
        do {
            let revision = try fileWriter.replace(destination, expecting: .absent) { staging in
                let document = PDFDocument()
                var backgrounds = ImportedBackgroundPages(sourceFiles: sourceFiles)
                for pageIndex in 0..<pageCount {
                    try Task.checkCancellation()
                    let pageReport = try autoreleasepool {
                        try appendPage(planForPage(pageIndex), at: pageIndex, to: document, backgrounds: &backgrounds, sourceFiles: sourceFiles,
                                       strokeCreationDate: strokeCreationDate)
                    }
                    pageReports.append(pageReport)
                }
                guard PDFFileService.write(document, to: staging) else { throw NotebookImportWriterError.verificationFailed(pageCount: pageCount) }
            }
            return NotebookImportWriting(revision: revision, pageReports: pageReports)
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
