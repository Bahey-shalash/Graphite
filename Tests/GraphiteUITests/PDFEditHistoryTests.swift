import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// Undo and redo of page changes in a PDF's own history, and that the saved file always
/// matches the open document afterwards.
@MainActor
final class PDFEditHistoryTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFEditHistory-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A PDF whose pages are told apart by their widths.
    private func makePDF(named filename: String, pageWidths: [CGFloat]) throws -> URL {
        let location = directory.appendingPathComponent(filename)
        var defaultMediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &defaultMediaBox, nil))
        for width in pageWidths {
            var mediaBox = CGRect(x: 0, y: 0, width: width, height: 792)
            let pageInfo = [kCGPDFContextMediaBox as String: Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 40, y: 40, width: 40, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    private func pageWidths(of document: PDFDocument) -> [Int] {
        (0..<document.pageCount).compactMap { pageIndex in document.page(at: pageIndex).map { page in Int(page.bounds(for: .mediaBox).width) } }
    }

    private func rotations(of document: PDFDocument) -> [Int] {
        (0..<document.pageCount).compactMap { pageIndex in document.page(at: pageIndex)?.rotation }
    }

    private func markupNames(onPage pageIndex: Int, of document: PDFDocument) -> [String] {
        document.page(at: pageIndex)?.annotations.compactMap { annotation in
            PDFMarkupKind(annotationType: annotation.type) != nil ? annotation.persistentName : nil
        } ?? []
    }

    /// Each user action arrives in its own event, which closes its undo group; a test
    /// makes the groups itself.
    private func step(in session: PDFSession, _ operation: () throws -> Void) rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try operation()
    }

    private func step(in session: PDFSession, _ operation: () async throws -> Void) async rethrows {
        session.undoManager.beginUndoGrouping()
        defer { session.undoManager.endUndoGrouping() }
        try await operation()
    }

    private func openSession(pageWidths widths: [CGFloat]) async throws -> (PDFSession, URL) {
        let location = try makePDF(named: "Notebook-\(UUID().uuidString).pdf", pageWidths: widths)
        let session = try await PDFSession.open(location)
        session.undoManager.groupsByEvent = false
        return (session, location)
    }

    func testRotateMoveDuplicateAndInsertUndoAndRedoInOrderAndSaveAsShown() async throws {
        let (session, location) = try await openSession(pageWidths: [300, 310, 320, 330])
        let paperData = try Data(contentsOf: try makePDF(named: "Paper.pdf", pageWidths: [400]))

        try step(in: session) { try session.rotatePages([1], clockwise: true) }
        XCTAssertEqual(session.undoAvailability.undoActionName, "Rotate Page")
        try step(in: session) { try session.movePage(from: 0, to: 3) }
        try step(in: session) { try session.duplicatePages([0]) }
        try step(in: session) { try session.insertPages(paperData, at: 2, actionName: "Insert Page") }
        XCTAssertEqual(pageWidths(of: session.document), [310, 310, 400, 320, 330, 300])
        XCTAssertEqual(rotations(of: session.document), [90, 90, 0, 0, 0, 0])
        XCTAssertTrue(session.undoAvailability.canUndo)
        XCTAssertEqual(session.undoAvailability.undoActionName, "Insert Page")

        for _ in 0..<4 { session.undoAvailability.undo() }
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(pageWidths(of: session.document), [300, 310, 320, 330])
        XCTAssertEqual(rotations(of: session.document), [0, 0, 0, 0])
        XCTAssertFalse(session.undoAvailability.canUndo)
        XCTAssertTrue(session.undoAvailability.canRedo)

        for _ in 0..<4 { session.undoAvailability.redo() }
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(pageWidths(of: session.document), [310, 310, 400, 320, 330, 300])
        XCTAssertEqual(rotations(of: session.document), [90, 90, 0, 0, 0, 0])

        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(pageWidths(of: saved), pageWidths(of: session.document), "The file holds what the document shows.")
        XCTAssertEqual(rotations(of: saved), rotations(of: session.document))
    }

    func testDeletedPagesComeBackWithUnsavedMarkupAndEarlierStepsFollowTheCopies() async throws {
        let (session, location) = try await openSession(pageWidths: [300, 310, 320, 330, 340])
        try session.apply(.addMarkup(page: 2, markup: PDFMarkup(name: "Result", kind: .highlight, color: .yellow,
                                                                  lineBounds: [CGRect(x: 60, y: 600, width: 120, height: 14)])))
        try step(in: session) { try session.rotatePages([2], clockwise: true) }
        let originalThirdPage = try XCTUnwrap(session.document.page(at: 2))

        // Two runs: pages 2–3 and page 5 (indices 1, 2 and 4).
        try await step(in: session) { try await session.deletePages(at: [4, 1, 2]) }
        XCTAssertEqual(pageWidths(of: session.document), [300, 330])
        XCTAssertEqual(session.undoAvailability.undoActionName, "Delete Pages")

        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(pageWidths(of: session.document), [300, 310, 320, 330, 340])
        XCTAssertEqual(rotations(of: session.document), [0, 0, 90, 0, 0])
        XCTAssertEqual(markupNames(onPage: 2, of: session.document), ["Result"], "Unsaved markup comes back with its page.")
        let restoredThirdPage = try XCTUnwrap(session.document.page(at: 2))
        XCTAssertFalse(restoredThirdPage === originalThirdPage, "The page is back as a copy.")

        // The rotation step was recorded on the original page and now reaches its copy.
        session.undoAvailability.undo()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(rotations(of: session.document), [0, 0, 0, 0, 0])
        session.undoAvailability.redo()
        session.undoAvailability.redo()
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(pageWidths(of: session.document), [300, 330])
        session.undoAvailability.undo()
        XCTAssertEqual(pageWidths(of: session.document), [300, 310, 320, 330, 340])

        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(pageWidths(of: saved), [300, 310, 320, 330, 340])
        XCTAssertEqual(rotations(of: saved), [0, 0, 90, 0, 0])
        XCTAssertEqual(markupNames(onPage: 2, of: saved), ["Result"])
    }

    func testUndoingAnInsertionThenEditingElsewhereClearsRedoAndKeepsTheFileConsistent() async throws {
        let (session, location) = try await openSession(pageWidths: [300, 310])
        let paperData = try Data(contentsOf: try makePDF(named: "Paper.pdf", pageWidths: [400, 410]))
        try step(in: session) { try session.insertPages(paperData, at: 1, actionName: "Import Pages") }
        XCTAssertEqual(pageWidths(of: session.document), [300, 400, 410, 310])
        session.undoAvailability.undo()
        XCTAssertEqual(pageWidths(of: session.document), [300, 310])
        try step(in: session) { try session.rotatePages([0], clockwise: false) }
        XCTAssertFalse(session.undoAvailability.canRedo, "A new change ends what could be redone.")
        try await session.save()
        let saved = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(pageWidths(of: saved), [300, 310])
        XCTAssertEqual(rotations(of: saved), [270, 0])
    }

    func testAStepWhosePageIsGoneReportsItAndLeavesTheHistory() async throws {
        let (session, _) = try await openSession(pageWidths: [300, 310, 320])
        try step(in: session) { try session.rotatePages([1], clockwise: true) }
        // A change outside the history removes the page the step names.
        try session.apply(.delete(pages: [1]))
        session.undoAvailability.undo()
        XCTAssertNotNil(session.errorMessage)
        XCTAssertFalse(session.undoAvailability.canUndo)
        XCTAssertFalse(session.undoAvailability.canRedo)
        XCTAssertEqual(pageWidths(of: session.document), [300, 320])
    }

    func testKeptPagesStayInMemoryWhenSmallAndInAPrivateFileWhenLarge() throws {
        let smallData = Data(repeating: 7, count: 1_000)
        XCTAssertEqual(try PDFHistoryPageContent(data: smallData).read(), smallData)
        let largeData = Data((0..<2_000_000).map { index in UInt8(truncatingIfNeeded: index) })
        var largeContent: PDFHistoryPageContent? = try PDFHistoryPageContent(data: largeData)
        let temporaryLocation = try XCTUnwrap(largeContent?.temporaryFileLocation)
        XCTAssertTrue(temporaryLocation.lastPathComponent.hasPrefix(PDFBaselineSnapshot.filenamePrefix), "Cleaned up with baseline copies at launch.")
        XCTAssertEqual(try largeContent?.read(), largeData)
        largeContent = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryLocation.path), "The file goes with the step.")
    }

    func testConsecutiveRuns() {
        XCTAssertEqual(PDFSession.consecutiveRuns(of: [1, 2, 4, 6, 7, 8]), [[1, 2], [4], [6, 7, 8]])
        XCTAssertEqual(PDFSession.consecutiveRuns(of: []), [])
    }
}
