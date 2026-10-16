#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The Mac's Live Preview draws a note's properties over their concealed YAML, as Obsidian
/// shows them above the note, and keeps the cursor out of the YAML it does not draw.
@MainActor
final class UiEditorMacPropertiesTests: XCTestCase {
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

    private static let noteText = "---\ntitle: Tokyo\ntags:\n  - travel\n---\nBody text\n"
    private static var propertiesEnd: Int { (noteText as NSString).range(of: "Body").location }

    /// A text view in a window, connected to a coordinator the way `makeNSView` connects it.
    private func makeEditor(text: String = noteText, mode: EditingMode = .livePreview,
                            showsProperties: Bool = true) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView) {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        vaultDirectories.append(vault)
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        var configuration = EditorConfiguration()
        configuration.mode = mode
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        coordinator.environment = LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in },
                                                         updateProperties: showsProperties ? { [session] properties in session.replaceProperties(properties) } : nil)
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
        coordinator.keepSelectionOutOfConcealedProperties(in: textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        // The note has keyboard focus, as after a click in it: markup shows at the cursor only then.
        window.makeFirstResponder(textView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        textView.frame.size.width = 700
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView)
    }

    private func propertiesView(in textView: NSTextView) -> NSView? {
        textView.subviews.first { subview in subview is NSHostingView<AnyView> }
    }

    /// The height a line of the text reserves below it, and whether it is concealed.
    private func paragraphStyle(at location: Int, in textView: NSTextView) -> NSParagraphStyle? {
        textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    private func isConcealed(_ location: Int, in textView: NSTextView) -> Bool {
        (paragraphStyle(at: location, in: textView)?.maximumLineHeight ?? 0) == 0.01
    }

    private func waitUntil(timeoutSeconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("Timed out after \(timeoutSeconds) s") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func moveCursor(to selection: NSRange, in textView: NSTextView, _ coordinator: NativeMarkdownEditor.Coordinator) {
        textView.setSelectedRange(selection)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
    }

    func testThePropertiesAreDrawnOverTheirConcealedYAMLAtTheTopOfTheText() async throws {
        let (_, textView) = try await makeEditor()
        for location in [0, 5, Self.propertiesEnd - 1] { XCTAssertTrue(isConcealed(location, in: textView), "YAML at \(location) is concealed") }
        XCTAssertFalse(isConcealed(Self.propertiesEnd, in: textView), "The note's text shows")
        let panel = try XCTUnwrap(propertiesView(in: textView), "The properties view is in the text view")
        let textContainer = try XCTUnwrap(textView.textContainer)
        XCTAssertEqual(panel.frame.minY, textView.textContainerOrigin.y)
        XCTAssertEqual(panel.frame.minX, textView.textContainerOrigin.x + textContainer.lineFragmentPadding)
        XCTAssertEqual(panel.frame.width, textContainer.size.width - 2 * textContainer.lineFragmentPadding)
        // The YAML's last line reserves the view's height, so the text starts below it.
        let lastLineStyle = try XCTUnwrap(paragraphStyle(at: Self.propertiesEnd - 1, in: textView))
        XCTAssertEqual(lastLineStyle.paragraphSpacing, panel.frame.height)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: Self.propertiesEnd, length: 0), "A note opened at its start puts the cursor on its text")
        // A click on the properties reaches their view, not the text under it.
        let pointInPanel = textView.convert(NSPoint(x: panel.frame.midX, y: panel.frame.minY + 30), to: textView.superview)
        let clickedView = try XCTUnwrap(textView.hitTest(pointInPanel))
        XCTAssertTrue(clickedView.isDescendant(of: panel), "\(clickedView)")
    }

    /// The view measures itself once laid out; the YAML then reserves that height.
    func testTheReservedHeightFollowsTheHeightThePropertiesViewMeasured() async throws {
        let (_, textView) = try await makeEditor(text: "---\na: 1\nb: 2\nc: 3\nd: 4\ne: 5\n---\nBody\n")
        let propertiesEnd = ("---\na: 1\nb: 2\nc: 3\nd: 4\ne: 5\n---\n" as NSString).length
        let estimate: CGFloat = 44 + 34 * 6
        let deadline = Date.now.addingTimeInterval(5)
        while paragraphStyle(at: propertiesEnd - 1, in: textView)?.paragraphSpacing == estimate, Date.now < deadline {
            propertiesView(in: textView)?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let reservedHeight = try XCTUnwrap(paragraphStyle(at: propertiesEnd - 1, in: textView)?.paragraphSpacing)
        XCTAssertNotEqual(reservedHeight, estimate, "The measured height replaced the estimate")
        XCTAssertGreaterThan(reservedHeight, 100, "Five properties are taller than a line")
        XCTAssertEqual(propertiesView(in: textView)?.frame.height, reservedHeight)
    }

    func testTheCursorStaysOutOfTheConcealedYAMLAndABackspaceCannotJoinItToTheText() async throws {
        let (coordinator, textView) = try await makeEditor()
        moveCursor(to: NSRange(location: 6, length: 0), in: textView, coordinator)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: Self.propertiesEnd, length: 0))
        // A selection dragged up into the YAML keeps only the text's part.
        moveCursor(to: NSRange(location: 6, length: Self.propertiesEnd), in: textView, coordinator)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: Self.propertiesEnd, length: 6))
        moveCursor(to: NSRange(location: Self.propertiesEnd, length: 0), in: textView, coordinator)
        textView.deleteBackward(nil)
        XCTAssertEqual(textView.string, Self.noteText, "The properties' closing line stays its own")
        // Select All covers the properties, as in Obsidian.
        textView.selectAll(nil)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: (Self.noteText as NSString).length))
    }

    func testEditSourceShowsTheYAMLUntilTheCursorLeavesIt() async throws {
        let (coordinator, textView) = try await makeEditor()
        coordinator.showPropertiesSource(in: textView)
        XCTAssertFalse(isConcealed(5, in: textView), "The YAML shows")
        XCTAssertNil(propertiesView(in: textView)?.superview, "The view leaves")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0), "The cursor is on the first property")
        moveCursor(to: NSRange(location: 8, length: 0), in: textView, coordinator)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0), "The shown YAML takes the cursor")
        XCTAssertFalse(isConcealed(5, in: textView))
        moveCursor(to: NSRange(location: Self.propertiesEnd + 2, length: 0), in: textView, coordinator)
        XCTAssertTrue(isConcealed(5, in: textView), "Leaving the YAML conceals it again")
        try await waitUntil { self.propertiesView(in: textView)?.superview != nil }
        XCTAssertFalse(coordinator.showsPropertiesSource)
    }

    /// The view edits the properties through the session; the new text reaches the editor
    /// as an undoable edit, and the YAML stays concealed under the updated view.
    func testAPropertyEditedInTheViewChangesTheFrontmatterAndCanBeUndone() async throws {
        let (coordinator, textView) = try await makeEditor()
        let panel = try XCTUnwrap(propertiesView(in: textView))
        let updateProperties = try XCTUnwrap(coordinator.environment?.updateProperties)
        updateProperties([NoteProperty(key: "title", value: .text("Kyoto")), NoteProperty(key: "tags", value: .list(["travel"]))])
        let editedText = coordinator.session.text
        XCTAssertTrue(editedText.contains("title: Kyoto"), editedText)
        coordinator.replaceText(with: editedText, in: textView)
        XCTAssertEqual(textView.string, editedText)
        XCTAssertTrue(isConcealed(5, in: textView))
        XCTAssertTrue(propertiesView(in: textView) === panel, "The same view shows the new properties, keeping its state")
        XCTAssertEqual(textView.selectedRange().location, (editedText as NSString).range(of: "Body").location, "The cursor stays on the text")
        coordinator.noteUndoManager.undo()
        XCTAssertEqual(textView.string, Self.noteText)
    }

    func testWithoutLivePreviewOrThePropertiesViewTheYAMLStaysText() async throws {
        for (mode, showsProperties) in [(EditingMode.source, true), (EditingMode.livePreview, false)] {
            let (_, textView) = try await makeEditor(mode: mode, showsProperties: showsProperties)
            XCTAssertFalse(isConcealed(5, in: textView), "\(mode), properties view \(showsProperties)")
            XCTAssertNil(propertiesView(in: textView))
            XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        }
    }

    /// Turning the Properties view off shows the YAML; turning it on conceals it again.
    func testTurningThePropertiesViewOnOrOffRestylesTheYAML() async throws {
        let (coordinator, textView) = try await makeEditor()
        let environment = try XCTUnwrap(coordinator.environment)
        coordinator.environment = LivePreviewEnvironment(root: environment.root, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                         resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        XCTAssertFalse(coordinator.rendersProperties)
        coordinator.restyleEverything(in: textView)
        XCTAssertFalse(isConcealed(5, in: textView))
        XCTAssertNil(propertiesView(in: textView)?.superview)
        coordinator.environment = environment
        coordinator.restyleEverything(in: textView)
        XCTAssertTrue(isConcealed(5, in: textView))
        try await waitUntil { self.propertiesView(in: textView)?.superview != nil }
    }

    func testSelectionsAndEditsAroundTheConcealedYAML() {
        let end = 20
        typealias Coordinator = NativeMarkdownEditor.Coordinator
        XCTAssertEqual(Coordinator.selection(NSRange(location: 3, length: 0), keptBelowConcealedPropertiesEndingAt: end), NSRange(location: 20, length: 0))
        XCTAssertEqual(Coordinator.selection(NSRange(location: 3, length: 30), keptBelowConcealedPropertiesEndingAt: end), NSRange(location: 20, length: 13))
        XCTAssertEqual(Coordinator.selection(NSRange(location: 0, length: 40), keptBelowConcealedPropertiesEndingAt: end), NSRange(location: 0, length: 40))
        XCTAssertEqual(Coordinator.selection(NSRange(location: 25, length: 2), keptBelowConcealedPropertiesEndingAt: end), NSRange(location: 25, length: 2))
        XCTAssertTrue(Coordinator.cutsIntoConcealedProperties(NSRange(location: 19, length: 1), propertiesEnd: end), "A backspace at the text's start")
        XCTAssertTrue(Coordinator.cutsIntoConcealedProperties(NSRange(location: 10, length: 15), propertiesEnd: end))
        XCTAssertFalse(Coordinator.cutsIntoConcealedProperties(NSRange(location: 0, length: 25), propertiesEnd: end), "Replacing the whole YAML")
        XCTAssertFalse(Coordinator.cutsIntoConcealedProperties(NSRange(location: 5, length: 3), propertiesEnd: end), "An edit inside it")
        XCTAssertFalse(Coordinator.cutsIntoConcealedProperties(NSRange(location: 20, length: 1), propertiesEnd: end), "A forward delete at the text's start")
    }
}
#endif
