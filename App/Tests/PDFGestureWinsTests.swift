#if os(iOS)
import XCTest
import SwiftUI
import PencilKit
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// A person's drag or pinch on a PDF always wins: the page stays where the gesture leaves it,
/// whatever else is going on (Read Aloud playing, a save), in a window of any size. Gestures
/// are real finger touches delivered through UIKit (`SynthesizedTouches`), so PDFKit's and
/// PencilKit's own recognizers take them as they take a finger's.
///
/// The owner filmed a PDF at about 250% whose page moved a little under the finger and then
/// sprang back, after every drag and pinch (2026-10-13). With Read Aloud following the word
/// read, following scrolled the page back at every view update; these tests fail with that
/// code. In the build the owner filmed, the window tiled beside another app was laid out
/// wider than its tile, and the page's right side could not be scrolled into view.
@MainActor
final class PDFGestureWinsTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var directory: URL?
    private var savedPreferences: [String: Any?] = [:]
    private var savedReadingSpeed: Double?
    private var workspace: WorkspaceModel?

    /// The zoom the owner wrote at: 250%.
    private static let writingZoom: CGFloat = 2.5

    override func setUp() async throws {
        if let reason = SynthesizedTouches.unavailableReason { throw XCTSkip(reason) }
        for key in [PDFAnnotationPreferenceKey.drawsWithFinger, PencilToolbarStyle.preferenceKey] {
            savedPreferences[key] = UserDefaults.standard.object(forKey: key)
        }
        UserDefaults.standard.set(false, forKey: PDFAnnotationPreferenceKey.drawsWithFinger)
        UserDefaults.standard.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        PencilActivity.forgetPencil()
    }

    override func tearDown() async throws {
        if let workspace {
            workspace.activeReadAloud.clear()
            if let savedReadingSpeed { workspace.activeReadAloud.session.setSpeed(savedReadingSpeed) }
        }
        workspace = nil
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for (key, value) in savedPreferences {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    // MARK: Gestures win

    /// Page 2 at 250% in the whole workspace: a drag and a pinch each leave the page where
    /// they put it for two seconds, and so does a save.
    func testADragAndAPinchOnAZoomedPageStayWhereTheyLeaveIt() async throws {
        let (workspace, session) = try await openPaper()
        let window = try host(workspace, size: nil)
        let pdfView = try await zoomedPDFView(of: session, in: window)
        let touches = SynthesizedTouches(window: window)
        let middle = visibleMiddle(of: pdfView, in: window)

        let beforeDrag = position(of: pdfView)
        await touches.drag(from: CGPoint(x: middle.x + 60, y: middle.y + 120), to: CGPoint(x: middle.x - 60, y: middle.y - 120))
        let afterDrag = position(of: pdfView)
        XCTAssertGreaterThan(distance(beforeDrag, afterDrag), 100, "The drag moves the page.")
        try await assertStaysStill(pdfView, seconds: 2, name: "after a drag")

        await touches.pinch(firstFinger: (CGPoint(x: middle.x - 30, y: middle.y - 30), CGPoint(x: middle.x - 90, y: middle.y - 90)),
                            secondFinger: (CGPoint(x: middle.x + 30, y: middle.y + 30), CGPoint(x: middle.x + 90, y: middle.y + 90)))
        XCTAssertGreaterThan(pdfView.scaleFactor, afterDrag.scale * 1.3, "The pinch zooms in.")
        try await assertStaysStill(pdfView, seconds: 2, name: "after a pinch")

        let beforeSave = position(of: pdfView)
        try await session.save()
        try await assertStaysStill(pdfView, seconds: 2, name: "after a save")
        XCTAssertEqual(position(of: pdfView), beforeSave)
        attachScreenshot(of: window, named: "Zoomed page after a drag, a pinch and a save")
    }

    /// The same while Read Aloud reads the page: a pinch and a drag pause following, the page
    /// stays where they put it while reading goes on, through a save and past the moment
    /// following used to come back by itself. Back to Reading brings the word read into view
    /// once, and following then never scrolls the page back and forth between two places.
    func testWhileReadAloudPlaysADragAndAPinchStay() async throws {
        let (workspace, session) = try await openPaper()
        let window = try host(workspace, size: nil)
        let pdfView = try await zoomedPDFView(of: session, in: window)
        let reader = workspace.activeReadAloud
        reader.readPDF(session, firstPageIndex: 1, lastPageIndex: session.pageCount - 1)
        try await waitUntil(timeoutSeconds: 30) { reader.session.state == .speaking && !(pdfView.highlightedSelections ?? []).isEmpty }
        try await Task.sleep(for: .milliseconds(600))
        let touches = SynthesizedTouches(window: window)
        let middle = visibleMiddle(of: pdfView, in: window)

        let beforePinch = position(of: pdfView)
        await touches.pinch(firstFinger: (CGPoint(x: middle.x - 30, y: middle.y - 30), CGPoint(x: middle.x - 80, y: middle.y - 80)),
                            secondFinger: (CGPoint(x: middle.x + 30, y: middle.y + 30), CGPoint(x: middle.x + 80, y: middle.y + 80)))
        XCTAssertGreaterThan(pdfView.scaleFactor, beforePinch.scale * 1.2, "The pinch zooms in while reading.")
        XCTAssertFalse(reader.followsReading, "A pinch pauses following, as a scroll does.")
        let wordsBefore = highlightedText(in: pdfView)
        try await assertStaysStill(pdfView, seconds: 2, name: "after a pinch while reading")

        await touches.drag(from: CGPoint(x: middle.x, y: middle.y + 120), to: CGPoint(x: middle.x, y: middle.y - 120))
        try await session.save()
        // Following came back by itself five seconds after a scroll; on a PDF it waits for
        // Back to Reading.
        try await assertStaysStill(pdfView, seconds: 6, name: "after a drag and a save while reading")
        XCTAssertEqual(reader.session.state, .speaking, "Reading goes on.")
        XCTAssertNotEqual(highlightedText(in: pdfView), wordsBefore, "Reading moved on to other words meanwhile.")
        attachScreenshot(of: window, named: "Page kept where the gestures left it while reading")

        workspace.activeReadAloudNavigator.backToReading()
        try await waitUntil { self.highlightIsOnScreen(in: pdfView) }
        // Following now brings each word into view once: the page never goes back and forth.
        var offsets: [CGFloat] = [position(of: pdfView).offset.y]
        let end = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < end {
            try await Task.sleep(for: .milliseconds(20))
            let offset = position(of: pdfView).offset.y
            if abs(offset - (offsets.last ?? offset)) > 0.5 { offsets.append(offset) }
        }
        let reversals = zip(offsets, offsets.dropFirst()).filter { pair in pair.1 < pair.0 - 0.5 }.count
        XCTAssertEqual(reversals, 0, "Following scrolled the page back up: \(offsets.map { offset in Int(offset) })")

        // Paused, nothing follows: a drag stays though the word read is off screen.
        reader.session.pause()
        await touches.drag(from: CGPoint(x: middle.x, y: middle.y + 150), to: CGPoint(x: middle.x, y: middle.y - 150))
        try await assertStaysStill(pdfView, seconds: 2, name: "after a drag while reading is paused")
    }

    // MARK: Split view

    /// The window sizes a PDF gets tiled beside another app on an 11-inch iPad: half the
    /// screen in portrait and in landscape, and two thirds in landscape.
    static let tiledWindowSizes: [CGSize] = [CGSize(width: 417, height: 1194), CGSize(width: 597, height: 834), CGSize(width: 694, height: 834)]

    /// In a window tiled beside another app, at 250% on page 2: a pinch at each corner of the
    /// page shown zooms there and stays; every edge of the page can be scrolled into view and
    /// stays there; the page never runs off the window.
    func testInATiledWindowThePageZoomsAtEveryCornerAndEveryEdgeCanBeReached() async throws {
        let (workspace, session) = try await openPaper()
        for size in Self.tiledWindowSizes {
            let name = "\(Int(size.width)) by \(Int(size.height))"
            let window = try host(workspace, size: size)
            let pdfView = try await zoomedPDFView(of: session, in: window)
            let pdfFrame = pdfView.convert(pdfView.bounds, to: window)
            XCTAssertGreaterThanOrEqual(pdfFrame.minX, -0.5, "\(name): the PDF starts inside the window.")
            XCTAssertLessThanOrEqual(pdfFrame.maxX, window.bounds.width + 0.5, "\(name): the PDF ends inside the window.")
            try await checkPinchesAtTheCorners(of: pdfView, in: window, name: name)
            try await checkEveryEdgeCanBeReached(of: pdfView, session: session, in: window, name: name)
            attachScreenshot(of: window, named: "\(name), right edge of page 2 at 250%")
            close(window)
        }
    }

    /// In a window tiled beside another app, at 250%: at each corner of page 2 and in each of
    /// its margins, a few points from the page's edge, a touch reaches the page's canvas
    /// (nothing over the page takes it), and a stroke the canvas draws there is saved in the
    /// file where it was drawn. PencilKit draws nothing from a synthesized touch (it reads the
    /// touch's coalesced samples, which UIKit gives only to touches from the screen), so the
    /// stroke is given to the canvas at the touched point, in the canvas's own coordinates.
    func testInATiledWindowStrokesAtEveryCornerAndMarginOfAZoomedPageReachTheFile() async throws {
        let (workspace, session) = try await openPaper()
        for size in [Self.tiledWindowSizes[0], Self.tiledWindowSizes[1]] {
            let name = "\(Int(size.width)) by \(Int(size.height))"
            let window = try host(workspace, size: size)
            let pdfView = try await zoomedPDFView(of: session, in: window)
            let page = try XCTUnwrap(session.document.page(at: 1))
            let inkBefore = inkBounds(on: page)
            let pageBox = page.bounds(for: pdfView.displayBox)
            let edgeDistance: CGFloat = 6
            // Page space: the origin is the page's bottom-left corner.
            let targets: [(name: String, point: CGPoint, inward: CGVector)] = [
                ("top left corner", CGPoint(x: pageBox.minX + edgeDistance, y: pageBox.maxY - edgeDistance), CGVector(dx: 1, dy: -1)),
                ("top right corner", CGPoint(x: pageBox.maxX - edgeDistance, y: pageBox.maxY - edgeDistance), CGVector(dx: -1, dy: -1)),
                ("bottom left corner", CGPoint(x: pageBox.minX + edgeDistance, y: pageBox.minY + edgeDistance), CGVector(dx: 1, dy: 1)),
                ("bottom right corner", CGPoint(x: pageBox.maxX - edgeDistance, y: pageBox.minY + edgeDistance), CGVector(dx: -1, dy: 1)),
                ("left margin", CGPoint(x: pageBox.minX + edgeDistance, y: pageBox.midY), CGVector(dx: 1, dy: 0)),
                ("right margin", CGPoint(x: pageBox.maxX - edgeDistance, y: pageBox.midY), CGVector(dx: -1, dy: 0)),
                ("top margin", CGPoint(x: pageBox.midX, y: pageBox.maxY - edgeDistance), CGVector(dx: 0, dy: -1)),
                ("bottom margin", CGPoint(x: pageBox.midX, y: pageBox.minY + edgeDistance), CGVector(dx: 0, dy: 1)),
            ]
            for target in targets {
                try scroll(pdfView, toShow: target.point, on: page, in: window)
                try await Task.sleep(for: .milliseconds(250))
                let start = pdfView.convert(pdfView.convert(target.point, from: page), to: window)
                let touchedView = window.hitTest(start, with: nil)
                let canvas = try XCTUnwrap(touchedView.flatMap(enclosingCanvas),
                                           "\(name), \(target.name): the touch reaches the page's canvas, not \(String(describing: touchedView)).")
                XCTAssertTrue(canvas.page === page, "\(name), \(target.name): the canvas touched is page 2's.")
                // A short stroke inward from the edge, 40 screen points long.
                let length: CGFloat = 40
                let end = CGPoint(x: start.x + target.inward.dx * length, y: start.y - target.inward.dy * length)
                canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [stroke(from: canvas.drawingPoint(fromWindow: start, in: window),
                                                                                    to: canvas.drawingPoint(fromWindow: end, in: window))])
                try await Task.sleep(for: .milliseconds(150))
            }
            try await waitUntil { self.inkBounds(on: page).count >= inkBefore.count + targets.count }
            try scroll(pdfView, toShow: targets[1].point, on: page, in: window)
            try await Task.sleep(for: .milliseconds(600))
            attachScreenshot(of: window, named: "\(name), a stroke at the top right corner of page 2 at 250%")
            pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
            pdfView.go(to: page)
            try await Task.sleep(for: .milliseconds(800))
            attachScreenshot(of: window, named: "\(name), page 2 with a stroke at each corner and margin")
            pdfView.scaleFactor = Self.writingZoom
            try await session.save()
            let saved = try XCTUnwrap(PDFDocument(url: session.location)?.page(at: 1))
            let savedInk = inkBounds(on: saved)
            for target in targets {
                XCTAssertTrue(savedInk.contains { bounds in bounds.insetBy(dx: -4, dy: -4).contains(target.point) },
                              "\(name), \(target.name): the stroke drawn at \(target.point) is in the saved page. Ink: \(savedInk)")
            }
            close(window)
        }
    }

    // MARK: The health monitor

    /// Something that puts the page back after each drag (here a stand-in for the bug the
    /// owner filmed) is noticed: after three such drags, a record is written and the PDF's view
    /// is built again, as switching tabs does.
    func testDragsThatSomethingPutsBackAreRecordedAndThePDFIsBuiltAgain() async throws {
        let (workspace, session) = try await openPaper()
        let window = try host(workspace, size: nil)
        let pdfView = try await zoomedPDFView(of: session, in: window)
        let scrollView = try XCTUnwrap(scrollView(of: pdfView))
        let undoer = PositionUndoer(scrollView: scrollView)
        defer { undoer.stop() }
        let recordsBefore = stoppedRecords()
        let generationBefore = session.viewGeneration
        let touches = SynthesizedTouches(window: window)
        let middle = visibleMiddle(of: pdfView, in: window)
        for _ in 0..<3 {
            await touches.drag(from: CGPoint(x: middle.x, y: middle.y + 120), to: CGPoint(x: middle.x, y: middle.y - 120))
            try await Task.sleep(for: .milliseconds(1_300))
        }
        try await waitUntil { session.viewGeneration > generationBefore }
        DiagnosticRecords.waitForPendingWrites()
        let newRecords = stoppedRecords().subtracting(recordsBefore)
        XCTAssertFalse(newRecords.isEmpty, "A record of the gestures put back is kept.")
        if let record = newRecords.first, let text = try? String(contentsOf: record, encoding: .utf8) {
            XCTAssertTrue(text.contains("put them back"), text)
        }
    }

    /// Puts a scroll view back where each pan found it, a moment after the pan ends.
    @MainActor
    private final class PositionUndoer: NSObject {
        private weak var scrollView: UIScrollView?
        private var offsetAtBegin: CGPoint?

        init(scrollView: UIScrollView) {
            self.scrollView = scrollView
            super.init()
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        }

        func stop() {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
        }

        @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began: offsetAtBegin = scrollView?.contentOffset
            case .ended, .cancelled:
                guard let offsetAtBegin else { return }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    self?.scrollView?.setContentOffset(offsetAtBegin, animated: false)
                }
            default: break
            }
        }
    }

    // MARK: Checks

    private func checkPinchesAtTheCorners(of pdfView: PDFView, in window: UIWindow, name: String) async throws {
        let touches = SynthesizedTouches(window: window)
        let visible = visibleFrame(of: pdfView, in: window)
        let inset: CGFloat = 70
        let corners = [CGPoint(x: visible.minX + inset, y: visible.minY + inset), CGPoint(x: visible.maxX - inset, y: visible.minY + inset),
                       CGPoint(x: visible.minX + inset, y: visible.maxY - inset), CGPoint(x: visible.maxX - inset, y: visible.maxY - inset)]
        for (index, corner) in corners.enumerated() {
            // In at one corner, out at the next, so the zoom goes up and down across its range.
            let zoomsIn = index.isMultiple(of: 2)
            let narrow: CGFloat = 20, wide: CGFloat = 65
            let (startHalf, endHalf) = zoomsIn ? (narrow, wide) : (wide, narrow)
            let before = position(of: pdfView)
            await touches.pinch(firstFinger: (CGPoint(x: corner.x - startHalf, y: corner.y), CGPoint(x: corner.x - endHalf, y: corner.y)),
                                secondFinger: (CGPoint(x: corner.x + startHalf, y: corner.y), CGPoint(x: corner.x + endHalf, y: corner.y)))
            try await Task.sleep(for: .milliseconds(400))
            let after = position(of: pdfView)
            XCTAssertNotEqual(after.scale, before.scale, accuracy: 0.01, "\(name): the pinch at corner \(index + 1) zooms.")
            try await assertStaysStill(pdfView, seconds: 1, name: "\(name), after a pinch at corner \(index + 1)")
        }
        pdfView.autoScales = false
        pdfView.scaleFactor = Self.writingZoom
        try await Task.sleep(for: .milliseconds(300))
    }

    /// Drags toward each edge until the page goes no further, then checks the page's edge is
    /// on screen and stays there.
    private func checkEveryEdgeCanBeReached(of pdfView: PDFView, session: PDFSession, in window: UIWindow, name: String) async throws {
        let page = try XCTUnwrap(session.document.page(at: 1))
        let touches = SynthesizedTouches(window: window)
        let middle = visibleMiddle(of: pdfView, in: window)
        let visible = visibleFrame(of: pdfView, in: window)
        let reach = min(visible.width, visible.height) * 0.3
        // The finger moves the page the other way: dragging left brings its right edge in.
        let edges: [(name: String, drag: CGVector, isReached: (CGRect) -> Bool)] = [
            ("right", CGVector(dx: -reach, dy: 0), { page in page.maxX <= visible.maxX + 0.5 }),
            ("left", CGVector(dx: reach, dy: 0), { page in page.minX >= visible.minX - 0.5 }),
            ("bottom", CGVector(dx: 0, dy: -reach), { page in page.maxY <= visible.maxY + 0.5 }),
            ("top", CGVector(dx: 0, dy: reach), { page in page.minY >= visible.minY - 0.5 }),
        ]
        for edge in edges {
            var pageFrame = pdfView.convert(pdfView.convert(page.bounds(for: pdfView.displayBox), from: page), to: window)
            var drags = 0
            while !edge.isReached(pageFrame), drags < 20 {
                await touches.drag(from: CGPoint(x: middle.x - edge.drag.dx / 2, y: middle.y - edge.drag.dy / 2),
                                   to: CGPoint(x: middle.x + edge.drag.dx / 2, y: middle.y + edge.drag.dy / 2), steps: 12, holdSeconds: 0.15)
                try await Task.sleep(for: .milliseconds(150))
                pageFrame = pdfView.convert(pdfView.convert(page.bounds(for: pdfView.displayBox), from: page), to: window)
                drags += 1
            }
            XCTAssertTrue(edge.isReached(pageFrame), "\(name): the page's \(edge.name) edge comes on screen. Page \(pageFrame), visible \(visible), after \(drags) drags.")
            try await assertStaysStill(pdfView, seconds: 1, name: "\(name), at the page's \(edge.name) edge")
        }
        // At the ends of the document, the first page's top edge and the last page's bottom
        // edge come clear of the bars and of a palette docked along the bottom.
        let scrollView = try XCTUnwrap(scrollView(of: pdfView))
        let insets = scrollView.adjustedContentInset
        let firstPage = try XCTUnwrap(session.document.page(at: 0))
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -insets.top), animated: false)
        pdfView.layoutIfNeeded()
        let firstFrame = pdfView.convert(pdfView.convert(firstPage.bounds(for: pdfView.displayBox), from: firstPage), to: window)
        XCTAssertGreaterThanOrEqual(firstFrame.minY, visibleFrame(of: pdfView, in: window).minY - 0.5, "\(name): the first page's top edge comes on screen.")
        let lastPage = try XCTUnwrap(session.document.page(at: session.pageCount - 1))
        let maximumOffset = max(-insets.top, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: maximumOffset), animated: false)
        pdfView.layoutIfNeeded()
        let lastFrame = pdfView.convert(pdfView.convert(lastPage.bounds(for: pdfView.displayBox), from: lastPage), to: window)
        XCTAssertLessThanOrEqual(lastFrame.maxY, visibleFrame(of: pdfView, in: window).maxY + 0.5,
                                 "\(name): the last page's bottom edge comes clear of what is over the page. Page \(lastFrame), visible \(visibleFrame(of: pdfView, in: window)).")
        attachScreenshot(of: window, named: "\(name), end of the document")
    }

    /// Fails when the page's offset or zoom changes during the time given.
    private func assertStaysStill(_ pdfView: PDFView, seconds: Double, name: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        // A fling or a bounce under way ends first; the person's gesture is over then.
        if let scrollView = scrollView(of: pdfView) {
            let settleEnd = ContinuousClock.now + .seconds(2)
            while (scrollView.isDecelerating || scrollView.isZoomBouncing), ContinuousClock.now < settleEnd {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let start = position(of: pdfView)
        let end = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < end {
            try await Task.sleep(for: .milliseconds(20))
            let now = position(of: pdfView)
            // Half a point is the scroll view settling on a whole pixel, not a move.
            if distance(start, now) > 1 || abs(now.scale - start.scale) > 0.0001 {
                XCTFail("\(name): the page moved by itself from \(start) to \(now).", file: file, line: line)
                return
            }
        }
    }

    // MARK: Setup

    /// A six-page paper in two columns, with ink on page 2, in a vault with a note, opened in
    /// a new tab and written on, as the owner's paper was.
    private func openPaper() async throws -> (WorkspaceModel, PDFSession) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GestureWins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder
        try writePaper(to: folder.appendingPathComponent("Paper.pdf"))
        try Data("# Untitled\n\nNotes beside the paper.\n".utf8).write(to: folder.appendingPathComponent("Untitled.md"))
        let workspace = WorkspaceModel()
        // Read Aloud is a core plugin that is off by default; these tests read.
        workspace.setCorePluginEnabled(.readAloud, true)
        workspace.folderAccess = FolderAccess(root: folder)
        workspace.store = VaultStore(root: folder)
        workspace.index = try VaultIndex(databaseURL: folder.appendingPathComponent("index.sqlite"))
        savedReadingSpeed = workspace.activeReadAloud.session.speed
        workspace.activeReadAloud.session.setSpeed(1.5)
        self.workspace = workspace
        await workspace.open(try VaultPath("Untitled.md"))
        await workspace.open(try VaultPath("Paper.pdf"), placement: .newTab)
        let session = try XCTUnwrap(workspace.pdfSession)
        session.isWriting = true
        return (workspace, session)
    }

    private func writePaper(to location: URL) throws {
        let sentence = "Processing using memory performs bulk bitwise operations inside commodity chips by activating several rows at once. "
        let column = String(repeating: sentence, count: 14)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: location) { context in
            for pageNumber in 1...6 {
                context.beginPage()
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]
                ("Page \(pageNumber). " + column as NSString).draw(in: CGRect(x: 54, y: 54, width: 240, height: 684), withAttributes: attributes)
                (column as NSString).draw(in: CGRect(x: 318, y: 54, width: 240, height: 684), withAttributes: attributes)
            }
        }
    }

    /// Graphite's whole window (sidebar, toolbar, tabs, the Pencil bar and the Read Aloud
    /// player) in a window of the app's scene, at the scene's size or the size given.
    private func host(_ workspace: WorkspaceModel, size: CGSize?) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        let window = UIWindow(windowScene: scene)
        if let size {
            window.frame = CGRect(origin: .zero, size: size)
            controller.traitOverrides.horizontalSizeClass = size.width < 700 ? .compact : .regular
        } else {
            window.frame = scene.coordinateSpace.bounds
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        windows.append(window)
        return window
    }

    private func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        windows.removeAll { shown in shown === window }
    }

    /// The PDF's view once it shows in the window, at 250% with page 2 in the middle.
    private func zoomedPDFView(of session: PDFSession, in window: UIWindow) async throws -> GraphitePDFDisplayView {
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window && (session.pdfView?.bounds.width ?? 0) > 100 }
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        try await Task.sleep(for: .milliseconds(1_000))
        pdfView.autoScales = false
        pdfView.scaleFactor = Self.writingZoom
        let page = try XCTUnwrap(session.document.page(at: 1))
        let pageBox = page.bounds(for: pdfView.displayBox)
        try scroll(pdfView, toShow: CGPoint(x: pageBox.midX, y: pageBox.midY), on: page, in: window)
        try await Task.sleep(for: .milliseconds(500))
        return pdfView
    }

    /// Scrolls so the page point is in the middle of the part of the PDF on screen, or as near
    /// as the page's edges allow.
    private func scroll(_ pdfView: PDFView, toShow point: CGPoint, on page: PDFPage, in window: UIWindow) throws {
        let scrollView = try XCTUnwrap(scrollView(of: pdfView))
        let visible = visibleFrame(of: pdfView, in: window)
        let pointInWindow = pdfView.convert(pdfView.convert(point, from: page), to: window)
        let insets = scrollView.adjustedContentInset
        var offset = scrollView.contentOffset
        offset.x += pointInWindow.x - visible.midX
        offset.y += pointInWindow.y - visible.midY
        offset.x = min(max(offset.x, -insets.left), max(-insets.left, scrollView.contentSize.width - scrollView.bounds.width + insets.right))
        offset.y = min(max(offset.y, -insets.top), max(-insets.top, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom))
        scrollView.setContentOffset(offset, animated: false)
        pdfView.layoutIfNeeded()
    }

    // MARK: Reading the view

    private func scrollView(of pdfView: PDFView) -> UIScrollView? {
        var ancestor = pdfView.documentView?.superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView { return scrollView }
            ancestor = view.superview
        }
        return nil
    }

    private func position(of pdfView: PDFView) -> UnansweredGestureCount.PagePosition {
        UnansweredGestureCount.PagePosition(offset: scrollView(of: pdfView)?.contentOffset ?? .zero, scale: pdfView.scaleFactor)
    }

    private func distance(_ first: UnansweredGestureCount.PagePosition, _ second: UnansweredGestureCount.PagePosition) -> CGFloat {
        hypot(first.offset.x - second.offset.x, first.offset.y - second.offset.y)
    }

    /// The part of the PDF on screen, in the window: inside the window, inside the scroll
    /// view's insets, and above the Pencil palette when it is docked along the bottom.
    private func visibleFrame(of pdfView: PDFView, in window: UIWindow) -> CGRect {
        var frame = pdfView.convert(pdfView.bounds, to: window).intersection(window.bounds)
        if let scrollView = scrollView(of: pdfView) {
            frame = frame.inset(by: scrollView.adjustedContentInset)
        }
        if let coordinator = (pdfView as? GraphitePDFDisplayView)?.annotationCoordinator, coordinator.toolPicker.isVisible {
            let palette = pdfView.convert(coordinator.toolPicker.frameObscured(in: pdfView), to: window)
            if !palette.isNull, !palette.isEmpty, palette.maxY >= frame.maxY - 1, palette.width >= frame.width * 0.8 {
                frame.size.height = max(0, palette.minY - frame.minY)
            }
        }
        return frame
    }

    private func visibleMiddle(of pdfView: PDFView, in window: UIWindow) -> CGPoint {
        let frame = visibleFrame(of: pdfView, in: window)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func highlightedText(in pdfView: PDFView) -> String {
        (pdfView.highlightedSelections ?? []).compactMap(\.string).joined(separator: " ")
    }

    private func highlightIsOnScreen(in pdfView: PDFView) -> Bool {
        guard let selection = pdfView.highlightedSelections?.first, let page = selection.pages.first else { return false }
        return pdfView.bounds.intersects(pdfView.convert(selection.bounds(for: page), from: page))
    }

    private var strokeCount = 0

    private func stroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        strokeCount += 1
        let points = (0...10).map { pointIndex in
            let fraction = CGFloat(pointIndex) / 10
            return PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction),
                                 timeOffset: Double(pointIndex) / 30, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .systemRed),
                        path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(strokeCount))))
    }

    private func inkBounds(on page: PDFPage) -> [CGRect] {
        page.annotations.filter { annotation in annotation.type == "Ink" }.map(\.bounds)
    }

    private func enclosingCanvas(_ view: UIView) -> PDFPageCanvasView? {
        var current: UIView? = view
        while let shown = current {
            if let canvas = shown as? PDFPageCanvasView { return canvas }
            current = shown.superview
        }
        return nil
    }

    private func stoppedRecords() -> Set<URL> {
        guard let folder = DiagnosticRecords.folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return Set(files.filter { file in file.lastPathComponent.hasPrefix("PDFStoppedTakingTouches-") })
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

}
private extension PDFPageCanvasView {
    /// A point of the window in the canvas's drawing, which is in the page's points from its
    /// top-left corner: the canvas is zoomed by its rendering scale.
    func drawingPoint(fromWindow point: CGPoint, in window: UIWindow) -> CGPoint {
        let pointInCanvas = convert(point, from: window)
        return CGPoint(x: pointInCanvas.x / zoomScale, y: pointInCanvas.y / zoomScale)
    }
}
#endif

private extension WorkspaceModel {
    /// The reader of a workspace whose Read Aloud plugin these tests turned on.
    var activeReadAloud: ReadAloudController {
        guard let readAloud else { preconditionFailure("The Read Aloud core plugin was turned on when the workspace was made.") }
        return readAloud
    }

    var activeReadAloudNavigator: ReadAloudNavigator {
        guard let readAloudNavigator else { preconditionFailure("The Read Aloud core plugin was turned on when the workspace was made.") }
        return readAloudNavigator
    }
}
