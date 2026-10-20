import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// The reading view folds headings and remembers callouts under the keys the editor, Live
/// Preview and Read Aloud use, whatever the reading view makes of the heading or the title.
@MainActor
final class ReadingViewBuilderFoldKeyTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "FoldKeyVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault) // Best-effort removal of a temporary folder.
    }

    private func build(_ source: String) async throws -> ReadingViewBuild {
        try await ReadingViewBuilder().build(source: source, note: try VaultPath("Note.md"), root: vault, index: index, configuration: ReadingConfiguration())
    }

    /// The fold key the reading view uses for each heading block, in order.
    private func headingKeys(_ build: ReadingViewBuild) -> [String?] {
        build.blocks.compactMap { block in
            if case .heading = block { build.foldKeys.headingKeysByBlock[block.id] } else { nil }
        }
    }

    func testHeadingsRewrittenForDisplayKeepTheEditorsFoldKeys() async throws {
        let source = "## Title ##\nBody\n\n##   Spaced\nBody\n\n## See [[Plan]]\nBody\n\n## A ==marked== word\nBody\n"
        let editorKeys = NoteFolding.regions(in: source).map(\.key)
        XCTAssertEqual(editorKeys, ["h2|## Title ##|0", "h2|##   Spaced|0", "h2|## See [[Plan]]|0", "h2|## A ==marked== word|0"])
        let build = try await build(source)
        XCTAssertEqual(headingKeys(build), editorKeys)
    }

    func testHeadingsAfterFrontmatterAndInsideCommentsAreNumberedAsTheEditorNumbersThem() async throws {
        let source = "---\ntitle: x\n---\n%%\n## Same\nHidden\n%%\n## Same\nBody\n"
        let build = try await build(source)
        XCTAssertEqual(headingKeys(build), ["h2|## Same|1"], "The editor counts the heading inside the comment, so this is its second occurrence.")
        XCTAssertEqual(NoteFolding.regions(in: source).map(\.key), ["h2|## Same|0", "h2|## Same|1"])
    }

    func testSetextHeadingsHaveTheEditorsFoldKeys() async throws {
        let source = "Title\n=====\nBody\n"
        let build = try await build(source)
        XCTAssertEqual(headingKeys(build), ["h1|Title|0"])
    }

    func testCalloutsKeepTheirWrittenTitleForTheFoldKey() async throws {
        let source = "> [!note]- See [[Plan]] and ==marked==\n> Body\n\n> [!tip]+ Plain title\n> More\n"
        let build = try await build(source)
        let callouts = build.blocks.compactMap { block -> (id: String, title: String)? in
            if case .callout(_, _, let title, _, _) = block { (block.id, title) } else { nil }
        }
        XCTAssertEqual(callouts.count, 2)
        guard callouts.count == 2 else { return }
        XCTAssertNotEqual(callouts[0].title, "See [[Plan]] and ==marked==", "The displayed title is rewritten, which is why the written one is kept.")
        XCTAssertEqual(build.foldKeys.calloutTitlesByBlock[callouts[0].id], "See [[Plan]] and ==marked==")
        XCTAssertEqual(build.foldKeys.calloutTitlesByBlock[callouts[1].id], "Plain title")
    }

    func testCalloutNestedInACalloutKeepsItsWrittenTitle() async throws {
        let source = "> [!note]+ Outer\n> > [!warning]- Inner [[Plan]]\n> > Body\n"
        let build = try await build(source)
        guard case .callout(_, _, _, _, let body)? = build.blocks.first, case .callout(let innerIdentifier, _, _, _, _)? = body.first else {
            return XCTFail("Expected a callout in a callout, got \(build.blocks)")
        }
        XCTAssertEqual(build.foldKeys.calloutTitlesByBlock["block-\(innerIdentifier)"], "Inner [[Plan]]")
    }
}
