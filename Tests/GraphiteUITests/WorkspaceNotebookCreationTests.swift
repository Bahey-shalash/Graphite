import XCTest
import PDFKit
import GraphiteCore
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

/// Creating a notebook from inside a note, embedded or in a folder, against real vault folders.
@MainActor
final class WorkspaceNotebookCreationTests: XCTestCase {
    private let options = NewNotebookOptions(paperChoice: .ruledNarrow, paperStyle: PaperSpecification(template: .blank),
                                             pageSize: .named(.a5, .landscape), pageCount: 3)

    private func makeVault(files: [String: String]) throws -> URL {
        try TemporaryVault.make(prefix: "NotebookCreationVault", files: files, for: self).root
    }

    private func openedNote(_ path: String, in vault: URL) async throws -> (WorkspaceModel, MarkdownSession) {
        let workspace = try IsolatedWorkspaceDevice.make(for: self).makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath(path))
        return (workspace, try XCTUnwrap(workspace.markdownSession))
    }

    func testEmbeddedNotebookGoesWithTheAttachmentsAndIsEmbeddedAtTheCursor() async throws {
        // Attachments in the note's own folder.
        let vault = try makeVault(files: ["Courses/Week 1.md": "Before\nAfter", ".obsidian/app.json": #"{"attachmentFolderPath": "./"}"#])
        let (workspace, session) = try await openedNote("Courses/Week 1.md", in: vault)
        let cursor = NSRange(location: ("Before\n" as NSString).length, length: 0)

        await workspace.createNotebook(named: "Sketches", options: options, placement: .embeddedInNote, from: session, at: cursor, textWhenChosen: session.text)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(session.text.contains("![[Sketches.pdf]]"), session.text)
        XCTAssertTrue(session.text.hasPrefix("Before\n"), session.text)
        let document = try XCTUnwrap(PDFDocument(url: vault.appendingPathComponent("Courses/Sketches.pdf")))
        XCTAssertEqual(document.pageCount, 3)
        let pageBounds = try XCTUnwrap(document.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(pageBounds.width, 595.28, accuracy: 0.01)
        XCTAssertEqual(pageBounds.height, 419.53, accuracy: 0.01)
    }

    func testNotebookInAFolderIsItsOwnFileWithALinkInTheNote() async throws {
        let vault = try makeVault(files: ["Courses/Analysis/Week 1.md": "Notes"])
        let (workspace, session) = try await openedNote("Courses/Analysis/Week 1.md", in: vault)
        let end = NSRange(location: (session.text as NSString).length, length: 0)

        await workspace.createNotebook(named: "Lecture", options: options, placement: .inFolder(try VaultPath("Courses"), insertsEmbed: false),
                                       from: session, at: end, textWhenChosen: session.text)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Courses/Lecture.pdf").path))
        XCTAssertTrue(session.text.contains("Lecture.pdf]]"), session.text)
        XCTAssertFalse(session.text.contains("!["), session.text)
    }

    func testAnExistingNameGetsAFreeOneAndTheOriginalIsUntouched() async throws {
        let vault = try makeVault(files: ["Week 1.md": "", "Lecture.pdf": "not a real PDF"])
        let (workspace, session) = try await openedNote("Week 1.md", in: vault)

        await workspace.createNotebook(named: "Lecture", options: options, placement: .inFolder(.root, insertsEmbed: true),
                                       from: session, at: NSRange(location: 0, length: 0), textWhenChosen: session.text)

        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Lecture.pdf"), encoding: .utf8), "not a real PDF")
        XCTAssertNotNil(PDFDocument(url: vault.appendingPathComponent("Lecture 1.pdf")))
        XCTAssertTrue(session.text.contains("![[Lecture 1.pdf]]"), session.text)
    }

    func testTextTypedWhileTheNotebookIsWrittenIsKept() async throws {
        let vault = try makeVault(files: ["Week 1.md": "Keep this"])
        let (workspace, session) = try await openedNote("Week 1.md", in: vault)
        let textWhenChosen = session.text
        let cursor = NSRange(location: (textWhenChosen as NSString).length, length: 0)
        session.text = "IMPORTANT " + textWhenChosen

        await workspace.createNotebook(named: "Ink", options: options, placement: .embeddedInNote, from: session, at: cursor, textWhenChosen: textWhenChosen)

        XCTAssertTrue(session.text.hasPrefix("IMPORTANT Keep this"), session.text)
        XCTAssertTrue(session.text.contains("Ink.pdf"), session.text)
    }
}
