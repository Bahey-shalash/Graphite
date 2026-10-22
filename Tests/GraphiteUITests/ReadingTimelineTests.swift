import XCTest
import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI
import GraphiteTestSupport

/// A ```mermaid block holding a timeline: read and laid out with the note's other blocks, off the main actor, in the
/// note's text size; one that cannot be read keeps its source and says why.
final class ReadingTimelineTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsATimeline: Error {}

    private func timeline(_ source: String) throws -> ReadingTimeline {
        guard case .timeline(let timeline) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsATimeline() }
        return timeline
    }

    func testATimelineIsLaidOutInTheNotesTextSize() throws {
        let timeline = try timeline("timeline\n  2002 : LinkedIn\n  2004 : Facebook : Google")
        XCTAssertEqual(timeline.layout.font.size, 17)
        XCTAssertEqual(timeline.layout.periods.count, 2)
        XCTAssertEqual(timeline.periodTexts, ["2002: LinkedIn", "2004: Facebook, Google"])
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try timeline("timeline\n  title History\n  accDescr: Platforms by year\n  2002")
        XCTAssertEqual(titled.title, "History")
        XCTAssertEqual(titled.description, "Platforms by year")
        XCTAssertEqual(try timeline("timeline\n  accTitle: Named\n  title Shown\n  2002").title, "Named")
        XCTAssertEqual(try timeline("timeline\n  2002").periodTexts, ["2002"])
    }

    func testATimelineThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "timeline\n  : early"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .eventWithoutPeriod)))
    }

    func testTheTimelinesProblemIsExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.unknownDirection("XY"), .expectedNode, .unclosedShape(closingText: "]"), .unclosedQuotation,
                                                .unclosedEdgeLabel, .unclosedAttributes, .unclosedAccessibilityDescription, .unclosedFrontMatter,
                                                .endWithoutSubgraph, .unclosedSubgraph(identifier: "one"), .unexpectedText("C"),
                                                .secondRoot(text: "second"), .unclosedIcon, .eventWithoutPeriod]
        XCTAssertEqual(Set(problems.map(\.explanation)).count, problems.count)
    }

    func testTheReadingViewBuildsATimelineBlockBetweenTheTextAroundIt() async throws {
        let vault = try TemporaryVault.make(prefix: "TimelineVault", for: self).root
        defer { try? FileManager.default.removeItem(at: vault) } // Best-effort removal of a temporary folder.
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let blocks = try await ReadingViewBuilder().build(source: "Before\n\n```mermaid\ntimeline TD\n  2002 : LinkedIn\n```\n\nAfter",
                                                           note: try VaultPath("Note.md"), root: vault, index: index,
                                                           configuration: ReadingConfiguration()).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, .timeline(let timeline)) = blocks[1] else { return XCTFail("The timeline is drawn") }
        XCTAssertEqual(timeline.layout.direction, .topToBottom)
    }
}
