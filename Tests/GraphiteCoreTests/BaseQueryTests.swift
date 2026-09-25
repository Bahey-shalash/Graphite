import XCTest
@testable import GraphiteCore

final class BaseDefinitionTests: XCTestCase {
    /// The task tracker example from Obsidian's Bases documentation.
    static let taskTrackerYAML = """
        filters:
          and:
            - file.hasTag("task")
            - 'file.ext == "md"'

        formulas:
          days_until_due: 'if(due, (date(due) - today()).days, "")'
          is_overdue: 'if(due, date(due) < today() && status != "done", false)'
          priority_label: 'if(priority == 1, "🔴 High", if(priority == 2, "🟡 Medium", "🟢 Low"))'

        properties:
          status:
            displayName: Status
          formula.days_until_due:
            displayName: "Days Until Due"
          formula.priority_label:
            displayName: Priority

        views:
          - type: table
            name: "Active Tasks"
            filters:
              and:
                - 'status != "done"'
            order:
              - file.name
              - status
              - formula.priority_label
              - due
              - formula.days_until_due
            groupBy:
              property: status
              direction: ASC
            summaries:
              formula.days_until_due: Average

          - type: table
            name: "Completed"
            filters:
              and:
                - 'status == "done"'
            order:
              - file.name
              - completed_date
        """

    func testParsesTheDocumentationTaskTracker() throws {
        let definition = try BaseDefinition.parse(Self.taskTrackerYAML)
        XCTAssertEqual(definition.filters, .and([.expression("file.hasTag(\"task\")"), .expression("file.ext == \"md\"")]))
        XCTAssertEqual(definition.formulas.map(\.name), ["days_until_due", "is_overdue", "priority_label"])
        XCTAssertEqual(definition.displayName(for: .note("status")), "Status")
        XCTAssertEqual(definition.displayName(for: BasePropertyIdentifier("formula.priority_label")), "Priority")
        XCTAssertEqual(definition.displayName(for: .note("due")), "due")
        XCTAssertEqual(definition.displayName(for: .file("name")), "file name")
        XCTAssertEqual(definition.views.map(\.name), ["Active Tasks", "Completed"])
        let activeTasks = definition.views[0]
        XCTAssertEqual(activeTasks.type, .table)
        XCTAssertEqual(activeTasks.order, [.file("name"), .note("status"), .formula("priority_label"), .note("due"), .formula("days_until_due")])
        XCTAssertEqual(activeTasks.groupBy, BaseSortKey(property: .note("status"), direction: .ascending))
        XCTAssertEqual(activeTasks.summaries, [.formula("days_until_due"): "Average"])
        XCTAssertEqual(activeTasks.filters, .and([.expression("status != \"done\"")]))
        XCTAssertTrue(definition.issues.isEmpty, "\(definition.issues)")
    }

    func testParsesViewOptionsForEveryViewType() throws {
        let definition = try BaseDefinition.parse("""
            views:
              - type: table
                name: Table
                limit: 10
                sort:
                  - property: note.priority
                    direction: DESC
                  - column: file.name
                    direction: ASC
                columnSize:
                  file.name: 240
                  note.status: 120
                rowHeight: tall
              - type: cards
                name: Gallery
                image: note.cover
                imageFit: contain
                imageAspectRatio: 1.5
                cardSize: 220
              - type: list
                name: Simple List
                markers: numbers
                indentProperties: true
                separator: " | "
              - type: map
                name: Map
                coordinates: note.coordinates
                markerIcon: formula.Type icon
                markerColor: note.color
                defaultZoom: 12
                center: "[48.8566, 2.3522]"
                minZoom: 3
                maxZoom: 30
                mapHeight: 50
                mapTiles:
                  - https://tiles.example/{z}/{x}/{y}.png
              - type: kanban
                name: Board
            """)
        guard definition.views.count == 5 else { return XCTFail("Expected 5 views, got \(definition.views.map(\.name))") }
        let table = definition.views[0]
        XCTAssertEqual(table.limit, 10)
        XCTAssertEqual(table.sort, [BaseSortKey(property: .note("priority"), direction: .descending), BaseSortKey(property: .file("name"), direction: .ascending)])
        XCTAssertEqual(table.columnWidths[.file("name")], 240)
        XCTAssertEqual(table.rowHeight, "tall")
        let cards = definition.views[1]
        XCTAssertEqual(cards.cards.imageProperty, .note("cover"))
        XCTAssertEqual(cards.cards.imageFit, .contain)
        XCTAssertEqual(cards.cards.imageAspectRatio, 1.5)
        XCTAssertEqual(cards.cards.cardSize, 220)
        let list = definition.views[2]
        XCTAssertEqual(list.list.marker, .numbers)
        XCTAssertTrue(list.list.indentsProperties)
        XCTAssertEqual(list.list.separator, " | ")
        let map = definition.views[3]
        XCTAssertEqual(map.map.coordinatesProperty, .note("coordinates"))
        XCTAssertEqual(map.map.markerIconProperty, .formula("Type icon"), "Property names may contain spaces.")
        XCTAssertEqual(map.map.markerColorProperty, .note("color"))
        XCTAssertEqual(map.map.defaultZoom, 12)
        XCTAssertEqual(map.map.center, "[48.8566, 2.3522]")
        XCTAssertEqual(map.map.minimumZoom, 3)
        XCTAssertEqual(map.map.maximumZoom, 24, "Zoom is clamped like the Maps plugin does.")
        XCTAssertEqual(map.map.embeddedHeight, 100)
        XCTAssertEqual(map.map.tileURLs, ["https://tiles.example/{z}/{x}/{y}.png"])
        XCTAssertEqual(definition.views[4].type, .unsupported("kanban"))
    }

    func testMapAcceptsZoomAndHeightAndViewsKeepTheirListPositions() throws {
        let definition = try BaseDefinition.parse("""
            views:
              - just a string, not a view
              - type: map
                name: Map
                zoom: 12
                height: 520
            """)
        XCTAssertEqual(definition.views.count, 1)
        XCTAssertEqual(definition.views[0].id, 1, "The id is the position in the file's views list, which the editor uses.")
        XCTAssertEqual(definition.views[0].map.defaultZoom, 12)
        XCTAssertEqual(definition.views[0].map.embeddedHeight, 520)
        let repeated = try BaseDefinition.parse("views:\n  - type: table\n    order: [file.name, rating, file.name]")
        XCTAssertEqual(repeated.views[0].order, [.file("name"), .note("rating")], "A repeated column is shown once.")
    }

    func testEmptyAndInvalidBases() throws {
        let emptyDefinition = try BaseDefinition.parse("")
        XCTAssertEqual(emptyDefinition.views.map(\.name), ["Table"], "An empty base shows a default table.")
        XCTAssertEqual(emptyDefinition.views[0].visibleProperties, [.file("name")])
        XCTAssertThrowsError(try BaseDefinition.parse("views: [unclosed")) { error in
            guard case .invalidYAML = error as? BaseDefinitionError else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try BaseDefinition.parse("- a\n- list"))
        let withIssues = try BaseDefinition.parse("filters:\n  maybe:\n    - x\nviews:\n  - just text\n  - type: table\n    limit: many")
        XCTAssertNil(withIssues.filters)
        XCTAssertEqual(withIssues.issues.count, 3, "\(withIssues.issues)")
        XCTAssertEqual(withIssues.views.count, 1)
    }

    func testNestedFiltersFromTheDocumentation() throws {
        let definition = try BaseDefinition.parse("""
            filters:
              or:
                - file.hasTag("tag")
                - and:
                    - file.hasTag("book")
                    - file.hasLink("Textbook")
                - not:
                    - file.hasTag("book")
                    - file.inFolder("Required Reading")
            """)
        XCTAssertEqual(definition.filters, .or([
            .expression("file.hasTag(\"tag\")"),
            .and([.expression("file.hasTag(\"book\")"), .expression("file.hasLink(\"Textbook\")")]),
            .not([.expression("file.hasTag(\"book\")"), .expression("file.inFolder(\"Required Reading\")")]),
        ]))
    }
}

final class BaseQueryTests: XCTestCase {
    private let tasks: [BaseFileRecord] = [
        BaseTestRecords.record("Tasks/Write report.md", yaml: "status: todo\npriority: 1\ndue: 2025-09-18\nestimate: 3", tags: ["task"]),
        BaseTestRecords.record("Tasks/Email team.md", yaml: "status: done\npriority: 2\ndue: 2025-09-10\nestimate: 1\ncompleted_date: 2025-09-09", tags: ["task"]),
        BaseTestRecords.record("Tasks/Plan trip.md", yaml: "status: doing\npriority: 3\nestimate: 5", tags: ["task"]),
        BaseTestRecords.record("Tasks/Fix bug.md", yaml: "status: todo\npriority: 1\ndue: 2025-09-12\nestimate: 2", tags: ["task", "work"]),
        BaseTestRecords.record("Tasks/Old idea.md", yaml: "priority: 2", tags: ["task/archived"]),
        BaseTestRecords.record("Notes/Meeting.md", yaml: "status: todo", tags: ["meeting"]),
        BaseTestRecords.record("Tasks/diagram.png"),
    ]

    private func run(_ yaml: String, view viewIndex: Int = 0, records: [BaseFileRecord]? = nil, this thisRecord: BaseFileRecord? = nil,
                     sortOverride: [BaseSortKey]? = nil) throws -> BaseQueryResult {
        let definition = try BaseDefinition.parse(yaml)
        let engine = BaseQueryEngine(definition: definition, environment: BaseTestRecords.environment(), thisRecord: thisRecord)
        return engine.run(viewIndex: viewIndex, records: records ?? tasks, sortOverride: sortOverride)
    }

    private func names(_ result: BaseQueryResult) -> [String] { result.rows.map(\.path.stem) }

    func testGlobalAndViewFiltersCombine() throws {
        let result = try run(BaseDefinitionTests.taskTrackerYAML)
        XCTAssertTrue(result.problems.isEmpty, "\(result.problems)")
        XCTAssertEqual(Set(names(result)), ["Write report", "Plan trip", "Fix bug", "Old idea"], "Nested #task/archived counts as #task; the image and the meeting do not.")
        let completed = try run(BaseDefinitionTests.taskTrackerYAML, view: 1)
        XCTAssertEqual(names(completed), ["Email team"])
        XCTAssertEqual(completed.columns.map(\.displayName), ["file name", "completed_date"])
        guard let completedRow = completed.rows.first, completedRow.cells.count > 1 else { return XCTFail("Expected a row with two cells") }
        XCTAssertEqual(completedRow.cells[1].value?.displayText, "2025-09-09")
    }

    func testOrAndNotFilters() throws {
        let result = try run("""
            filters:
              or:
                - file.hasTag("meeting")
                - and:
                    - file.hasTag("task")
                    - priority == 1
                - not:
                    - file.ext == "md"
            """)
        XCTAssertEqual(Set(names(result)), ["Meeting", "Write report", "Fix bug", "diagram"])
    }

    func testFormulasGroupsAndSummariesFromTheTaskTracker() throws {
        let result = try run(BaseDefinitionTests.taskTrackerYAML)
        XCTAssertEqual(result.columns.map(\.displayName), ["file name", "Status", "Priority", "due", "Days Until Due"])
        XCTAssertEqual(result.groups.map { group in group.key?.value?.displayText ?? "" }, ["doing", "todo", ""], "Groups ascend; the empty group is last.")
        guard result.groups.count == 3 else { return XCTFail("Expected 3 groups") }
        let todoGroup = result.groups[1]
        XCTAssertEqual(todoGroup.rows.map(\.path.stem), ["Fix bug", "Write report"], "Rows keep the default name order within a group.")
        XCTAssertEqual(todoGroup.rows.map { row in row.cells[2].value?.displayText }, ["🔴 High", "🔴 High"])
        XCTAssertEqual(todoGroup.rows.map { row in row.cells[4].value }, [.number(-4), .number(2)])
        XCTAssertEqual(todoGroup.summaries[.formula("days_until_due")], BaseSummaryCell(name: "Average", value: .value(.number(-1))))
        let doingGroup = result.groups[0]
        guard let doingRow = doingGroup.rows.first, doingRow.cells.count > 4 else { return XCTFail("Expected a doing row with five cells") }
        XCTAssertEqual(doingRow.cells[4].value, .string(""), "if(due, …, \"\") is empty text without a due date.")
        XCTAssertEqual(result.summaries[.formula("days_until_due")]?.value, .value(.number(-1)), "Text values are ignored by Average.")
        XCTAssertEqual(result.matchingCount, 4)
    }

    func testMultipleSortKeysAndDirectionsWithEmptyValuesLast() throws {
        let yaml = """
            filters: file.hasTag("task")
            views:
              - type: table
                name: Sorted
                sort:
                  - property: priority
                    direction: ASC
                  - property: estimate
                    direction: DESC
            """
        XCTAssertEqual(names(try run(yaml)), ["Write report", "Fix bug", "Email team", "Old idea", "Plan trip"])
        let byDueDescending = try run(yaml, sortOverride: [BaseSortKey(property: .note("due"), direction: .descending)])
        XCTAssertEqual(names(byDueDescending), ["Write report", "Fix bug", "Email team", "Old idea", "Plan trip"])
        let byDueAscending = try run(yaml, sortOverride: [BaseSortKey(property: .note("due"), direction: .ascending)])
        XCTAssertEqual(names(byDueAscending), ["Email team", "Fix bug", "Write report", "Old idea", "Plan trip"], "Empty due dates stay last in both directions.")
    }

    func testSortingMixedDatesAndDateTextIsConsistent() {
        // Dates from properties typed as dates, next to the same kind of dates written as text.
        let values: [BaseValue] = [.string("2026-10-20"), .string("2027-03-15"), .string("2026-10-02"), .string("not a date"), .number(3), .string("12")]
        let dateValues = values.compactMap { value -> BaseValue? in
            guard case .string(let text) = value, let date = BaseDateParsing.date(from: text, calendar: BaseDateFormatting.displayCalendar) else { return nil }
            return .date(date)
        }
        let mixed = (values + dateValues).map(\.normalizedForSorting)
        let sorted = mixed.sorted { leftValue, rightValue in BaseValue.sortOrder(leftValue, rightValue) == .orderedAscending }
        XCTAssertEqual(sorted.map(\.displayText).filter { text in text.contains("202") }.map { text in String(text.prefix(4)) }, ["2026", "2026", "2026", "2026", "2027", "2027"])
        XCTAssertEqual(sorted.first, .number(3))
        XCTAssertEqual(sorted[1], .number(12), "Numeric text sorts as a number.")
        XCTAssertEqual(sorted.last, .string("not a date"))
    }

    func testLimitAppliesAfterSorting() throws {
        let result = try run("""
            filters: file.hasTag("task")
            views:
              - type: table
                name: Top two
                limit: 2
                sort:
                  - property: estimate
                    direction: DESC
            """)
        XCTAssertEqual(names(result), ["Plan trip", "Write report"])
        XCTAssertEqual(result.matchingCount, 5, "The count before the limit is kept for the header.")
        XCTAssertEqual(result.displayedCount, 2)
    }

    func testDefaultSummaries() {
        let numbers: [BaseValue] = [.number(4), .number(1), .number(3), .null, .string("x"), .number(2)]
        XCTAssertEqual(BaseSummaryCalculator.summarize("Average", values: numbers), .number(2.5))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Min", values: numbers), .number(1))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Max", values: numbers), .number(4))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Sum", values: numbers), .number(10))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Range", values: numbers), .number(3))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Median", values: numbers), .number(2.5))
        guard case .number(let deviation) = BaseSummaryCalculator.summarize("Stddev", values: numbers) else { return XCTFail() }
        XCTAssertEqual(deviation, 1.118, accuracy: 0.001)
        XCTAssertEqual(BaseSummaryCalculator.summarize("Empty", values: numbers), .number(1))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Filled", values: numbers), .number(5))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Unique", values: numbers + [.number(4), .string("4")]), .number(6), "The number 4 and the text 4 differ.")
        let calendar = BaseDateFormatting.displayCalendar
        let dates: [BaseValue] = ["2025-01-10", "2025-01-01", "2025-03-01"].compactMap { text in BaseDateParsing.date(from: text, calendar: calendar).map(BaseValue.date) }
        XCTAssertEqual(BaseSummaryCalculator.summarize("Earliest", values: dates)?.displayText, "2025-01-01")
        XCTAssertEqual(BaseSummaryCalculator.summarize("Latest", values: dates)?.displayText, "2025-03-01")
        guard case .duration(let range) = BaseSummaryCalculator.summarize("Range", values: dates) else { return XCTFail("Date range is a duration.") }
        XCTAssertEqual(range.totalMilliseconds / BaseDuration.millisecondsPerDay, 59, accuracy: 0.05)
        let checkboxes: [BaseValue] = [.boolean(true), .boolean(false), .boolean(true), .null]
        XCTAssertEqual(BaseSummaryCalculator.summarize("Checked", values: checkboxes), .number(2))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Unchecked", values: checkboxes), .number(1))
        XCTAssertNil(BaseSummaryCalculator.summarize("Nonsense", values: checkboxes))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Average", values: []), .null)
    }

    func testCustomSummaryFormulasAndUnknownSummaries() throws {
        let result = try run("""
            filters: file.hasTag("task")
            summaries:
              customAverage: 'values.mean().round(3)'
              total: 'values.reduce(acc + value, 0)'
            views:
              - type: table
                name: Estimates
                order: [file.name, estimate, priority, status]
                summaries:
                  estimate: customAverage
                  priority: total
                  status: Median of nothing
            """)
        XCTAssertEqual(result.summaries[.note("estimate")]?.value, .value(.number(2.75)))
        XCTAssertEqual(result.summaries[.note("priority")]?.value, .value(.number(9)))
        guard case .error(let message) = result.summaries[.note("status")]?.value else { return XCTFail("Unknown summaries are errors.") }
        XCTAssertTrue(message.contains("Median of nothing"))
    }

    func testFilterSyntaxErrorsStopTheViewAndRuntimeErrorsAreCounted() throws {
        let broken = try run("filters: 'status == \"todo'\n")
        XCTAssertTrue(broken.rows.isEmpty)
        XCTAssertEqual(broken.problems.count, 1)
        let brokenProblem = try XCTUnwrap(broken.problems.first)
        XCTAssertTrue(brokenProblem.contains("Unterminated"), brokenProblem)
        let partlyFailing = try run("filters: 'file.hasTag(\"task\") && 10 / estimate > 2'\n")
        XCTAssertEqual(Set(names(partlyFailing)), ["Email team", "Fix bug", "Write report"])
        XCTAssertTrue(partlyFailing.problems.isEmpty, "Missing values are empty, not errors: 10 / empty is empty.")
        let failing = try run("filters: 'file.hasTag(\"task\") && estimate.lower() == \"x\"'\n")
        XCTAssertTrue(failing.rows.isEmpty)
        XCTAssertEqual(failing.problems.count, 1)
        let failingProblem = try XCTUnwrap(failing.problems.first)
        XCTAssertTrue(failingProblem.hasPrefix("4 files were left out"), failingProblem)
    }

    func testCellErrorsAreVisiblePerRow() throws {
        let result = try run("""
            filters: file.hasTag("task")
            formulas:
              ratio: '10 / (priority - 1)'
            views:
              - type: table
                name: Ratios
                order: [file.name, formula.ratio, formula.missing]
                sort:
                  - property: file.name
                    direction: ASC
            """)
        let cellsByName = Dictionary(uniqueKeysWithValues: result.rows.map { row in (row.path.stem, row.cells) })
        XCTAssertEqual(cellsByName["Email team"]?[1], .value(.number(10)))
        guard case .error(let message) = cellsByName["Fix bug"]?[1] else { return XCTFail("Division by zero shows in the cell.") }
        XCTAssertTrue(message.contains("zero"))
        guard case .error = cellsByName["Fix bug"]?[2] else { return XCTFail("An undefined formula shows in the cell.") }
    }

    func testThisFiltersForEmbeddedBases() throws {
        let museums = BaseTestRecords.record("Places/Museums.md", yaml: "color: blue\nicon: landmark")
        let landmarks = BaseTestRecords.record("Places/Landmarks.md", yaml: "color: red\nicon: tower")
        let places = [
            BaseTestRecords.record("Places/Louvre.md", yaml: "categories: [\"[[Places]]\"]\ntype: [\"[[Museums]]\"]\ncoordinates: [\"48.8606\", \"2.3376\"]"),
            BaseTestRecords.record("Places/Eiffel Tower.md", yaml: "categories: [\"[[Places]]\"]\ntype: [\"[[Landmarks]]\"]\ncoordinates: [\"48.85837\", \"2.294481\"]"),
            BaseTestRecords.record("Places/Orsay.md", yaml: "categories: [\"[[Places]]\"]\ntype: \"[[Museums]]\"\ncoordinates: 48.86, 2.3266"),
            museums, landmarks,
        ]
        let yaml = """
            filters:
              and:
                - categories.containsAny(link("Places"))
            formulas:
              Type icon: list(type)[0].asFile().properties.icon
              Type color: list(type)[0].asFile().properties.color
            views:
              - type: map
                name: Type map
                filters:
                  and:
                    - list(type).contains(this)
                order: [file.name]
                coordinates: note.coordinates
                markerIcon: formula.Type icon
                markerColor: formula.Type color
                center: this.center
              - type: map
                name: All
                coordinates: note.coordinates
                markerIcon: formula.Type icon
                markerColor: formula.Type color
                center: "[48.85, 2.35]"
            """
        let embedded = try run(yaml, records: places, this: museums)
        XCTAssertEqual(Set(names(embedded)), ["Louvre", "Orsay"])
        let louvre = try XCTUnwrap(embedded.rows.first { row in row.path.stem == "Louvre" })
        XCTAssertEqual(louvre.presentation.coordinate, BaseCoordinate(latitude: 48.8606, longitude: 2.3376))
        XCTAssertEqual(louvre.presentation.markerIcon, "landmark")
        XCTAssertEqual(louvre.presentation.markerColor, "blue")
        XCTAssertEqual(embedded.rows.first { row in row.path.stem == "Orsay" }?.presentation.coordinate, BaseCoordinate(latitude: 48.86, longitude: 2.3266))
        XCTAssertNil(embedded.mapCenter)
        XCTAssertEqual(embedded.problems.count, 1, "An unusable center is reported.")
        let all = try run(yaml, view: 1, records: places, this: museums)
        XCTAssertEqual(Set(names(all)), ["Louvre", "Eiffel Tower", "Orsay"])
        XCTAssertEqual(all.mapCenter, BaseCoordinate(latitude: 48.85, longitude: 2.35))
        XCTAssertEqual(all.rows.first { row in row.path.stem == "Eiffel Tower" }?.presentation.markerColor, "red")
    }

    func testCoordinatesAcceptTheMapsPluginFormats() {
        XCTAssertEqual(BaseCoordinate(value: .list([.string("34.13956"), .string("-118.38710")])), BaseCoordinate(latitude: 34.13956, longitude: -118.3871))
        XCTAssertEqual(BaseCoordinate(value: .list([.number(1), .number(2)])), BaseCoordinate(latitude: 1, longitude: 2))
        XCTAssertEqual(BaseCoordinate(value: .string("34.13956,-118.38710")), BaseCoordinate(latitude: 34.13956, longitude: -118.3871))
        XCTAssertEqual(BaseCoordinate(value: .string("[34.1, -118.3]")), BaseCoordinate(latitude: 34.1, longitude: -118.3))
        XCTAssertNil(BaseCoordinate(value: .string("91, 0")), "Latitudes beyond ±90 are rejected.")
        XCTAssertNil(BaseCoordinate(value: .list([.string("north")])))
        XCTAssertNil(BaseCoordinate(value: .null))
    }

    func testCardCoversFromLinksPathsURLsAndColors() throws {
        let records = [
            BaseTestRecords.record("Books/A.md", yaml: "cover: \"[[a.jpg]]\""),
            BaseTestRecords.record("Books/B.md", yaml: "cover: \"#F54927\""),
            BaseTestRecords.record("Books/C.md", yaml: "cover: https://example.com/c.png"),
            BaseTestRecords.record("Books/D.md", yaml: "cover: Books/images/d.png"),
            BaseTestRecords.record("Books/E.md", yaml: "cover: \"[[Notes]]\""),
            BaseTestRecords.record("Books/F.md", links: [BaseTestRecords.wikiLink("a.jpg", isEmbed: true)]),
            BaseTestRecords.record("Books/images/a.jpg"),
            BaseTestRecords.record("Books/images/d.png"),
            BaseTestRecords.record("Notes.md"),
        ]
        let result = try run("""
            filters: file.ext == "md" && file.inFolder("Books")
            formulas:
              cover: if(cover, cover, file.embeds[0])
            views:
              - type: cards
                name: Covers
                image: formula.cover
            """, records: records)
        let covers = Dictionary(uniqueKeysWithValues: result.rows.map { row in (row.path.stem, row.presentation.coverImage) })
        XCTAssertEqual(covers["A"], .vaultFile(try VaultPath("Books/images/a.jpg")))
        XCTAssertEqual(covers["B"], .color("#F54927"))
        XCTAssertEqual(covers["C"], .remote(try XCTUnwrap(URL(string: "https://example.com/c.png"))))
        XCTAssertEqual(covers["D"], .vaultFile(try VaultPath("Books/images/d.png")))
        XCTAssertEqual(covers["E"], .some(nil), "A note is not an image.")
        XCTAssertEqual(covers["F"], .vaultFile(try VaultPath("Books/images/a.jpg")), "The first embed works as a cover, as in Obsidian.")
    }

    func testPrefilterExtractsOnlyNecessaryConditions() throws {
        let definition = try BaseDefinition.parse("""
            filters:
              and:
                - file.inFolder("Courses/") && file.hasTag("#lecture", "exam")
                - 'status == "done"'
                - file.ext == "md"
                - file.hasLink(this.file)
                - or:
                    - file.hasTag("never-required")
                - not:
                    - file.hasProperty("draft")
                - course.contains("EE")
                - 'priority != 3'
                - file.hasProperty(this.propertyName)
            """)
        let thisRecord = BaseTestRecords.record("Courses/Index.md", yaml: "propertyName: topic")
        let prefilter = BaseRecordPrefilter.extract(from: [definition.filters].compactMap { filter in filter }, definition: definition,
                                                    environment: BaseTestRecords.environment(), thisRecord: thisRecord)
        XCTAssertEqual(prefilter.requirements, [
            .inAnyFolder(["Courses"]), .hasAnyTag(["lecture", "exam"]), .hasAnyProperty(["status"]), .hasAnyExtension(["md"]),
            .linksTo(.path(try VaultPath("Courses/Index.md"))), .hasAnyProperty(["course"]), .hasAnyProperty(["topic"]),
        ])
        let unfiltered = BaseRecordPrefilter.extract(from: [.or([.expression("file.inFolder(\"A\")"), .expression("file.inFolder(\"B\")")])],
                                                     definition: definition, environment: BaseTestRecords.environment(), thisRecord: nil)
        XCTAssertTrue(unfiltered.requirements.isEmpty, "Alternatives cannot narrow the query.")
    }
}
