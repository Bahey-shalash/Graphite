import XCTest

/// `App/Graphite.entitlements` and `App/Info.plist`, the files that decide what the sandboxed
/// Mac app may reach. Any entitlement added or dropped changes what a plugin or a note can
/// touch, so the full set is written out here and a change has to change this test as well.
final class GraphiteEntitlementsTests: XCTestCase {
    private static let applicationFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App", isDirectory: true)

    private func propertyList(named fileName: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.applicationFolder.appendingPathComponent(fileName))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }

    func testTheMacAppIsSandboxedWithExactlyTheSixEntitlements() throws {
        let entitlements = try propertyList(named: "Graphite.entitlements")
        let expectedEntitlements: [String: Bool] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.files.user-selected.read-write": true,
            "com.apple.security.files.bookmarks.app-scope": true,
            "com.apple.security.device.audio-input": true,
            "com.apple.security.device.camera": true,
            "com.apple.security.network.client": true,
        ]
        XCTAssertEqual(Set(entitlements.keys), Set(expectedEntitlements.keys), "No entitlement is added or dropped without a decision.")
        for (key, expectedValue) in expectedEntitlements {
            XCTAssertEqual(entitlements[key] as? Bool, expectedValue, key)
        }
    }

    func testTheMacAppAsksForNoOtherFileOrNetworkServerAccess() throws {
        let entitlementKeys = try propertyList(named: "Graphite.entitlements").keys
        let forbiddenKeyPrefixes = ["com.apple.security.network.server", "com.apple.security.files.all", "com.apple.security.temporary-exception"]
        for key in entitlementKeys {
            XCTAssertFalse(forbiddenKeyPrefixes.contains { prefix in key.hasPrefix(prefix) }, key)
        }
    }

    func testTheCameraMicrophoneAndPhotoLibraryAddReasonsStayInInformationPropertyList() throws {
        let information = try propertyList(named: "Info.plist")
        let usageDescriptionKeys = Set(information.keys.filter { key in key.hasSuffix("UsageDescription") })
        XCTAssertEqual(usageDescriptionKeys, ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription"])
        for key in usageDescriptionKeys {
            let reason = try XCTUnwrap(information[key] as? String, key)
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) states why the app asks.")
        }
    }
}
