#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class PencilWorkspaceTests: XCTestCase {
    func testHidingTabsKeepsTheEditorAndItsUndoHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocusWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = "# Lecture notes\n\nA quiet workspace for reading and writing.\n\n## Key ideas\n\nKeep notes, handwriting and lecture slides together.\n"
        try Data(source.utf8).write(to: directory.appendingPathComponent("Lecture.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Lecture.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .source
        func panes(showsTabs: Bool) -> some View {
            NavigationStack {
                WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in },
                               showQuickSwitcher: {}, showsTabBar: showsTabs)
            }
        }
        let controller = UIHostingController(rootView: panes(showsTabs: true))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { !descendants(of: controller.view, matching: MarkdownTextView.self).isEmpty }
        let editor = try XCTUnwrap(descendants(of: controller.view, matching: MarkdownTextView.self).first)
        editor.becomeFirstResponder()
        editor.selectedRange = NSRange(location: (source as NSString).length, length: 0)
        editor.insertText("Remember this.")
        try await waitUntil { session.text.hasSuffix("Remember this.") }
        let selectedRange = editor.selectedRange
        XCTAssertTrue(editor.undoManager?.canUndo == true)
        editor.resignFirstResponder()
        attachScreenshot(of: window, named: "Markdown workspace with tabs")
        controller.rootView = panes(showsTabs: false)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(descendants(of: controller.view, matching: MarkdownTextView.self).first === editor)
        XCTAssertEqual(editor.selectedRange, selectedRange)
        XCTAssertTrue(editor.undoManager?.canUndo == true)
        attachScreenshot(of: window, named: "Markdown workspace with tabs hidden")
        controller.rootView = panes(showsTabs: true)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(descendants(of: controller.view, matching: MarkdownTextView.self).first === editor)
        editor.undoManager?.undo()
        try await waitUntil { session.text == source }
    }

    func testReadingPositionSurvivesViewRecreationAndNewHeadingTakesPriority() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingPosition-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let path = try VaultPath("Lecture.md")
        let source = (0..<80).map { section in
            "## Section \(section)\n\nLecture notes for section \(section). This paragraph gives the reading view enough content to scroll.\n\n"
        }.joined()
        let position = ReadingPosition()
        let cache = ReadingBlocksCache()
        func preview(request: HeadingScrollRequest? = nil) -> AnyView {
            AnyView(MarkdownPreview(source: source, path: path, root: directory, index: index, configuration: ReadingConfiguration(),
                headingScrollRequest: .constant(request), handledScrollToken: .constant(nil), navigate: { _, _ in },
                openPDF: { _, _ in }, updateProperties: nil, blocksCache: cache, savedPosition: position))
        }
        let controller = UIHostingController(rootView: preview())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func readingScrollView() -> UIScrollView? {
            descendants(of: controller.view, matching: UIScrollView.self).first { $0.contentSize.height > $0.bounds.height * 3 }
        }
        try await waitUntil { readingScrollView() != nil }
        let firstScrollView = try XCTUnwrap(readingScrollView())
        firstScrollView.setContentOffset(CGPoint(x: 0, y: 1100 - firstScrollView.adjustedContentInset.top), animated: false)
        try await waitUntil { position.verticalOffset > 1000 }
        let rememberedOffset = position.verticalOffset
        controller.rootView = AnyView(Text("Another tab"))
        try await waitUntil { readingScrollView() == nil }
        controller.rootView = preview()
        try await waitUntil { (readingScrollView()?.contentOffset.y ?? 0) > 1000 }
        let restoredScrollView = try XCTUnwrap(readingScrollView())
        XCTAssertEqual(restoredScrollView.contentOffset.y + restoredScrollView.adjustedContentInset.top, rememberedOffset, accuracy: 3)

        controller.rootView = AnyView(Text("Another tab"))
        try await waitUntil { readingScrollView() == nil }
        controller.rootView = preview(request: HeadingScrollRequest(anchor: NotePreviewDocument.anchor(forHeading: "Section 1")))
        try await waitUntil { readingScrollView() != nil && position.verticalOffset < 500 }
        XCTAssertLessThan(try XCTUnwrap(readingScrollView()).contentOffset.y, 500)
        attachScreenshot(of: window, named: "Restored reading workspace")
    }

    func testReadingModeRestoresPageTouchesAndKeepsInkWhenReturningToWriting() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("PencilWorkspace-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)).write(to: location)
        defer { try? FileManager.default.removeItem(at: location) }
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: NavigationStack {
            PDFPane(session: session, resolveConflict: { _ in })
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { descendants(of: controller.view, matching: PDFPageCanvasView.self).contains { !$0.isHidden } }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: PDFPageCanvasView.self).first { !$0.isHidden })
        let page = try XCTUnwrap(canvas.page)
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)

        let strokePoints = (0...10).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 50 + pointIndex * 10, y: 100), timeOffset: Double(pointIndex) / 10,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: strokePoints, creationDate: Date()))])
        try await waitUntil { page.annotations.contains { $0.type == "Ink" } }
        let ink = try XCTUnwrap(page.annotations.first { $0.type == "Ink" })
        XCTAssertFalse(ink.shouldDisplay, "The live canvas draws ink without doubling its PDF appearance.")

        session.isWriting = false
        try await waitUntil { canvas.isHidden }
        XCTAssertFalse(canvas.isUserInteractionEnabled)
        XCTAssertTrue(ink.shouldDisplay, "Reading must show the existing PDF ink.")
        let pagePoint = canvas.convert(CGPoint(x: 100, y: 100), to: pdfView)
        XCTAssertNil(pdfView.annotationCoordinator?.canvas(at: pagePoint, in: pdfView), "Reading leaves touches with PDFKit.")
        try await Task.sleep(for: .milliseconds(350))
        attachScreenshot(of: window, named: "PDF reading workspace")

        session.isWriting = true
        try await waitUntil { !canvas.isHidden && canvas.isUserInteractionEnabled }
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        XCTAssertFalse(ink.shouldDisplay)
        XCTAssertTrue(pdfView.annotationCoordinator?.canvas(at: pagePoint, in: pdfView) === canvas)
        try await Task.sleep(for: .milliseconds(350))
        attachScreenshot(of: window, named: "PDF writing workspace")
        try await session.save()
        let reopened = try XCTUnwrap(PDFDocument(url: location))
        XCTAssertEqual(reopened.page(at: 0)?.annotations.filter { $0.type == "Ink" }.count, 1)
    }

    func testDrawingEditorUpdatesFingerPolicyWithoutReplacingCanvas() async throws {
        let preferenceName = "GraphiteDrawingDrawsWithFinger"
        let previousPreference = UserDefaults.standard.object(forKey: preferenceName)
        UserDefaults.standard.set(false, forKey: preferenceName)
        defer {
            if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: preferenceName) }
            else { UserDefaults.standard.removeObject(forKey: preferenceName) }
        }
        let request = DrawingEditorRequest(target: .newDrawing(notePath: try VaultPath("Note.md"), insertionRange: NSRange(location: 0, length: 0)),
                                           title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil, background: .white, format: .png)
        let controller = UIHostingController(rootView: DrawingEditor(request: request, save: { _, _ in },
            exportCopy: { _, _ in throw CocoaError(.featureUnsupported) }, preserveDraft: { _ in }, removeDraft: {}))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { !descendants(of: controller.view, matching: InfiniteCanvasView.self).isEmpty }
        let canvas = try XCTUnwrap(descendants(of: controller.view, matching: InfiniteCanvasView.self).first)
        XCTAssertEqual(canvas.drawingPolicy, .pencilOnly)
        UserDefaults.standard.set(true, forKey: preferenceName)
        try await waitUntil { canvas.drawingPolicy == .anyInput }
        XCTAssertTrue(descendants(of: controller.view, matching: InfiniteCanvasView.self).first === canvas)
        UserDefaults.standard.set(false, forKey: preferenceName)
        try await waitUntil { canvas.drawingPolicy == .pencilOnly }
        canvas.setZoomScale(canvas.minimumZoomScale * 2, animated: false)
        XCTAssertGreaterThan(canvas.zoomScale, canvas.minimumZoomScale)
        canvas.fitToWidth()
        try await waitUntil { abs(canvas.zoomScale - canvas.minimumZoomScale) < 0.001 }
        attachScreenshot(of: window, named: "Drawing workspace")
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testReadWriteSwitchWithoutEditsDoesNotRewritePDF() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("PencilWorkspace-Unchanged-\(UUID().uuidString).pdf")
        let originalBytes = try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank))
        try originalBytes.write(to: location)
        defer { try? FileManager.default.removeItem(at: location) }
        let session = try await PDFSession.open(location)
        session.isWriting = false
        session.isWriting = true
        try await session.save()
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted writing workspace did not reach the expected state.")
    }
}
#endif
