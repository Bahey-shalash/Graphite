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
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.contentView = nil }
        windows = []
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
    /// - Parameter hasKeyboardFocus: Puts the view in a window with keyboard focus, as after a
    ///   click in the note: markup shows at the cursor only then.
    private func makeEditor(text: String, mode: EditingMode = .livePreview, hasKeyboardFocus: Bool = false) async throws
        -> (NativeMarkdownEditor.Coordinator, MarkdownMacTextView, NSScrollView) {
        let session = try await makeSession(text: text)
        var configuration = EditorConfiguration()
        configuration.mode = mode
        let coordinator = NativeMarkdownEditor.Coordinator(session: session, configuration: configuration)
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.delegate = coordinator
        coordinator.connect(textView)
        coordinator.restyleEverything(in: textView)
        if hasKeyboardFocus {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
            windows.append(window)
            window.contentView = scrollView
            window.makeFirstResponder(textView)
        }
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

    func testSavingAQueuedInsertionKeepsNativeUndo() async throws {
        let (coordinator, textView, scrollView) = try await makeEditor(text: "Lecture.\n", mode: .source)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scrollView
        coordinator.resume(scrollView)
        let session = coordinator.session
        session.insert("![[Recording.m4a]]", at: NSRange(location: (session.text as NSString).length, length: 0))
        XCTAssertNotNil(session.pendingInsertion)
        try await session.save()
        XCTAssertEqual(textView.string, "Lecture.\n![[Recording.m4a]]")
        XCTAssertEqual(session.text, textView.string)
        XCTAssertNil(session.pendingInsertion)
        XCTAssertTrue(coordinator.noteUndoManager.canUndo)
        coordinator.noteUndoManager.undo()
        XCTAssertEqual(textView.string, "Lecture.\n")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.text, "Lecture.\n")
    }

    // MARK: Markup the Mac cannot draw stays visible (F168)

    /// The Mac draws bullets, task boxes, quote bars and formulas over their hidden markup,
    /// as the iPad does, with the same layout fragment.
    func testBulletsCheckboxesQuotesAndMathAreDrawnOverTheirHiddenMarkup() async throws {
        let text = "- [ ] task\nInline $x^2$ math\n- bullet\n> quote\nlast"
        let (_, textView, _) = try await makeEditor(text: text)
        let source = text as NSString
        textView.setSelectedRange(NSRange(location: source.length, length: 0))
        let textStorage = try XCTUnwrap(textView.textStorage)
        let (coordinator, _, _) = (textView.delegate as? NativeMarkdownEditor.Coordinator, 0, 0)
        try XCTUnwrap(coordinator).restyleEverything(in: textView)
        for marker in ["- ", "[ ]", "- b", ">", "$x^2$"] {
            let range = source.range(of: marker)
            var replacement: Any?
            textStorage.enumerateAttribute(ConcealedReplacement.attributeKey, in: range) { value, _, _ in if value != nil { replacement = value } }
            let isConcealedMarker = !isVisible(NSRange(location: range.location, length: 1), in: textStorage)
            XCTAssertTrue(replacement != nil || isConcealedMarker, "\(marker) is drawn or hidden")
        }
        let textLayoutManager = try XCTUnwrap(textView.textLayoutManager)
        let documentStart = textLayoutManager.documentRange.location
        let fragment = try XCTUnwrap(textLayoutManager.textLayoutFragment(for: documentStart))
        XCTAssertTrue(fragment is ConcealedReplacementLayoutFragment, "The Mac's paragraphs are drawn by the replacements' fragment")
    }

    /// A click on a drawn task box checks it, through the text view so it can be undone; a
    /// click on the box of the cursor's line, where `[ ]` shows as written, places the cursor.
    func testAClickOnADrawnTaskBoxChecksItAndCanBeUndone() async throws {
        let text = "- [ ] Write the essay\n- [x] Read the paper\nLast line"
        let (coordinator, textView, _) = try await makeEditor(text: text, hasKeyboardFocus: true)
        let source = text as NSString
        textView.setSelectedRange(NSRange(location: source.length, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertTrue(coordinator.toggleTask(atCharacter: source.range(of: "[ ]").location + 1, in: textView))
        XCTAssertEqual(textView.string, "- [x] Write the essay\n- [x] Read the paper\nLast line")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: source.length, length: 0), "The cursor stays where it was")
        coordinator.noteUndoManager.undo()
        XCTAssertEqual(textView.string, text)
        // The editor takes in the undone edit on the next turn of the run loop, before a next click could come.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(coordinator.toggleTask(atCharacter: source.range(of: "[x] Read").location + 1, in: textView))
        XCTAssertEqual(textView.string, "- [ ] Write the essay\n- [ ] Read the paper\nLast line")
        XCTAssertFalse(coordinator.toggleTask(atCharacter: source.range(of: "Last").location, in: textView), "Text is not a box")
        // On the cursor's line the box shows as `[ ]`; a click there places the cursor.
        textView.setSelectedRange(NSRange(location: source.range(of: "Write").location, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertFalse(coordinator.toggleTask(atCharacter: 3, in: textView))
    }

    // MARK: Restyling only what changed (F174, F184)

    func testTypingAndMovingTheCursorRestyleOnlyTheLinesInvolved() async throws {
        let lines = (0..<200).map { index in "Paragraph \(index) with **bold** text" }
        let (coordinator, textView, _) = try await makeEditor(text: lines.joined(separator: "\n"), hasKeyboardFocus: true)
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

        // Moving the cursor into bold text reveals its markup; the first line's heading
        // marker hides again, and its bold text was never touched.
        let editedSource = NSString(string: textStorage.string)
        let targetLine = editedSource.lineRange(for: NSRange(location: editedSource.range(of: "Paragraph 20 ").location, length: 0))
        let revealedMarker = editedSource.range(of: "**", range: targetLine)
        XCTAssertTrue(isVisible(NSRange(location: 0, length: 2), in: textStorage))
        textView.setSelectedRange(NSRange(location: NSMaxRange(revealedMarker) + 2, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertEqual(coordinator.revealedMarkup?.lineRange, targetLine)
        XCTAssertTrue(isVisible(revealedMarker, in: textStorage))
        XCTAssertFalse(isVisible(NSRange(location: 0, length: 2), in: textStorage))
        let firstLineMarker = editedSource.range(of: "**")
        XCTAssertFalse(isVisible(firstLineMarker, in: textStorage))
        XCTAssertNotNil(textStorage.attribute(sentinelKey, at: farLine.location + 2 + 2, effectiveRange: nil), "Moving the cursor restyled the whole note")
    }

    /// A far jump restyles the two lines involved, not the lines between them, and the line
    /// after the old cursor line hides its markup again (P7).
    func testMovingTheCursorRestylesNeitherTheLinesBetweenNorLeavesTheNextLineRevealed() async throws {
        let lines = ["Top line"] + (1..<200).map { index in "# Heading \(index)" }
        let (coordinator, textView, _) = try await makeEditor(text: lines.joined(separator: "\n"), hasKeyboardFocus: true)
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
        XCTAssertEqual(coordinator.revealedMarkup?.lineRange, lastLine)
        XCTAssertTrue(isVisible(NSRange(location: lastLine.location, length: 1), in: textStorage))
        XCTAssertNotNil(textStorage.attribute(sentinelKey, at: middleLine.location + 2, effectiveRange: nil), "A far jump restyled the lines between")
    }

    // MARK: One element at a time

    /// Whether the editor's text is styled as styling the whole note afresh for its
    /// selection would style it, so nothing an earlier selection showed is left over.
    private func assertStyledForItsSelection(_ coordinator: NativeMarkdownEditor.Coordinator, _ textView: NSTextView, _ message: String = "",
                                             file: StaticString = #filePath, line: UInt = #line) throws {
        let textStorage = try XCTUnwrap(textView.textStorage)
        let source = NSString(string: textStorage.string)
        let expected = NSTextStorage(string: source as String)
        let styler = MarkdownTextStyler(configuration: coordinator.configuration, accentColor: NSColor.graphiteAccent(hex: coordinator.configuration.accentHex) ?? .controlAccentColor)
        styler.applyStyles(to: expected, editedRange: NSRange(location: 0, length: 0), restyleEverything: true,
                           revealedMarkup: RevealedMarkup(selection: textView.selectedRange(), in: source), concealedBlocks: [])
        // Compared character by character, so a failure names the first one that differs.
        // The accent is a new color object for every styler, so colors are compared as
        // the components they resolve to.
        func comparableAttributes(of styledText: NSTextStorage, at location: Int) -> [String: String] {
            var comparable: [String: String] = [:]
            for (key, value) in styledText.attributes(at: location, effectiveRange: nil) {
                comparable[key.rawValue] = (value as? NSColor)?.usingColorSpace(.sRGB).map { color in "\(color.redComponent) \(color.greenComponent) \(color.blueComponent) \(color.alphaComponent)" } ?? "\(value)"
            }
            return comparable
        }
        for location in 0..<source.length {
            let attributes = comparableAttributes(of: textStorage, at: location)
            let expectedAttributes = comparableAttributes(of: expected, at: location)
            guard attributes != expectedAttributes else { continue }
            let differingKeys = Set(attributes.keys).union(expectedAttributes.keys).filter { key in attributes[key] != expectedAttributes[key] }.sorted()
            return XCTFail("\(message): character \(location) of \(source.substring(with: source.lineRange(for: NSRange(location: location, length: 0))).debugDescription) differs in \(differingKeys)", file: file, line: line)
        }
    }

    private func moveCursor(to selection: NSRange, in textView: NSTextView, _ coordinator: NativeMarkdownEditor.Coordinator) {
        textView.setSelectedRange(selection)
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
    }

    private func type(_ typedText: String, in textView: NSTextView, _ coordinator: NativeMarkdownEditor.Coordinator) {
        textView.insertText(typedText, replacementRange: textView.selectedRange())
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    }

    func testOnlyTheElementUnderTheCursorShowsItsMarkupAsTheCursorMoves() async throws {
        let text = "# Title with **bold**\nPlain **bold** and [[Note|alias]] and ==mark==\n- item with `code`\n"
        let (coordinator, textView, _) = try await makeEditor(text: text, hasKeyboardFocus: true)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let source = text as NSString
        let secondLine = source.lineRange(for: NSRange(location: source.range(of: "Plain").location, length: 0))
        let bold = source.range(of: "**bold**", range: secondLine)
        let link = source.range(of: "[[Note|alias]]")
        let mark = source.range(of: "==mark==")
        func shown() -> [Bool] { [bold, link, mark].map { element in isVisible(NSRange(location: element.location, length: 2), in: textStorage) } }

        moveCursor(to: NSRange(location: secondLine.location + 2, length: 0), in: textView, coordinator)
        XCTAssertEqual(shown(), [false, false, false], "The cursor's line stays rendered away from the cursor.")
        XCTAssertFalse(isVisible(NSRange(location: 0, length: 2), in: textStorage), "The heading's marks hide when the cursor leaves its line.")
        moveCursor(to: NSRange(location: bold.location + 4, length: 0), in: textView, coordinator)
        XCTAssertEqual(shown(), [true, false, false])
        moveCursor(to: NSRange(location: NSMaxRange(link) - 3, length: 0), in: textView, coordinator)
        XCTAssertEqual(shown(), [false, true, false])
        XCTAssertTrue(isVisible(NSRange(location: link.location, length: 7), in: textStorage), "The link's target shows with its brackets.")
        // A selection from inside the bold text to inside the highlight touches all three.
        moveCursor(to: NSRange(location: bold.location + 4, length: mark.location + 4 - bold.location - 4), in: textView, coordinator)
        XCTAssertEqual(shown(), [true, true, true])
        XCTAssertEqual(textView.selectedRange(), NSRange(location: bold.location + 4, length: mark.location - bold.location), "Showing markup never moves the selection.")
        try assertStyledForItsSelection(coordinator, textView)
        moveCursor(to: NSRange(location: 3, length: 0), in: textView, coordinator)
        XCTAssertEqual(shown(), [false, false, false])
        XCTAssertTrue(isVisible(NSRange(location: 0, length: 2), in: textStorage), "The heading's marks show on the cursor's line.")
        XCTAssertFalse(isVisible(source.range(of: "**"), in: textStorage), "Bold text in the heading stays rendered until the cursor reaches it.")
        try assertStyledForItsSelection(coordinator, textView)
    }

    /// Typing at the end of bold text keeps its closing markup in view, the cursor stays
    /// where typing left it, and undo and redo leave the note styled for where they put
    /// the cursor.
    func testTypingDeletingAndUndoKeepTheMarkupOfTheElementBeingEdited() async throws {
        let text = "Intro line\nSome **bold** text and [[Note]] here\nLast line with ==mark==\n"
        let (coordinator, textView, _) = try await makeEditor(text: text, hasKeyboardFocus: true)
        let textStorage = try XCTUnwrap(textView.textStorage)
        let source = text as NSString
        let bold = source.range(of: "**bold**")
        func boldMarkers() -> [NSRange] {
            let currentBold = NSString(string: textStorage.string).range(of: "\\*\\*[a-z ]+\\*\\*", options: .regularExpression)
            return [NSRange(location: currentBold.location, length: 2), NSRange(location: NSMaxRange(currentBold) - 2, length: 2)]
        }

        // The cursor at the end of the word, before the closing `**`.
        moveCursor(to: NSRange(location: NSMaxRange(bold) - 2, length: 0), in: textView, coordinator)
        type("er", in: textView, coordinator)
        XCTAssertEqual(textStorage.string, text.replacingOccurrences(of: "**bold**", with: "**bolder**"))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: NSMaxRange(bold), length: 0))
        XCTAssertTrue(boldMarkers().allSatisfy { marker in isVisible(marker, in: textStorage) })
        try assertStyledForItsSelection(coordinator, textView, "after typing inside bold text")

        // After the closing `**`, the edge still counts; one space further it does not.
        moveCursor(to: NSRange(location: NSMaxRange(bold) + 2, length: 0), in: textView, coordinator)
        XCTAssertTrue(boldMarkers().allSatisfy { marker in isVisible(marker, in: textStorage) })
        type("!", in: textView, coordinator)
        XCTAssertFalse(boldMarkers().contains { marker in isVisible(marker, in: textStorage) }, "A character typed after the bold text separates the cursor from it.")
        try assertStyledForItsSelection(coordinator, textView, "after typing past bold text")

        // Deleting that character brings the cursor back to the edge.
        textView.insertText("", replacementRange: NSRange(location: textView.selectedRange().location - 1, length: 1))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        XCTAssertTrue(boldMarkers().allSatisfy { marker in isVisible(marker, in: textStorage) })
        try assertStyledForItsSelection(coordinator, textView, "after deleting back to the edge")

        // Undo and redo from far away: the cursor goes where the edit was.
        moveCursor(to: NSRange(location: textStorage.length - 4, length: 0), in: textView, coordinator)
        try assertStyledForItsSelection(coordinator, textView, "after moving to the highlight")
        let undoManager = try XCTUnwrap(textView.undoManager)
        for step in 0..<3 where undoManager.canUndo {
            undoManager.undo()
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            try assertStyledForItsSelection(coordinator, textView, "after undo \(step)")
        }
        XCTAssertEqual(textStorage.string, text)
        for step in 0..<3 where undoManager.canRedo {
            undoManager.redo()
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            try assertStyledForItsSelection(coordinator, textView, "after redo \(step)")
        }
        XCTAssertEqual(coordinator.session.text, textStorage.string)
    }

    // MARK: Jumps, links, and undo (F173, F171)

    func testHeadingJumpWaitsForAWindowThenSelectsAndScrollsToTheHeading() async throws {
        let body = (0..<300).map { index in "Line \(index)" }.joined(separator: "\n")
        let text = body + "\n## Target heading\nAfter"
        let (coordinator, textView, scrollView) = try await makeEditor(text: text)
        coordinator.pendingJump = .heading(anchor: "target heading")
        XCTAssertNotNil(textView.textLayoutManager, "Native source highlights and jump geometry require TextKit 2")
        coordinator.performPendingJumpIfReady(in: textView)
        XCTAssertNotNil(coordinator.pendingJump, "A view outside a window cannot be measured yet")

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = scrollView
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.frame.size.width = 600
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        scrollView.layoutSubtreeIfNeeded()
        textView.layoutSubtreeIfNeeded()
        coordinator.performPendingJumpIfReady(in: textView)
        XCTAssertNil(coordinator.pendingJump)
        let headingLocation = (text as NSString).range(of: "## Target heading").location
        XCTAssertEqual(textView.selectedRange(), NSRange(location: headingLocation, length: 0))
        XCTAssertGreaterThan(textView.visibleRect.minY, 100, "view \(textView.frame), scroll \(scrollView.contentView.bounds), TextKit 2 \(textView.textLayoutManager != nil)")
    }

    func testClickedLinksFollowOnlyWhereTheirMarkupIsConcealed() async throws {
        let text = "Cursor in [[Here]] not [[There]]\nSee [[Target]] now\n`[[Code]]`"
        let (coordinator, textView, _) = try await makeEditor(text: text, hasKeyboardFocus: true)
        var followed: [String] = []
        coordinator.follow = { target, _ in followed.append(target) }
        let source = text as NSString
        textView.setSelectedRange(NSRange(location: source.range(of: "Here").location + 2, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        XCTAssertTrue(coordinator.followLink(atCharacter: source.range(of: "Target").location + 1, modifierFlags: [], in: textView))
        XCTAssertEqual(followed, ["Target"])
        // The link the cursor is in shows its markup and is being edited; the other link
        // on the cursor's line stays a link.
        XCTAssertNil(coordinator.link(atCharacter: source.range(of: "Here").location + 1, in: textView))
        XCTAssertNotNil(coordinator.link(atCharacter: source.range(of: "There").location + 1, in: textView))
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

    /// Each note keeps its own history, as on the iPad, rather than the window's shared one,
    /// and a hidden editor shown again in a new container still undoes its edits.
    func testEachNoteHasItsOwnHistoryThatSurvivesBeingHiddenAndShownAgain() async throws {
        let (lectureCoordinator, lectureTextView, lectureScrollView) = try await makeEditor(text: "Lecture\n")
        let (slidesCoordinator, slidesTextView, slidesScrollView) = try await makeEditor(text: "Slides\n")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled], backing: .buffered, defer: true)
        let firstContainer = MarkdownEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let secondContainer = MarkdownEditorContainerView(frame: NSRect(x: 400, y: 0, width: 400, height: 400))
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        content.addSubview(firstContainer)
        content.addSubview(secondContainer)
        window.contentView = content
        firstContainer.host(lectureScrollView)
        secondContainer.host(slidesScrollView)
        lectureCoordinator.replaceText(with: "Lecture edited\n", in: lectureTextView)
        slidesCoordinator.replaceText(with: "Slides edited\n", in: slidesTextView)
        XCTAssertTrue(lectureTextView.undoManager === lectureCoordinator.noteUndoManager)
        XCTAssertFalse(lectureTextView.undoManager === window.undoManager)
        XCTAssertFalse(window.undoManager?.canUndo == true, "Nothing goes to the window's shared history.")

        // The slides changed last, yet undo in the lecture undoes the lecture.
        lectureTextView.undoManager?.undo()
        XCTAssertEqual(lectureTextView.string, "Lecture\n")
        XCTAssertEqual(slidesTextView.string, "Slides edited\n")
        lectureTextView.undoManager?.redo()

        // Hidden, then shown in a new container, as when its tab returns.
        lectureCoordinator.suspend(lectureScrollView)
        XCTAssertFalse(lectureCoordinator.session.isEditorAttached)
        XCTAssertNil(lectureScrollView.superview)
        let returningContainer = MarkdownEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        content.addSubview(returningContainer)
        returningContainer.host(lectureScrollView)
        lectureCoordinator.resume(lectureScrollView)
        XCTAssertTrue(lectureCoordinator.session.isEditorAttached)
        XCTAssertTrue(lectureCoordinator.session.undoAvailability.canUndo)
        lectureCoordinator.session.undoAvailability.undo()
        XCTAssertEqual(lectureTextView.string, "Lecture\n")
        // The note's text follows on the next turn of the run loop.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(lectureCoordinator.session.text, "Lecture\n")
    }

    /// SwiftUI makes a note's new view before it dismantles the old one, and can dismantle
    /// a view it has only just made, as when the split closes. The editor ends in the
    /// view that stays whichever way round that goes, and is never left hidden.
    func testEditorEndsInTheViewThatStaysWhicheverViewIsDismantledFirst() async throws {
        for dismantlesPassingViewFirst in [true, false] {
            let (coordinator, textView, scrollView) = try await makeEditor(text: "Lecture\n")
            let retention = MarkdownEditorRetention()
            let document = TabDocument()
            document.markdownSession = coordinator.session
            coordinator.retention = retention
            coordinator.retentionOwner = document
            coordinator.scrollView = scrollView
            coordinator.replaceText(with: "Lecture edited\n", in: textView)
            coordinator.suspend(scrollView)

            let splitContainer = MarkdownEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            let stayingContainer = MarkdownEditorContainerView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
            let passingContainer = MarkdownEditorContainerView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
            coordinator.viewWasMade(with: splitContainer)
            XCTAssertTrue(splitContainer.scrollViewShownHere === scrollView, "A hidden editor is shown in its new view at once.")
            XCTAssertTrue(coordinator.session.isEditorAttached)

            coordinator.viewWasMade(with: stayingContainer)
            coordinator.viewWasMade(with: passingContainer)
            XCTAssertTrue(splitContainer.scrollViewShownHere === scrollView, "The editor stays where it is until that view is dismantled.")
            var updatedScrollViews: [NSScrollView] = []
            stayingContainer.updateWhenScrollViewArrives = { arrivedScrollView in updatedScrollViews.append(arrivedScrollView) }

            if dismantlesPassingViewFirst {
                coordinator.viewWasDismantled(with: passingContainer)
                coordinator.viewWasDismantled(with: splitContainer)
            } else {
                coordinator.viewWasDismantled(with: splitContainer)
                XCTAssertTrue(passingContainer.scrollViewShownHere === scrollView)
                coordinator.viewWasDismantled(with: passingContainer)
            }
            XCTAssertTrue(stayingContainer.scrollViewShownHere === scrollView, "dismantlesPassingViewFirst: \(dismantlesPassingViewFirst)")
            XCTAssertEqual(updatedScrollViews.count, 1, "The view that stays brings the editor up to date once it shows it.")
            XCTAssertTrue(coordinator.session.isEditorAttached)
            XCTAssertEqual(retention.hiddenEditorCount, 0, "An editor on screen is not kept as a hidden one.")
            XCTAssertTrue(coordinator.session.undoAvailability.canUndo)

            // With no view left, the editor leaves the screen and is kept with its history.
            coordinator.viewWasDismantled(with: stayingContainer)
            XCTAssertNil(scrollView.superview)
            XCTAssertFalse(coordinator.session.isEditorAttached)
            XCTAssertTrue(retention.hasHiddenEditor(for: coordinator.session))
        }
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

    func testPluginsHearTypingAndAddTheirItemsToTheContextMenu() async throws {
        let (coordinator, textView, _) = try await makeEditor(text: "Study #physics today")
        var changeCount = 0
        coordinator.actions.pluginEditorDidChange = { changeCount += 1; return nil }
        textView.insertText("!", replacementRange: NSRange(location: 20, length: 0))
        XCTAssertEqual(coordinator.session.text, "Study #physics today!")
        XCTAssertEqual(changeCount, 1, "plugins hear the note change, as in Obsidian's editor")

        let rightClick = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let titlesWithoutPlugins = textView.menu(for: rightClick)?.items.map(\.title) ?? []
        XCTAssertFalse(titlesWithoutPlugins.contains("Rename #physics"))
        textView.pendingPluginMenuItems = [NSMenuItem(title: "Rename #physics", action: nil, keyEquivalent: "")]
        let titles = try XCTUnwrap(textView.menu(for: rightClick)).items.map(\.title)
        XCTAssertEqual(titles.last, "Rename #physics", "the plugins' items follow the editor's own")
    }
}
#endif
