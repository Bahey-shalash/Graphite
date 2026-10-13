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
        try await waitUntil { !canvas.isUserInteractionEnabled }
        XCTAssertFalse(canvas.isHidden, "Reading shows the ink as it was drawn, from the canvas.")
        XCTAssertFalse(ink.shouldDisplay, "The canvas shows the ink, so its PDF appearance is not drawn under it as well.")
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

    /// Turning writing on or off changes nothing on the page: highlighter, pen and pencil
    /// ink look the same while reading as while writing, at the page's size and zoomed in.
    func testInkLooksTheSameWhileReadingAndWhileWriting() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("InkToggle-\(UUID().uuidString).pdf")
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

        func stroke(_ inkType: PKInk.InkType, color: UIColor, width: CGFloat, atY lineY: CGFloat) -> PKStroke {
            let points = (0...24).map { pointIndex in
                PKStrokePoint(location: CGPoint(x: 60 + CGFloat(pointIndex) * 12, y: lineY + 6 * sin(CGFloat(pointIndex) * 0.5)),
                              timeOffset: Double(pointIndex) / 60, size: CGSize(width: width, height: width), opacity: inkType == .marker ? 1.4 : 1,
                              force: 0.4 + 0.05 * CGFloat(pointIndex % 8), azimuth: .pi / 2, altitude: .pi / 3)
            }
            return PKStroke(ink: PKInk(inkType, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        canvas.drawing = PKDrawing(strokes: [
            stroke(.marker, color: UIColor(red: 1, green: 0.62, blue: 0.79, alpha: 1), width: 18, atY: 120),
            stroke(.pen, color: .systemRed, width: 3, atY: 128),
            stroke(.pencil, color: .darkGray, width: 4, atY: 170),
        ])
        try await waitUntil { page.annotations.filter { $0.type == "Ink" }.count == 3 }
        try await Task.sleep(for: .milliseconds(500))

        // In the page's points, top down, as the overlay over the page and its canvas count them.
        let inkArea = CGRect(x: 40, y: 90, width: 340, height: 110)
        let overlayView = try XCTUnwrap(canvas.overlayView)
        func pixels() throws -> [UInt8] {
            let area = overlayView.convert(inkArea, to: nil)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(bounds: area, format: format).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let cgImage = try XCTUnwrap(image.cgImage)
            var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
            let context = try XCTUnwrap(CGContext(data: &bytes, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            return bytes
        }
        func differingFraction(_ first: [UInt8], _ second: [UInt8]) -> Double {
            var inked = 0, differing = 0
            for index in stride(from: 0, to: min(first.count, second.count), by: 4) {
                let isInked = first[index] < 240 || first[index + 1] < 240 || first[index + 2] < 240 || second[index] < 240 || second[index + 1] < 240 || second[index + 2] < 240
                guard isInked else { continue }
                inked += 1
                if (0..<3).contains(where: { channel in abs(Int(first[index + channel]) - Int(second[index + channel])) > 24 }) { differing += 1 }
            }
            return inked == 0 ? 1 : Double(differing) / Double(inked)
        }

        for zoom in [pdfView.scaleFactor, pdfView.scaleFactor * 3] {
            pdfView.scaleFactor = zoom
            pdfView.go(to: pdfView.convert(overlayView.convert(inkArea, to: pdfView), to: page), on: page)
            try await Task.sleep(for: .milliseconds(800))
            let whileWriting = try pixels()
            session.isWriting = false
            try await waitUntil { !canvas.isUserInteractionEnabled }
            try await Task.sleep(for: .milliseconds(500))
            let whileReading = try pixels()
            let fraction = differingFraction(whileWriting, whileReading)
            XCTAssertLessThan(fraction, 0.01, "At \(Int(zoom * 100)) percent, \(Int(fraction * 100)) percent of the inked pixels change when writing is turned off.")
            session.isWriting = true
            try await waitUntil { canvas.isUserInteractionEnabled }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertLessThan(differingFraction(whileWriting, try pixels()), 0.01, "And nothing changes when it is turned on again.")
        }
        attachScreenshot(of: window, named: "Ink while writing, zoomed")
    }

    /// The window sizes an iPad gives Graphite: the screen, halves and thirds of it in either
    /// orientation, and freely sized windows. Each is checked at the size class iPadOS gives
    /// it; where that depends on the screen and the window's arrangement, at both.
    static let windowSizes: [(size: CGSize, sizeClasses: [UIUserInterfaceSizeClass])] = [
        (CGSize(width: 375, height: 834), [.compact]),
        (CGSize(width: 507, height: 834), [.compact, .regular]),
        (CGSize(width: 590, height: 834), [.compact, .regular]),
        (CGSize(width: 694, height: 834), [.compact, .regular]),
        (CGSize(width: 820, height: 1180), [.regular]),
        (CGSize(width: 1194, height: 834), [.regular]),
    ]

    /// A workspace showing a PDF being written on, with a note in another tab, in a vault of
    /// its own.
    private func pdfWorkspace(in directory: URL) async throws -> (WorkspaceModel, PDFSession) {
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .ruled), pageCount: 4).write(to: directory.appendingPathComponent("Paper.pdf"))
        try Data("# Untitled\n".utf8).write(to: directory.appendingPathComponent("Untitled.md"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        workspace.index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        await workspace.open(try VaultPath("Untitled.md"))
        await workspace.open(try VaultPath("Paper.pdf"), placement: .newTab)
        let session = try XCTUnwrap(workspace.pdfSession)
        session.isWriting = true
        return (workspace, session)
    }

    /// The page's edges in its view, and the view's width.
    private func pageEdges(of session: PDFSession) throws -> (page: CGRect, viewWidth: CGFloat) {
        let pdfView = try XCTUnwrap(session.pdfView)
        let page = try XCTUnwrap(pdfView.currentPage ?? session.document.page(at: 0))
        return (pdfView.convert(page.bounds(for: .cropBox), from: page), pdfView.bounds.width)
    }

    /// The bars' buttons and title UIKit shows (the navigation bar's and the bottom bar's),
    /// each with its kind and frame in the window, and whether one of them shows the More
    /// menu's ellipsis. UIKit's bar buttons carry no label of their own a test can read.
    private func barControls(in window: UIWindow) -> (controls: [(kind: String, frame: CGRect)], showsMore: Bool) {
        var controls: [(String, CGRect)] = []
        var showsMore = false
        func visit(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            let kind = String(describing: type(of: view))
            if kind.contains("ButtonBarButton") || kind.contains("TitleControl") {
                controls.append((kind, view.convert(view.bounds, to: window)))
            }
            if let imageView = view as? UIImageView, imageView.image?.description.contains("ellipsis") == true { showsMore = true }
            view.subviews.forEach(visit)
        }
        (descendants(of: window, matching: UINavigationBar.self) + descendants(of: window, matching: UIToolbar.self)).forEach(visit)
        return (controls, showsMore)
    }

    /// A PDF being written on, in the whole workspace (sidebar, toolbar, tabs and the fixed
    /// Pencil bar), in a window of every size: the page fits the window's width, the Pencil
    /// bar is whole or compact, never cut off, and every bar control is inside the window.
    func testThePDFWorkspaceFitsEveryWindowSize() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WindowSizes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let savedStyle = UserDefaults.standard.object(forKey: PencilToolbarStyle.preferenceKey)
        UserDefaults.standard.set(PencilToolbarStyle.fixed.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        defer {
            if let savedStyle { UserDefaults.standard.set(savedStyle, forKey: PencilToolbarStyle.preferenceKey) }
            else { UserDefaults.standard.removeObject(forKey: PencilToolbarStyle.preferenceKey) }
        }
        let (workspace, session) = try await pdfWorkspace(in: directory)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for (size, sizeClasses) in Self.windowSizes {
            for sizeClass in sizeClasses {
                let name = "\(Int(size.width))x\(Int(size.height)) \(sizeClass == .compact ? "compact" : "regular")"
                let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
                controller.traitOverrides.horizontalSizeClass = sizeClass
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(origin: .zero, size: size)
                window.rootViewController = controller
                PencilToolRowForm.lastShown = nil
                window.makeKeyAndVisible()
                try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
                try await Task.sleep(for: .milliseconds(1500))
                attachScreenshot(of: window, named: name)

                let (page, viewWidth) = try pageEdges(of: session)
                XCTAssertGreaterThanOrEqual(page.minX, -1, "\(name): the page starts inside its view.")
                XCTAssertLessThanOrEqual(page.maxX, viewWidth + 1, "\(name): the page ends inside its view.")
                XCTAssertLessThanOrEqual(viewWidth - page.width, 40, "\(name): the page fits the width, with no empty column.")
                let pdfFrame = try XCTUnwrap(session.pdfView).convert(try XCTUnwrap(session.pdfView).bounds, to: window)
                XCTAssertGreaterThanOrEqual(pdfFrame.minX, -1, "\(name): the PDF is inside the window.")
                XCTAssertLessThanOrEqual(pdfFrame.maxX, size.width + 1, "\(name): the PDF is inside the window.")

                if sizeClass == .regular {
                    let shownRow = try XCTUnwrap(PencilToolRowForm.lastShown, "\(name): the fixed Pencil bar shows.")
                    XCTAssertNotEqual(shownRow.form, .scrolling, "\(name): the Pencil bar is whole or compact, not cut off.")
                    XCTAssertGreaterThanOrEqual(shownRow.frameInWindow.minX, -0.5, "\(name): the Pencil bar starts inside the window.")
                    XCTAssertLessThanOrEqual(shownRow.frameInWindow.maxX, size.width + 0.5, "\(name): the Pencil bar ends inside the window.")
                }
                let (controls, showsMore) = barControls(in: window)
                XCTAssertFalse(controls.isEmpty)
                for control in controls {
                    XCTAssertGreaterThanOrEqual(control.frame.minX, -0.5, "\(name): a \(control.kind) is inside the window.")
                    XCTAssertLessThanOrEqual(control.frame.maxX, size.width + 0.5, "\(name): a \(control.kind) is inside the window.")
                    XCTAssertGreaterThan(control.frame.width, 1, "\(name): a \(control.kind) is not squeezed away.")
                }
                let titles = controls.filter { control in control.kind.contains("TitleControl") }
                for title in titles {
                    XCTAssertGreaterThanOrEqual(title.frame.width, 60, "\(name): the title stays readable.")
                    XCTAssertFalse(controls.contains { control in control.kind.contains("ButtonBarButton") && control.frame.intersects(title.frame.insetBy(dx: 1, dy: 1)) },
                                   "\(name): no button covers the title.")
                }
                XCTAssertTrue(showsMore, "\(name): the More menu, which holds what the bar has no room for, shows.")
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }

    /// A PDF fitted to its window's width, or zoomed past that, keeps fitting, or keeps its
    /// zoom past fitting, when the window changes size, though a pinch has turned PDFKit's own
    /// fitting off; the page never runs off one edge with an empty column at the other.
    func testThePDFRefitsWhenTheWindowChangesSize() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WindowResize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (workspace, session) = try await pdfWorkspace(in: directory)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let controller = UIHostingController(rootView: GraphiteRootView(workspace: workspace))
        controller.traitOverrides.horizontalSizeClass = .regular
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1194, height: 834)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.window === window }
        try await Task.sleep(for: .milliseconds(1000))
        let pdfView = try XCTUnwrap(session.pdfView)

        // Pinched back to fitting: PDFKit no longer fits the page itself.
        pdfView.autoScales = false
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        for width in [590.0, 820.0, 375.0, 1194.0] as [CGFloat] {
            window.frame = CGRect(x: 0, y: 0, width: width, height: 834)
            try await Task.sleep(for: .milliseconds(900))
            let (page, viewWidth) = try pageEdges(of: session)
            XCTAssertLessThanOrEqual(abs(viewWidth - page.width), 40, "At \(Int(width)) points the page fits the width again.")
            XCTAssertGreaterThanOrEqual(page.minX, -1)
            XCTAssertLessThanOrEqual(page.maxX, viewWidth + 1)
        }
        attachScreenshot(of: window, named: "Resized, fitting")

        // Zoomed in to write: the zoom past fitting stays, and no column is left empty.
        pdfView.autoScales = false
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit * 1.5
        let zoomPastFitting = pdfView.scaleFactor / pdfView.scaleFactorForSizeToFit
        for width in [590.0, 820.0] as [CGFloat] {
            window.frame = CGRect(x: 0, y: 0, width: width, height: 834)
            try await Task.sleep(for: .milliseconds(900))
            XCTAssertEqual(pdfView.scaleFactor / pdfView.scaleFactorForSizeToFit, zoomPastFitting, accuracy: 0.05, "At \(Int(width)) points the zoom past fitting stays.")
            let (page, viewWidth) = try pageEdges(of: session)
            // PDFKit keeps a margin around a page, scaled with it: about 6 points at this zoom.
            XCTAssertLessThanOrEqual(page.minX, 12, "At \(Int(width)) points no empty column is left of the page.")
            XCTAssertGreaterThanOrEqual(page.maxX, viewWidth - 12, "At \(Int(width)) points no empty column is right of the page.")
        }
        attachScreenshot(of: window, named: "Resized, zoomed")
    }

    /// Zoomed in to write on a page, the canvas draws its ink at the zoom it is seen at, not
    /// at the page's size magnified, while its drawing, its place over the page and the width
    /// of a stroke on the page stay what they are at the page's own size.
    func testPageInkIsDrawnAtTheZoomItIsSeenAtAndStaysInPagePoints() async throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("ZoomedInk-\(UUID().uuidString).pdf")
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
        let pageSize = page.bounds(for: .cropBox).size
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)

        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 0.8), 1, "Never below the page's own size")
        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 1.2), 1.5, "In steps, never below the zoom")
        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 2.5), 2.5)
        XCTAssertEqual(PDFPageOverlayView.renderingScale(forZoom: 8), PDFPageOverlayView.maximumRenderingScale)

        pdfView.autoScales = false
        pdfView.scaleFactor = 2.2
        let expectedScale = PDFPageOverlayView.renderingScale(forZoom: 2.2)
        try await waitUntil { canvas.zoomScale == expectedScale }
        XCTAssertEqual(canvas.overlayView?.renderingScale, expectedScale)
        XCTAssertEqual(canvas.drawingSize.width, pageSize.width, accuracy: 0.5, "The drawing stays in the page's points")
        XCTAssertEqual(canvas.drawingSize.height, pageSize.height, accuracy: 0.5)

        // A point of the drawing is over the same point of the page on screen.
        let drawingPoint = CGPoint(x: 120, y: 90)
        let pointOverCanvas = canvas.convert(CGPoint(x: drawingPoint.x * canvas.zoomScale, y: drawingPoint.y * canvas.zoomScale), to: pdfView)
        let pagePoint = CGPoint(x: page.bounds(for: .cropBox).minX + drawingPoint.x, y: page.bounds(for: .cropBox).maxY - drawingPoint.y)
        let pointOverPage = pdfView.convert(pagePoint, from: page)
        XCTAssertEqual(pointOverCanvas.x, pointOverPage.x, accuracy: 1)
        XCTAssertEqual(pointOverCanvas.y, pointOverPage.y, accuracy: 1)

        // PencilKit keeps a tool as wide on screen at any zoom of its canvas: the canvas draws
        // with the chosen width times its zoom, so the stroke is as wide on the page.
        let chosenPen = PKInkingTool(.pen, color: .black, width: 3)
        let drawingPen = try XCTUnwrap(canvas.toolForDrawing(chosenPen) as? PKInkingTool)
        XCTAssertEqual(drawingPen.width, 3 * canvas.zoomScale, accuracy: 0.01)
        // PencilKit gives a pixel eraser a width of at least 16.4 when it is made.
        let chosenEraser = PKEraserTool(.bitmap, width: 20)
        let drawingEraser = try XCTUnwrap(canvas.toolForDrawing(chosenEraser) as? PKEraserTool)
        XCTAssertEqual(drawingEraser.width, chosenEraser.width * canvas.zoomScale, accuracy: 0.01)

        // Ink drawn at this zoom is stored where it is on the page.
        let strokePoints = (0...10).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: 50 + pointIndex * 10, y: 100), timeOffset: Double(pointIndex) / 10,
                          size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: strokePoints, creationDate: Date()))])
        try await waitUntil { page.annotations.contains { $0.type == "Ink" } }
        let ink = try XCTUnwrap(page.annotations.first { $0.type == "Ink" })
        let cropBox = page.bounds(for: .cropBox)
        XCTAssertEqual(ink.bounds.midX, cropBox.minX + 100, accuracy: 6)
        XCTAssertEqual(ink.bounds.midY, cropBox.maxY - 100, accuracy: 6)
        try await Task.sleep(for: .milliseconds(350))
        attachScreenshot(of: window, named: "PDF ink drawn at a zoom of 2.2")

        // Back at the page's size, the canvas draws at it again.
        pdfView.scaleFactor = 1
        try await waitUntil { canvas.zoomScale == 1 }
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
        XCTAssertEqual(canvas.drawingSize.width, pageSize.width, accuracy: 0.5)
    }

    /// Apple's palette is drawn above every screen of the app. Over a PDF being written on, a
    /// sheet hides it and the PDF keeps first responder, for its history; a text field in a
    /// sheet keeps the first responder it takes, even when the PDF's view is updated under it.
    /// When the sheet goes, the palette comes back with the tool chosen before, for the PDF.
    func testPaletteGivesWayToASheetOverThePDFAndComesBackWithTheSameTool() async throws {
        let defaults = UserDefaults.standard
        let preferenceKeys = [PencilToolbarStyle.preferenceKey, PDFAnnotationPreferenceKey.showsToolPicker, PDFAnnotationPreferenceKey.drawsShapes]
        let preferencesBefore = preferenceKeys.map { key in defaults.object(forKey: key) }
        defer {
            for (key, preference) in zip(preferenceKeys, preferencesBefore) {
                if let preference { defaults.set(preference, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(PencilToolbarStyle.floating.rawValue, forKey: PencilToolbarStyle.preferenceKey)
        defaults.set(true, forKey: PDFAnnotationPreferenceKey.showsToolPicker)
        defaults.set(false, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("PaletteUnderSheet-\(UUID().uuidString).pdf")
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
        let pdfView = try XCTUnwrap(session.pdfView as? GraphitePDFDisplayView)
        let toolPicker = try XCTUnwrap(pdfView.annotationCoordinator?.toolPicker)
        // The test must not change the tools the simulator's app remembers.
        toolPicker.stateAutosaveName = nil
        let toolPickerHost = try XCTUnwrap(descendants(of: pdfView, matching: PencilToolPickerHostView.self).first)
        try await waitUntil { toolPicker.isVisible && toolPickerHost.isFirstResponder }
        let marker = try XCTUnwrap(toolPicker.toolItems.first { item in (item as? PKToolPickerInkingItem)?.inkingTool.inkType == .marker })
        toolPicker.selectedToolItemIdentifier = marker.identifier

        let sheet = UIViewController()
        sheet.modalPresentationStyle = .formSheet
        controller.present(sheet, animated: false)
        try await waitUntil { !toolPicker.isVisible }
        XCTAssertNotNil(pdfView.window, "The PDF stays in the window under the sheet.")
        XCTAssertTrue(toolPickerHost.isFirstResponder, "Only the palette gives way; the PDF keeps first responder.")
        sheet.dismiss(animated: false)
        try await waitUntil { controller.presentedViewController == nil && toolPicker.isVisible }
        XCTAssertEqual(toolPicker.selectedToolItemIdentifier, marker.identifier, "The palette comes back with the tool chosen before.")
        XCTAssertTrue(toolPickerHost.isFirstResponder)

        let sheetWithTextField = UIViewController()
        sheetWithTextField.modalPresentationStyle = .formSheet
        let nameField = UITextField(frame: CGRect(x: 20, y: 20, width: 240, height: 44))
        sheetWithTextField.view.addSubview(nameField)
        controller.present(sheetWithTextField, animated: false)
        try await waitUntil { nameField.window != nil && !toolPicker.isVisible }
        XCTAssertTrue(nameField.becomeFirstResponder())
        // An update of the PDF's view under the sheet, here from a preference the pane reads,
        // asks the PDF to hold first responder again.
        defaults.set(true, forKey: PDFAnnotationPreferenceKey.drawsShapes)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(nameField.isFirstResponder, "The sheet's text field keeps first responder.")
        XCTAssertFalse(toolPicker.isVisible)
        sheetWithTextField.dismiss(animated: false)
        try await waitUntil { controller.presentedViewController == nil && toolPickerHost.isFirstResponder && toolPicker.isVisible }
        XCTAssertEqual(toolPicker.selectedToolItemIdentifier, marker.identifier)
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
