#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Page Preview in the Mac editor: the pointer resting on a link to a note asks for its card,
/// in source mode and in Live Preview; moving off the link, typing, scrolling and Escape close
/// it; web links and links written in code ask for none; while Page Preview is off the pointer
/// is not watched.
@MainActor
final class UiEditorMacLinkPreviewsTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        try await super.tearDown()
    }

    private struct Editor {
        let coordinator: NativeMarkdownEditor.Coordinator
        let textView: MarkdownMacTextView
        let cards: LinkPreviewModel
    }

    /// A note's editor connected as `makeNSView` connects it, in a window, with the cursor on
    /// the note's last line and the window's cards.
    private func makeEditor(text: String, mode: EditingMode) async throws -> Editor {
        let vault = try TemporaryVault.make(prefix: "LinkPreviewVault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = mode
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let noteView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        scrollView.frame = noteView.bounds
        noteView.addSubview(scrollView)
        let window = NSWindow(contentRect: noteView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        windows.append(window)
        window.contentView = noteView
        window.showInvisibly()
        window.makeFirstResponder(textView)
        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        if coordinator.linkPreviews.use(cards, sourceNote: notePath) { textView.updateTrackingAreas() }
        textView.layoutSubtreeIfNeeded()
        return Editor(coordinator: coordinator, textView: textView, cards: cards)
    }

    /// The middle of the first character of `substring` in the note, in window coordinates,
    /// found through the text view's own geometry API.
    private func windowPoint(atStartOf substring: String, in textView: MarkdownMacTextView) throws -> CGPoint {
        let range = (textView.string as NSString).range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound, "The note holds “\(substring)”.")
        let screenRect = textView.firstRect(forCharacterRange: NSRange(location: range.location, length: 1), actualRange: nil)
        let windowRect = try XCTUnwrap(textView.window).convertFromScreen(screenRect)
        return CGPoint(x: windowRect.midX, y: windowRect.midY)
    }

    private func movePointer(to windowPoint: CGPoint, in textView: NSTextView) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: windowPoint, modifierFlags: [], timestamp: 0,
                                                     windowNumber: textView.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        textView.mouseMoved(with: event)
    }

    private func waitingRequest(_ cards: LinkPreviewModel) -> LinkPreviewRequest? {
        if case .waiting(let request) = cards.phase { request } else { nil }
    }

    func testThePointerRestingOnALinkAsksForItsCardBesideItAndMovingOffItCancelsIt() async throws {
        let editor = try await makeEditor(text: "See [[Other#Plan]] and more words here.\nLast line\n", mode: .source)
        let onLink = try windowPoint(atStartOf: "Other", in: editor.textView)
        try movePointer(to: onLink, in: editor.textView)

        let request = try XCTUnwrap(waitingRequest(editor.cards))
        XCTAssertEqual(request.target, "Other#Plan")
        XCTAssertTrue(request.isWiki)
        XCTAssertEqual(request.sourceNote, try VaultPath("Note.md"))
        XCTAssertEqual(request.trigger, LinkPreviewTrigger.hover)
        XCTAssertEqual(request.source, LinkPreviewSource.editor)
        XCTAssertTrue(request.anchor.contains(onLink), "The card is placed beside the link under the pointer.")

        try movePointer(to: try windowPoint(atStartOf: "Plan", in: editor.textView), in: editor.textView)
        XCTAssertEqual(waitingRequest(editor.cards), request, "Moving along the link keeps its card coming.")

        try movePointer(to: try windowPoint(atStartOf: "words", in: editor.textView), in: editor.textView)
        guard case .hidden = editor.cards.phase else { return XCTFail("Off the link, its card does not come: \(editor.cards.phase)") }
    }

    func testALinkWhoseMarkupLivePreviewHidesAsksForItsCardOnItsShownText() async throws {
        let editor = try await makeEditor(text: "See [[Other|the other note]] here.\n\nLast line\n", mode: .livePreview)
        try movePointer(to: try windowPoint(atStartOf: "other note", in: editor.textView), in: editor.textView)
        XCTAssertEqual(waitingRequest(editor.cards)?.target, "Other")
    }

    func testAMarkdownLinkToANoteAsksForItsCardAndAWebLinkOrALinkInCodeAsksForNone() async throws {
        let editor = try await makeEditor(text: "A [lecture](Lectures/Week%201.md) and [site](https://example.com).\nCode `[[Other]]` here.\nLast\n", mode: .source)
        try movePointer(to: try windowPoint(atStartOf: "lecture", in: editor.textView), in: editor.textView)
        let request = try XCTUnwrap(waitingRequest(editor.cards))
        XCTAssertEqual(request.target, "Lectures/Week%201.md")
        XCTAssertFalse(request.isWiki)

        try movePointer(to: try windowPoint(atStartOf: "site", in: editor.textView), in: editor.textView)
        guard case .hidden = editor.cards.phase else { return XCTFail("A web link asks for no card.") }
        try movePointer(to: try windowPoint(atStartOf: "Other", in: editor.textView), in: editor.textView)
        guard case .hidden = editor.cards.phase else { return XCTFail("A link written in code is text.") }
    }

    func testTypingScrollingAndEscapeCloseTheCard() async throws {
        let editor = try await makeEditor(text: "See [[Other]] here.\nLast\n", mode: .source)
        let onLink = try windowPoint(atStartOf: "Other", in: editor.textView)

        try movePointer(to: onLink, in: editor.textView)
        XCTAssertNotNil(waitingRequest(editor.cards))
        editor.textView.insertText("x", replacementRange: editor.textView.selectedRange())
        guard case .hidden = editor.cards.phase else { return XCTFail("Typing closes the card.") }

        try movePointer(to: try windowPoint(atStartOf: "here", in: editor.textView), in: editor.textView)
        try movePointer(to: onLink, in: editor.textView)
        XCTAssertNotNil(waitingRequest(editor.cards))
        editor.textView.cancelOperation(nil)
        guard case .hidden = editor.cards.phase else { return XCTFail("Escape closes the card.") }

        try movePointer(to: try windowPoint(atStartOf: "here", in: editor.textView), in: editor.textView)
        try movePointer(to: onLink, in: editor.textView)
        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -20, wheel2: 0, wheel3: 0))
        editor.textView.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
        guard case .hidden = editor.cards.phase else { return XCTFail("Scrolling closes the card.") }
    }

    func testWhilePagePreviewIsOffThePointerIsNotWatched() async throws {
        let editor = try await makeEditor(text: "See [[Other]] here.\nLast\n", mode: .source)
        let watchedAreaCount = editor.textView.trackingAreas.count
        XCTAssertTrue(editor.coordinator.linkPreviews.use(nil, sourceNote: try VaultPath("Note.md")))
        editor.textView.updateTrackingAreas()
        XCTAssertEqual(editor.textView.trackingAreas.count, watchedAreaCount - 1, "The editor's own area for links goes.")
        try movePointer(to: try windowPoint(atStartOf: "Other", in: editor.textView), in: editor.textView)
        guard case .hidden = editor.cards.phase else { return XCTFail("No card is asked for.") }
    }
}
#endif
