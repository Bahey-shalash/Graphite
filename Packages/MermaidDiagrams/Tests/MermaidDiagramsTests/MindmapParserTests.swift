import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's mindmap parser specs (`mindmap.spec.ts` and `mindmapDb.getData.test.ts`, as Pele
/// ports them in `tests/compat`), the examples of Mermaid's mindmap documentation, and the errors.
final class MindmapParserTests: XCTestCase {
    private func mindmap(_ source: String) throws -> MindmapDiagram {
        try MindmapReading.mindmap(source)
    }

    private func texts(_ diagram: MindmapDiagram, _ indices: [Int]) -> [String] {
        indices.map { index in diagram.nodes[index].label.spokenText }
    }

    // MARK: Hierarchy

    func testOneNodeIsTheRoot() throws {
        let diagram = try mindmap("mindmap\n    root")
        XCTAssertEqual(diagram.nodes, [MindmapNode(identifier: "root", label: DiagramLabel("root"), shape: .plain, parentIndex: nil, branchIndex: nil)])
    }

    func testIndentationGivesTheHierarchy() throws {
        let diagram = try mindmap("mindmap\n    root\n      child1\n        leaf1\n      child2")
        XCTAssertEqual(texts(diagram, diagram.nodes[0].childIndices), ["child1", "child2"])
        XCTAssertEqual(texts(diagram, diagram.nodes[1].childIndices), ["leaf1"])
        XCTAssertEqual(diagram.nodes[2].parentIndex, 1)
        XCTAssertEqual(diagram.nodes[3].parentIndex, 0)
    }

    func testTheParentIsTheLastNodeWithASmallerIndentationWhereverItIs() throws {
        // C is less indented than B but more than A: it is A's child, as in Mermaid's documentation.
        let diagram = try mindmap("mindmap\nRoot\n    A\n        B\n      C")
        XCTAssertEqual(texts(diagram, diagram.nodes[1].childIndices), ["B", "C"])
    }

    func testTheRootMayStartAtTheLineStartOrOnTheKeywordsLine() throws {
        XCTAssertEqual(try mindmap("mindmap\nroot\n      theId(child1)").nodes[1].parentIndex, 0)
        XCTAssertEqual(try mindmap("mindmap root\n  child").nodes.map(\.parentIndex), [nil, 0])
    }

    func testASecondRootIsReportedOnItsLine() {
        XCTAssertEqual(MindmapReading.readError("mindmap\n    root\n    fakeRoot"), .invalidSyntax(line: 3, problem: .secondRoot(text: "fakeRoot")))
        XCTAssertEqual(MindmapReading.readError("mindmap\n          root\n        fakeRoot\n    realRootWrongPlace"),
                       .invalidSyntax(line: 3, problem: .secondRoot(text: "fakeRoot")))
    }

    func testEmptyRowsRowsOfSpacesAndCommentsDoNotInterfere() throws {
        let commented = try mindmap("mindmap\n  root(Root)\n    Child(Child)\n      a(a)\n\n      %% This is a comment\n      b[New Stuff]")
        XCTAssertEqual(texts(commented, commented.nodes[1].childIndices), ["a", "New Stuff"])
        let spaced = try mindmap("mindmap\nroot\n A\n \n\n B")
        XCTAssertEqual(texts(spaced, spaced.nodes[0].childIndices), ["A", "B"])
        let crlf = try mindmap("mindmap\r\n  root\r\n    A\r\n\r\n    B\r\n")
        XCTAssertEqual(texts(crlf, crlf.nodes[0].childIndices), ["A", "B"])
    }

    func testACommentMayEndANodesLine() throws {
        let diagram = try mindmap("mindmap\n  root(Root)\n    Child(Child)\n      a(a) %% This is a comment\n      b[New Stuff]")
        XCTAssertEqual(texts(diagram, diagram.nodes[1].childIndices), ["a", "New Stuff"])
    }

    // MARK: Nodes

    func testEachPairOfDelimitersGivesItsShape() throws {
        let cases: [(String, MindmapNodeShape)] = [
            ("id[text]", .rectangle), ("id(text)", .roundedRectangle), ("id((text))", .circle), ("id)text(", .cloud),
            ("id))text((", .bang), ("id{{text}}", .hexagon), ("text", .plain), ("(-text)", .plain), ("id(text((", .cloud),
            ("[text)", .rectangle),
        ]
        for (statement, shape) in cases {
            let root = try XCTUnwrap(try mindmap("mindmap\n " + statement).nodes.first, statement)
            XCTAssertEqual(root.shape, shape, statement)
            XCTAssertEqual(root.label, DiagramLabel("text"), statement)
        }
    }

    func testTheIdentifierComesBeforeTheDelimitersOrIsTheText() throws {
        let diagram = try mindmap("mindmap\n    root[The root]\n      theId(child1)\n      (no identifier)\n      I am the default shape")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["root", "theId", "no identifier", "I am the default shape"])
        XCTAssertEqual(diagram.nodes.map(\.label.spokenText), ["The root", "child1", "no identifier", "I am the default shape"])
    }

    func testQuotedTextMayHoldDelimiters() throws {
        let diagram = try mindmap("mindmap\n    root[\"String containing []\"]\n      child1[\"String containing ()\"]")
        XCTAssertEqual(diagram.nodes.map(\.label.spokenText), ["String containing []", "String containing ()"])
        XCTAssertEqual(diagram.nodes[0].identifier, "root")
    }

    func testAMarkdownStringKeepsItsLinesAndLosesItsEmphasis() throws {
        let diagram = try mindmap("""
        mindmap
            id1["`**Root** with
        a second line
        Unicode works too: 🤓`"]
              id2["`The dog in **the** hog... a *very long text* that wraps to a new line`"]
              id3[Regular labels still works]
        """)
        XCTAssertEqual(diagram.nodes[0].label.lines, ["Root with", "a second line", "Unicode works too: 🤓"])
        XCTAssertEqual(diagram.nodes[1].label.lines, ["The dog in the hog... a very long text that wraps to a new line"])
        XCTAssertEqual(diagram.nodes[2].label.lines, ["Regular labels still works"])
        XCTAssertEqual(diagram.nodes.map(\.parentIndex), [nil, 0, 0])
    }

    func testABreakTagEndsALineAndEntityCodesAreRead() throws {
        let diagram = try mindmap("mindmap\n  root\n    On effectiveness<br/>and features\n    Caf#233; &amp; tea")
        XCTAssertEqual(diagram.nodes[1].label.lines, ["On effectiveness", "and features"])
        XCTAssertEqual(diagram.nodes[2].label.lines, ["Café & tea"])
    }

    // MARK: Decorations and accessibility

    func testIconsAndClassesAreReadAndNotApplied() throws {
        let diagram = try mindmap("mindmap\n    root[The root]\n    :::m-4 p-8\n    ::icon(bomb)\n    ::ICON(fa fa-book)\n")
        XCTAssertEqual(diagram.nodes.count, 1)
        XCTAssertEqual(diagram.nodes[0].shape, .rectangle)
        XCTAssertEqual(diagram.unappliedDecorationCount, 3)
    }

    func testANodeMayFollowAClassAndKeepItsPlace() throws {
        let diagram = try mindmap("mindmap\n  root(Root)\n    Child(Child)\n    :::hot\n      a(a)\n      b[New Stuff]")
        XCTAssertEqual(diagram.nodes[0].childIndices, [1])
        XCTAssertEqual(texts(diagram, diagram.nodes[1].childIndices), ["a", "New Stuff"])
    }

    func testAccessibilityTextIsReadWhereverItIsWritten() throws {
        let diagram = try mindmap("mindmap\n  accTitle: Plans\n  root\n    accDescr {\n      What we plan\n      this year\n    }\n    child")
        XCTAssertEqual(diagram.accessibilityTitle, "Plans")
        XCTAssertEqual(diagram.accessibilityDescription, "What we plan this year")
        XCTAssertEqual(texts(diagram, diagram.nodes[0].childIndices), ["child"])
        XCTAssertEqual(try mindmap("mindmap\n  root\n  accDescr: One line").accessibilityDescription, "One line")
    }

    // MARK: Branches

    func testEachFirstLevelBranchHasItsIndexAndItsNodesShareIt() throws {
        let diagram = try mindmap("mindmap\nA\n  a0\n    aa0\n  a1\n    aaa\n  a2")
        XCTAssertEqual(diagram.nodes.map(\.branchIndex), [nil, 0, 0, 1, 1, 2])
    }

    func testBranchIndexesStartAgainAfterEleven() throws {
        let source = "mindmap\nroot\n" + (1...15).map { number in "  child\(number)" }.joined(separator: "\n")
        let branches = try mindmap(source).nodes.dropFirst().map(\.branchIndex)
        XCTAssertEqual(branches, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 1, 2, 3])
    }

    // MARK: Errors and limits

    func testAMindmapWithoutANodeIsAnError() {
        XCTAssertEqual(MindmapReading.readError("mindmap"), .invalidSyntax(line: 1, problem: .expectedNode))
        XCTAssertEqual(MindmapReading.readError("mindmap\n  ::icon(bomb)\n"), .invalidSyntax(line: 3, problem: .expectedNode))
    }

    func testUnclosedTextIsReportedOnTheLineItOpens() {
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root\n    a[never closed\n    b"),
                       .invalidSyntax(line: 3, problem: .unclosedShape(closingText: "]")))
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root((open"), .invalidSyntax(line: 2, problem: .unclosedShape(closingText: "))")))
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root[\"open]"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root\n  ::icon(fa fa-book"), .invalidSyntax(line: 3, problem: .unclosedIcon))
    }

    func testTextThatFitsNoStatementIsUnexpected() {
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root[text] more"), .invalidSyntax(line: 2, problem: .unexpectedText("more")))
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root[]"), .invalidSyntax(line: 2, problem: .unexpectedText("]")))
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root{text}"), .invalidSyntax(line: 2, problem: .unexpectedText("{text}")))
        XCTAssertEqual(MindmapReading.readError("mindmap\n  root[\"text\" tail]"), .invalidSyntax(line: 2, problem: .unexpectedText(" tail]")))
    }

    func testNodesPastTheLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertEqual(MindmapReading.readError("mindmap\nroot\n  a\n  b\n  c", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertNil(MindmapReading.readError("mindmap\nroot\n  a\n  b", limits: limits))
    }

    // MARK: Mermaid's documentation

    func testTheDocumentationsFirstExampleReads() throws {
        let diagram = try mindmap("""
        mindmap
          root((mindmap))
            Origins
              Long history
              ::icon(fa fa-book)
              Popularisation
                British popular psychology author Tony Buzan
            Research
              On effectiveness<br/>and features
              On Automatic creation
                Uses
                    Creative techniques
                    Strategic planning
                    Argument mapping
            Tools
              Pen and paper
              Mermaid

        """)
        XCTAssertEqual(diagram.nodes.count, 15)
        XCTAssertEqual(diagram.nodes[0].shape, .circle)
        XCTAssertEqual(texts(diagram, diagram.nodes[0].childIndices), ["Origins", "Research", "Tools"])
        XCTAssertEqual(diagram.nodes.last?.branchIndex, 2)
        XCTAssertEqual(diagram.unappliedDecorationCount, 1)
        let uses = try XCTUnwrap(diagram.nodes.firstIndex { node in node.identifier == "Uses" })
        XCTAssertEqual(texts(diagram, diagram.nodes[uses].childIndices), ["Creative techniques", "Strategic planning", "Argument mapping"])
    }
}
