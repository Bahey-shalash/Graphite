import XCTest
import CoreGraphics
import CoreText
import GraphiteCore
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class MyTemplatesModelTests: XCTestCase {
    private func textPDF(_ pageTexts: [String]) throws -> Data {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try XCTUnwrap(CGDataConsumer(data: output))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for text in pageTexts {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 24, nil)]))
            context.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    private func makeModel() throws -> (MyTemplatesModel, TemporaryVault) {
        let vault = try TemporaryVault.make(prefix: "MyTemplatesModel", for: self)
        let model = MyTemplatesModel()
        model.use(MyTemplatesModel.Source(vaultIdentifier: UUID(), store: VaultStore(root: vault.root)))
        return (model, vault)
    }

    private func add(_ pdf: Data, pageIndex: Int = 0, named name: String, to model: MyTemplatesModel) async throws {
        let draft = try await MyTemplateDraft.make(from: pdf, sourceName: "Source")
        draft.selectPage(pageIndex)
        model.add(draft, named: name)
    }

    func testAChosenPageIsKeptAsATemplateAndListed() async throws {
        let (model, vault) = try makeModel()
        try await add(try textPDF(["One", "Two"]), pageIndex: 1, named: "Lecture grid", to: model)
        try await waitUntil { model.templates.map(\.fileName) == ["Lecture grid.pdf"] }
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.location(of: ".obsidian/graphite-templates/Lecture grid.pdf").path))
        XCTAssertNil(model.failure)
    }

    func testChangesHappenInTheOrderAsked() async throws {
        let (model, _) = try makeModel()
        let pdf = try textPDF(["Page"])
        try await add(pdf, named: "A", to: model)
        try await add(pdf, named: "B", to: model)
        try await add(pdf, named: "C", to: model)
        try await waitUntil { model.templates.map(\.fileName) == ["A.pdf", "B.pdf", "C.pdf"] }
        model.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        model.setHidden(true, template: MyPaperTemplateList.Template(fileName: "B.pdf", isHidden: false))
        try await waitUntil { model.templates.map(\.fileName) == ["C.pdf", "A.pdf", "B.pdf"] && model.templates[2].isHidden }
        XCTAssertEqual(model.shownTemplates.map(\.fileName), ["C.pdf", "A.pdf"])
    }

    func testRenamingAndDeleting() async throws {
        let (model, vault) = try makeModel()
        let pdf = try textPDF(["Page"])
        try await add(pdf, named: "A", to: model)
        try await add(pdf, named: "B", to: model)
        try await waitUntil { model.templates.count == 2 }
        model.rename(model.templates[0], to: "Weekly")
        try await waitUntil { model.templates.map(\.fileName) == ["Weekly.pdf", "B.pdf"] }
        model.delete(model.templates[1])
        try await waitUntil { model.templates.map(\.fileName) == ["Weekly.pdf"] }
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.location(of: ".obsidian/graphite-templates/B.pdf").path))
    }

    func testAPictureIsDrawnForAListedTemplateAndGivenBackWhenTheSheetCloses() async throws {
        let (model, _) = try makeModel()
        try await add(try textPDF(["Page"]), named: "A", to: model)
        try await waitUntil { model.templates.count == 1 }
        model.requestPreview(of: "A.pdf")
        try await waitUntil { model.previews["A.pdf"] != nil }
        XCTAssertEqual(model.previews["A.pdf"]?.pageSize, CGSize(width: 595, height: 842))
        model.forgetPreviews()
        XCTAssertTrue(model.previews.isEmpty)
    }

    func testNoMorePicturesAreKeptThanTheBudget() async throws {
        let (model, vault) = try makeModel()
        let names = (0..<(MyTemplatesModel.maximumPreviewCount + 5)).map { number in "T\(number).pdf" }
        let pdf = try textPDF(["Page"])
        for name in names { try vault.writeFile(".obsidian/graphite-templates/" + name, data: pdf) }
        model.refresh()
        try await waitUntil { model.templates.count == names.count }
        for name in names { model.requestPreview(of: name) }
        try await waitUntil { model.previews.count == MyTemplatesModel.maximumPreviewCount }
        XCTAssertLessThanOrEqual(model.previews.count, MyTemplatesModel.maximumPreviewCount)
    }

    func testAnArrangementThatCannotBeReadIsKeptAsideAndReported() async throws {
        let vault = try TemporaryVault.make(prefix: "MyTemplatesModel", files: [".obsidian/graphite-templates/templates.json": "not json"], for: self)
        try vault.writeFile(".obsidian/graphite-templates/A.pdf", data: try textPDF(["Page"]))
        let model = MyTemplatesModel()
        model.use(MyTemplatesModel.Source(vaultIdentifier: UUID(), store: VaultStore(root: vault.root)))
        try await waitUntil { model.failure != nil }
        XCTAssertEqual(model.failure, .arrangementSetAside(keptCopyName: "templates.unreadable.json"))
        try await waitUntil { model.templates.map(\.fileName) == ["A.pdf"] }
        XCTAssertEqual(try String(contentsOf: vault.location(of: ".obsidian/graphite-templates/templates.unreadable.json"), encoding: .utf8), "not json")
    }

    func testAnotherVaultStartsWithItsOwnTemplates() async throws {
        let (model, _) = try makeModel()
        try await add(try textPDF(["Page"]), named: "A", to: model)
        try await waitUntil { model.templates.count == 1 }
        let other = try TemporaryVault.make(prefix: "OtherVault", for: self)
        model.use(MyTemplatesModel.Source(vaultIdentifier: UUID(), store: VaultStore(root: other.root)))
        XCTAssertTrue(model.templates.isEmpty)
        try await waitUntil { model.isListed }
        XCTAssertTrue(model.templates.isEmpty)
    }

    func testADraftOfAPDFOffersItsPagesAndNamesThemByNumber() async throws {
        let draft = try await MyTemplateDraft.make(from: try textPDF(["One", "Two", "Three"]), sourceName: "Slides")
        XCTAssertEqual(draft.kind, .pdf(pageCount: 3))
        XCTAssertEqual(draft.name, "Slides page 1")
        draft.selectPage(2)
        XCTAssertEqual(draft.name, "Slides page 3")
        draft.rename(to: "Mine")
        draft.selectPage(1)
        XCTAssertEqual(draft.name, "Mine", "A name the person typed is kept when another page is chosen.")
        draft.selectPage(7)
        XCTAssertEqual(draft.selectedPageIndex, 1, "A page that is not there is not chosen.")
    }

    func testADraftOfAFileThatIsNeitherAPDFNorAPictureIsRefused() async throws {
        do {
            _ = try await MyTemplateDraft.make(from: Data("just words".utf8), sourceName: "Notes")
            XCTFail("Text is not paper.")
        } catch {
            XCTAssertEqual(error as? MyTemplateDraftError, .unsupported)
        }
    }

    func testADraftOfAOnePagePDFKeepsTheFilesName() async throws {
        let draft = try await MyTemplateDraft.make(from: try textPDF(["Only"]), sourceName: "Planner")
        XCTAssertEqual(draft.name, "Planner")
        XCTAssertEqual(draft.pageCount, 1)
    }
}
