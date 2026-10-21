import XCTest
import GraphiteCore
@testable import GraphiteUI

final class MyTemplateArrangementTests: XCTestCase {
    private let names = ["A", "B", "C", "D"]

    func testAnItemMovesDownToJustBeforeTheDestination() {
        XCTAssertEqual(MyTemplateArrangement.moved(names, fromOffsets: IndexSet(integer: 0), toOffset: 3), ["B", "C", "A", "D"])
    }

    func testAnItemMovesUp() {
        XCTAssertEqual(MyTemplateArrangement.moved(names, fromOffsets: IndexSet(integer: 3), toOffset: 1), ["A", "D", "B", "C"])
    }

    func testAnItemMovesToTheEnd() {
        XCTAssertEqual(MyTemplateArrangement.moved(names, fromOffsets: IndexSet(integer: 1), toOffset: 4), ["A", "C", "D", "B"])
    }

    func testSeveralItemsMoveTogetherInTheirOrder() {
        XCTAssertEqual(MyTemplateArrangement.moved(names, fromOffsets: IndexSet([0, 2]), toOffset: 4), ["B", "D", "A", "C"])
    }

    func testMovingOntoItsOwnPlaceChangesNothing() {
        XCTAssertEqual(MyTemplateArrangement.moved(names, fromOffsets: IndexSet(integer: 1), toOffset: 1), names)
        XCTAssertEqual(MyTemplateArrangement.moved(names, fromOffsets: IndexSet(integer: 1), toOffset: 2), names)
    }

    func testAnOffsetOutsideTheListIsIgnored() {
        XCTAssertEqual(MyTemplateArrangement.moved(names, fromOffsets: IndexSet(integer: 9), toOffset: 0), names)
    }

    func testTemplatesAreShownInTheArrangedOrderAndAnUnnamedOneStaysAfter() {
        let templates = ["A", "B", "C"].map { name in MyPaperTemplateList.Template(fileName: name + ".pdf", isHidden: false) }
        let arranged = MyPaperTemplateList.Template.arranged(templates, as: ["C.pdf", "A.pdf"])
        XCTAssertEqual(arranged.map(\.fileName), ["C.pdf", "A.pdf", "B.pdf"])
    }
}
