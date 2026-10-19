import XCTest
import GraphiteCore
@testable import GraphiteApple

final class NewNotebookOptionsTests: XCTestCase {
    private let style = PaperSpecification(template: .blank, spacing: PaperSpecification.standardSpacing, paperColorHex: "#fbf7ea", lineColor: .blue, lineStrength: .strong)

    func testPaperTakesTheChoicesTemplateAndTheChosenSize() {
        let options = NewNotebookOptions(paperChoice: .squared, paperStyle: style, pageSize: .named(.a5, .landscape))
        XCTAssertEqual(options.paper.template, .grid)
        XCTAssertEqual(options.paper.width, 595.28)
        XCTAssertEqual(options.paper.height, 419.53)
        XCTAssertEqual(options.paper.paperColorHex, "#fbf7ea")
        XCTAssertEqual(options.paper.lineColor, .blue)
        XCTAssertEqual(options.paper.lineStrength, .strong)
    }

    func testRuledNarrowAndWideSetTheirSpacing() {
        var options = NewNotebookOptions(paperChoice: .ruledNarrow, paperStyle: style, pageSize: .named(.a4, .portrait))
        XCTAssertEqual(options.paper.spacing, NotebookPaperGallery.ruledNarrowSpacingPoints)
        XCTAssertEqual(options.paper.template, .ruled)
        options.choose(.ruledWide)
        XCTAssertEqual(options.paper.spacing, NotebookPaperGallery.ruledWideSpacingPoints)
    }

    func testOtherPapersKeepTheChosenSpacing() {
        var options = NewNotebookOptions(paperChoice: .ruledWide, paperStyle: style, pageSize: .named(.a4, .portrait))
        options.choose(.dotted)
        XCTAssertEqual(options.paper.spacing, NotebookPaperGallery.ruledWideSpacingPoints)
        XCTAssertEqual(options.paperChoice, .dotted)
    }

    func testChoosingForAPictureLeavesTheOptionsAlone() {
        let options = NewNotebookOptions(paperChoice: .dotted, paperStyle: style, pageSize: .named(.a4, .portrait))
        XCTAssertEqual(options.choosing(.music).paper.template, .music)
        XCTAssertEqual(options.paperChoice, .dotted)
    }

    func testCustomSizesOutsideOneToFortyInchesAreRefused() {
        XCTAssertEqual(NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .custom(widthPoints: 50, heightPoints: 800)).problem, .pageSizeOutOfRange)
        XCTAssertEqual(NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .custom(widthPoints: 600, heightPoints: 3000)).problem, .pageSizeOutOfRange)
        XCTAssertEqual(NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .custom(widthPoints: .nan, heightPoints: 800)).problem, .pageSizeOutOfRange)
        XCTAssertNil(NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .custom(widthPoints: 72, heightPoints: 2880)).problem)
    }

    /// The create sheet used to close first and let the generator reject the size, so the
    /// user's entries were lost; the sheet's check and the generator agree on every side.
    func testCustomSizeProblemMatchesWhatTheGeneratorAccepts() throws {
        for sideLength in [72.0, 612, 2880] {
            let options = NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .custom(widthPoints: sideLength, heightPoints: 792))
            XCTAssertNil(options.problem)
            XCTAssertNoThrow(try PDFTemplateGenerator.documentData(paper: options.paper))
        }
        for sideLength in [71.9, 2880.1, 50, 0, -10, 100_000, .infinity, .nan] {
            let options = NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .custom(widthPoints: 612, heightPoints: sideLength))
            XCTAssertEqual(options.problem, .pageSizeOutOfRange, "\(sideLength)")
            XCTAssertThrowsError(try PDFTemplateGenerator.documentData(paper: options.paper), "\(sideLength)")
        }
    }

    func testPageCountsOutsideTheRangeAreRefused() {
        XCTAssertEqual(NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .named(.a4, .portrait), pageCount: 0).problem, .pageCountOutOfRange)
        XCTAssertEqual(NewNotebookOptions(paperChoice: .blank, paperStyle: style, pageSize: .named(.a4, .portrait), pageCount: 1001).problem, .pageCountOutOfRange)
    }

    func testEveryNamedSizeInEitherOrientationMakesANotebook() throws {
        for size in NotebookPageSize.allCases {
            for orientation in PageOrientation.allCases {
                let options = NewNotebookOptions(paperChoice: .dotted, paperStyle: style, pageSize: .named(size, orientation))
                XCTAssertNil(options.problem, "\(size) \(orientation)")
                XCTAssertNoThrow(try PDFTemplateGenerator.documentData(paper: options.paper), "\(size) \(orientation)")
            }
        }
    }

    func testEverySectionChoiceAppearsOnce() {
        let listedChoices = NotebookPaperSection.allCases.flatMap(\.choices)
        XCTAssertEqual(listedChoices.count, Set(listedChoices).count)
        XCTAssertEqual(Set(listedChoices), Set(NotebookPaperChoice.allCases))
    }
}
