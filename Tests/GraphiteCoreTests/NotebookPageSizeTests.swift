import XCTest
@testable import GraphiteCore

final class NotebookPageSizeTests: XCTestCase {
    func testISOSizesAreTheirMillimetersInPoints() {
        XCTAssertEqual(NotebookPageSize.a4.portraitPointSize, CGSize(width: 595.28, height: 841.89))
        XCTAssertEqual(NotebookPageSize.a3.portraitPointSize, CGSize(width: 841.89, height: 1190.55))
        XCTAssertEqual(NotebookPageSize.a5.portraitPointSize, CGSize(width: 419.53, height: 595.28))
        XCTAssertEqual(NotebookPageSize.a6.portraitPointSize, CGSize(width: 297.64, height: 419.53))
        XCTAssertEqual(NotebookPageSize.a7.portraitPointSize, CGSize(width: 209.76, height: 297.64))
    }

    func testAmericanSizesAreWholeInches() {
        XCTAssertEqual(NotebookPageSize.letter.portraitPointSize, CGSize(width: 612, height: 792))
        XCTAssertEqual(NotebookPageSize.tabloid.portraitPointSize, CGSize(width: 792, height: 1224))
    }

    func testEveryPortraitSizeIsTallerThanWide() {
        for size in NotebookPageSize.allCases {
            XCTAssertLessThan(size.portraitPointSize.width, size.portraitPointSize.height, size.rawValue)
        }
    }

    func testLandscapeLaysTheLongerSideHorizontally() {
        XCTAssertEqual(NotebookPageSize.a4.pointSize(in: .landscape), CGSize(width: 841.89, height: 595.28))
        XCTAssertEqual(NotebookPageSize.a4.pointSize(in: .portrait), CGSize(width: 595.28, height: 841.89))
    }

    func testOrientationOfASizeIsReadFromItsSides() {
        XCTAssertEqual(PageOrientation(of: CGSize(width: 800, height: 600)), .landscape)
        XCTAssertEqual(PageOrientation(of: CGSize(width: 600, height: 800)), .portrait)
        XCTAssertEqual(PageOrientation(of: CGSize(width: 600, height: 600)), .portrait)
    }

    func testApplyingAnOrientationToASquareKeepsIt() {
        XCTAssertEqual(PageOrientation.landscape.applied(to: CGSize(width: 500, height: 500)), CGSize(width: 500, height: 500))
    }
}
