import XCTest
@testable import GraphiteUI

/// The welcome tour's pages: what each one needs to show, and which pages the Mac leaves out.
/// The hosted `WelcomeTourScreenshotTests` load each page's pictures from the app.
final class WelcomeTourContentTests: XCTestCase {
    func testEveryPageHasATitleASummaryAndPointsWithDistinctIdentifiers() {
        for page in WelcomeTourPage.allCases {
            let content = page.content
            XCTAssertFalse(content.title.isEmpty, "\(page)")
            XCTAssertFalse(content.summary.isEmpty, "\(page)")
            XCTAssertFalse(content.points.isEmpty, "\(page)")
            let identifiers = content.points.map(\.id)
            XCTAssertEqual(Set(identifiers).count, identifiers.count, "\(page): a point's identifier is its title, which the list draws by.")
        }
    }

    func testAPageWithSeveralScreenshotsGivesEachAnOwnLabel() {
        for page in WelcomeTourPage.allCases where page.content.screenshots.count > 1 {
            let labels = page.content.screenshots.map(\.label)
            XCTAssertEqual(Set(labels).count, labels.count, "\(page)")
        }
    }

    func testTheTourStartsWithTheWelcomeAndEndsWithGettingStarted() {
        XCTAssertEqual(WelcomeTourPage.pagesOnThisPlatform.first, .welcome)
        XCTAssertEqual(WelcomeTourPage.pagesOnThisPlatform.last, .gettingStarted)
    }

    func testTheMacLeavesOutOnlyThePencilPages() {
        #if os(macOS)
        XCTAssertEqual(WelcomeTourPage.pagesOnThisPlatform, WelcomeTourPage.allCases.filter { page in !page.needsApplePencilFeatures })
        XCTAssertEqual(Set(WelcomeTourPage.allCases.filter(\.needsApplePencilFeatures)), [.handwriting, .pdfs, .pencilTools])
        #else
        XCTAssertEqual(WelcomeTourPage.pagesOnThisPlatform, WelcomeTourPage.allCases)
        #endif
    }

    func testTheSourceCodeLinkGoesToTheRepository() {
        XCTAssertEqual(WelcomeTourCopy.sourceCodeAddress?.absoluteString, "https://github.com/Graphite-Note/Graphite")
        XCTAssertTrue(WelcomeTourPage.welcome.content.points.contains { point in point.destination == WelcomeTourCopy.sourceCodeAddress })
    }

    func testTheBetaPointLinksToTheRepositorysIssues() {
        XCTAssertEqual(ProjectAddresses.issues?.absoluteString, "https://github.com/Graphite-Note/Graphite/issues")
        XCTAssertTrue(WelcomeTourPage.gettingStarted.content.points.contains { point in point.destination == ProjectAddresses.issues })
    }
}
