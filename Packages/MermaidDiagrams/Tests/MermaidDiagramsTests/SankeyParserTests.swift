import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// The inputs of Mermaid 12.1.0's `sankey.spec.ts` (ported to Pele's `tests/compat/sankey`, its `energy.csv` among
/// them), Mermaid's documentation examples, and the errors.
final class SankeyParserTests: XCTestCase {
    private func diagram(_ source: String) throws -> SankeyDiagram {
        try SankeyReading.diagram(source)
    }

    // MARK: Mermaid's spec

    func testTheEnergyFlowsReadWithEitherKeyword() throws {
        let rows = try SankeyCorpus.energyRows()
        for keyword in ["sankey-beta", "sankey"] {
            let read = try diagram(keyword + "\n\n " + rows)
            XCTAssertEqual(read.links.count, 70, keyword)
            XCTAssertEqual(read.nodes.count, 52, keyword)
            XCTAssertEqual(Array(read.nodes.prefix(6).map(\.name)), ["Agricultural 'waste'", "Bio-conversion", "Liquid", "sankey", "target", "Losses"])
        }
    }

    func testTheEnergyFlowsKeepQuotedFieldsCommasAndQuotationMarks() throws {
        let read = try diagram("sankey-beta\n\n " + SankeyCorpus.energyRows())
        let names = Set(read.nodes.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["\"Biomass imports\"", "Heating and cooling, commercial", "Heating and cooling, homes", "\"Wave\"", "\"Wind\""]))
        XCTAssertTrue(SankeyReading.rows(read).contains("sankey → target: 10.0"), "The keyword unquoted in a row is a name")
        XCTAssertTrue(SankeyReading.rows(read).contains("Bio-conversion → Solid: 280.0"))
        XCTAssertEqual(SankeyReading.rows(read).first, "Agricultural 'waste' → Bio-conversion: 124.729", "Spaces around a field are left")
    }

    func testProtoIsANameLikeAnyOther() throws {
        for keyword in ["sankey-beta", "sankey"] {
            let read = try diagram("\(keyword)\n      __proto__,A,0.597\n      A,__proto__,0.403\n      ")
            XCTAssertEqual(read.nodes.map(\.name), ["__proto__", "A"])
            XCTAssertEqual(read.links.map(\.value), [0.597, 0.403])
        }
    }

    func testTheSampleOfIssue7528ReadsItsSpecialCharacters() throws {
        let sample = """

              Agricultural 'waste',Bio-conversion,124.729
              Bio-conversion,Liquid,0.597
              Bio-conversion,Losses,26.862
              Bio-conversion,Solid,280.322
              Bio-conversion,Gas,81.144
              Biofuel imports,Liquid,35
              Biomass imports,Solid,35
              Coal imports,Coal,11.606
              Coal reserves,Coal,63.965
              Coal,Solid,75.571
              District heating,Industry,10.639
              District heating,Heating and cooling - homes,22.505
              District heating,Heating and cooling - commercial,46.184
              Electricity grid,Over generation / exports,104.453
              Electricity grid,Lighting & appliances - commercial,113.726
              Electricity grid,Lighting & appliances - homes,27.14

        """
        for keyword in ["sankey-beta", "sankey"] {
            let read = try diagram(keyword + sample)
            XCTAssertEqual(read.nodes.count, 19)
            XCTAssertEqual(read.links.count, 16)
            let names = Set(read.nodes.map(\.name))
            XCTAssertTrue(names.isSuperset(of: ["Agricultural 'waste'", "Heating and cooling - homes", "Heating and cooling - commercial",
                                                "Over generation / exports", "Lighting & appliances - commercial", "Lighting & appliances - homes"]))
        }
    }

    // MARK: Mermaid's documentation and its rules

    func testEveryDocumentationExampleReadsWithItsFrontMatter() throws {
        let examples = try SankeyCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 8)
        XCTAssertEqual(try examples.map { example in try diagram(example).links.count }, [68, 3, 3, 2, 2, 3, 3, 3])
        let quoted = try diagram(examples[4])
        XCTAssertEqual(quoted.nodes.map(\.name), ["Pumped heat", "Heating and cooling, \"homes\"", "Heating and cooling, \"commercial\""])
    }

    func testTheTitleIsTheFrontMattersOnly() throws {
        XCTAssertEqual(try diagram("---\ntitle: Energy\n---\nsankey\na,b,1").title, "Energy")
        XCTAssertNil(try diagram("sankey\na,b,1").title)
    }

    func testValuesAreReadAsParseFloatReadsThem() throws {
        let read = try diagram("sankey\na,b,12 kg\na,c,abc\na,d,\"1,5\"\na,e,1e3")
        XCTAssertEqual(read.links.map(\.value), [12, nil, 1, 1000])
    }

    func testACommentLineTakesTheBlankLinesBeforeItAndBlankLinesAreLeft() throws {
        let read = try diagram("sankey-beta\r\n\r\na,b,1\n   \n%% a comment\n\n\nb,c,2\n  %% indented\nc,d,3\n\n   ")
        XCTAssertEqual(SankeyReading.rows(read), ["a → b: 1.0", "b → c: 2.0", "c → d: 3.0"])
    }

    // MARK: Errors

    func testARowWithoutItsThreeFieldsIsAnErrorOnItsLine() {
        XCTAssertEqual(SankeyReading.readError("sankey-beta\na,b,1\n%% skipped\nc,d\n"), .invalidSyntax(line: 4, problem: .expectedSankeyFields))
        XCTAssertEqual(SankeyReading.readError("sankey\na,b,1\n   \nc,d,2"), .invalidSyntax(line: 3, problem: .expectedSankeyFields),
                       "A line of spaces between rows is a row without fields, as in Mermaid")
        XCTAssertEqual(SankeyReading.readError("sankey\n\"\",b,1"), .invalidSyntax(line: 2, problem: .expectedSankeyFields), "An empty quoted field")
        XCTAssertEqual(SankeyReading.readError("sankey"), .invalidSyntax(line: 1, problem: .expectedSankeyFields), "No row")
    }

    func testTextTheGrammarDoesNotReadIsShown() {
        XCTAssertEqual(SankeyReading.readError("sankey-beta  \na,b,1"), .invalidSyntax(line: 1, problem: .unexpectedText("  ")))
        XCTAssertEqual(SankeyReading.readError("sankey\na,b,1,extra"), .invalidSyntax(line: 2, problem: .unexpectedText(",extra")))
        XCTAssertEqual(SankeyReading.readError("sankey\na\tb,c,1"), .invalidSyntax(line: 2, problem: .unexpectedText("\tb,c,1")), "A tab is no text")
        XCTAssertEqual(SankeyReading.readError("sankey\n#1;,b,1"), .invalidSyntax(line: 2, problem: .unexpectedText("#1;,b,1")),
                       "A control character by its entity code")
    }

    func testAnUnclosedQuotationIsAnErrorWhereItOpens() {
        XCTAssertEqual(SankeyReading.readError("sankey\na,b,1\n\"c,d,2\ne,f,3"), .invalidSyntax(line: 3, problem: .unclosedQuotation))
    }

    func testNodesAndLinksAreBounded() {
        let limits = MermaidDiagramLimits(maximumSourceBytes: 50_000, maximumNodeCount: 3, maximumEdgeCount: 2, maximumLayoutPointCount: 100)
        XCTAssertNil(SankeyReading.readError("sankey\na,b,1\nb,c,1", limits: limits))
        XCTAssertEqual(SankeyReading.readError("sankey\na,b,1\nc,d,1", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertEqual(SankeyReading.readError("sankey\na,b,1\nb,c,1\nc,a,1", limits: limits), .tooManyEdges(limit: 2))
    }
}
