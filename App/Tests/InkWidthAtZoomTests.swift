#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

/// A pen keeps its width on the page at any zoom, as on paper: on a PDF page, whose canvas
/// draws larger to stay sharp, and in a drawing, whose canvas the person zooms.
@MainActor
final class InkWidthAtZoomTests: XCTestCase {
    private func selection(_ ink: PencilInk, width: Double) -> PencilToolSelection {
        var preset = InkPreset(ink: ink)
        preset.width = width
        return PencilToolSelection(kind: .ink, preset: preset, erasesWholeStrokes: true, eraserWidth: 18, isRulerActive: false)
    }

    func testAPageIsDrawnNoLargerThanKeepsThePensPencilsAndHighlightersWidth() {
        func largestScale(_ inkType: PKInkingTool.InkType, width: CGFloat) -> CGFloat {
            PDFPageOverlayView.largestRenderingScale(keepingWidthOf: PKInkingTool(inkType, color: .black, width: width))
        }
        XCTAssertEqual(largestScale(.pen, width: 4.8), PDFPageOverlayView.maximumRenderingScale, "25.66 / 4.8 is more than 3")
        XCTAssertEqual(largestScale(.pen, width: 12), 2, "25.66 / 12 is 2.1")
        XCTAssertEqual(largestScale(.pencil, width: 7), 2, "16 / 7 is 2.3")
        XCTAssertEqual(largestScale(.marker, width: 28), 2, "60 / 28 is 2.1")
        XCTAssertEqual(largestScale(.pencil, width: 16), 1, "Never below the page's own size")
        XCTAssertEqual(largestScale(.monoline, width: 3), PDFPageOverlayView.maximumRenderingScale,
                       "PencilKit does not hold a monoline tool to its widest width")
        XCTAssertEqual(PDFPageOverlayView.largestRenderingScale(keepingWidthOf: PKEraserTool(.vector)), PDFPageOverlayView.maximumRenderingScale)
    }

    func testABroadPencilOnAZoomedPageLandsAsWideAsChosenAndANarrowPenDrawsSharpAgain() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("WidthAtZoom-\(UUID().uuidString).pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .blank)).write(to: location)
        defer { try? FileManager.default.removeItem(at: location) }
        let session = try await PDFSession.open(location)
        let controller = UIHostingController(rootView: NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { self.canvases(in: controller.view).contains { !$0.isHidden } }
        let canvas = try XCTUnwrap(canvases(in: controller.view).first { !$0.isHidden })
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let toolPicker = PKToolPicker()
        canvas.takeTool(from: toolPicker, fixedTool: selection(.pen, width: 2.8))
        pdfView.autoScales = false
        pdfView.scaleFactor = 3.2
        try await waitUntil { canvas.zoomScale == PDFPageOverlayView.maximumRenderingScale }

        canvas.takeTool(from: toolPicker, fixedTool: selection(.pencil, width: 7))
        XCTAssertEqual(canvas.zoomScale, 2, "16 points is the widest pencil: the page is drawn at twice its size")
        let pencil = try XCTUnwrap(canvas.tool as? PKInkingTool)
        XCTAssertEqual(pencil.width / canvas.zoomScale, 7, accuracy: 0.01, "7 points on the page")

        canvas.takeTool(from: toolPicker, fixedTool: selection(.pen, width: 2.8))
        XCTAssertEqual(canvas.zoomScale, PDFPageOverlayView.maximumRenderingScale, "A narrow pen draws as sharp as the zoom allows")
        let pen = try XCTUnwrap(canvas.tool as? PKInkingTool)
        XCTAssertEqual(pen.width / canvas.zoomScale, 2.8, accuracy: 0.01)
        XCTAssertEqual(canvas.drawingSize.width, try XCTUnwrap(canvas.page).bounds(for: .cropBox).width, accuracy: 0.5)
    }

    func testADrawingZoomedInWritesAsWideInTheDrawingAsAtItsFittedSize() throws {
        let canvas = InfiniteCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 1_000))
        canvas.canvasWidth = 400
        canvas.layoutIfNeeded()
        XCTAssertEqual(canvas.zoomScale, 2, accuracy: 0.001, "Fitted: 800 points of screen for 400 of drawing")
        canvas.takeTool(from: PKToolPicker(), fixedTool: selection(.monoline, width: 1.56))
        XCTAssertEqual(try XCTUnwrap(canvas.tool as? PKInkingTool).width, 1.56 * 2, accuracy: 0.001)

        canvas.zoomScale = 6
        canvas.layoutIfNeeded()
        let zoomedTool = try XCTUnwrap(canvas.tool as? PKInkingTool)
        XCTAssertEqual(zoomedTool.width / canvas.zoomScale, 1.56, accuracy: 0.001, "The stroke is 1.56 points of the drawing at any zoom")
    }

    private func canvases(in view: UIView) -> [PDFPageCanvasView] {
        view.subviews.flatMap { child in ((child as? PDFPageCanvasView).map { [$0] } ?? []) + canvases(in: child) }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted canvas did not reach the expected state.")
    }
}
#endif
