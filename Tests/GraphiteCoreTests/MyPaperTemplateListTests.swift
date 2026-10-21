import XCTest
@testable import GraphiteCore

final class MyPaperTemplateListTests: XCTestCase {
    private func list(_ json: String) throws -> MyPaperTemplateList {
        try MyPaperTemplateList(configurationData: Data(json.utf8))
    }

    func testTemplatesNamedInTheArrangementComeFirstInItsOrderThenTheOthersByName() throws {
        let arranged = try list(#"{"order": ["Zebra.pdf", "Alpha.pdf"]}"#)
        let shown = arranged.templates(listing: ["Alpha.pdf", "Mango.pdf", "Zebra.pdf", "Beta.pdf"])
        XCTAssertEqual(shown.map(\.fileName), ["Zebra.pdf", "Alpha.pdf", "Beta.pdf", "Mango.pdf"])
    }

    func testANameWithoutItsFileIsLeftOutAndAFileWithoutAnArrangementIsShown() throws {
        let arranged = try list(#"{"order": ["Gone.pdf", "Here.pdf"]}"#)
        XCTAssertEqual(arranged.templates(listing: ["Here.pdf", "Hand placed.pdf"]).map(\.fileName), ["Here.pdf", "Hand placed.pdf"])
    }

    func testNumbersInNamesSortAsPeopleCountThem() {
        XCTAssertEqual(MyPaperTemplateList().templates(listing: ["Page 10.pdf", "Page 2.pdf"]).map(\.fileName), ["Page 2.pdf", "Page 10.pdf"])
    }

    func testHidingAndShowingATemplate() {
        var arranged = MyPaperTemplateList()
        arranged.setHidden(true, fileName: "A.pdf")
        XCTAssertEqual(arranged.templates(listing: ["A.pdf", "B.pdf"]).map(\.isHidden), [true, false])
        arranged.setHidden(false, fileName: "A.pdf")
        XCTAssertEqual(arranged.templates(listing: ["A.pdf"]).map(\.isHidden), [false])
    }

    func testARenamedTemplateKeepsItsPlaceAndHiddenState() {
        var arranged = MyPaperTemplateList()
        arranged.arrange(["A.pdf", "B.pdf", "C.pdf"])
        arranged.setHidden(true, fileName: "B.pdf")
        arranged.rename("B.pdf", to: "Lecture grid.pdf")
        let shown = arranged.templates(listing: ["A.pdf", "Lecture grid.pdf", "C.pdf"])
        XCTAssertEqual(shown.map(\.fileName), ["A.pdf", "Lecture grid.pdf", "C.pdf"])
        XCTAssertEqual(shown[1].isHidden, true)
        XCTAssertEqual(shown[1].name, "Lecture grid")
    }

    func testADeletedTemplateIsForgotten() {
        var arranged = MyPaperTemplateList()
        arranged.arrange(["A.pdf", "B.pdf"])
        arranged.setHidden(true, fileName: "A.pdf")
        arranged.forget("A.pdf")
        XCTAssertEqual(arranged.order, ["B.pdf"])
        XCTAssertTrue(arranged.hiddenFileNames.isEmpty)
    }

    func testRoundTripKeepsWhatThisBuildDoesNotKnow() throws {
        let newer = try list(#"{"order": ["A.pdf", 7, "B.pdf"], "hidden": ["B.pdf", null], "version": 3, "extra": {"a": 1}}"#)
        XCTAssertEqual(newer.order, ["A.pdf", "B.pdf"])
        let rewritten = try XCTUnwrap(JSONSerialization.jsonObject(with: newer.configurationData()) as? [String: Any])
        XCTAssertEqual(rewritten["version"] as? Int, 3)
        XCTAssertEqual((rewritten["extra"] as? [String: Any])?["a"] as? Int, 1)
        XCTAssertEqual((rewritten["order"] as? [Any])?.count, 3, "The entry that is no file name is kept.")
        XCTAssertEqual((rewritten["hidden"] as? [Any])?.count, 2)
    }

    func testNoFileOrAnEmptyOneMeansNoArrangement() throws {
        XCTAssertEqual(try MyPaperTemplateList(configurationData: nil), MyPaperTemplateList())
        XCTAssertEqual(try MyPaperTemplateList(configurationData: Data()), MyPaperTemplateList())
    }

    func testAFileThatIsNotThisFormatIsRefusedSoItIsNeverOverwritten() {
        XCTAssertThrowsError(try list("not json")) { error in XCTAssertEqual(error as? MyPaperTemplateListError, .notAJSONObject) }
        XCTAssertThrowsError(try list("[1, 2]")) { error in XCTAssertEqual(error as? MyPaperTemplateListError, .notAJSONObject) }
        XCTAssertThrowsError(try list(#"{"order": "A.pdf"}"#)) { error in XCTAssertEqual(error as? MyPaperTemplateListError, .fieldNotAnArray("order")) }
    }
}
