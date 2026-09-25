import XCTest
import GraphiteCore
@testable import GraphiteUI

@MainActor
final class UiMarkdownPaneContinuationTests: XCTestCase {
    private var vaultDirectory: URL!

    override func setUp() async throws {
        vaultDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MarkdownPaneContinuationVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vaultDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vaultDirectory)
    }

    // MARK: Save a Copy

    func testSaveACopyDoesNotReportFailureWhenTheOtherVersionCannotBeRead() async throws {
        let notePath = try VaultPath("Note.md")
        let noteLocation = vaultDirectory.appendingPathComponent("Note.md")
        try Data("original".utf8).write(to: noteLocation)
        let store = VaultStore(root: vaultDirectory)
        let session = try MarkdownSession(path: notePath, snapshot: try await store.read(notePath), store: store, didSave: { _ in })
        session.text = "my edits"
        // Another app replaced the note with bytes that are not UTF-8.
        try Data([0xFF, 0xFE, 0x00]).write(to: noteLocation)
        await session.checkExternalChange()
        XCTAssertTrue(session.hasExternalConflict)

        let copyPath = try await session.saveSeparateCopy()

        let copyText = String(decoding: try Data(contentsOf: vaultDirectory.appendingPathComponent(copyPath.rawValue)), as: UTF8.self)
        XCTAssertEqual(copyText, "my edits")
        XCTAssertFalse(session.hasExternalConflict)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNotNil(session.errorMessage, "The note says why the other version is not shown")
        XCTAssertEqual(Array(try Data(contentsOf: noteLocation)), [0xFF, 0xFE, 0x00], "The other app's file is left as it is")
    }

    // MARK: Outgoing links

    func testOutgoingLinksKeepWhetherEachLinkIsAWikilink() throws {
        let semantics = try MarkdownSemantics.parse("[[Other]] and [x](Missing%20Note.md) and [[Other|again]] and [y](Other)\n")
        let outgoingLinks = NoteLinksInspector.outgoingLinks(in: semantics.links)
        XCTAssertEqual(outgoingLinks, [
            NoteLinksInspector.OutgoingLink(target: "Missing%20Note.md", isWiki: false),
            NoteLinksInspector.OutgoingLink(target: "Other", isWiki: true),
            NoteLinksInspector.OutgoingLink(target: "Other", isWiki: false),
        ])
    }

    // MARK: Heading suggestions

    func testHeadingSuggestionsReadTheSameHeadingsAsTheParsedBody() throws {
        let samples = [
            "# One\n\n## Two\ntext",
            "---\ntitle: Test\n---\n# After frontmatter\n\n### Deep",
            "---\r\ntitle: CRLF\r\n---\r\n# Windows\r\n",
            "No frontmatter\n---\n# Not a property\n",
            "---\n---\n# Empty frontmatter",
            "",
        ]
        for sample in samples {
            let expected = NotePreviewDocument.outline(of: try MarkdownSemantics.parse(sample).body)
            let headings = CompletionProvider.headings(inNoteText: sample)
            XCTAssertEqual(headings.map(\.level), expected.map(\.level), sample)
            XCTAssertEqual(headings.map(\.text), expected.map(\.text), sample)
            XCTAssertEqual(headings.map(\.anchor), expected.map(\.anchor), sample)
        }
    }
}
