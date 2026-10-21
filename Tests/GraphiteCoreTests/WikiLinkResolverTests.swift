import XCTest
@testable import GraphiteCore

/// Where links lead, as Obsidian resolves them.
final class WikiLinkResolverTests: XCTestCase {
    /// `[[/Folder/Note]]` starts at the vault root, and only there: it named a path beside the note.
    func testALinkStartingWithASlashIsFromTheVaultRootOnly() throws {
        let source = try VaultPath("A/x.md")
        XCTAssertEqual(WikiLinkResolver.directCandidates(target: "/Folder/Note", source: source).map(\.rawValue), ["Folder/Note.md", "Folder/Note"])
    }

    /// A Wikilink is written as the file is named; a Markdown link is percent-encoded.
    func testOnlyMarkdownLinksArePercentDecoded() throws {
        let source = try VaultPath("x.md")
        XCTAssertEqual(WikiLinkResolver.directCandidates(target: "A%20B", source: source, isWiki: true).first?.rawValue, "A%20B.md")
        XCTAssertEqual(WikiLinkResolver.directCandidates(target: "A%20B.md", source: source, isWiki: false).first?.rawValue, "A B.md")
    }
}
