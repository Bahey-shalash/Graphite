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

    func testOnlyHighlighterStrokesAndUsableWidthsAreChanged() {
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(ink: PKInk(.pen, color: .black)), width: 18))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(), width: 0))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(), width: .nan))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(transform: CGAffineTransform(scaleX: 0, y: 0)), width: 18))
    }
}
#endif
