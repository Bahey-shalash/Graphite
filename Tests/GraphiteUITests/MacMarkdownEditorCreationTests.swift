#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Creating the Mac note editor puts the note's text and its saved selection (clamped to the
/// text) in the text view before its delegate is set, so creation never records the cursor
/// that setting the text leaves at its end as the note's own.
@MainActor
final class MacMarkdownEditorCreationTests: XCTestCase {
    private var vaultDirectory: URL?
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) } // Best-effort removal of a temporary folder.
        vaultDirectory = nil
        try await super.tearDown()
    }

    private func makeSession(text: String, selection: NSRange) async throws -> MarkdownSession {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("CreationVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        vaultDirectory = vault
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        session.selection = selection
        return session
    }

    private static func textView(in view: NSView) -> MarkdownMacTextView? {
        if let textView = view as? MarkdownMacTextView { return textView }
        for subview in view.subviews {
            if let textView = textView(in: subview) { return textView }
        }
        return nil
    }

    /// The editor SwiftUI makes for `session`, shown in a window; the run loop turns until it exists.
    private func showEditor(for session: MarkdownSession) throws -> MarkdownMacTextView {
        let editor = NativeMarkdownEditor(session: session, configuration: EditorConfiguration(), headingScrollRequest: nil, follow: { _, _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        self.window = window
        window.contentView = NSHostingView(rootView: editor)
        window.orderFront(nil)
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            if let contentView = window.contentView, let textView = Self.textView(in: contentView) { return textView }
            RunLoop.current.run(until: Date.now.addingTimeInterval(0.01))
        }
        throw XCTSkip("SwiftUI did not make the editor within 20 s.")
    }

    func testCreatingTheEditorKeepsTheNotesSavedSelection() async throws {
        let session = try await makeSession(text: "Hello world, this is a note.\n", selection: NSRange(location: 5, length: 0))
        let textView = try showEditor(for: session)
        XCTAssertEqual(textView.string, "Hello world, this is a note.\n")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(session.selection, NSRange(location: 5, length: 0), "Creation must not record the end-of-text cursor as the note's.")
    }

    func testCreatingTheEditorKeepsASavedRangeSelection() async throws {
        let session = try await makeSession(text: "Hello world, this is a note.\n", selection: NSRange(location: 6, length: 5))
        let textView = try showEditor(for: session)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 5))
        XCTAssertEqual(session.selection, NSRange(location: 6, length: 5))
    }

    func testASavedSelectionPastTheEndOfTheTextIsClamped() async throws {
        let text = "Short\n"
        let session = try await makeSession(text: text, selection: NSRange(location: 500, length: 3))
        let textView = try showEditor(for: session)
        let textLength = (text as NSString).length
        XCTAssertEqual(textView.selectedRange(), NSRange(location: textLength, length: 0))
        XCTAssertEqual(session.selection, NSRange(location: 500, length: 3), "The text view clamps its own selection; the note's saved one is not rewritten by creation.")
    }

    func testASavedRangeReachingPastTheEndKeepsItsStartAndEndsAtTheEnd() async throws {
        let text = "Short note\n"
        let session = try await makeSession(text: text, selection: NSRange(location: 6, length: 100))
        let textView = try showEditor(for: session)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: (text as NSString).length - 6))
    }
}
#endif
