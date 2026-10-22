import XCTest
@testable import MermaidDiagrams

/// The class diagram's statements, on the examples of Mermaid 12.1.0's class diagram documentation and the inputs of
/// Mermaid's parser specs as Pele ports them (`tests/compat/class`).
final class ClassDiagramParserTests: XCTestCase {
    private func diagram(_ body: String) throws -> ClassDiagram {
        try ClassDiagramReading.classDiagram("classDiagram\n" + body)
    }

    private func readError(_ body: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        ClassDiagramReading.readError("classDiagram\n" + body, limits: limits)
    }

    private func onlyClass(_ body: String) throws -> ClassDiagramClass {
        let classes = try diagram(body).classes
        XCTAssertEqual(classes.count, 1)
        return try XCTUnwrap(classes.first)
    }

    private func onlyRelation(_ body: String) throws -> ClassDiagramRelation {
        let relations = try diagram(body).relations
        XCTAssertEqual(relations.count, 1)
        return try XCTUnwrap(relations.first)
    }

    // MARK: Classes

    func testClassStatementsAndRelationsDeclareClassesInTheOrderTheyAreNamed() throws {
        let classes = try diagram("class Animal\nVehicle <|-- Car\nclass Animal").classes
        XCTAssertEqual(classes.map(\.identifier), ["Animal", "Vehicle", "Car"])
        XCTAssertEqual(classes[0].label, DiagramLabel("Animal"))
    }

    func testANameAloneDeclaresNothingAsInMermaid() throws {
        XCTAssertEqual(try diagram("Animal\n").classes, [])
    }

    func testALabelInBracketsReplacesTheNameItShows() throws {
        let classes = try diagram("""
        class C1["OneWord"]
        class C2["With, Comma"]
        class C3["With (Brackets)"]
        class C4["With [Brackets]"]
        class C5["With {Brackets}"]
        class C9["With - dash"]
        class C10["With _ underscore"]
        class C11["With ' single quote"]
        class C12["With ~!@#$%^&*()_+=-/?"]
        class C13["With Città foreign language"]
        class C14 ["Spaced"]
        """).classes
        XCTAssertEqual(classes.map(\.label.spokenText), ["OneWord", "With, Comma", "With (Brackets)", "With [Brackets]", "With {Brackets}", "With - dash",
                                                         "With _ underscore", "With ' single quote", "With ~!@#$%^&*()_+=-/?", "With Città foreign language",
                                                         "Spaced"])
        XCTAssertEqual(classes[0].identifier, "C1")
        XCTAssertEqual(try onlyClass("class Animal[\"Animal with a label\"]\nclass Animal[\"Renamed\"]").label, DiagramLabel("Renamed"))
    }

    func testNamesMayHoldDashesDotsUnderscoresBackticksAndCharactersBeyondASCII() throws {
        let classes = try diagram("""
        class Ca-r
        class `A_Car`
        class `Animal Class!`
        class Città
        Company.Project.Module --> `IPC::Sender`
        """).classes
        XCTAssertEqual(classes.map(\.identifier), ["Ca-r", "A_Car", "Animal Class!", "Città", "Company.Project.Module", "IPC::Sender"])
        XCTAssertEqual(try diagram("A--B\nC..D").classes.map(\.identifier), ["A", "B", "C", "D"])
    }

    func testAGenericTypeIsKeptFromTheFirstNamingAndShownInAngleBrackets() throws {
        let classes = try diagram("class Square~Shape~\nClass01~T~ <|-- Class02\nclass Pair~K, V~\nPlain --> Square~Other~").classes
        XCTAssertEqual(classes.map(\.genericType), ["Shape", "T", nil, "K, V", nil])
        XCTAssertEqual(classes[0].displayedName, DiagramLabel("Square<Shape>"))
        XCTAssertEqual(classes[3].displayedName, DiagramLabel("Pair<K, V>"))
        XCTAssertEqual(classes[2].displayedName, DiagramLabel("Class02"))
        XCTAssertEqual(try onlyClass("class `Car`~T~").displayedName, DiagramLabel("Car<T>"))
    }

    func testMembersInBracesAreSortedIntoAttributesAndMethodsInTheirOrder() throws {
        let actual = try onlyClass("class Class1 {\nint testMember\ntest()\nstring fooMember\nfoo()\n}")
        XCTAssertEqual(actual.attributes.map(\.text), ["int testMember", "string fooMember"])
        XCTAssertEqual(actual.methods.map(\.text), ["test()", "foo()"])
        let account = try onlyClass("class BankAccount{\n    +String owner\n    +BigDecimal balance\n    +deposit(amount) bool\n    +withdrawal(amount) int\n}")
        XCTAssertEqual(account.attributes.map(\.text), ["+String owner", "+BigDecimal balance"])
        XCTAssertEqual(account.methods.map(\.text), ["+deposit(amount) : bool", "+withdrawal(amount) : int"])
    }

    func testMembersAfterAColonJoinTheirClassAndDeclareIt() throws {
        let account = try onlyClass("""
        BankAccount : +String owner
        BankAccount: +deposit(amount)
        BankAccount :  -List~string~ messages
        """)
        XCTAssertEqual(account.attributes.map(\.text), ["+String owner", "-List<string> messages"])
        XCTAssertEqual(account.methods.map(\.text), ["+deposit(amount)"])
        let car = try onlyClass("class Car{\n+int wheels\n}\nCar : +ArrayList size()\n")
        XCTAssertEqual(car.attributes.map(\.text), ["+int wheels"])
        XCTAssertEqual(car.methods.map(\.text), ["+ArrayList size()"])
    }

    func testAnEmptyBodySeparatorsAndAOneLineBodyAreRead() throws {
        let empty = try onlyClass("class EmptyClass {}")
        XCTAssertEqual(empty.attributes, [])
        XCTAssertEqual(empty.methods, [])
        XCTAssertEqual(try onlyClass("class Shape <<interface>> {\n}").annotations, ["interface"])
        let grouped = try onlyClass("class Foo1 {\n  You can use\n..\nas you want\n==\n__\n--\nEnd of class\n}")
        XCTAssertEqual(grouped.attributes.map(\.text), ["You can use", "..", "as you want", "==", "__", "--", "End of class"])
        XCTAssertEqual(try onlyClass("class A { +x }").attributes.map(\.text), ["+x"])
    }

    func testAnnotationsAreReadInEveryForm() throws {
        XCTAssertEqual(try onlyClass("class Class1\n<<interface>> Class1").annotations, ["interface"])
        XCTAssertEqual(try onlyClass("class Class1 {\n<<interface>>\nint : test\ntest()\n}").annotations, ["interface"])
        XCTAssertEqual(try onlyClass("class Shape <<interface>>").annotations, ["interface"])
        let inline = try onlyClass("class Shape <<interface>> {\n    noOfVertices\n    draw()\n}")
        XCTAssertEqual(inline.annotations, ["interface"])
        XCTAssertEqual(inline.attributes.map(\.text), ["noOfVertices"])
        XCTAssertEqual(inline.methods.map(\.text), ["draw()"])
        XCTAssertEqual(try onlyClass("Color : <<enumeration>>").annotations, ["enumeration"])
        let early = try onlyClass("<<interface>> Shape\nclass Shape {\n  draw()\n}")
        XCTAssertEqual(early.annotations, ["interface"])
        XCTAssertEqual(early.methods.count, 1)
        XCTAssertEqual(try onlyClass("class Shape{\n    <<abstract class>>\n}").annotations, ["abstract class"])
    }

    func testCommentsAreSkippedOutsideAndInsideBraces() throws {
        let commented = try onlyClass("""

        %% Comment Class1 <|-- Class02
        class Class1 {
        %% Comment Class1 <|-- Class02 }
        int : test
        test()

        }
        %% Comment
        """)
        XCTAssertEqual(commented.attributes.map(\.text), ["int : test"])
        XCTAssertEqual(commented.methods.map(\.text), ["test()"])
        XCTAssertEqual(try diagram("A --> B %% a comment after a relation").relations.count, 1)
    }

    func testStylesLinksAndCallbacksAreCountedAndNotApplied() throws {
        let styled = try diagram("""
        class Animal:::someclass {
            -int sizeInFeet
        }
        classDef someclass fill:#f96
        style Animal fill:#f9f,stroke:#333,stroke-width:4px
        cssClass "Animal" pink
        link Animal "https://www.github.com" "This is a tooltip for a link"
        click Animal href "https://www.github.com" "This is a tooltip for a link"
        callback Animal "callbackFunction" "This is a tooltip for a callback"
        click Animal call callbackFunction() "This is a tooltip for a callback"
        """)
        XCTAssertEqual(styled.unappliedStatementCount, 8)
        XCTAssertEqual(styled.classes.first?.attributes.map(\.text), ["-int sizeInFeet"])
    }

    // MARK: Relations

    func testEachOperatorGivesItsMarksAndLine() throws {
        let cases: [(String, ClassDiagramRelationEnd, ClassDiagramRelationEnd, ClassDiagramLineStyle)] = [
            ("<|--", .inheritance, .none, .solid), ("*--", .composition, .none, .solid), ("o--", .aggregation, .none, .solid),
            ("<--", .arrow, .none, .solid), ("--", .none, .none, .solid), ("<..", .arrow, .none, .dashed), ("<|..", .inheritance, .none, .dashed),
            ("..", .none, .none, .dashed), ("--|>", .none, .inheritance, .solid), ("--*", .none, .composition, .solid),
            ("--o", .none, .aggregation, .solid), ("-->", .none, .arrow, .solid), ("..>", .none, .arrow, .dashed), ("..|>", .none, .inheritance, .dashed),
            ("<|--|>", .inheritance, .inheritance, .solid), ("*--*", .composition, .composition, .solid), ("<-->", .arrow, .arrow, .solid),
            ("*--o", .composition, .aggregation, .solid), ("o..", .aggregation, .none, .dashed), ("<--*", .arrow, .composition, .solid),
        ]
        for (written, sourceEnd, targetEnd, line) in cases {
            let relation = try onlyRelation("classA \(written) classB")
            XCTAssertEqual(relation.sourceEnd, sourceEnd, written)
            XCTAssertEqual(relation.targetEnd, targetEnd, written)
            XCTAssertEqual(relation.line, line, written)
            XCTAssertEqual(relation.source, .classIndex(0), written)
            XCTAssertEqual(relation.target, .classIndex(1), written)
        }
        XCTAssertEqual(try onlyRelation("A<|--B").sourceEnd, .inheritance)
        XCTAssertEqual(try onlyRelation("A <| -- > B").targetEnd, .arrow)
    }

    func testCardinalitiesAndLabelsAreRead() throws {
        let relations = try diagram("""
        Customer "1" --> "*" Ticket
        Student "1" --> "1..*" Course : enrolls
        Galaxy --> "many" Star : Contains
        Class1 "1" *-- "many" Class02 : contains
        Order --> Payment : settled by
        A " " -- B :
        """).relations
        XCTAssertEqual(relations.map(\.sourceCardinality), ["1", "1", nil, "1", nil, nil])
        XCTAssertEqual(relations.map(\.targetCardinality), ["*", "1..*", "many", "many", nil, nil])
        XCTAssertEqual(relations.map { relation in relation.label?.spokenText }, [nil, "enrolls", "Contains", "contains", "settled by", nil])
    }

    func testLabelsMayHoldArrowsAndParentheses() throws {
        let relations = try diagram("Driver -- Car : drives >\nCar *-- Wheel : have 4 >\nCar -- Person : < owns\nclassI -- classJ : Link(Solid)").relations
        XCTAssertEqual(relations.map { relation in relation.label?.spokenText }, ["drives >", "have 4 >", "< owns", "Link(Solid)"])
    }

    func testAnAggregationMarkNeedsNoIdentifierCharacterAfterIt() throws {
        let toOrder = try diagram("Customer -- order")
        XCTAssertEqual(toOrder.classes.map(\.identifier), ["Customer", "order"])
        XCTAssertEqual(toOrder.relations.first?.targetEnd, ClassDiagramRelationEnd.none)
        XCTAssertEqual(try onlyRelation("Class05 o-- Class06").sourceEnd, .aggregation)
        XCTAssertEqual(try onlyRelation("Class05 --o Class06").targetEnd, .aggregation)
    }

    func testALollipopEndFacingNoMarkNamesAnInterfaceOfItsOwn() throws {
        let lollipops = try diagram("""
          class Class01 {
            int amount
            draw()
          }
          Class01 --() bar
          Class02 --() bar
          foo ()-- Class01
          A ()--() B
        """)
        XCTAssertEqual(lollipops.classes.map(\.identifier), ["Class01", "Class02", "A", "B"])
        XCTAssertEqual(lollipops.relations.map(\.source), [.classIndex(0), .classIndex(1), .interface(DiagramLabel("foo")), .classIndex(2)])
        XCTAssertEqual(lollipops.relations.map(\.target), [.interface(DiagramLabel("bar")), .interface(DiagramLabel("bar")), .classIndex(0), .classIndex(3)])
        XCTAssertEqual(lollipops.relations[3].sourceEnd, .lollipop)
        XCTAssertEqual(lollipops.relations[3].targetEnd, .lollipop)
    }

    // MARK: Notes, namespaces, direction, accessibility

    func testNotesStandAloneOrJoinTheClassTheyName() throws {
        let noted = try diagram("""
            note "From Duck till Zebra"
            Animal <|-- Duck
            note for Duck "can fly<br>can swim<br>can dive"
            note for Later "about a class declared after it"
            note for Missing "about no class"
            class Later
        """)
        XCTAssertEqual(noted.notes.map(\.classIndex), [nil, 1, 2, nil])
        XCTAssertEqual(noted.notes[1].text.lines, ["can fly", "can swim", "can dive"])
        XCTAssertEqual(noted.notes[0].text, DiagramLabel("From Duck till Zebra"))
        XCTAssertEqual(noted.classes.map(\.identifier), ["Animal", "Duck", "Later"])
    }

    func testANotesTextMayHoldTheDiagramsKeywordsAndMarks() throws {
        for keyword in ["direction", "classDiagram", "namespace", "{}", "}", "()", "[]", "class", "cssClass", "link", "click", "note for", "<<", ">>",
                        "~Generic~", "<|", "|>", "--", "..", "-->", ": label", ":::", "function(arg1, arg2)"] {
            let noted = try diagram("note \"This is a keyword: \(keyword). It truly is.\"\nclass Something\nnote for Something \"\(keyword)\"")
            XCTAssertEqual(noted.notes.map(\.text.spokenText), ["This is a keyword: \(keyword). It truly is.", keyword], keyword)
        }
        XCTAssertEqual(try diagram("note \"About **it**\"").notes.first?.text, DiagramLabel("About it"), "A note's text is Markdown, as in Pele")
    }

    func testNamespacesAreReadWithTheClassesDeclaredInsideThem() throws {
        let grouped = try diagram("""
        namespace Namespace1 { class Class1 }
        namespace Platform["The platform"] {
            namespace Auth {
                class UserService {
                    +login()
                }
            }
            class Gateway
            note "inside"
        }
        namespace Company.Engineering {
            class TechLead
        }
        Gateway --> UserService : delegates
        """)
        XCTAssertEqual(grouped.namespaces.map(\.identifier), ["Namespace1", "Platform", "Platform.Auth", "Company.Engineering"])
        XCTAssertEqual(grouped.namespaces.map(\.title.spokenText), ["Namespace1", "The platform", "Auth", "Company.Engineering"])
        XCTAssertEqual(grouped.namespaces.map(\.classIndices), [[0], [2], [1], [3]])
        XCTAssertEqual(grouped.classes[1].methods.map(\.text), ["+login()"])
        XCTAssertEqual(grouped.notes.count, 1)
        XCTAssertEqual(grouped.relations.count, 1)
    }

    func testTheDirectionStatementSetsTheDirectionAndAnUnknownOneIsLeft() throws {
        XCTAssertEqual(try diagram("class A").direction, .topToBottom)
        XCTAssertEqual(try diagram("direction RL\nclass A").direction, .rightToLeft)
        XCTAssertEqual(try diagram("  direction LR").direction, .leftToRight)
        XCTAssertEqual(try diagram("direction BT").direction, .bottomToTop)
        XCTAssertEqual(try diagram("direction LR\ndirection TB").direction, .topToBottom)
        XCTAssertEqual(try diagram("direction LR\ndirection TD").direction, .leftToRight)
    }

    func testAccessibilityTitleAndDescriptionAreRead() throws {
        let described = try diagram("accTitle: My Title\naccDescr: My Description")
        XCTAssertEqual(described.accessibilityTitle, "My Title")
        XCTAssertEqual(described.accessibilityDescription, "My Description")
        XCTAssertEqual(try diagram("accDescr {\n  This is my multi\n  line description\n}").accessibilityDescription, "This is my multi line description")
    }

    // MARK: Errors and limits

    func testEachErrorIsTypedWithItsLine() {
        let cases: [(String, MermaidDiagramReadError)] = [
            ("class", .invalidSyntax(line: 2, problem: .expectedName)),
            ("class A[\"never closed", .invalidSyntax(line: 2, problem: .unclosedQuotation)),
            ("class A[Unquoted]", .invalidSyntax(line: 2, problem: .expectedQuotedText)),
            ("class A[\"Label\"", .invalidSyntax(line: 2, problem: .unclosedShape(closingText: "]"))),
            ("class A {\n+x", .invalidSyntax(line: 2, problem: .unclosedClassBody(identifier: "A"))),
            ("class A {\n+x {", .invalidSyntax(line: 3, problem: .unexpectedText("{"))),
            ("A~T --> B", .invalidSyntax(line: 2, problem: .unclosedGenericType)),
            ("`Open --> B", .invalidSyntax(line: 2, problem: .unclosedQuotation)),
            ("<<interface Shape", .invalidSyntax(line: 2, problem: .unclosedAnnotation)),
            ("<<>> Shape", .invalidSyntax(line: 2, problem: .unexpectedText("<<>>"))),
            ("<<interface>>", .invalidSyntax(line: 2, problem: .expectedName)),
            ("A \"1\" B", .invalidSyntax(line: 2, problem: .expectedRelationLine)),
            ("A <| B", .invalidSyntax(line: 2, problem: .expectedRelationLine)),
            ("A -->", .invalidSyntax(line: 2, problem: .expectedName)),
            ("A --> B C", .invalidSyntax(line: 2, problem: .unexpectedText("C"))),
            ("A B", .invalidSyntax(line: 2, problem: .unexpectedText("B"))),
            ("note link", .invalidSyntax(line: 2, problem: .expectedQuotedText)),
            ("note for \"text\"", .invalidSyntax(line: 2, problem: .expectedName)),
            ("namespace N {\nclass X", .invalidSyntax(line: 3, problem: .unclosedNamespace(identifier: "N"))),
            ("namespace N {\n  A --> B\n}", .invalidSyntax(line: 3, problem: .unexpectedText("A --> B"))),
            ("namespace {", .invalidSyntax(line: 2, problem: .expectedName)),
            ("accDescr {\nnever closed", .invalidSyntax(line: 2, problem: .unclosedAccessibilityDescription)),
            ("class A\n@", .invalidSyntax(line: 3, problem: .unexpectedText("@"))),
        ]
        for (body, error) in cases {
            XCTAssertEqual(readError(body), error, body)
        }
        XCTAssertEqual(ClassDiagramReading.readError("classDiagram LR\nclass A"), .invalidSyntax(line: 1, problem: .unexpectedText("LR")))
    }

    func testLimitsAreCheckedBeforeAnythingPastThemIsMade() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertNil(readError("class A\nclass B\nA --> B", limits: limits))
        XCTAssertEqual(readError("class A\nclass B\nclass C", limits: limits), .tooManyNodes(limit: 2))
        XCTAssertEqual(readError("class A\nnote \"one\"\nnote \"two\"", limits: limits), .tooManyNodes(limit: 2))
        XCTAssertEqual(readError("A --() bar\nB --> A", limits: limits), .tooManyNodes(limit: 2))
        limits = .standard
        limits.maximumEdgeCount = 1
        XCTAssertEqual(readError("A --> B\nB --> C", limits: limits), .tooManyEdges(limit: 1))
    }

    func testTheV2KeywordAndAnEmptyDiagramRead() throws {
        XCTAssertEqual(try ClassDiagramReading.classDiagram("classDiagram-v2\n  Animal <|-- Duck").classes.count, 2)
        XCTAssertEqual(try ClassDiagramReading.classDiagram("classDiagram\n").classes, [])
    }
}
