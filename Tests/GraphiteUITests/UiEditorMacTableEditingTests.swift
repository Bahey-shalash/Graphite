#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// A Live Preview table's cells are edited in place, in its view: each edit the view makes
/// changes only that cell's characters in the note, through the text view so it can be undone,
/// and the view that made it stays (a new one would lose the cell being typed in), though the
/// edit gives the table a new key.
@MainActor
final class UiEditorMacTableEditingTests: XCTestCase {
    private var vaultDirectories: [URL] = []
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        for vaultDirectory in vaultDirectories { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectories = []
        try await super.tearDown()
    }

    private static let tableNote = "Intro line\n\n| Year | Rate |\n| --- | --- |\n| 2024 | 2.0 |\n| 2025 | 1.8 |\n\nAfter the table\n"
    private static var tableLocation: Int { (tableNote as NSString).range(of: "| Year").location }

    private func makeEditor(text: String) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        vaultDirectories.append(vault)
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = .livePreview
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        coordinator.environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = CGSize(width: 32, height: 32)
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        textView.frame.size.width = 700
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView)
    }

    private func blockViews(in textView: NSTextView) -> [NSView] {
        textView.subviews.filter { subview in subview is NSHostingView<AnyView> }
    }

    private func isConcealed(_ location: Int, in textView: NSTextView) -> Bool {
        ((textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.maximumLineHeight ?? 0) == 0.01
    }

    private func waitUntil(timeoutSeconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("Timed out after \(timeoutSeconds) s") }
            windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testEditsFromTheTablesViewChangeOnlyTheirCellsKeepTheViewAndUndo() async throws {
        let (coordinator, textView) = try await makeEditor(text: Self.tableNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        let tableView = try XCTUnwrap(blockViews(in: textView).first)
        let key = try XCTUnwrap(LivePreviewBlockKey.keys(for: LivePreviewBlockScanner.blocks(in: Self.tableNote as NSString)).first)
        let editor = ObjectIdentifier(self)
        coordinator.styling.renderedBlocks.beginEditingInView(blockWithKey: key, at: Self.tableLocation, owner: editor)

        coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: { source in
            MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "2.1", in: source)
        }, in: textView)
        let afterFirstEdit = Self.tableNote.replacingOccurrences(of: "| 2024 | 2.0 |", with: "| 2024 | 2.1 |")
        XCTAssertEqual(textView.string, afterFirstEdit)
        try await waitUntil { self.blockViews(in: textView).count == 1 && self.isConcealed(Self.tableLocation, in: textView) }
        XCTAssertTrue(blockViews(in: textView).first === tableView, "The view that made the edit stays")

        // Made with the key the view had before: the table is found at its place.
        coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: { source in
            MarkdownTableEditing.replacingCell(row: 2, column: 0, with: "2026 | est.", in: source)
        }, in: textView)
        let afterSecondEdit = afterFirstEdit.replacingOccurrences(of: "| 2025 | 1.8 |", with: "| 2026 \\| est. | 1.8 |")
        XCTAssertEqual(textView.string, afterSecondEdit, "A pipe typed in a cell is escaped")
        try await waitUntil { self.blockViews(in: textView).count == 1 && self.isConcealed(Self.tableLocation, in: textView) }
        XCTAssertTrue(blockViews(in: textView).first === tableView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0), "The note's cursor stays where it was")

        coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: { source in
            MarkdownTableEditing.insertingRow(atBodyIndex: 2, in: source)
        }, in: textView)
        XCTAssertEqual(textView.string, afterSecondEdit.replacingOccurrences(of: "| 1.8 |\n", with: "| 1.8 |\n|  |  |\n"))

        let undoManager = try XCTUnwrap(textView.undoManager)
        while undoManager.canUndo, textView.string != Self.tableNote { undoManager.undo() }
        XCTAssertEqual(textView.string, Self.tableNote, "Each edit can be undone")
    }

    func testAnEditThatChangesNothingLeavesTheNoteAlone() async throws {
        let (coordinator, textView) = try await makeEditor(text: Self.tableNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        let key = try XCTUnwrap(LivePreviewBlockKey.keys(for: LivePreviewBlockScanner.blocks(in: Self.tableNote as NSString)).first)
        coordinator.replaceSource(ofBlockWithKey: key, editedBy: ObjectIdentifier(self), using: { _ in nil }, in: textView)
        coordinator.replaceSource(ofBlockWithKey: key, editedBy: ObjectIdentifier(self), using: { source in
            MarkdownTableEditing.replacingCell(row: 0, column: 0, with: "Year", in: source)
        }, in: textView)
        XCTAssertEqual(textView.string, Self.tableNote)
        XCTAssertFalse(textView.undoManager?.canUndo ?? false)
    }

    /// Two identical tables: after an edit of the first, the second takes the key the first
    /// had. Edits from the first table's editor still reach the first table.
    func testAnEditedTableIsFoundAtItsPlaceNotByAKeyAnIdenticalTableTookOver() async throws {
        let table = "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        let note = "Intro\n\n" + table + "\nBetween\n\n" + table + "\nEnd\n"
        let (coordinator, textView) = try await makeEditor(text: note)
        defer { withExtendedLifetime(coordinator) {} }
        try await waitUntil { self.blockViews(in: textView).count == 2 }
        let firstKey = try XCTUnwrap(LivePreviewBlockKey.keys(for: LivePreviewBlockScanner.blocks(in: note as NSString)).first)
        let firstLocation = (note as NSString).range(of: "| A").location
        let editor = ObjectIdentifier(self)
        coordinator.styling.renderedBlocks.beginEditingInView(blockWithKey: firstKey, at: firstLocation, owner: editor)
        coordinator.replaceSource(ofBlockWithKey: firstKey, editedBy: editor, using: { source in
            MarkdownTableEditing.replacingCell(row: 1, column: 0, with: "one", in: source)
        }, in: textView)
        // At once, as Return past the last row does: the stale key now names the second table.
        coordinator.replaceSource(ofBlockWithKey: firstKey, editedBy: editor, using: { source in
            MarkdownTableEditing.insertingRow(atBodyIndex: 1, in: source)
        }, in: textView)
        let editedTable = "| A | B |\n| --- | --- |\n| one | 2 |\n|  |  |\n"
        XCTAssertEqual(textView.string, "Intro\n\n" + editedTable + "\nBetween\n\n" + table + "\nEnd\n")
    }

    /// Text added above a table while its cell is edited moves the table; the editor's next
    /// edits still reach it.
    func testAnEditedTableIsFollowedWhenTextAboveItMovesIt() async throws {
        let (coordinator, textView) = try await makeEditor(text: Self.tableNote)
        defer { withExtendedLifetime(coordinator) {} }
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        let key = try XCTUnwrap(LivePreviewBlockKey.keys(for: LivePreviewBlockScanner.blocks(in: Self.tableNote as NSString)).first)
        let editor = ObjectIdentifier(self)
        coordinator.styling.renderedBlocks.beginEditingInView(blockWithKey: key, at: Self.tableLocation, owner: editor)
        coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: { source in
            MarkdownTableEditing.replacingCell(row: 1, column: 1, with: "2.1", in: source)
        }, in: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("New first line\n", replacementRange: NSRange(location: 0, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        try await waitUntil { self.isConcealed(Self.tableLocation + 15, in: textView) }
        coordinator.replaceSource(ofBlockWithKey: key, editedBy: editor, using: { source in
            MarkdownTableEditing.replacingCell(row: 2, column: 1, with: "1.9", in: source)
        }, in: textView)
        let expected = "New first line\n" + Self.tableNote.replacingOccurrences(of: "| 2024 | 2.0 |", with: "| 2024 | 2.1 |")
            .replacingOccurrences(of: "| 2025 | 1.8 |", with: "| 2025 | 1.9 |")
        XCTAssertEqual(textView.string, expected)
    }

    /// One table's editor ending, as a tap moves editing to another table, leaves the other
    /// table's view kept.
    func testOnlyTheEditorThatBeganLetsTheViewGo() async throws {
        let blocks = LivePreviewRenderedBlocks(detachedViewsBudgetMegabytes: 8)
        let key = try XCTUnwrap(LivePreviewBlockKey.keys(for: LivePreviewBlockScanner.blocks(in: Self.tableNote as NSString)).first)
        let firstEditorObject = NSObject()
        let firstEditor = ObjectIdentifier(firstEditorObject)
        let secondEditorObject = NSObject()
        let secondEditor = ObjectIdentifier(secondEditorObject)
        blocks.beginEditingInView(blockWithKey: key, at: Self.tableLocation, owner: secondEditor)
        blocks.endEditingInView(owner: firstEditor)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(blocks.locationEditedInItsView(by: secondEditor), Self.tableLocation)
        blocks.endEditingInView(owner: secondEditor)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertNil(blocks.locationEditedInItsView(by: secondEditor))
        withExtendedLifetime((firstEditorObject, secondEditorObject)) {}
    }
}
#endif
