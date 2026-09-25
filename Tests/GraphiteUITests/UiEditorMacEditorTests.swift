#if os(macOS)
import AppKit
import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The Mac editor: styling that shows what it cannot draw, restyling only what changed,
/// jumps, links, and pasted attachments.
@MainActor
final class UiEditorMacEditorTests: XCTestCase {
    private var vaultDirectories: [URL] = []

    override func tearDown() async throws {
        for vaultDirectory in vaultDirectories { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectories = []
        try await super.tearDown()
    }

    private func makeSession(text: String) async throws -> MarkdownSession {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        vaultDirectories.append(vault)
        try Data(text.utf8).write(to: vault.appendingPathComponent("Note.md"))
        let store = VaultStore(root: vault)
        let notePath = try VaultPath("Note.md")
        return try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
    }

    /// A text view connected to a coordinator the way `makeNSView` connects it.
    private func makeEditor(text: String, mode: EditingMode = .livePreview) async throws -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, NSScrollView) {
        let session = try await makeSession(text: text)
        var configuration = EditorConfiguration()
        configuration.mode = mode
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        let scrollView = MarkdownMacTextView.scrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        return (coordinator, textView, scrollView)
    }

    private func isVisible(_ range: NSRange, in textStorage: NSTextStorage) -> Bool {
        var isVisible = true
        textStorage.enumerateAttributes(in: range) { attributes, _, _ in
            if let font = attributes[.font] as? NSFont, font.pointSize < 1 { isVisible = false }
            if let color = attributes[.foregroundColor] as? NSColor, color.alphaComponent == 0 { isVisible = false }
        }
        return isVisible
    }

    // MARK: Markup the Mac cannot draw stays visible (F168)

    func testBulletsCheckboxesQuotesAndMathStayVisibleAwayFromTheCursor() {
        let source = "- [ ] task\nInline $x^2$ math\n- bullet\n> quote\nlast" as NSString
        let textStorage = NSTextStorage(string: source as String)
        // The Mac's default styler already leaves this markup visible; a styler that draws
        // replacements hides it, which is what `showSource` must undo.
        let styler = MarkdownTextStyler(configuration: EditorConfiguration(), accentColor: .controlAccentColor, drawsConcealedReplacements: true)
        let revealedRange = source.lineRange(for: NSRange(location: source.length, length: 0))
        styler.applyStyles(to: textStorage, editedRange: NSRange(location: 0, length: 0), restyleEverything: true, revealedRange: revealedRange, concealedBlocks: [])
        let markers = ["- ", "[ ]", "- b", ">"].map { marker in source.range(of: marker) }
        let hiddenBefore = markers.filter { marker in !isVisible(marker, in: textStorage) }
        XCTAssertFalse(hiddenBefore.isEmpty, "The shared styler hides markup it expects a drawing for")

        UndrawnReplacementStyling.showSource(in: textStorage, range: NSRange(location: 0, length: source.length), baseFont: styler.baseFont)
        for marker in markers + [source.range(of: "$x^2$")] {
            XCTAssertTrue(isVisible(marker, in: textStorage), "\(source.substring(with: marker)) is hidden")
        }
        var remainingReplacements = 0
        textStorage.enumerateAttribute(ConcealedReplacement.attributeKey, in: NSRange(location: 0, length: source.length)) { value, _, _ in
            if value != nil { remainingReplacements += 1 }
        }
        XCTAssertEqual(remainingReplacements, 0)
    }

    // MARK: Restyling only what changed (F174, F184)

    func testTypingAndMovingTheCursorRestyleOnlyTheLinesInvolved() async throws {
        let lines = (0..<200).map { index in "Paragraph \(index) with **bold** text" }
        let (coordinator, textView, _) = try await makeEditor(text: lines.joined(separator: "\n"))
        let textStorage = try XCTUnwrap(textView.textStorage)
        let source = NSString(string: textStorage.string)
        let sentinelKey = NSAttributedString.Key("UiEditorSentinel")
        let farLine = source.lineRange(for: NSRange(location: source.range(of: "Paragraph 150").location, length: 0))
        textStorage.addAttribute(sentinelKey, value: true, range: farLine)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("# ", replacementRange: NSRange(location: 0, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertEqual(coordinator.session.text, textStorage.string)
        let headingFont = try XCTUnwrap(textStorage.attribute(.font, at: 4, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(headingFont.pointSize, EditorConfiguration().textSize)
        XCTAssertNotNil(textStorage.attribute(sentinelKey, at: farLine.location + 2, effectiveRange: nil), "Typing restyled the whole note")

        // Moving the cursor reveals its new line's markup and conceals the old line's again.
        let editedSource = NSString(string: textStorage.string)
        let targetLine = editedSource.lineRange(for: NSRange(location: editedSource.range(of: "Paragraph 20 ").location, length: 0))
        textView.setSelectedRange(NSRange(location: targetLine.location + 3, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertEqual(coordinator.revealedRange, targetLine)
        let revealedMarker = editedSource.range(of: "**", range: targetLine)
        XCTAssertTrue(isVisible(revealedMarker, in: textStorage))
        let firstLineMarker = editedSource.range(of: "**")
        XCTAssertFalse(isVisible(firstLineMarker, in: textStorage))
        XCTAssertNotNil(textStorage.attribute(sentinelKey, at: farLine.location + 2 + 2, effectiveRange: nil), "Moving the cursor restyled the whole note")
    }

    /// A far jump restyles the two lines involved, not the lines between them, and the line
    /// after the old cursor line hides its markup again (P7).
    func testMovingTheCursorRestylesNeitherTheLinesBetweenNorLeavesTheNextLineRevealed() async throws {
        let lines = ["Top line"] + (1..<200).map { index in "# Heading \(index)" }
        let (coordinator, textView, _) = try await makeEditor(text: lines.joined(separator: "\n"))
        let textStorage = try XCTUnwrap(textView.textStorage)
        let source = NSString(string: textStorage.string)
        let sentinelKey = NSAttributedString.Key("UiEditorSentinel")
        let middleLine = source.lineRange(for: NSRange(location: source.range(of: "# Heading 100").location, length: 0))
        textStorage.addAttribute(sentinelKey, value: true, range: middleLine)

        let secondLine = source.lineRange(for: NSRange(location: source.range(of: "# Heading 1\n").location, length: 0))
        let thirdLineMarker = NSRange(location: source.range(of: "# Heading 2\n").location, length: 1)
        textView.setSelectedRange(NSRange(location: secondLine.location + 3, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        // Only the cursor's own line is revealed; markup starting the next line stays hidden.
        XCTAssertFalse(isVisible(thirdLineMarker, in: textStorage), "Markup right after the cursor's line shows")

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertFalse(isVisible(thirdLineMarker, in: textStorage), "The line after the old cursor line stayed revealed")

        let lastLine = source.lineRange(for: NSRange(location: source.length, length: 0))
        textView.setSelectedRange(NSRange(location: lastLine.location + 3, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertEqual(coordinator.revealedRange, lastLine)
        XCTAssertTrue(isVisible(NSRange(location: lastLine.location, length: 1), in: textStorage))
        XCTAssertNotNil(textStorage.attribute(sentinelKey, at: middleLine.location + 2, effectiveRange: nil), "A far jump restyled the lines between")
    }

    // MARK: Jumps, links, and undo (F173, F171)

    func testHeadingJumpWaitsForAWindowThenSelectsAndScrollsToTheHeading() async throws {
        let body = (0..<300).map { index in "Line \(index)" }.joined(separator: "\n")
        let text = body + "\n## Target heading\nAfter"
        let (coordinator, textView, scrollView) = try await makeEditor(text: text)
        coordinator.pendingJump = .heading(anchor: "target heading")
        coordinator.performPendingJumpIfReady(in: textView)
        XCTAssertNotNil(coordinator.pendingJump, "A view outside a window cannot be measured yet")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scrollView
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.frame.size.width = 600
        coordinator.performPendingJumpIfReady(in: textView)
        XCTAssertNil(coordinator.pendingJump)
        let headingLocation = (text as NSString).range(of: "## Target heading").location
        XCTAssertEqual(textView.selectedRange(), NSRange(location: headingLocation, length: 0))
        XCTAssertGreaterThan(textView.visibleRect.minY, 100)
    }

    func testClickedLinksFollowOnlyWhereTheirMarkupIsConcealed() async throws {
        let text = "Cursor line [[Here]]\nSee [[Target]] now\n`[[Code]]`"
        let (coordinator, textView, _) = try await makeEditor(text: text)
        var followed: [String] = []
        coordinator.follow = { target, _ in followed.append(target) }
        let source = text as NSString
        XCTAssertTrue(coordinator.followLink(atCharacter: source.range(of: "Target").location + 1, modifierFlags: [], in: textView))
        XCTAssertEqual(followed, ["Target"])
        // The cursor's line shows its markup and is being edited.
        XCTAssertNil(coordinator.link(atCharacter: source.range(of: "Here").location + 1, in: textView))
        XCTAssertNil(coordinator.link(atCharacter: source.range(of: "Code").location + 1, in: textView))

        var openedElsewhere: [(String, TabPlacement)] = []
        coordinator.actions.followLinkElsewhere = { target, _, placement in openedElsewhere.append((target, placement)) }
        XCTAssertTrue(coordinator.followLink(atCharacter: source.range(of: "Target").location + 1, modifierFlags: [.command], in: textView))
        XCTAssertEqual(openedElsewhere.map { opened in opened.0 }, ["Target"])
        XCTAssertEqual(openedElsewhere.map { opened in opened.1 }, [.newTab])

        let (sourceModeCoordinator, sourceModeTextView, _) = try await makeEditor(text: text, mode: .source)
        XCTAssertNil(sourceModeCoordinator.link(atCharacter: source.range(of: "Target").location + 1, in: sourceModeTextView))
    }

    /// A property edited from a panel changes only the frontmatter, and can be undone.
    func testTextChangedElsewhereIsReplacedInPlaceAndCanBeUndone() async throws {
        let oldText = "---\ntags: a\n---\nBody text\n"
        let (coordinator, textView, scrollView) = try await makeEditor(text: oldText)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scrollView
        let bodyLocation = (oldText as NSString).range(of: "text").location
        textView.setSelectedRange(NSRange(location: bodyLocation, length: 0))
        let newText = "---\ntags: a, b\n---\nBody text\n"
        coordinator.replaceText(with: newText, in: textView)
        XCTAssertEqual(textView.string, newText)
        XCTAssertEqual(coordinator.session.text, newText)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: bodyLocation + 3, length: 0), "The cursor stays on the same character")
        let undoManager = try XCTUnwrap(textView.undoManager)
        XCTAssertTrue(undoManager.canUndo)
        undoManager.undo()
        XCTAssertEqual(textView.string, oldText)
    }

    // MARK: Pasted and dropped attachments (F173, F667)

    /// Two files pasted over a selected word, or dropped at a point: the first takes the
    /// place asked for and the second goes after it, instead of replacing part of the
    /// first's embed or going before it.
    func testSeveralPastedFilesGoInOrderWithoutOverwritingEachOther() async throws {
        let text = "Intro word here\n"
        for requestedRange in [(text as NSString).range(of: "word"), NSRange(location: 6, length: 0)] {
            let (coordinator, textView, _) = try await makeEditor(text: text)
            let session = coordinator.session
            session.isEditorAttached = true
            var requestedRanges: [NSRange] = []
            coordinator.actions.insertAttachment = { _, _, _, range in requestedRanges.append(range) }
            textView.insertAttachment?(Data(), "First", "png", requestedRange)
            textView.insertAttachment?(Data(), "Second", "png", requestedRange)
            XCTAssertEqual(requestedRanges, [requestedRange, requestedRange])
            // As the pane does once each file is saved.
            for stem in ["First", "Second"] {
                session.insertBlock("![[\(stem).png]]", at: requestedRange)
                coordinator.apply(try XCTUnwrap(session.pendingInsertion), to: textView)
            }
            let result = textView.string as NSString
            let firstLocation = result.range(of: "![[First.png]]").location
            let secondLocation = result.range(of: "![[Second.png]]").location
            XCTAssertNotEqual(firstLocation, NSNotFound, result as String)
            XCTAssertNotEqual(secondLocation, NSNotFound, result as String)
            XCTAssertLessThan(firstLocation, secondLocation, result as String)
            XCTAssertEqual(result.range(of: "word").location != NSNotFound, requestedRange.length == 0, result as String)
            XCTAssertEqual(session.text, result as String)
        }
    }

    func testPastedImageFileAndVaultItemBecomeAttachmentsOrLinks() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("UiEditorTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let pasteDate = Date(timeIntervalSince1970: 0)

        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        XCTAssertEqual(MacPastedAttachment.attachments(on: pasteboard, now: pasteDate),
                       [.file(data: pngData, stem: WorkspaceModel.pastedImageStem(at: pasteDate), fileExtension: "png")])

        // An image copied with its caption is pasted as text.
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .png], owner: nil)
        pasteboard.setString("Caption", forType: .string)
        pasteboard.setData(pngData, forType: .png)
        XCTAssertEqual(MacPastedAttachment.attachments(on: pasteboard, now: pasteDate), [])

        let fileDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Paste-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fileDirectory) }
        let documentURL = fileDirectory.appendingPathComponent("Report.pdf")
        try Data("%PDF".utf8).write(to: documentURL)
        let missingURL = fileDirectory.appendingPathComponent("Missing.pdf")
        pasteboard.clearContents()
        pasteboard.writeObjects([documentURL as NSURL, missingURL as NSURL])
        XCTAssertEqual(MacPastedAttachment.attachments(on: pasteboard, now: pasteDate),
                       [.file(data: Data("%PDF".utf8), stem: "Report", fileExtension: "pdf"), .unreadableFile(name: "Missing.pdf")])

        pasteboard.clearContents()
        let itemData = try JSONEncoder().encode(VaultItemTransfer(path: "Folder/Other note.md"))
        pasteboard.setData(itemData, forType: MacPastedAttachment.vaultItemType)
        XCTAssertEqual(MacPastedAttachment.attachments(on: pasteboard, now: pasteDate), [.vaultItem(try VaultPath("Folder/Other note.md"))])
        XCTAssertTrue(MacPastedAttachment.isOffered(on: pasteboard))
    }
}
#endif
