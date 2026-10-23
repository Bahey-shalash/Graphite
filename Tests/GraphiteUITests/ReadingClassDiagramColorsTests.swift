import XCTest
import SwiftUI
@testable import GraphiteUI

final class ReadingClassDiagramColorsTests: XCTestCase {
    private func redComponent(_ color: Color) -> CGFloat {
        let resolved = color.resolve(in: EnvironmentValues()).cgColor
        let standard = CGColorSpace(name: CGColorSpace.sRGB).flatMap { space in resolved.converted(to: space, intent: .defaultIntent, options: nil) }
        return (standard?.components?.first ?? 0) * 255
    }

    func testOnPelesPageAndTextTheMutedTextAndNotesTakePelesColors() {
        let colors = ReadingClassDiagramColors(diagram: ReadingDiagramColors(background: Color(.sRGB, red: 1, green: 1, blue: 1),
                                                                             foreground: Color(.sRGB, red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255)))
        XCTAssertEqual(redComponent(colors.muted), 0x6E, accuracy: 1.5)
        XCTAssertEqual(redComponent(colors.noteSurface), 0xE6, accuracy: 1.5)
    }

    func testTheyFollowADarkPage() {
        let colors = ReadingClassDiagramColors(diagram: ReadingDiagramColors(background: Color(.sRGB, red: 0, green: 0, blue: 0),
                                                                             foreground: Color(.sRGB, red: 1, green: 1, blue: 1)))
        XCTAssertGreaterThan(redComponent(colors.muted), redComponent(colors.noteSurface))
        XCTAssertGreaterThan(redComponent(colors.noteSurface), redComponent(colors.diagram.surface))
    }
}
