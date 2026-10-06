import XCTest
import Yams
@testable import GraphiteCore

/// Bases defects found with the edge-case vault, each compared with what Obsidian does for
/// the same `.base` file: a date Range across a daylight-saving change, anchors and custom
/// tags in rewritten entries, `inFolder`, `date()` and `duration()`.
final class CoreBasesEdgeCaseFixTests: XCTestCase {
    private static func calendar(_ timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    private let newYork = CoreBasesEdgeCaseFixTests.calendar("America/New_York")

    private let note = BaseTestRecords.record("Library/Books/Dune.md", yaml: """
        estimate: ""
        year: 1980
        """)

    private func evaluate(_ sourceText: String) throws -> BaseValue {
        let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [note])
        return try evaluator.evaluate(sourceText: sourceText, for: note)
    }

    // MARK: A date Range across a daylight-saving change

    /// The Range summary of a date column, as the table shows it, for notes due on `dueTexts`.
    private func rangeText(ofDatesDue dueTexts: [String], calendar: Calendar) throws -> String? {
        let records = dueTexts.enumerated().map { position, dueText in
            BaseTestRecords.record("Tasks/Task \(position).md", yaml: "due: \(dueText)")
        }
        let definition = try BaseDefinition.parse("""
            views:
              - type: table
                name: Tasks
                order: [file.name, note.due]
                summaries:
                  note.due: Range
            """)
        let environment = BaseEvaluationEnvironment(now: BaseTestRecords.fixedNow, calendar: calendar)
        let result = BaseQueryEngine(definition: definition, environment: environment, thisRecord: nil).run(viewIndex: 0, records: records)
        return result.summaries[.note("due")]?.value.value?.displayText
    }

    func testDateRangeAcrossTheStartOfDaylightSavingTimeCountsWholeDays() throws {
        // New York's clocks went forward on 2025-03-09, so these midnights are 30 days
        // less one hour apart.
        XCTAssertEqual(try rangeText(ofDatesDue: ["2025-03-01", "2025-03-31", "2025-03-15"], calendar: newYork), "30 days")
        XCTAssertEqual(try rangeText(ofDatesDue: ["2025-03-08", "2025-03-10"], calendar: newYork), "2 days")
    }

    func testDateRangeAcrossTheEndOfDaylightSavingTimeCountsWholeDays() throws {
        // The clocks went back on 2025-11-02, so these midnights are 2 days and one hour apart.
        XCTAssertEqual(try rangeText(ofDatesDue: ["2025-11-01", "2025-11-03"], calendar: newYork), "2 days")
    }

    func testDateRangeWithTimesMeasuresTheWallClock() throws {
        XCTAssertEqual(try rangeText(ofDatesDue: ["2025-03-08T10:00:00", "2025-03-10T12:30:00"], calendar: newYork), "2 days 2 hours 30 minutes")
        XCTAssertEqual(try rangeText(ofDatesDue: ["2025-06-01T10:00:00", "2025-06-01T12:00:00"], calendar: newYork), "2 hours",
                       "Without a daylight-saving change nothing differs.")
        XCTAssertEqual(try rangeText(ofDatesDue: ["2025-06-01"], calendar: newYork), "0 seconds")
    }

    // MARK: inFolder

    func testInFolderComparesCaseAsObsidianDoes() throws {
        XCTAssertEqual(try evaluate("file.inFolder(\"Library\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.inFolder(\"Library/Books\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.inFolder(\"library\")"), .boolean(false), "Obsidian compares folder paths exactly.")
        XCTAssertEqual(try evaluate("file.inFolder(\"Library/books\")"), .boolean(false))
        XCTAssertEqual(try evaluate("file.inFolder(\"LIBRARY/BOOKS\")"), .boolean(false))
    }

    func testInFolderStillNormalizesSlashesAndTheVaultRoot() throws {
        XCTAssertEqual(try evaluate("file.inFolder(\"/Library/Books/\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.inFolder(\"Library//Books\")"), .boolean(true), "Repeated slashes are one, as in Obsidian's path normalization.")
        XCTAssertEqual(try evaluate("file.inFolder(\"/\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.inFolder(\"\")"), .boolean(true))
        XCTAssertEqual(try evaluate("file.inFolder(\"Lib\")"), .boolean(false), "A folder whose name only starts the same is another folder.")
    }

    func testInFolderComparesComposedAndDecomposedNamesAsEqual() throws {
        let decomposedFolderNote = BaseTestRecords.record("Cafe\u{301}/Menu.md")
        let evaluator = BaseEvaluator(formulas: [], environment: BaseTestRecords.environment(), thisRecord: nil, knownRecords: [decomposedFolderNote])
        XCTAssertEqual(try evaluator.evaluate(sourceText: "file.inFolder(\"Caf\u{E9}\")", for: decomposedFolderNote), .boolean(true),
                       "Obsidian normalizes both paths to NFC.")
    }

    // MARK: date() and duration()

    func testDateOfANumberIsAnErrorAsInObsidian() throws {
        XCTAssertThrowsError(try evaluate("date(1980)")) { error in
            XCTAssertEqual(error.localizedDescription, "date() needs text, not a number.")
        }
        XCTAssertThrowsError(try evaluate("date(year)"), "A number property is not a date either.")
        XCTAssertThrowsError(try evaluate("date(1700000000000)"), "Milliseconds are not read as a date.")
        XCTAssertEqual(try evaluate("date(\"1980-01-01\").year"), .number(1980))
        XCTAssertEqual(try evaluate("date(missing)"), .null)
    }

    func testDurationOfEmptyTextIsEmpty() throws {
        XCTAssertEqual(try evaluate("duration(\"\")"), .null)
        XCTAssertEqual(try evaluate("duration(\"   \")"), .null)
        XCTAssertEqual(try evaluate("duration(estimate)"), .null, "An empty text property has no duration.")
        XCTAssertEqual(try evaluate("now() + duration(estimate)"), .null)
        XCTAssertEqual(try evaluate("duration(\"2h\").hours"), .number(2))
    }

    // MARK: Anchors, aliases and custom tags in rewritten entries

    func testAnAnchorInAReorderedListStaysAnAnchor() throws {
        let yaml = """
            # Columns shared with the sort below
            views:
              - type: table
                name: Books
                order:
                  - &title file.name
                  - note.author
                  - note.year
                sort:
                  - property: *title
                    direction: ASC
            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setOrder([.note("author"), .file("name"), .note("year")], forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), """
            # Columns shared with the sort below
            views:
              - type: table
                name: Books
                order:
                  - note.author
                  - &title file.name
                  - note.year
                sort:
                  - property: *title
                    direction: ASC
            """)
    }

    func testAnAnchorInARewrittenFlowViewStaysAnAnchor() throws {
        let yaml = """
            views:
              - {type: table, name: Books, order: &columns [file.name, note.author]}
              # The gallery shows the same columns
              - type: cards
                name: Gallery
                order: *columns

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(3, forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), """
            views:
              - {type: table, name: Books, order: &columns [file.name, note.author], limit: 3}
              # The gallery shows the same columns
              - type: cards
                name: Gallery
                order: *columns

            """)
    }

    func testAnAliasInARewrittenFlowViewStaysAnAlias() throws {
        let yaml = """
            views:
              - type: cards
                name: A
                sort:
                  - &byName {property: file.name, direction: ASC}
              - {type: list, name: B, sort: [*byName]}
              - {<<: &shared {type: table, limit: 10}, name: C}
              - {<<: *shared, name: D}

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(3, forViewAt: 1)
        try editor.setName("Last", forViewAt: 3)
        XCTAssertEqual(try editor.yaml(), """
            views:
              - type: cards
                name: A
                sort:
                  - &byName {property: file.name, direction: ASC}
              - {type: list, name: B, sort: [*byName], limit: 3}
              - {<<: &shared {type: table, limit: 10}, name: C}
              - {<<: *shared, name: Last}

            """)
    }

    func testAnAliasWhoseValueChangesBecomesItsOwnValue() throws {
        let yaml = """
            views:
              - type: table
                name: Books
                order: &columns
                  - file.name
                  - note.author
              - type: cards
                name: Gallery
                order: *columns

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setOrder([.file("name"), .note("author"), .note("cover")], forViewAt: 1)
        XCTAssertEqual(try editor.yaml(), """
            views:
              - type: table
                name: Books
                order: &columns
                  - file.name
                  - note.author
              - type: cards
                name: Gallery
                order:
                  - file.name
                  - note.author
                  - note.cover

            """)
    }

    func testCustomTagsInARewrittenFlowViewAreKept() throws {
        let yaml = """
            views:
              - {type: table, name: Books, custom: !mytag value, options: !settings {dense: true}, marks: !set [a, b], label: !!str 123}
              - type: cards
                name: Gallery

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(3, forViewAt: 0)
        let output = try editor.yaml()
        XCTAssertEqual(output, """
            views:
              - {type: table, name: Books, custom: !mytag value, options: !settings {dense: true}, marks: !set [a, b], label: "123", limit: 3}
              - type: cards
                name: Gallery

            """)
        let view = try XCTUnwrap(try Yams.compose(yaml: output)?["views"]?.sequence?.first?.mapping)
        XCTAssertEqual(view["custom"]?.scalar?.tag.description, "!mytag")
        XCTAssertEqual(view["options"]?.mapping?.tag.description, "!settings")
    }

    func testACustomTagOnAReorderedListItemIsKept() throws {
        let yaml = """
            views:
              - type: table
                name: Books
                order:
                  - !column file.name
                  - "note.author"
                  - &year !column note.year
                pinned: *year

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setOrder([.note("year"), .note("author"), .file("name")], forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), """
            views:
              - type: table
                name: Books
                order:
                  - &year !column note.year
                  - "note.author"
                  - !column file.name
                pinned: *year

            """)
    }

    func testAnchorsAndTagsSurviveWhenTheWholeFileIsWritten() throws {
        // A root mapping in flow style cannot be edited line by line.
        let yaml = "{views: [{type: table, name: A, order: &columns [file.name], custom: !mytag value}, {type: cards, name: B, order: *columns}]}\n"
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(3, forViewAt: 0)
        XCTAssertEqual(try editor.yaml(),
                       "{views: [{type: table, name: A, order: &columns [file.name], custom: !mytag value, limit: 3}, {type: cards, name: B, order: *columns}]}\n")
    }

    func testChangingAnAnchoredValueKeepsEveryViewsMeaning() throws {
        let yaml = """
            views:
              - {type: table, name: Books, order: &columns [file.name, note.author]}
              - {type: cards, name: Gallery, order: *columns}

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setOrder([.file("name")], forViewAt: 0)
        let definition = try BaseDefinition.parse(try editor.yaml())
        XCTAssertEqual(definition.views[0].order, [.file("name")])
        XCTAssertEqual(definition.views[1].order, [.file("name"), .note("author")], "The gallery keeps the columns it had.")
    }

    func testAnAnchoredBlockListIsEditedInPlace() throws {
        let yaml = """
            views:
              - type: table
                name: Books
                order: &columns !ordered   # shared
                  - file.name
                  - note.author
                limit: 10

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setOrder([.file("name"), .note("author"), .note("year")], forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), """
            views:
              - type: table
                name: Books
                order: &columns !ordered   # shared
                  - file.name
                  - note.author
                  - note.year
                limit: 10

            """)
    }

    func testRemovingTheViewThatHoldsAnAnchorKeepsTheOtherViewsMeaning() throws {
        let yaml = """
            views:
              - {type: table, name: Books, order: &columns [file.name, note.author]}
              - {type: cards, name: Gallery, order: *columns}
              - {type: list, name: Titles, order: *columns}

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.removeView(at: 0)
        let output = try editor.yaml()
        let definition = try BaseDefinition.parse(output)
        XCTAssertEqual(definition.views.map(\.name), ["Gallery", "Titles"])
        XCTAssertEqual(definition.views.map(\.order), [[.file("name"), .note("author")], [.file("name"), .note("author")]])
    }

    func testAnAnchorNameUsedTwiceKeepsEachAliasOnItsOwnValue() throws {
        let yaml = """
            views:
              - {type: table, name: A, order: &columns [file.name]}
              - {type: table, name: B, order: *columns}
              - {type: table, name: C, order: &columns [note.author]}
              - {type: table, name: D, order: *columns}

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(2, forViewAt: 1)
        try editor.setLimit(4, forViewAt: 3)
        XCTAssertEqual(try editor.yaml(), """
            views:
              - {type: table, name: A, order: &columns [file.name]}
              - {type: table, name: B, order: *columns, limit: 2}
              - {type: table, name: C, order: &columns [note.author]}
              - {type: table, name: D, order: *columns, limit: 4}

            """)
    }

    func testTagsAnchorsAndEmojiSurviveTogetherWithWindowsLineEndings() throws {
        let yaml = "views:\r\n  - {type: table, name: \"📚 Books\", icon: &icon !emoji 📚, order: [file.name]}\r\n  - {type: cards, name: Gallery, icon: *icon}\r\n"
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(3, forViewAt: 0)
        try editor.setLimit(4, forViewAt: 1)
        XCTAssertEqual(try editor.yaml(), "views:\r\n  - {type: table, name: \"📚 Books\", icon: &icon !emoji 📚, order: [file.name], limit: 3}\r\n"
            + "  - {type: cards, name: Gallery, icon: *icon, limit: 4}\r\n")
    }

    func testTextThatLooksLikeAWriterMarkerIsKept() throws {
        let yaml = "views:\n  - {type: table, name: \"&GraphiteTagMarker_0_\", note: GraphiteTagMarker_0_, custom: !mytag value}\n"
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(3, forViewAt: 0)
        XCTAssertEqual(try editor.yaml(), "views:\n  - {type: table, name: \"&GraphiteTagMarker_0_\", note: GraphiteTagMarker_0_, custom: !mytag value, limit: 3}\n")
    }

    func testATagThatCannotBeWrittenBackRefusesTheEdit() throws {
        // `%20` is a space in the tag's name, which cannot be written back as it is; the
        // edit is refused rather than saved without the tag.
        let yaml = "views:\n  - {type: table, name: Books, custom: !my%20tag value}\n"
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.setLimit(3, forViewAt: 0)
        XCTAssertThrowsError(try editor.yaml())
    }

    func testADuplicatedViewIsWrittenInFullAndTheOriginalKeepsItsAnchors() throws {
        let yaml = """
            views:
              - type: table
                name: Books
                order: &columns
                  - file.name
                custom: !mytag value
              - type: cards
                name: Gallery
                order: *columns

            """
        var editor = try BaseDefinitionEditor(yaml: yaml)
        try editor.duplicateView(at: 0, name: "Books copy")
        XCTAssertEqual(try editor.yaml(), """
            views:
              - type: table
                name: Books
                order: &columns
                  - file.name
                custom: !mytag value
              - type: table
                name: Books copy
                order:
                  - file.name
                custom: !mytag value
              - type: cards
                name: Gallery
                order: *columns

            """)
    }
}
