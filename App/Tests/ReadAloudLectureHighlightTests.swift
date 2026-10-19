#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import AVFoundation
import GraphiteApple
import GraphiteCore
import GraphiteIndex
import GraphiteVoices
@testable import GraphiteUI

/// Reads a lecture-style note (properties, headings, math, an embed, a long body) with the
/// app's own reader and the simulator's real voice, in Live Preview, the reading view and a
/// PDF, and checks that a highlight appears on screen, moves on with the voice, and that
/// scrolling by hand while it reads stays smooth and is not pulled back.
@MainActor
final class ReadAloudLectureHighlightTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?
    private var workspace: WorkspaceModel?
    private var savedSpeed = 1.0

    override func tearDown() async throws {
        workspace?.readAloud.clear()
        workspace?.readAloud.session.setSpeed(savedSpeed)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        workspace = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
    }

    private static let lecture: String = {
        // Real notes are full of apostrophes, quotes, dashes and acronyms, which the voice's
        // text and the rendered text write differently; every paragraph here has them.
        let paragraph = "The gate's output stays at a full \"logic\" level -- while the CMOS inputs are stable, and the noise margin tells how much SRAM disturbance it tolerates. "
        var note = "---\ntitle: Static Logic\ntags:\n  - CMOS\n---\n# Static logic\n\n![[missing-figure.png]]\n\n## Noise margins\n\n"
        note += "The high margin is $N_{MH} = V_{OH} - V_{IH}$ for every gate. " + paragraph + "\n\n"
        for section in 1...12 {
            note += "## Section \(section)\n\n" + String(repeating: paragraph, count: 3) + "\n\n"
        }
        return note
    }()

    func testHighlightAppearsAndMovesOnInLivePreview() async throws {
        let (workspace, session) = try await openLecture(viewMode: .livePreview)
        let controller = try host(workspace)
        let editor = try await visibleEditor(in: controller)
        workspace.readAloud.readMarkdown(session.text, path: session.path)
        try await waitUntil(timeoutSeconds: 20) { !editor.readAloudHighlights.isEmpty }
        let firstFrames = editor.readAloudHighlights.map(\.frame)
        try await waitUntil(timeoutSeconds: 20) { !editor.readAloudHighlights.isEmpty && editor.readAloudHighlights.map(\.frame) != firstFrames }
        attachScreenshot(named: "Live Preview highlight")
        workspace.readAloud.clear()
        try await waitUntil { editor.readAloudHighlights.isEmpty }
    }

    func testHighlightAppearsAndMovesOnInTheReadingView() async throws {
        let (workspace, session) = try await openLecture(viewMode: .reading)
        _ = try host(workspace)
        try await Task.sleep(for: .milliseconds(800))
        // Tags and other light-blue chrome are on screen before reading; only new blue counts.
        let before = bluePixels()
        workspace.readAloud.readMarkdown(session.text, path: session.path)
        func highlight() -> CGRect? { highlightBounds(excluding: before) }
        try await waitUntil(timeoutSeconds: 20) { highlight() != nil }
        let first = try XCTUnwrap(highlight())
        try await waitUntil(timeoutSeconds: 20) { highlight().map { bounds in bounds != first } ?? false }
        attachScreenshot(named: "Reading view highlight")
        workspace.readAloud.clear()
        try await waitUntil { self.highlightBounds(excluding: before) == nil }
    }

    func testHighlightAppearsAndMovesOnInAPDF() async throws {
        let directory = try makeVault(notes: [:])
        let pdfLocation = directory.appendingPathComponent("Lecture.pdf")
        let pages = ["Static CMOS logic keeps its output at a full level. The noise margin tells how much disturbance it tolerates.",
                     "Dynamic logic stores its value as charge on a node, which leaks away over time."]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: pdfLocation) { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 60, y: 80, width: 480, height: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
            }
        }
        let workspace = try await makeWorkspace(directory: directory)
        await workspace.open(try VaultPath("Lecture.pdf"))
        let pdf = try XCTUnwrap(workspace.pdfSession)
        _ = try host(workspace)
        try await waitUntil { pdf.pdfView != nil }
        let pdfView = try XCTUnwrap(pdf.pdfView)
        workspace.readAloud.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        func highlighted() -> String? { pdfView.highlightedSelections?.compactMap(\.string).joined(separator: " ") }
        // Word by word, and the respelled acronym ("see moss") lit where "CMOS" is written.
        var seen = Set<String>()
        try await waitUntil(timeoutSeconds: 25) {
            if let word = highlighted(), !word.isEmpty { seen.insert(word) }
            return seen.contains("CMOS") && seen.count >= 3
        }
        attachScreenshot(named: "PDF highlight")
        // Word by word on the next page too.
        let secondPage = try XCTUnwrap(pdf.document.page(at: 1))
        try await waitUntil(timeoutSeconds: 30) { (pdfView.highlightedSelections ?? []).contains { selection in selection.pages.contains(secondPage) } }
        attachScreenshot(named: "PDF highlight on the second page")
        workspace.readAloud.clear()
        try await waitUntil { (pdfView.highlightedSelections ?? []).isEmpty }
    }

    /// A person scrolls fast through the note while it is read: following pauses, the view
    /// stays where the person put it, and no frame of the scroll waits more than 100 ms.
    func testScrollingByHandWhileReadingStaysSmoothAndIsNotPulledBack() async throws {
        let (workspace, session) = try await openLecture(viewMode: .livePreview)
        let controller = try host(workspace)
        let editor = try await visibleEditor(in: controller)
        workspace.readAloud.readMarkdown(session.text, path: session.path)
        try await waitUntil(timeoutSeconds: 20) { !editor.readAloudHighlights.isEmpty }
        // What a finger does first: the editor's own drag callback pauses following.
        editor.delegate?.scrollViewWillBeginDragging?(editor)
        try await waitUntil { !workspace.readAloud.followsReading }
        let measurement = FrameGapMeasurement(scrollView: editor, step: 45, duration: 3)
        let longestGap = await measurement.run()
        XCTAssertLessThan(longestGap, 0.1, "Longest frame gap while scrolling and reading: \(Int(longestGap * 1_000)) ms.")
        let offsetAfterScroll = editor.contentOffset.y
        try await Task.sleep(for: .milliseconds(1_500))
        XCTAssertEqual(editor.contentOffset.y, offsetAfterScroll, accuracy: 1, "Following must not pull the page back while paused.")
        XCTAssertEqual(workspace.readAloud.session.state, .speaking)
    }

    // MARK: Player and navigation

    /// The player's section skip, a jump by tap, and "Read from Here" after scrolling away all
    /// move reading where asked, with the real voice in Live Preview.
    func testSectionSkipTapAndReadFromHereMoveReading() async throws {
        let (workspace, session) = try await openLecture(viewMode: .livePreview)
        let controller = try host(workspace)
        let editor = try await visibleEditor(in: controller)
        let reader = workspace.readAloud
        let navigator = workspace.readAloudNavigator
        reader.readMarkdown(session.text, path: session.path)
        try await waitUntil(timeoutSeconds: 20) { reader.session.state == .speaking }
        // Section skip: to the next heading.
        navigator.skipSection(forward: true)
        XCTAssertEqual(reader.session.currentPassage?.kind, .heading)
        let afterSkip = reader.session.passageIndex
        navigator.skipSection(forward: true)
        XCTAssertGreaterThan(reader.session.passageIndex, afterSkip)
        XCTAssertEqual(navigator.sections.first { $0.passageIndex == navigator.currentSectionIndex }?.title.hasPrefix("Section"), true)
        // A tap on "Section 7" moves reading there.
        let target = (session.text as NSString).range(of: "## Section 7").location
        _ = navigator.tapped(atSourceLocation: target + 4)
        XCTAssertEqual(reader.session.currentPassage?.text, "Section 7")
        // Scrolling away pauses following; "Read from Here" reads from the top of the screen.
        editor.delegate?.scrollViewWillBeginDragging?(editor)
        try await waitUntil { !reader.followsReading }
        editor.setContentOffset(CGPoint(x: 0, y: max(0, editor.contentSize.height - editor.bounds.height)), animated: false)
        editor.layoutIfNeeded()
        let visible = try XCTUnwrap(navigator.visibleLocation?())
        navigator.readFromVisiblePosition()
        XCTAssertTrue(reader.followsReading)
        let readingAt = try XCTUnwrap(reader.session.currentPassage?.spans.map(\.sourceRange.location).min())
        XCTAssertGreaterThanOrEqual(readingAt + 400, visible, "Reading moved to what is on screen.")
        XCTAssertLessThanOrEqual(readingAt, visible + 600)
        XCTAssertGreaterThan(visible, 0)
    }

    /// The floating player keeps clear of the highlighted line, in portrait at the largest text.
    func testFloatingPlayerNeverCoversTheHighlightedLine() async throws {
        let (workspace, session) = try await openLecture(viewMode: .livePreview)
        let rootView = AnyView(ZStack {
            NavigationStack {
                WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
            }
            ReadAloudFloatingPlayer(reader: workspace.readAloud, navigator: workspace.readAloudNavigator)
        })
        let controller = UIHostingController(rootView: rootView)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        let editor = try await visibleEditor(in: controller)
        workspace.readAloud.readMarkdown(session.text, path: session.path)
        try await waitUntil(timeoutSeconds: 20) { !editor.readAloudHighlights.isEmpty }
        // Put the word being read at the bottom of the screen, under where the player sits.
        workspace.readAloud.followsReading = false
        if let word = editor.readAloudHighlights.first?.frame {
            editor.setContentOffset(CGPoint(x: 0, y: max(0, word.maxY - editor.bounds.height + 40)), animated: false)
        }
        var checks = 0
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(150))
            guard let player = workspace.readAloudNavigator.playerFrameInWindow,
                  let highlight = workspace.readAloudNavigator.highlightFrameInWindow, !player.isEmpty else { continue }
            checks += 1
            XCTAssertFalse(player.intersects(highlight), "Player \(player) covers the highlight \(highlight).")
        }
        XCTAssertGreaterThan(checks, 3)
        attachScreenshot(named: "Floating player clear of the highlight")
    }

    /// The Read Aloud pen on a PDF page: a tap reads from the word, a second tap reads
    /// exactly to the word tapped, both show their marks over the page, and nothing is drawn
    /// or changed in the PDF. The floating player says "Reading Selection" and keeps clear of
    /// the word read.
    func testReadAloudPenReadsFromATappedWordThenExactlyToASecondTap() async throws {
        let directory = try makeVault(notes: [:])
        let pdfLocation = directory.appendingPathComponent("Paper.pdf")
        let pages = ["Static CMOS logic keeps its output at a full level. The noise margin tells how much disturbance it tolerates.",
                     "Dynamic logic stores its value as charge on a node, which leaks away over time."]
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try pdfRenderer.writePDF(to: pdfLocation) { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 60, y: 80, width: 480, height: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
            }
        }
        let workspace = try await makeWorkspace(directory: directory)
        await workspace.open(try VaultPath("Paper.pdf"))
        let pdf = try XCTUnwrap(workspace.pdfSession)
        let controller = try hostWithPlayer(workspace)
        try await waitUntil { pdf.pdfView != nil }
        let pdfView = try XCTUnwrap(pdf.pdfView)
        pdf.isWriting = true
        PaletteInkSelection.pointsToRead = true
        defer { PaletteInkSelection.pointsToRead = false }
        let page = try XCTUnwrap(pdf.document.page(at: 0))
        func canvas() -> PDFPageCanvasView? {
            descendants(of: controller.view, matching: PDFPageCanvasView.self).first { canvas in canvas.page === page && !canvas.isHidden }
        }
        try await waitUntil { canvas()?.pointsToRead == true && canvas()?.readAloudPenTapped != nil }
        let pageCanvas = try XCTUnwrap(canvas())
        XCTAssertFalse(pageCanvas.isDrawingEnabled, "The pen never draws.")
        let annotationsBefore = page.annotations.count
        let versionBefore = pdf.changeVersion

        func tap(_ word: String) throws {
            let text = try XCTUnwrap(page.string) as NSString
            let range = text.range(of: word)
            XCTAssertNotEqual(range.location, NSNotFound, word)
            let bounds = try XCTUnwrap(page.selection(for: range)).bounds(for: page)
            let point = pdfView.convert(pdfView.convert(CGPoint(x: bounds.midX, y: bounds.midY), from: page), to: nil)
            pageCanvas.readAloudPenTapped?(point)
        }
        func markers() -> [ReadAloudPenMarkerView] { descendants(of: pdfView, matching: ReadAloudPenMarkerView.self) }
        let reader = workspace.readAloud
        let navigator = workspace.readAloudNavigator

        // One tap: reading starts at "output", marked as the start.
        try tap("output")
        try await waitUntil(timeoutSeconds: 15) { reader.session.document != nil && reader.sourceIdentifier == pdf.location.path }
        XCTAssertTrue(reader.session.document?.passages.first?.text.hasPrefix("output") ?? false,
                      String(describing: reader.session.document?.passages.first?.text))
        try await waitUntil { markers().count == 1 }
        XCTAssertTrue(markers().first?.isStart ?? false)

        // A second tap: exactly from "output" through "tells", and nothing after it.
        try tap("tells")
        try await waitUntil(timeoutSeconds: 15) {
            let text = reader.session.document?.passages.map(\.text).joined(separator: " ") ?? ""
            return text.hasPrefix("output") && text.hasSuffix("tells")
        }
        XCTAssertTrue(navigator.isReadingPenSelection)
        try await waitUntil { markers().count == 2 }
        XCTAssertEqual(markers().filter(\.isStart).count, 1)
        try await waitUntil(timeoutSeconds: 10) { navigator.highlightFrameInWindow != nil }
        attachScreenshot(named: "Read Aloud pen: start and end marks, Reading Selection")

        // The player keeps clear of the word read while the range plays.
        var checks = 0
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(150))
            guard let player = navigator.playerFrameInWindow, let word = navigator.highlightFrameInWindow, !player.isEmpty else { continue }
            checks += 1
            XCTAssertFalse(player.intersects(word), "Player \(player) covers the word \(word).")
        }
        XCTAssertGreaterThan(checks, 3)

        // No ink, no annotation, no change to the PDF.
        XCTAssertTrue(pageCanvas.drawing.strokes.isEmpty)
        XCTAssertEqual(page.annotations.count, annotationsBefore)
        XCTAssertEqual(pdf.changeVersion, versionBefore)

        // Stopping clears the marks.
        reader.clear()
        try await waitUntil { markers().isEmpty }
    }

    /// A landscape-wide window (the simulator here cannot be turned): the player sits within
    /// the window, keeps clear of the word read, and is drawn the same.
    func testFloatingPlayerInALandscapeWindow() async throws {
        let directory = try makeVault(notes: [:])
        let pdfLocation = directory.appendingPathComponent("Wide.pdf")
        let text = String(repeating: "Static CMOS logic keeps its output at a full level while the noise margin tells how much disturbance it tolerates. ", count: 14)
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: pdfLocation) { context in
            context.beginPage()
            (text as NSString).draw(in: CGRect(x: 60, y: 60, width: 492, height: 680), withAttributes: [.font: UIFont.systemFont(ofSize: 15)])
        }
        let workspace = try await makeWorkspace(directory: directory)
        await workspace.open(try VaultPath("Wide.pdf"))
        let pdf = try XCTUnwrap(workspace.pdfSession)
        _ = try hostWithPlayer(workspace)
        let window = try XCTUnwrap(self.window)
        window.frame = CGRect(x: 0, y: 0, width: 1210, height: 834)
        window.layoutIfNeeded()
        try await waitUntil { pdf.pdfView != nil }
        workspace.readAloud.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 0)
        let navigator = workspace.readAloudNavigator
        try await waitUntil(timeoutSeconds: 20) { navigator.highlightFrameInWindow != nil && navigator.playerFrameInWindow != nil }
        var checks = 0
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(150))
            guard let player = navigator.playerFrameInWindow, let word = navigator.highlightFrameInWindow, !player.isEmpty else { continue }
            checks += 1
            XCTAssertTrue(window.bounds.contains(player), "Player \(player) outside the window \(window.bounds).")
            XCTAssertFalse(player.intersects(word), "Player \(player) covers the word \(word).")
        }
        XCTAssertGreaterThan(checks, 3)
        attachScreenshot(named: "Player in a landscape window")
    }

    // MARK: Helpers

    private func hostWithPlayer(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(ZStack {
            NavigationStack {
                WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
            }
            ReadAloudFloatingPlayer(reader: workspace.readAloud, navigator: workspace.readAloudNavigator)
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func openLecture(viewMode: NoteViewMode) async throws -> (WorkspaceModel, MarkdownSession) {
        let workspace = try await makeWorkspace(directory: try makeVault(notes: ["Lecture.md": Self.lecture]))
        await workspace.open(try VaultPath("Lecture.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = viewMode
        return (workspace, session)
    }

    private func makeVault(notes: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudLecture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        for (name, text) in notes { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        return directory
    }

    private func makeWorkspace(directory: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { name in name.hasSuffix(".md") || name.hasSuffix(".pdf") }
        try await index.refresh(paths: names.map { name in try VaultPath(name) }, root: directory)
        workspace.index = index
        savedSpeed = workspace.readAloud.session.speed
        // A brisk speed keeps the test short; the highlight path is the same at any speed.
        workspace.readAloud.session.setSpeed(1.5)
        self.workspace = workspace
        return workspace
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    private func visibleEditor(in controller: UIViewController) async throws -> MarkdownTextView {
        func editor() -> MarkdownTextView? {
            descendants(of: controller.view, matching: MarkdownTextView.self).first { editor in editor.window != nil && editor.bounds.height > 100 }
        }
        try? await waitUntil { editor() != nil }
        if editor() == nil {
            let editors = descendants(of: controller.view, matching: MarkdownTextView.self)
            attachScreenshot(named: "No editor")
            XCTFail("Editors: \(editors.map { "\($0.bounds) window \($0.window != nil)" }); window \(String(describing: controller.view.window?.bounds))")
        }
        return try XCTUnwrap(editor())
    }

    /// The window's strongly blue, light pixels (the reading fill), by position.
    private func bluePixels() -> (pixels: Set<Int>, width: Int) {
        guard let window else { return ([], 0) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return ([], 0) }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        var pixels = Set<Int>()
        for row in 0..<cgImage.height {
            for column in 0..<cgImage.width {
                let pixel = bytes + row * cgImage.bytesPerRow + column * bytesPerPixel
                let first = Int(pixel[0]), second = Int(pixel[1]), third = Int(pixel[2])
                let (red, green, blue) = cgImage.bitmapInfo.contains(.byteOrder32Little) ? (third, second, first) : (first, second, third)
                if blue > 205, blue > red + 30, blue > green + 10 { pixels.insert(row * cgImage.width + column) }
            }
        }
        return (pixels, cgImage.width)
    }

    /// The bounding box of reading-blue pixels that were not there before reading, or nil.
    private func highlightBounds(excluding before: (pixels: Set<Int>, width: Int)) -> CGRect? {
        let now = bluePixels()
        let added = now.pixels.subtracting(before.pixels)
        guard added.count > 40, now.width > 0 else { return nil }
        return added.reduce(CGRect.null) { bounds, index in
            bounds.union(CGRect(x: index % now.width, y: index / now.width, width: 1, height: 1))
        }
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Also kept as a file in the app's temporary folder, readable when xcodebuild stops
        // before writing its result bundle.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudScreenshots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-") + ".png"))
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in (child as? View).map { [$0] } ?? [] + descendants(of: child, matching: type) }
    }

}

/// Scrolls a view down a step per display frame, as a quick finger would, and records the
/// longest time between two frames: a stall of the main thread shows up as a long gap.
@MainActor
private final class FrameGapMeasurement: NSObject {
    private let scrollView: UIScrollView
    private let step: CGFloat
    private let duration: TimeInterval
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var startTimestamp: CFTimeInterval?
    private var longestGap: CFTimeInterval = 0
    private var direction: CGFloat = 1
    private var continuation: CheckedContinuation<TimeInterval, Never>?

    init(scrollView: UIScrollView, step: CGFloat, duration: TimeInterval) {
        self.scrollView = scrollView
        self.step = step
        self.duration = duration
    }

    func run() async -> TimeInterval {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let displayLink = CADisplayLink(target: self, selector: #selector(frame(_:)))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        if let previousTimestamp { longestGap = max(longestGap, now - previousTimestamp) }
        previousTimestamp = now
        if startTimestamp == nil { startTimestamp = now }
        let maximumOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        var next = scrollView.contentOffset.y + step * direction
        if next > maximumOffset || next < 0 { direction *= -1; next = min(max(0, next), maximumOffset) }
        scrollView.contentOffset.y = next
        if let startTimestamp, now - startTimestamp >= duration {
            link.invalidate()
            displayLink = nil
            continuation?.resume(returning: longestGap)
            continuation = nil
        }
    }
}

/// A tiny stand-in for a downloaded voice: a quiet tone a few hundredths of a second per
/// character, so High Quality reading can be tested end to end (rendering ahead, the cache,
/// AVAudioEngine playback, word highlighting, waiting and the system-voice fallback) in the
/// Simulator, which cannot run the MLX models.
private final class ToneRenderer: NeuralPassageRendering, @unchecked Sendable {
    // `@unchecked Sendable`: every property is read and written while holding `lock`.
    private let lock = NSLock()
    private var renderedTexts: [String] = []
    private var renderedVoices: [String] = []
    /// Voices that babble: they run on to twelve times the passage's length, like Qwen3-TTS
    /// did on a list of spelled acronyms.
    var babblingVoiceIdentifiers: Set<String> = []
    private var gate: CheckedContinuation<Void, Never>?
    private var isGated = false
    static let secondsPerCharacter = 0.012

    var renders: [String] { lock.withLock { renderedTexts } }
    var lastText: String? { lock.withLock { renderedTexts.last } }
    var voices: [String] { lock.withLock { renderedVoices } }

    func holdRendering() { lock.withLock { isGated = true } }
    func releaseRendering() {
        let waiting: CheckedContinuation<Void, Never>? = lock.withLock { isGated = false; defer { gate = nil }; return gate }
        waiting?.resume()
    }

    func render(_ text: String, voice: NeuralVoiceDescription, voiceFolder: URL, seed: UInt64?) async throws -> RenderedSpeech {
        if lock.withLock({ isGated }) {
            await withCheckedContinuation { continuation in
                let releaseNow: Bool = lock.withLock { if isGated { gate = continuation; return false }; return true }
                if releaseNow { continuation.resume() }
            }
        }
        lock.withLock { renderedTexts.append(text); renderedVoices.append(voice.id) }
        let sampleRate = 24_000
        let babbles = babblingVoiceIdentifiers.contains(voice.id)
        let secondsPerCharacter = babbles ? 12 / ReadAloudRenderCheck.charactersPerSecond : Self.secondsPerCharacter
        let count = max(sampleRate / 10, Int(Double(text.count) * secondsPerCharacter * Double(sampleRate)))
        let samples = (0..<count).map { index in Float(0.05 * sin(Double(index) * 2 * .pi * 220 / Double(sampleRate))) }
        return RenderedSpeech(samples: samples, sampleRate: sampleRate)
    }

    func releaseResources() async {}
}

/// Reports the rendered passage's words evenly spread over its audio, as speech recognition
/// would for a clear voice.
private struct EvenAligner: ReadAloudSpeechAligning {
    let renderer: ToneRenderer
    func recognizedWords(in audioFile: URL, language: String) async -> [ReadAloudRecognizedWord]? {
        guard let text = renderer.lastText, let file = try? AVAudioFile(forReading: audioFile) else { return nil }
        let duration = Double(file.length) / file.fileFormat.sampleRate
        let words = ReadAloudWordAlignment.words(in: text)
        return words.enumerated().map { index, word in
            let start = duration * Double(index) / Double(words.count)
            return ReadAloudRecognizedWord(text: (text as NSString).substring(with: word.range), startSeconds: start,
                                           endSeconds: start + duration / Double(words.count))
        }
    }
}

/// The system voice's stand-in: records what it was asked to speak.
@MainActor
private final class RecordingQuickSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    var voices = [ReadAloudVoice(id: "quick-voice", name: "Quick", language: "en-US", quality: 3)]
    var spokenTexts: [String] = []
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { spokenTexts.append(text) }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

@MainActor
final class HighQualityReadAloudTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() async throws {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HighQualityReadAloudTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder
    }

    /// A library with one test voice, installed unless told otherwise, and a speech that uses
    /// the tone renderer.
    private func makeReader(installsVoice: Bool = true, cacheCapacityBytes: Int64 = 50_000_000)
        throws -> (ReadAloudController, NeuralReadAloudSpeech, ToneRenderer, RecordingQuickSpeech) {
        let voice = NeuralVoiceDescription(
            id: "test-tone", name: "Tone", modelName: "Test Tone", modelFamily: .pocketTTS, speaker: "tone", language: "en",
            qualityNote: "A test tone.", license: NeuralVoiceLicense(name: "MIT", address: URL(string: "https://example.com")!),
            sources: [NeuralVoiceSource(repository: "test/tone", revision: "r1",
                                        files: [NeuralVoiceFile(path: "model.safetensors", byteCount: 4, sha256: String(repeating: "0", count: 64))])],
            platforms: ["iOS", "macOS"], minimumPhysicalMemoryBytes: 1)
        let installation = NeuralVoiceInstallation(voicesFolder: try temporaryFolder())
        if installsVoice {
            try FileManager.default.createDirectory(at: installation.stagingFolder(of: voice), withIntermediateDirectories: true)
            try Data("test".utf8).write(to: installation.stagingFolder(of: voice).appendingPathComponent("model.safetensors"))
            try installation.finishInstalling(voice)
        }
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "HighQualityReadAloudTests-\(UUID().uuidString)"))
        let cache = ReadAloudAudioCache(folder: try temporaryFolder(), capacityBytes: cacheCapacityBytes)
        let library = NeuralVoiceLibrary(manifest: NeuralVoiceManifest(downloadHost: URL(string: "https://example.com")!, voices: [voice]),
                                         installation: installation, audioCache: cache, preferences: preferences,
                                         platform: "iOS", physicalMemoryBytes: 1 << 33, startsDownloader: false)
        let renderer = ToneRenderer()
        let preparation = ReadAloudPassagePreparation(cache: cache, renderer: renderer, aligner: EvenAligner(renderer: renderer))
        let quick = RecordingQuickSpeech()
        let speech = NeuralReadAloudSpeech(quick: quick, library: library, preparation: preparation)
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("quick-voice")
        return (ReadAloudController(session: session, neuralSpeech: speech, preferences: preferences), speech, renderer, quick)
    }

    private func testVoice(_ identifier: String, family: NeuralVoiceModelFamily) -> NeuralVoiceDescription {
        NeuralVoiceDescription(
            id: identifier, name: identifier, modelName: identifier, modelFamily: family, speaker: nil, language: "en",
            qualityNote: "A test voice.", license: NeuralVoiceLicense(name: "MIT", address: URL(string: "https://example.com")!),
            sources: [NeuralVoiceSource(repository: "test/\(identifier)", revision: "r1",
                                        files: [NeuralVoiceFile(path: "model.safetensors", byteCount: 4, sha256: String(repeating: "0", count: 64))])],
            platforms: ["iOS", "macOS"], minimumPhysicalMemoryBytes: 1)
    }

    /// A babbling autoregressive voice is chosen; a Pocket TTS voice is installed too when
    /// `installsFallback`.
    private func makeBabblingReader(installsFallback: Bool) throws
        -> (ReadAloudController, NeuralReadAloudSpeech, ToneRenderer, RecordingQuickSpeech) {
        let babbler = testVoice("babbler", family: .qwen3TTS)
        let pocket = testVoice("steady-pocket", family: .pocketTTS)
        let installation = NeuralVoiceInstallation(voicesFolder: try temporaryFolder())
        for voice in installsFallback ? [babbler, pocket] : [babbler] {
            try FileManager.default.createDirectory(at: installation.stagingFolder(of: voice), withIntermediateDirectories: true)
            try Data("test".utf8).write(to: installation.stagingFolder(of: voice).appendingPathComponent("model.safetensors"))
            try installation.finishInstalling(voice)
        }
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "HighQualityReadAloudTests-\(UUID().uuidString)"))
        let cache = ReadAloudAudioCache(folder: try temporaryFolder())
        let library = NeuralVoiceLibrary(manifest: NeuralVoiceManifest(downloadHost: URL(string: "https://example.com")!, voices: [babbler, pocket]),
                                         installation: installation, audioCache: cache, preferences: preferences,
                                         platform: "iOS", physicalMemoryBytes: 1 << 33, startsDownloader: false)
        library.selectVoice(babbler)
        let renderer = ToneRenderer()
        renderer.babblingVoiceIdentifiers = ["babbler"]
        let preparation = ReadAloudPassagePreparation(cache: cache, renderer: renderer, aligner: EvenAligner(renderer: renderer))
        let quick = RecordingQuickSpeech()
        let speech = NeuralReadAloudSpeech(quick: quick, library: library, preparation: preparation)
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("quick-voice")
        return (ReadAloudController(session: session, neuralSpeech: speech, preferences: preferences), speech, renderer, quick)
    }

    func testABabblingRenderingIsRegeneratedThenReadByPocketTTSAndNeverHeard() async throws {
        let (reader, speech, renderer, quick) = try makeBabblingReader(installsFallback: true)
        reader.session.load(try ReadAloudDocument.markdown("Write VHDL for the FPGA."))
        reader.session.play()
        try await waitUntil(timeoutSeconds: 20) { reader.session.state == .speaking && reader.session.spokenRange != nil }
        XCTAssertEqual(renderer.voices, ["babbler", "babbler", "steady-pocket"], "two attempts with the chosen voice, then the fallback")
        XCTAssertEqual(renderer.renders[0], "Write VHDL for the FPGA.", "the autoregressive voice gets acronyms as written")
        XCTAssertEqual(renderer.renders[2], "Write V H D L for the F P G A.", "the fallback reads the passage's respellings")
        XCTAssertTrue(speech.preparation.lastRejection?.contains("times longer") == true, String(describing: speech.preparation.lastRejection))
        XCTAssertTrue(quick.spokenTexts.isEmpty)
        try await waitUntil(timeoutSeconds: 20) { reader.session.state == .finished }
    }

    func testWithoutAFallbackVoiceTheSystemVoiceReadsWhatTheVoiceGarbled() async throws {
        let (reader, speech, renderer, quick) = try makeBabblingReader(installsFallback: false)
        reader.session.load(try ReadAloudDocument.markdown("Write VHDL for the FPGA."))
        reader.session.play()
        try await waitUntil(timeoutSeconds: 20) { !quick.spokenTexts.isEmpty }
        XCTAssertEqual(renderer.voices, ["babbler", "babbler"])
        XCTAssertEqual(quick.spokenTexts, ["Write V H D L for the F P G A."])
        XCTAssertEqual(speech.preparation.systemVoiceTexts, ["Write VHDL for the FPGA."])
    }

    private let note = "# Memory\n\nCompared with SRAM, DRAM is denser but slower.\n\nRead and write signals come from the controller."

    func testHighQualityRendersAheadPlaysTheVoiceAndHighlightsAlignedWords() async throws {
        let (reader, speech, renderer, quick) = try makeReader()
        XCTAssertEqual(speech.library.mode, .highQuality, "High Quality is the default once a voice is downloaded")
        reader.session.load(try ReadAloudDocument.markdown(note))
        reader.session.play()
        var highlightedWords: [String] = []
        let deadline = Date().addingTimeInterval(20)
        while reader.session.state != .finished, Date() < deadline {
            if let range = reader.session.spokenRange, let passage = reader.session.currentPassage {
                let word = (passage.text as NSString).substring(with: range)
                if highlightedWords.last != word { highlightedWords.append(word) }
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(reader.session.state, .finished)
        XCTAssertEqual(Set(renderer.renders), Set(reader.session.document?.passages.map(\.text) ?? []), "every passage is rendered once")
        XCTAssertEqual(renderer.renders.count, reader.session.document?.passages.count)
        XCTAssertTrue(quick.spokenTexts.isEmpty, "the system voice never read")
        // The voice reads the respelled text ("dee ram" for DRAM), and the highlight follows it.
        XCTAssertTrue(highlightedWords.contains("dee") && highlightedWords.contains("controller"), "words highlighted: \(highlightedWords)")
        let comparedIndex = try XCTUnwrap(highlightedWords.firstIndex(of: "Compared"))
        let denserIndex = try XCTUnwrap(highlightedWords.firstIndex(of: "denser"))
        XCTAssertLessThan(comparedIndex, denserIndex, "the highlight moves forward with the audio")

        // Reading the same note again renders nothing: every passage comes from the cache.
        reader.session.load(try ReadAloudDocument.markdown(note))
        reader.session.play()
        try await waitUntil(timeoutSeconds: 20) { reader.session.state == .finished }
        XCTAssertEqual(renderer.renders.count, reader.session.document?.passages.count)

        // Editing one paragraph re-renders that paragraph alone.
        reader.session.load(try ReadAloudDocument.markdown(note.replacingOccurrences(of: "denser but slower", with: "denser and slower")))
        reader.session.play()
        try await waitUntil(timeoutSeconds: 20) { reader.session.state == .finished }
        XCTAssertEqual(renderer.renders.count, (reader.session.document?.passages.count ?? 0) + 1)
        XCTAssertTrue(renderer.renders.last?.hasSuffix("is denser and slower.") == true, String(describing: renderer.renders.last))
    }

    /// The Read Aloud pen's range in High Quality: only the words between the two taps are
    /// prepared and heard, not the page around them.
    func testThePensRangeIsPreparedAloneInHighQuality() async throws {
        let (reader, speech, renderer, quick) = try makeReader()
        XCTAssertEqual(speech.library.mode, .highQuality)
        let location = try temporaryFolder().appendingPathComponent("Range.pdf")
        let text = "Alpha bravo charlie delta echo. Foxtrot golf hotel india juliet."
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: location) { context in
            context.beginPage()
            (text as NSString).draw(in: CGRect(x: 60, y: 80, width: 480, height: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
        }
        let pdf = try await PDFSession.open(location)
        let pageText = try XCTUnwrap(pdf.document.page(at: 0)?.string) as NSString
        let start = pageText.range(of: "charlie"), end = pageText.range(of: "golf")
        reader.readPDFRange(pdf, start: PDFReadAloudEndpoint(pageIndex: 0, offset: start.location, revision: pdf.changeVersion),
                            end: PDFReadAloudEndpoint(pageIndex: 0, offset: NSMaxRange(end), revision: pdf.changeVersion))
        try await waitUntil(timeoutSeconds: 20) { reader.session.document != nil && !reader.isPreparing }
        if reader.session.state != .speaking { reader.session.play() }
        try await waitUntil(timeoutSeconds: 30) { reader.session.state == .finished }
        let rendered = renderer.renders.joined(separator: " ")
        XCTAssertTrue(rendered.contains("charlie") && rendered.contains("golf"), rendered)
        for outside in ["Alpha", "bravo", "hotel", "juliet"] { XCTAssertFalse(rendered.contains(outside), "\(outside) was prepared: \(rendered)") }
        XCTAssertTrue(quick.spokenTexts.isEmpty, "the downloaded voice read it")
    }

    func testUnpreparedPassageWaitsWithProgressThenTheSystemVoiceFillsInOnceAllowed() async throws {
        let (reader, speech, renderer, quick) = try makeReader()
        renderer.holdRendering()
        reader.session.load(try ReadAloudDocument.markdown(note))
        reader.session.play()
        try await waitUntil { speech.isWaitingForPassage }
        XCTAssertTrue(reader.isWaitingForPreparedAudio)
        XCTAssertEqual(reader.preparingDescription, "Preparing… 0%")
        XCTAssertNotNil(reader.preparedAudioShare)
        XCTAssertTrue(quick.spokenTexts.isEmpty, "without the person's permission reading waits for the voice")

        speech.setReadsUnpreparedPassagesQuickly(true)
        XCTAssertEqual(quick.spokenTexts, ["Memory"], "the waiting passage starts at once with the system voice")
        XCTAssertFalse(speech.isWaitingForPassage)
        renderer.releaseRendering()
        try await waitUntil { !speech.preparation.isPreparing }
        XCTAssertEqual(speech.preparation.preparedShare, 1, accuracy: 0.001)
    }

    func testWithoutADownloadedVoiceQuickModeSpeaksWithTheSystemVoice() async throws {
        let (reader, speech, renderer, quick) = try makeReader(installsVoice: false)
        XCTAssertEqual(speech.library.mode, .quick)
        XCTAssertFalse(speech.readsWithDownloadedVoice)
        reader.session.load(try ReadAloudDocument.markdown(note))
        reader.session.play()
        XCTAssertEqual(quick.spokenTexts, ["Memory"])
        XCTAssertTrue(renderer.renders.isEmpty)
        XCTAssertNil(reader.preparedAudioShare)
    }

    func testChoosingQuickWithADownloadedVoiceUsesTheSystemVoice() async throws {
        let (reader, speech, renderer, quick) = try makeReader()
        speech.library.chooseMode(.quick)
        reader.session.load(try ReadAloudDocument.markdown(note))
        reader.session.play()
        XCTAssertEqual(quick.spokenTexts, ["Memory"])
        XCTAssertTrue(renderer.renders.isEmpty)
    }

    func testPauseAndResumeHoldThePlaceWithinARenderedPassage() async throws {
        let (reader, _, _, _) = try makeReader()
        reader.session.load(try ReadAloudDocument.plainText(String(repeating: "Bitlines are precharged before every read. ", count: 6)))
        reader.session.play()
        try await waitUntil { (reader.session.spokenRange?.location ?? 0) > 40 }
        reader.session.pause()
        let pausedAt = try XCTUnwrap(reader.session.spokenRange)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(reader.session.spokenRange, pausedAt, "nothing moves while paused")
        reader.session.play()
        XCTAssertEqual(reader.session.state, .speaking)
        try await waitUntil { (reader.session.spokenRange?.location ?? 0) > pausedAt.location }
    }
}
#endif
