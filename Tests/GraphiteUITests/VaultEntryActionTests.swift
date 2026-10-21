import XCTest
@testable import GraphiteUI

final class VaultEntryActionTests: XCTestCase {
    func testAFileOffersTabsRenameMoveCopyBookmarkAndDelete() {
        let actions = VaultEntryAction.offered(isDirectory: false, bookmarksAreEnabled: true, isBookmarked: false)
        XCTAssertEqual(actions, [.openInNewTab, .openOnOtherSide, .rename, .moveTo, .makeCopy, .bookmark, .delete])
    }

    func testAFolderOffersNoTabs() {
        let actions = VaultEntryAction.offered(isDirectory: true, bookmarksAreEnabled: true, isBookmarked: false)
        XCTAssertEqual(actions, [.rename, .moveTo, .makeCopy, .bookmark, .delete])
    }

    func testABookmarkedItemOffersToRemoveIt() {
        XCTAssertTrue(VaultEntryAction.offered(isDirectory: false, bookmarksAreEnabled: true, isBookmarked: true).contains(.removeBookmark))
        XCTAssertFalse(VaultEntryAction.offered(isDirectory: false, bookmarksAreEnabled: true, isBookmarked: true).contains(.bookmark))
    }

    func testBookmarksAreOfferedOnlyWhileThePluginIsOn() {
        let actions = VaultEntryAction.offered(isDirectory: false, bookmarksAreEnabled: false, isBookmarked: true)
        XCTAssertFalse(actions.contains(.bookmark) || actions.contains(.removeBookmark))
    }

    func testOnlyDeleteIsDestructiveAndTheOtherSideUsesTheWorkspacesWording() {
        XCTAssertEqual(VaultEntryAction.allCases.filter(\.isDestructive), [.delete])
        XCTAssertEqual(VaultEntryAction.openOnOtherSide.title(otherSideTitle: "Open to the Right"), "Open to the Right")
    }
}
