#if os(macOS)
import XCTest
@testable import GraphiteUI

/// AppKit takes the Metal renderer setting only as a Boolean: the text "NO" left the
/// renderer on and opening a note kept its 170 MB peak.
final class MacViewDrawingTests: XCTestCase {
    func testTheMetalRendererIsTurnedOffWithABooleanThatSetValuesStillOverride() throws {
        let suiteName = "MacViewDrawingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        MacViewDrawing.drawLargeViewsWithoutTheMetalRenderer(in: defaults)

        let registeredValue = defaults.object(forKey: MacViewDrawing.metalRendererDefaultsKey)
        XCTAssertEqual(registeredValue as? Bool, false)
        XCTAssertFalse(registeredValue is String)
        defaults.set(true, forKey: MacViewDrawing.metalRendererDefaultsKey)
        XCTAssertEqual(defaults.object(forKey: MacViewDrawing.metalRendererDefaultsKey) as? Bool, true)
    }
}
#endif
