#if canImport(UIKit)
import XCTest
import PencilKit
import UIKit
@testable import GraphiteApple

/// The color saved for a Pencil stroke: how it looks on white paper in light appearance,
/// in sRGB, with wide-gamut components limited to 0...1, whatever the viewer's appearance.
final class PencilStrokeSamplerColorTests: XCTestCase {
    private func stroke(color: UIColor, opacity: CGFloat = 1) -> PKStroke {
        let controlPoints = (0...3).map { step in
            PKStrokePoint(location: CGPoint(x: 10 + CGFloat(step) * 10, y: 20), timeOffset: TimeInterval(step) / 10,
                          size: CGSize(width: 3, height: 3), opacity: opacity, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: controlPoints, creationDate: Date(timeIntervalSince1970: 100)))
    }

    func testADynamicColorIsSavedAsItsLightVariantEvenWhileTheAppIsInDarkAppearance() {
        let dynamicColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 1, green: 1, blue: 1, alpha: 1) : UIColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        }
        let inkStroke = stroke(color: dynamicColor)
        var savedInDark: VectorInkColor?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent { savedInDark = PencilStrokeSampler.color(of: inkStroke) }
        let savedInLight = PencilStrokeSampler.color(of: inkStroke)
        let expected = VectorInkColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        for saved in [savedInLight, savedInDark] {
            XCTAssertEqual(saved?.red ?? -1, expected.red, accuracy: 0.002)
            XCTAssertEqual(saved?.green ?? -1, expected.green, accuracy: 0.002)
            XCTAssertEqual(saved?.blue ?? -1, expected.blue, accuracy: 0.002)
            XCTAssertEqual(saved?.alpha ?? -1, 1, accuracy: 0.002)
        }
    }

    func testAWideGamutColorIsClampedIntoSRGB() throws {
        let saturatedP3Green = UIColor(displayP3Red: 0, green: 1, blue: 0, alpha: 1)
        let color = PencilStrokeSampler.color(of: stroke(color: saturatedP3Green))
        for component in [color.red, color.green, color.blue, color.alpha] {
            XCTAssertGreaterThanOrEqual(component, 0)
            XCTAssertLessThanOrEqual(component, 1)
        }
        XCTAssertEqual(color.green, 1, accuracy: 0.002)
        XCTAssertEqual(color.red, 0, "A component below sRGB's range is limited to 0.")
    }

    func testTheStrokesOpacityIsTheAverageOfItsPointsTimesTheColorsAlpha() {
        let color = PencilStrokeSampler.color(of: stroke(color: UIColor(red: 0, green: 0, blue: 0, alpha: 0.5), opacity: 0.5))
        XCTAssertEqual(color.alpha, 0.25, accuracy: 0.01)
    }
}
#endif
