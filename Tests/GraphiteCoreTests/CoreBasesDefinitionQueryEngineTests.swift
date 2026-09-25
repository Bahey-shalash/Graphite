import XCTest
@testable import GraphiteCore

/// Regressions for running a base: reading property values, sorting, grouping,
/// summaries, covers, map coordinates and the index pre-filter.
final class CoreBasesDefinitionQueryEngineTests: XCTestCase {
    private let environment = BaseTestRecords.environment()

    private func value(_ yaml: String) -> BaseValue? {
        guard let node = BaseFrontmatter.entries(fromYAML: yaml)?.first?.node else { return nil }
        return BaseFrontmatter.value(of: node, declaredType: nil, source: nil, calendar: environment.calendar)
    }

    private func run(_ yaml: String, records: [BaseFileRecord], sortOverride: [BaseSortKey]? = nil) throws -> BaseQueryResult {
        let definition = try BaseDefinition.parse(yaml)
        return BaseQueryEngine(definition: definition, environment: environment, thisRecord: nil).run(viewIndex: 0, records: records, sortOverride: sortOverride)
    }

    // MARK: Property values

    func testTimestampsWithAnOffsetAreDates() throws {
        guard case .date(let utcDate)? = value("due: 2025-01-01T10:00:00Z") else { return XCTFail("A UTC timestamp is a date.") }
        guard case .date(let offsetDate)? = value("due: 2025-01-01T12:00:00+02:00") else { return XCTFail("A timestamp with an offset is a date.") }
        XCTAssertEqual(utcDate.date, offsetDate.date)
        XCTAssertEqual(utcDate.date, Date(timeIntervalSince1970: 1_735_725_600))
        guard case .date? = value("due: \"2025-01-01T10:00:00.250-0530\"") else { return XCTFail("Quoted timestamps with an offset are dates too.") }
        XCTAssertEqual(value("due: 2025-01-01Z"), .string("2025-01-01Z"), "An offset needs a time.")
    }

    func testTrailingLineBreaksKeepNumbersAndDatesAsText() {
        for text in ["12\n", "12\r\n", "2024-01-01\n", "2024-01-01T10:00Z\n"] {
            for isPlain in [true, false] {
                let readValue = BaseFrontmatter.value(of: .scalar(text: text, isPlain: isPlain), declaredType: nil, source: nil, calendar: environment.calendar)
                XCTAssertEqual(readValue, .string(text), "\(text.debugDescription) is text.")
            }
        }
        XCTAssertEqual(value("pages: 12"), .number(12))
        XCTAssertEqual(value("pages: -.5e2"), .number(-50))
        guard case .date? = value("due: 2024-01-01") else { return XCTFail("A date without a line break is a date.") }
    }

    // MARK: Engine

    func testADefinitionWithoutViewsRunsAsATable() throws {
        let result = BaseQueryEngine(definition: BaseDefinition(), environment: environment, thisRecord: nil)
            .run(viewIndex: 3, records: [BaseTestRecords.record("Note.md")])
        XCTAssertEqual(result.view.type, .table)
        XCTAssertEqual(result.rows.map(\.path.rawValue), ["Note.md"])
    }

    func testMixedValuesSortTheSameWhateverTheLoadOrder() throws {
        let records = [
            BaseTestRecords.record("A.md", yaml: "value: 5"),
            BaseTestRecords.record("B.md", yaml: "value: 3a"),
            BaseTestRecords.record("C.md", yaml: "value: \"[[4]]\""),
            BaseTestRecords.record("D.md", yaml: "value: 1"),
        ]
        let permutations = [[0, 1, 2, 3], [2, 1, 0, 3], [1, 2, 3, 0], [3, 0, 2, 1], [2, 0, 1, 3], [1, 3, 0, 2]]
        for direction in [BaseSortDirection.ascending, .descending] {
            let orders = try permutations.map { permutation in
                try run("views: [{type: table, name: T}]", records: permutation.map { index in records[index] },
                        sortOverride: [BaseSortKey(property: .note("value"), direction: direction)]).rows.map(\.path.rawValue)
            }
            XCTAssertEqual(Set(orders).count, 1, "One order for every load order: \(orders)")
            XCTAssertEqual(orders.first, direction == .ascending ? ["D.md", "A.md", "B.md", "C.md"] : ["C.md", "B.md", "A.md", "D.md"],
                           "Numbers come before text and links, which compare by their text.")
        }
    }

    func testTextImagesAndLinksSortByOneRule() {
        let values: [BaseValue] = [.string("a100"), .string("a9"), .image("a50"), .icon("a70"), .link(BaseLink(target: "a8")), .number(3)]
        func isAscending(_ leftValue: BaseValue, _ rightValue: BaseValue) -> Bool {
            BaseQueryEngine.compareForSorting(leftValue, rightValue, direction: .ascending) == .orderedAscending
        }
        for first in values {
            for second in values where isAscending(first, second) {
                XCTAssertFalse(isAscending(second, first), "\(first) and \(second)")
                for third in values where isAscending(second, third) {
                    XCTAssertTrue(isAscending(first, third), "\(first) < \(second) < \(third) must give \(first) < \(third).")
                }
            }
        }
    }

    func testGroupsOfNumericTextFollowTheSortOrder() throws {
        let records = ["10", "9", "2"].map { chapter in BaseTestRecords.record("Chapter \(chapter).md", yaml: "chapter: \"\(chapter)\"") }
        let yaml = """
            views:
              - type: table
                name: Chapters
                groupBy:
                  property: chapter
                  direction: ASC
            """
        let groups = try run(yaml, records: records).groups
        XCTAssertEqual(groups.compactMap { group in group.key?.value?.displayText }, ["2", "9", "10"])
        let sortedRows = try run(yaml, records: records, sortOverride: [BaseSortKey(property: .note("chapter"), direction: .ascending)])
        XCTAssertEqual(sortedRows.rows.map(\.path.rawValue), ["Chapter 2.md", "Chapter 9.md", "Chapter 10.md"])
    }

    func testLinksToOneNoteShareAGroupAndCountOnceAsUnique() throws {
        let records = [
            BaseTestRecords.record("People/Ann.md"),
            BaseTestRecords.record("People/Bob.md"),
            BaseTestRecords.record("Tasks/One.md", yaml: "owner: \"[[Ann]]\""),
            BaseTestRecords.record("Tasks/Two.md", yaml: "owner: \"[[People/Ann|Annie]]\""),
            BaseTestRecords.record("Tasks/Three.md", yaml: "owner: \"[[Bob]]\""),
        ]
        let result = try run("""
            filters: file.inFolder("Tasks")
            views:
              - type: table
                name: Tasks
                order: [file.name, owner]
                groupBy:
                  property: owner
                  direction: ASC
                summaries:
                  owner: Unique
            """, records: records)
        XCTAssertEqual(result.groups.map { group in group.rows.map(\.path.rawValue).sorted() }, [["Tasks/One.md", "Tasks/Two.md"], ["Tasks/Three.md"]])
        XCTAssertEqual(result.summaries[.note("owner")]?.value, .value(.number(2)))
    }

    func testUniqueIgnoresLinkLabels() {
        let links: [BaseValue] = [.link(BaseLink(target: "Ann")), .link(BaseLink(target: "Ann", display: "Annie")), .link(BaseLink(target: "ann.md"))]
        XCTAssertEqual(BaseSummaryCalculator.summarize("Unique", values: links), .number(1))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Unique", values: links + [.link(BaseLink(target: "Bob"))]), .number(2))
        XCTAssertEqual(BaseSummaryCalculator.summarize("Unique", values: [.string("Ann"), .link(BaseLink(target: "Ann"))]), .number(2),
                       "Text and a link stay different values.")
    }

    // MARK: Covers and coordinates

    func testCoversLoadOnlyFromTheWeb() throws {
        let covers = [
            "file": "\"[x](file:///etc/passwd.png)\"",
            "ftp": "\"[x](ftp://host/a.png)\"",
            "javascript": "\"[x](javascript://alert(1))\"",
            "web": "\"[x](https://example.com/a.png)\"",
            "color": "\"#ff00aa\"",
            "colorWithLineBreak": "\"#fff\\n\"",
        ]
        let records = covers.map { name, cover in BaseTestRecords.record("\(name).md", yaml: "cover: \(cover)") }
        let result = try run("""
            views:
              - type: cards
                name: Cards
                image: cover
            """, records: records)
        let coversByName = Dictionary(uniqueKeysWithValues: result.rows.map { row in (row.path.stem, row.presentation.coverImage) })
        XCTAssertEqual(coversByName["file"], .some(nil))
        XCTAssertEqual(coversByName["ftp"], .some(nil))
        XCTAssertEqual(coversByName["javascript"], .some(nil))
        XCTAssertEqual(coversByName["web"], .remote(try XCTUnwrap(URL(string: "https://example.com/a.png"))))
        XCTAssertEqual(coversByName["color"], .color("#ff00aa"))
        XCTAssertEqual(coversByName["colorWithLineBreak"], .some(nil))
    }

    func testCoordinateTextNeedsExactlyTwoParts() {
        XCTAssertNil(BaseCoordinate(value: .string("48,85, 2,35")), "Decimal commas are not read as a coordinate.")
        XCTAssertNil(BaseCoordinate(value: .string("1, 2, 3")))
        XCTAssertNil(BaseCoordinate(value: .string("48.85")))
        XCTAssertEqual(BaseCoordinate(value: .string("48.85, 2.35")), BaseCoordinate(latitude: 48.85, longitude: 2.35))
        XCTAssertEqual(BaseCoordinate(value: .string("[48.85, 2.35]")), BaseCoordinate(latitude: 48.85, longitude: 2.35))
    }

    // MARK: Pre-filter

    private func prefilter(_ filters: [String]) -> BaseRecordPrefilter {
        BaseRecordPrefilter.extract(from: [.and(filters.map(BaseFilter.expression))], definition: BaseDefinition(), environment: environment, thisRecord: nil)
    }

    func testEmptyExtensionDoesNotNarrowTheQuery() {
        XCTAssertEqual(prefilter(["file.ext == \"\""]).requirements, [])
        XCTAssertEqual(prefilter(["file.ext == \"pdf\""]).requirements, [.hasAnyExtension(["pdf"])])
        let readme = BaseTestRecords.record("README")
        let evaluator = BaseEvaluator(formulas: [], environment: environment, thisRecord: nil, knownRecords: [readme])
        XCTAssertEqual(try evaluator.matches(.expression("file.ext == \"\""), record: readme), true)
    }

    func testPropertyEqualityToPlainTextNarrowsByStoredText() {
        XCTAssertEqual(prefilter(["status == \"reading\"", "\" Next up \" == note.stage", "note[\"owner\"] == \"Ann\""]).propertyTextRequirements, [
            BasePropertyTextRequirement(key: "status", text: "reading"),
            BasePropertyTextRequirement(key: "stage", text: "Next up"),
            BasePropertyTextRequirement(key: "owner", text: "Ann"),
        ])
        for filter in ["pages == \"10\"", "pages == \"1e1\"", "pages == \"nan\"", "pages == \" 7 \"", "folder == \"a/b\"", "name == \"Zoë\"",
                       "status == \"\"", "status != \"reading\"", "status == 3", "file.name == \"reading\""] {
            XCTAssertEqual(prefilter([filter]).propertyTextRequirements, [], filter)
        }
        let alternatives = BaseRecordPrefilter.extract(from: [.or([.expression("status == \"reading\"")])], definition: BaseDefinition(), environment: environment, thisRecord: nil)
        XCTAssertEqual(alternatives.propertyTextRequirements, [])
    }

    /// Every value `==` treats as equal to the text holds that text in its stored JSON,
    /// ignoring ASCII case, or holds a percent sign.
    func testValuesEqualToThePropertyTextContainItWhenStored() throws {
        let matchingValues = ["reading", "\"[[Reading]]\"", "\"[[reading.md|label]]\"", "\"[[ Reading#Part ]]\"", "\"[x](reading)\"", "\"[x](read%69ng)\""]
        let evaluator = BaseEvaluator(formulas: [], environment: environment, thisRecord: nil)
        let encoder = JSONEncoder()
        for yamlValue in matchingValues {
            let record = BaseTestRecords.record("Note.md", yaml: "status: \(yamlValue)")
            XCTAssertTrue(try evaluator.matches(.expression("status == \"reading\""), record: record), "\(yamlValue) equals the text.")
            let node = try XCTUnwrap(record.properties.first?.node)
            let storedText = try XCTUnwrap(String(data: try encoder.encode(node), encoding: .utf8))
            XCTAssertTrue(storedText.lowercased().contains("reading") || storedText.contains("%"), storedText)
        }
    }

    // MARK: In-memory provider

    func testInMemoryProviderResolvesAliasesAndCountsPropertyLinks() throws {
        let annPath = try VaultPath("People/Ann Lee.md")
        let records = [
            BaseTestRecords.record("People/Ann Lee.md", yaml: "aliases: [Ann]"),
            BaseTestRecords.record("People/Bob.md", yaml: "alias: Robert"),
            BaseTestRecords.record("Tasks/Body.md", links: [BaseTestRecords.wikiLink("Ann")]),
            BaseTestRecords.record("Tasks/Property.md", yaml: "owner: \"[[Ann Lee]]\""),
            BaseTestRecords.record("Tasks/Unrelated.md", yaml: "owner: \"[[Bob]]\""),
        ]
        let provider = BaseInMemoryRecordProvider(records: records)
        XCTAssertEqual(provider.resolveLinkTarget("Ann", from: try VaultPath("Tasks/Body.md")), annPath)
        XCTAssertEqual(provider.resolveLinkTarget("robert", from: .root), try VaultPath("People/Bob.md"))
        XCTAssertEqual(provider.backlinks(to: annPath), [try VaultPath("Tasks/Body.md"), try VaultPath("Tasks/Property.md")])

        let ambiguous = BaseInMemoryRecordProvider(records: records + [BaseTestRecords.record("Other/Ann.md")])
        XCTAssertNil(ambiguous.resolveLinkTarget("Ann", from: .root), "A name and another note's alias make the link ambiguous, as in the index.")
    }
}

