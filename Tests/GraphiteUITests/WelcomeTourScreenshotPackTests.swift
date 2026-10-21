import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The welcome tour's pictures are a download (`WelcomeTourScreenshotPack`): every screenshot
/// a page of this platform shows must be in this platform's pack, in both appearances.
final class WelcomeTourScreenshotPackTests: XCTestCase {
    func testEveryScreenshotOfThisPlatformsPagesIsInItsPackInLightAndDark() throws {
        let pack = try XCTUnwrap(WelcomeTourScreenshotPack.forThisPlatform)
        let screenshots = WelcomeTourPage.pagesOnThisPlatform.flatMap { page in page.content.screenshots }
        XCTAssertFalse(screenshots.isEmpty)
        for screenshot in screenshots {
            for isDark in [false, true] {
                let name = WelcomeTourScreenshotPack.fileName(of: screenshot.assetName, isDark: isDark)
                XCTAssertNotNil(pack.file(named: name), name)
            }
        }
    }

    func testThePackIsDownloadedFromOneFixedRevisionOverHTTPS() throws {
        let pack = try XCTUnwrap(WelcomeTourScreenshotPack.forThisPlatform)
        XCTAssertEqual(pack.baseAddress.scheme, "https")
        XCTAssertTrue(pack.baseAddress.absoluteString.contains(WelcomeTourScreenshotPack.revision))
        XCTAssertEqual(WelcomeTourScreenshotPack.revision.count, 40, "A full commit hash, which never moves.")
        XCTAssertTrue(pack.files.allSatisfy { file in file.sha256.count == 64 && file.byteCount > 0 })
    }
}
