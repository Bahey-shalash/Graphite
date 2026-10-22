#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Suggestions in the Mac editor, as on the iPad: links after `[[`, and what community
/// plugins suggest elsewhere, shown at the cursor, chosen with the arrow keys and Return,
/// closed with Escape or when the note loses keyboard focus.
@MainActor
final class UiEditorMacSuggestionsTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        try await super.tearDown()
    }

    /// A note's editor connected as `makeNSView` connects it, in a window, with keyboard focus.
    private func makeFocusedEditor(text: String) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = try TemporaryVault.make(prefix: "Vault", for: self).root
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .source
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
        return (coordinator, textView)
    }

    /// One suggestion whose edit replaces what was typed after `[[` with `name]]`.
    private func linkSuggestion(_ name: String) -> CompletionItem {
        CompletionItem(id: name, title: name, systemImage: "doc.text") { context in
            guard case .link(let query) = context else { return [] }
            let replacement = name + "]]"
            return [MarkdownTextEdit(range: query.replacementRange, replacement: replacement,
                                     selectionAfter: NSRange(location: query.replacementRange.location + replacement.utf16.count, length: 0))]
        }
    }

    private func press(_ characters: String, keyCode: UInt16, in textView: NSTextView) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: textView.window?.windowNumber ?? 0, context: nil,
                                                   characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        textView.keyDown(with: event)
    }

    private static let returnKeyCode: UInt16 = 36
    private static let escapeKeyCode: UInt16 = 53
    private static let downArrowKeyCode: UInt16 = 125

    func testTypingALinkShowsSuggestionsAtTheCursorAndReturnInsertsTheChosenOne() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "See ")
        let session = coordinator.session
        session.completion.provider = { _ in [self.linkSuggestion("Mechanics"), self.linkSuggestion("Optics")] }
        textView.insertText("[[", replacementRange: textView.selectedRange())
        try await waitUntil("the suggestions show") { session.completion.isVisible }
        guard case .link = session.completion.context else {
            return XCTFail("A link is suggested after [[, not \(String(describing: session.completion.context)).")
        }
        let caret = session.completion.caretRect
        XCTAssertGreaterThan(caret.height, 0, "The suggestions are placed at the cursor.")
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 600, height: 400).contains(caret.origin), "\(caret) is inside the note, from its top left.")
        XCTAssertLessThan(caret.minY, 200, "The cursor is on the first line, at the top of the note: \(caret).")

        try press(String(UnicodeScalar(NSDownArrowFunctionKey)!), keyCode: Self.downArrowKeyCode, in: textView)
        XCTAssertEqual(session.completion.selectedIndex, 1, "The down arrow moves through the suggestions.")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 0), "The cursor stays where it was.")
        try press("\r", keyCode: Self.returnKeyCode, in: textView)
        try await waitUntil("the chosen link is inserted") { textView.string == "See [[Optics]]" }
        XCTAssertFalse(session.completion.isVisible)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 14, length: 0))
        XCTAssertEqual(session.text, "See [[Optics]]")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "See [[", "Undo takes the suggestion back.")
    }

    func testEscapeClosesTheSuggestionsAndReturnThenStartsANewLine() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "See ")
        let session = coordinator.session
        session.completion.provider = { _ in [self.linkSuggestion("Mechanics")] }
        textView.insertText("[[Me", replacementRange: textView.selectedRange())
        try await waitUntil("the suggestions show") { session.completion.isVisible }
        try press("\u{1b}", keyCode: Self.escapeKeyCode, in: textView)
        XCTAssertFalse(session.completion.isVisible)
        try press("\r", keyCode: Self.returnKeyCode, in: textView)
        XCTAssertEqual(textView.string, "See [[Me\n", "With the suggestions closed, Return is Return.")
    }

    func testSuggestionsCloseWhenTheNoteLosesKeyboardFocus() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "See ")
        let session = coordinator.session
        session.completion.provider = { _ in [self.linkSuggestion("Mechanics")] }
        textView.insertText("[[", replacementRange: textView.selectedRange())
        try await waitUntil("the suggestions show") { session.completion.isVisible }
        textView.window?.makeFirstResponder(nil)
        XCTAssertFalse(session.completion.isVisible)
        XCTAssertNil(session.completion.context)
    }

    func testPluginsHearEachChangeAndCursorMoveOnceAndTheirSuggestionsShow() async throws {
        let (coordinator, textView) = try await makeFocusedEditor(text: "Mood ")
        let session = coordinator.session
        var heardCursors: [Int] = []
        coordinator.actions.pluginEditorDidChange = {
            heardCursors.append(textView.selectedRange().location)
            return heardCursors.count
        }
        session.completion.provider = { context in
            guard case .pluginSuggestion = context else { return [] }
            return [CompletionItem(id: "smile", title: "😄 smile", systemImage: "puzzlepiece.extension") { _ in [] }]
        }
        textView.insertText(":", replacementRange: textView.selectedRange())
        XCTAssertEqual(heardCursors, [6], "Plugins hear the change, as in Obsidian's editor (editor-change).")
        XCTAssertEqual(session.completion.context, .pluginSuggestion(revision: 1))
        try await waitUntil("the plugins' suggestions show") { session.completion.items.map(\.title) == ["😄 smile"] }

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertEqual(heardCursors, [6, 2], "Plugins hear the cursor move.")
        coordinator.updateCompletion(in: textView)
        XCTAssertEqual(heardCursors, [6, 2], "Asked again for the same change and cursor, as scrolling does, plugins are not asked twice.")
        XCTAssertEqual(session.completion.context, .pluginSuggestion(revision: 2))
    }
}
#endif
