import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class UiMarkdownPaneFixTests: XCTestCase {
    private var vaultDirectory: URL!

    override func setUp() async throws {
        vaultDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MarkdownPaneVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vaultDirectory)
    }

    private func makeSession(named name: String = "Note.md", contents: Data) async throws -> (session: MarkdownSession, store: VaultStore) {
        let notePath = try VaultPath(name)
        try contents.write(to: vaultDirectory.appendingPathComponent(name))
        let store = VaultStore(root: vaultDirectory)
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        return (session, store)
    }

    private func fileBytes(_ name: String) throws -> [UInt8] {
        Array(try Data(contentsOf: vaultDirectory.appendingPathComponent(name)))
    }

    /// Waits for work started on the main actor, such as a suggestion fetch, to finish.
    private func waitUntil(_ condition: () -> Bool, timeoutSeconds: Double = 5) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out waiting") }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Byte-order mark

    func testSavingKeepsTheByteOrderMarkAndLineEndings() async throws {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        let (session, _) = try await makeSession(contents: Data(byteOrderMark + Array("hello\r\nworld".utf8)))
        XCTAssertEqual(session.text, "hello\r\nworld")
        session.text += "!"
        try await session.save()
        XCTAssertEqual(try fileBytes("Note.md"), byteOrderMark + Array("hello\r\nworld!".utf8))
    }

    func testSavingANoteWithoutByteOrderMarkAddsNone() async throws {
        let (session, _) = try await makeSession(contents: Data("plain".utf8))
        session.text = "plain text"
        try await session.save()
        XCTAssertEqual(try fileBytes("Note.md"), Array("plain text".utf8))
    }

    func testByteOrderMarkDecodingKeepsAFollowingZeroWidthNoBreakSpace() {
        let decoded = NoteTextEncoding.decode(Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF] + Array("a".utf8)))
        XCTAssertEqual(decoded?.text, "\u{FEFF}a")
        XCTAssertEqual(decoded?.hasByteOrderMark, true)
        XCTAssertNil(NoteTextEncoding.decode(Data([0xFF, 0xFE])))
    }

    func testAddingABlockIdentifierToAnotherNoteKeepsItsByteOrderMark() async throws {
        let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
        let otherText = "First paragraph\n"
        try Data(byteOrderMark + Array(otherText.utf8)).write(to: vaultDirectory.appendingPathComponent("Other.md"))
        let workspace = WorkspaceModel()
        workspace.store = VaultStore(root: vaultDirectory)
        let block = try XCTUnwrap(NoteBlocks.blocks(in: otherText).first)
        let identifierEdit = NoteBlocks.addingIdentifier("abc123", to: block, in: otherText)
        try await workspace.addBlockIdentifier(identifierEdit, to: try VaultPath("Other.md"), expectingText: otherText)
        let savedBytes = try fileBytes("Other.md")
        XCTAssertEqual(Array(savedBytes.prefix(3)), byteOrderMark)
        XCTAssertTrue(String(decoding: savedBytes.dropFirst(3), as: UTF8.self).contains("^abc123"))
    }

    // MARK: A note removed by another app

    func testSaveACopyEndsTheConflictWhenAnotherAppDeletedTheNote() async throws {
        let (session, _) = try await makeSession(contents: Data("original".utf8))
        session.text = "my edits"
        try FileManager.default.removeItem(at: vaultDirectory.appendingPathComponent("Note.md"))
        do {
            try await session.save()
            XCTFail("Saving over a deleted note must report the conflict")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertTrue(session.hasExternalConflict)
        do {
            try await session.reload()
            XCTFail("There is no other version to use")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("deleted or moved"), error.localizedDescription)
        }

        let copyPath = try await session.saveSeparateCopy()
        XCTAssertEqual(String(decoding: try fileBytes(copyPath.rawValue), as: UTF8.self), "my edits")
        XCTAssertFalse(session.hasExternalConflict)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(session.errorMessage)
        // Navigation saves first; it must no longer be blocked.
        try await session.save()
    }

    func testSaveACopyStillShowsTheOtherVersionWhenTheNoteExists() async throws {
        let (session, _) = try await makeSession(contents: Data("original".utf8))
        session.text = "my edits"
        try Data("theirs".utf8).write(to: vaultDirectory.appendingPathComponent("Note.md"))
        await session.checkExternalChange()
        XCTAssertTrue(session.hasExternalConflict)
        let copyPath = try await session.saveSeparateCopy()
        XCTAssertEqual(String(decoding: try fileBytes(copyPath.rawValue), as: UTF8.self), "my edits")
        XCTAssertEqual(session.text, "theirs")
        XCTAssertFalse(session.hasExternalConflict)
    }

    // MARK: Insertions waiting for the editor

    /// Applies the queued insertions one at a time, as the editor view does.
    private func applyQueuedInsertionsAsTheEditorDoes(to session: MarkdownSession) {
        while let insertion = session.pendingInsertion {
            let source = session.text as NSString
            let location = min(insertion.range.location, source.length)
            session.text = source.replacingCharacters(in: NSRange(location: location, length: min(insertion.range.length, source.length - location)), with: insertion.text)
            session.selection = insertion.selectionAfter ?? NSRange(location: location + (insertion.text as NSString).length, length: 0)
            session.markInsertionApplied(insertion)
        }
    }

    /// Several dropped images used to overwrite each other in a single waiting slot. Queued
    /// for the editor, they must end up exactly as if each had been applied at once.
    func testSeveralInsertionsBeforeTheEditorAppliesThemAllLand() async throws {
        let original = "Intro\n\nOutro"
        let (directSession, _) = try await makeSession(named: "Direct.md", contents: Data(original.utf8))
        directSession.selection = NSRange(location: 5, length: 0)
        directSession.insertBlock("![[One.png]]")
        directSession.insertBlock("![[Two.png]]")
        directSession.insert("x", at: NSRange(location: (directSession.text as NSString).length, length: 0))

        let (queuedSession, _) = try await makeSession(named: "Queued.md", contents: Data(original.utf8))
        queuedSession.isEditorAttached = true
        queuedSession.selection = NSRange(location: 5, length: 0)
        queuedSession.insertBlock("![[One.png]]")
        queuedSession.insertBlock("![[Two.png]]")
        // A range of the text the editor shows now, which is still the original.
        queuedSession.insert("x", at: NSRange(location: (original as NSString).length, length: 0))
        XCTAssertEqual(queuedSession.text, original)
        applyQueuedInsertionsAsTheEditorDoes(to: queuedSession)

        XCTAssertTrue(directSession.text.contains("![[One.png]]") && directSession.text.contains("![[Two.png]]"))
        XCTAssertTrue(directSession.text.hasSuffix("Outrox"))
        XCTAssertEqual(queuedSession.text, directSession.text)
    }

    /// A recording that finishes after the editor closed (reading view, another tab) must
    /// still leave its embed in the note.
    func testInsertionsWaitingWhenTheEditorGoesAwayAreKeptInTheText() async throws {
        let (directSession, _) = try await makeSession(named: "Direct.md", contents: Data("Line".utf8))
        directSession.selection = NSRange(location: 4, length: 0)
        directSession.insertBlock("![[Recording.m4a]]")
        XCTAssertNil(directSession.pendingInsertion)
        XCTAssertTrue(directSession.text.contains("![[Recording.m4a]]"))

        let (queuedSession, _) = try await makeSession(named: "Queued.md", contents: Data("Line".utf8))
        queuedSession.isEditorAttached = true
        queuedSession.selection = NSRange(location: 4, length: 0)
        queuedSession.insertBlock("![[Recording.m4a]]")
        XCTAssertEqual(queuedSession.text, "Line")
        queuedSession.isEditorAttached = false
        XCTAssertNil(queuedSession.pendingInsertion)
        XCTAssertEqual(queuedSession.text, directSession.text)
        XCTAssertTrue(queuedSession.hasUnsavedChanges)
    }

    // MARK: Editing commands

    func testCommandsWithACursorPastTheEndDoNotCrash() {
        let text = "---\n---\nab" as NSString
        let staleSelection = NSRange(location: 40, length: 0)
        for command in [EditorCommand.bold, .italic, .code, .heading(2), .bulletList, .task, .insertWikilink, .insertMarkdownLink, .insertTag, .indent, .moveLinesUp] {
            guard let edit = MarkdownEditing.edit(for: command, in: text, selection: staleSelection, indentUnit: "\t") else { continue }
            XCTAssertLessThanOrEqual(NSMaxRange(edit.range), text.length, "\(command)")
        }
    }

    func testTagAfterAnEmojiGetsASeparatingSpace() throws {
        let text = "Hi 😀" as NSString
        let edit = try XCTUnwrap(MarkdownEditing.edit(for: .insertTag, in: text, selection: NSRange(location: text.length, length: 0), indentUnit: "\t"))
        XCTAssertEqual(edit.replacement, " #")
        let afterSpace = try XCTUnwrap(MarkdownEditing.edit(for: .insertTag, in: "Hi " as NSString, selection: NSRange(location: 3, length: 0), indentUnit: "\t"))
        XCTAssertEqual(afterSpace.replacement, "#")
    }

    func testTagKeepsTheSelectedWordAsItsName() throws {
        let text = "Plan project" as NSString
        let edit = try XCTUnwrap(MarkdownEditing.edit(for: .insertTag, in: text, selection: NSRange(location: 5, length: 7), indentUnit: "\t"))
        XCTAssertEqual(text.replacingCharacters(in: edit.range, with: edit.replacement), "Plan #project")
        XCTAssertEqual(edit.selectionAfter, NSRange(location: 13, length: 0))
    }

    // MARK: Markdown-link completion

    private func linkQuery(in text: String) throws -> LinkQuery {
        guard case .link(let query)? = LinkCompletion.context(in: text as NSString, cursor: (text as NSString).length) else {
            throw XCTSkip("No link context in \(text)")
        }
        return query
    }

    private func applying(_ edit: MarkdownTextEdit, to text: String) -> String {
        (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testMarkdownLinkToAHeadingOrBlockOfTheSameNoteHasOnlyAFragment() throws {
        let headingText = "See [[#Intro"
        let heading = CompletionProvider.linkEdit(query: try linkQuery(in: headingText),
                                                  choice: CompletionProvider.fragmentChoice(notePart: "", fragment: "Intro"), usesWikilinks: false)
        XCTAssertEqual(applying(heading, to: headingText), "See [#Intro](#Intro)")
        let blockText = "See [[#^abc123"
        let block = CompletionProvider.linkEdit(query: try linkQuery(in: blockText),
                                                choice: CompletionProvider.fragmentChoice(notePart: "", fragment: "^abc123"), usesWikilinks: false)
        XCTAssertEqual(applying(block, to: blockText), "See [#^abc123](#^abc123)")
    }

    func testMarkdownLinkToAHeadingKeepsADotInTheNoteName() throws {
        let text = "[[Meeting 3.4#Ag"
        let edit = CompletionProvider.linkEdit(query: try linkQuery(in: text),
                                               choice: CompletionProvider.fragmentChoice(notePart: "Meeting 3.4", fragment: "Agenda"), usesWikilinks: false)
        XCTAssertEqual(applying(edit, to: text), "[Meeting 3.4#Agenda](Meeting%203.4.md#Agenda)")
    }

    func testWikilinkToAHeadingIsUnchanged() throws {
        let text = "[[Note#Int"
        let edit = CompletionProvider.linkEdit(query: try linkQuery(in: text),
                                               choice: CompletionProvider.fragmentChoice(notePart: "Note", fragment: "Intro"), usesWikilinks: true)
        XCTAssertEqual(applying(edit, to: text), "[[Note#Intro]]")
    }

    // MARK: Suggestions and newer typing

    func testAcceptingAnOlderListUsesTheRangeOfWhatIsTypedNow() async throws {
        let model = CompletionModel()
        model.provider = { _ in
            [CompletionItem(id: "project", title: "#project", systemImage: "number") { context in
                guard case .tag(_, let replacementRange) = context else { return [] }
                return [MarkdownTextEdit(range: replacementRange, replacement: "project ", selectionAfter: NSRange(location: replacementRange.location + 8, length: 0))]
            }]
        }
        var performedEdits: [MarkdownTextEdit] = []
        model.performEdits = { edits in performedEdits = edits }
        let firstText = "Note #pro"
        model.update(context: LinkCompletion.context(in: firstText as NSString, cursor: 9), caretRect: .zero)
        try await waitUntil { model.isVisible }
        // "je" is typed; Return comes before the new suggestions.
        let typedText = "Note #proje"
        model.update(context: LinkCompletion.context(in: typedText as NSString, cursor: 11), caretRect: .zero)
        XCTAssertTrue(model.isVisible)
        model.accept()
        try await waitUntil { !performedEdits.isEmpty }
        XCTAssertEqual(applying(try XCTUnwrap(performedEdits.first), to: typedText), "Note #project ")
    }

    func testHeadingSuggestionFromAnOlderQueryReplacesTheWholeNewQuery() async throws {
        let (session, _) = try await makeSession(contents: Data("# Introduction\n\nSee [[#Int".utf8))
        let workspace = WorkspaceModel()
        session.completion.suggest(from: workspace, for: session)
        var performedEdits: [MarkdownTextEdit] = []
        session.completion.performEdits = { edits in performedEdits = edits }
        session.completion.update(context: LinkCompletion.context(in: session.text as NSString, cursor: (session.text as NSString).length), caretRect: .zero)
        try await waitUntil { session.completion.isVisible }
        session.text += "ro"
        session.completion.update(context: LinkCompletion.context(in: session.text as NSString, cursor: (session.text as NSString).length), caretRect: .zero)
        session.completion.accept()
        try await waitUntil { !performedEdits.isEmpty }
        XCTAssertEqual(applying(try XCTUnwrap(performedEdits.first), to: session.text), "# Introduction\n\nSee [[#Introduction]]")
    }

    func testASuggestionThatNoLongerFitsInsertsNothing() async throws {
        let (session, _) = try await makeSession(contents: Data("# Introduction\n\nSee [[#Int".utf8))
        let workspace = WorkspaceModel()
        session.completion.suggest(from: workspace, for: session)
        var performedEdits: [[MarkdownTextEdit]] = []
        session.completion.performEdits = { edits in performedEdits.append(edits) }
        session.completion.update(context: LinkCompletion.context(in: session.text as NSString, cursor: (session.text as NSString).length), caretRect: .zero)
        try await waitUntil { session.completion.isVisible }
        // The heading query became a block query.
        session.text = "# Introduction\n\nSee [[#^"
        session.completion.update(context: LinkCompletion.context(in: session.text as NSString, cursor: (session.text as NSString).length), caretRect: .zero)
        session.completion.accept()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(performedEdits.isEmpty)
    }

    func testAFailedSuggestionIsReported() async throws {
        let model = CompletionModel()
        model.provider = { _ in
            [CompletionItem(id: "block", title: "Paragraph", systemImage: "text.alignleft") { _ in throw GraphiteError.conflict }]
        }
        var reportedErrors: [Error] = []
        model.reportError = { error in reportedErrors.append(error) }
        model.update(context: LinkCompletion.context(in: "[[#^" as NSString, cursor: 4), caretRect: .zero)
        try await waitUntil { model.isVisible }
        model.accept()
        try await waitUntil { !reportedErrors.isEmpty }
        XCTAssertEqual(reportedErrors.first as? GraphiteError, .conflict)
    }

    func testFileSuggestionKeepsTheFolderUntilTheIndexHasSeenEveryFile() async throws {
        let (session, _) = try await makeSession(contents: Data("[[".utf8))
        let workspace = WorkspaceModel()
        workspace.index = try VaultIndex(databaseURL: vaultDirectory.appendingPathComponent("index.sqlite"))
        workspace.recentFiles = RecentFiles(paths: [try VaultPath("Folder/Notes.md")])
        XCTAssertFalse(workspace.hasCompletedIndexScan)
        session.completion.suggest(from: workspace, for: session)
        var performedEdits: [MarkdownTextEdit] = []
        session.completion.performEdits = { edits in performedEdits = edits }
        session.completion.update(context: LinkCompletion.context(in: session.text as NSString, cursor: 2), caretRect: .zero)
        try await waitUntil { session.completion.isVisible }
        session.completion.accept()
        try await waitUntil { !performedEdits.isEmpty }
        XCTAssertEqual(applying(try XCTUnwrap(performedEdits.first), to: session.text), "[[Folder/Notes]]")
    }

    func testCompletionTitleHighlightsOnlyRangesInsideTheTitle() {
        let highlighted = CompletionPopup.highlightedTitle("Ideas", highlights: [0..<1, 3..<5, 7..<12], accent: .blue)
        XCTAssertEqual(String(highlighted.characters), "Ideas")
        let accentedText = highlighted.runs.filter { run in run[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] != nil }
            .map { run in String(highlighted[run.range].characters) }
        XCTAssertEqual(accentedText, ["I", "as"])
    }

    // MARK: Memory

    func testSuggestionsDoNotKeepTheSessionAlive() async throws {
        let workspace = WorkspaceModel()
        weak var releasedSession: MarkdownSession?
        do {
            let (session, _) = try await makeSession(contents: Data("text".utf8))
            session.completion.suggest(from: workspace, for: session)
            releasedSession = session
        }
        XCTAssertNil(releasedSession)
    }

    // MARK: Word count

    func testWordCountMatchesTheParsedBodyCount() throws {
        let samples = [
            "",
            "one",
            "---\ntitle: Test\ntags: [a, b]\n---\nHello  world\n\n  with 😀 emoji\tand tabs\n",
            "---\r\ntitle: CRLF\r\n---\r\nLine one\r\nLine two",
            "No frontmatter here\n---\nnot: yaml",
            "---\n---\n",
        ]
        for sample in samples {
            let parsedBody = try MarkdownSemantics.parse(sample).body
            let expectedWordCount = parsedBody.split(whereSeparator: { character in character.isWhitespace || character.isNewline }).count
            let counts = NoteTextCounts(countingBodyOf: sample)
            XCTAssertEqual(counts.wordCount, expectedWordCount, sample)
            XCTAssertEqual(counts.characterCount, parsedBody.count, sample)
        }
    }
}
