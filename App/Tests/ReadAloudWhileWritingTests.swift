#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import PencilKit
import Vision
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Reading aloud while writing: ink never stops or shifts reading, handwriting is never
/// read, and a note edited while it is read goes on at the same sentence.
@MainActor
final class ReadAloudWhileWritingTests: XCTestCase {
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

    private static let pages = [
        "Static CMOS logic keeps its output at a full level. The noise margin tells how much disturbance it tolerates before a gate flips.",
        "Dynamic logic stores its value as charge on a node, which leaks away over time unless the clock refreshes it."
    ]

    /// Reads a PDF range while a pen stroke, a highlighter stroke and an erase are made and
    /// the PDF is saved: reading is never interrupted, the words read are the same as
    /// without ink, and the highlight keeps moving on.
    func testInkAndSavesWhileReadingAPDFRangeChangeNothingRead() async throws {
        let (workspace, pdf) = try await openPDF()
        let reader = workspace.readAloud
        let start = PDFReadAloudEndpoint(pageIndex: 0, offset: 0, revision: pdf.readingTextVersion)
        let endText = try XCTUnwrap(pdf.document.page(at: 1)?.string) as NSString
        let end = PDFReadAloudEndpoint(pageIndex: 1, offset: endText.range(of: "time").location + 4, revision: pdf.readingTextVersion)

        // Without ink: the passages read on each page.
        let baseline = try await readRange(reader, pdf: pdf, start: start, end: end, whileReading: nil)

        // With ink, a highlighter, an erase and a save while it reads.
        pdf.isWriting = true
        let page = try XCTUnwrap(pdf.document.page(at: 0))
        let coordinator = try await annotationCoordinator(of: pdf)
        try await waitUntil { coordinator.editingCanvas(for: page) != nil }
        let canvas = try XCTUnwrap(coordinator.editingCanvas(for: page))
        let versionBefore = pdf.changeVersion
        var actions: [@MainActor () async throws -> Void] = [
            { canvas.drawing = PKDrawing(strokes: [self.stroke(.pen, atHeight: 120)]) },
            { canvas.drawing = PKDrawing(strokes: canvas.drawing.strokes + [self.stroke(.marker, atHeight: 160)]) },
            { canvas.drawing = PKDrawing(strokes: Array(canvas.drawing.strokes.dropFirst())) },
            { try await pdf.save() },
        ]
        // Each change is made once the highlight has moved on two words since the last one.
        var wordsAfterInk: [String] = []
        var hasStarted = false
        let withInk = try await readRange(reader, pdf: pdf, start: start, end: end) { word in
            if let word, wordsAfterInk.last != word { wordsAfterInk.append(word) }
            if !actions.isEmpty, hasStarted ? wordsAfterInk.count >= 3 : word != nil {
                hasStarted = true
                try await actions.removeFirst()()
                wordsAfterInk = word.map { [$0] } ?? []
            }
        }
        XCTAssertTrue(actions.isEmpty, "Every ink action was made while reading.")
        XCTAssertGreaterThan(pdf.changeVersion, versionBefore, "The ink changed the PDF.")
        XCTAssertEqual(pdf.readingTextVersion, start.revision, "Ink is not a change to the text read.")
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(withInk, baseline, "The same passages were read, in the same order.")
        XCTAssertGreaterThan(wordsAfterInk.count, 1, "The highlight kept moving after the last change.")
    }

    /// A scanned page with handwriting across it: the handwriting is not in the text read.
    func testHandwritingOnAScannedPageIsNotRead() async throws {
        let folder = try makeDirectory()
        let location = folder.appendingPathComponent("Scan.pdf")
        // A page that is only a picture of printed words, as a scanner makes it.
        let pageSize = CGSize(width: 612, height: 792)
        let picture = UIGraphicsImageRenderer(size: pageSize).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
            ("Memory cells store charge\nRefresh keeps them alive" as NSString)
                .draw(in: CGRect(x: 60, y: 80, width: 500, height: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 34)])
        }
        let document = PDFDocument()
        let page = try XCTUnwrap(PDFPage(image: picture))
        document.insert(page, at: 0)
        // Handwriting across the page: the letters BAI as ink strokes.
        let ink = PDFAnnotation(bounds: page.bounds(for: .mediaBox), forType: .ink, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = 7
        ink.border = border
        ink.color = .black
        for path in Self.letterPaths("BAI", at: CGPoint(x: 80, y: 360), size: 160) { ink.add(path) }
        page.addAnnotation(ink)
        XCTAssertTrue(document.write(to: location))

        // The handwriting is legible: recognition of the page as shown, with its ink, reads it.
        let shown = try XCTUnwrap(PDFDocument(url: location)?.page(at: 0)).thumbnail(of: CGSize(width: 1224, height: 1584), for: .mediaBox)
        let shownText = try await recognizedText(in: try XCTUnwrap(shown.cgImage))
        XCTAssertTrue(shownText.uppercased().contains("BAI"), "Control: the ink is legible to recognition (\(shownText)).")

        let pdf = try await PDFSession.open(location)
        let reader = ReadAloudController()
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 0)
        try await waitUntil(timeoutSeconds: 30) { !reader.isPreparing }
        let recognized = try XCTUnwrap(reader.recognizedPDFPage?.text, String(describing: reader.errorMessage))
        XCTAssertTrue(recognized.contains("Memory") && recognized.contains("Refresh"), recognized)
        XCTAssertFalse(recognized.uppercased().contains("BAI"), "The handwriting was read: \(recognized)")
        reader.clear()
    }

    /// A note edited while it is read, above and inside the sentence read: reading goes on
    /// at the same sentence. Removing that sentence pauses reading and says so.
    func testANoteEditedWhileReadGoesOnAtTheSameSentence() async throws {
        var note = "# Memory\n\n"
        for number in 1...8 { note += "## Part \(number)\n\nSentence \(number) begins here. It explains part \(number) of the memory in some detail.\n\n" }
        let workspace = try await makeWorkspace(notes: ["Note.md": note], extraFiles: [:])
        await workspace.open(try VaultPath("Note.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        _ = try host(workspace)
        let reader = workspace.readAloud
        reader.readMarkdown(session.text, path: session.path)
        try await waitUntil(timeoutSeconds: 15) { reader.session.document != nil && !reader.isPreparing }
        let document = try XCTUnwrap(reader.session.document)
        let index = try XCTUnwrap(document.passages.firstIndex { passage in passage.text.hasPrefix("Sentence 5") })
        reader.session.move(to: index)
        reader.session.play()
        try await waitUntil { reader.session.state == .speaking }
        let passageBefore = try XCTUnwrap(reader.session.currentPassage?.text)

        // An edit above: a paragraph added at the top.
        session.text = "An added paragraph at the top.\n\n" + session.text
        try await waitUntil(timeoutSeconds: 5) { !reader.isReanchoringNote && reader.session.state == .speaking }
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.currentPassage?.text, passageBefore, "Reading went on in the same passage.")
        // The highlight comes back with the next word spoken.
        try await waitUntil(timeoutSeconds: 5) { reader.highlight(in: session.path) != nil }
        let highlighted = try XCTUnwrap(reader.highlight(in: session.path))
        XCTAssertTrue((session.text as NSString).substring(with: highlighted).count > 0)
        let passageSource = (session.text as NSString).range(of: "Sentence 5 begins here.")
        XCTAssertTrue(NSLocationInRange(highlighted.location, NSRange(location: passageSource.location, length: 200)),
                      "The highlight is in the same sentence after the edit: \(highlighted) vs \(passageSource)")

        // An edit at the other end of the sentence read keeps its start.
        session.text = session.text.replacingOccurrences(of: "part 5 of the memory in some detail.", with: "part 5 of the memory briefly.")
        try await waitUntil(timeoutSeconds: 5) { !reader.isReanchoringNote }
        XCTAssertNil(reader.errorMessage)
        XCTAssertTrue(reader.session.currentPassage?.text.hasPrefix("Sentence 5 begins here.") ?? false,
                      String(describing: reader.session.currentPassage?.text))

        // The passage removed altogether: reading pauses and says why.
        session.text = session.text.replacingOccurrences(of: "Sentence 5 begins here. It explains part 5 of the memory briefly.", with: "")
        try await waitUntil(timeoutSeconds: 5) { !reader.isReanchoringNote }
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertNotEqual(reader.session.state, .speaking)
    }

    // MARK: Helpers

    /// Reads the range to its end; returns the passages of each page read, in order.
    /// `whileReading` is called with the word highlighted on the page, every 60 ms.
    private func readRange(_ reader: ReadAloudController, pdf: PDFSession, start: PDFReadAloudEndpoint, end: PDFReadAloudEndpoint,
                           whileReading: ((String?) async throws -> Void)?) async throws -> [[String]] {
        reader.readPDFRange(pdf, start: start, end: end)
        var pagesRead: [[String]] = []
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if let passages = reader.session.document?.passages.map(\.text), pagesRead.last != passages { pagesRead.append(passages) }
            XCTAssertNil(reader.errorMessage, "Reading was interrupted: \(String(describing: reader.errorMessage))")
            if reader.errorMessage != nil { break }
            if reader.session.state == .finished, !reader.isPreparing, reader.sourcePageIndex == 1 { break }
            if let whileReading {
                let word = pdf.pdfView?.highlightedSelections?.compactMap(\.string).joined(separator: " ")
                try await whileReading(word?.isEmpty == false ? word : nil)
            }
            try await Task.sleep(for: .milliseconds(60))
        }
        XCTAssertEqual(reader.session.state, .finished, "The range was read to its end.")
        return pagesRead
    }

    private func openPDF() async throws -> (WorkspaceModel, PDFSession) {
        let folder = try makeDirectory()
        let location = folder.appendingPathComponent("Lecture.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: location) { context in
            for text in Self.pages {
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 60, y: 80, width: 480, height: 600), withAttributes: [.font: UIFont.systemFont(ofSize: 22)])
            }
        }
        let workspace = try await makeWorkspace(notes: [:], extraFiles: [:], folder: folder)
        await workspace.open(try VaultPath("Lecture.pdf"))
        let pdf = try XCTUnwrap(workspace.pdfSession)
        _ = try host(workspace)
        try await waitUntil { pdf.pdfView != nil }
        return (workspace, pdf)
    }

    private func annotationCoordinator(of pdf: PDFSession) async throws -> PDFAnnotationCoordinator {
        try await waitUntil { (pdf.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator != nil }
        return try XCTUnwrap((pdf.pdfView as? GraphitePDFDisplayView)?.annotationCoordinator)
    }

    private var strokeCount = 0

    private func stroke(_ inkType: PKInk.InkType, atHeight height: CGFloat) -> PKStroke {
        strokeCount += 1
        let points = (0...20).map { pointIndex in
            PKStrokePoint(location: CGPoint(x: CGFloat(60 + pointIndex * 20), y: height), timeOffset: Double(pointIndex) / 20,
                          size: CGSize(width: 6, height: 6), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(inkType, color: inkType == .marker ? .systemYellow : .black),
                        path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(strokeCount))))
    }

    /// The outlines of letters in a bold font, as paths in page space (y up), for ink.
    private static func letterPaths(_ letters: String, at origin: CGPoint, size: CGFloat) -> [UIBezierPath] {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        var characters = Array(letters.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        var x = origin.x
        var paths: [UIBezierPath] = []
        for (glyph, advance) in zip(glyphs, advances) {
            var transform = CGAffineTransform(translationX: x, y: origin.y)
            if let outline = CTFontCreatePathForGlyph(font, glyph, &transform) { paths.append(UIBezierPath(cgPath: outline)) }
            x += advance.width
        }
        return paths
    }

    private func recognizedText(in image: CGImage) async throws -> String {
        let request = RecognizeTextRequest()
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in observation.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func makeDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudWhileWriting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directory = folder
        return folder
    }

    private func makeWorkspace(notes: [String: String], extraFiles: [String: Data], folder: URL? = nil) async throws -> WorkspaceModel {
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

}
#endif
