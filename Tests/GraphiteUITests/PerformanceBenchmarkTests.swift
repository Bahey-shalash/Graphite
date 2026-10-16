import XCTest
import SwiftUI
import PDFKit
import CoreText
@testable import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Time, processor and memory use of opening, scrolling and typing in a long note, of
/// opening and scrolling a long PDF with its pages sidebar, of an embedded PDF while other
/// files change, and of the map's updates. The same file runs on the Mac (`swift test`) and
/// in the hosted iPad tests, so both platforms are measured the same way.
///
/// The benchmarks run only when asked for, as they take minutes:
/// `GRAPHITE_BENCHMARKS=1 swift test -c release -Xswiftc -enable-testing --filter PerformanceBenchmarkTests`
/// on the Mac, and `TEST_RUNNER_GRAPHITE_BENCHMARKS=1 xcodebuild test … -only-testing:GraphiteIntegrationTests/PerformanceBenchmarkTests`
/// for the iPad. Each prints one `GRAPHITE-BENCH` line per run.
///
/// A frame's cost is the main thread's work for one scroll step or keystroke: the step
/// itself, plus how late a 16 ms timer then fires, which is the time the main thread spent
/// on what the step set off (SwiftUI updates, layout, drawing).
@MainActor
final class PerformanceBenchmarkTests: XCTestCase {
    private static let runCount = 3
    nonisolated private static let frameInterval = Duration.milliseconds(16)
    #if canImport(UIKit)
    nonisolated private static let platformName = "iPad"
    #else
    nonisolated private static let platformName = "Mac"
    #endif
    /// The iPad Pro 11-inch's portrait window, used on the Mac too.
    private static let windowSize = CGSize(width: 834, height: 1210)

    private var temporaryDirectories: [URL] = []
    #if canImport(UIKit)
    private var windows: [UIWindow] = []
    #else
    private var windows: [NSWindow] = []
    #endif

    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRAPHITE_BENCHMARKS"] == "1",
                          "Benchmarks run only with GRAPHITE_BENCHMARKS=1.")
    }

    override func tearDown() async throws {
        for window in windows { close(window) }
        windows.removeAll()
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectories.removeAll()
    }

    // MARK: A long note

    func testOpeningScrollingAndTypingInALongNote() async throws {
        let noteText = Self.longLectureNote(sectionCount: 40)
        for run in 1...Self.runCount {
            let vault = try makeTemporaryDirectory(named: "NoteBenchmark")
            let notePath = try VaultPath("Lecture.md")
            try Data(noteText.utf8).write(to: vault.appendingPathComponent(notePath.rawValue))
            let workspace = WorkspaceModel()
            workspace.folderAccess = FolderAccess(root: vault)
            workspace.store = VaultStore(root: vault)
            let index = try VaultIndex(databaseURL: vault.appendingPathComponent("index.sqlite"))
            workspace.index = index
            _ = try await index.reconcile(root: vault)

            let footprintBeforeOpening = ProcessResourceUsage.memoryFootprintBytes()
            // Opening: from the request to a laid-out editor with its first blocks drawn.
            let opening = BenchmarkMeasurement(scenario: "note-open", run: run)
            await workspace.open(notePath, placement: .currentTab)
            let tab = try XCTUnwrap(workspace.layout.tabID(showing: notePath))
            let session = try XCTUnwrap(workspace.document(for: tab).markdownSession)
            session.viewMode = .livePreview
            let window = host(NavigationStack {
                WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
            })
            let editor = try await waitForValue(timeout: .seconds(20)) { () -> BenchmarkTextView? in
                self.layOut(window)
                guard let editor = self.descendants(of: self.contentView(of: window), matching: BenchmarkTextView.self).first,
                      self.text(of: editor) == session.text, self.visibleBounds(of: editor).width > 0,
                      !self.blockViews(in: editor).isEmpty else { return nil }
                return editor
            }
            opening.finish()

            // Scrolling to the end and back, a step of 40% of the window at a time.
            let scrolling = BenchmarkMeasurement(scenario: "note-scroll", run: run)
            for direction in [1.0, -1.0] {
                // Each way on its own too: down, blocks are drawn the first time; up, again.
                let way = BenchmarkMeasurement(scenario: direction > 0 ? "note-scroll-down" : "note-scroll-up", run: run)
                defer { way.finish() }
                var stepCount = 0
                while stepCount < 2_000 {
                    let viewportHeight = visibleBounds(of: editor).height
                    let currentOffset = scrollOffset(of: editor)
                    let lastOffset = max(0, documentHeight(of: editor) - viewportHeight)
                    let nextOffset = min(lastOffset, max(0, currentOffset + direction * viewportHeight * 0.4))
                    if abs(nextOffset - currentOffset) < 1 { break }
                    await scrolling.measureFrame { self.scroll(editor, to: nextOffset) }
                    way.recordFrame(from: scrolling)
                    stepCount += 1
                }
            }
            scrolling.finish()

            // Typing forty characters in the middle of the note.
            let middle = (text(of: editor) as NSString).range(of: "## Section 20").location
            scroll(editor, to: max(0, (documentHeight(of: editor) - visibleBounds(of: editor).height) / 2))
            select(NSRange(location: middle, length: 0), in: editor)
            let typing = BenchmarkMeasurement(scenario: "note-typing", run: run)
            for character in "The inverter's delay grows with its load" {
                await typing.measureFrame { self.type(String(character), in: editor) }
            }
            typing.finish()
            try? await workspace.document(for: tab).saveAllChanges()
            close(window)
            try await reportMemoryKept(scenario: "note-memory-kept-after-close", run: run, since: footprintBeforeOpening)
        }
    }

    // MARK: A long PDF

    func testOpeningAndScrollingALongPDFWithItsPagesSidebar() async throws {
        let directory = try makeTemporaryDirectory(named: "PDFBenchmark")
        let location = try Self.makeLecturePDF(at: directory.appendingPathComponent("Lecture.pdf"), pageCount: 150)
        for run in 1...Self.runCount {
            let footprintBeforeOpening = ProcessResourceUsage.memoryFootprintBytes()
            let opening = BenchmarkMeasurement(scenario: "pdf-open", run: run)
            let session = try await PDFSession.open(location)
            let window = host(NavigationStack {
                HStack(spacing: 0) {
                    PDFPagesSidebar(session: session, commands: PDFPageCommands(session: session), renderer: PDFThumbnailRenderer())
                        .frame(width: 210)
                    PDFPane(session: session, resolveConflict: { _ in })
                }
            })
            let pdfView = try await waitForValue(timeout: .seconds(20)) { () -> PDFView? in
                self.layOut(window)
                guard let pdfView = session.pdfView, pdfView.bounds.height > 100, !pdfView.visiblePages.isEmpty else { return nil }
                return pdfView
            }
            opening.finish()

            // Page by page to the end, as a reader turning pages does: each turn is a page
            // change PDFKit reports, which the pane, its sidebar and the session follow.
            // Scrolling the scroll view from code did not make PDFKit report page changes.
            let scrolling = BenchmarkMeasurement(scenario: "pdf-scroll", run: run)
            for pageIndex in 1..<session.document.pageCount {
                guard let page = session.document.page(at: pageIndex) else { continue }
                await scrolling.measureFrame {
                    pdfView.go(to: page)
                    self.layOut(window)
                }
            }
            scrolling.finish()
            XCTAssertGreaterThan(session.currentPageIndex, 100, "The scroll did not reach the end of the PDF.")
            close(window)
            try await reportMemoryKept(scenario: "pdf-memory-kept-after-close", run: run, since: footprintBeforeOpening)
        }
    }

    // MARK: An embedded PDF while other files change

    /// Every change another app makes in the vault raises the drawing version; the embed
    /// then checks its own file. Measured against the same time spent idle.
    func testAnEmbeddedPDFWhileOtherFilesChange() async throws {
        let directory = try makeTemporaryDirectory(named: "EmbedBenchmark")
        let location = try Self.makeScannedPDF(at: directory.appendingPathComponent("Scans.pdf"), pageCount: 30)
        for run in 1...Self.runCount {
            let model = EmbedBenchmarkModel()
            let window = host(EmbedBenchmarkContainer(model: model, location: location))
            _ = try await waitForValue(timeout: .seconds(20)) { () -> PDFView? in
                self.layOut(window)
                return self.descendants(of: self.contentView(of: window), matching: PDFView.self).first { pdfView in !pdfView.visiblePages.isEmpty }
            }
            try await Task.sleep(for: .seconds(1))

            let idle = BenchmarkMeasurement(scenario: "embed-idle", run: run)
            for _ in 1...6 { await idle.measureFrame {}; try await Task.sleep(for: .milliseconds(500)) }
            idle.finish()

            let changes = BenchmarkMeasurement(scenario: "embed-other-files-change", run: run)
            for _ in 1...6 { await changes.measureFrame { model.drawingVersion += 1 }; try await Task.sleep(for: .milliseconds(500)) }
            changes.finish()
            close(window)
        }
    }

    // MARK: The map

    /// Updates of the view around the map that change nothing the map shows.
    func testUpdatesAroundTheVaultMap() async throws {
        let notes = (0..<3_000).compactMap { noteNumber -> PlacedNote? in
            guard let path = try? VaultPath("Places/Place \(noteNumber).md"),
                  let coordinate = BaseCoordinate(latitude: 46 + Double(noteNumber % 60) * 0.05, longitude: 6 + Double(noteNumber / 60) * 0.05) else { return nil }
            return PlacedNote(path: path, coordinate: coordinate)
        }
        for run in 1...Self.runCount {
            let model = MapBenchmarkModel()
            let window = host(MapBenchmarkContainer(model: model, notes: notes))
            try await Task.sleep(for: .seconds(2))
            layOut(window)
            let updates = BenchmarkMeasurement(scenario: "map-updates", run: run)
            for _ in 1...40 { await updates.measureFrame { model.unrelatedCounter += 1 } }
            updates.finish()
            close(window)
        }
    }

    // MARK: Content

    /// A lecture note with properties and, in every section, the elements a lecture has:
    /// headings, emphasis, links, inline and display math, lists, tasks, a callout, code
    /// and a table.
    static func longLectureNote(sectionCount: Int) -> String {
        var lines = ["---", "title: Inverter delay and sizing", "course: EE-330 Digital IC Design", "lecture: 6", "due: 2026-10-07",
                     "reviewed: false", "score: 8.5", "tags:", "  - lecture", "  - delay", "aliases:", "  - Inverter sizing lecture", "---", ""]
        for section in 1...sectionCount {
            lines += [
                "## Section \(section)", "",
                "The **propagation delay** of an inverter driving a load of $C_L$ is set by its [[RC model]] and the *effective* resistance $R_{eq}$ of the transistor that switches. Section \(section) works through a chain of inverters sized by logical effort, with `t_p = 0.69 R C`.",
                "",
                "A second paragraph links to [the slides](https://example.com/slides/\(section)) and to [[Static logic#Section \(section)]], and states that the energy per transition is $E = C_L V_{DD}^2$, independent of the size.",
                "",
                "- Size the first stage for the input capacitance",
                "- Keep the stage effort near four",
                "  - nested: the parasitic delay adds $p$",
                "- Count the stages: $N = \\log_4 F$",
                "",
                "- [ ] Redo exercise \(section).a",
                "- [x] Read chapter \(section)",
                "",
                "> [!tip] Rule of thumb \(section)",
                "> A fanout of four gives a delay close to the optimum, whatever the technology.",
                "",
                "```verilog",
                "module inverter_chain_\(section) (input a, output y);",
                "  wire [3:0] stage;",
                "  assign stage[0] = ~a;",
                "  assign stage[1] = ~stage[0];",
                "  assign y = ~stage[1];",
                "endmodule",
                "```",
                "",
                "| Stage | Size | Delay |",
                "| --- | --- | --- |",
                "| 1 | 1 | 5 ps |",
                "| 2 | 4 | 5 ps |",
                "| 3 | 16 | 5 ps |",
                "",
                "$$",
                "t_p = 0.69\\, R_{eq} \\left( C_{int} + C_L \\right)",
                "$$",
                "",
            ]
        }
        return lines.joined(separator: "\n")
    }

    /// A lecture handout: fifty lines of text and a figure on every page, so PDFKit has text
    /// to lay out and drawing to do on each.
    static func makeLecturePDF(at location: URL, pageCount: Int) throws -> URL {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            for lineIndex in 0..<50 {
                let text = NSAttributedString(string: "Page \(pageIndex + 1), line \(lineIndex + 1): the delay of a chain of inverters is least when every stage bears the same effort.",
                                              attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                context.textPosition = CGPoint(x: 54, y: 740 - CGFloat(lineIndex) * 12)
                CTLineDraw(CTLineCreateWithAttributedString(text), context)
            }
            for barIndex in 0..<24 {
                context.setFillColor(CGColor(red: CGFloat(barIndex) / 24, green: 0.4, blue: 1 - CGFloat(barIndex) / 24, alpha: 1))
                context.fill(CGRect(x: 54 + CGFloat(barIndex) * 21, y: 60, width: 16, height: 20 + CGFloat((barIndex * 7 + pageIndex) % 60)))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    /// A scanned handout: one large picture per page that does not compress, about 1 MB a
    /// page, as a scanned textbook has.
    static func makeScannedPDF(at location: URL, pageCount: Int) throws -> URL {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        let pixelWidth = 600, pixelHeight = 600
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<pageCount {
            var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
            for pixelIndex in pixels.indices { pixels[pixelIndex] = UInt8.random(in: 0...255, using: &generator) }
            let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
            let picture = try XCTUnwrap(CGImage(width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixelWidth * 4,
                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
            context.beginPDFPage(nil)
            context.draw(picture, in: CGRect(x: 6, y: 96, width: 600, height: 600))
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    /// The memory still taken a moment after a document's window closed, against before it opened.
    private func reportMemoryKept(scenario: String, run: Int, since footprintBeforeOpening: UInt64) async throws {
        try await Task.sleep(for: .seconds(1.5))
        let kept = (Double(ProcessResourceUsage.memoryFootprintBytes()) - Double(footprintBeforeOpening)) / 1_048_576
        print("GRAPHITE-BENCH platform=\(Self.platformName) scenario=\(scenario) run=\(run) kept_mb=\(String(format: "%.2f", kept))")
    }

    // MARK: Waiting

    private func waitForValue<Value>(timeout: Duration, _ value: () -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let found = value() { return found }
            try await Task.sleep(for: .milliseconds(2))
        }
        return try XCTUnwrap(value(), "Timed out after \(timeout).")
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    // MARK: Platform

    #if canImport(UIKit)
    typealias BenchmarkTextView = MarkdownTextView

    private func host(_ view: some View) -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first
        let window = scene.map { scene in UIWindow(windowScene: scene) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: Self.windowSize)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        windows.append(window)
        return window
    }

    private func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
        windows.removeAll { openWindow in openWindow === window }
    }

    private func contentView(of window: UIWindow) -> UIView { window }
    private func layOut(_ window: UIWindow) { window.layoutIfNeeded() }

    private func descendants<Found: UIView>(of parent: UIView, matching type: Found.Type) -> [Found] {
        parent.subviews.flatMap { child in ((child as? Found).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    private func text(of editor: MarkdownTextView) -> String { editor.text }
    private func select(_ range: NSRange, in editor: MarkdownTextView) { editor.selectedRange = range }
    private func type(_ text: String, in editor: MarkdownTextView) { editor.insertText(text); editor.layoutIfNeeded() }

    /// SwiftUI's hosted views, which Live Preview places in the text view for its blocks.
    private func blockViews(in editor: MarkdownTextView) -> [UIView] {
        editor.subviews.filter { subview in
            var responder = subview.next
            while let currentResponder = responder, !(currentResponder is UIView) {
                if currentResponder is UIViewController { return true }
                responder = currentResponder.next
            }
            return false
        }
    }

    private func visibleBounds(of scrollView: UIScrollView) -> CGRect { scrollView.bounds }
    private func scrollOffset(of scrollView: UIScrollView) -> CGFloat { scrollView.contentOffset.y }
    private func documentHeight(of scrollView: UIScrollView) -> CGFloat { scrollView.contentSize.height + scrollView.adjustedContentInset.bottom }

    private func scroll(_ scrollView: UIScrollView, to offset: CGFloat) {
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: false)
        scrollView.layoutIfNeeded()
    }
    #else
    typealias BenchmarkTextView = MarkdownMacTextView

    private func host(_ view: some View) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: Self.windowSize), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: AnyView(view))
        windows.append(window)
        layOut(window)
        return window
    }

    private func close(_ window: NSWindow) {
        window.contentView = nil
        window.close()
        windows.removeAll { openWindow in openWindow === window }
    }

    private func contentView(of window: NSWindow) -> NSView { window.contentView ?? NSView() }

    private func layOut(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private func descendants<Found: NSView>(of parent: NSView, matching type: Found.Type) -> [Found] {
        parent.subviews.flatMap { child in ((child as? Found).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    private func text(of editor: MarkdownMacTextView) -> String { editor.string }
    private func select(_ range: NSRange, in editor: MarkdownMacTextView) { editor.setSelectedRange(range) }

    private func type(_ text: String, in editor: MarkdownMacTextView) {
        editor.insertText(text, replacementRange: editor.selectedRange())
        editor.enclosingScrollView?.layoutSubtreeIfNeeded()
        editor.window?.displayIfNeeded()
    }

    /// SwiftUI's hosted views, which Live Preview places in the text view for its blocks.
    private func blockViews(in editor: MarkdownMacTextView) -> [NSView] {
        editor.subviews.filter { subview in String(describing: Swift.type(of: subview)).hasPrefix("NSHostingView") }
    }

    private func enclosingScrollView(of view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.enclosingScrollView
    }

    private func visibleBounds(of view: NSView) -> CGRect { enclosingScrollView(of: view)?.contentView.bounds ?? view.bounds }
    private func scrollOffset(of view: NSView) -> CGFloat { enclosingScrollView(of: view)?.contentView.bounds.minY ?? 0 }
    private func documentHeight(of view: NSView) -> CGFloat { enclosingScrollView(of: view)?.documentView?.frame.height ?? view.frame.height }

    private func scroll(_ view: NSView, to offset: CGFloat) {
        guard let scrollView = enclosingScrollView(of: view) else { return }
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        scrollView.layoutSubtreeIfNeeded()
        scrollView.window?.displayIfNeeded()
    }
    #endif
}

/// One scenario's run: wall time, processor time of every thread, memory footprint, and
/// the cost of each frame it measured.
@MainActor
final class BenchmarkMeasurement {
    private let scenario: String
    private let run: Int
    private let startTime = ContinuousClock.now
    private let startProcessorSeconds = ProcessResourceUsage.processorSeconds()
    private let startMainThreadSeconds = ProcessResourceUsage.mainThreadProcessorSeconds()
    private let startFootprintBytes = ProcessResourceUsage.memoryFootprintBytes()
    private var peakFootprintBytes: UInt64
    private var frameDurations: [Duration] = []

    init(scenario: String, run: Int) {
        self.scenario = scenario
        self.run = run
        peakFootprintBytes = startFootprintBytes
    }

    /// The step's own work, and the main thread's work it set off, measured as how late a
    /// timer then fires.
    func measureFrame(_ step: () -> Void) async {
        let stepStart = ContinuousClock.now
        step()
        let stepEnd = ContinuousClock.now
        try? await Task.sleep(for: PerformanceBenchmarkTests.frameIntervalForMeasurement)
        let lateness = max(.zero, stepEnd.duration(to: .now) - PerformanceBenchmarkTests.frameIntervalForMeasurement)
        frameDurations.append(stepStart.duration(to: stepEnd) + lateness)
        peakFootprintBytes = max(peakFootprintBytes, ProcessResourceUsage.memoryFootprintBytes())
    }

    /// Counts the frame `other` measured last in this measurement too.
    func recordFrame(from other: BenchmarkMeasurement) {
        if let frame = other.frameDurations.last { frameDurations.append(frame) }
        peakFootprintBytes = max(peakFootprintBytes, other.peakFootprintBytes)
    }

    func finish() {
        let wallMilliseconds = Self.milliseconds(startTime.duration(to: .now))
        let processorMilliseconds = (ProcessResourceUsage.processorSeconds() - startProcessorSeconds) * 1_000
        let mainThreadMilliseconds = (ProcessResourceUsage.mainThreadProcessorSeconds() - startMainThreadSeconds) * 1_000
        let endFootprintBytes = ProcessResourceUsage.memoryFootprintBytes()
        peakFootprintBytes = max(peakFootprintBytes, endFootprintBytes)
        let sortedFrames = frameDurations.map(Self.milliseconds).sorted()
        func percentile(_ fraction: Double) -> Double {
            sortedFrames.isEmpty ? 0 : sortedFrames[min(sortedFrames.count - 1, Int((Double(sortedFrames.count - 1) * fraction).rounded()))]
        }
        let megabyte = 1_048_576.0
        let fields: [(String, String)] = [
            ("platform", PerformanceBenchmarkTests.platformNameForMeasurement), ("scenario", scenario), ("run", "\(run)"),
            ("wall_ms", Self.format(wallMilliseconds)), ("main_cpu_ms", Self.format(mainThreadMilliseconds)), ("cpu_ms", Self.format(processorMilliseconds)),
            ("cpu_share", Self.format(wallMilliseconds > 0 ? processorMilliseconds / wallMilliseconds : 0)),
            ("footprint_start_mb", Self.format(Double(startFootprintBytes) / megabyte)),
            ("footprint_peak_mb", Self.format(Double(peakFootprintBytes) / megabyte)),
            ("footprint_growth_mb", Self.format((Double(peakFootprintBytes) - Double(startFootprintBytes)) / megabyte)),
            ("frames", "\(sortedFrames.count)"), ("frame_median_ms", Self.format(percentile(0.5))),
            ("frame_p95_ms", Self.format(percentile(0.95))), ("frame_max_ms", Self.format(sortedFrames.last ?? 0)),
            ("frames_over_16ms", "\(sortedFrames.filter { frame in frame > 16 }.count)"),
        ]
        print("GRAPHITE-BENCH " + fields.map { name, value in "\(name)=\(value)" }.joined(separator: " "))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func format(_ value: Double) -> String { String(format: "%.2f", value) }
}

extension PerformanceBenchmarkTests {
    nonisolated static var frameIntervalForMeasurement: Duration { frameInterval }
    nonisolated static var platformNameForMeasurement: String { platformName }
}

/// The process's processor time and memory footprint, as Instruments and Xcode's gauges
/// report them.
enum ProcessResourceUsage {
    static func processorSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    }

    /// The main thread's own processor time, which the app's other threads, and on the
    /// simulator the system's, do not blur. Read on the main thread.
    static func mainThreadProcessorSeconds() -> Double {
        var information = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let thread = pthread_mach_thread_np(pthread_self())
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(information.user_time.seconds) + Double(information.user_time.microseconds) / 1_000_000
            + Double(information.system_time.seconds) + Double(information.system_time.microseconds) / 1_000_000
    }

    static func memoryFootprintBytes() -> UInt64 {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        return result == KERN_SUCCESS ? information.phys_footprint : 0
    }
}

@MainActor @Observable
private final class EmbedBenchmarkModel {
    var drawingVersion = 0
}

private struct EmbedBenchmarkContainer: View {
    let model: EmbedBenchmarkModel
    let location: URL

    var body: some View {
        ScrollView {
            EmbeddedPDFViewer(location: location, drawingVersion: model.drawingVersion, openInPane: { _ in })
                .padding()
        }
    }
}

@MainActor @Observable
private final class MapBenchmarkModel {
    var unrelatedCounter = 0
}

private struct MapBenchmarkContainer: View {
    let model: MapBenchmarkModel
    let notes: [PlacedNote]

    var body: some View {
        VStack(spacing: 0) {
            Text("\(model.unrelatedCounter) updates")
            NotesMapView(notes: notes, title: { path in path.stem }, highlightedPath: notes.first?.path, accent: .blue, open: { _ in }, fitRequest: 0)
        }
    }
}
