import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's Git graph documentation examples, all read, those without options laid out, and the benchmark's
/// generated histories.
final class GitGraphCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsReadAndThoseWithoutOptionsAreDrawn() throws {
        let examples = try GitGraphCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 35)
        var drawnCount = 0
        for example in examples {
            let diagram = try GitGraphReading.gitGraph(example)
            do {
                let layout = try GitGraphLayoutEngine.layout(diagram, typography: typography)
                XCTAssertEqual(layout.commits.count, diagram.commits.count)
                XCTAssertEqual(layout.lanes.count, diagram.branches.count)
                drawnCount += 1
            } catch {
                XCTAssertEqual(error, .optionsNotApplied)
                XCTAssertTrue(diagram.setsGitGraphOptions)
            }
        }
        XCTAssertEqual(drawnCount, 26, "The nine examples that set gitGraph options in their front matter stay code")
    }

    func testTheGeneratedHistoriesAreDrawnWithoutTwoCommitsInOnePlace() throws {
        let diagram = try GitGraphReading.gitGraph(GitGraphCorpus.generated(branchCount: 10))
        XCTAssertEqual(diagram.branches.count, 11)
        XCTAssertEqual(diagram.commits.count, 1 + 10 * (3 + 2))
        let layout = try GitGraphLayoutEngine.layout(diagram, typography: typography)
        let dotDiameter = 2 * GitGraphGeometry.dotRadius
        for (index, commit) in layout.commits.enumerated() {
            for other in layout.commits[(index + 1)...] {
                XCTAssertGreaterThanOrEqual(hypot(commit.center.x - other.center.x, commit.center.y - other.center.y), dotDiameter)
            }
        }
        XCTAssertEqual(layout.connectors.filter { connector in connector.style == .acrossLanes }.count, 20)
    }
}
