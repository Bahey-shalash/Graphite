import XCTest
@testable import GraphiteUI

/// The device settings of the Pencil, kept under these names, and the defaults of those that
/// can be read from a chosen store.
@MainActor
final class PencilPreferenceKeyTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "PencilPreferenceKeyTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testThePencilSettingsAreKeptUnderTheseNames() {
        XCTAssertEqual(StrokeHoldPreference.key, "GraphiteMakesShapesOnHold")
        XCTAssertEqual(EvenHighlighterPreference.key, "GraphiteHighlighterIgnoresTilt")
        XCTAssertEqual(PalmRejectionPreference.key, "GraphitePalmRejection")
        XCTAssertEqual(LassoShape.preferenceKey, "GraphiteLassoShape")
        XCTAssertEqual(LaserPointerStyle.preferenceKey, "GraphiteLaserPointerStyle")
        XCTAssertEqual(PencilToolbarStyle.preferenceKey, "GraphitePencilToolbarStyle")
    }

    func testShapesOnHoldAndPalmRejectionAreOnUnlessTurnedOff() {
        XCTAssertTrue(StrokeHoldPreference.isOn(in: defaults))
        XCTAssertTrue(PalmRejectionPreference.isOn(in: defaults))

        defaults.set(false, forKey: "GraphiteMakesShapesOnHold")
        defaults.set(false, forKey: "GraphitePalmRejection")

        XCTAssertFalse(StrokeHoldPreference.isOn(in: defaults))
        XCTAssertFalse(PalmRejectionPreference.isOn(in: defaults))
    }

    func testTheEvenHighlighterIsOffUnlessTurnedOn() {
        XCTAssertFalse(EvenHighlighterPreference.isOn(in: defaults))

        defaults.set(true, forKey: "GraphiteHighlighterIgnoresTilt")

        XCTAssertTrue(EvenHighlighterPreference.isOn(in: defaults))
    }

    func testTheLassoShapeAndLaserPointerStyleAreKeptByTheseRawValues() {
        XCTAssertEqual(LassoShape.allCases.map(\.rawValue), ["freehand", "rectangle"])
        XCTAssertEqual(LaserPointerStyle.allCases.map(\.rawValue), ["dot", "line"])
    }
}
