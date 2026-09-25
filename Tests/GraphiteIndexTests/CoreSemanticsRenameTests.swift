import XCTest
@testable import GraphiteIndex
import GraphiteCore

/// Renames rewrite exactly the links MarkdownSemantics locates, so its ranges must be
/// exact in notes with Windows line endings and indented continuation lines.
final class CoreSemanticsRenameTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var operations: VaultFileOperations!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try write("Old.md", "old")
        try write("Other.md", "other")
        try write("CRLF.md", "[b](Old.md) x\r\n[a](Old.md)\r\n`[[Old]]` in code\r\n[o](Other.md) and [[Old]]\r\n")
        try write("Indented.md", "Some paragraph\n  continued with [Old](Old.md) here.\n> quote\n   lazily [q](Old.md)\n- item\n\tthen [t](Old.md)\n")
        try write("Breaks.md", "Line\\\n[a](Old.md) and\\\n[b](Other.md)\n[c](Old.md\n\"Title\") end\n> x\\\r\n> [d](Old.md)\n")
        try write("Definition.md", "[r]: Other.md\ntext [x](Old.md) [y](Other.md)\n")
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        operations = VaultFileOperations(store: VaultStore(root: vault), index: index)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ relativePath: String, _ text: String) throws {
        try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
    }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testRenameRewritesExactlyTheLinksInWindowsAndIndentedNotes() async throws {
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Old.md"), to: VaultPath("Folder/New.md"))
        let report = try await operations.move(VaultPath("Old.md"), to: VaultPath("Folder/New.md"), applying: plan)
        XCTAssertEqual(Set(report.updatedNotes.map(\.rawValue)).subtracting(["Definition.md"]), ["CRLF.md", "Indented.md", "Breaks.md"])
        XCTAssertEqual(try read("CRLF.md"), "[b](Folder/New.md) x\r\n[a](Folder/New.md)\r\n`[[Old]]` in code\r\n[o](Other.md) and [[New]]\r\n",
                       "Line endings, code and the other link stay as written.")
        XCTAssertEqual(try read("Indented.md"),
                       "Some paragraph\n  continued with [Old](Folder/New.md) here.\n> quote\n   lazily [q](Folder/New.md)\n- item\n\tthen [t](Folder/New.md)\n")
        XCTAssertEqual(try read("Breaks.md"), "Line\\\n[a](Folder/New.md) and\\\n[b](Other.md)\n[c](Folder/New.md\n\"Title\") end\n> x\\\r\n> [d](Folder/New.md)\n",
                       "Hard breaks and a title on its own line do not shift the links after them.")
        // A leading reference definition moves cmark's positions; that link may stay as it
        // was, but no other text changes.
        XCTAssertTrue(["[r]: Other.md\ntext [x](Old.md) [y](Other.md)\n", "[r]: Other.md\ntext [x](Folder/New.md) [y](Other.md)\n"].contains(try read("Definition.md")))
    }
}
