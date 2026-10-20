import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// Ink a Pencil canvas shows but has not recorded in the PDF yet is recorded first by every
/// save, copy, export, deletion and page-tree edit, through the writer the view registers.
@MainActor
final class PDFSessionPendingInkRecordTests: XCTestCase {
    private var directory: URL!
    private var location: URL!

    override func setUpWithError() throws {
        directory = try TemporaryVault.make(prefix: "PDFSessionPendingInkRecord", for: self).root
        location = directory.appendingPathComponent("Notebook.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 3).write(to: location)
    }

    private final class WriterCounter {
        var calls = 0
    }

    private func stroke(named name: String) -> PDFEdit {
        let stroke = PortableInkStroke(name: name, segments: [[CGPoint(x: 100, y: 300), CGPoint(x: 300, y: 300)]],
                                       width: 2, red: 0, green: 0, blue: 0, alpha: 1, outline: nil)
        return .updateInk(PDFInkUpdate(pageIndex: 0, group: PDFInkGroups.defaultGroup, removal: .strokes([]), addedStrokes: [stroke], editableRecord: nil))
    }

    func testSavingRecordsPendingInkFirstSoTheFileHoldsTheStroke() async throws {
        let session = try await PDFSession.open(location)
        let canvasOwner = NSObject()
        var hasRecorded = false
        // What the view's writer does: record the stroke a canvas shows but has not handed over.
        session.registerPendingInkRecordWriter(for: canvasOwner) {
            guard !hasRecorded else { return }
            hasRecorded = true
            try? session.apply(self.stroke(named: "pending-stroke"))
        }

        try await session.save()

        XCTAssertTrue(hasRecorded)
        let savedPage = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0))
        XCTAssertEqual(savedPage.annotations.compactMap(\.persistentName), ["pending-stroke"], "The pending stroke is in the file.")
    }

    func testEverySaveCopyExportAndPageTreeEditAsksTheViewToRecordFirst() async throws {
        let session = try await PDFSession.open(location)
        let counter = WriterCounter()
        let canvasOwner = NSObject()
        session.registerPendingInkRecordWriter(for: canvasOwner) { counter.calls += 1 }

        func assertOneMoreCall(_ operation: String, _ body: () async throws -> Void) async throws {
            let callsBefore = counter.calls
            try await body()
            XCTAssertGreaterThan(counter.calls, callsBefore, "\(operation) records pending ink first.")
        }
        try await assertOneMoreCall("Saving without changes") { try await session.save() }
        try await assertOneMoreCall("Saving a copy") { _ = try await session.saveSeparateCopy() }
        try await assertOneMoreCall("Exporting pages") { _ = try await session.export(pages: [0]) }
        try await assertOneMoreCall("Exporting runs of pages for Undo") { _ = try await session.export(pageRuns: [[0], [2]]) }
        try await assertOneMoreCall("Deleting pages") { try await session.deletePages(at: [2]) }
        try await assertOneMoreCall("Moving a page") { try session.apply(.move(from: 0, to: 1)) }
        try await assertOneMoreCall("Inserting a page") {
            try session.apply(.insert(data: PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)), at: 0))
        }
        try await assertOneMoreCall("Closing the session") { try await session.saveBeforeClosing() }
    }

    func testAnEditThatLeavesThePageTreeAloneDoesNotAskTheView() async throws {
        let session = try await PDFSession.open(location)
        let counter = WriterCounter()
        let canvasOwner = NSObject()
        session.registerPendingInkRecordWriter(for: canvasOwner) { counter.calls += 1 }
        try session.apply(.rotate(page: 0, clockwise: true))
        try session.apply(.bookmark(page: 0, label: "Page 1"))
        XCTAssertEqual(counter.calls, 0)
    }

    func testAWriterThatIsUnregisteredIsNotCalledAgain() async throws {
        let session = try await PDFSession.open(location)
        let counter = WriterCounter()
        let canvasOwner = NSObject()
        session.registerPendingInkRecordWriter(for: canvasOwner) { counter.calls += 1 }
        try await session.save()
        XCTAssertEqual(counter.calls, 1)
        session.unregisterPendingInkRecordWriter(for: canvasOwner)
        try await session.save()
        XCTAssertEqual(counter.calls, 1)
    }

    func testSavingAfterAConflictDoesNotRecordPendingInkIntoTheOpenDocument() async throws {
        let session = try await PDFSession.open(location)
        try session.apply(.rotate(page: 1, clockwise: true))
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 2).write(to: location)
        _ = try? await session.save()
        XCTAssertTrue(session.hasExternalConflict)
        let counter = WriterCounter()
        let canvasOwner = NSObject()
        session.registerPendingInkRecordWriter(for: canvasOwner) { counter.calls += 1 }

        _ = try? await session.save()

        XCTAssertEqual(counter.calls, 0)
    }
}
