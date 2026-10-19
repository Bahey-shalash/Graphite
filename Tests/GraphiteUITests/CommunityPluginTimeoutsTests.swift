import XCTest
@testable import GraphiteUI

/// The waits and rests of the community-plugin features that have a name of their own.
@MainActor
final class CommunityPluginTimeoutsTests: XCTestCase {
    func testThePluginTimeoutsThatHaveNamesAreThese() {
        XCTAssertEqual(CommunityPluginHost.menuTimeout, .seconds(2), "A menu is shown without the plugins' items after this.")
        XCTAssertEqual(CommunityPluginHost.typingTimeout, .seconds(4), "A plugin's suggestions for one change are skipped after this.")
        XCTAssertEqual(CommunityPluginShownCodeBlock.drawingTimeout, .seconds(20), "A block that is not drawn by then says so.")
        XCTAssertEqual(CommunityPluginShownCodeBlock.tapTimeout, .seconds(5), "A tap on a plugin's block is given up after this.")
    }

    func testTheThemeMeasurementDeadlineIsFifteenSeconds() {
        XCTAssertEqual(ThemeTokenResolver.measurementDeadline, .seconds(15))
    }

    func testTheAppearanceIsSavedSixHundredMillisecondsAfterTheLastChangeAndTheThemeResolvedThreeHundredAfterTheLast() {
        XCTAssertEqual(WorkspaceModel.appearanceSaveDelay, .milliseconds(600))
        XCTAssertEqual(WorkspaceModel.themeRefreshDelay, .milliseconds(300))
    }

    func testThePluginLoadTimeoutIsThirtySecondsAndTheLargestNoteSentForTypingIsHalfAMebibyte() {
        XCTAssertEqual(CommunityPluginHost().pluginLoadTimeout, .seconds(30))
        XCTAssertEqual(CommunityPluginHost.maximumTypingNoteLength, 512 * 1024)
    }
}
