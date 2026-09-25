import XCTest
@testable import GraphiteCore

final class TagsAndPropertiesTests: XCTestCase {
    // MARK: Tags

    func testNestsTagsAndSortsEachLevel() {
        let nodes = TagTree.nodes(from: [
            ("course", 5), ("course/math", 3), ("course/physics", 4), ("course/math/linear", 1), ("exam", 2),
        ], sortedBy: .frequencyDescending)
        XCTAssertEqual(nodes.map(\.tag), ["course", "exam"])
        XCTAssertEqual(nodes.first?.children.map(\.name), ["physics", "math"], "Most used first.")
        XCTAssertEqual(nodes.first?.children.last?.children.map(\.tag), ["course/math/linear"])
        XCTAssertEqual(nodes.last?.children, [])

        let byName = TagTree.nodes(from: [("b", 1), ("a/z", 1), ("a", 2), ("a/y", 1)], sortedBy: .nameAscending)
        XCTAssertEqual(byName.map(\.tag), ["a", "b"])
        XCTAssertEqual(byName.first?.children.map(\.name), ["y", "z"])
    }

    func testAddsMissingLevelsAndMergesCapitals() {
        let nodes = TagTree.nodes(from: [("Project/alpha/notes", 2), ("project/beta", 1)], sortedBy: .nameAscending)
        XCTAssertEqual(nodes.count, 1, "Project and project are one tag.")
        XCTAssertEqual(nodes.first?.fileCount, 2, "A missing level takes the largest count below it.")
        XCTAssertEqual(nodes.first?.children.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(nodes.first?.children.first?.children.map(\.tag), ["Project/alpha/notes"])
    }

    func testSortOrdersBreakTiesByName() {
        let items = [("b", 2), ("a", 2), ("c", 5), ("Item 10", 1), ("Item 9", 1)]
        XCTAssertEqual(VaultListSortOrder.nameAscending.sorted(items, name: \.0, count: \.1).map(\.0), ["a", "b", "c", "Item 9", "Item 10"])
        XCTAssertEqual(VaultListSortOrder.nameDescending.sorted(items, name: \.0, count: \.1).map(\.0), ["Item 10", "Item 9", "c", "b", "a"])
        XCTAssertEqual(VaultListSortOrder.frequencyDescending.sorted(items, name: \.0, count: \.1).map(\.0), ["c", "a", "b", "Item 9", "Item 10"])
        XCTAssertEqual(VaultListSortOrder.frequencyAscending.sorted(items, name: \.0, count: \.1).map(\.0), ["Item 9", "Item 10", "a", "b", "c"])
    }

    // MARK: Property types

    func testInfersTypesAsObsidianDoes() {
        func type(_ key: String, _ samples: [BaseFrontmatterNode], declared: [String: PropertyType] = [:]) -> PropertyType {
            NoteProperties.type(ofKey: key, sampleValues: samples, declaredTypes: declared)
        }
        XCTAssertEqual(type("rating", [.scalar(text: "", isPlain: true), .scalar(text: "4", isPlain: true)]), .number, "Empty values are skipped.")
        XCTAssertEqual(type("rating", [.scalar(text: "4", isPlain: false)]), .text, "A quoted number is text.")
        XCTAssertEqual(type("done", [.scalar(text: "true", isPlain: true)]), .checkbox)
        XCTAssertEqual(type("due", [.scalar(text: "2026-10-01", isPlain: true)]), .date)
        XCTAssertEqual(type("start", [.scalar(text: "2026-10-01T09:30", isPlain: true)]), .datetime)
        XCTAssertEqual(type("authors", [.sequence([.scalar(text: "Ada", isPlain: true)])]), .multitext)
        XCTAssertEqual(type("Tags", [.scalar(text: "x", isPlain: true)]), .tags, "The name decides for tags and aliases.")
        XCTAssertEqual(type("rating", [.scalar(text: "4", isPlain: true)], declared: ["Rating": .text]), .text, "types.json wins, ignoring capitals.")
        XCTAssertEqual(type("empty", []), .text)
    }

    // MARK: Renaming properties

    private func renamed(_ key: String, to newKey: String, in text: String) throws -> String? {
        guard let edit = try PropertyRenaming.edit(renaming: key, to: newKey, in: text) else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testRenamesOnlyTheNameAndKeepsTheRestByteForByte() throws {
        let note = "---\nstatus:   draft # a comment\nlist:\n  - one\n  - two\nstatusNote: keep\n---\nstatus: in the body stays\n"
        XCTAssertEqual(try renamed("status", to: "state", in: note),
                       "---\nstate:   draft # a comment\nlist:\n  - one\n  - two\nstatusNote: keep\n---\nstatus: in the body stays\n")
        XCTAssertEqual(try renamed("STATUS", to: "state", in: note)?.hasPrefix("---\nstate:"), true, "Names match ignoring capitals.")
        XCTAssertEqual(try renamed("list", to: "items", in: note), note.replacingOccurrences(of: "\nlist:", with: "\nitems:"))
        XCTAssertNil(try renamed("missing", to: "other", in: note))
        XCTAssertNil(try renamed("status", to: "state", in: "No frontmatter.\nstatus: here\n"))
        XCTAssertNil(try renamed("status", to: "status", in: note), "Nothing to do.")
    }

    func testRenamesQuotedNamesAndQuotesNewOnesThatNeedIt() throws {
        let note = "---\r\n\"due date\": 2026-10-01\r\n'it''s': yes\r\n---\r\nBody"
        XCTAssertEqual(try renamed("due date", to: "deadline", in: note), "---\r\ndeadline: 2026-10-01\r\n'it''s': yes\r\n---\r\nBody")
        XCTAssertEqual(try renamed("it's", to: "flag", in: note), "---\r\n\"due date\": 2026-10-01\r\nflag: yes\r\n---\r\nBody")
        XCTAssertEqual(try renamed("due date", to: "2026", in: note), "---\r\n\"2026\": 2026-10-01\r\n'it''s': yes\r\n---\r\nBody",
                       "A name YAML would read as a number is quoted.")
    }

    func testRefusesRenamesThatWouldLoseOrMergeProperties() {
        XCTAssertThrowsError(try renamed("status", to: "Mood", in: "---\nstatus: a\nmood: b\n---\n"), "The note already has that name.")
        XCTAssertThrowsError(try renamed("status", to: "state", in: "---\nstatus: [unclosed\n---\n"), "Invalid YAML is left alone.")
        XCTAssertThrowsError(try renamed("status", to: "  ", in: "---\nstatus: a\n---\n"))
    }

    func testKeepsTheCursorOnTheSameText() throws {
        let note = "---\nstatus: draft\n---\nBody"
        let bodyLocation = (note as NSString).range(of: "Body").location
        let edit = try XCTUnwrap(PropertyRenaming.edit(renaming: "status", to: "st", in: note, selection: NSRange(location: bodyLocation, length: 0)))
        XCTAssertEqual(edit.selectionAfter, NSRange(location: bodyLocation - 4, length: 0))
        let insideName = try XCTUnwrap(PropertyRenaming.edit(renaming: "status", to: "st", in: note, selection: NSRange(location: 6, length: 0)))
        XCTAssertEqual(insideName.selectionAfter, NSRange(location: 6, length: 0), "Moved to the end of the new name.")
    }

    // MARK: types.json

    func testAssignsAndMovesPropertyTypesKeepingTheRestOfTheFile() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vault) }
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        let typesLocation = vault.appendingPathComponent(".obsidian/types.json")
        try Data(#"{"types":{"Rating":"number","tags":"tags"},"other":1}"#.utf8).write(to: typesLocation)
        let store = VaultStore(root: vault)

        try await store.setPropertyType(.text, forKey: "rating")
        var types = await store.propertyTypes()
        XCTAssertEqual(types, ["Rating": .text, "tags": .tags], "The name as already written is kept.")
        try await store.movePropertyType(from: "RATING", to: "score")
        types = await store.propertyTypes()
        XCTAssertEqual(types, ["score": .text, "tags": .tags])
        let configuration = try JSONSerialization.jsonObject(with: Data(contentsOf: typesLocation)) as? [String: Any]
        XCTAssertEqual(configuration?["other"] as? Int, 1, "Keys Graphite does not know stay.")

        let before = try Data(contentsOf: typesLocation)
        try await store.movePropertyType(from: "missing", to: "anything")
        XCTAssertEqual(try Data(contentsOf: typesLocation), before, "Nothing to move leaves the file untouched.")

        try Data("[1, 2]".utf8).write(to: typesLocation)
        do {
            try await store.setPropertyType(.number, forKey: "x")
            XCTFail("A types.json that is not an object is not overwritten.")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: typesLocation), Data("[1, 2]".utf8))
    }
}
