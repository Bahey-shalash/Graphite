#if canImport(UIKit)
import UIKit
import PencilKit
import os
import GraphiteApple

/// Measures Pencil writing: signposts for the Pencil's touches and for the work done at each
/// pen-up, and a log line with the tool each stroke begins with and the width it lands with.
/// It exists in debug builds and in builds made with the `GRAPHITE_WRITING_TRACE` condition
/// (`OTHER_SWIFT_FLAGS=-DGRAPHITE_WRITING_TRACE`), which measure an optimized build; in any
/// other build every call compiles to nothing.
///
/// "Pencil stroke to ink" (`FR-101`) is measured on screen with a camera. The app's share of
/// it lies between the events "Pencil down" (with how long UIKit took to deliver the touch)
/// and "Stroke began" (PencilKit took the touch); the pen-up's between "Pencil up" and the
/// end of the "Pen-up recording" interval. Instruments shows them under the subsystem
/// `com.graphite.study`, category `PencilWriting`.
@MainActor
enum PencilWritingTrace {
    #if DEBUG || GRAPHITE_WRITING_TRACE
    private static let signposter = OSSignposter(subsystem: "com.graphite.study", category: "PencilWriting")
    private static let logger = Logger(subsystem: "com.graphite.study", category: "PencilWriting")
    private static let millisecondsPerSecond = 1_000.0
    #endif

    /// Runs `work` inside a signpost interval named `name`.
    @inline(__always)
    static func measure<Outcome>(_ name: StaticString, _ work: () throws -> Outcome) rethrows -> Outcome {
        #if DEBUG || GRAPHITE_WRITING_TRACE
        let intervalState = signposter.beginInterval(name)
        defer { signposter.endInterval(name, intervalState) }
        #endif
        return try work()
    }

    /// Apple Pencil touched a page; UIKit delivered the touch this long after it happened.
    @inline(__always)
    static func pencilDidTouch(_ touch: UITouch) {
        #if DEBUG || GRAPHITE_WRITING_TRACE
        let deliveryMilliseconds = (PencilActivity.now - touch.timestamp) * millisecondsPerSecond
        signposter.emitEvent("Pencil down", "delivered after \(deliveryMilliseconds, format: .fixed(precision: 2)) ms")
        #endif
    }

    /// Apple Pencil left the page, or UIKit cancelled its touch.
    @inline(__always)
    static func pencilDidLift(_ touch: UITouch) {
        #if DEBUG || GRAPHITE_WRITING_TRACE
        let deliveryMilliseconds = (PencilActivity.now - touch.timestamp) * millisecondsPerSecond
        signposter.emitEvent("Pencil up", "delivered after \(deliveryMilliseconds, format: .fixed(precision: 2)) ms")
        #endif
    }

    /// PencilKit began a stroke on `canvas`: the tool it draws with, the tool the canvas
    /// should draw with for the chosen one, and where the choice came from.
    @inline(__always)
    static func strokeDidBegin(on canvas: HistoryCanvasView) {
        #if DEBUG || GRAPHITE_WRITING_TRACE
        let drawingTool = describe(canvas.tool)
        let expectedTool = canvas.chosenTool.map { chosenTool in describe(canvas.toolForDrawing(chosenTool)) } ?? "none"
        let chosenTool = canvas.chosenTool.map(describe) ?? "none"
        let source = canvas.followsToolPicker ? "floating palette" : "fixed bar"
        let zoomScale = canvas.zoomScale
        let screenPointsPerDrawingPoint = screenPointsPerDrawingPoint(of: canvas)
        let canvasKind = String(describing: type(of: canvas))
        signposter.emitEvent("Stroke began", "\(drawingTool, privacy: .public)")
        logger.log("""
            Stroke began on \(canvasKind, privacy: .public) at canvas zoom \(zoomScale, format: .fixed(precision: 3)), \
            \(screenPointsPerDrawingPoint, format: .fixed(precision: 3)) screen points per drawing point, from the \(source, privacy: .public): \
            draws with \(drawingTool, privacy: .public); expected \(expectedTool, privacy: .public); chosen \(chosenTool, privacy: .public)
            """)
        #endif
    }

    /// A stroke was recorded: its point size and the width PencilKit draws it, both in the
    /// drawing's points, which on a PDF page are the page's points.
    @inline(__always)
    static func strokeWasRecorded(_ stroke: PKStroke, on canvas: HistoryCanvasView) {
        #if DEBUG || GRAPHITE_WRITING_TRACE
        let transform = stroke.transform
        let transformScale = abs(transform.a * transform.d - transform.b * transform.c).squareRoot()
        let pointSizes = stroke.path.map { strokePoint in strokePoint.size.width * transformScale }.sorted()
        let drawnWidths = PencilStrokeSampler.visibleSegments(of: stroke).joined().map(\.width).sorted()
        guard !pointSizes.isEmpty, !drawnWidths.isEmpty else { return }
        let medianPointSize = pointSizes[pointSizes.count / 2]
        let medianDrawnWidth = drawnWidths[drawnWidths.count / 2]
        let inkName = stroke.ink.inkType.rawValue
        let zoomScale = canvas.zoomScale
        logger.log("""
            Stroke recorded at zoom \(zoomScale, format: .fixed(precision: 3)): \(inkName, privacy: .public), \
            drawn width in the drawing \(medianDrawnWidth, format: .fixed(precision: 3)) pt, \
            point size \(medianPointSize, format: .fixed(precision: 3)) pt (medians of \(pointSizes.count) points)
            """)
        #endif
    }

    #if DEBUG || GRAPHITE_WRITING_TRACE
    /// How large a point of the drawing is on screen: the PDF's zoom on a page, the
    /// scroll view's zoom in a drawing. A drawing point is `zoomScale` points of the canvas.
    private static func screenPointsPerDrawingPoint(of canvas: HistoryCanvasView) -> CGFloat {
        guard canvas.window != nil else { return canvas.zoomScale }
        return canvas.convert(CGRect(x: 0, y: 0, width: canvas.zoomScale, height: 0), to: nil).width
    }

    private static func describe(_ tool: PKTool) -> String {
        if let inkingTool = tool as? PKInkingTool {
            return "\(inkingTool.inkType.rawValue) width \(String(format: "%.3f", inkingTool.width))"
                + " azimuth \(String(format: "%.3f", inkingTool.azimuth)) alpha \(String(format: "%.2f", inkingTool.color.cgColor.alpha))"
        }
        if let eraserTool = tool as? PKEraserTool { return "eraser width \(String(format: "%.3f", eraserTool.width))" }
        return String(describing: type(of: tool))
    }
    #endif
}
#endif
