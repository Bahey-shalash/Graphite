import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's 25 entity relationship documentation examples, as Pele's corpus collects them: every one is read.
final class EntityRelationshipCorpusTests: XCTestCase {
    func testEveryDocumentationExampleIsRead() throws {
        let examples = try EntityRelationshipCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 25)
        var entityCount = 0
        var relationshipCount = 0
        var subgraphExampleCount = 0
        for example in examples {
            let diagram = try EntityRelationshipReading.diagram(example)
            XCTAssertFalse(diagram.entities.isEmpty, example)
            entityCount += diagram.entities.count
            relationshipCount += diagram.relationships.count
            if diagram.subgraphCount > 0 { subgraphExampleCount += 1 }
        }
        XCTAssertEqual(subgraphExampleCount, 6)
        print("ENTITY-RELATIONSHIP-CORPUS read \(examples.count): \(entityCount) entities, \(relationshipCount) relationships")
    }

    func testEveryExampleWithoutSubgraphsIsLaidOutWithoutOverlapAndTheOthersAreRefused() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        var laidOutCount = 0
        var refusedCount = 0
        for example in try EntityRelationshipCorpus.documentationExamples() {
            do {
                let layout = try EntityRelationshipLayoutEngine.layout(EntityRelationshipReading.diagram(example), typography: typography, limits: .standard)
                for (index, entity) in layout.entities.enumerated() {
                    for other in layout.entities[(index + 1)...] { XCTAssertFalse(entity.frame.intersects(other.frame), example) }
                    XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(entity.frame), example)
                }
                laidOutCount += 1
            } catch let error as EntityRelationshipLayoutError {
                XCTAssertEqual(error, .subgraphsNotLaidOut)
                refusedCount += 1
            }
        }
        XCTAssertEqual(laidOutCount, 19)
        XCTAssertEqual(refusedCount, 6)
    }

    func testTheGeneratedSchemasAreLaidOutWithoutOverlap() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        for entityCount in [10, 100] {
            let diagram = try EntityRelationshipReading.diagram(EntityRelationshipCorpus.schema(entityCount: entityCount))
            XCTAssertEqual(diagram.entities.count, entityCount)
            let layout = try EntityRelationshipLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            XCTAssertEqual(layout.relationships.count, diagram.relationships.count)
            for (index, entity) in layout.entities.enumerated() {
                for other in layout.entities[(index + 1)...] { XCTAssertFalse(entity.frame.intersects(other.frame)) }
            }
        }
    }

    func testTheAttributesOfTheKeysExampleAreRead() throws {
        let examples = try EntityRelationshipCorpus.documentationExamples()
        let example = try XCTUnwrap(examples.first { example in example.contains("The license #") })
        let person = try XCTUnwrap(try EntityRelationshipReading.diagram(example).entities.first { entity in entity.identifier == "PERSON" })
        XCTAssertEqual(person.attributes.first, EntityRelationshipAttribute(type: "string", name: "driversLicense", keys: [.primary],
                                                                            comment: DiagramLabel("The license #")))
        XCTAssertEqual(person.attributes.map(\.type), ["string", "string(99)", "string", "string", "int"])
    }
}
