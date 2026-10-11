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
            XCTAssertEqual(point.size.width, 18, accuracy: 0.001)
            XCTAssertEqual(point.size.height, 18, accuracy: 0.001)
            XCTAssertEqual(point.azimuth, EvenHighlighter.tipAzimuth, accuracy: 0.001)
            XCTAssertEqual(point.altitude, EvenHighlighter.uprightAltitude, accuracy: 0.001)
            XCTAssertEqual(point.force, evenPoints[0].force, accuracy: 0.001)
        }
        XCTAssertEqual(evenStroke.ink.inkType, .marker)
        XCTAssertEqual(evenStroke.path.creationDate, stroke.path.creationDate)
    }

    func testWidthIsInTheDrawingsPointsUnderAScaledStroke() throws {
        let evenStroke = try XCTUnwrap(EvenHighlighter.evenStroke(tiltedStroke(transform: CGAffineTransform(scaleX: 2, y: 2)), width: 18))
        XCTAssertEqual(Array(evenStroke.path).first?.size.width ?? 0, 9, accuracy: 0.001)
        XCTAssertEqual(evenStroke.transform, CGAffineTransform(scaleX: 2, y: 2))
    }

    func testOnlyHighlighterStrokesAndUsableWidthsAreChanged() {
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(ink: PKInk(.pen, color: .black)), width: 18))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(), width: 0))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(), width: .nan))
        XCTAssertNil(EvenHighlighter.evenStroke(tiltedStroke(transform: CGAffineTransform(scaleX: 0, y: 0)), width: 18))
    }
}
#endif
