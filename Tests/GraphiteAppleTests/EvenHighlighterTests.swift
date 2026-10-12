#if canImport(UIKit)
import XCTest
import PencilKit
@testable import GraphiteApple

final class EvenHighlighterTests: XCTestCase {
    /// A highlighter stroke as a tilted, turning Pencil draws it: each point's tip a
    /// different size, angle and pressure.
    private func tiltedStroke(ink: PKInk = PKInk(.marker, color: .systemYellow), transform: CGAffineTransform = .identity) -> PKStroke {
        let controlPoints = (0...12).map { step in
            let fraction = CGFloat(step) / 12
            return PKStrokePoint(location: CGPoint(x: 40 + 300 * fraction, y: 200), timeOffset: TimeInterval(fraction),
                                 size: CGSize(width: 10 + 30 * fraction, height: 6 + 12 * fraction), opacity: 1, force: 0.4 + fraction,
                                 azimuth: fraction * .pi, altitude: .pi / 6 + fraction)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 1)),
                        transform: transform, mask: nil)
    }

    func testEveryPointTakesOneUprightTipAlongTheSameLine() throws {
        let stroke = tiltedStroke()
        let evenStroke = try XCTUnwrap(EvenHighlighter.evenStroke(stroke, width: 18))
        let originalPoints = Array(stroke.path), evenPoints = Array(evenStroke.path)
        XCTAssertEqual(evenPoints.count, originalPoints.count)
        XCTAssertEqual(evenPoints.map(\.location), originalPoints.map(\.location))
        XCTAssertEqual(evenPoints.map(\.timeOffset), originalPoints.map(\.timeOffset))
        for point in evenPoints {
            XCTAssertEqual(point.size.width, 18 / EvenHighlighter.chiselLengthPerPointSize, accuracy: 0.001)
            XCTAssertEqual(point.size.height, 18 / EvenHighlighter.chiselLengthPerPointSize, accuracy: 0.001)
            XCTAssertEqual(point.azimuth, EvenHighlighter.tipAzimuth, accuracy: 0.001)
            XCTAssertEqual(point.altitude, EvenHighlighter.uprightAltitude, accuracy: 0.001)
            XCTAssertEqual(point.force, evenPoints[0].force, accuracy: 0.001)
            XCTAssertEqual(point.opacity, EvenHighlighter.tipOpacity, accuracy: 0.001, "One opacity, however fast the stroke was drawn.")
        }
        XCTAssertEqual(evenStroke.ink.inkType, .marker)
        XCTAssertEqual(evenStroke.path.creationDate, stroke.path.creationDate)
        XCTAssertEqual(evenStroke.randomSeed, stroke.randomSeed)
    }

    func testWidthIsInTheDrawingsPointsUnderAScaledStroke() throws {
        let evenStroke = try XCTUnwrap(EvenHighlighter.evenStroke(tiltedStroke(transform: CGAffineTransform(scaleX: 2, y: 2)), width: 18))
        XCTAssertEqual(Array(evenStroke.path).first?.size.width ?? 0, 9 / EvenHighlighter.chiselLengthPerPointSize, accuracy: 0.001)
        XCTAssertEqual(evenStroke.transform, CGAffineTransform(scaleX: 2, y: 2))
    }

    /// What PencilKit draws, not only the points: a highlight across a line of text is as
    /// tall as the tool is wide, as tall as an upright Pencil or a finger draws it, so it does
    /// not change at the lift; and the same at any tilt.
    func testAHighlightAcrossALineIsAsTallAsTheToolIsWideAndAsAnUprightStroke() throws {
        let toolWidth: CGFloat = 57
        func horizontalStroke(size: CGFloat, azimuth: CGFloat, altitude: CGFloat) -> PKStroke {
            let controlPoints = (0...8).map { step in
                PKStrokePoint(location: CGPoint(x: 100 + 25 * CGFloat(step), y: 300), timeOffset: TimeInterval(step) * 0.016,
                              size: CGSize(width: size, height: size), opacity: 1, force: 1, azimuth: azimuth, altitude: altitude)
            }
            return PKStroke(ink: PKInk(.marker, color: .systemYellow), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date()))
        }
        // As PencilKit records a finger's stroke with this tool: two thirds of its width, upright.
        let uprightStroke = horizontalStroke(size: toolWidth * 2 / 3, azimuth: .pi / 2, altitude: .pi / 2)
        let tiltedStroke = horizontalStroke(size: toolWidth * 1.4, azimuth: 0.3, altitude: .pi / 5)
        let evenFromUpright = try XCTUnwrap(EvenHighlighter.evenStroke(uprightStroke, width: toolWidth))
        let evenFromTilted = try XCTUnwrap(EvenHighlighter.evenStroke(tiltedStroke, width: toolWidth))
        XCTAssertEqual(evenFromUpright.renderBounds.height, toolWidth, accuracy: 3)
        XCTAssertEqual(evenFromUpright.renderBounds.height, uprightStroke.renderBounds.height, accuracy: 1)
        XCTAssertEqual(evenFromUpright.renderBounds.width, uprightStroke.renderBounds.width, accuracy: 1, "No longer or shorter either.")
        XCTAssertEqual(evenFromTilted.renderBounds.size.height, evenFromUpright.renderBounds.size.height, accuracy: 0.5)
        XCTAssertNotEqual(tiltedStroke.renderBounds.height, uprightStroke.renderBounds.height, accuracy: 3, "The tilt changed the stroke as drawn.")
    }

    /// The tip turns with the stroke, so the band is as wide in every direction.
    func testTheTipTurnsAcrossTheStrokeInEveryDirection() throws {
        func line(to end: CGPoint) -> [CGPoint] { (0...10).map { step in CGPoint(x: end.x * CGFloat(step) / 10, y: end.y * CGFloat(step) / 10) } }
        let alongTheRows = EvenHighlighter.tipAzimuths(along: line(to: CGPoint(x: 200, y: 0)), reach: 10)
        let down = EvenHighlighter.tipAzimuths(along: line(to: CGPoint(x: 0, y: 200)), reach: 10)
        let diagonal = EvenHighlighter.tipAzimuths(along: line(to: CGPoint(x: 200, y: 200)), reach: 10)
        for azimuth in alongTheRows { XCTAssertEqual(azimuth, .pi / 2, accuracy: 0.001) }
        for azimuth in down { XCTAssertEqual(azimuth, .pi, accuracy: 0.001) }
        for azimuth in diagonal { XCTAssertEqual(azimuth, .pi * 3 / 4, accuracy: 0.001) }
        XCTAssertEqual(EvenHighlighter.tipAzimuths(along: [CGPoint(x: 5, y: 5)], reach: 10), [EvenHighlighter.tipAzimuth], "A dot.")
        // A tremble shorter than the reach does not turn the tip.
        let trembling = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 2)] + line(to: CGPoint(x: 200, y: 0)).dropFirst()
        XCTAssertEqual(EvenHighlighter.tipAzimuths(along: trembling, reach: 10).last ?? 0, .pi / 2, accuracy: 0.001)

        func renderedArea(of stroke: PKStroke) -> CGFloat { stroke.renderBounds.width * stroke.renderBounds.height }
        let marker = PKInk(.marker, color: .systemYellow)
        func stroke(through points: [CGPoint]) -> PKStroke {
            PKStroke(ink: marker, path: PKStrokePath(controlPoints: points.enumerated().map { pointIndex, location in
                PKStrokePoint(location: location, timeOffset: TimeInterval(pointIndex) * 0.016, size: CGSize(width: 10, height: 10), opacity: 1,
                              force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date()))
        }
        let horizontalBand = try XCTUnwrap(EvenHighlighter.evenStroke(stroke(through: line(to: CGPoint(x: 200, y: 0))), width: 24)).renderBounds
        let verticalBand = try XCTUnwrap(EvenHighlighter.evenStroke(stroke(through: line(to: CGPoint(x: 0, y: 200))), width: 24)).renderBounds
        XCTAssertEqual(horizontalBand.height, verticalBand.width, accuracy: 1, "As wide down the page as across it.")
        XCTAssertEqual(horizontalBand.width, verticalBand.height, accuracy: 1)
    }

    /// While the even highlighter is in use, the canvas draws with an invisible tool of the
    /// same kind and width; its stroke takes the highlighter's ink when it becomes even.
    func testTheStandInDrawsNothingAndItsStrokeTakesTheHighlightersInk() throws {
        let highlighter = PKInkingTool(.marker, color: UIColor.systemYellow.withAlphaComponent(0.8), width: 30)
        let standIn = EvenHighlighter.invisibleStandIn(for: highlighter)
        XCTAssertEqual(standIn.inkType, .marker)
        XCTAssertEqual(standIn.width, highlighter.width, accuracy: 0.001)
        XCTAssertEqual(standIn.color.cgColor.alpha, 0)
        XCTAssertTrue(EvenHighlighter.isInvisible(standIn.ink))
        XCTAssertFalse(EvenHighlighter.isInvisible(highlighter.ink))
        XCTAssertFalse(EvenHighlighter.isInvisible(PKInk(.pen, color: .clear)), "Only the highlighter's stand-in.")
        let drawnWithStandIn = tiltedStroke(ink: standIn.ink)
        let evenStroke = try XCTUnwrap(EvenHighlighter.evenStroke(drawnWithStandIn, width: 30, ink: highlighter.ink))
        XCTAssertEqual(evenStroke.ink.color.cgColor.alpha, 0.8, accuracy: 0.001)
        XCTAssertFalse(EvenHighlighter.isInvisible(evenStroke.ink))
    }

    /// The band the canvas shows while the stand-in draws reaches as far as the even stroke.
    func testTheBandReachesPastTheStrokesEndsAsTheEvenStrokeDoes() throws {
        let points = (0...8).map { step in CGPoint(x: 100 + 25 * CGFloat(step), y: 300) }
        let band = EvenHighlighter.bandPath(through: points, width: 24).boundingBoxOfPath
        let stroke = PKStroke(ink: PKInk(.marker, color: .systemYellow), path: PKStrokePath(controlPoints: points.enumerated().map { pointIndex, location in
            PKStrokePoint(location: location, timeOffset: TimeInterval(pointIndex) * 0.016, size: CGSize(width: 16, height: 16), opacity: 1, force: 1,
                          azimuth: .pi / 2, altitude: .pi / 2)
        }, creationDate: Date()))
        let evenBounds = try XCTUnwrap(EvenHighlighter.evenStroke(stroke, width: 24)).renderBounds
        XCTAssertEqual(band.minX, evenBounds.minX, accuracy: 4)
        XCTAssertEqual(band.maxX, evenBounds.maxX, accuracy: 4)
        let dot = EvenHighlighter.bandPath(through: [CGPoint(x: 50, y: 50)], width: 24).boundingBoxOfPath
        XCTAssertGreaterThan(dot.width, 0, "A dot's band has a length.")
        XCTAssertLessThan(EvenHighlighter.bandOpacity(forWidth: 8), EvenHighlighter.bandOpacity(forWidth: 50))
        XCTAssertEqual(EvenHighlighter.bandOpacity(forWidth: 2), EvenHighlighter.bandOpacity(forWidth: 8))
        XCTAssertLessThanOrEqual(EvenHighlighter.bandOpacity(forWidth: 200), 1)
    }

    func testOnlyHighlighterStrokesAndUsableWidthsAreChanged() {
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(ink: PKInk(.pen, color: .black)), width: 18))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(), width: 0))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(), width: .nan))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(transform: CGAffineTransform(scaleX: 0, y: 0)), width: 18))
    }
}
#endif
