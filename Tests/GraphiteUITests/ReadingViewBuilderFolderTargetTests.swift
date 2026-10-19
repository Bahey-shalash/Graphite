import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// A folder is not the target of a Wikilink or an embed in the reading view: a name that is
/// also a folder's means the note of that name, wherever it is, as it does in the editor.
@MainActor
final class ReadingViewBuilderFolderTargetTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "FolderTargetVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault) // Best-effort removal of a temporary folder.
    }

    private func write(_ text: String, to path: String) throws {
        let location = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func build(_ source: String, marksUnresolvedLinks: Bool = false) async throws -> ReadingViewBuild {
        _ = try await index.reconcile(root: vault)
        var configuration = ReadingConfiguration()
        configuration.marksUnresolvedLinks = marksUnresolvedLinks
        return try await ReadingViewBuilder().build(source: source, note: try VaultPath("Host.md"), root: vault, index: index, configuration: configuration)
    }

    func testEmbedNamedLikeAFolderEmbedsTheFolderNoteInsideIt() async throws {
        try write("The folder note.", to: "Projects/Projects.md")
        let build = try await build("![[Projects]]\n")
        guard case .transclusion(_, let path, _, _)? = build.blocks.first else { return XCTFail("Expected the folder note to be embedded, got \(build.blocks)") }
        XCTAssertEqual(path.rawValue, "Projects/Projects.md")
    }

    func testLinkNamedLikeAFolderIsMarkedUnresolvedWhenNoNoteHasThatName() async throws {
        try write("A note in the folder.", to: "Projects/Plan.md")
        let build = try await build("See [[Projects]].\n", marksUnresolvedLinks: true)
        guard case .markdown(_, let text)? = build.blocks.first else { return XCTFail("Expected Markdown, got \(build.blocks)") }
        XCTAssertTrue(text.contains("unresolved=1"), "A folder is no note to link to: \(text)")
    }

    func testNoteBesideAFolderOfTheSameNameStillResolvesAndEmbeds() async throws {
        try write("The note.", to: "Projects.md")
        try write("A note in the folder.", to: "Projects/Plan.md")
        let linked = try await build("See [[Projects]].\n", marksUnresolvedLinks: true)
        guard case .markdown(_, let text)? = linked.blocks.first else { return XCTFail("Expected Markdown, got \(linked.blocks)") }
        XCTAssertFalse(text.contains("unresolved=1"))
        let embedded = try await build("![[Projects]]\n")
        guard case .transclusion(_, let path, _, _)? = embedded.blocks.first else { return XCTFail("Expected the note to be embedded, got \(embedded.blocks)") }
        XCTAssertEqual(path.rawValue, "Projects.md")
    }
}
