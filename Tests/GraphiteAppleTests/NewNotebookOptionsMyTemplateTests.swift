import XCTest
import GraphiteCore
@testable import GraphiteApple

final class NewNotebookOptionsMyTemplateTests: XCTestCase {
    private func options() -> NewNotebookOptions {
        NewNotebookOptions(paperChoice: .dotted, paperStyle: PaperSpecification(), pageSize: .named(.a4, .portrait), pageCount: 3)
    }

    func testChoosingATemplateKeepsTheBuiltInPaperForLater() {
        var chosen = options()
        chosen.choose(myTemplate: "Planner.pdf")
        XCTAssertEqual(chosen.myTemplateFileName, "Planner.pdf")
        XCTAssertEqual(chosen.paperChoice, .dotted)
    }

    func testChoosingABuiltInPaperReplacesTheTemplate() {
        var chosen = options()
        chosen.choose(myTemplate: "Planner.pdf")
        chosen.choose(.ruledNarrow)
        XCTAssertNil(chosen.myTemplateFileName)
    }

    func testAGalleryPictureOfAPaperIsNeverOfATemplate() {
        var chosen = options()
        chosen.choose(myTemplate: "Planner.pdf")
        XCTAssertNil(chosen.choosing(.blank).myTemplateFileName)
    }

    func testATemplatesSizeIsItsOwnSoTheChosenSizeIsNotChecked() {
        var chosen = NewNotebookOptions(paperChoice: .dotted, paperStyle: PaperSpecification(), pageSize: .custom(widthPoints: 5, heightPoints: 5), pageCount: 3)
        XCTAssertEqual(chosen.problem, .pageSizeOutOfRange)
        chosen.choose(myTemplate: "Planner.pdf")
        XCTAssertNil(chosen.problem)
        chosen.pageCount = 0
        XCTAssertEqual(chosen.problem, .pageCountOutOfRange)
    }
}
