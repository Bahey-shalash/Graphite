#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Ink written on a PDF is never lost: not when its page scrolls away and back, not when
/// the tab is switched right after the stroke, not when Graphite leaves the screen, and not
/// when a canvas's change never reached the document.
@MainActor
final class PDFInkSafetyTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []
    private var directory: URL?

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    /// A page scrolled away and back, while its canvas is still kept: the page's canvas
    /// shows every stroke, and the next stroke keeps them all, in the file too. The page
    /// already had saved ink, as the owner's paper did; strokes added since then were lost
    /// when the page came back (2026-10-13).
    func testStrokesSurviveTheirPageScrollingAwayAndBack() async throws {
        let session = try await openNotebook(pageCount: 6)
        session.isWriting = true
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: firstPage, in: session)
        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 100)])
        try await waitUntil { self.inkCount(on: firstPage) == 1 }
        // Saved, so the page carries a record of its ink to edit it again.
        try await session.save()
        canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(atHeight: 160)])
        try await waitUntil { self.inkCount(on: firstPage) == 2 }

        // Away to the last page, then back, as a reader does.
        for pageIndex in [2, 4, 5, 3, 1, 0] {
            session.go(to: pageIndex)
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
        }
        let canvasAfterReturn = try await editingCanvas(for: firstPage, in: session)
        _ = await eventually { canvasAfterReturn.drawing.strokes.count >= 2 }
        XCTAssertEqual(canvasAfterReturn.drawing.strokes.count, 2, "The page's canvas shows both strokes after scrolling back.")
        XCTAssertEqual(inkCount(on: firstPage), 2, "The page still has both strokes.")

        // A third stroke on the page keeps the first two.
        canvasAfterReturn.drawing = PKDrawing(strokes: canvasAfterReturn.drawing.strokes + [stroke(atHeight: 220)])
        _ = await eventually { self.inkCount(on: firstPage) == 3 }
        XCTAssertEqual(inkCount(on: firstPage), 3, "A new stroke keeps the earlier ones.")
        try await session.save()
        XCTAssertEqual(try savedInkCount(at: session.location, pageIndex: 0), 3)
        let saved = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        let editable = try XCTUnwrap(PDFInkGroups.editableGroup(on: saved))
        XCTAssertEqual(try PKDrawing(data: editable.record.drawingData).strokes.count, 3, "All three strokes can be edited again.")
    }

    /// Strokes on several pages, then another tab at once: every stroke is in the file.
    func testStrokesDrawnJustBeforeSwitchingTabsReachTheFile() async throws {
        let folder = try makeDirectory()
        let location = folder.appendingPathComponent("Notebook.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: 3).write(to: location)
        try Data("Notes\n".utf8).write(to: folder.appendingPathComponent("Note.md"))
        let workspace = try await makeWorkspace(folder: folder)
        await workspace.open(try VaultPath("Note.md"))
        let noteTab = workspace.layout.activeTab.id
        await workspace.open(try VaultPath("Notebook.pdf"), placement: .newTab)
        let session = try XCTUnwrap(workspace.pdfSession)
        session.isWriting = true
        _ = try host(AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: firstPage, in: session)
        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 100), stroke(atHeight: 140)])
        // No wait: the tab changes in the same turn of the main queue as the stroke.
        workspace.activateTab(noteTab)
        try await waitUntil { session.pdfView?.window == nil }
        try await workspace.saveOpenDocuments()
        XCTAssertEqual(try savedInkCount(at: location, pageIndex: 0), 2, "Both strokes are in the file.")
    }

    /// Strokes, then Graphite leaves the screen (it saves every open document): the strokes
    /// are in the file, with the record that lets them be edited again.
    func testStrokesReachTheFileWhenGraphiteLeavesTheScreen() async throws {
        let session = try await openNotebook(pageCount: 2)
        session.isWriting = true
        _ = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: firstPage, in: session)
        canvas.drawing = PKDrawing(strokes: [stroke(atHeight: 100)])
        try await session.save()
        XCTAssertEqual(try savedInkCount(at: session.location, pageIndex: 0), 1)
        let reopened = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        let editable = try XCTUnwrap(PDFInkGroups.editableGroup(on: reopened), "The stroke can be edited again after reopening.")
        XCTAssertEqual(try PKDrawing(data: editable.record.drawingData).strokes.count, 1)
    }

    /// A canvas whose change never reached the PDF: its ink is recorded when the view is built
    /// again because the PDF stopped taking touches, and the new view shows it.
    func testInkACanvasNeverRecordedIsSavedWhenThePDFViewIsBuiltAgain() async throws {
        let session = try await openNotebook(pageCount: 2)
        session.isWriting = true
        _ = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        let canvas = try await editingCanvas(for: firstPage, in: session)
        let oldView = try XCTUnwrap(session.pdfView)
        // Shown without the change being reported, as when a change is lost on its way.
        canvas.showWithoutRecording(PKDrawing(strokes: [stroke(atHeight: 100), stroke(atHeight: 140)]))
        XCTAssertEqual(inkCount(on: firstPage), 0)
        let coordinator = try XCTUnwrap((oldView as? GraphitePDFDisplayView)?.annotationCoordinator)
        coordinator.rebuildViewAfterRecordingInk()
        XCTAssertEqual(inkCount(on: firstPage), 2, "The canvas's ink is recorded before its view goes.")
        try await waitUntil { session.pdfView != nil && session.pdfView !== oldView }
        let newCanvas = try await editingCanvas(for: firstPage, in: session)
        _ = await eventually { newCanvas.drawing.strokes.count == 2 }
        XCTAssertEqual(newCanvas.drawing.strokes.count, 2, "The new view shows the ink.")
        try await session.save()
        XCTAssertEqual(try savedInkCount(at: session.location, pageIndex: 0), 2)
    }

    /// A recognizer the page's scrolling waits for, left under way with no touch (as palm
    /// rejection could be): it is reset within a few seconds, and a record says so.
    func testAGestureLeftUnderWayOnThePDFIsResetAndRecorded() async throws {
        let session = try await openNotebook(pageCount: 2)
        session.isWriting = true
        _ = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        _ = try await editingCanvas(for: firstPage, in: session)
        let coordinator = try XCTUnwrap((session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator)
        let palmRejection = try XCTUnwrap(coordinator.palmRejectionRecognizer)
        let recordsBefore = repairRecords()
        palmRejection.state = .began
        palmRejection.state = .changed
        XCTAssertTrue(palmRejection.isUnderWayWithoutTouches)
        try await waitUntil(seconds: 6) { palmRejection.state == .possible }
        DiagnosticRecords.waitForPendingWrites()
        let newRecords = repairRecords().subtracting(recordsBefore)
        XCTAssertFalse(newRecords.isEmpty, "A record of the repair is kept.")
        if let record = newRecords.first, let data = try? Data(contentsOf: record),
           let text = String(data: data, encoding: .utf8) {
            XCTAssertTrue(text.contains("PalmRejectionRecognizer"), text)
            XCTAssertTrue(text.contains("touchedViews"), text)
        }
    }

    private func repairRecords() -> Set<URL> {
        guard let folder = DiagnosticRecords.folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return Set(files.filter { file in file.lastPathComponent.hasPrefix("PDFRepaired-") })
    }

    // MARK: Helpers

    private func savedInkCount(at location: URL, pageIndex: Int) throws -> Int {
        let saved = try XCTUnwrap(PDFDocument(url: location))
        return try XCTUnwrap(saved.page(at: pageIndex)).annotations.filter { annotation in annotation.type == "Ink" }.count
    }

    private func makeDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("InkSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder
        return folder
    }

    private func makeWorkspace(folder: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: folder)
        workspace.store = VaultStore(root: folder)
        let index = try VaultIndex(databaseURL: folder.appendingPathComponent("index.sqlite"))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { name in name.hasSuffix(".md") || name.hasSuffix(".pdf") }
        try await index.refresh(paths: names.map { name in try VaultPath(name) }, root: folder)
        workspace.index = index
        return workspace
    }

    private func openNotebook(pageCount: Int) async throws -> PDFSession {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("InkSafety-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank), pageCount: pageCount).write(to: location)
        locations.append(location)
        return try await PDFSession.open(location)
    }

    private func host(_ rootView: AnyView) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return controller
    }

    private func editingCanvas(for page: PDFPage, in session: PDFSession) async throws -> PDFPageCanvasView {
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil { coordinator()?.editingCanvas(for: page) != nil }
        return try XCTUnwrap(coordinator()?.editingCanvas(for: page))
    }

    private var strokeCount = 0

    private func stroke(atHeight height: CGFloat) -> PKStroke {
        strokeCount += 1
        let creationDate = Date(timeIntervalSinceReferenceDate: Double(strokeCount))
        let points = (0...10).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: CGFloat(50 + pointIndex * 10), y: height), timeOffset: Double(pointIndex) / 10,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: creationDate))
    }

    private func inkCount(on page: PDFPage) -> Int {
        page.annotations.filter { annotation in annotation.type == "Ink" }.count
    }

    /// Whether the condition became true within the time, without failing the test.
    private func eventually(seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func waitUntil(seconds: Double = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("The condition did not become true within \(seconds) seconds")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
#endif
