import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's user journey documentation example, read and laid out, and the benchmark's generated journeys.
final class UserJourneyCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testTheDocumentationExampleIsDrawn() throws {
        let examples = try UserJourneyCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 1)
        let diagram = try UserJourneyReading.userJourney(try XCTUnwrap(examples.first))
        let layout = UserJourneyLayoutEngine.layout(diagram, typography: typography)
        XCTAssertEqual(layout.tasks.count, 5)
        XCTAssertEqual(layout.sections.count, 2)
        XCTAssertEqual(layout.legend.count, 2)
        XCTAssertNotNil(layout.title)
    }

    func testTheGeneratedJourneysAreDrawnWithoutOverlap() throws {
        let diagram = try UserJourneyReading.userJourney(UserJourneyCorpus.generated(taskCount: 20))
        XCTAssertEqual(diagram.sections.count, 4)
        XCTAssertEqual(diagram.actorNames.count, 5)
        let layout = UserJourneyLayoutEngine.layout(diagram, typography: typography)
        let frames = layout.sections.map(\.frame) + layout.tasks.map(\.frame)
            + layout.tasks.map { task in CGRect(x: task.faceCenter.x - 11, y: task.faceCenter.y - 11, width: 22, height: 22) }
            + layout.legend.map(\.text.frame)
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), "\(frame) and \(other)") }
        }
        XCTAssertTrue(frames.allSatisfy { frame in CGRect(origin: .zero, size: layout.size).contains(frame) })
    }
}
