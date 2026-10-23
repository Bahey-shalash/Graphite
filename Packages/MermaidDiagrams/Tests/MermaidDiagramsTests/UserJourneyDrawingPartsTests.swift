import XCTest
@testable import MermaidDiagrams

/// A laid-out user journey grouped by how it is painted.
final class UserJourneyDrawingPartsTests: XCTestCase {
    private func parts(_ source: String) throws -> (UserJourneyLayout, UserJourneyDrawingParts) {
        let layout = try UserJourneyReading.uniformLayout(source)
        return (layout, UserJourneyDrawingParts(layout: layout))
    }

    private func assertRectangle(_ rectangle: CGRect, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let corners = [expected.minX, expected.minY, expected.maxX, expected.maxY]
        for (value, expectedValue) in zip([rectangle.minX, rectangle.minY, rectangle.maxX, rectangle.maxY], corners) {
            XCTAssertEqual(value, expectedValue, accuracy: 0.001, file: file, line: line)
        }
    }

    func testCardsBandsFacesAndTheScaleEachHaveTheirPath() throws {
        let (layout, parts) = try parts("journey\n  title Day\n  section Work\n    Make tea: 5: Me\n    Do work: 1: Me, Cat\n  section Home\n    Sit: 3")
        assertRectangle(parts.cards.boundingBoxOfPath, equals: layout.tasks[0].frame.union(layout.tasks[2].frame))
        assertRectangle(parts.sectionBands.boundingBoxOfPath, equals: layout.sections[0].frame.union(layout.sections[1].frame))
        XCTAssertEqual(parts.faces.boundingBoxOfPath.minY, layout.tasks[0].faceCenter.y - 11, accuracy: 0.001)
        XCTAssertEqual(parts.faces.boundingBoxOfPath.maxY, layout.tasks[1].faceCenter.y + 11, accuracy: 0.001)
        XCTAssertEqual(parts.scaleLines.boundingBoxOfPath.height, 4 * 26, accuracy: 0.001)
        XCTAssertFalse(parts.scoreLine.isEmpty)
        XCTAssertFalse(parts.stems.isEmpty)
        XCTAssertEqual(parts.scaleTexts.map(\.lines), [["5"], ["4"], ["3"], ["2"], ["1"]])
        XCTAssertEqual(parts.sectionTexts.map(\.lines), [["Work"], ["Home"]])
        XCTAssertEqual(parts.taskTexts.map(\.lines), [["Make tea"], ["Do work"], ["Sit"]])
        XCTAssertEqual(parts.legendTexts.map(\.lines), [["Cat"], ["Me"]])
        XCTAssertEqual(parts.title?.lines, ["Day"])
    }

    func testDotsAreGroupedByTheirActorsSeriesColor() throws {
        let (layout, parts) = try parts("journey\n  a: 5: Me\n  b: 1: Me, Cat")
        XCTAssertEqual(parts.cardDotsBySeries.count, 2)
        let catDot = try XCTUnwrap(layout.tasks[1].actorDots.first { dot in dot.seriesIndex == 0 })
        assertRectangle(parts.cardDotsBySeries[0].boundingBoxOfPath, equals: catDot.center.square(halfSide: 5))
        XCTAssertEqual(parts.legendDotsBySeries[1].boundingBoxOfPath.midX, layout.legend[1].dot.center.x, accuracy: 0.001)
    }

    func testTheNinthActorTakesTheFirstColorAgain() throws {
        let (layout, parts) = try parts("journey\n  a: 3: " + (1...9).map { index in "p\(index)" }.joined(separator: ", "))
        XCTAssertEqual(parts.cardDotsBySeries.count, 8)
        XCTAssertEqual(parts.legendDotsBySeries.count, 8)
        let firstColor = parts.legendDotsBySeries[0].boundingBoxOfPath
        assertRectangle(firstColor, equals: layout.legend[0].dot.center.square(halfSide: 5).union(layout.legend[8].dot.center.square(halfSide: 5)))
    }

    func testOneTaskHasNoLineFromFaceToFaceAndAnEmptyJourneyNothing() throws {
        XCTAssertTrue(try parts("journey\n  alone: 3").1.scoreLine.isEmpty)
        let empty = try parts("journey").1
        XCTAssertTrue(empty.cards.isEmpty)
        XCTAssertTrue(empty.scaleLines.isEmpty)
        XCTAssertTrue(empty.cardDotsBySeries.isEmpty)
    }
}

private extension CGPoint {
    func square(halfSide: CGFloat) -> CGRect {
        CGRect(x: x - halfSide, y: y - halfSide, width: 2 * halfSide, height: 2 * halfSide)
    }
}
