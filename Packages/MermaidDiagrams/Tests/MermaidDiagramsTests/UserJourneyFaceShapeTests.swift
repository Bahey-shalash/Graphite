import XCTest
@testable import MermaidDiagrams

/// Pele's faces: a circle, two eyes, and a mouth whose shape follows the mood, measured from the face's center.
final class UserJourneyFaceShapeTests: XCTestCase {
    private func mouth(_ mood: UserJourneyMood) -> CGRect {
        let mouths = CGMutablePath()
        UserJourneyFaceShape.add(mood, at: CGPoint(x: 100, y: 100), circles: CGMutablePath(), eyes: CGMutablePath(), mouths: mouths)
        return mouths.boundingBoxOfPath
    }

    func testASmileDipsBelowItsCornersAndAFrownRisesAboveThem() {
        let rise = (36.0 - 25.0).squareRoot()
        let smile = mouth(.happy)
        XCTAssertEqual(smile.minX, 95, accuracy: 0.001)
        XCTAssertEqual(smile.maxX, 105, accuracy: 0.001)
        XCTAssertEqual(smile.minY, 102, accuracy: 0.001)
        XCTAssertEqual(smile.maxY, 102 - rise + 6, accuracy: 0.001)
        let frown = mouth(.sad)
        XCTAssertEqual(frown.minY, 106.5 + rise - 6, accuracy: 0.001)
        XCTAssertEqual(frown.maxY, 106.5, accuracy: 0.001)
        XCTAssertEqual(frown.width, 10, accuracy: 0.001)
    }

    func testANeutralMouthIsStraight() {
        XCTAssertEqual(mouth(.neutral), CGRect(x: 95.5, y: 104.5, width: 9, height: 0))
    }

    func testTheCircleAndEyesSurroundTheCenter() {
        let circles = CGMutablePath()
        let eyes = CGMutablePath()
        UserJourneyFaceShape.add(.happy, at: CGPoint(x: 50, y: 40), circles: circles, eyes: eyes, mouths: CGMutablePath())
        XCTAssertEqual(circles.boundingBoxOfPath, CGRect(x: 39, y: 29, width: 22, height: 22))
        XCTAssertEqual(eyes.boundingBoxOfPath.minX, 50 - 3.6 - 1.3, accuracy: 0.001)
        XCTAssertEqual(eyes.boundingBoxOfPath.maxX, 50 + 3.6 + 1.3, accuracy: 0.001)
        XCTAssertEqual(eyes.boundingBoxOfPath.midY, 40 - 2.8, accuracy: 0.001)
    }
}
