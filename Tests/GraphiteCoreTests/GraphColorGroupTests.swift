import XCTest
@testable import GraphiteCore

/// Obsidian's graph groups: which files a group's search colors, which group wins, and the
/// stored list that keeps what it does not read.
final class GraphColorGroupTests: XCTestCase {
    private func path(_ text: String) -> VaultPath {
        guard let path = try? VaultPath(text) else { preconditionFailure("Invalid test path \(text)") }
        return path
    }

    /// Two courses, a lab tagged #course/vlsi, a drawing, a link without a file.
    private func courseGraph() -> LinkGraph {
        LinkGraph.build(
            files: [path("Courses/VLSI/Lecture 1.md"), path("Courses/VLSI/Lab.md"), path("Courses/Signals/Sampling.md"),
                    path("Inbox/Idea.md"), path("Courses/VLSI/Layout.png")],
            links: [(path("Courses/VLSI/Lecture 1.md"), path("Courses/VLSI/Layout.png"))],
            unresolvedLinks: [(path("Inbox/Idea.md"), "Courses VLSI plan")],
            tags: [(path("Courses/VLSI/Lab.md"), "course/vlsi"), (path("Inbox/Idea.md"), "Course/vlsi")])
    }

    private func identifier(_ number: Int) -> UUID {
        guard let identifier = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) else { preconditionFailure("Invalid identifier") }
        return identifier
    }

    func testAGroupColorsTheFilesItsSearchMatchesAndTheFirstGroupWins() {
        let groupIndexes = courseGraph().colorGroupIndexes(for: ["path:Courses/VLSI", "courses"])
        XCTAssertEqual(groupIndexes, ["Courses/VLSI/Lecture 1.md": 0, "Courses/VLSI/Lab.md": 0, "Courses/VLSI/Layout.png": 0,
                                      "Courses/Signals/Sampling.md": 1],
                       "VLSI's files take the first group even though the second matches them too; capitals do not count.")
    }

    func testATagMatchesTheNotesThatCarryItOrATagNestedUnderIt() {
        let groupIndexes = courseGraph().colorGroupIndexes(for: ["tag:#course"])
        XCTAssertEqual(groupIndexes, ["Courses/VLSI/Lab.md": 0, "Inbox/Idea.md": 0])
    }

    func testTagsAndLinksWithoutAFileKeepTheirOwnColors() {
        let groupIndexes = courseGraph().colorGroupIndexes(for: ["vlsi"])
        XCTAssertNil(groupIndexes["#course/vlsi"], "A tag is not a file.")
        XCTAssertNil(groupIndexes["Courses VLSI plan"], "A link without a file is not a file.")
        XCTAssertEqual(groupIndexes["Courses/VLSI/Lab.md"], 0)
    }

    func testAGroupWithoutWordsColorsNothing() {
        XCTAssertEqual(courseGraph().colorGroupIndexes(for: ["", "  "]), [:])
        XCTAssertEqual(courseGraph().colorGroupIndexes(for: ["", "signals"]), ["Courses/Signals/Sampling.md": 1],
                       "A group without words takes no file from the groups after it.")
    }

    func testAGroupKeepsItsSearchAndACanonicalColor() {
        var group = GraphColorGroup(identifier: identifier(1), query: "tag:#vlsi", colorHex: "#E93147")
        XCTAssertEqual(group.id, identifier(1).uuidString)
        XCTAssertEqual(group.query, "tag:#vlsi")
        XCTAssertEqual(group.colorHex, "#e93147")
        group.colorHex = "0AF"
        XCTAssertEqual(group.colorHex, "#00aaff")
        group.colorHex = "not a color"
        XCTAssertNil(group.colorHex)
    }

    func testTheListKeepsFieldsAndElementsItDoesNotRead() throws {
        let stored = Data("""
        [{"id":"A","query":"tag:#vlsi","color":"#e93147","opacity":0.5},"a note from a newer build",{"query":"signals","color":"#08b94e"}]
        """.utf8)
        var identifierNumbers = (10...).makeIterator()
        var list = try XCTUnwrap(GraphColorGroupList(decoding: stored, makeIdentifier: { self.identifier(identifierNumbers.next() ?? 0) }))
        XCTAssertEqual(list.groups.map(\.query), ["tag:#vlsi", "signals"])
        XCTAssertEqual(list.groups.map(\.id), ["A", identifier(10).uuidString], "A group stored without an identifier is given one.")

        var changed = list.groups[0]
        changed.query = "tag:#course/vlsi"
        list.replace(changed)
        let written = try JSONDecoder().decode(JSONValue.self, from: list.encoded())
        guard case .array(let elements) = written, elements.count == 3, case .object(let first) = elements[0] else {
            return XCTFail("The list is written back as a list of three elements: \(written)")
        }
        XCTAssertEqual(first["query"], .string("tag:#course/vlsi"))
        XCTAssertEqual(first["opacity"], .number(0.5), "A field this build does not read is written back.")
        XCTAssertEqual(elements[1], .string("a note from a newer build"), "An element that is not a group stays where it was.")
    }

    func testAStoredValueThatIsNotAListIsNotReadAsGroups() {
        XCTAssertNil(GraphColorGroupList(decoding: Data("{\"groups\":[]}".utf8), makeIdentifier: { self.identifier(1) }))
        XCTAssertNil(GraphColorGroupList(decoding: Data("not JSON".utf8), makeIdentifier: { self.identifier(1) }))
    }

    func testGroupsAreAddedLastAndReplacedOrRemovedByTheirIdentifier() throws {
        var list = GraphColorGroupList()
        list.append(GraphColorGroup(identifier: identifier(1), query: "vlsi", colorHex: "#e93147"))
        list.append(GraphColorGroup(identifier: identifier(2), query: "signals", colorHex: "#08b94e"))
        var second = list.groups[1]
        second.query = "sampling"
        list.replace(second)
        XCTAssertEqual(list.groups.map(\.query), ["vlsi", "sampling"])
        list.removeGroup(identifiedBy: identifier(1).uuidString)
        XCTAssertEqual(list.groups.map(\.id), [identifier(2).uuidString])
        list.removeGroup(identifiedBy: "unknown")
        XCTAssertEqual(list.groups.count, 1)
        let reread = try XCTUnwrap(GraphColorGroupList(decoding: list.encoded(), makeIdentifier: { self.identifier(9) }))
        XCTAssertEqual(reread, list)
    }
}
