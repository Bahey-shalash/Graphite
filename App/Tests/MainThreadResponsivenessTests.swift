#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import PencilKit
import os
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The scenes the owner's iPad froze in, kept responsive: a long note read aloud in the
/// reading view, and a PDF written on in a narrow window while it is read aloud. Each one
/// watches the main thread from another thread, counts how often the main run loop wakes
/// once nothing changes, and listens for SwiftUI's own warnings of update loops.
@MainActor
final class MainThreadResponsivenessTests: XCTestCase {
    private var window: UIWindow?
    private var directory: URL?
    private var workspace: WorkspaceModel?
    private var savedSpeed = 1.0

    override func tearDown() async throws {
        workspace?.readAloud.clear()
        workspace?.readAloud.session.setSpeed(savedSpeed)
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        workspace = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    /// A long note, as a conversation pasted into a note: headings, lists, math and many
    /// paragraphs, about 400 KB.
    static let longNote: String = {
        let paragraph = "What this paper wants to explore is whether the DRAM's analog behavior lets you combine **many inputs at once**, which could reduce the number of steps significantly -- the paper's *problem statement*. "
        var note = "---\ntitle: Functionally complete DRAM\ntags:\n  - reading\n---\n# Functionally complete Boolean logic\n\n"
        for section in 1...220 {
            note += "## Part \(section)\n\n"
            note += String(repeating: paragraph, count: 3) + "\n\n"
            note += "1. Prior COTS DRAM logic is **not functionally complete**.\n2. Prior COTS DRAM logic is limited to *small input counts*.\n\n"
            note += "$$(((A_1 \\wedge A_2) \\wedge A_3) \\wedge \\cdots) \\wedge A_{16}$$\n\n"
            note += String(repeating: paragraph, count: 2) + "\n\n"
        }
        return note
    }()

    /// The main thread held for three seconds: the watchdog writes a record while it is held,
    /// with where the main thread was, and another once it answers.
    func testAMainThreadStallLeavesARecordWithWhereTheMainThreadWas() async throws {
        try XCTSkipIf(MainThreadWatchdog.isDebuggerAttached, "Under a debugger the watchdog does not run.")
        MainThreadWatchdog.shared.start()
        let before = records(named: "MainThreadStall")
        // The main thread stays blocked until the watchdog, which runs on a thread of its own, has
        // written its record: how soon it does depends on the machine, so no fixed time is used.
        let stallDeadline = ContinuousClock.now + .seconds(60)
        while records(named: "MainThreadStall-").subtracting(before).isEmpty, ContinuousClock.now < stallDeadline { usleep(50_000) }
        try await waitUntil("the record says when the stall ended") { !self.records(named: "MainThreadStallEnded-").subtracting(before).isEmpty }
        DiagnosticRecords.waitForPendingWrites()
        let stallRecords = records(named: "MainThreadStall-").subtracting(before)
        XCTAssertEqual(stallRecords.count, 1, "One record of the stall.")
        let stallText = try stallRecords.first.map { record in try String(contentsOf: record, encoding: .utf8) } ?? ""
        XCTAssertTrue(stallText.contains("mainThreadFrames"), stallText)
        XCTAssertTrue(stallText.contains("libsystem_kernel.dylib"), "The main thread was asleep in the kernel: \(stallText)")
        XCTAssertTrue(stallText.contains("\"uuid\""), "Images are listed for symbolication.")
        XCTAssertFalse(records(named: "MainThreadStallEnded-").subtracting(before).isEmpty, "A record says when it ended.")
    }

    /// The processor time the main thread has used, in nanoseconds; call on the main thread.
    private static func mainThreadProcessorNanoseconds() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    }

    private func records(named prefix: String) -> Set<URL> {
        guard let folder = DiagnosticRecords.folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return Set(files.filter { file in file.lastPathComponent.hasPrefix(prefix) })
    }

    /// A long note in the reading view, read aloud: each word read updates the view, and an
    /// update of a 0.8 MB note takes no longer than the budget. The view hashed the whole
    /// note at every update; the owner's iPad was found doing that when the system ended a
    /// frozen Graphite (2026-10-12).
    func testALongNoteInTheReadingViewUpdatesQuicklyAsEachWordIsRead() async throws {
        let folder = try makeDirectory()
        let index = try VaultIndex(databaseURL: folder.appendingPathComponent("index.sqlite"))
        let source = String(repeating: Self.longNote, count: 3)
        XCTAssertGreaterThan(source.utf8.count, 750_000)
        let reading = ReadingRangeModel()
        let path = try VaultPath("Long.md")
        // The word is given as the note's pane gives it: read only inside the reading view.
        let controller = UIHostingController(rootView: AnyView(
            MarkdownPreview(source: source, path: path, root: folder, index: index, configuration: ReadingConfiguration(),
                            headingScrollRequest: .constant(nil), handledScrollToken: .constant(nil), navigate: { _, _ in },
                            openPDF: { _, _ in }, updateProperties: nil, readingWord: ReadingWordSource { reading.range })
        ))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        try await waitUntil(timeoutSeconds: 30) {
            self.descendants(of: controller.view, matching: UIScrollView.self).contains { scrollView in scrollView.contentSize.height > 5_000 }
        }
        try await Task.sleep(for: .seconds(1))
        // The main thread's own time, with the view left alone and while words are read at
        // twenty a second, faster than any voice: what each word costs is the difference.
        let wordCount = 60
        let interval = Duration.milliseconds(50)
        let idleStart = Self.mainThreadProcessorNanoseconds()
        try await Task.sleep(for: interval * wordCount)
        let idleNanoseconds = Self.mainThreadProcessorNanoseconds() - idleStart
        let readingStart = Self.mainThreadProcessorNanoseconds()
        for wordIndex in 0..<wordCount {
            reading.range = NSRange(location: 200 + wordIndex * 6, length: 5)
            try await Task.sleep(for: interval)
        }
        let readingNanoseconds = Self.mainThreadProcessorNanoseconds() - readingStart
        let millisecondsPerWord = Double(Int64(readingNanoseconds) - Int64(idleNanoseconds)) / Double(wordCount) / 1_000_000
        print("Reading view update per word: \(millisecondsPerWord) ms of the main thread")
        // Under 1 millisecond in a Debug build on the simulator; 19 with the word given to
        // the whole view, and 900 with every block of the note made at once.
        XCTAssertLessThan(millisecondsPerWord, 8, "Each word read costs the main thread less than the budget.")
    }

    /// The same note read aloud for real in the workspace's reading view, with the words
    /// highlighted and followed: the main thread stays mostly free.
    func testALongNoteReadAloudInTheReadingViewLeavesTheMainThreadMostlyFree() async throws {
        try TimingBudgets.requireTheOwnersDevice()
        let source = String(repeating: Self.longNote, count: 3)
        let workspace = try await makeWorkspace(notes: ["Long.md": source])
        await workspace.open(try VaultPath("Long.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .reading
        _ = try host(workspace, size: CGSize(width: 834, height: 1194))
        try await Task.sleep(for: .seconds(3))
        workspace.readAloud.readMarkdown(session.text, path: session.path)
        try await waitUntil(timeoutSeconds: 30) { workspace.readAloud.highlight(in: session.path) != nil }
        try await Task.sleep(for: .seconds(1))
        var ranges = Set<Int>()
        let measuredSeconds = 6.0
        let start = Self.mainThreadProcessorNanoseconds()
        let deadline = Date().addingTimeInterval(measuredSeconds)
        while Date() < deadline {
            if let range = workspace.readAloud.highlight(in: session.path) { ranges.insert(range.location) }
            try await Task.sleep(for: .milliseconds(20))
        }
        let busyFraction = Double(Self.mainThreadProcessorNanoseconds() - start) / (measuredSeconds * 1_000_000_000)
        print("Long note read aloud: main thread busy \(Int(busyFraction * 100)) %, \(ranges.count) words highlighted")
        XCTAssertGreaterThan(ranges.count, 5, "Reading went on.")
        // 3 % here; 20 % with the word given to the whole view.
        XCTAssertLessThan(busyFraction, 0.12, "The main thread stays nearly free while a long note is read.")
    }

    /// A PDF's view built again and again, as switching tabs does: each view's Pencil
    /// palette and coordinator go with it. Every palette left behind made each of the PDF's
    /// updates ask all of them about the first responder (`PKToolPicker._toolPickersForWindow`
    /// under `updateToolPickerVisibility` in a 0x8BADF00D report, 2026-10-12).
    func testPDFViewsBuiltAgainLetGoOfTheirPalettes() async throws {
        let folder = try makeDirectory()
        let location = folder.appendingPathComponent("Paper.pdf")
        try Self.writeLecturePDF(to: location, pageCount: 3)
        let session = try await PDFSession.open(location)
        session.isWriting = true
        let controller = UIHostingController(rootView: AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 834, height: 1194)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        weak var firstPalette: PKToolPicker?
        weak var firstCoordinator: PDFAnnotationCoordinator?
        for round in 0..<6 {
            try await waitUntil { (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator != nil && session.pdfView?.window != nil }
            if round == 0 {
                firstCoordinator = (session.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator
                firstPalette = firstCoordinator?.toolPicker
            }
            try await Task.sleep(for: .milliseconds(300))
            controller.rootView = AnyView(Text("Another tab"))
            try await waitUntil { session.pdfView?.window == nil }
            try await Task.sleep(for: .milliseconds(100))
            controller.rootView = AnyView(NavigationStack { PDFPane(session: session, resolveConflict: { _ in }) })
        }
        try await Task.sleep(for: .seconds(1))
        XCTAssertNil(firstCoordinator, "The first view's coordinator went with its view.")
        XCTAssertNil(firstPalette, "The first view's palette went with its view.")
    }

    /// A PDF written on in a window beside another app while it is read aloud, with the
    /// floating player, as on the owner's iPad: SwiftUI reports no update cycle, and the
    /// main thread never stops answering for long.
    func testAPDFReadAloudWhileWrittenOnInANarrowWindowMakesNoUpdateCycle() async throws {
        let folder = try makeDirectory()
        try Self.writeLecturePDF(to: folder.appendingPathComponent("Paper.pdf"), pageCount: 17)
        let workspace = try await makeWorkspace(notes: ["Untitled.md": "Notes\n"], folder: folder)
        await workspace.open(try VaultPath("Untitled.md"))
        await workspace.open(try VaultPath("Paper.pdf"), placement: .newTab)
        let pdf = try XCTUnwrap(workspace.pdfSession)
        pdf.isWriting = true
        _ = try host(workspace, size: CGSize(width: 507, height: 1194))
        try await waitUntil { pdf.pdfView?.window != nil }
        // Listened to once the test's window has settled: building this window in a hosted
        // test, beside the app's own, prints SwiftUI cycle warnings in some full runs, which
        // the app's own window opening the same PDF does not (2026-10-13).
        try await Task.sleep(for: .seconds(1))
        let warnings = SwiftUIWarningCapture()
        warnings.start()
        defer { warnings.stop() }
        let probe = MainThreadProbe()
        probe.start()
        workspace.readAloud.readPDF(pdf, firstPageIndex: 0, lastPageIndex: pdf.pageCount - 1)
        try await waitUntil(timeoutSeconds: 20) { workspace.readAloudNavigator.highlightFrameInWindow != nil }
        try await Task.sleep(for: .seconds(5))
        let measurement = probe.stop()
        workspace.readAloud.clear()
        print("PDF read aloud while written on, 507 points wide: \(measurement), \(warnings.summary)")
        XCTAssertEqual(warnings.count(of: SwiftUIWarningCapture.cycleMarker), 0, "SwiftUI found no update cycle.")
        XCTAssertLessThan(measurement.longestUnansweredSeconds, 1, "The main thread kept answering.")
    }

    // MARK: Helpers

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { subview in (subview as? View).map { [$0] } ?? [] } + parent.subviews.flatMap { subview in descendants(of: subview, matching: type) }
    }

    static func writeLecturePDF(to location: URL, pageCount: Int) throws {
        let text = String(repeating: "Processing-using-DRAM is an emerging paradigm that leverages the analog operational properties of DRAM circuitry to enable massively parallel in-DRAM computation. ", count: 18)
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: location) { context in
            for _ in 0..<pageCount {
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 50, y: 50, width: 512, height: 692), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            }
        }
    }

    private func makeDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Responsiveness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder
        return folder
    }

    private func makeWorkspace(notes: [String: String], folder: URL? = nil) async throws -> WorkspaceModel {
        let folder = try folder ?? makeDirectory()
        for (name, text) in notes { try Data(text.utf8).write(to: folder.appendingPathComponent(name)) }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: folder)
        workspace.store = VaultStore(root: folder)
        let index = try VaultIndex(databaseURL: folder.appendingPathComponent("index.sqlite"))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { name in name.hasSuffix(".md") || name.hasSuffix(".pdf") }
        try await index.refresh(paths: names.map { name in try VaultPath(name) }, root: folder)
        workspace.index = index
        savedSpeed = workspace.readAloud.session.speed
        workspace.readAloud.session.setSpeed(2)
        self.workspace = workspace
        return workspace
    }

    private func host(_ workspace: WorkspaceModel, size: CGSize) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(ZStack {
            NavigationStack {
                WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
            }
            ReadAloudFloatingPlayer(reader: workspace.readAloud, navigator: workspace.readAloudNavigator)
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

}

/// The word being read, which a test changes as Read Aloud would.
@MainActor @Observable
final class ReadingRangeModel {
    var range: NSRange?
}

/// Watches the main thread from another thread: the longest it took to answer, and how many
/// times its run loop woke up.
final class MainThreadProbe: @unchecked Sendable {
    struct Measurement: CustomStringConvertible {
        let longestUnansweredSeconds: Double
        let runLoopWakeUps: Int
        let elapsedSeconds: Double
        var wakeUpsPerSecond: Double { Double(runLoopWakeUps) / max(elapsedSeconds, 0.001) }
        var description: String {
            String(format: "longest stall %.0f ms, %.0f wake-ups/s", longestUnansweredSeconds * 1000, wakeUpsPerSecond)
        }
    }

    private struct State {
        var pingSentAt: Double?
        var longestUnanswered = 0.0
        var wakeUps = 0
        var isRunning = true
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var observer: CFRunLoopObserver?
    private var startedAt = 0.0

    @MainActor func start() {
        startedAt = CFAbsoluteTimeGetCurrent()
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, 0) { [state] _, _ in
            state.withLock { state in state.wakeUps += 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
        let thread = Thread { [state] in
            while state.withLock({ state in state.isRunning }) {
                let now = CFAbsoluteTimeGetCurrent()
                let shouldPing: Bool = state.withLock { state in
                    if let sentAt = state.pingSentAt {
                        state.longestUnanswered = max(state.longestUnanswered, now - sentAt)
                        return false
                    }
                    state.pingSentAt = now
                    return true
                }
                if shouldPing {
                    DispatchQueue.main.async { [state] in
                        let answeredAt = CFAbsoluteTimeGetCurrent()
                        state.withLock { state in
                            if let sentAt = state.pingSentAt { state.longestUnanswered = max(state.longestUnanswered, answeredAt - sentAt) }
                            state.pingSentAt = nil
                        }
                    }
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        thread.start()
    }

    @MainActor func stop() -> Measurement {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt
        return state.withLock { state in
            state.isRunning = false
            // The wake-ups the probe's own pings cause are not counted against the app.
            return Measurement(longestUnansweredSeconds: state.longestUnanswered, runLoopWakeUps: state.wakeUps, elapsedSeconds: elapsed)
        }
    }
}

/// Listens to the process's standard error, where the simulator copies the system log, for
/// SwiftUI's warnings of views that update themselves without end.
final class SwiftUIWarningCapture: @unchecked Sendable {
    static let cycleMarker = "Cycle detected through attribute"
    static let repeatedUpdateMarker = "tried to update multiple times per frame"

    private let pipe = Pipe()
    private var savedStandardError: Int32 = -1
    private let captured = OSAllocatedUnfairLock(initialState: "")

    func start() {
        savedStandardError = dup(STDERR_FILENO)
        let savedDescriptor = savedStandardError
        pipe.fileHandleForReading.readabilityHandler = { [captured] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            // Still shown in the test log.
            chunk.withUnsafeBytes { bytes in _ = write(savedDescriptor, bytes.baseAddress, bytes.count) }
            let text = String(decoding: chunk, as: UTF8.self)
            captured.withLock { captured in captured += text }
        }
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
    }

    func stop() {
        guard savedStandardError >= 0 else { return }
        fflush(stderr)
        dup2(savedStandardError, STDERR_FILENO)
        close(savedStandardError)
        savedStandardError = -1
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    func count(of marker: String) -> Int {
        captured.withLock { captured in captured.components(separatedBy: marker).count - 1 }
    }

    var summary: String {
        "cycles \(count(of: Self.cycleMarker)), repeated updates \(count(of: Self.repeatedUpdateMarker))"
    }
}
#endif
