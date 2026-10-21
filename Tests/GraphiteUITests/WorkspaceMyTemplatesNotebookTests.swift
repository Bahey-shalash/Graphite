import XCTest
import CoreGraphics
import CoreText
import PDFKit
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A notebook made from one of the person's own paper templates, from the library's New Notebook
/// sheet and from inside a note.
@MainActor
final class WorkspaceMyTemplatesNotebookTests: XCTestCase {
    private func makeWorkspace() async throws -> (WorkspaceModel, TemporaryVault) {
        let vault = try TemporaryVault.make(prefix: "TemplateNotebook", files: ["Note.md": "text"], for: self)
        let indexFolder = try TemporaryVault.make(prefix: "TemplateNotebookIndex", for: self).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault.root)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault.root)
        workspace.store = VaultStore(root: vault.root)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return (workspace, vault)
    }

    private func templateData() throws -> Data {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: output)), mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Weekly planner", attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 24, nil)]))
        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    func testANotebookOfATemplateHasThatPageAsEveryPage() async throws {
        let (workspace, vault) = try await makeWorkspace()
        _ = try await XCTUnwrap(workspace.store).addMyPaperTemplate(try templateData(), named: "Planner")
        var options = NewNotebookOptions(paperChoice: .dotted, paperStyle: PaperSpecification(), pageSize: .named(.a4, .portrait), pageCount: 4)
        options.choose(myTemplate: "Planner.pdf")

        await workspace.createNotebook(named: "Week", options: options)

        XCTAssertNil(workspace.errorMessage)
        let document = try XCTUnwrap(PDFDocument(url: vault.location(of: "Week.pdf")))
        XCTAssertEqual(document.pageCount, 4)
        for pageIndex in 0..<4 { XCTAssertTrue(try XCTUnwrap(document.page(at: pageIndex)?.string).contains("Weekly planner")) }
    }

    func testANotebookOfABuiltInPaperIsUnchanged() async throws {
        let (workspace, vault) = try await makeWorkspace()
        let options = NewNotebookOptions(paperChoice: .squared, paperStyle: PaperSpecification(), pageSize: .named(.a4, .portrait), pageCount: 2)
        await workspace.createNotebook(named: "Squares", options: options)
        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(PDFDocument(url: vault.location(of: "Squares.pdf"))?.pageCount, 2)
    }

    func testATemplateThatIsGoneMakesNoNotebookAndSaysSo() async throws {
        let (workspace, vault) = try await makeWorkspace()
        var options = NewNotebookOptions(paperChoice: .dotted, paperStyle: PaperSpecification(), pageSize: .named(.a4, .portrait), pageCount: 2)
        options.choose(myTemplate: "Deleted.pdf")
        await workspace.createNotebook(named: "Week", options: options)
        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.location(of: "Week.pdf").path))
    }
}
