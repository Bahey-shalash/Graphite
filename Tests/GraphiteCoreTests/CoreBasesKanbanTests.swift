import XCTest
@testable import GraphiteCore

/// Obsidian 1.14's Kanban layout, `type: kanban`: read, written, and grouped into columns.
final class CoreBasesKanbanTests: XCTestCase {
    func testKanbanIsAViewTypeOfItsOwn() throws {
        let definition = try BaseDefinition.parse("""
            views:
              - type: kanban
                name: Board
                groupBy:
                  property: note.status
                  direction: ASC
              - type: Kanban
                name: Capitalized
              - type: base-board
                name: A plugin's board
            """)
        XCTAssertEqual(definition.views.map(\.type), [.kanban, .kanban, .unsupported("base-board")])
        XCTAssertEqual(BaseViewType.kanban.rawValue, "kanban")
        XCTAssertEqual(definition.views[0].groupBy, BaseSortKey(property: .note("status"), direction: .ascending))
    }

    func testANewBoardAndAChangedLayoutAreWrittenAsKanban() throws {
        let yaml = "views:\n  - type: table\n    name: Tasks\n"
        var editor = try BaseDefinitionEditor(yaml: yaml)
        editor.addView(type: .kanban, name: "Board")
        XCTAssertEqual(try editor.yaml(), yaml + "  - type: kanban\n    name: Board\n    order:\n      - file.name\n")
        var changed = try BaseDefinitionEditor(yaml: yaml)
        try changed.setType(.kanban, forViewAt: 0)
        XCTAssertEqual(try changed.yaml(), "views:\n  - type: kanban\n    name: Tasks\n")
    }

    func testABoardsColumnsAreItsGroupsWithEmptyValuesLast() throws {
        let records = [("A", "todo"), ("B", "done"), ("C", ""), ("D", "todo")].map { name, status in
            BaseTestRecords.record("Tasks/\(name).md", yaml: status.isEmpty ? "priority: 1" : "status: \(status)")
        }
        let definition = try BaseDefinition.parse("""
            views:
              - type: kanban
                name: Board
                groupBy:
                  property: note.status
                  direction: DESC
            """)
        let result = BaseQueryEngine(definition: definition, environment: BaseTestRecords.environment(), thisRecord: nil).run(viewIndex: 0, records: records)
        XCTAssertEqual(result.groups.map { group in group.key?.value?.displayText ?? "?" }, ["todo", "done", ""])
        XCTAssertEqual(result.groups.map { group in group.rows.map(\.path.stem) }, [["A", "D"], ["B"], ["C"]])
    }
}
