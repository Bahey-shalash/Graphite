import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's class diagram documentation examples, all read and laid out, so that none crashes and each that is not
/// drawn says why.
final class ClassDiagramCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsReadAndDrawnOrRefusedForItsNamespaces() throws {
        let examples = try ClassDiagramCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 38)
        var drawnCount = 0
        var refusals: [ClassDiagramLayoutError] = []
        for example in examples {
            let diagram = try ClassDiagramReading.classDiagram(example)
            do {
                let layout = try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)
                XCTAssertEqual(layout.classes.count, diagram.classes.count)
                let boxes = layout.classes.map(\.frame).reduce(CGRect.null) { bounds, frame in bounds.union(frame) }
                XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(boxes))
                drawnCount += 1
            } catch let error as ClassDiagramLayoutError {
                refusals.append(error)
            }
        }
        // The five examples with namespaces are not laid out yet; the count only rises.
        XCTAssertEqual(drawnCount, 33)
        XCTAssertEqual(refusals, Array(repeating: .namespacesNotLaidOut, count: 5))
    }

    func testPelesFourClassDiagramAndTheGeneratedHierarchiesAreDrawnWithoutOverlap() throws {
        for source in [ClassDiagramCorpus.fourClassDiagram, ClassDiagramCorpus.hierarchy(classCount: 50), ClassDiagramCorpus.hierarchy(classCount: 200)] {
            let diagram = try ClassDiagramReading.classDiagram(source)
            let layout = try ClassDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            XCTAssertEqual(layout.classes.count, diagram.classes.count)
            XCTAssertEqual(layout.relations.count, diagram.relations.count)
            for (index, box) in layout.classes.enumerated() {
                for other in layout.classes[(index + 1)...] { XCTAssertFalse(box.frame.intersects(other.frame)) }
            }
        }
    }
}
