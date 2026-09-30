import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple
#if canImport(UIKit)
import PencilKit
#endif

// A PDF's undo history belongs to its session (`PDFSession.undoManager`). Before, PencilKit
// kept stroke steps in the window's shared history, aimed at page canvases: releasing a
// canvas far from the page shown dropped its steps, rebuilding the view (switching tabs)
// dropped them all, and two PDFs side by side shared one history.
//
// Every step here changes the document through ordinary edits (`PDFSession.apply`), which
// saving replays on the file, so the file and the open document never disagree about what
// an undo did. Steps name pages through `PDFHistoryPage` boxes, which follow a page when
// undo or redo puts a new copy of it in the document (a deletion undone, an insertion redone).

/// A page named by steps of the undo history. Holding it weakly lets a deleted page go;
/// undoing the deletion inserts a copy and points the box at it.
@MainActor
final class PDFHistoryPage {
    weak var page: PDFPage?
    init(_ page: PDFPage) { self.page = page }
}

/// Pages kept by a step to put them back, as a PDF of those pages exactly as saving writes
/// them. Up to a megabyte stays in memory; more waits in a private temporary file, named
/// like the session's baseline copies, so a file left by an ended process is removed at
/// the next launch.
final class PDFHistoryPageContent {
    private static let maximumBytesInMemory = 1_048_576

    private enum Storage {
        case memory(Data)
        case temporaryFile(PDFBaselineSnapshot)
    }

    private let storage: Storage

    init(data: Data) throws {
        if data.count <= Self.maximumBytesInMemory {
            storage = .memory(data)
        } else {
            let temporaryCopy = PDFBaselineSnapshot(location: PDFBaselineSnapshot.makeLocation())
            try data.write(to: temporaryCopy.location, options: .atomic)
            storage = .temporaryFile(temporaryCopy)
        }
    }

    func read() throws -> Data {
        switch storage {
        case .memory(let data): data
        case .temporaryFile(let temporaryCopy): try Data(contentsOf: temporaryCopy.location)
        }
    }

    /// The private file holding the pages, when they are too large to stay in memory.
    var temporaryFileLocation: URL? {
        guard case .temporaryFile(let temporaryCopy) = storage else { return nil }
        return temporaryCopy.location
    }
}

/// Consecutive pages taken out of a PDF, with what the history needs to put them back.
@MainActor
struct PDFRemovedPageRun {
    /// Where the first page was, counting the pages before it once earlier runs are back.
    let startIndex: Int
    let pages: [PDFHistoryPage]
    let content: PDFHistoryPageContent
}

#if canImport(UIKit)
/// The view whose canvases edit a PDF's pages, which applies undone and redone ink to a
/// page's canvas, so the canvas and the page's annotations stay one drawing.
@MainActor
protocol PDFInkCanvasProvider: AnyObject {
    /// The canvas editing the page's ink, once its stored ink is restored; nil when the
    /// page has none, as when its canvas was released far from the page shown.
    func editingCanvas(for page: PDFPage) -> PDFPageCanvasView?
    func isDisplaying(_ page: PDFPage) -> Bool
}
#endif

extension PDFSession {
    private static let pageNoLongerExists = GraphiteError.invalidFile("This page no longer exists, so the change cannot be undone.")
    private static let inkChangedOutsideHistory = GraphiteError.invalidFile("The ink on this page changed in a way this step does not know, so it was not undone.")
    /// Deleting copies the pages first, for Undo; edits made meanwhile make it copy again.
    private static let maximumDeletionCopyAttempts = 3

    // MARK: Steps

    /// Registers a step whose undo and redo register each other, so it can be undone and
    /// redone repeatedly. A step that fails reports why and leaves the history.
    func registerStep(named actionName: String, undo: @escaping (PDFSession) throws -> Void, redo: @escaping (PDFSession) throws -> Void) {
        undoManager.registerUndo(withTarget: self) { session in
            do {
                try undo(session)
                session.registerStep(named: actionName, undo: redo, redo: undo)
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: Pages the history names

    func historyPage(for page: PDFPage) -> PDFHistoryPage {
        if let existing = historyPages.object(forKey: page) { return existing }
        let created = PDFHistoryPage(page)
        historyPages.setObject(created, forKey: page)
        return created
    }

    private func historyPage(atIndex pageIndex: Int) throws -> PDFHistoryPage {
        historyPage(for: try page(atIndex: pageIndex))
    }

    private func page(atIndex pageIndex: Int) throws -> PDFPage {
        guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else { throw Self.pageNoLongerExists }
        return page
    }

    /// Where the page is now; it throws when the page is not in the document.
    func currentIndex(of historyPage: PDFHistoryPage) throws -> Int {
        guard let page = historyPage.page, page.document === document else { throw Self.pageNoLongerExists }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { throw Self.pageNoLongerExists }
        return pageIndex
    }

    /// Points a box at the copy of its page that undo or redo just inserted.
    private func rebind(_ historyPage: PDFHistoryPage, to page: PDFPage) {
        historyPage.page = page
        historyPages.setObject(historyPage, forKey: page)
    }

    // MARK: Page changes

    func rotatePages(_ pageIndices: [Int], clockwise: Bool) throws {
        let rotatedPages = try pageIndices.map { pageIndex in try historyPage(atIndex: pageIndex) }
        for pageIndex in pageIndices { try apply(.rotate(page: pageIndex, clockwise: clockwise)) }
        registerStep(named: rotatedPages.count == 1 ? "Rotate Page" : "Rotate Pages") { session in
            try session.rotate(rotatedPages, clockwise: !clockwise)
        } redo: { session in
            try session.rotate(rotatedPages, clockwise: clockwise)
        }
    }

    private func rotate(_ rotatedPages: [PDFHistoryPage], clockwise: Bool) throws {
        for rotatedPage in rotatedPages { try apply(.rotate(page: currentIndex(of: rotatedPage), clockwise: clockwise)) }
        if let firstPage = rotatedPages.first { go(to: try currentIndex(of: firstPage)) }
    }

    func duplicatePages(_ pageIndices: [Int]) throws {
        // From the last page back, so earlier duplicates do not shift later indices.
        var duplications: [(source: PDFHistoryPage, duplicate: PDFHistoryPage)] = []
        for pageIndex in Set(pageIndices).sorted(by: >) {
            let source = try historyPage(atIndex: pageIndex)
            try apply(.duplicate(page: pageIndex))
            duplications.append((source, try historyPage(atIndex: pageIndex + 1)))
        }
        guard !duplications.isEmpty else { return }
        registerStep(named: duplications.count == 1 ? "Duplicate Page" : "Duplicate Pages") { session in
            try session.removePages(duplications.map(\.duplicate))
        } redo: { session in
            // The document is as it was before the duplication, so each source duplicates
            // to the same content again.
            for (source, duplicate) in duplications {
                let sourceIndex = try session.currentIndex(of: source)
                try session.apply(.duplicate(page: sourceIndex))
                session.rebind(duplicate, to: try session.page(atIndex: sourceIndex + 1))
            }
            if let firstDuplicate = duplications.last?.duplicate { session.go(to: try session.currentIndex(of: firstDuplicate)) }
        }
    }

    /// Inserts the pages of a PDF, such as new paper or imported pages.
    func insertPages(_ pagesData: Data, at insertionIndex: Int, actionName: String) throws {
        let pageCountBefore = document.pageCount
        try apply(.insert(data: pagesData, at: insertionIndex))
        let insertedPages = try (insertionIndex..<(insertionIndex + document.pageCount - pageCountBefore)).map { pageIndex in
            try historyPage(atIndex: pageIndex)
        }
        let content = try PDFHistoryPageContent(data: pagesData)
        registerStep(named: actionName) { session in
            try session.removePages(insertedPages)
        } redo: { session in
            try session.putBack([PDFRemovedPageRun(startIndex: insertionIndex, pages: insertedPages, content: content)])
        }
    }

    /// Moves one page so that it ends up at `destinationIndex`.
    func movePage(from sourceIndex: Int, to destinationIndex: Int) throws {
        guard sourceIndex != destinationIndex else { return }
        let movedPage = try historyPage(atIndex: sourceIndex)
        try apply(.move(from: sourceIndex, to: destinationIndex))
        registerStep(named: "Move Page") { session in
            try session.move(movedPage, to: sourceIndex)
        } redo: { session in
            try session.move(movedPage, to: destinationIndex)
        }
    }

    private func move(_ movedPage: PDFHistoryPage, to destinationIndex: Int) throws {
        let pageIndex = try currentIndex(of: movedPage)
        if pageIndex != destinationIndex { try apply(.move(from: pageIndex, to: destinationIndex)) }
        go(to: destinationIndex)
    }

    /// Deletes pages so that Undo can put them back: first each run of consecutive pages
    /// is copied as saving would write it (content, ink, markup, and Graphite's re-editing
    /// records), which takes time proportional to the PDF. When the PDF keeps changing
    /// during the copy, the pages are deleted without an Undo step.
    func deletePages(at pageIndices: [Int]) async throws {
        let sortedIndices = Array(Set(pageIndices)).sorted()
        guard !sortedIndices.isEmpty else { return }
        guard sortedIndices.count < pageCount else { throw GraphiteError.invalidFile("A PDF must keep at least one page.") }
        // Boxes, not indices: pages can move while the copy is made.
        let deletedPages = try sortedIndices.map { pageIndex in try historyPage(atIndex: pageIndex) }
        var copiedRuns: [PDFRemovedPageRun]?
        for _ in 0..<Self.maximumDeletionCopyAttempts {
            let versionBeforeCopy = changeVersion
            let currentIndices = try deletedPages.map { deletedPage in try currentIndex(of: deletedPage) }
            let runs = Self.consecutiveRuns(of: currentIndices)
            let runData = try await export(pageRuns: runs)
            guard changeVersion == versionBeforeCopy else { continue }
            var pagesByIndex: [Int: PDFHistoryPage] = [:]
            for (pageIndex, deletedPage) in zip(currentIndices, deletedPages) { pagesByIndex[pageIndex] = deletedPage }
            copiedRuns = try zip(runs, runData).map { run, data in
                PDFRemovedPageRun(startIndex: run[0], pages: run.compactMap { pageIndex in pagesByIndex[pageIndex] },
                                  content: try PDFHistoryPageContent(data: data))
            }
            break
        }
        let indicesToDelete = try deletedPages.map { deletedPage in try currentIndex(of: deletedPage) }
        try apply(.delete(pages: indicesToDelete))
        guard let copiedRuns else { return }
        registerStep(named: deletedPages.count == 1 ? "Delete Page" : "Delete Pages") { session in
            try session.putBack(copiedRuns)
        } redo: { session in
            try session.removePages(copiedRuns.flatMap(\.pages))
        }
    }

    private func removePages(_ removedPages: [PDFHistoryPage]) throws {
        let pageIndices = try removedPages.map { removedPage in try currentIndex(of: removedPage) }
        try apply(.delete(pages: pageIndices))
        if let firstIndex = pageIndices.min() { go(to: min(firstIndex, max(document.pageCount - 1, 0))) }
    }

    /// Inserts copies of pages at the places they had, in ascending order, so each place
    /// counts the pages before it once those are back.
    private func putBack(_ runs: [PDFRemovedPageRun]) throws {
        for run in runs.sorted(by: { leftRun, rightRun in leftRun.startIndex < rightRun.startIndex }) {
            try apply(.insert(data: run.content.read(), at: run.startIndex))
            for (offset, restoredPage) in run.pages.enumerated() { rebind(restoredPage, to: try page(atIndex: run.startIndex + offset)) }
        }
        if let firstIndex = runs.map(\.startIndex).min() { go(to: firstIndex) }
    }

    /// Sorted page indices grouped into runs of consecutive pages.
    static func consecutiveRuns(of sortedIndices: [Int]) -> [[Int]] {
        var runs: [[Int]] = []
        for pageIndex in sortedIndices {
            if let lastIndex = runs.last?.last, lastIndex + 1 == pageIndex {
                runs[runs.count - 1].append(pageIndex)
            } else {
                runs.append([pageIndex])
            }
        }
        return runs
    }

    // MARK: Ink

    #if canImport(UIKit)
    /// Records a drawing change a page's canvas made, already applied to the page's ink.
    func registerInkChange(_ change: PencilDrawingChange, on page: PDFPage, overlaySize: CGSize) {
        let drawnPage = historyPage(for: page)
        registerStep(named: "Drawing") { session in
            try session.applyInkFromHistory(on: drawnPage, overlaySize: overlaySize) { drawing in change.reverting(drawing) }
        } redo: { session in
            try session.applyInkFromHistory(on: drawnPage, overlaySize: overlaySize) { drawing in change.reapplying(to: drawing) }
        }
    }

    /// Gives a page the drawing `transform` makes of its current one: through its canvas
    /// when one edits the page, otherwise straight into its annotations, rebuilding the
    /// ink tracker from the page's stored drawing. The page is shown if it is not.
    private func applyInkFromHistory(on drawnPage: PDFHistoryPage, overlaySize: CGSize, transform: (PKDrawing) -> PKDrawing?) throws {
        let pageIndex = try currentIndex(of: drawnPage)
        guard let page = drawnPage.page else { throw Self.pageNoLongerExists }
        if let canvas = inkCanvasProvider?.editingCanvas(for: page) {
            guard let drawing = transform(canvas.drawing) else { throw Self.inkChangedOutsideHistory }
            canvas.showDrawingFromHistory(drawing)
            if inkCanvasProvider?.isDisplaying(page) != true { go(to: pageIndex) }
            return
        }
        let currentInk = try Self.editableInk(on: page)
        var tracker = currentInk.tracker
        guard let drawing = transform(currentInk.drawing) else { throw Self.inkChangedOutsideHistory }
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: overlaySize)
        try apply(.updateInk(tracker.update(for: drawing, pageIndex: pageIndex, coordinates: coordinates)))
        go(to: pageIndex)
    }

    /// The page's editable ink as a canvas would restore it, or a new group when it has none.
    private static func editableInk(on page: PDFPage) throws -> (tracker: PDFPageInkTracker, drawing: PKDrawing) {
        guard let editableGroup = PDFInkGroups.editableGroup(on: page) else {
            return (PDFPageInkTracker(group: PDFInkGroups.newGroup(on: page)), PKDrawing())
        }
        guard let restored = PDFPageInkTracker.restoring(editableGroup) else { throw inkChangedOutsideHistory }
        return restored
    }
    #endif
}
