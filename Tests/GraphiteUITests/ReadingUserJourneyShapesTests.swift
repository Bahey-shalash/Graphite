import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingUserJourneyShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAUserJourney: Error {}

    private func journey(_ source: String) throws -> ReadingUserJourney {
        guard case .userJourney(let journey) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAUserJourney() }
        return journey
    }

    func testCardsFacesAndDotsKeepTheirOwnPaths() throws {
        let journey = try journey("journey\n  section Work\n    Make tea: 5: Me\n    Do work: 1: Me, Cat")
        let cardFrames = journey.layout.tasks.map(\.frame)
        XCTAssertEqual(journey.shapes.cards.boundingRect.minX, cardFrames[0].minX, accuracy: 0.001)
        XCTAssertEqual(journey.shapes.cards.boundingRect.maxX, cardFrames[1].maxX, accuracy: 0.001)
        XCTAssertEqual(journey.shapes.cardDotsBySeries.count, 2, "Cat and Me")
        XCTAssertEqual(journey.shapes.legendDotsBySeries.count, 2)
        for path in [journey.shapes.scaleLines, journey.shapes.stems, journey.shapes.scoreLine, journey.shapes.faces, journey.shapes.eyes,
                     journey.shapes.mouths, journey.shapes.sectionBands] {
            XCTAssertFalse(path.isEmpty)
        }
    }

    func testTextIsHeadingsInBoldThenCardsAndTheLegendAndTheTitleComesLast() throws {
        let journey = try journey("journey\n  title My day\n  section Work\n    Make tea: 5: Me")
        XCTAssertEqual(journey.shapes.textLines.map(\.text), ["Work", "Make tea", "Me", "My day"])
        XCTAssertEqual(journey.shapes.textLines.map(\.isBold), [true, false, false, true])
        XCTAssertEqual(journey.shapes.textLines[1].font.size, 14, "Cards are seven eighths of the text size")
        XCTAssertEqual(journey.shapes.scaleTextLines.map(\.text), ["5", "4", "3", "2", "1"])
        XCTAssertEqual(journey.shapes.scaleTextLines.first?.font.size, 12, "The scale is three quarters of the text size")
    }
}
