import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's timeline documentation examples, all read and laid out, and the benchmark's generated timelines.
final class TimelineCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawn() throws {
        let examples = try TimelineCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 14)
        for example in examples {
            let diagram = try TimelineReading.timeline(example)
            let layout = TimelineLayoutEngine.layout(diagram, typography: typography)
            XCTAssertEqual(layout.periods.count, diagram.periods.count)
            XCTAssertNotNil(layout.axis)
            XCTAssertNotNil(layout.title)
        }
    }

    func testTheGeneratedTimelinesAreDrawnWithoutOverlap() throws {
        for isDown in [false, true] {
            let diagram = try TimelineReading.timeline(TimelineCorpus.generated(periodCount: 20, isDown: isDown))
            XCTAssertEqual(diagram.sections.count, 4)
            XCTAssertEqual(diagram.periods.map(\.events.count), Array(repeating: 2, count: 20))
            let layout = TimelineLayoutEngine.layout(diagram, typography: typography)
            let frames = layout.sections.map(\.frame) + layout.periods.flatMap { period in [period.frame] + period.events.map(\.frame) }
            for (index, frame) in frames.enumerated() {
                for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), "\(frame) and \(other)") }
            }
        }
    }
}
