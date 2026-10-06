import XCTest
import SwiftUI
@testable import Textual
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Ticking a task from reading view: the checkboxes the reading view draws, and the one
/// character of the note's file a tap changes, byte for byte.
@MainActor
final class UiReadingTaskTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingTasks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault)
    }

    /// A task as the reading view draws it: which note it is ticked in, its status and
    /// place, and the text after its checkbox.
    private struct DrawnTask {
        let note: VaultPath
        let task: ReadingTasks.MarkedTask
        let text: String
    }

    private func write(_ data: Data, to path: String) throws {
        let location = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: location)
    }

    private func fileData(_ path: String) throws -> Data { try Data(contentsOf: vault.appendingPathComponent(path)) }

    private func session(for path: String) async throws -> MarkdownSession {
        let store = VaultStore(root: vault)
        let notePath = try VaultPath(path)
        return try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
    }

    /// The tasks the reading view draws for `source`, the text of `note`, in order.
    private func drawnTasks(in source: String, note: String = "Note.md") async throws -> [DrawnTask] {
        let notePath = try VaultPath(note)
        let build = try await ReadingViewBuilder().build(source: source, note: notePath, root: vault, index: index, configuration: ReadingConfiguration())
        return try drawnTasks(in: build.blocks, note: notePath)
    }

    private func drawnTasks(in blocks: [RenderedBlock], note: VaultPath) throws -> [DrawnTask] {
        try blocks.flatMap { block -> [DrawnTask] in
            switch block {
            case .markdown(_, let text), .displayMath(_, let text):
                return try drawnTasks(inMarkdown: text, note: note)
            case .heading(_, let level, let text, _):
                // Reading view draws a heading's text after its `#`s.
                return try drawnTasks(inMarkdown: String(repeating: "#", count: level) + " " + text, note: note)
            case .callout(_, _, let title, _, let body):
                return try drawnTasks(inMarkdown: title, note: note) + drawnTasks(in: body, note: note)
            case .transclusion(_, let path, _, let body):
                return try drawnTasks(in: body, note: path)
            default:
                return []
            }
        }
    }

    private func drawnTasks(inMarkdown markdown: String, note: VaultPath) throws -> [DrawnTask] {
        let attributed = try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: markdown)
        var tasks: [DrawnTask] = []
        for (presentationIntent, paragraphRange) in attributed.runs[\.presentationIntent] {
            guard let task = attributed[paragraphRange].runs.first?[ReadingTaskAttribute.self] else { continue }
            XCTAssertEqual(presentationIntent?.components.dropFirst().first.map { component in
                if case .listItem = component.kind { return true }
                return false
            }, true, "A checkbox is drawn only for a list item.")
            tasks.append(DrawnTask(note: note, task: task, text: String(attributed[paragraphRange].characters.dropFirst())))
        }
        return tasks
    }

    /// `text` with the status character of the task on the line that is `line` replaced.
    private func replacingStatus(onLine line: String, in text: String, with status: String) throws -> String {
        let source = text as NSString
        let lineRange = source.range(of: line)
        XCTAssertNotEqual(lineRange.location, NSNotFound, line)
        XCTAssertEqual(source.range(of: line, range: NSRange(location: NSMaxRange(lineRange), length: source.length - NSMaxRange(lineRange))).location, NSNotFound,
                       "The expected line is written once.")
        let bracket = (line as NSString).range(of: "[").location
        let statusLength = (line as NSString).rangeOfComposedCharacterSequence(at: bracket + 1).length
        return source.replacingCharacters(in: NSRange(location: lineRange.location + bracket + 1, length: statusLength), with: status)
    }

    // MARK: Ticking a note's own tasks

    private static let variedNote = [
        "---", "tags: [shopping]", "done: false", "---",
        "# Tasks [^n]",
        "", "Intro with a reference[^n].",
        "[^n]: A footnote before the tasks,", "    over two lines.",
        "%% a comment", "- [ ] hidden in the comment", "%%",
        "$$", "a \\\\", "b", "$$",
        "- [ ] dash open", "* [x] star done", "+ [/] plus in progress",
        "\t- [-] nested with a tab", "    - [ ] nested with spaces",
        "1. [ ] numbered", "12) [X] numbered with a parenthesis",
        "- [\u{1F525}] emoji status",
        "- [ ] with a link [[Other]] and ~={#ff0000}color=~ and ==mark==",
        "- [ ] reference[^n] and %%inline comment%% here ^block-id",
        "> - [ ] quoted",
        "> [!todo] A callout",
        "> - [ ] in the callout",
        ">- [x] without a space",
        "> > [!note]- Folded",
        "> > - [ ] nested callout",
        "- [x]",
    ]

    /// Each task, the line it is written on, and the status a tap gives it.
    private static let variedNoteTasks: [(line: String, text: String, statusAfterTap: String)] = [
        ("- [ ] dash open", "dash open", "x"), ("* [x] star done", "star done", " "), ("+ [/] plus in progress", "plus in progress", " "),
        ("\t- [-] nested with a tab", "nested with a tab", " "), ("    - [ ] nested with spaces", "nested with spaces", "x"),
        ("1. [ ] numbered", "numbered", "x"), ("12) [X] numbered with a parenthesis", "numbered with a parenthesis", " "),
        ("- [\u{1F525}] emoji status", "emoji status", " "),
        ("- [ ] with a link [[Other]]", "with a link Other and color and mark", "x"),
        ("- [ ] reference[^n]", "reference1 and  here", "x"),
        ("> - [ ] quoted", "quoted", "x"), ("> - [ ] in the callout", "in the callout", "x"), (">- [x] without a space", "without a space", " "),
        ("> > - [ ] nested callout", "nested callout", "x"), ("- [x]\n", "", " "),
    ]

    func testTickingEachTaskChangesOnlyItsStatusInTheFile() async throws {
        for (lineEnding, hasByteOrderMark) in [("\n", false), ("\r\n", false), ("\r\n", true), ("\n", true)] {
            let text = Self.variedNote.joined(separator: lineEnding) + lineEnding
            let original = (hasByteOrderMark ? Self.byteOrderMark : Data()) + Data(text.utf8)
            try write(original, to: "Note.md")
            let tasks = try await drawnTasks(in: try session(for: "Note.md").text)
            XCTAssertEqual(tasks.map(\.text), Self.variedNoteTasks.map(\.text), "line ending \(lineEnding.debugDescription)")
            XCTAssertEqual(tasks.compactMap(\.task.location).count, Self.variedNoteTasks.count, "Every drawn task can be ticked.")
            for (task, expected) in zip(tasks, Self.variedNoteTasks) {
                try write(original, to: "Note.md")
                let noteSession = try await session(for: "Note.md")
                XCTAssertTrue(noteSession.toggleTask(at: try XCTUnwrap(task.task.location)), expected.line)
                try await noteSession.save()
                let expectedLine = expected.line.replacingOccurrences(of: "\n", with: lineEnding)
                let expectedText = try replacingStatus(onLine: expectedLine, in: text, with: expected.statusAfterTap)
                XCTAssertEqual(try fileData("Note.md"), (hasByteOrderMark ? Self.byteOrderMark : Data()) + Data(expectedText.utf8), expected.line)
            }
        }
    }

    func testTickingTwiceGivesBackTheFile() async throws {
        let original = Data("- [ ] open\r\n- [x] done\r\n".utf8)
        try write(original, to: "Note.md")
        let noteSession = try await session(for: "Note.md")
        let tasks = try await drawnTasks(in: noteSession.text)
        for task in tasks {
            let location = try XCTUnwrap(task.task.location)
            XCTAssertTrue(noteSession.toggleTask(at: location))
            XCTAssertTrue(noteSession.toggleTask(at: location), "The line's checksum leaves out its status, so a second tap finds the task.")
        }
        try await noteSession.save()
        XCTAssertEqual(noteSession.text, "- [ ] open\r\n- [x] done\r\n")
        XCTAssertFalse(noteSession.hasUnsavedChanges)
    }

    func testTickingKeepsTheCursorAndLeavesTheSaveToTheSession() async throws {
        try write(Data("Some text\n- [ ] task\nmore\n".utf8), to: "Note.md")
        let noteSession = try await session(for: "Note.md")
        noteSession.selection = NSRange(location: 22, length: 3)
        let drawn = try await drawnTasks(in: noteSession.text)
        let task = try XCTUnwrap(drawn.first?.task.location)
        XCTAssertTrue(noteSession.toggleTask(at: task))
        XCTAssertEqual(noteSession.text, "Some text\n- [x] task\nmore\n")
        XCTAssertEqual(noteSession.selection, NSRange(location: 22, length: 3))
        XCTAssertTrue(noteSession.hasUnsavedChanges)
        XCTAssertEqual(try fileData("Note.md"), Data("Some text\n- [ ] task\nmore\n".utf8), "The file changes when the session saves it.")
        try await noteSession.save()
        XCTAssertEqual(try fileData("Note.md"), Data("Some text\n- [x] task\nmore\n".utf8))
    }

    func testDuplicateTaskLinesAreTickedOneByOne() async throws {
        let text = "- [ ] same\n- [ ] same\n\n> [!note]\n> - [ ] same\n\n- [ ] same\n  - [ ] same\n"
        try write(Data(text.utf8), to: "Note.md")
        let tasks = try await drawnTasks(in: text)
        XCTAssertEqual(tasks.count, 5)
        let statusOffsets = [3, 14, 38, 50, 63]
        XCTAssertEqual(tasks.compactMap(\.task.location?.statusOffset), statusOffsets)
        for (task, statusOffset) in zip(tasks, statusOffsets) {
            let noteSession = try await session(for: "Note.md")
            XCTAssertTrue(noteSession.toggleTask(at: try XCTUnwrap(task.task.location)))
            XCTAssertEqual(noteSession.text, (text as NSString).replacingCharacters(in: NSRange(location: statusOffset, length: 1), with: "x"))
        }
    }

    func testTapOnAnOlderDrawingOfAChangedNoteChangesNothing() async throws {
        let text = "---\ntitle: Old\n---\n- [ ] first\n- [ ] second\n"
        try write(Data(text.utf8), to: "Note.md")
        let noteSession = try await session(for: "Note.md")
        let tasks = try await drawnTasks(in: noteSession.text)
        // A property edited in reading view moves every task before the view is drawn again.
        noteSession.replaceProperties([NoteProperty(key: "title", value: .text("A longer title"))])
        let changedText = noteSession.text
        XCTAssertNotEqual(changedText, text)
        for task in tasks { XCTAssertFalse(noteSession.toggleTask(at: try XCTUnwrap(task.task.location))) }
        XCTAssertEqual(noteSession.text, changedText)
        // Drawn again, the tasks are found where they now are.
        let redrawnTasks = try await drawnTasks(in: noteSession.text)
        XCTAssertTrue(noteSession.toggleTask(at: try XCTUnwrap(redrawnTasks.last?.task.location)))
        XCTAssertTrue(noteSession.text.hasSuffix("- [ ] first\n- [x] second\n"))
    }

    // MARK: What is not a task

    func testCheckboxesInCodeTablesHeadingsAndTextAreNotTasks() async throws {
        let text = [
            "```", "- [ ] fenced code", "```",
            "", "    - [/] indented code",
            "", "| - [ ] a cell | b |", "|---|---|", "| - [x] | c |",
            "", "# - [ ] a heading",
            "", "A paragraph", "2. [ ] continues it",
            "", "[ ] not a list",
            "", "> [!note]", "> ```", "> - [ ] code in a callout", "> ```",
            "", "- [ ] the only task",
        ].joined(separator: "\n")
        let notePath = try VaultPath("Note.md")
        let build = try await ReadingViewBuilder().build(source: text, note: notePath, root: vault, index: index, configuration: ReadingConfiguration())
        XCTAssertEqual(try drawnTasks(in: build.blocks, note: notePath).map(\.text), ["the only task"])
        let renderedText = try markdownTexts(build.blocks).map { markdown in
            String(try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: markdown).characters)
        }.joined(separator: "\n")
        for written in ["- [ ] fenced code", "- [/] indented code", "- [ ] a cell", "- [x]", "- [ ] a heading", "2. [ ] continues it", "[ ] not a list", "- [ ] code in a callout"] {
            XCTAssertTrue(renderedText.contains(written), "\(written) reads as the note has it")
        }
    }

    private func markdownTexts(_ blocks: [RenderedBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .markdown(_, let text), .displayMath(_, let text): [text]
            case .heading(_, let level, let text, _): [String(repeating: "#", count: level) + " " + text]
            case .callout(_, _, let title, _, let body): [title] + markdownTexts(body)
            case .transclusion(_, _, _, let body): markdownTexts(body)
            default: []
            }
        }
    }

    func testCopiedTaskKeepsItsCheckboxAsWritten() throws {
        let markdown = ObsidianInlineMarkup.preparedForReading("- [/] half done", colorsEnabled: true, paletteHexByName: [:])
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: 17).attributedString(for: markdown)
        XCTAssertEqual(Formatter(attributed).plainText(), "  • [/] half done")
    }

    // MARK: Tasks of an embedded note

    func testTaskOfAnEmbeddedNoteIsTickedInThatNote() async throws {
        let otherText = "---\r\ntype: list\r\n---\r\n- [ ] whole note task\r\n\r\n## Later\r\n- [x] section task\r\n\r\n- [ ] block task ^tasks\r\n"
        let otherData = Self.byteOrderMark + Data(otherText.utf8)
        try write(otherData, to: "Folder/Other.md")
        let hostText = "- [ ] host task\n\n![[Other]]\n\n![[Other#Later]]\n\n![[Other#^tasks]]\n"
        try write(Data(hostText.utf8), to: "Host.md")
        let otherPath = try VaultPath("Folder/Other.md")
        try await index.refresh(paths: [otherPath, try VaultPath("Host.md")], root: vault)
        let tasks = try await drawnTasks(in: hostText, note: "Host.md")
        // The whole note, the section from its heading to the end, and the block.
        XCTAssertEqual(tasks.map(\.text), ["host task", "whole note task", "section task", "block task", "section task", "block task", "block task"])
        XCTAssertEqual(tasks.map(\.note.rawValue), ["Host.md"] + Array(repeating: "Folder/Other.md", count: 6))

        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        let hostSession = try await session(for: "Host.md")
        let expectedLines = ["- [ ] whole note task", "- [x] section task", "- [ ] block task ^tasks", "- [x] section task", "- [ ] block task ^tasks", "- [ ] block task ^tasks"]
        for (task, line) in zip(tasks.dropFirst(), expectedLines) {
            try write(otherData, to: "Folder/Other.md")
            let didToggle = await workspace.toggleReadingTask(at: try XCTUnwrap(task.task.location), in: task.note, shownBy: hostSession)
            XCTAssertTrue(didToggle, line)
            let expectedText = try replacingStatus(onLine: line, in: otherText, with: line.contains("[x]") ? " " : "x")
            XCTAssertEqual(try fileData("Folder/Other.md"), Self.byteOrderMark + Data(expectedText.utf8), line)
        }
        XCTAssertEqual(hostSession.text, hostText, "The note that embeds the task is unchanged.")
        XCTAssertNil(workspace.errorMessage)
    }

    func testTaskOfAnEmbeddedNoteOpenInATabIsTickedThroughItsSession() async throws {
        let otherText = "- [ ] embedded\n"
        try write(Data(otherText.utf8), to: "Other.md")
        let hostText = "![[Other]]\n"
        try write(Data(hostText.utf8), to: "Host.md")
        try await index.refresh(paths: [try VaultPath("Other.md"), try VaultPath("Host.md")], root: vault)
        let drawn = try await drawnTasks(in: hostText, note: "Host.md")
        let task = try XCTUnwrap(drawn.first)

        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        await workspace.open(try VaultPath("Other.md"))
        let otherSession = try XCTUnwrap(workspace.openMarkdownSession(at: try VaultPath("Other.md")))
        let hostSession = try await session(for: "Host.md")
        let didToggle = await workspace.toggleReadingTask(at: try XCTUnwrap(task.task.location), in: task.note, shownBy: hostSession)
        XCTAssertTrue(didToggle)
        XCTAssertEqual(otherSession.text, "- [x] embedded\n")
        XCTAssertFalse(otherSession.hasUnsavedChanges, "Saved at once, since reading view draws an embedded note from its file.")
        XCTAssertEqual(try fileData("Other.md"), Data("- [x] embedded\n".utf8))
    }

    func testTaskOfAnEmbeddedNoteChangedSinceItWasDrawnIsNotTicked() async throws {
        try write(Data("- [ ] embedded\n".utf8), to: "Other.md")
        let hostText = "![[Other]]\n"
        try write(Data(hostText.utf8), to: "Host.md")
        try await index.refresh(paths: [try VaultPath("Other.md"), try VaultPath("Host.md")], root: vault)
        let drawn = try await drawnTasks(in: hostText, note: "Host.md")
        let task = try XCTUnwrap(drawn.first)
        try write(Data("- [ ] added first\n- [ ] embedded\n".utf8), to: "Other.md")

        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        let hostSession = try await session(for: "Host.md")
        let didToggle = await workspace.toggleReadingTask(at: try XCTUnwrap(task.task.location), in: task.note, shownBy: hostSession)
        XCTAssertFalse(didToggle)
        XCTAssertEqual(try fileData("Other.md"), Data("- [ ] added first\n- [ ] embedded\n".utf8))
    }

    // MARK: Checkboxes that cannot be ticked

    func testCheckboxesOutsideTheNotesLinesArePictures() async throws {
        let text = "Claim[^n].\n\n[^n]: - [ ] a task in a footnote\n"
        let notePath = try VaultPath("Note.md")
        let build = try await ReadingViewBuilder().build(source: text, note: notePath, root: vault, index: index, configuration: ReadingConfiguration())
        guard case .footnotes(_, let notes)? = build.blocks.last else { return XCTFail("Expected the footnotes") }
        let tasks = try drawnTasks(inMarkdown: try XCTUnwrap(notes.first?.text), note: notePath)
        XCTAssertEqual(tasks.map(\.text), ["a task in a footnote"])
        XCTAssertNil(tasks.first?.task.location, "A footnote is shown away from its lines, so its checkbox is a picture.")
    }

    func testPrivateUseCharactersOfTheNoteAreNotReadAsMarkers() async throws {
        let text = "Glyphs \u{E005}32 and \u{E00A}x \\tag{1}\u{E00B} stay.\n- [ ] task\n"
        let notePath = try VaultPath("Note.md")
        let build = try await ReadingViewBuilder().build(source: text, note: notePath, root: vault, index: index, configuration: ReadingConfiguration())
        let rendered = try markdownTexts(build.blocks).map { markdown in
            String(try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: markdown).characters)
        }.joined()
        XCTAssertTrue(rendered.contains("Glyphs \u{E005}32 and \u{E00A}x \\tag{1}\u{E00B} stay."))
        XCTAssertEqual(try drawnTasks(in: build.blocks, note: notePath).map(\.text), ["task"])
    }
}
