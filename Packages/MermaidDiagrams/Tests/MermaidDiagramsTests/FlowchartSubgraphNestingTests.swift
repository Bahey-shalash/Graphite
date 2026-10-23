import XCTest
@testable import MermaidDiagrams

/// Groups as Mermaid 12.1.0 reads them: the inputs are those of its `subgraph.spec.js`, as Pele's `tests/compat` carries
/// them (MIT licensed), with the identifiers, titles, members and nesting its expectations give.
final class FlowchartSubgraphNestingTests: XCTestCase {
    private func memberIdentifiers(of subgraph: FlowchartSubgraph, in diagram: FlowchartDiagram) -> Set<String> {
        Set(subgraph.nodeIndices.map { index in diagram.nodes[index].identifier }
            + subgraph.childSubgraphIndices.map { index in diagram.subgraphs[index].identifier })
    }

    private func subgraph(_ identifier: String, in diagram: FlowchartDiagram) throws -> FlowchartSubgraph {
        try XCTUnwrap(diagram.subgraphs.first { subgraph in subgraph.identifier == identifier })
    }

    func testAGroupTakesEveryNodeOfTheChainsWrittenInIt() throws {
        let diagram = try FlowchartReading.flowchart("graph TB\nsubgraph One\n\ta1-->a2-->a3\nend")
        XCTAssertEqual(diagram.subgraphs.count, 1)
        XCTAssertEqual(diagram.subgraphs[0].identifier, "One")
        XCTAssertEqual(diagram.subgraphs[0].title, DiagramLabel("One"))
        XCTAssertEqual(memberIdentifiers(of: diagram.subgraphs[0], in: diagram), ["a1", "a2", "a3"])
    }

    func testTheIdentifierAndTitleOfEachHeaderForm() throws {
        let cases: [(header: String, identifier: String, title: String)] = [
            ("subgraph \"Some Title\"", "subGraph0", "Some Title"),
            ("subgraph some-id[Some Title]", "some-id", "Some Title"),
            ("subgraph uid1[text of doom]", "uid1", "text of doom"),
            ("subgraph uid2[\"text of doom\"]", "uid2", "text of doom"),
            ("subgraph uid2[textofdoom]", "uid2", "textofdoom"),
            ("subgraph old style that is broken", "subGraph0", "old style that is broken"),
            ("subgraph a-b-c", "a-b-c", "a-b-c"),
            ("subgraph 1test", "1test", "1test"),
        ]
        for (header, identifier, title) in cases {
            let diagram = try FlowchartReading.flowchart("graph TD\nA-->B\n\(header)\nc-->d\nend")
            XCTAssertEqual(diagram.subgraphs.map(\.identifier), [identifier], header)
            XCTAssertEqual(diagram.subgraphs.first?.title, DiagramLabel(title), header)
            XCTAssertEqual(diagram.edges.count, 2, header)
        }
    }

    func testAGroupWrittenOnOneLineEndsAtItsSemicolons() throws {
        for source in ["graph TD;A-->B;subgraph myTitle;c-->d;end;", "graph TD;A-->B;subgraph \"title in quotes\";c-->d;end;",
                       "graph TD\nA-->B\nsubgraph myTitle\nc-->d\nend;"] {
            let diagram = try FlowchartReading.flowchart(source)
            XCTAssertEqual(diagram.subgraphs.count, 1, source)
            XCTAssertEqual(memberIdentifiers(of: diagram.subgraphs[0], in: diagram), ["c", "d"], source)
        }
        XCTAssertEqual(try FlowchartReading.flowchart("graph TD;subgraph \"title in quotes\";c-->d;end;").subgraphs[0].title,
                       DiagramLabel("title in quotes"))
    }

    func testANodeNamedAgainInAGroupJoinsIt() throws {
        let diagram = try FlowchartReading.flowchart("graph TD\nA[Christmas] -->|Get money| B(Go shopping)\nsubgraph 1test\nA\nend")
        XCTAssertEqual(memberIdentifiers(of: diagram.subgraphs[0], in: diagram), ["A"])
    }

    func testGroupsWithOneIdentifierAreOneGroup() throws {
        let diagram = try FlowchartReading.flowchart("""
        graph TD
        A-->B
        subgraph myTitle

         c-->d

         subgraph inner

           e-->f
         end

         subgraph inner

           h-->i
         end

        end
        """)
        XCTAssertEqual(diagram.subgraphs.map(\.identifier), ["myTitle", "inner"])
        XCTAssertEqual(memberIdentifiers(of: try subgraph("inner", in: diagram), in: diagram), ["e", "f", "h", "i"])
        XCTAssertEqual(memberIdentifiers(of: try subgraph("myTitle", in: diagram), in: diagram), ["c", "d", "inner"])
    }

    func testAGroupNamedInsideAnotherIsNestedInItWhereverItIsWritten() throws {
        let sources = [
            "flowchart TB\nsubgraph A\nb-->B\na\nend\na-->c\nsubgraph B\nc\nend",
            "flowchart TB\nb-->B\na-->c\nsubgraph B\nc\nend\nsubgraph A\na\nb\nB\nend",
            "flowchart TB\nsubgraph B\nc\nend\na-->c\nsubgraph A\nb-->B\na\nend",
        ]
        for source in sources {
            let diagram = try FlowchartReading.flowchart(source)
            let outer = try subgraph("A", in: diagram)
            let inner = try subgraph("B", in: diagram)
            XCTAssertEqual(memberIdentifiers(of: inner, in: diagram), ["c"], source)
            XCTAssertEqual(memberIdentifiers(of: outer, in: diagram), ["a", "b", "B"], source)
            XCTAssertEqual(diagram.subgraphs.first?.identifier, "A", "The outer group comes first: \(source)")
            XCTAssertEqual(inner.representingNodeIndex.map { index in diagram.nodes[index].identifier }, "B", source)
        }
    }

    func testANodeNamedInAGroupAndInTheGroupAroundItBelongsToTheInnerOne() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TB\nsubgraph outer\nA --> B\nsubgraph inner\nA\nend\nend")
        XCTAssertEqual(memberIdentifiers(of: try subgraph("inner", in: diagram), in: diagram), ["A"])
        XCTAssertEqual(memberIdentifiers(of: try subgraph("outer", in: diagram), in: diagram), ["B", "inner"])
    }

    func testANodeNamedInTwoGroupsSideBySideBelongsToTheFirstToEnd() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TB\nsubgraph one\nA\nend\nsubgraph two\nA --> B\nend")
        XCTAssertEqual(memberIdentifiers(of: try subgraph("one", in: diagram), in: diagram), ["A"])
        XCTAssertEqual(memberIdentifiers(of: try subgraph("two", in: diagram), in: diagram), ["B"])
    }

    func testAGroupNeverHoldsItself() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TB\nsubgraph A\nA --> B\nend")
        XCTAssertEqual(memberIdentifiers(of: diagram.subgraphs[0], in: diagram), ["B"])
        XCTAssertEqual(diagram.subgraphs[0].representingNodeIndex, 0)
    }

    func testGroupsNamedInsideEachOtherAreNestedOnceTheLastToEndOutside() throws {
        let diagram = try FlowchartReading.flowchart("flowchart TB\nsubgraph A\nB\nend\nsubgraph B\nA\nend")
        XCTAssertEqual(diagram.subgraphs.map(\.identifier), ["B", "A"])
        XCTAssertEqual(diagram.subgraphs[0].childSubgraphIndices, [1])
        XCTAssertEqual(diagram.subgraphs[1].childSubgraphIndices, [])
    }

    func testADirectionInsideAGroupIsKept() throws {
        let diagram = try FlowchartReading.flowchart("graph LR\n  subgraph WithTD\n    direction TD\n    A1 --> A2\n  end")
        XCTAssertEqual(diagram.subgraphs[0].direction, .topToBottom)
        XCTAssertEqual(memberIdentifiers(of: diagram.subgraphs[0], in: diagram), ["A1", "A2"])
    }

    func testACollapsedViewOnAGroupIsKept() throws {
        let diagram = try FlowchartReading.flowchart("graph TD\nsubgraph one [My Group]\nA --> B\nend\nC --> A\none@{ view: collapsed }")
        XCTAssertTrue(diagram.subgraphs[0].isCollapsed)
        XCTAssertEqual(diagram.subgraphs[0].title, DiagramLabel("My Group"))
        XCTAssertFalse(try FlowchartReading.flowchart("graph TD\nsubgraph one\nA\nend").subgraphs[0].isCollapsed)
    }
}
