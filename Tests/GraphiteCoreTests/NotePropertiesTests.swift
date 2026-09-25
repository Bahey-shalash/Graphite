import XCTest
@testable import GraphiteCore

final class NotePropertiesTests: XCTestCase {
    func testTypesAreInferredLikeObsidian() throws {
        let yaml = """
        title: Logic Design
        tags:
          - VLSI
          - logic-design
        pages: 54
        rating: 4.5
        done: false
        due: 2026-09-23
        lecture: 2026-09-23T14:30
        empty:
        quoted: "42"
        related:
          - "[[9_Static logic]]"
        nested:
          a: 1
        """
        let properties = try XCTUnwrap(NoteProperties.parse(yaml))
        let values = Dictionary(uniqueKeysWithValues: properties.map { property in (property.key, property.value) })
        XCTAssertEqual(properties.map(\.key), ["title", "tags", "pages", "rating", "done", "due", "lecture", "empty", "quoted", "related", "nested"], "Written order is kept.")
        XCTAssertEqual(values["title"], .text("Logic Design"))
        XCTAssertEqual(values["tags"], .list(["VLSI", "logic-design"]))
        XCTAssertEqual(values["pages"], .number(54))
        XCTAssertEqual(values["rating"], .number(4.5))
        XCTAssertEqual(values["done"], .checkbox(false))
        XCTAssertEqual(values["due"], .date("2026-09-23"))
        XCTAssertEqual(values["lecture"], .dateTime("2026-09-23T14:30"))
        XCTAssertEqual(values["empty"], .empty)
        XCTAssertEqual(values["quoted"], .text("42"))
        XCTAssertEqual(values["related"], .list(["[[9_Static logic]]"]))
        guard case .unsupported = values["nested"] else { return XCTFail("Nested objects stay verbatim.") }
    }

    func testDeclaredTypesWin() throws {
        let properties = try XCTUnwrap(NoteProperties.parse("code: 007\ntopic: one", declaredTypes: ["code": .text, "topic": .multitext]))
        guard properties.count == 2 else { return XCTFail("Expected 2 properties, found \(properties)") }
        XCTAssertEqual(properties[0].value, .text("007"))
        XCTAssertEqual(properties[1].value, .list(["one"]))
    }

    func testInvalidYAMLIsReportedNotGuessed() {
        XCTAssertNil(NoteProperties.parse("- just\n- a list"))
        XCTAssertNil(NoteProperties.parse("key: [unclosed"))
        XCTAssertEqual(NoteProperties.parse("  \n"), [])
    }

    func testSerializationRoundTripsAndQuotesOnlyWhenNeeded() throws {
        let properties = [
            NoteProperty(key: "title", value: .text("Logic Design")),
            NoteProperty(key: "note", value: .text("a: b")),
            NoteProperty(key: "count", value: .text("12")),
            NoteProperty(key: "tags", value: .list(["VLSI", "#hash"])),
            NoteProperty(key: "none", value: .list([])),
            NoteProperty(key: "pages", value: .number(54)),
            NoteProperty(key: "done", value: .checkbox(true)),
            NoteProperty(key: "due", value: .date("2026-09-23")),
            NoteProperty(key: "blank", value: .empty),
        ]
        let yaml = NoteProperties.serialize(properties)
        XCTAssertEqual(yaml, """
        title: Logic Design
        note: "a: b"
        count: "12"
        tags:
          - VLSI
          - "#hash"
        none: []
        pages: 54
        done: true
        due: 2026-09-23
        blank:

        """)
        XCTAssertEqual(NoteProperties.parse(yaml)?.map(\.value), properties.map(\.value), "Every value, the empty list included, reads back unchanged.")
    }

    func testReplacingFrontmatterKeepsTheBodyExactly() {
        let body = "# Title\r\n\r\nText with  two spaces\r\n"
        let source = "---\r\nold: 1\r\n---\r\n" + body
        let updated = NoteProperties.replacingFrontmatter(in: source, with: [NoteProperty(key: "new", value: .text("value"))])
        XCTAssertEqual(updated, "---\r\nnew: value\r\n---\r\n" + body)
        XCTAssertEqual(NoteProperties.replacingFrontmatter(in: source, with: []), body)
        XCTAssertEqual(NoteProperties.replacingFrontmatter(in: "Plain\n", with: [NoteProperty(key: "a", value: .checkbox(false))]), "---\na: false\n---\nPlain\n")
    }
}
