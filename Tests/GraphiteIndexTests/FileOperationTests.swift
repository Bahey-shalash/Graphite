import XCTest
@testable import GraphiteIndex
import GraphiteCore

final class FileOperationTests: XCTestCase {
    private var vault: URL!
    private var store: VaultStore!
    private var index: VaultIndex!
    private var operations: VaultFileOperations!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        for folder in ["Notes", "Other"] { try FileManager.default.createDirectory(at: vault.appendingPathComponent(folder), withIntermediateDirectories: true) }
        try write("Notes/Old name.md", "# Heading\n![](pic.png) [[Sibling]] [[./Sibling]]")
        try write("Notes/Sibling.md", "sibling")
        try write("Notes/pic.png", "not really a picture")
        try write("Notes/Linker.md", "[[Old name]] [[Old name#Heading|alias]] ![[Old name]] [x](Old%20name.md) [y](../Notes/Old%20name.md#Heading) [[Notes/Old name]] `[[Old name]]`")
        try write("Other/Deep.md", "[[Old name.md]] and [text](<../Notes/Old name.md>)\n\n| a | [[Old name\\|table alias]] |")
        try write("Other/Props.md", "---\nrelated: \"[[Old name]]\"\n---\nBody")
        store = VaultStore(root: vault)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        operations = VaultFileOperations(store: store, index: index)
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

    private func move(_ source: String, _ destination: String) async throws -> MoveReport {
        let plan = try await operations.linkUpdates(forMoving: VaultPath(source), to: VaultPath(destination))
        return try await operations.move(VaultPath(source), to: VaultPath(destination), applying: plan)
    }

    func testRenameRewritesEveryLinkInItsOwnStyle() async throws {
        let report = try await move("Notes/Old name.md", "Notes/New name.md")
        XCTAssertEqual(Set(report.updatedNotes.map(\.rawValue)), ["Notes/Linker.md", "Other/Deep.md", "Other/Props.md"])
        XCTAssertEqual(try read("Notes/Linker.md"),
                       "[[New name]] [[New name#Heading|alias]] ![[New name]] [x](New%20name.md) [y](New%20name.md#Heading) [[Notes/New name]] `[[Old name]]`")
        XCTAssertEqual(try read("Other/Deep.md"), "[[New name.md]] and [text](<../Notes/New name.md>)\n\n| a | [[New name\\|table alias]] |")
        XCTAssertEqual(try read("Other/Props.md"), "---\nrelated: \"[[New name]]\"\n---\nBody")
        XCTAssertEqual(try read("Notes/New name.md"), "# Heading\n![](pic.png) [[Sibling]] [[./Sibling]]", "Its own links still work from the same folder.")
    }

    func testMovingToAnotherFolderRewritesPathsAndTheNotesOwnRelativeLinks() async throws {
        _ = try await move("Notes/Old name.md", "Other/Old name.md")
        XCTAssertEqual(try read("Notes/Linker.md"),
                       "[[Old name]] [[Old name#Heading|alias]] ![[Old name]] [x](../Other/Old%20name.md) [y](../Other/Old%20name.md#Heading) [[Other/Old name]] `[[Old name]]`")
        XCTAssertEqual(try read("Other/Old name.md"), "# Heading\n![](../Notes/pic.png) [[Sibling]] [[../Notes/Sibling]]")
        XCTAssertEqual(try read("Other/Deep.md"), "[[Old name.md]] and [text](<Old name.md>)\n\n| a | [[Old name\\|table alias]] |")
    }

    func testRenamingAFolderMovesEveryLinkIntoIt() async throws {
        _ = try await move("Notes", "Lectures")
        XCTAssertEqual(try read("Lectures/Linker.md"),
                       "[[Old name]] [[Old name#Heading|alias]] ![[Old name]] [x](Old%20name.md) [y](Old%20name.md#Heading) [[Lectures/Old name]] `[[Old name]]`")
        XCTAssertEqual(try read("Other/Deep.md"), "[[Old name.md]] and [text](<../Lectures/Old name.md>)\n\n| a | [[Old name\\|table alias]] |")
    }

    func testANameThatBecomesAmbiguousGetsAPath() async throws {
        try write("Other/New name.md", "another note with the same name")
        _ = try await index.reconcile(root: vault)
        _ = try await move("Notes/Old name.md", "Notes/New name.md")
        XCTAssertTrue(try read("Notes/Linker.md").hasPrefix("[[Notes/New name]] [[Notes/New name#Heading|alias]]"))
    }

    func testANoteChangedAfterPlanningIsLeftAlone() async throws {
        let plan = try await operations.linkUpdates(forMoving: VaultPath("Notes/Old name.md"), to: VaultPath("Notes/New name.md"))
        try write("Other/Deep.md", "edited elsewhere [[Old name]]")
        let report = try await operations.move(VaultPath("Notes/Old name.md"), to: VaultPath("Notes/New name.md"), applying: plan)
        XCTAssertEqual(report.notesNotUpdated.map(\.rawValue), ["Other/Deep.md"])
        XCTAssertEqual(try read("Other/Deep.md"), "edited elsewhere [[Old name]]")
    }

    func testStoreRefusesToReplaceAndKeepsDeletedFiles() async throws {
        do {
            try await store.move(VaultPath("Notes/Old name.md"), to: VaultPath("Notes/Sibling.md"))
            XCTFail("Moving onto another file must fail.")
        } catch {}
        XCTAssertEqual(try read("Notes/Sibling.md"), "sibling")
        do {
            try await store.move(VaultPath("Notes"), to: VaultPath("Notes/Inside"))
            XCTFail("A folder cannot move into itself.")
        } catch {}
        let copy = try await store.duplicate(VaultPath("Notes/Sibling.md"))
        XCTAssertEqual(copy.rawValue, "Notes/Sibling 1.md")
        let trashed = try await store.delete(VaultPath("Notes/Sibling 1.md"), method: .vaultTrash)
        XCTAssertEqual(trashed, .movedToVaultTrash(try VaultPath(".trash/Sibling 1.md")))
        XCTAssertEqual(try read(".trash/Sibling 1.md"), "sibling")
        let folder = try await store.createFolder(named: "Week 1", in: VaultPath("Notes"))
        XCTAssertEqual(folder.rawValue, "Notes/Week 1")
        let permanentlyDeleted = try await store.delete(folder, method: .permanent)
        XCTAssertEqual(permanentlyDeleted, .deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Notes/Week 1").path))
        XCTAssertNotNil(FileNameRules.problem(with: "a/b", isNote: false))
        XCTAssertNotNil(FileNameRules.problem(with: "Topic #1", isNote: true))
        XCTAssertNil(FileNameRules.problem(with: "Topic #1", isNote: false))
        XCTAssertNotNil(FileNameRules.problem(with: ".hidden", isNote: false))
    }
}

