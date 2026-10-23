import XCTest
import SwiftUI
@testable import GraphiteUI

final class ReadingDiagramColorsTests: XCTestCase {
    private func redComponent(_ color: Color) -> CGFloat {
        let resolved = color.resolve(in: EnvironmentValues()).cgColor
        let standard = resolved.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        return (standard?.components?.first ?? 0) * 255
    }

    func testOnPelesPageAndTextTheShapesTakePelesColors() {
        let colors = ReadingDiagramColors(background: Color(.sRGB, red: 1, green: 1, blue: 1),
                                          foreground: Color(.sRGB, red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255))
        XCTAssertEqual(redComponent(colors.surface), 0xF3, accuracy: 1)
        XCTAssertEqual(redComponent(colors.border), 0x8A, accuracy: 1.5)
        XCTAssertEqual(redComponent(colors.alternateSurface), 0xE6, accuracy: 1)
        XCTAssertEqual(redComponent(colors.muted), 0x6E, accuracy: 1.5)
    }

    func testTheShapesFollowADarkPage() {
        let colors = ReadingDiagramColors(background: Color(.sRGB, red: 0, green: 0, blue: 0), foreground: Color(.sRGB, red: 1, green: 1, blue: 1))
        XCTAssertEqual(redComponent(colors.surface), 255 * 0.054, accuracy: 1)
        XCTAssertGreaterThan(redComponent(colors.border), redComponent(colors.surface))
    }
}
