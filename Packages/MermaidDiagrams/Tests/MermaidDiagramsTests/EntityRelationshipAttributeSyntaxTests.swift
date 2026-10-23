import XCTest
@testable import MermaidDiagrams

/// An entity's `{ … }` on the inputs of Mermaid's parser specs (`erDiagram.spec.js` of Mermaid 12.1.0, as Pele ports
/// them) and of its documentation.
final class EntityRelationshipAttributeSyntaxTests: XCTestCase {
    private func attributes(_ block: String, of entity: String = "BOOK") throws -> [EntityRelationshipAttribute] {
        let read = try EntityRelationshipReading.diagram("erDiagram\n\(entity) \(block)")
        return try XCTUnwrap(read.entities.first { candidate in candidate.identifier == entity }).attributes
    }

    private func readError(_ body: String) -> MermaidDiagramReadError? {
        EntityRelationshipReading.readError("erDiagram\n" + body)
    }

    func testEachRowIsATypeAndAName() throws {
        let read = try attributes("{\nstring myBookTitle\nstring MYBOOKSUBTITLE_1\nstring author-ref[name](1)\n}")
        XCTAssertEqual(read, [EntityRelationshipAttribute(type: "string", name: "myBookTitle"), EntityRelationshipAttribute(type: "string", name: "MYBOOKSUBTITLE_1"),
                              EntityRelationshipAttribute(type: "string", name: "author-ref[name](1)")])
    }

    func testTypesAndNamesTakeAsterisksCommasBracketsAndAQuestionMark() throws {
        XCTAssertEqual(try attributes("{\nstring *title}").map(\.name), ["*title"])
        XCTAssertEqual(try attributes("{\nid *the_Primary_Key}").map(\.name), ["*the_Primary_Key"])
        XCTAssertEqual(try attributes("{\npublic.geometry(point,4326) location}").first,
                       EntityRelationshipAttribute(type: "public.geometry(point,4326)", name: "location"))
        XCTAssertEqual(try attributes("{\ncharacter(10) isbn FK\nvarchar(5) postal_code \"Five digits\"\n}").map(\.type), ["character(10)", "varchar(5)"])
        XCTAssertEqual(try attributes("{\nstring[] readers FK \"comment\"\nstring[] authors FK\n}").map(\.type), ["string[]", "string[]"])
        XCTAssertEqual(try attributes("{\nstring? alias\n}").first, EntityRelationshipAttribute(type: "string?", name: "alias"), "Mermaid 11.16")
    }

    func testBackticksHoldAnyCharacter() throws {
        XCTAssertEqual(try attributes("{\nstring `geo.accuracy`\n}", of: "HOTEL").first, EntityRelationshipAttribute(type: "string", name: "geo.accuracy"))
        XCTAssertEqual(try attributes("{\n`my.type` address\n}", of: "HOTEL").first, EntityRelationshipAttribute(type: "my.type", name: "address"))
        XCTAssertEqual(try attributes("{\nstring `geo.accuracy` PK \"the comment\"\n}", of: "HOTEL").first,
                       EntityRelationshipAttribute(type: "string", name: "geo.accuracy", keys: [.primary], comment: DiagramLabel("the comment")))
        XCTAssertEqual(try attributes("{ `my type` `my name` PK,FK }").first?.name, "my name")
    }

    func testKeysAndCommentsFollowTheName() throws {
        let read = try attributes("""
        {
        int customer_number PK, FK "comment1"
        datetime customer_status_start_datetime PK,UK, FK
        datetime customer_status_end_datetime PK , UK "comment3"
        string customer_firstname
        string customer_lastname "comment5"
        string? alias uk "optional display name"
        }
        """, of: "CUSTOMER")
        XCTAssertEqual(read.map(\.keys), [[.primary, .foreign], [.primary, .unique, .foreign], [.primary, .unique], [], [], [.unique]])
        XCTAssertEqual(read.map(\.comment), [DiagramLabel("comment1"), nil, DiagramLabel("comment3"), nil, DiagramLabel("comment5"),
                                             DiagramLabel("optional display name")])
    }

    func testANameThatStartsLikeAKeyIsAName() throws {
        let read = try attributes("{\nint fk_title FK \n\nstring pk_author PK\nstring uk_address UK\nfloat pk_price PK \"comment\"\n}")
        XCTAssertEqual(read.map(\.name), ["fk_title", "pk_author", "uk_address", "pk_price"])
    }

    func testGenericTypesAreReadWithAngleBrackets() throws {
        let read = try attributes("{\ntype~T~ type\noption~T~ readable \"comment\"\nstring id PK\nList~string~ tags FK, UK \"many\"\nMap~K,V~ index\n}")
        XCTAssertEqual(read.map(\.type), ["type<T>", "option<T>", "string", "List<string>", "Map<K,V>"])
        XCTAssertEqual(read.map(\.name), ["type", "readable", "id", "tags", "index"])
    }

    func testBlocksAddUpAndMayBeEmptyOrWrittenOnOneLine() throws {
        let read = try EntityRelationshipReading.diagram("erDiagram\nBOOK {\nstring title\n}\nBOOK {\nstring author\nfloat price\n}")
        XCTAssertEqual(read.entities.first?.attributes.map(\.name), ["title", "author", "price"])
        for empty in ["{}", "{ }", "        {}", "{\n  \n\n  \n}"] {
            XCTAssertEqual(try attributes(empty), [], empty)
        }
        XCTAssertEqual(try EntityRelationshipReading.diagram("erDiagram\nBOOK{string title}").entities.first?.attributes.count, 1)
        XCTAssertEqual(try attributes("{\n  \n\n  string title\n\n  \n}").count, 1)
    }

    func testACommentIsDrawnAsMarkdownOverItsLines() throws {
        let comment = try XCTUnwrap(try attributes("{\nstring id PK \"The **main** key<br>of #quot;book#quot;\"\n}").first?.comment)
        XCTAssertEqual(comment.lines, ["The main key", "of \"book\""])
    }

    func testCommentLinesInsideABlockAreSkipped() throws {
        XCTAssertEqual(try attributes("{\n  %% the title\n  string title\n}").map(\.name), ["title"])
    }

    func testABrokenBlockIsReportedWithWhatIsMissing() {
        XCTAssertEqual(readError("BOOK {\nstring title\nstring"), .invalidSyntax(line: 2, problem: .unclosedAttributeBlock(entity: "BOOK")))
        XCTAssertEqual(readError("BOOK {\nstring }"), .invalidSyntax(line: 3, problem: .expectedAttribute))
        XCTAssertEqual(readError("BOOK {\nstring title PK,\n}"), .invalidSyntax(line: 4, problem: .expectedAttribute))
        XCTAssertEqual(readError("BOOK {\nstring title \"never closed\n}"), .invalidSyntax(line: 3, problem: .unclosedQuotation))
        XCTAssertEqual(readError("BOOK {\nstring `unclosed\n}"), .invalidSyntax(line: 2, problem: .unclosedAttributeBlock(entity: "BOOK")))
        for leading in ["0", "-", "[", "]", "(", ")"] {
            XCTAssertEqual(readError("BOOK {\nstring \(leading)author\n}"), .invalidSyntax(line: 3, problem: .expectedAttribute), leading)
        }
    }
}
