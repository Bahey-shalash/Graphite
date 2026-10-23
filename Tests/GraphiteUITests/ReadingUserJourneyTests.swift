import XCTest
import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI
import GraphiteTestSupport

/// A ```mermaid block holding a user journey: read and laid out with the note's other blocks, off the main actor, in
/// the note's text size; one that cannot be read keeps its source and says why.
final class ReadingUserJourneyTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAUserJourney: Error {}

    private func journey(_ source: String) throws -> ReadingUserJourney {
        guard case .userJourney(let journey) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAUserJourney() }
        return journey
    }

    func testAUserJourneyIsLaidOutInTheNotesTextSize() throws {
        let journey = try journey("journey\n  title My working day\n  section Go to work\n    Make tea: 5: Me\n    Do work: 1: Me, Cat\n    Rest: x")
        XCTAssertEqual(journey.layout.font.size, 17)
        XCTAssertEqual(journey.layout.tasks.count, 3)
        XCTAssertEqual(journey.taskTexts, ["Make tea: 5 (Me)", "Do work: 1 (Me, Cat)", "Rest"])
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try journey("journey\n  title My day\n  accDescr: How the day felt\n  a: 3.5")
        XCTAssertEqual(titled.title, "My day")
        XCTAssertEqual(titled.description, "How the day felt")
        XCTAssertEqual(titled.taskTexts, ["a: 3.5"])
        XCTAssertEqual(try journey("journey\n  accTitle: Named\n  title Shown\n  a: 9").title, "Named")
        XCTAssertEqual(try journey("journey\n  a: 9").taskTexts, ["a: 5"], "The level the face shows")
    }

    func testAUserJourneyThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "journey\n  A task"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .expectedTaskScore)))
    }

    func testTheUserJourneysProblemIsExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.unexpectedText("C"), .unclosedAccessibilityDescription, .expectedTaskData, .eventWithoutPeriod,
                                                .expectedSliceValue, .expectedTaskScore]
        XCTAssertEqual(Set(problems.map(\.explanation)).count, problems.count)
    }

    func testTheReadingViewBuildsAUserJourneyBlockBetweenTheTextAroundIt() async throws {
        let vault = try TemporaryVault.make(prefix: "UserJourneyVault", for: self).root
        defer { try? FileManager.default.removeItem(at: vault) } // Best-effort removal of a temporary folder.
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let blocks = try await ReadingViewBuilder().build(source: "Before\n\n```mermaid\njourney\n  Make tea: 5: Me\n```\n\nAfter",
                                                           note: try VaultPath("Note.md"), root: vault, index: index,
                                                           configuration: ReadingConfiguration()).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, .userJourney(let journey)) = blocks[1] else { return XCTFail("The user journey is drawn") }
        XCTAssertEqual(journey.layout.legend.count, 1)
    }
}
