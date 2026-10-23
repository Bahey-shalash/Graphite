import XCTest
import MermaidDiagrams
@testable import GraphiteUI

/// Live Preview prepares a ```` ```mermaid ```` block as the reading view does (`ReadingDiagram`): the diagram of a type
/// drawn natively, laid out in the note's text font and size; the source and why for one that cannot be read; code for a
/// type not drawn natively yet.
final class LivePreviewDiagramPreparationTests: XCTestCase {
    private let font = DiagramFont(postScriptName: nil, size: 20)

    private func content(_ source: String) -> LivePreviewDiagramContent {
        LivePreviewDiagramPreparation.content(of: LivePreviewDiagramRequest(source: source, font: font))
    }

    func testAFlowchartIsLaidOutInTheRequestedFontAndSize() {
        guard case .diagram(.flowchart(let flowchart)) = content("flowchart LR\n  A[Start] --> B{Done?}") else { return XCTFail("The flowchart is drawn") }
        XCTAssertEqual(flowchart.layout.font, font)
        XCTAssertEqual(flowchart.nodeTexts, ["Start", "Done?"])
    }

    /// Every type the reading view draws is drawn. The Gantt chart is laid out on the moment it is built (`WallClock`),
    /// which a test does not read; the reading view's tests give it one.
    func testEveryTypeTheReadingViewDrawsIsDrawn() {
        let sources = [
            "flowchart TD\n  A --> B", "sequenceDiagram\n  Alice->>Bob: Hello", "classDiagram\n  Animal <|-- Duck",
            "stateDiagram-v2\n  [*] --> Still\n  Still --> [*]", "erDiagram\n  CUSTOMER ||--o{ ORDER : places", "pie\n  \"Dogs\" : 3\n  \"Cats\" : 2",
            "mindmap\n  root\n    branch", "timeline\n  2004 : Facebook",
        ]
        for source in sources {
            guard case .diagram(let diagram) = content(source) else {
                XCTFail("Drawn natively: \(source)")
                continue
            }
            if case .unreadable(_, let failure) = diagram { XCTFail("Read and laid out: \(source), \(failure)") }
        }
    }

    func testADiagramThatCannotBeReadShowsItsSourceAndWhy() {
        let source = "flowchart TD\nA[never closed"
        guard case .diagram(.unreadable(let shownSource, let failure)) = content(source) else { return XCTFail("Shown with why") }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedShape(closingText: "]"))))
    }

    func testATypeNotDrawnNativelyStaysCode() {
        guard case .code = content("requirementDiagram\n  requirement test_req {\n  }") else { return XCTFail("A requirement diagram is shown as code") }
        guard case .code = content("flowchart TD\nsubgraph one\nA --> B\nend\none@{ view: collapsed }") else {
            return XCTFail("A flowchart holding a collapsed group is shown as code")
        }
    }

    /// The preparation says which code and font it was made for, so a view drawing it knows whether it is current.
    func testAPreparationIsForTheRequestItWasMadeFor() async {
        let request = LivePreviewDiagramRequest(source: "pie\n  \"A\" : 1", font: font)
        let preparation = await LivePreviewDiagramPreparation.prepared(for: request)
        XCTAssertEqual(preparation.request, request)
        guard case .diagram(.pieChart(let chart)) = preparation.content else { return XCTFail("The pie chart is drawn") }
        XCTAssertEqual(chart.layout.slices.count, 1)
    }

    /// A diagram is laid out in the note's text font and size, as the reading view lays it out.
    func testTheRequestTakesTheNotesTextSizeAndFont() {
        // The vault's folder is never read here.
        let environment = LivePreviewEnvironment(root: URL(fileURLWithPath: "/Vault", isDirectory: true), textSize: 19, colorsEnabled: true, paletteHexByName: [:],
                                                 drawingVersion: 0, resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil)
        let request = LivePreviewDiagramRequest(source: "pie", environment: environment)
        XCTAssertEqual(request.font, DiagramFont(postScriptName: NoteTypography.standard.diagramFontPostScriptName, size: 19))
        XCTAssertEqual(request.source, "pie")
    }
}
