import XCTest
@testable import MermaidDiagrams

final class FlowchartParserTests: XCTestCase {
    private func flowchart(_ body: String, header: String = "flowchart TD") throws -> FlowchartDiagram {
        try FlowchartReading.flowchart(header + "\n" + body)
    }

    private func readError(_ body: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        FlowchartReading.readError("flowchart TD\n" + body, limits: limits)
    }

    private func onlyEdge(_ body: String) throws -> FlowchartEdge {
        let edges = try flowchart(body).edges
        XCTAssertEqual(edges.count, 1)
        return try XCTUnwrap(edges.first)
    }

    // MARK: Direction

    func testTheDirectionIsTopToBottomUnlessTheHeaderNamesOne() throws {
        XCTAssertEqual(try flowchart("A", header: "flowchart").direction, .topToBottom)
        XCTAssertEqual(try flowchart("A", header: "graph LR;").direction, .leftToRight)
        XCTAssertEqual(try flowchart("A", header: "flowchart BT %% bottom up").direction, .bottomToTop)
        XCTAssertEqual(try flowchart("A", header: "graph <").direction, .rightToLeft)
    }

    func testAnUnknownDirectionIsReportedOnTheHeaderLine() {
        XCTAssertEqual(FlowchartReading.readError("flowchart XY\nA"), .invalidSyntax(line: 1, problem: .unknownDirection("XY")))
    }

    func testStatementsCanFollowTheHeaderOnItsLine() throws {
        let diagram = try flowchart("", header: "graph TD;A-->B;B-->C")
        XCTAssertEqual(diagram.edges.count, 2)
    }

    // MARK: Nodes

    func testEachBracketPairGivesItsShape() throws {
        let cases: [(String, FlowchartNodeShape)] = [
            ("A[text]", .rectangle), ("A(text)", .roundedRectangle), ("A([text])", .stadium), ("A[[text]]", .subroutine),
            ("A[(text)]", .cylinder), ("A((text))", .circle), ("A(((text)))", .doubleCircle), ("A>text]", .asymmetric),
            ("A{text}", .diamond), ("A{{text}}", .hexagon), ("A[/text/]", .leanRight), ("A[\\text\\]", .leanLeft),
            ("A[/text\\]", .trapezoid), ("A[\\text/]", .invertedTrapezoid),
        ]
        for (statement, shape) in cases {
            let node = try XCTUnwrap(try flowchart(statement).nodes.first, statement)
            XCTAssertEqual(node.shape, shape, statement)
            XCTAssertEqual(node.label, DiagramLabel("text"), statement)
        }
    }

    func testANodeWithoutTextShowsItsIdentifierInARectangle() throws {
        XCTAssertEqual(try flowchart("Start --> End_2").nodes, [
            FlowchartNode(identifier: "Start", label: DiagramLabel("Start")),
            FlowchartNode(identifier: "End_2", label: DiagramLabel("End_2")),
        ])
    }

    func testIdentifiersMayHoldHyphensAndCharactersBeyondASCII() throws {
        let diagram = try flowchart("step-1 --> Étape_2-b")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["step-1", "Étape_2-b"])
    }

    func testQuotedTextMayHoldBracketsAndSemicolons() throws {
        let node = try XCTUnwrap(try flowchart("A[\"Call f(x); then [check]\"]").nodes.first)
        XCTAssertEqual(node.label, DiagramLabel("Call f(x); then [check]"))
    }

    func testAMarkdownStringAndLineBreaksGiveSeveralLines() throws {
        let node = try XCTUnwrap(try flowchart("A[\"`**First** line\nsecond`\"] --> B[one<br/>two]").nodes.first)
        XCTAssertEqual(node.label.lines, ["First line", "second"])
        XCTAssertEqual(try flowchart("B[one<br/>two]").nodes.first?.label.lines, ["one", "two"])
    }

    func testALaterDefinitionReplacesTheShapeAndTextOfAnEarlierOne() throws {
        let diagram = try flowchart("A --> B\nA{Decide}\nA[Rectangle again]")
        XCTAssertEqual(diagram.nodes[0], FlowchartNode(identifier: "A", label: DiagramLabel("Rectangle again"), shape: .rectangle))
    }

    func testAttributesNameTheShapeAndTheText() throws {
        let diagram = try flowchart("A@{ shape: diam, label: \"Is it, really?\" }\nB@{shape: cloud}\nC@{ icon: \"fa:user\",\n  shape: cyl }")
        XCTAssertEqual(diagram.nodes[0], FlowchartNode(identifier: "A", label: DiagramLabel("Is it, really?"), shape: .diamond))
        XCTAssertEqual(diagram.nodes[1].shape, .rectangle, "A shape not drawn yet is drawn as a rectangle")
        XCTAssertEqual(diagram.nodes[2].shape, .cylinder)
    }

    func testClassesOnANodeAreCountedAndTheNodeIsKept() throws {
        let diagram = try flowchart("A[Start]:::important --> B:::quiet")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["A", "B"])
        XCTAssertEqual(diagram.unappliedStatementCount, 2)
    }

    // MARK: Edges

    func testEachOperatorGivesItsStrokeMarksAndSpan() throws {
        let cases: [(String, FlowchartEdgeStroke, FlowchartArrowhead, FlowchartArrowhead, Int)] = [
            ("A-->B", .solid, .none, .arrow, 1), ("A --- B", .solid, .none, .none, 1), ("A--->B", .solid, .none, .arrow, 2),
            ("A----B", .solid, .none, .none, 2), ("A -.-> B", .dotted, .none, .arrow, 1), ("A-.-B", .dotted, .none, .none, 1),
            ("A-..->B", .dotted, .none, .arrow, 2), ("A ==> B", .thick, .none, .arrow, 1), ("A===B", .thick, .none, .none, 1),
            ("A===>B", .thick, .none, .arrow, 2), ("A ~~~ B", .invisible, .none, .none, 1), ("A --o B", .solid, .none, .circle, 1),
            ("A --x B", .solid, .none, .cross, 1), ("A <--> B", .solid, .arrow, .arrow, 1), ("A o--o B", .solid, .circle, .circle, 1),
            ("A x==x B", .thick, .cross, .cross, 1), ("A <-.-> B", .dotted, .arrow, .arrow, 1),
        ]
        for (statement, stroke, sourceArrowhead, targetArrowhead, span) in cases {
            let edge = try onlyEdge(statement)
            XCTAssertEqual(edge, FlowchartEdge(sourceIndex: 0, targetIndex: 1, stroke: stroke, sourceArrowhead: sourceArrowhead,
                                               targetArrowhead: targetArrowhead, minimumRankSpan: span), statement)
        }
    }

    func testTextBetweenBarsLabelsTheEdge() throws {
        XCTAssertEqual(try onlyEdge("A -->|Yes| B").label, DiagramLabel("Yes"))
        XCTAssertEqual(try onlyEdge("A-- \"a|b\" -->B").label, DiagramLabel("a|b"))
        XCTAssertEqual(try onlyEdge("A ---|\"x|y\"| B").label, DiagramLabel("x|y"))
    }

    func testTextInsideTheLinkLabelsTheEdgeAndTheClosingGivesTheMark() throws {
        let solid = try onlyEdge("A -- needs review ---> B")
        XCTAssertEqual(solid.label, DiagramLabel("needs review"))
        XCTAssertEqual(solid.minimumRankSpan, 2)
        XCTAssertEqual(try onlyEdge("A -. maybe .-> B").label, DiagramLabel("maybe"))
        XCTAssertEqual(try onlyEdge("A -. maybe .-> B").stroke, .dotted)
        let thick = try onlyEdge("A == surely ==x B")
        XCTAssertEqual(thick.label, DiagramLabel("surely"))
        XCTAssertEqual(thick.targetArrowhead, .cross)
    }

    func testAChainMakesAnEdgeForEachLink() throws {
        let diagram = try flowchart("A --> B -->|then| C --- D")
        XCTAssertEqual(diagram.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[0, 1], [1, 2], [2, 3]])
        XCTAssertEqual(diagram.edges[1].label, DiagramLabel("then"))
    }

    func testAnAmpersandMakesAnEdgeFromEachNodeBeforeToEachAfter() throws {
        let diagram = try flowchart("A & B --> C & D")
        XCTAssertEqual(diagram.edges.map { edge in [edge.sourceIndex, edge.targetIndex] }, [[0, 2], [0, 3], [1, 2], [1, 3]])
    }

    func testAnEdgeIdentifierIsReadAndItsAttributesNameNoNode() throws {
        let diagram = try flowchart("A e1@--> B\ne1@{ animate: true }")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["A", "B"])
        XCTAssertEqual(diagram.edges.count, 1)
        XCTAssertEqual(diagram.unappliedStatementCount, 1)
    }

    func testANodeLinkedToItselfIsOneEdge() throws {
        XCTAssertEqual(try onlyEdge("A --> A"), FlowchartEdge(sourceIndex: 0, targetIndex: 0))
    }

    // MARK: Statements

    func testSemicolonsAndLineBreaksBothEndStatements() throws {
        let diagram = try flowchart("A-->B;B-->C\n\n  C-->D;")
        XCTAssertEqual(diagram.edges.count, 3)
    }

    func testCommentsAreSkippedOnTheirOwnLinesAndAfterAStatement() throws {
        let diagram = try flowchart("%% the start\nA --> B %% then B\n%% end")
        XCTAssertEqual(diagram.edges.count, 1)
    }

    func testStyleStatementsAreCountedAndLeft() throws {
        let diagram = try flowchart("""
        A --> B
        classDef warm fill:#f96,stroke:#333;
        class A,B warm
        style A fill:#f9f,stroke:#333,stroke-width:4px; B --> C
        linkStyle 0 stroke:#ff3,stroke-width:4px
        click A "https://example.com" "Tooltip; with a semicolon"
        """)
        XCTAssertEqual(diagram.unappliedStatementCount, 5)
        XCTAssertEqual(diagram.edges.count, 2, "A statement after a style's semicolon is read")
    }

    func testAccessibilityTitleAndDescriptionAreKept() throws {
        let diagram = try flowchart("accTitle: Order flow\naccDescr {\n  How an order\n  is handled\n}\nA --> B")
        XCTAssertEqual(diagram.accessibilityTitle, "Order flow")
        XCTAssertEqual(diagram.accessibilityDescription, "How an order is handled")
        XCTAssertEqual(try flowchart("accDescr: One line").accessibilityDescription, "One line")
    }

    // MARK: Groups

    func testAGroupTakesTheNodesWrittenInsideItAndItsDirection() throws {
        let diagram = try flowchart("""
        A --> B
        subgraph outer [The outside]
          direction LR
          B --> C
          subgraph inner
            D
          end
        end
        subgraph "Quoted title"
          E
        end
        subgraph Two words
          F
        end
        """)
        XCTAssertEqual(diagram.subgraphs, [
            FlowchartSubgraph(identifier: "outer", title: DiagramLabel("The outside"), nodeIndices: [1, 2], childSubgraphIndices: [1],
                              direction: .leftToRight),
            FlowchartSubgraph(identifier: "inner", title: DiagramLabel("inner"), nodeIndices: [3]),
            FlowchartSubgraph(identifier: "subGraph2", title: DiagramLabel("Quoted title"), nodeIndices: [4]),
            FlowchartSubgraph(identifier: "subGraph3", title: DiagramLabel("Two words"), nodeIndices: [5]),
        ])
        XCTAssertEqual(diagram.unappliedStatementCount, 0)
    }

    func testADirectionOutsideAGroupOrNamingNoDirectionIsLeft() throws {
        let diagram = try flowchart("direction LR\nsubgraph one\ndirection sideways\nA\nend")
        XCTAssertNil(diagram.subgraphs[0].direction)
        XCTAssertEqual(diagram.unappliedStatementCount, 2)
    }

    func testEndWithoutAGroupAndAGroupLeftOpenAreErrors() {
        XCTAssertEqual(readError("A --> B\nend"), .invalidSyntax(line: 3, problem: .endWithoutSubgraph))
        XCTAssertEqual(readError("subgraph open\n A"), .invalidSyntax(line: 3, problem: .unclosedSubgraph(identifier: "open")))
    }

    func testAWordThatStartsLikeAKeywordIsANode() throws {
        let diagram = try flowchart("classes --> ending\nstyles & endpoint --> subgraphs")
        XCTAssertEqual(diagram.nodes.map(\.identifier), ["classes", "ending", "styles", "endpoint", "subgraphs"])
        XCTAssertEqual(diagram.unappliedStatementCount, 0)
    }

    // MARK: Errors and limits

    func testUnclosedTextIsReportedWhereItOpens() {
        XCTAssertEqual(readError("A --> B\nC[never closed\nD --> E"), .invalidSyntax(line: 3, problem: .unclosedShape(closingText: "]")))
        XCTAssertEqual(readError("A[\"open quote]"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
        XCTAssertEqual(readError("A -->|yes B"), .invalidSyntax(line: 2, problem: .unclosedEdgeLabel))
        XCTAssertEqual(readError("A -- no end B"), .invalidSyntax(line: 2, problem: .unclosedEdgeLabel))
        XCTAssertEqual(readError("A@{ shape: rect"), .invalidSyntax(line: 2, problem: .unclosedAttributes))
    }

    func testTextThatFitsNoStatementIsShownInTheError() {
        XCTAssertEqual(readError("A --> B C"), .invalidSyntax(line: 2, problem: .unexpectedText("C")))
        XCTAssertEqual(readError("A -->"), .invalidSyntax(line: 2, problem: .expectedNode))
        XCTAssertEqual(readError("A --> --> B"), .invalidSyntax(line: 2, problem: .unexpectedText("--> B")))
    }

    func testEdgesPastTheLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumEdgeCount = 8
        XCTAssertNil(readError("A & B --> C & D & E & F", limits: limits))
        XCTAssertEqual(readError("A & B & C --> D & E & F", limits: limits), .tooManyEdges(limit: 8))
    }

    func testNodesPastTheLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertEqual(readError("A --> B --> C", limits: limits), .tooManyNodes(limit: 2))
    }
}
