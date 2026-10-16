#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The Mac's Live Preview draws tables, math, callouts and the other rendered blocks as views
/// over their concealed source, as the iPad does: a block shows its source while the cursor is
/// in it, a click on its view puts the cursor there, and only the blocks TextKit has laid out
/// have views.
@MainActor
final class UiEditorMacRenderedBlocksTests: XCTestCase {
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
    private static var tableRange: NSRange {
        let source = tableNote as NSString
        let start = source.range(of: "| Year").location
        return NSRange(location: start, length: source.range(of: "\nAfter").location - start)
    }

    private func makeEditor(text: String, height: CGFloat = 500) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, NSScrollView) {
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: height), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        windows.append(window)
        window.contentView = scrollView
        // The note has keyboard focus, as after a click in it: markup shows at the cursor only then.
        window.makeFirstResponder(textView)
        scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: height)
        textView.frame.size.width = 700
        scrollView.layoutSubtreeIfNeeded()
        return (coordinator, textView, scrollView)
    }

    private func blockViews(in textView: NSTextView) -> [NSView] {
        textView.subviews.filter { subview in subview is NSHostingView<AnyView> }.sorted { leftView, rightView in leftView.frame.minY < rightView.frame.minY }
    }

    private func isConcealed(_ location: Int, in textView: NSTextView) -> Bool {
        ((textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.maximumLineHeight ?? 0) == 0.01
    }

    private func moveCursor(to selection: NSRange, in textView: NSTextView, _ coordinator: NativeMarkdownEditor.Coordinator) {
        textView.setSelectedRange(selection)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
    }

    private func type(_ typedText: String, in textView: NSTextView, _ coordinator: NativeMarkdownEditor.Coordinator) {
        textView.insertText(typedText, replacementRange: textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    }

    private func waitUntil(timeoutSeconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("Timed out after \(timeoutSeconds) s") }
            windows.forEach { window in window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A lecture's citation line, quoted and starting with bold text: in the Mac's editor its
    /// wrapped line started at the margin, under the quote's bar. Checked with the cursor
    /// elsewhere, after it passes through the line, and after typing in the line.
    func testAWrappedQuoteStartingWithBoldTextStartsItsSecondLineUnderItsText() async throws {
        let text = "Intro\n\n> **Lecture 4, Memory-Centric Computing II** - Dr. Geraldo F. Oliveira · SAFARI Research Group, ETH Zürich, and Huawei Zürich · 2 October 2026\n\nAfter the quote.\n"
        // The coordinator is the text view's delegate, which the text view holds weakly.
        let (coordinator, textView, _) = try await makeEditor(text: text)
        defer { withExtendedLifetime(coordinator) {} }
        let quoteStart = (text as NSString).range(of: "> **").location
        func lineStarts() throws -> (first: CGFloat, second: CGFloat) {
            let textLayoutManager = try XCTUnwrap(textView.textLayoutManager)
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
            let contentStorage = try XCTUnwrap(textLayoutManager.textContentManager as? NSTextContentStorage)
            let location = try XCTUnwrap(contentStorage.location(contentStorage.documentRange.location, offsetBy: quoteStart + 4))
            let fragment = try XCTUnwrap(textLayoutManager.textLayoutFragment(for: location))
            XCTAssertGreaterThan(fragment.textLineFragments.count, 1, "The quote wraps")
            let firstLine = fragment.textLineFragments[0]
            let secondLine = fragment.textLineFragments[1]
            let textOffsetInFirstLine = 4 - (contentStorage.offset(from: contentStorage.documentRange.location, to: fragment.rangeInElement.location) - quoteStart)
            return (firstLine.locationForCharacter(at: textOffsetInFirstLine).x + firstLine.typographicBounds.minX,
                    secondLine.locationForCharacter(at: secondLine.characterRange.location).x + secondLine.typographicBounds.minX)
        }
        var starts = try lineStarts()
        XCTAssertGreaterThan(starts.second, 6, "The second line clears the bar")
        XCTAssertEqual(starts.second, starts.first, accuracy: 2, "The second line starts under the first line's text")

        textView.setSelectedRange(NSRange(location: quoteStart + 20, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        starts = try lineStarts()
        XCTAssertGreaterThan(starts.second, 6, "After the cursor passed through, the second line still clears the bar")

        textView.setSelectedRange(NSRange(location: quoteStart + 20, length: 0))
        textView.insertText("x", replacementRange: textView.selectedRange())
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        try await Task.sleep(for: .milliseconds(50))
        starts = try lineStarts()
        XCTAssertGreaterThan(starts.second, 6, "After typing in it, the second line still clears the bar")
    }

    func testATableAwayFromTheCursorIsDrawnOverItsConcealedSource() async throws {
        let (_, textView, _) = try await makeEditor(text: Self.tableNote)
        let tableRange = Self.tableRange
        XCTAssertTrue(isConcealed(tableRange.location + 3, in: textView), "The table's source is concealed")
        XCTAssertFalse(isConcealed((Self.tableNote as NSString).range(of: "After").location, in: textView), "The text after it shows")
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        let tableView = try XCTUnwrap(blockViews(in: textView).first)
        let textContainer = try XCTUnwrap(textView.textContainer)
        XCTAssertEqual(tableView.frame.minX, textView.textContainerOrigin.x + textContainer.lineFragmentPadding)
        XCTAssertGreaterThan(tableView.frame.minY, textView.textContainerOrigin.y + 10, "Below the intro line")
        // Once measured, the table's last line reserves its view's height, so the text after it starts below.
        try await waitUntil {
            let lastLineStyle = textView.textStorage?.attribute(.paragraphStyle, at: NSMaxRange(tableRange) - 1, effectiveRange: nil) as? NSParagraphStyle
            return lastLineStyle?.paragraphSpacing == tableView.frame.height
        }
        XCTAssertGreaterThan(tableView.frame.height, 60, "Three rows are taller than a line")
    }

    func testTheCursorInABlockShowsItsSourceAndLeavingDrawsItAgain() async throws {
        let (coordinator, textView, _) = try await makeEditor(text: Self.tableNote)
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        let tableView = try XCTUnwrap(blockViews(in: textView).first)
        moveCursor(to: NSRange(location: Self.tableRange.location + 4, length: 0), in: textView, coordinator)
        XCTAssertFalse(isConcealed(Self.tableRange.location + 3, in: textView), "The source shows while the cursor is in it")
        XCTAssertTrue(blockViews(in: textView).isEmpty, "The view leaves at once")
        moveCursor(to: NSRange(location: 2, length: 0), in: textView, coordinator)
        XCTAssertTrue(isConcealed(Self.tableRange.location + 3, in: textView))
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        XCTAssertTrue(blockViews(in: textView).first === tableView, "The view kept off screen comes back, not a new one")
    }

    /// A note opened from the file list keeps its cursor at the start without keyboard focus:
    /// a block there is drawn, and shows its source only once the note has focus.
    func testABlockAtTheCursorShowsItsSourceOnlyWhileTheNoteHasKeyboardFocus() async throws {
        let calloutNote = "> [!info] What to check\n> A line inside the callout.\n\nAfter the callout\n"
        let (coordinator, textView, _) = try await makeEditor(text: calloutNote)
        let window = try XCTUnwrap(textView.window)
        moveCursor(to: NSRange(location: 3, length: 0), in: textView, coordinator)
        XCTAssertFalse(isConcealed(3, in: textView), "With focus, the callout under the cursor shows its source")
        window.makeFirstResponder(nil)
        XCTAssertTrue(isConcealed(3, in: textView), "Focus elsewhere, as in the file list, draws the callout")
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        window.makeFirstResponder(textView)
        XCTAssertFalse(isConcealed(3, in: textView), "Focus back in the note shows the source at the cursor again")
        XCTAssertTrue(blockViews(in: textView).isEmpty)
    }

    /// A click on a block's view puts the cursor at the block's start, showing its source.
    func testRevealingABlocksSourcePutsTheCursorInIt() async throws {
        let (coordinator, textView, _) = try await makeEditor(text: Self.tableNote)
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        let entryKey = try XCTUnwrap(LivePreviewBlockKey.keys(for: LivePreviewBlockScanner.blocks(in: Self.tableNote as NSString)).first)
        coordinator.revealSource(ofBlockWithKey: entryKey, in: textView)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: Self.tableRange.location, length: 0))
        XCTAssertFalse(isConcealed(Self.tableRange.location + 3, in: textView))
        XCTAssertTrue(blockViews(in: textView).isEmpty)
    }

    /// TextKit lays out the viewport; blocks far below it have no view until they scroll in.
    func testOnlyTheBlocksTextKitHasLaidOutHaveViews() async throws {
        let paragraph = (0..<12).map { lineIndex in "Paragraph line \(lineIndex)." }.joined(separator: "\n")
        let text = (0..<40).map { blockIndex in "\(paragraph)\n\n$$x_{\(blockIndex)} = \(blockIndex)$$\n" }.joined(separator: "\n")
        let (_, textView, scrollView) = try await makeEditor(text: text, height: 500)
        try await waitUntil { !self.blockViews(in: textView).isEmpty }
        let viewsAtTop = blockViews(in: textView).count
        XCTAssertLessThan(viewsAtTop, 10, "Of 40 blocks, only those near the top have views")
        let lastBlockLocation = (text as NSString).range(of: "$$x_{39}").location
        textView.scrollRangeToVisible(NSRange(location: lastBlockLocation, length: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        try await waitUntil {
            self.blockViews(in: textView).contains { view in view.frame.intersects(textView.visibleRect) && view.frame.minY > textView.bounds.height / 2 }
        }
        XCTAssertLessThan(blockViews(in: textView).count, 10, "The blocks scrolled away gave up their place on screen")
    }

    /// Typing in a paragraph moves the blocks after it; their views stay, not built again.
    func testTypingElsewhereKeepsTheBlocksViews() async throws {
        let (coordinator, textView, _) = try await makeEditor(text: Self.tableNote)
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        let tableView = try XCTUnwrap(blockViews(in: textView).first)
        let afterLocation = (Self.tableNote as NSString).range(of: "After").location
        moveCursor(to: NSRange(location: afterLocation, length: 0), in: textView, coordinator)
        type("More ", in: textView, coordinator)
        try await waitUntil { self.blockViews(in: textView).count == 1 }
        XCTAssertTrue(blockViews(in: textView).first === tableView)
        // A line typed above the table moves its view down.
        let tableTop = tableView.frame.minY
        moveCursor(to: NSRange(location: 0, length: 0), in: textView, coordinator)
        type("New first line\n", in: textView, coordinator)
        try await waitUntil { (self.blockViews(in: textView).first?.frame.minY ?? 0) > tableTop + 5 }
        XCTAssertTrue(blockViews(in: textView).first === tableView)
    }

    func testCalloutsMathAndRulesAreRenderedAndCodeIsNot() async throws {
        let text = "Intro\n\n> [!note] Title\n> Body\n\n$$a^2$$\n\n---\n\n```swift\nlet x = 1\n```\n\nEnd\n"
        let (_, textView, _) = try await makeEditor(text: text)
        try await waitUntil { self.blockViews(in: textView).count == 3 }
        let source = text as NSString
        XCTAssertTrue(isConcealed(source.range(of: "> [!note]").location + 2, in: textView))
        XCTAssertTrue(isConcealed(source.range(of: "$$a").location + 1, in: textView))
        XCTAssertFalse(isConcealed(source.range(of: "let x").location, in: textView), "Fenced code stays styled text")
    }
}
#endif
