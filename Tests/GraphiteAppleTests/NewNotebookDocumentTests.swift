import XCTest
import PDFKit
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

final class NewNotebookDocumentTests: XCTestCase {
    private func options(pageCount: Int, cover: NotebookCoverColor? = nil) -> NewNotebookOptions {
        var options = NewNotebookOptions(paperChoice: .squared, paperStyle: PaperSpecification(), pageSize: .named(.a5, .portrait), pageCount: pageCount)
        options.cover = cover
        return options
    }

    func testWithoutACoverTheNotebookIsThePapers() throws {
        let data = try NewNotebookDocument.data(for: options(pageCount: 3), titled: "Notes", templateLocation: nil)
        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 3)
    }

    func testACoverIsAnExtraFirstPage() throws {
        let data = try NewNotebookDocument.data(for: options(pageCount: 3, cover: .purple), titled: "Quantum Notes", templateLocation: nil)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 4)
        XCTAssertTrue(try XCTUnwrap(document.page(at: 0)?.string).contains("Quantum"))
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, document.page(at: 1)?.bounds(for: .mediaBox).size)
    }

    func testACoverGoesBeforeATemplatesPages() throws {
        let folder = try TemporaryVault.make(prefix: "CoverTemplate", for: self).root
        let location = folder.appendingPathComponent("Template.pdf")
        try PDFTemplateGenerator.documentData(paper: PaperSpecification(template: .dotted, width: 300, height: 400), pageCount: 1).write(to: location)
        var chosen = options(pageCount: 2, cover: .orange)
        chosen.choose(myTemplate: "Template.pdf")
        let data = try NewNotebookDocument.data(for: chosen, titled: "Planner", templateLocation: location)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 3)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 300, height: 400), "The cover has the template's size, not the chosen size.")
    }

    func testATemplateThatIsNotThereIsRefused() throws {
        var chosen = options(pageCount: 1)
        chosen.choose(myTemplate: "Gone.pdf")
        XCTAssertThrowsError(try NewNotebookDocument.data(for: chosen, titled: "A", templateLocation: nil)) { error in
            XCTAssertEqual(error as? MyPaperTemplateError, .unreadableTemplate)
        }
    }

    func testNoCoverIsTheDefault() {
        XCTAssertNil(options(pageCount: 1).cover)
    }
}
