import XCTest
@testable import GraphiteCore

final class AppleFolderArtPlanTests: XCTestCase {
    func testATagColorAndSymbolAreAllApplesArt() {
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: .green, mark: .symbol("star.fill")))
        XCTAssertEqual(plan.standIn.tags, [FinderTag(name: "Green", color: .green)])
        XCTAssertEqual(plan.standIn.iconAttributeData, Data(#"{"sym":"star.fill"}"#.utf8))
        XCTAssertTrue(plan.standIn.setsCustomIconFlag)
        XCTAssertNil(plan.tintColor)
        XCTAssertNil(plan.markDrawnOver)
    }

    /// A color alone is drawn by the invisible emoji, which tints the stand-in.
    func testAColorAloneTintsTheStandIn() {
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: .orange))
        XCTAssertEqual(plan.standIn.tags, [FinderTag(name: "Orange", color: .orange)])
        XCTAssertEqual(plan.standIn.iconAttributeData, Data(#"{"emoji":" "}"#.utf8))
        XCTAssertNil(plan.markDrawnOver)
    }

    func testAColorNoTagHasIsTintedFromGrayAndTheMarkDrawnOver() {
        let color = FolderColor.custom(red: 10, green: 200, blue: 30)
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: color, mark: .emoji("🥸")))
        XCTAssertEqual(plan.standIn.tags, [FinderTag(name: "Gray", color: .gray)])
        XCTAssertEqual(plan.tintColor, color)
        XCTAssertEqual(plan.markDrawnOver, .emoji("🥸"))
    }

    func testAPlainLookIsThePlainFolder() {
        let plan = AppleFolderArtPlan.plan(for: FolderStyle())
        XCTAssertEqual(plan.standIn.tags, [])
        XCTAssertNil(plan.standIn.iconAttributeData)
        XCTAssertFalse(plan.standIn.setsCustomIconFlag)
    }

    func testAPictureIsPlacedOnTheTintedFolder() throws {
        let picture = FolderPicture(path: try VaultPath(".obsidian/graphite-folder-icons/0123456789abcdef.png"), layout: .onFolder)
        let plan = AppleFolderArtPlan.plan(for: FolderStyle(color: .red, mark: .picture(picture)))
        XCTAssertEqual(plan.picture, picture)
        XCTAssertNil(plan.markDrawnOver)
        XCTAssertEqual(plan.standIn.iconAttributeData, Data(#"{"emoji":" "}"#.utf8))
    }

    func testEachLookHasItsOwnStableStandIn() {
        let green = AppleFolderArtPlan.plan(for: FolderStyle(color: .green)).standInName
        XCTAssertEqual(green, AppleFolderArtPlan.plan(for: FolderStyle(color: .green)).standInName)
        XCTAssertNotEqual(green, AppleFolderArtPlan.plan(for: FolderStyle(color: .red)).standInName)
        XCTAssertNotEqual(green, AppleFolderArtPlan.plan(for: FolderStyle(color: .green, mark: .symbol("star.fill"))).standInName)
    }
}
