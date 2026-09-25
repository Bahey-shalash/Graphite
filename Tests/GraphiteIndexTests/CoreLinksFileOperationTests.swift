import XCTest
@testable import GraphiteIndex
import GraphiteCore

/// Moves and renames through the real store, index and link planner, for link forms whose
/// rewrite used to corrupt the note or leave the link behind.
final class CoreLinksFileOperationTests: XCTestCase {
    private var vault: URL!
    private var store: VaultStore!
    private var index: VaultIndex!
    private var operations: VaultFileOperations!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("CoreLinksVault-\(UUID().uuidString)")
        for folder in ["Notes", "Other", "Attachments"] { try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder), withIntermediateDirectories: true) }
        store = VaultStore(root: vault)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        operations = VaultFileOperations(store: store, index: index)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ files: [String: String]) async throws {
        for (relativePath, text) in files { try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath)) }
        _ = try await index.reconcile(root: vault)
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @discardableResult
    private func move(_ source: String, _ destination: String) async throws -> MoveReport {
        let plan = try await operations.linkUpdates(forMoving: VaultPath(source), to: VaultPath(destination))
        return try await operations.move(VaultPath(source), to: VaultPath(destination), applying: plan)
    }

    func testDestinationsWithParenthesesAreRewrittenWhole() async throws {
        try await write(["Notes/Linker.md": "See ![](Pasted%20image%20(2).png) and [x](Lecture%20(1).md) end",
                         "Notes/Pasted image (2).png": "image", "Notes/Lecture (1).md": "lecture"])
        try await move("Notes/Pasted image (2).png", "Attachments/Pasted image (2).png")
        try await move("Notes/Lecture (1).md", "Other/Lecture (1).md")
        XCTAssertEqual(try read("Notes/Linker.md"), "See ![](../Attachments/Pasted%20image%20%282%29.png) and [x](../Other/Lecture%20%281%29.md) end")
    }

    func testAnImageInsideALinkIsRewrittenWithTheLink() async throws {
        try await write(["Notes/Card.md": "Badge [![logo](logo.png)](Target.md) done", "Notes/Target.md": "target", "Notes/logo.png": "image"])
        let report = try await move("Notes/Card.md", "Other/Card.md")
        XCTAssertEqual(try read("Other/Card.md"), "Badge [![logo](../Notes/logo.png)](../Notes/Target.md) done")
        XCTAssertEqual(report.updatedNotes.map(\.rawValue), ["Other/Card.md"])
    }

    func testRenamingAFolderRewritesAnImageInsideALink() async throws {
        try await write(["Index.md": "[![logo](Notes/logo.png)](Notes/Target.md)", "Notes/Target.md": "target", "Notes/logo.png": "image"])
        try await move("Notes", "Moved")
        XCTAssertEqual(try read("Index.md"), "[![logo](Moved/logo.png)](Moved/Target.md)")
    }

    func testMovingANoteKeepsItsAliasLinks() async throws {
        try await write(["Notes/Mover.md": "see [[Fourier]] here and [[fourier transform]]", "Other/Fourier Transform.md": "---\naliases: [Fourier]\n---\nBody"])
        try await move("Notes/Mover.md", "Other/Mover.md")
        XCTAssertEqual(try read("Other/Mover.md"), "see [[Fourier]] here and [[fourier transform]]")
    }

    func testRenamingToANameWithAQuoteKeepsThePropertiesValid() async throws {
        try await write(["Linker.md": "---\naliases: [Linky]\nrelated: '[[Newton]]'\n---\nBody", "Newton.md": "laws"])
        try await move("Newton.md", "Newton's laws.md")
        let updated = try read("Linker.md")
        XCTAssertEqual(updated, "---\naliases: [Linky]\nrelated: '[[Newton''s laws]]'\n---\nBody")
        XCTAssertEqual(try MarkdownSemantics.parse(updated).aliases, ["Linky"])
    }

    func testReferenceDefinitionsFollowARename() async throws {
        try await write(["Linker.md": "see [the note][ref]\n\n[ref]: Target.md\n", "Target.md": "target"])
        let report = try await move("Target.md", "Renamed.md")
        XCTAssertEqual(try read("Linker.md"), "see [the note][ref]\n\n[ref]: Renamed.md\n")
        XCTAssertEqual(report.updatedNotes.map(\.rawValue), ["Linker.md"])
    }

    func testTitlesAndLettersBeyondASCIIKeepTheirForm() async throws {
        try await write(["Linker.md": "see [x](Target.md \"a](b\") and [y](Café.md) end", "Target.md": "target", "Café.md": "café"])
        try await move("Linker.md", "Notes/Linker.md")
        XCTAssertEqual(try read("Notes/Linker.md"), "see [x](../Target.md \"a](b\") and [y](../Café.md) end")
    }
}
