import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Tags in the graph: shown unless the person hides them.
@MainActor
final class GraphTagsTests: XCTestCase {
    func testTheGraphsShowTagsUnlessThePersonHidesThem() {
        XCTAssertTrue(GraphSettingDefault.showsTags)
        XCTAssertTrue(GraphSettingDefault.localShowsTags)
    }

    func testTheOtherDefaultsAreObsidians() {
        XCTAssertFalse(GraphSettingDefault.showsAttachments)
        XCTAssertTrue(GraphSettingDefault.showsExistingFilesOnly)
        XCTAssertTrue(GraphSettingDefault.showsOrphans)
        XCTAssertFalse(GraphSettingDefault.showsArrows)
        XCTAssertEqual(GraphSettingDefault.localDepth, 1)
        XCTAssertTrue(GraphSettingDefault.localFollowsIncomingLinks)
        XCTAssertTrue(GraphSettingDefault.localFollowsOutgoingLinks)
        XCTAssertTrue(GraphSettingDefault.localShowsNeighborLinks)
        XCTAssertFalse(GraphSettingDefault.localShowsAttachments)
        XCTAssertTrue(GraphSettingDefault.localShowsExistingFilesOnly)
    }
}
