#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
@testable import GraphiteUI

/// Text boxes on a PDF page in the hosted app, with the floating palette's text tool: its
/// tap makes a box, typing goes
/// into it through the system text view, a tap beside it ends typing as one step of the
/// PDF's history, and the box is moved, turned, undone, saved and read back from the file.
@MainActor
final class PDFTextBoxesTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var locations: [URL] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for location in locations { try? FileManager.default.removeItem(at: location) }
        locations = []
        PaletteInkSelection.tool = .none
    }

    func testATapOfTheTextToolMakesABoxThatIsTypedMovedTurnedUndoneSavedAndReadBack() async throws {
        try requireTouches()
        let (session, controller, page) = try await openNotebookWithTextTool()
        let window = try XCTUnwrap(controller.view.window)
        let pdfView = try XCTUnwrap(session.pdfView)

        // A tap of the text tool on the page starts a box there and raises the keyboard.
        let tapPoint = CGPoint(x: 90, y: 700)
        try await tap(atPagePoint: tapPoint, on: page, in: pdfView, window: window)
        let textView = try await editingTextView(in: controller)
        XCTAssertTrue(textView.isFirstResponder, "The keyboard, Scribble and dictation type into the box.")
        textView.insertText("Lecture notes")
        XCTAssertTrue(session.textBoxes(on: page).isEmpty, "The document takes the box when typing ends.")
        attachScreenshot(of: controller, named: "Typing in a new text box")

        // A tap beside it ends typing: the box is in the document as one step. (The point is
        // above the bar the system shows over the keyboard's place.)
        try await tap(atPagePoint: CGPoint(x: 450, y: 560), on: page, in: pdfView, window: window)
        try await waitUntil("the typed box is in the document") { session.textBoxes(on: page).count == 1 }
        let typed = try XCTUnwrap(session.textBoxes(on: page).first)
        XCTAssertEqual(typed.plainText, "Lecture notes")
        XCTAssertEqual(typed.origin.x, tapPoint.x, accuracy: 2)
        XCTAssertEqual(typed.origin.y, tapPoint.y, accuracy: 2)
        XCTAssertEqual(typed.rotationRadians, 0)
        XCTAssertEqual(typed.height, PDFTextBoxLayout(box: typed).fittedHeight, accuracy: 0.01)
        XCTAssertEqual(session.undoManager.undoActionName, "Add Text Box")
        XCTAssertTrue(session.textBoxActivity == .idle)
        try await waitUntil("the box is drawn over the ink") { self.shownBoxLayerCount(in: controller) > 0 }
        attachScreenshot(of: controller, named: "A text box over the page")

        // Moved, then turned, each one step; undo takes both back, redo the move again.
        let selection = PDFTextBoxSelection(boxName: typed.name, page: session.historyPage(for: page))
        session.textBoxActivity = .selected(selection)
        endEvent(of: session)
        try session.changeSelectedTextBox(actionName: "Move Text Box") { box in box.origin.x += 50; box.origin.y -= 40 }
        endEvent(of: session)
        try session.changeSelectedTextBox(actionName: "Rotate Text Box") { box in box = box.rotated(to: 0.5) }
        endEvent(of: session)
        let turned = try XCTUnwrap(session.textBox(selection))
        XCTAssertEqual(turned.rotationRadians, 0.5, accuracy: 1e-9)
        attachScreenshot(of: controller, named: "A text box moved and turned")
        session.undoAvailability.undo()
        endEvent(of: session)
        session.undoAvailability.undo()
        endEvent(of: session)
        XCTAssertEqual(session.textBox(selection), typed)
        session.undoAvailability.redo()
        endEvent(of: session)
        XCTAssertEqual(session.textBox(selection)?.origin.x ?? 0, typed.origin.x + 50, accuracy: 0.01)
        session.undoAvailability.redo()
        endEvent(of: session)

        // Saved and opened again, the box is the same, and other readers see its text.
        try await session.save()
        let reopened = try await PDFSession.open(session.location)
        let reopenedPage = try XCTUnwrap(reopened.document.page(at: 0))
        XCTAssertEqual(reopened.textBoxes(on: reopenedPage), [turned])
        let reader = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        XCTAssertEqual(reader.annotations.first { annotation in annotation.type == "FreeText" }?.contents, "Lecture notes")
        XCTAssertNil(session.errorMessage)
    }

    func testTypingAgainInABoxChangesItAsOneStepAndRemovingAllItsTextRemovesIt() async throws {
        try requireTouches()
        let (session, controller, page) = try await openNotebookWithTextTool()
        let window = try XCTUnwrap(controller.view.window)
        let pdfView = try XCTUnwrap(session.pdfView)
        try await tap(atPagePoint: CGPoint(x: 80, y: 600), on: page, in: pdfView, window: window)
        let textView = try await editingTextView(in: controller)
        textView.insertText("One line")
        let oneLineHeight = textView.bounds.height
        textView.insertText("\nTwo lines\nThree lines")
        try await waitUntil("the box grows with its text") { textView.bounds.height > oneLineHeight * 2 }
        try await tap(atPagePoint: CGPoint(x: 400, y: 200), on: page, in: pdfView, window: window)
        try await waitUntil("the box is in the document") { session.textBoxes(on: page).count == 1 }
        let threeLines = try XCTUnwrap(session.textBoxes(on: page).first)
        XCTAssertEqual(threeLines.plainText, "One line\nTwo lines\nThree lines")

        // Typing in it again, inside the box: one "Edit Text" step.
        try await tap(atPagePoint: threeLines.pagePoint(along: 10, down: 8), on: page, in: pdfView, window: window)
        let secondTextView = try await editingTextView(in: controller)
        secondTextView.selectedRange = NSRange(location: 0, length: (secondTextView.text as NSString).length)
        secondTextView.deleteBackward()
        try await tap(atPagePoint: CGPoint(x: 400, y: 200), on: page, in: pdfView, window: window)
        try await waitUntil("the emptied box is removed") { session.textBoxes(on: page).isEmpty }
        XCTAssertEqual(session.undoManager.undoActionName, "Delete Text Box")
        session.undoAvailability.undo()
        endEvent(of: session)
        XCTAssertEqual(session.textBoxes(on: page), [threeLines])
    }

    func testTextTypedBeforeASaveIsSavedWhileTypingGoesOn() async throws {
        try requireTouches()
        let (session, controller, page) = try await openNotebookWithTextTool()
        let window = try XCTUnwrap(controller.view.window)
        let pdfView = try XCTUnwrap(session.pdfView)
        try await tap(atPagePoint: CGPoint(x: 80, y: 500), on: page, in: pdfView, window: window)
        let textView = try await editingTextView(in: controller)
        textView.insertText("Saved while typing")
        try await session.save()
        XCTAssertTrue(textView.isFirstResponder, "Saving does not end typing.")
        let saved = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 0))
        XCTAssertEqual(PDFPageManager.textBoxes(on: saved).map(\.plainText), ["Saved while typing"])
        textView.insertText(" and after")
        try await tap(atPagePoint: CGPoint(x: 400, y: 200), on: page, in: pdfView, window: window)
        try await waitUntil("typing ends") { session.textBoxActivity == .idle }
        XCTAssertEqual(session.textBoxes(on: page).map(\.plainText), ["Saved while typing and after"])
        XCTAssertEqual(session.undoManager.undoActionName, "Add Text Box", "One step for the whole of the typing.")
    }

    // MARK: Helpers

    /// Taps need IOKit's digitizer events; without them the test fails rather than passing unseen.
    private func requireTouches() throws {
        if let reason = SynthesizedTouches.unavailableReason { throw TouchesUnavailable(reason: reason) }
    }

    private struct TouchesUnavailable: Error {
        let reason: String
    }

    private func openNotebookWithTextTool() async throws -> (PDFSession, UIHostingController<AnyView>, PDFPage) {
        let location = try makeHostedBlankNotebook(named: "TextBoxes")
        locations.append(location)
        let session = try await PDFSession.open(location)
        let controller = try host(AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let page = try XCTUnwrap(session.document.page(at: 0))
        func coordinator() -> PDFAnnotationCoordinator? { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator }
        try await waitUntil("the page's canvas edits it") { coordinator()?.editingCanvas(for: page) != nil }
        // The floating palette's Text Box, chosen once the palette is up (taking up the
        // palette's tool puts Graphite's tools away), which the page's canvas takes at once.
        PaletteInkSelection.placesTextBoxes = true
        try await waitUntil("the canvas places text") { coordinator()?.editingCanvas(for: page)?.placesTextBoxes == true }
        return (session, controller, page)
    }

    private func tap(atPagePoint pagePoint: CGPoint, on page: PDFPage, in pdfView: PDFView, window: UIWindow) async throws {
        let windowPoint = pdfView.convert(pdfView.convert(pagePoint, from: page), to: window)
        await SynthesizedTouches(window: window).move(paths: [(windowPoint, windowPoint)], steps: 1, stepSeconds: 0.03, holdSeconds: 0)
    }

    private func editingTextView(in controller: UIViewController) async throws -> PDFTextBoxEditingView {
        try await waitUntil("a box is typed in") { self.descendants(of: controller.view, matching: PDFTextBoxEditingView.self).first?.isFirstResponder == true }
        return try XCTUnwrap(descendants(of: controller.view, matching: PDFTextBoxEditingView.self).first)
    }

    private func shownBoxLayerCount(in controller: UIViewController) -> Int {
        descendants(of: controller.view, matching: PDFPageTextBoxesView.self).reduce(0) { count, view in
            count + (view.layer.sublayers?.first?.sublayers?.count ?? 0)
        }
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

    /// Steps made in code arrive within one turn of the run loop, in one undo group.
    private func endEvent(of session: PDFSession) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(session.undoManager.groupingLevel, 0)
    }

    private func attachScreenshot(of controller: UIViewController, named name: String) {
        guard let window = controller.view.window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }
}
#endif
