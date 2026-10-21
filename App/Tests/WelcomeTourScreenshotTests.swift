#if os(iOS)
import XCTest
import UIKit
@testable import GraphiteUI

/// Run in the application host so this checks the screenshots Xcode compiled into the app's
/// `WelcomeTour` asset catalog, which the tour loads from the main bundle.
final class WelcomeTourScreenshotTests: XCTestCase {
    @MainActor func testEveryScreenshotOfTheTourLoadsInTheLightAndTheDarkAppearance() throws {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let screenshots = WelcomeTourPage.allCases.flatMap { page in page.content.screenshots }
        XCTAssertFalse(screenshots.isEmpty)
        for screenshot in screenshots {
            let lightImage = try XCTUnwrap(UIImage(named: screenshot.assetName, in: .main, compatibleWith: light), screenshot.assetName)
            let darkImage = try XCTUnwrap(UIImage(named: screenshot.assetName, in: .main, compatibleWith: dark), screenshot.assetName)
            XCTAssertFalse(lightImage.pngData() == darkImage.pngData(), "\(screenshot.assetName) has no dark picture of its own")
            XCTAssertGreaterThan(lightImage.size.width, 600, screenshot.assetName)
            XCTAssertFalse(screenshot.accessibilityDescription.isEmpty, screenshot.assetName)
        }
    }
}
#endif
