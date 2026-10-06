import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Obsidian's Kanban layout: the columns a board shows, and moving a card, which writes
/// the column's value into the note's grouped property.
@MainActor
final class UiBasesKanbanTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("UiBasesKanbanVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        let location = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private let fixTestbench = "---\nstatus: todo   # set by the lab\npriority: 1\ndue: 2026-09-20\ndone: false\ncourse: \"[[Digital design]]\"\ntags: [task, lab]\n---\n\nThe testbench fails on reset.\n"
    private let reviewLecture = "---\nstatus: doing\npriority: 2\ndue: 2026-09-24\ndone: false\ncourse: \"[[Signals]]\"\ntags: [task]\n---\nBody\n"
    private let emailTheTA = "---\nstatus: done\npriority: 2\ndue: 2026-09-18\ndone: true\ntags: [task]\n---\n"
    private let planStudyGroup = "---\nstatus:\npriority: 3\ndone: false\n---\n"

    /// A board of four tasks, grouped by `groupProperty`.
    private func boardModel(groupedBy groupProperty: String) async throws -> BaseDocumentModel {
        try write(fixTestbench, to: "Tasks/Fix testbench.md")
        try write(reviewLecture, to: "Tasks/Review lecture 5.md")
        try write(emailTheTA, to: "Tasks/Email the TA.md")
        try write(planStudyGroup, to: "Tasks/Plan study group.md")
        try write("filters: file.inFolder(\"Tasks\")\nformulas:\n  urgency: priority * 2\nviews:\n  - type: kanban\n    name: Board\n    order: [file.name, priority]\n    groupBy:\n      property: \(groupProperty)\n      direction: ASC\n", to: "Tasks.base")
        _ = try await index.reconcile(root: vault)
        let basePath = try VaultPath("Tasks.base")
        let model = BaseDocumentModel(source: .file(basePath), contextPath: basePath, store: store, index: index)
        await model.reload()
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertEqual(model.selectedView?.type, .kanban)
        return model
    }

    private func columns(_ model: BaseDocumentModel) -> [String: [String]] {
        var columns: [String: [String]] = [:]
        for group in model.result?.groups ?? [] { columns[BaseKanbanView.title(of: group)] = group.rows.map(\.path.stem) }
        return columns
    }

    private func groupKey(_ model: BaseDocumentModel, titled title: String) throws -> BaseCellValue {
        try XCTUnwrap(model.result?.groups.first { group in BaseKanbanView.title(of: group) == title }?.key)
    }

    // MARK: Columns

    func testColumnsAreTheGroupsOfTheGroupedPropertyWithEmptyValuesInNone() async throws {
        let model = try await boardModel(groupedBy: "note.status")
        XCTAssertEqual(model.result?.groups.map(BaseKanbanView.title(of:)), ["doing", "done", "todo", "None"])
        XCTAssertEqual(columns(model), ["doing": ["Review lecture 5"], "done": ["Email the TA"], "todo": ["Fix testbench"], "None": ["Plan study group"]])
    }

    // MARK: Moving cards

    func testMovingACardWritesOnlyTheGroupedPropertyOfItsNote() async throws {
        let model = try await boardModel(groupedBy: "note.status")
        let path = try VaultPath("Tasks/Fix testbench.md")
        XCTAssertTrue(model.canMoveToGroup(path))
        let isMoved = await model.moveToGroup(path, groupKey: try groupKey(model, titled: "doing"))
        XCTAssertTrue(isMoved)
        XCTAssertNil(model.actionErrorMessage)
        XCTAssertEqual(try text(at: "Tasks/Fix testbench.md"), fixTestbench.replacingOccurrences(of: "status: todo   # set by the lab\n", with: "status: doing # set by the lab\n"),
                       "Only the status line changes, and its comment stays.")
        XCTAssertEqual(columns(model)["doing"], ["Fix testbench", "Review lecture 5"], "The card is in its new column once the note is saved.")
        XCTAssertNil(columns(model)["todo"])
    }

    func testMovingACardToTheNoneColumnEmptiesTheProperty() async throws {
        let model = try await boardModel(groupedBy: "note.status")
        let isMoved = await model.moveToGroup(try VaultPath("Tasks/Email the TA.md"), groupKey: try groupKey(model, titled: "None"))
        XCTAssertTrue(isMoved)
        XCTAssertEqual(try text(at: "Tasks/Email the TA.md"), emailTheTA.replacingOccurrences(of: "status: done\n", with: "status:\n"))
        XCTAssertEqual(columns(model)["None"], ["Email the TA", "Plan study group"])
    }

    func testMovingACardWritesTheColumnsValueAsTheNoteHoldsIt() async throws {
        let byPriority = try await boardModel(groupedBy: "note.priority")
        let isMovedByPriority = await byPriority.moveToGroup(try VaultPath("Tasks/Fix testbench.md"), groupKey: try groupKey(byPriority, titled: "3"))
        XCTAssertTrue(isMovedByPriority)
        XCTAssertTrue(try text(at: "Tasks/Fix testbench.md").contains("\npriority: 3\n"), "A number stays a number.")

        let byDone = try await boardModel(groupedBy: "note.done")
        let isMovedByDone = await byDone.moveToGroup(try VaultPath("Tasks/Fix testbench.md"), groupKey: try groupKey(byDone, titled: "true"))
        XCTAssertTrue(isMovedByDone)
        XCTAssertTrue(try text(at: "Tasks/Fix testbench.md").contains("\ndone: true\n"))

        let byDue = try await boardModel(groupedBy: "note.due")
        let dueKey = try XCTUnwrap(byDue.result?.groups.first { group in group.rows.map(\.path.stem) == ["Review lecture 5"] }?.key)
        let isMovedByDue = await byDue.moveToGroup(try VaultPath("Tasks/Fix testbench.md"), groupKey: dueKey)
        XCTAssertTrue(isMovedByDue)
        XCTAssertTrue(try text(at: "Tasks/Fix testbench.md").contains("\ndue: 2026-09-24\n"), "A date is written as a date.")

        let byCourse = try await boardModel(groupedBy: "note.course")
        let courseKey = try XCTUnwrap(byCourse.result?.groups.first { group in group.rows.map(\.path.stem) == ["Review lecture 5"] }?.key)
        let isMovedByCourse = await byCourse.moveToGroup(try VaultPath("Tasks/Fix testbench.md"), groupKey: courseKey)
        XCTAssertTrue(isMovedByCourse)
        XCTAssertTrue(try text(at: "Tasks/Fix testbench.md").contains("\ncourse: \"[[Signals]]\"\n"), "A link is written as the link.")
        XCTAssertEqual(byCourse.result?.groups.first { group in group.rows.map(\.path.stem).contains("Fix testbench") }?.rows.count, 2)
    }

    func testCardsOfABoardGroupedByAFormulaOrAFilePropertyDoNotMove() async throws {
        for groupProperty in ["formula.urgency", "file.folder"] {
            let model = try await boardModel(groupedBy: groupProperty)
            let path = try VaultPath("Tasks/Fix testbench.md")
            XCTAssertFalse(model.canMoveToGroup(path), groupProperty)
            let key = try XCTUnwrap(model.result?.groups.first?.key)
            let isMoved = await model.moveToGroup(path, groupKey: key)
            XCTAssertFalse(isMoved, groupProperty)
            XCTAssertEqual(try text(at: "Tasks/Fix testbench.md"), fixTestbench, groupProperty)
        }
    }

    func testOnlyMarkdownNotesMove() async throws {
        let model = try await boardModel(groupedBy: "note.status")
        XCTAssertFalse(model.canMoveToGroup(try VaultPath("Tasks/Slides.pdf")))
        XCTAssertFalse(model.canMoveToGroup(try VaultPath("Tasks.base")), "The base itself is no card to move.")
    }

    func testAMoveThatWouldChangeAnotherPropertyIsRefused() async throws {
        let model = try await boardModel(groupedBy: "note.status")
        // A duplicate key: rewriting the frontmatter would lose one of them.
        let damagedNote = "---\nstatus: todo\nstatus: later\npriority: 1\n---\n"
        try write(damagedNote, to: "Tasks/Fix testbench.md")
        let isMoved = await model.moveToGroup(try VaultPath("Tasks/Fix testbench.md"), groupKey: try groupKey(model, titled: "doing"))
        XCTAssertFalse(isMoved)
        XCTAssertNotNil(model.actionErrorMessage)
        XCTAssertEqual(try text(at: "Tasks/Fix testbench.md"), damagedNote)
    }

    // MARK: Column values

    func testAColumnsValueIsWrittenAsANotePropertyHoldsIt() {
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.string("doing"))), .text("doing"))
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.number(2.5))), .number(2.5))
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.boolean(false))), .checkbox(false))
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.link(BaseLink(target: "People/Ann", display: "Ann")))), .text("[[People/Ann|Ann]]"))
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.list([.string("a"), .link(BaseLink(target: "B"))]))), .list(["a", "[[B]]"]))
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.null)), .empty)
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.string(""))), .empty)
        XCTAssertEqual(BaseDocumentModel.propertyValue(forGroupKey: .value(.list([]))), .empty)
    }

    func testAColumnWhoseValueNoPropertyHoldsTakesNoCards() throws {
        XCTAssertNil(BaseDocumentModel.propertyValue(forGroupKey: .error("There is no formula named “x”.")))
        XCTAssertNil(BaseDocumentModel.propertyValue(forGroupKey: .value(.file(try VaultPath("Notes/A.md")))))
        XCTAssertNil(BaseDocumentModel.propertyValue(forGroupKey: .value(.duration(BaseDuration(days: 2)))))
        XCTAssertNil(BaseDocumentModel.propertyValue(forGroupKey: .value(.object(BaseObject(entries: [BaseObjectEntry(key: "a", value: .number(1))])))))
        XCTAssertNil(BaseDocumentModel.propertyValue(forGroupKey: .value(.list([.list([.string("nested")])]))))
    }
}
