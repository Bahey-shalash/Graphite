import XCTest
@testable import MermaidDiagrams

final class MermaidDiagramReaderTests: XCTestCase {
    private func flowchart(_ source: String) throws -> FlowchartDiagram {
        try FlowchartReading.flowchart(source)
    }

    private func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        FlowchartReading.readError(source, limits: limits)
    }

    func testFlowchartGraphAndElkKeywordsAllReadAFlowchart() throws {
        for keyword in ["flowchart", "graph", "flowchart-elk"] {
            XCTAssertEqual(try flowchart("\(keyword) LR\n  A --> B").nodes.count, 2, keyword)
        }
    }

    func testOtherDiagramTypesAreNamedByTheirKeyword() {
        XCTAssertEqual(readError("sequenceDiagram\n  Alice->>Bob: Hi"), .unsupportedDiagramType(keyword: "sequenceDiagram"))
        XCTAssertEqual(readError("stateDiagram-v2\n  [*] --> Still"), .unsupportedDiagramType(keyword: "stateDiagram-v2"))
        XCTAssertEqual(readError("journey\n  title My working day"), .unsupportedDiagramType(keyword: "journey"))
    }

    func testTextWithoutADiagramIsNoDiagram() {
        XCTAssertEqual(readError(""), .noDiagram)
        XCTAssertEqual(readError("  \n\n"), .noDiagram)
        XCTAssertEqual(readError("%% only a comment\n%%{init: {\"theme\": \"dark\"}}%%\n"), .noDiagram)
    }

    func testCommentsDirectivesAndABlankStartComeBeforeTheKeyword() throws {
        let diagram = try flowchart("\n%%{init: {\"flowchart\": {\"curve\": \"linear\"}}}%%\n%% a comment\n\ngraph TD\nA-->B")
        XCTAssertEqual(diagram.edges.count, 1)
    }

    func testFrontMatterGivesTheTitle() throws {
        let diagram = try flowchart("---\ntitle: \"Order flow\"\nconfig:\n  theme: forest\n---\nflowchart LR\n  A --> B")
        XCTAssertEqual(diagram.title, "Order flow")
        XCTAssertEqual(diagram.direction, .leftToRight)
    }

    func testUnclosedFrontMatterIsReportedOnItsFirstLine() {
        XCTAssertEqual(readError("---\ntitle: Lost\nflowchart LR\n  A --> B"), .invalidSyntax(line: 1, problem: .unclosedFrontMatter))
    }

    func testAByteOrderMarkIsSkipped() throws {
        XCTAssertEqual(try flowchart("\u{FEFF}graph TD\nA-->B").edges.count, 1)
    }

    func testTextOverTheSizeLimitIsRefusedBeforeReading() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = 10
        XCTAssertEqual(readError("graph TD\nA-->B", limits: limits), .sourceTooLarge(limitBytes: 10))
    }

    func testTextThatStartsWithNoKeywordIsUnexpected() {
        XCTAssertEqual(readError("--> graph"), .invalidSyntax(line: 1, problem: .unexpectedText("--> graph")))
    }
}
