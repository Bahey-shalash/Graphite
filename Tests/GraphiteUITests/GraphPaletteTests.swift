import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The graph's colors against Graphite's accents, in light and dark appearance.
final class GraphPaletteTests: XCTestCase {
    /// The contrast WCAG asks of shapes against what is around them.
    private let shapeContrast = 3.0

    private func presetAccents() throws -> [(name: String, color: ThemeColor)] {
        try GraphiteTheme.accentPresets.map { preset in (preset.name, try XCTUnwrap(ThemeColor(hex: preset.hex), preset.name)) }
    }

    func testEveryNodeStandsOutFromThePageInLightAndDark() throws {
        for accent in try presetAccents() {
            let light = GraphPalette(appearance: .light, accent: accent.color)
            let dark = GraphPalette(appearance: .dark, accent: accent.color)
            for kind in [GraphNode.Kind.note, .attachment, .tag, .unresolved] {
                let lightColor = light.color(of: kind), darkColor = dark.color(of: kind)
                XCTAssertGreaterThanOrEqual(AccentLegibility.contrastOnLightBackground(red: lightColor.red, green: lightColor.green, blue: lightColor.blue),
                                            shapeContrast, "\(kind) in light with \(accent.name)")
                XCTAssertGreaterThanOrEqual(AccentLegibility.contrastOnDarkBackground(red: darkColor.red, green: darkColor.green, blue: darkColor.blue),
                                            shapeContrast, "\(kind) in dark with \(accent.name)")
            }
        }
    }

    func testTagsAndAttachmentsKeepAwayFromTheAccentsHue() throws {
        for accent in try presetAccents() {
            guard let accentHue = GraphPalette.hueDegrees(of: accent.color) else { continue }
            for appearance in [GraphPalette.Appearance.light, .dark] {
                let palette = GraphPalette(appearance: appearance, accent: accent.color)
                for kind in [GraphNode.Kind.tag, .attachment] {
                    let hue = try XCTUnwrap(GraphPalette.hueDegrees(of: palette.color(of: kind)))
                    XCTAssertGreaterThanOrEqual(GraphPalette.hueDistanceDegrees(hue, accentHue), GraphPalette.accentHueClearanceDegrees,
                                                "\(kind) with \(accent.name) in \(appearance)")
                }
            }
        }
    }

    func testTagsAreGreenAndAttachmentsAmberUnlessTheAccentIsNearThem() throws {
        let inkBlue = try XCTUnwrap(ThemeColor(hex: GraphiteTheme.defaultAccentHex))
        let green = try XCTUnwrap(ThemeColor(hex: "#2f8f5b")), orange = try XCTUnwrap(ThemeColor(hex: "#d2691e"))
        let usual = GraphPalette(appearance: .light, accent: inkBlue)
        XCTAssertEqual(GraphPalette(appearance: .light, accent: green).attachment, usual.attachment)
        XCTAssertNotEqual(GraphPalette(appearance: .light, accent: green).tag, usual.tag, "A green accent turns tags purple.")
        XCTAssertEqual(GraphPalette(appearance: .light, accent: orange).tag, usual.tag)
        XCTAssertNotEqual(GraphPalette(appearance: .light, accent: orange).attachment, usual.attachment, "An orange accent turns attachments blue.")
        let graphite = try XCTUnwrap(ThemeColor(hex: "#6e6e73"))
        XCTAssertNil(GraphPalette.hueDegrees(of: graphite), "A gray accent has no hue to keep away from.")
        XCTAssertEqual(GraphPalette(appearance: .dark, accent: graphite), GraphPalette(appearance: .dark, accent: inkBlue))
    }

    func testALinkWithoutAFileIsAHollowRingNotANote() {
        XCTAssertTrue(GraphPalette.isDrawnHollow(.unresolved))
        XCTAssertFalse(GraphPalette.isDrawnHollow(.note))
        XCTAssertFalse(GraphPalette.isDrawnHollow(.attachment))
        XCTAssertFalse(GraphPalette.isDrawnHollow(.tag))
    }

    func testLinksStayFainterThanNodesAndStepBackWhileANodeIsFocused() {
        for appearance in [GraphPalette.Appearance.light, .dark] {
            let palette = GraphPalette(appearance: appearance, accent: ThemeColor(red: 0.18, green: 0.36, blue: 0.63))
            XCTAssertLessThan(palette.link.alpha, 0.5)
            XCTAssertLessThan(palette.dimmedLink.alpha, palette.link.alpha)
        }
    }

    func testHuesAreMeasuredAroundTheWheel() {
        XCTAssertEqual(GraphPalette.hueDegrees(of: ThemeColor(red: 1, green: 0, blue: 0)), 0)
        XCTAssertEqual(GraphPalette.hueDegrees(of: ThemeColor(red: 0, green: 1, blue: 0)), 120)
        XCTAssertEqual(GraphPalette.hueDegrees(of: ThemeColor(red: 1, green: 0, blue: 1)), 300)
        XCTAssertEqual(GraphPalette.hueDistanceDegrees(350, 10), 20)
        XCTAssertEqual(GraphPalette.hueDistanceDegrees(90, 270), 180)
    }
}
