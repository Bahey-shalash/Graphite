import XCTest
@testable import GraphiteCore

/// A link names a file, never a folder: `WikiLinkResolver.existingDirectFile` skips a folder
/// that has the written name.
final class WikiLinkResolverExistingFileTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("ResolverVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Projects"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: vault)
    }

    private func write(_ relativePath: String) throws {
        try Data("text".utf8).write(to: vault.appendingPathComponent(relativePath))
    }

    private func resolved(_ target: String, from source: String = "Host.md", isWiki: Bool = true) throws -> String? {
        WikiLinkResolver.existingDirectFile(target: target, source: try VaultPath(source), isWiki: isWiki, in: vault)?.rawValue
    }

    func testAFolderWithTheWrittenNameIsNotAFile() throws {
        XCTAssertNil(try resolved("Projects"))
    }

    func testTheNoteBesideAFolderOfTheSameNameIsFound() throws {
        try write("Projects.md")
        XCTAssertEqual(try resolved("Projects"), "Projects.md")
    }

    func testAFileWithoutAnExtensionIsFoundByItsWholeName() throws {
        try write("LICENSE")
        XCTAssertEqual(try resolved("LICENSE"), "LICENSE")
    }

    func testAFolderNextToTheLinkingNoteIsSkippedForTheRootNote() throws {
        try write("Notes.md")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Area/Notes"), withIntermediateDirectories: true)
        XCTAssertEqual(try resolved("Notes", from: "Area/Host.md"), "Notes.md")
    }

    func testAMissingFileIsNotFound() throws {
        XCTAssertNil(try resolved("Nothing"))
    }
}
