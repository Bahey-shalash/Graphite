import XCTest
@testable import GraphiteCore

final class AppleFolderArtPlanTests: XCTestCase {
    func testTheStandInCarriesWhatGraphiteWrites() {
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: .green, mark: .symbol("star.fill")))
        XCTAssertEqual(plan.standIn.tags, [FinderTag(name: "Green", color: .green)])
        XCTAssertEqual(plan.standIn.iconAttributeData, Data(#"{"sym":"star.fill"}"#.utf8))
        XCTAssertTrue(plan.standIn.setsCustomIconFlag)
    }

    /// A color alone is a tag, which Finder and Files show as a dot on a plain folder.
    func testAColorAloneIsOnlyATag() {
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: .orange))
        XCTAssertEqual(plan.standIn.tags, [FinderTag(name: "Orange", color: .orange)])
        XCTAssertNil(plan.standIn.iconAttributeData)
        XCTAssertFalse(plan.standIn.setsCustomIconFlag)
    }

    func testAColorNoTagHasIsItsNearestTag() {
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: .custom(red: 10, green: 200, blue: 30), mark: .emoji("🥸")))
        XCTAssertEqual(plan.standIn.tags, [FinderTag(name: "Green", color: .green)])
        XCTAssertEqual(plan.standIn.iconAttributeData, Data(#"{"emoji":"🥸"}"#.utf8))
    }

    func testAPictureIsPlacedOnTheFolder() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .onFolder)
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: .red, mark: .picture(picture)))
        XCTAssertEqual(plan.picture, picture)
        XCTAssertNil(plan.standIn.iconAttributeData)
    }

    func testEachLookHasItsOwnStableStandIn() {
        let green = AppleFolderArtPlan.plan(for: FolderStyle(color: .green)).standInName
        XCTAssertEqual(green, AppleFolderArtPlan.plan(for: FolderStyle(color: .green)).standInName)
        XCTAssertNotEqual(green, AppleFolderArtPlan.plan(for: FolderStyle(color: .red)).standInName)
        XCTAssertNotEqual(green, AppleFolderArtPlan.plan(for: FolderStyle(color: .green, mark: .symbol("star.fill"))).standInName)
    }
}
