#if os(iOS)
import XCTest
import UIKit

/// Run in the application host so this checks Xcode's compiled resources and manifest.
final class AppIconBundleTests: XCTestCase {
    @MainActor func testEveryIconIsRegisteredForPhoneAndPadAndHasArtwork() throws {
        let expectedAlternates: Set<String> = ["AppIconRed", "AppIconBlack", "AppIconCharcoal", "AppIconBlueGraphite"]
        for manifestKey in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            let declarations = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: manifestKey) as? [String: Any])
            let primary = try XCTUnwrap(declarations["CFBundlePrimaryIcon"] as? [String: Any])
            XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
            let alternates = try XCTUnwrap(declarations["CFBundleAlternateIcons"] as? [String: [String: Any]])
            XCTAssertEqual(Set(alternates.keys), expectedAlternates)
            for (name, declaration) in alternates {
                XCTAssertEqual(declaration["CFBundleIconName"] as? String, name)
            }
        }
        for colorName in ["Blue", "Red", "Black", "Charcoal", "BlueGraphite"] {
            XCTAssertNotNil(UIImage(named: "AppIconPreview" + colorName), "Missing settings preview: \(colorName)")
        }
        XCTAssertTrue(UIApplication.shared.supportsAlternateIcons)
    }

}
#endif
