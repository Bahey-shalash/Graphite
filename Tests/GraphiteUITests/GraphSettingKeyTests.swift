import XCTest
@testable import GraphiteUI

/// The device settings of the graph views and the canvas, kept under these names.
final class GraphSettingKeyTests: XCTestCase {
    func testTheVaultGraphSettingsAreKeptUnderTheseNames() {
        XCTAssertEqual(GraphSettingKey.showsTags, "graphShowsTags")
        XCTAssertEqual(GraphSettingKey.showsAttachments, "graphShowsAttachments")
        XCTAssertEqual(GraphSettingKey.showsExistingFilesOnly, "graphShowsExistingFilesOnly")
        XCTAssertEqual(GraphSettingKey.showsOrphans, "graphShowsOrphans")
        XCTAssertEqual(GraphSettingKey.showsArrows, "graphShowsArrows")
        XCTAssertEqual(GraphSettingKey.linkDistance, "graphLinkDistance")
        XCTAssertEqual(GraphSettingKey.repelStrength, "graphRepelStrength")
        XCTAssertEqual(GraphSettingKey.centerStrength, "graphCenterStrength")
    }

    func testTheLocalGraphSettingsAreKeptUnderTheseNames() {
        XCTAssertEqual(GraphSettingKey.localDepth, "localGraphDepth")
        XCTAssertEqual(GraphSettingKey.localFollowsIncomingLinks, "localGraphFollowsIncomingLinks")
        XCTAssertEqual(GraphSettingKey.localFollowsOutgoingLinks, "localGraphFollowsOutgoingLinks")
        XCTAssertEqual(GraphSettingKey.localShowsNeighborLinks, "localGraphShowsNeighborLinks")
        XCTAssertEqual(GraphSettingKey.localShowsTags, "localGraphShowsTags")
        XCTAssertEqual(GraphSettingKey.localShowsAttachments, "localGraphShowsAttachments")
        XCTAssertEqual(GraphSettingKey.localShowsExistingFilesOnly, "localGraphShowsExistingFilesOnly")
    }

    func testEachVaultsColorGroupsAreKeptUnderItsIdentifier() throws {
        let vault = try XCTUnwrap(UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F"))
        XCTAssertEqual(GraphSettingKey.colorGroups(ofVault: vault), "graphColorGroups.6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")
        XCTAssertEqual(GraphSettingKey.unreadableColorGroups(ofVault: vault), "graphColorGroups.6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F.unreadable")
    }

    func testTheCanvasSnapSettingsAreKeptUnderTheseNames() {
        XCTAssertEqual(CanvasPreferenceKey.snapsToGrid, "GraphiteCanvasSnapsToGrid")
        XCTAssertEqual(CanvasPreferenceKey.snapsToObjects, "GraphiteCanvasSnapsToObjects")
    }
}
