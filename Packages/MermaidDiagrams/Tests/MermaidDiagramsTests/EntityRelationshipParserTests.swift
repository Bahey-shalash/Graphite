import XCTest
@testable import MermaidDiagrams

/// The entity relationship parser on the inputs of Mermaid's parser specs (`erDiagram.spec.js` of Mermaid 12.1.0, as
/// Pele ports them in `tests/compat/er`) and of its documentation.
final class EntityRelationshipParserTests: XCTestCase {
    private func diagram(_ body: String) throws -> EntityRelationshipDiagram {
        try EntityRelationshipReading.diagram("erDiagram\n" + body)
    }

    private func readError(_ body: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        EntityRelationshipReading.readError("erDiagram\n" + body, limits: limits)
    }

    private func onlyRelationship(_ body: String) throws -> EntityRelationship {
        let relationships = try diagram(body).relationships
        XCTAssertEqual(relationships.count, 1, body)
        return try XCTUnwrap(relationships.first)
    }

    // MARK: Entities

    func testEntitiesMayStandAloneOnTheirLines() throws {
        let read = try diagram("ISLAND\nMAINLAND")
        XCTAssertEqual(read.entities.map(\.identifier), ["ISLAND", "MAINLAND"])
        XCTAssertEqual(read.entities[0].label, DiagramLabel("ISLAND"))
        XCTAssertTrue(read.relationships.isEmpty)
    }

    func testStatementsNeedNoSeparatorAndMayFollowTheKeyword() throws {
        let read = try EntityRelationshipReading.diagram("erDiagram A B C\nD { a b c d } E\n")
        XCTAssertEqual(read.entities.map(\.identifier), ["A", "B", "C", "D", "E"])
        XCTAssertEqual(read.entities[3].attributes.map(\.name), ["b", "d"])
    }

    func testBareNamesHoldHyphensUnderscoresPeriodsAsterisksAndCharactersBeyondASCII() throws {
        let names = ["DUCK-BILLED_PLATYPUS", "_foo", "A.B", "C*D", "Étape", "__proto__", "constructor", "prototype"]
        XCTAssertEqual(try diagram(names.joined(separator: "\n")).entities.map(\.identifier), names)
    }

    func testQuotedNamesMayHoldAnyCharacterButPercentBackslashAndLineBreaks() throws {
        // The characters of Mermaid's spec, entered with the Mac keyboard utility.
        let characters = ("~ ` ! @ # $ ^ & * ( ) - = + [ ] { } | / ; : ' . ? ¡ ⁄ ™ € £ ‹ ¢ › ∞ ﬁ § ‡ • ° ª · º ‚ ≠ ± œ Œ ∑ „ ® † ˇ ¥ Á ¨ ˆ ˆ Ø π ∏ "
            + "“ « » å Å ß Í ∂ Î ƒ Ï © ˙ Ó ∆ Ô ˚  ¬ Ò … Ú æ Æ Ω ¸ ≈ π ˛ ç Ç √ ◊ ∫ ı ˜ µ Â ≤ ¯ ≥ ˘ ÷ ¿").split(separator: " ").map(String.init)
        for character in characters {
            for name in ["Blo\(character)rf", "Blo\(character)\(character)rf", "Blorf\(character)"] {
                XCTAssertEqual(try diagram("\"\(name)\"").entities.first?.identifier, name)
            }
        }
        XCTAssertEqual(try diagram("\"a\(characters.joined())\"").entities.count, 1)
        for refused in ["\"\"", "\"Blo%rf\"", "\"Blo\\rf\"", "\"Blo\rrf\"", "\"Blo\u{8}rf\"", "\"Blo\u{B}rf\"", "\"Blo\nrf\""] {
            XCTAssertNotNil(readError(refused), refused)
        }
    }

    func testAQuotedNameIsDrawnAsMarkdown() throws {
        XCTAssertEqual(try diagram("\"This **is** _Markdown_\"").entities.first?.label, DiagramLabel("This is Markdown"))
        XCTAssertEqual(try diagram("\"This ❤ Unicode\"").entities.first?.label, DiagramLabel("This ❤ Unicode"))
    }

    func testAnAliasIsDrawnInsteadOfTheNameAndTheFirstAliasIsKept() throws {
        let read = try diagram("p[Person]\na[\"Customer Account\"]\np[Other]")
        XCTAssertEqual(read.entities.map(\.identifier), ["p", "a"])
        XCTAssertEqual(read.entities.map(\.label), [DiagramLabel("Person"), DiagramLabel("Customer Account")])
        XCTAssertEqual(read.entities.map(\.hasAlias), [true, true])
    }

    func testAnAliasGivenAfterARelationshipNamedTheEntityStillApplies() throws {
        for body in ["foo ||--o| bar : rel\nbuzz foo[\"batman\"]", "buzz foo[\"batman\"]\nfoo ||--o| bar : rel"] {
            let read = try diagram(body)
            let foo = try XCTUnwrap(read.entities.first { entity in entity.identifier == "foo" })
            let bar = try XCTUnwrap(read.entities.first { entity in entity.identifier == "bar" })
            XCTAssertEqual(foo.label, DiagramLabel("batman"), body)
            XCTAssertFalse(bar.hasAlias, body)
        }
    }

    func testNumbersAndTheLetterUNameEntities() throws {
        for name in ["1", "u", "2.5", "1.5", "0.1", "99.99"] {
            let read = try diagram("CUSTOMER }|..|{ DELIVERY-ADDRESS : has\n\(name)")
            XCTAssertEqual(read.entities.map(\.identifier), ["CUSTOMER", "DELIVERY-ADDRESS", name])
        }
        XCTAssertEqual(try diagram("u {\nstring name\nint id\n}\n1 {\nstring name\n}\n2.5 {\nstring value\n}").entities.map(\.attributes.count), [2, 1, 1])
        for body in ["CUSTOMER ||--|| u : has", "u ||--|| v : connects", "1 ||--|| 2 : connects", "2.5 ||--|| 5.5 : connects"] {
            XCTAssertEqual(try diagram(body).relationships.count, 1, body)
        }
    }

    func testAComplexDiagramWithSpecialNamesIsRead() throws {
        let read = try diagram("""
            CUSTOMER ||--o{ 1 : places
            1 ||--|{ u : contains
            u {
              string name
              int quantity
            }
            "2.5" ||--|| ORDER : processes
            ORDER {
              int id
              date created
            }
        """)
        XCTAssertEqual(read.entities.map(\.identifier), ["CUSTOMER", "1", "u", "2.5", "ORDER"])
        XCTAssertEqual(read.relationships.count, 3)
    }

    // MARK: Relationships

    func testARelationshipJoinsItsEntitiesWithACardinalityAtEachEnd() throws {
        let read = try diagram("CAR ||--o{ DRIVER : \"insured for\"")
        XCTAssertEqual(read.entities.map(\.identifier), ["CAR", "DRIVER"])
        XCTAssertEqual(read.relationships, [EntityRelationship(firstEntityIndex: 0, secondEntityIndex: 1, firstEntityCardinality: .exactlyOne,
                                                               secondEntityCardinality: .zeroOrMore, identification: .identifying,
                                                               label: DiagramLabel("insured for"))])
    }

    func testEveryCardinalitySymbolReadsOnEitherSide() throws {
        let symbols: [(left: String, right: String, cardinality: EntityRelationshipCardinality)] = [
            ("|o", "o|", .zeroOrOne), ("||", "||", .exactlyOne), ("}o", "o{", .zeroOrMore), ("}|", "|{", .oneOrMore),
        ]
        for first in symbols {
            for second in symbols {
                for line in ["--", ".."] {
                    let relationship = try onlyRelationship("A \(first.left)\(line)\(second.right) B : has")
                    XCTAssertEqual(relationship.firstEntityCardinality, first.cardinality, "\(first.left)\(line)\(second.right)")
                    XCTAssertEqual(relationship.secondEntityCardinality, second.cardinality, "\(first.left)\(line)\(second.right)")
                }
            }
        }
        XCTAssertEqual(try onlyRelationship("PERSON o{--|| HOUSE : has").firstEntityCardinality, .zeroOrMore)
        XCTAssertEqual(try onlyRelationship("PROJECT u--o{ TEAM_MEMBER : \"parent\"").firstEntityCardinality, .parent)
    }

    func testCardinalitiesAndLinesMayBeWrittenInWords() throws {
        let cases: [(String, EntityRelationshipCardinality, EntityRelationshipIdentification, EntityRelationshipCardinality)] = [
            ("A one or zero to many B", .zeroOrOne, .identifying, .zeroOrMore),
            ("A one or many optionally to zero or one B", .oneOrMore, .nonIdentifying, .zeroOrOne),
            ("A zero or more to zero or many B", .zeroOrMore, .identifying, .zeroOrMore),
            ("A many(0) to many(1) B", .zeroOrMore, .identifying, .oneOrMore),
            ("A many optionally to one B", .zeroOrMore, .nonIdentifying, .exactlyOne),
            ("A only one optionally to 1+ B", .exactlyOne, .nonIdentifying, .oneOrMore),
            ("A 0+ optionally to 1 B", .zeroOrMore, .nonIdentifying, .exactlyOne),
            ("CAR 1 to zero or more NAMED-DRIVER", .exactlyOne, .identifying, .zeroOrMore),
            ("HOUSE ONE TO ONE ROOM", .exactlyOne, .identifying, .exactlyOne),
        ]
        for (statement, first, identification, second) in cases {
            let relationship = try onlyRelationship(statement + " : has")
            XCTAssertEqual([relationship.firstEntityCardinality, relationship.secondEntityCardinality], [first, second], statement)
            XCTAssertEqual(relationship.identification, identification, statement)
        }
    }

    func testOneBeforeALineIsACardinalityInEveryLine() throws {
        for (line, identification) in [("--", EntityRelationshipIdentification.identifying), ("..", .nonIdentifying), (".-", .nonIdentifying),
                                       ("-.", .nonIdentifying)] {
            let relationship = try onlyRelationship("CUSTOMER 1\(line)one or more DELIVERY-ADDRESS : has")
            XCTAssertEqual(relationship.firstEntityCardinality, .exactlyOne, line)
            XCTAssertEqual(relationship.secondEntityCardinality, .oneOrMore, line)
            XCTAssertEqual(relationship.identification, identification, line)
        }
    }

    func testANumberAfterTheCardinalityOneNamesTheSecondEntity() throws {
        for (body, second) in [("a many to 1 1: label", "1"), ("a many to 1 12: label", "12")] {
            let read = try diagram(body)
            XCTAssertEqual(read.entities.map(\.identifier), ["a", second], body)
            XCTAssertEqual(read.relationships.first?.secondEntityCardinality, .exactlyOne, body)
            XCTAssertEqual(read.relationships.first?.firstEntityCardinality, .zeroOrMore, body)
        }
    }

    func testLabelsAreAWordOrQuotedTextAndMayBeEmpty() throws {
        XCTAssertEqual(try onlyRelationship("CUSTOMER ||--|{ ORDER : places").label, DiagramLabel("places"))
        XCTAssertEqual(try onlyRelationship("CUSTOMER ||--|{ ORDER : \"places\"").label, DiagramLabel("places"))
        XCTAssertTrue(try onlyRelationship("CUSTOMER ||--|{ ORDER : \"\"").label.isEmpty)
        XCTAssertEqual(try onlyRelationship("TEACHER }o--o{ STUDENT : \"is teacher of\"").label, DiagramLabel("is teacher of"))
        XCTAssertEqual(try onlyRelationship("A ||--|| B : \"50% off\"").label, DiagramLabel("50% off"))
    }

    func testAnEntityMayRelateToItselfAndTwoEntitiesMoreThanOnce() throws {
        let recursive = try diagram("NODE ||--o{ NODE : \"leads to\"")
        XCTAssertEqual(recursive.entities.count, 1)
        XCTAssertEqual(recursive.relationships.first?.secondEntityIndex, 0)
        let twice = try diagram("CAR ||--o{ PERSON : \"insured for\"\nCAR }o--|| PERSON : \"owned by\"\nDRIVER ||--|| LICENSE : has")
        XCTAssertEqual(twice.entities.count, 4)
        XCTAssertEqual(twice.relationships.count, 3)
    }

    // MARK: Other statements

    func testTheDirectionIsTopToBottomUnlessAStatementNamesOne() throws {
        XCTAssertEqual(try diagram("A").direction, .topToBottom)
        let directions: [(String, FlowchartDirection)] = [("TB", .topToBottom), ("BT", .bottomToTop), ("LR", .leftToRight), ("rl", .rightToLeft)]
        for (keyword, direction) in directions {
            XCTAssertEqual(try diagram("direction \(keyword)\nA").direction, direction, keyword)
        }
        XCTAssertEqual(try diagram("DIRECTION LR anything else\nA").entities.map(\.identifier), ["A"])
        XCTAssertEqual(try diagram("direction TD").entities.map(\.identifier), ["direction", "TD"], "Not a direction: two entities, as in Mermaid")
    }

    func testAccessibilityTitleAndDescriptionAreKept() throws {
        let single = try diagram("  accTitle: graph title\n  accDescr: this graph is about stuff\n  TEACHER }o--o{ STUDENT : \"is teacher of\"")
        XCTAssertEqual(single.accessibilityTitle, "graph title")
        XCTAssertEqual(single.accessibilityDescription, "this graph is about stuff")
        let multiline = try diagram("accTitle: graph title\naccDescr { this graph is\n    about\n    stuff\n    }\n\nA")
        XCTAssertEqual(multiline.accessibilityDescription, "this graph is\nabout\nstuff")
        XCTAssertEqual(multiline.entities.map(\.identifier), ["A"])
    }

    func testCommentsAreSkipped() throws {
        let read = try diagram("%% the customers\nCUSTOMER ||--o{ ORDER : places %% and their orders\n  %% end")
        XCTAssertEqual(read.entities.map(\.identifier), ["CUSTOMER", "ORDER"])
    }

    func testStylesAndClassesAreCountedAndNotApplied() throws {
        let read = try diagram("""
        CUSTOMER:::myClass ||--o{ PERSON:::myClass : allows
        c[CUSTOMER]:::first,second {
          string name
        }
        HOUSE:::someclass
        style CUSTOMER color:red,stroke:blue,fill:#f9f
        classDef firstClass,secondClass fill:#f9f, stroke: red, color: pink
        class CUSTOMER, PERSON firstClass, secondClass
        classDef default fill:#f9f;
        """)
        XCTAssertEqual(read.entities.map(\.identifier), ["CUSTOMER", "PERSON", "c", "HOUSE"])
        XCTAssertEqual(read.entities[2].attributes.count, 1)
        XCTAssertEqual(read.unappliedStatementCount, 8)
    }

    func testSubgraphsAreCountedAndADirectionInsideOneLeavesTheDiagrams() throws {
        let read = try diagram("""
        direction LR
        subgraph TOP
            direction TB
            subgraph B1 [title 1]
                I1 ||--|| F1 : links
            end
            subgraph "Customer Domain"
                CUSTOMER
            end
        end
        A ||--|| TOP : links
        """)
        XCTAssertEqual(read.subgraphCount, 3)
        XCTAssertEqual(read.direction, .leftToRight)
        XCTAssertEqual(read.relationships.count, 2)
    }

    // MARK: Errors and limits

    func testEachBrokenStatementIsReportedOnItsLineWithWhatIsMissing() {
        let cases: [(String, Int, MermaidSyntaxProblem)] = [
            ("A xxx B : has", 2, .unexpectedText(": has")),
            ("A\nA || B : has", 3, .expectedRelationshipLine),
            ("A ||-- B : has", 2, .expectedCardinality),
            ("A ||--o{ : has", 2, .expectedNode),
            ("A ||--o{ B\nC", 2, .expectedRelationshipLabel),
            ("A ||--o{ B : 1", 2, .expectedRelationshipLabel),
            ("A[Person", 2, .unclosedShape(closingText: "]")),
            ("A[Two words]", 2, .unexpectedText("words]")),
            ("A ||--o{ \"B : has", 2, .unclosedQuotation),
            ("accDescr { never closed\nA", 2, .unclosedAccessibilityDescription),
            ("A\nend", 3, .endWithoutSubgraph),
            ("subgraph group\nA", 3, .unclosedSubgraph(identifier: "group")),
            ("subgraph one\nA", 2, .expectedNode),
            ("class\nA", 2, .expectedNode),
            ("erDiagram", 2, .unexpectedText("erDiagram")),
            ("CUSTOMER ; ORDER", 2, .unexpectedText("; ORDER")),
        ]
        for (body, line, problem) in cases {
            XCTAssertEqual(readError(body), .invalidSyntax(line: line, problem: problem), body)
        }
    }

    func testEntitiesAndRelationshipsPastTheLimitsAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertEqual(readError("A\nB\nC", limits: limits), .tooManyNodes(limit: 2))
        XCTAssertNil(readError("A ||--|| B : x\nB ||--|| A : y", limits: limits))
        limits.maximumEdgeCount = 1
        XCTAssertEqual(readError("A ||--|| B : x\nB ||--|| A : y", limits: limits), .tooManyEdges(limit: 1))
    }
}
