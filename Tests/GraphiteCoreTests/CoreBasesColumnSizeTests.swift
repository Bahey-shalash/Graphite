import XCTest
@testable import GraphiteCore

/// A table view's `columnSize`: read as Obsidian reads it, and written back so that only
/// that key changes in the `.base` file.
final class CoreBasesColumnSizeTests: XCTestCase {
    private let booksBase = """
        # Reading list
        filters:
          and:
            - file.inFolder("Books")   # only books
        views:
          - type: table
            name: Books
            order:
              - file.name
              - note.author
              - formula.age
            columnSize:
              file.name: 240   # the title
              note.author: 120
            futureOption: keep me
          - type: cards
            name: Covers

        """

    private func widths(_ yaml: String, view viewIndex: Int = 0) throws -> [BasePropertyIdentifier: Double] {
        try BaseDefinition.parse(yaml).views[viewIndex].columnWidths
    }

    // MARK: Reading

    func testWidthsAreReadByProperty() throws {
        XCTAssertEqual(try widths(booksBase), [.file("name"): 240, .note("author"): 120])
        XCTAssertEqual(try widths(booksBase, view: 1), [:])
    }

    func testOnlyNumbersOtherThanZeroAreWidthsAsInObsidian() throws {
        let yaml = """
            views:
              - type: table
                name: T
                columnSize:
                  file.name: "240"
                  note.zero: 0
                  note.text: wide
                  note.list: [1, 2]
                  note.nan: .nan
                  note.infinite: .inf
                  note.fraction: 150.6
                  note.empty:
            """
        XCTAssertEqual(try widths(yaml), [.note("fraction"): 150.6], "Quoted text, zero, and values that are not numbers are no widths.")
    }

    func testWidthsStayWithinTheColumnLimits() throws {
        let yaml = "views:\n  - type: table\n    name: T\n    columnSize:\n      note.narrow: 12\n      note.negative: -30\n      note.huge: 1e9\n"
        XCTAssertEqual(try widths(yaml), [.note("narrow"): 40, .note("negative"): 40, .note("huge"): 2_000],
                       "Obsidian shows a resized column at least 40 points wide.")
    }

    func testAColumnSizeThatIsNotAMappingIsIgnored() throws {
        XCTAssertEqual(try widths("views:\n  - type: table\n    name: T\n    columnSize: 200\n"), [:])
        XCTAssertEqual(try widths("views:\n  - type: table\n    name: T\n    columnSize: [200, 300]\n"), [:])
        XCTAssertEqual(try widths("views:\n  - type: table\n    name: T\n    columnSize:\n"), [:])
    }

    // MARK: Writing

    func testResizingAColumnChangesOnlyItsLine() throws {
        var editor = try BaseDefinitionEditor(yaml: booksBase)
        try editor.setColumnWidth(183.4, of: .note("author"), forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), booksBase.replacingOccurrences(of: "      note.author: 120\n", with: "      note.author: 183\n"))
    }

    func testResizingAColumnWithoutAWidthAddsOneLine() throws {
        var editor = try BaseDefinitionEditor(yaml: booksBase)
        try editor.setColumnWidth(96, of: .formula("age"), forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), booksBase.replacingOccurrences(of: "      note.author: 120\n", with: "      note.author: 120\n      formula.age: 96\n"))
    }

    func testTheFirstResizedColumnOfAViewAddsTheKey() throws {
        var editor = try BaseDefinitionEditor(yaml: booksBase)
        try editor.setColumnWidth(300, of: .file("name"), forViewAt: 1)
        XCTAssertEqual(try editor.yaml(), booksBase.replacingOccurrences(of: "    name: Covers\n", with: "    name: Covers\n    columnSize:\n      file.name: 300\n"))
        XCTAssertEqual(try widths(try editor.yaml(), view: 1), [.file("name"): 300])
    }

    func testResettingAColumnRemovesItsLineAndTheLastOneRemovesTheKey() throws {
        var editor = try BaseDefinitionEditor(yaml: booksBase)
        try editor.setColumnWidth(nil, of: .file("name"), forViewAt: 0)
        let withoutTitleWidth = booksBase.replacingOccurrences(of: "      file.name: 240   # the title\n", with: "")
        XCTAssertEqual(try editor.yaml(), withoutTitleWidth)

        try editor.setColumnWidth(nil, of: .note("author"), forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), withoutTitleWidth.replacingOccurrences(of: "    columnSize:\n      note.author: 120\n", with: ""))
        XCTAssertEqual(try widths(try editor.yaml()), [:])

        // Resetting a column that has no width changes nothing.
        var untouched = try BaseDefinitionEditor(yaml: booksBase)
        try untouched.setColumnWidth(nil, of: .formula("age"), forViewAt: 0)
        XCTAssertEqual(try untouched.yaml(), booksBase)
    }

    func testWidthsAreWrittenAsWholePointsWithinTheColumnLimits() throws {
        var editor = try BaseDefinitionEditor(yaml: booksBase)
        try editor.setColumnWidth(12.2, of: .file("name"), forViewAt: 0)
        try editor.setColumnWidth(9_999, of: .note("author"), forViewAt: 0)
        let output = try editor.yaml()
        XCTAssertEqual(try widths(output), [.file("name"): 40, .note("author"): 2_000])
        // A comment on a line that is rewritten goes with the line, as for every edit.
        XCTAssertEqual(output, booksBase.replacingOccurrences(of: "      file.name: 240   # the title\n      note.author: 120\n",
                                                              with: "      file.name: 40\n      note.author: 2000\n"))
    }

    func testAWidthUnderAnotherSpellingIsReplacedByTheNameObsidianReads() throws {
        // Obsidian looks widths up by the full property name, so `author: 120` is no width
        // there. A resize must not leave it beside the new one.
        let yaml = "views:\n  - type: table\n    name: T\n    order: [file.name, author]\n    columnSize:\n      author: 120\n      file.name: 200\n"
        XCTAssertEqual(try widths(yaml), [.note("author"): 120, .file("name"): 200])
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setColumnWidth(150, of: .note("author"), forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), "views:\n  - type: table\n    name: T\n    order: [file.name, author]\n    columnSize:\n      file.name: 200\n      note.author: 150\n")
    }

    func testAFlowStyleColumnSizeStaysInFlowStyle() throws {
        let yaml = "views:\n  - type: table\n    name: T\n    columnSize: {file.name: 200, note.author: 120}\n    limit: 5\n"
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setColumnWidth(90, of: .note("author"), forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), "views:\n  - type: table\n    name: T\n    columnSize: {file.name: 200, note.author: 90}\n    limit: 5\n")
    }

    func testAColumnSizeThatIsNotAMappingIsReplacedByOne() throws {
        var editor = try BaseDefinitionEditor(yaml: "views:\n  - type: table\n    name: T\n    columnSize: wide\n")
        try editor.setColumnWidth(150, of: .file("name"), forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), "views:\n  - type: table\n    name: T\n    columnSize:\n      file.name: 150\n")
    }

    func testResizingTheDefaultTableOfABaseWithoutViewsWritesTheView() throws {
        var editor = try BaseDefinitionEditor(yaml: "filters: file.ext == \"md\"\n")
        try editor.setColumnWidth(320, of: .file("name"), forViewAt: 0)
        let definition = try BaseDefinition.parse(try editor.yaml())
        XCTAssertEqual(definition.filters, .expression("file.ext == \"md\""))
        XCTAssertEqual(definition.views.map(\.columnWidths), [[.file("name"): 320]])
    }

    func testWindowsLineEndingsAndAMissingViewAreHandled() throws {
        var editor = try BaseDefinitionEditor(yaml: "views:\r\n  - type: table\r\n    name: T\r\n")
        try editor.setColumnWidth(150, of: .file("name"), forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), "views:\r\n  - type: table\r\n    name: T\r\n    columnSize:\r\n      file.name: 150\r\n")
        XCTAssertThrowsError(try editor.setColumnWidth(150, of: .file("name"), forViewAt: 4))
    }
}
