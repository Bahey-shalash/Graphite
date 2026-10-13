import Foundation
import CoreGraphics

/// Counts the finger gestures on a PDF that the PDF did not answer, to tell when it stopped
/// taking touches (`PDFPaneHealthMonitor`). A gesture counts only when it moved far enough to
/// scroll or zoom, could have scrolled, and Apple Pencil was not in use around it, so a hand
/// resting while writing never counts. One the PDF answered starts the count again.
struct UnansweredGestureCount {
    /// Gestures in a row the PDF did not answer before it is taken to have stopped.
    static let limit = 3
    /// They count in a row only within this long of each other.
    static let windowSeconds: TimeInterval = 30
    /// How far a finger, or two fingers apart, move before a gesture is one to answer.
    static let answerableMovementPoints: CGFloat = 40
    /// A gesture this soon after Apple Pencil was on the screen may be a hand resting to write.
    static let pencilQuietSeconds: TimeInterval = 2

    struct Gesture {
        var fingerCount: Int
        /// The vertical drag, or the change of the distance between two fingers, in points.
        var largestMovement: CGFloat
        var wasAnswered: Bool
        /// Whether the PDF could scroll up or down, or the gesture was a pinch.
        var couldMove: Bool
        var drawsWithFinger: Bool
        /// Seconds since Apple Pencil was last seen on the screen when the gesture ended.
        var secondsSincePencil: TimeInterval
    }

    private(set) var unansweredTimes: [TimeInterval] = []

    /// Adds a gesture that ended at `time`; true when the PDF is taken to have stopped taking
    /// touches, after which the count starts again.
    mutating func add(_ gesture: Gesture, at time: TimeInterval) -> Bool {
        // With finger drawing one finger draws, and may rightly change nothing (an eraser
        // over blank paper); only two fingers, which scroll and zoom, count then.
        guard !(gesture.drawsWithFinger && gesture.fingerCount < 2),
              gesture.largestMovement >= Self.answerableMovementPoints, gesture.couldMove,
              gesture.secondsSincePencil >= Self.pencilQuietSeconds else { return false }
        guard !gesture.wasAnswered else {
            unansweredTimes.removeAll()
            return false
        }
        unansweredTimes = unansweredTimes.filter { unansweredTime in time - unansweredTime <= Self.windowSeconds } + [time]
        guard unansweredTimes.count >= Self.limit else { return false }
        unansweredTimes.removeAll()
        return true
    }
}

#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
import PDFKit
import PencilKit
import os
import GraphiteApple

/// Keeps a PDF that is shown taking touches, and leaves evidence when it stops.
///
/// On the owner's iPad (2026-10-13) a PDF being written on stopped taking any touch: no
/// scrolling, no zooming, while the rest of Graphite worked; showing another tab and coming
/// back, which builds the PDF's view again, revived it. The cause was not seen on a
/// simulator, which cannot send Apple Pencil touches. This watches for it from outside the
/// PDF view:
///
/// - Every finger gesture that starts on the PDF is followed by a passive recognizer on the
///   window (`UnansweredGestureCount` says which count). When the touches reached the PDF
///   and several such gestures in a row changed nothing (no scroll, no zoom, no edit, no
///   text selected), the PDF stopped taking touches: a record is written and the view is
///   built again, as switching tabs does, after every canvas's ink is recorded. When they
///   reached another view over the PDF, only a record is written: that view may be a
///   control the person meant to use.
/// - Once a second, the page canvases and the recognizers of the PDF are checked for states
///   that cannot last, a canvas on screen that is not the page's own or that records
///   nothing, a gesture still under way with no touch left. Each is put right and recorded.
@MainActor
final class PDFPaneHealthMonitor {
    /// A gesture still under way with no touch left this long is stuck.
    static let stuckGestureSeconds: TimeInterval = 2
    /// A record of touches reaching a view over the PDF is written at most this often.
    static let coveredRecordIntervalSeconds: TimeInterval = 300
    private static let log = Logger(subsystem: "com.graphite.study", category: "PDFPaneHealth")

    private weak var coordinator: PDFAnnotationCoordinator?
    private weak var pdfView: GraphitePDFDisplayView?
    private weak var observedWindow: UIWindow?
    private let observer = PDFTouchSequenceObserver()
    private var timer: Timer?
    private var unansweredInPDF = UnansweredGestureCount()
    private var unansweredOverPDF = UnansweredGestureCount()
    private var lastCoveredRecordTime: TimeInterval = -.infinity
    /// When each recognizer was first seen under way without touches, by identity.
    private var gesturesWithoutTouchesSince: [ObjectIdentifier: TimeInterval] = [:]
    /// What the PDF looked like when the gesture followed now began.
    private var gestureStart: GestureStart?
    /// Set once the view is to be built again, so the old one is left alone meanwhile.
    private(set) var hasRequestedRebuild = false

    private struct GestureStart {
        let contentOffset: CGPoint
        let scaleFactor: CGFloat
        let changeVersion: Int
        let selectedText: String?
        let touchCount: Int
        let startLocations: [CGPoint]
        let locationInWindow: CGPoint
        /// Whether the touch reached the PDF view or a view inside it.
        let reachedPDF: Bool
        let couldScrollVertically: Bool
        var largestMovement: CGFloat = 0
        var wasPinch = false
        var wasAnswered = false
    }

    init(coordinator: PDFAnnotationCoordinator, pdfView: GraphitePDFDisplayView) {
        self.coordinator = coordinator
        self.pdfView = pdfView
        observer.sequenceBegan = { [weak self] touches in self?.gestureBegan(touches) }
        observer.sequenceMoved = { [weak self] touches in self?.gestureMoved(touches) }
        observer.sequenceEnded = { [weak self] in self?.gestureEnded() }
    }

    /// Follows the window the PDF view is in now, or none.
    func windowDidChange(to window: UIWindow?) {
        guard window !== observedWindow else { return }
        observedWindow?.removeGestureRecognizer(observer)
        observedWindow = window
        window?.addGestureRecognizer(observer)
        timer?.invalidate()
        timer = nil
        gestureStart = nil
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkStates() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        windowDidChange(to: nil)
    }

    // MARK: Gestures the PDF should answer

    private var mainScrollView: UIScrollView? { pdfView?.documentView?.enclosingScrollViewForHealth }

    private func gestureBegan(_ touches: [UITouch]) {
        gestureStart = nil
        // A finger on a PDF embedded in a note may scroll the note instead, rightly; a sheet
        // or popover over the PDF takes the touches meant for it.
        guard let pdfView, let coordinator, !coordinator.isEmbedded, let window = pdfView.window, !hasRequestedRebuild,
              window.rootViewController?.presentedViewController == nil else { return }
        let fingerTouches = touches.filter { touch in touch.type == .direct }
        guard !fingerTouches.isEmpty, fingerTouches.count == touches.count else { return }
        let locations = fingerTouches.map { touch in touch.location(in: pdfView) }
        guard locations.allSatisfy({ location in pdfView.bounds.contains(location) }) else { return }
        let touchedViews = fingerTouches.compactMap(\.view)
        let reachedPDF = !touchedViews.isEmpty && touchedViews.allSatisfy { view in view.isDescendant(of: pdfView) }
        // Another scroll view or a control over the PDF answers the gesture itself.
        if !reachedPDF, touchedViews.contains(where: { view in view is UIControl || view.enclosingScrollViewForHealth.map { scrollView in !scrollView.isDescendant(of: pdfView) } ?? false }) {
            return
        }
        let scrollView = mainScrollView
        let couldScrollVertically = scrollView.map { scrollView in
            scrollView.contentSize.height > scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom + 1
        } ?? false
        gestureStart = GestureStart(contentOffset: scrollView?.contentOffset ?? .zero, scaleFactor: pdfView.scaleFactor,
                                    changeVersion: coordinator.session.changeVersion, selectedText: pdfView.currentSelection?.string,
                                    touchCount: fingerTouches.count, startLocations: locations,
                                    locationInWindow: fingerTouches[0].location(in: nil), reachedPDF: reachedPDF,
                                    couldScrollVertically: couldScrollVertically)
    }

    private func gestureMoved(_ touches: [UITouch]) {
        guard var start = gestureStart, let pdfView else { return }
        let fingerTouches = touches.filter { touch in touch.type == .direct }
        // A second finger joining a one-finger gesture makes it a pinch or a two-finger scroll.
        if fingerTouches.count != start.touchCount {
            gestureBegan(touches)
            return
        }
        let locations = fingerTouches.map { touch in touch.location(in: pdfView) }
        var movement: CGFloat = 0
        if let location = locations.first, let startLocation = start.startLocations.first {
            // Vertical only: a page that fits the width rightly does not move sideways.
            movement = abs(location.y - startLocation.y)
        }
        if locations.count >= 2, start.startLocations.count >= 2 {
            let distanceNow = hypot(locations[0].x - locations[1].x, locations[0].y - locations[1].y)
            let distanceAtStart = hypot(start.startLocations[0].x - start.startLocations[1].x, start.startLocations[0].y - start.startLocations[1].y)
            let pinch = abs(distanceNow - distanceAtStart)
            if pinch >= UnansweredGestureCount.answerableMovementPoints { start.wasPinch = true }
            movement = max(movement, pinch)
        }
        start.largestMovement = max(start.largestMovement, movement)
        if !start.wasAnswered, didAnswer(since: start) { start.wasAnswered = true }
        gestureStart = start
    }

    private func didAnswer(since start: GestureStart) -> Bool {
        guard let pdfView, let coordinator else { return true }
        let offset = mainScrollView?.contentOffset ?? .zero
        return abs(offset.x - start.contentOffset.x) > 0.5 || abs(offset.y - start.contentOffset.y) > 0.5
            || abs(pdfView.scaleFactor - start.scaleFactor) > 0.0001
            || coordinator.session.changeVersion != start.changeVersion
            || pdfView.currentSelection?.string != start.selectedText
    }

    private func gestureEnded() {
        guard var start = gestureStart, let coordinator else { return }
        gestureStart = nil
        if !start.wasAnswered, didAnswer(since: start) { start.wasAnswered = true }
        let now = ProcessInfo.processInfo.systemUptime
        let gesture = UnansweredGestureCount.Gesture(fingerCount: start.touchCount, largestMovement: start.largestMovement,
                                                     wasAnswered: start.wasAnswered, couldMove: start.couldScrollVertically || start.wasPinch,
                                                     drawsWithFinger: coordinator.drawsWithFinger,
                                                     secondsSincePencil: now - observer.lastPencilTouchTime)
        if !start.wasAnswered, gesture.largestMovement >= UnansweredGestureCount.answerableMovementPoints {
            Self.log.notice("A finger gesture on the PDF changed nothing; the touch reached the PDF: \(start.reachedPDF)")
        }
        if start.reachedPDF {
            guard unansweredInPDF.add(gesture, at: now) else { return }
            paneStoppedTakingTouches(lastTouchInWindow: start.locationInWindow)
        } else {
            guard unansweredOverPDF.add(gesture, at: now), now - lastCoveredRecordTime >= Self.coveredRecordIntervalSeconds else { return }
            lastCoveredRecordTime = now
            var fields = describe(touchAt: start.locationInWindow)
            fields["action"] = "None: the touches reached a view over the PDF, which may be one the person meant to use."
            DiagnosticRecords.write(kind: "PDFTouchesReachedAnotherView", fields: fields)
        }
    }

    /// Records what the PDF looked like, then builds its view again.
    private func paneStoppedTakingTouches(lastTouchInWindow: CGPoint) {
        guard let coordinator, !hasRequestedRebuild else { return }
        var fields = describe(touchAt: lastTouchInWindow)
        fields["action"] = "The PDF's ink was recorded and its view built again, as switching tabs does."
        DiagnosticRecords.write(kind: "PDFStoppedTakingTouches", fields: fields)
        DiagnosticContext.note("The PDF stopped taking touches; its view was built again")
        hasRequestedRebuild = true
        coordinator.rebuildViewAfterRecordingInk()
    }

    // MARK: States that cannot last

    private func checkStates() {
        guard let pdfView, let coordinator, pdfView.window != nil, !hasRequestedRebuild else { return }
        DiagnosticContext.set(String(format: "%.0f x %.0f", pdfView.window?.bounds.width ?? 0, pdfView.window?.bounds.height ?? 0), for: "window")
        DiagnosticContext.set(String(format: "PDF, %@, zoom %.2f, %d pages", coordinator.isWriting ? "writing" : "reading",
                                     pdfView.scaleFactor, coordinator.session.pageCount), for: "document")
        var repairs = coordinator.repairCanvases()
        let now = ProcessInfo.processInfo.systemUptime
        var seenStuck = Set<ObjectIdentifier>()
        for recognizer in recognizersThePDFWaitsFor() where recognizer.isUnderWayWithoutTouches {
            let identifier = ObjectIdentifier(recognizer)
            seenStuck.insert(identifier)
            let since = gesturesWithoutTouchesSince[identifier] ?? now
            gesturesWithoutTouchesSince[identifier] = since
            guard now - since >= Self.stuckGestureSeconds else { continue }
            repairs.append("Reset \(type(of: recognizer)), under way for \(Int(now - since)) s without a touch")
            if let canvas = recognizer.view?.enclosingCanvasForHealth { coordinator.recordUnrecordedInk(of: canvas) }
            recognizer.isEnabled = false
            recognizer.isEnabled = true
            gesturesWithoutTouchesSince[identifier] = nil
        }
        gesturesWithoutTouchesSince = gesturesWithoutTouchesSince.filter { entry in seenStuck.contains(entry.key) }
        guard !repairs.isEmpty else { return }
        Self.log.error("Repaired the PDF: \(repairs.joined(separator: "; "), privacy: .public)")
        var fields = describe(touchAt: pdfView.convert(CGPoint(x: pdfView.bounds.midX, y: pdfView.bounds.midY), to: nil))
        fields["repairs"] = repairs
        DiagnosticRecords.write(kind: "PDFRepaired", fields: fields)
    }

    /// The PDF view's recognizers, its scroll views', and the page canvases', which a page's
    /// scrolling, zooming and drawing go through.
    private func recognizersThePDFWaitsFor() -> [UIGestureRecognizer] {
        guard let pdfView else { return [] }
        return Self.recognizers(in: pdfView)
    }

    private static func recognizers(in view: UIView) -> [UIGestureRecognizer] {
        (view.gestureRecognizers ?? []) + view.subviews.flatMap { subview in recognizers(in: subview) }
    }

    // MARK: Evidence

    /// What a touch at a point of the window reaches, and the state of everything that
    /// decides whether the PDF answers it.
    func describe(touchAt pointInWindow: CGPoint) -> [String: Any] {
        guard let pdfView, let window = pdfView.window else { return ["pdfView": "not in a window"] }
        var fields: [String: Any] = [:]
        let touchedView = window.hitTest(pointInWindow, with: nil)
        fields["touchPoint"] = "\(Int(pointInWindow.x)), \(Int(pointInWindow.y))"
        fields["touchedViews"] = touchedView.map(Self.ancestry) ?? ["nothing"]
        fields["touchedViewIsInPDF"] = touchedView?.isDescendant(of: pdfView) ?? false
        fields["pdfViewAncestors"] = Self.ancestry(of: pdfView).prefix(12).map { $0 }
        fields["pdfFrameInWindow"] = NSCoder.string(for: pdfView.convert(pdfView.bounds, to: nil))
        fields["scaleFactor"] = Double(pdfView.scaleFactor)
        fields["autoScales"] = pdfView.autoScales
        if let scrollView = mainScrollView {
            fields["scrollView"] = [
                "isScrollEnabled": scrollView.isScrollEnabled,
                "isUserInteractionEnabled": scrollView.isUserInteractionEnabled,
                "contentOffset": NSCoder.string(for: scrollView.contentOffset),
                "contentSize": NSCoder.string(for: scrollView.contentSize),
                "zoomScale": Double(scrollView.zoomScale)
            ] as [String: Any]
        }
        fields["recognizers"] = recognizersThePDFWaitsFor().map(Self.describe)
        fields["windowRecognizers"] = (window.gestureRecognizers ?? []).map(Self.describe)
        fields["pencil"] = PencilActivity.diagnosticDescription
        fields["canvases"] = coordinator?.canvasDiagnostics() ?? []
        fields["selectionFrames"] = Self.selectionFrames(in: window).map { frame in
            "\(NSCoder.string(for: frame.convert(frame.bounds, to: nil))) hidden \(frame.isHidden) alpha \(frame.alpha)"
        }
        fields["presentedViewController"] = window.rootViewController?.presentedViewController.map { String(describing: type(of: $0)) } ?? "none"
        return fields
    }

    private static func ancestry(of view: UIView) -> [String] {
        var names: [String] = []
        var current: UIView? = view
        while let shown = current {
            names.append("\(type(of: shown)) interaction \(shown.isUserInteractionEnabled) hidden \(shown.isHidden) alpha \(String(format: "%.2f", shown.alpha))")
            current = shown.superview
        }
        return names
    }

    private static func describe(_ recognizer: UIGestureRecognizer) -> String {
        let stateName: String
        switch recognizer.state {
        case .possible: stateName = "possible"
        case .began: stateName = "began"
        case .changed: stateName = "changed"
        case .ended: stateName = "ended"
        case .cancelled: stateName = "cancelled"
        case .failed: stateName = "failed"
        @unknown default: stateName = "unknown"
        }
        let viewName = recognizer.view.map { String(describing: type(of: $0)) } ?? "no view"
        return "\(type(of: recognizer)) on \(viewName): \(stateName), enabled \(recognizer.isEnabled), touches \(recognizer.numberOfTouches)"
    }

    private static func selectionFrames(in view: UIView) -> [SelectionFrameView] {
        ((view as? SelectionFrameView).map { [$0] } ?? []) + view.subviews.flatMap { subview in selectionFrames(in: subview) }
    }
}

/// Follows every touch sequence of a window without taking part: it never recognizes, never
/// prevents another recognizer and never delays or cancels a touch.
final class PDFTouchSequenceObserver: UIGestureRecognizer {
    var sequenceBegan: (([UITouch]) -> Void)?
    var sequenceMoved: (([UITouch]) -> Void)?
    var sequenceEnded: (() -> Void)?
    private var activeTouches = Set<UITouch>()

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /// When Apple Pencil was last seen on the screen, on the uptime clock.
    private(set) var lastPencilTouchTime: TimeInterval = -.infinity

    private func notePencil(in touches: Set<UITouch>) {
        if touches.contains(where: { touch in touch.type == .pencil }) { lastPencilTouchTime = ProcessInfo.processInfo.systemUptime }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        notePencil(in: touches)
        let isNewSequence = activeTouches.isEmpty
        activeTouches.formUnion(touches)
        if isNewSequence { sequenceBegan?(Array(activeTouches)) } else { sequenceMoved?(Array(activeTouches)) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        notePencil(in: touches)
        sequenceMoved?(Array(activeTouches))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish(touches) }

    override func reset() {
        super.reset()
        if !activeTouches.isEmpty { sequenceEnded?() }
        activeTouches.removeAll()
    }

    private func finish(_ touches: Set<UITouch>) {
        notePencil(in: touches)
        sequenceMoved?(Array(activeTouches))
        activeTouches.subtract(touches)
        guard activeTouches.isEmpty else { return }
        sequenceEnded?()
        // Never recognizing, it fails once the sequence is over, so UIKit resets it.
        state = .failed
    }
}

extension UIGestureRecognizer {
    /// Under way, yet following no touch: a state UIKit leaves only when told. A hover is
    /// under way without touching by nature, and does not count.
    var isUnderWayWithoutTouches: Bool {
        !(self is UIHoverGestureRecognizer) && isEnabled && (state == .began || state == .changed) && numberOfTouches == 0
    }
}

private extension UIView {
    var enclosingScrollViewForHealth: UIScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }

    var enclosingCanvasForHealth: PDFPageCanvasView? {
        var current: UIView? = self
        while let view = current {
            if let canvas = view as? PDFPageCanvasView { return canvas }
            current = view.superview
        }
        return nil
    }
}
#endif

