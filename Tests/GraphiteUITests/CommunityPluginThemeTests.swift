import XCTest
@testable import GraphiteUI

/// The accent Graphite gives the plugins' page as Obsidian gives it: hue, saturation and
/// lightness, which themes derive their accent shades from.
final class CommunityPluginThemeTests: XCTestCase {
    func testAccentHexBecomesHueSaturationAndLightness() throws {
        let purple = try XCTUnwrap(CommunityPluginHost.hueSaturationLightness(ofHex: "#8b6cef"))
        XCTAssertEqual(purple.hue, 254.2, accuracy: 0.1)
        XCTAssertEqual(purple.saturation, 80.4, accuracy: 0.1)
        XCTAssertEqual(purple.lightness, 68.0, accuracy: 0.2)
        let green = try XCTUnwrap(CommunityPluginHost.hueSaturationLightness(ofHex: "#2e8b57"))
        XCTAssertEqual(green.hue, 146.5, accuracy: 0.2)
        let gray = try XCTUnwrap(CommunityPluginHost.hueSaturationLightness(ofHex: "#808080"))
        XCTAssertEqual(gray.saturation, 0)
        XCTAssertNil(CommunityPluginHost.hueSaturationLightness(ofHex: "purple"))
    }
}
