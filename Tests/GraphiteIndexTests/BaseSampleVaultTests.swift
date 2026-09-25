import XCTest
import GraphiteCore
@testable import GraphiteIndex

/// Runs every base in `Tests/BaseSampleVault` through a real index, the way the app does:
/// pre-filter in SQL, load bounded records, evaluate off the main actor.
final class BaseSampleVaultTests: XCTestCase {
    private var vault: URL!
    private var cacheDirectory: URL!
    private var index: VaultIndex!
    private var store: VaultStore!

    private static var sampleVaultLocation: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BaseSampleVault")
    }

    override func setUp() async throws {
        // A copy, so nothing a test does can touch the checked-in sample.
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("BaseSample-\(UUID().uuidString)")
        cacheDirectory = vault.appendingPathExtension("cache")
        try FileManager.default.copyItem(at: Self.sampleVaultLocation, to: vault)
        index = try VaultIndex(databaseURL: cacheDirectory.appendingPathComponent("index.sqlite"))
        store = VaultStore(root: vault)
        let report = try await index.reconcile(root: vault)
        XCTAssertTrue(report.failedPaths.isEmpty, "\(report.failedPaths)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    /// 2026-09-23 12:00 in the device time zone.
    private var environment: BaseEvaluationEnvironment {
        get async {
            let calendar = BaseDateFormatting.displayCalendar
            let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12)) ?? .now
            return BaseEvaluationEnvironment(now: now, calendar: calendar, declaredTypes: await store.propertyTypes())
        }
    }

    private enum SampleSource {
        case file(VaultPath)
        case inline(String)
    }

    private func run(_ source: SampleSource, viewName: String, this contextPath: VaultPath? = nil) async throws -> BaseQueryResult {
        let yaml: String
        let defaultContext: VaultPath
        switch source {
        case .file(let path):
            yaml = try String(contentsOf: path.url(in: vault), encoding: .utf8)
            defaultContext = path
        case .inline(let text):
            yaml = text
            defaultContext = .root
        }
        let definition = try BaseDefinition.parse(yaml)
        XCTAssertTrue(definition.issues.isEmpty, "\(definition.issues)")
        let viewIndex = try XCTUnwrap(definition.views.firstIndex { view in view.name == viewName }, viewName)
        let context = contextPath ?? defaultContext
        let storedThisRecord = try await index.baseRecord(at: context)
        let thisRecord = storedThisRecord ?? BaseFileRecord(path: context, size: 0, createdDate: .now, modifiedDate: .now)
        let environment = await environment
        let view = definition.views[viewIndex]
        let prefilter = BaseRecordPrefilter.extract(from: [definition.filters, view.filters].compactMap { filter in filter }, definition: definition,
                                                    environment: environment, thisRecord: thisRecord)
        let batch = try await index.baseRecords(matching: prefilter)
        XCTAssertFalse(batch.isTruncated)
        let provider = index.baseRecordProvider
        return await Task.detached {
            BaseQueryEngine(definition: definition, environment: environment, thisRecord: thisRecord, provider: provider).run(viewIndex: viewIndex, records: batch.records)
        }.value
    }

    private func cells(_ result: BaseQueryResult, _ property: BasePropertyIdentifier) -> [String: BaseCellValue] {
        guard let position = result.columns.firstIndex(where: { column in column.property == property }) else { return [:] }
        return Dictionary(uniqueKeysWithValues: result.rows.map { row in (row.path.stem, row.cells[position]) })
    }

    func testBooksLibraryTableSortsFormatsAndSummarizes() async throws {
        let result = try await run(.file(VaultPath("Books.base")), viewName: "Library")
        XCTAssertEqual(result.rows.map(\.path.stem), ["Dune", "Gödel, Escher, Bach", "The Left Hand of Darkness", "Middlemarch", "The Structure of Scientific Revolutions"])
        XCTAssertEqual(result.columns.map(\.displayName), ["", "file name", "Author", "genre", "pages", "Rating", "Est. time", "finished", "per_page"])
        XCTAssertEqual(cells(result, .formula("reading_time"))["Dune"], .value(.string("13.7 h")))
        XCTAssertEqual(cells(result, .formula("status_icon"))["Middlemarch"], .value(.string("📚")))
        guard case .error = cells(result, .formula("per_page"))["Gödel, Escher, Bach"] else { return XCTFail("777 pages divide by zero in this sample formula.") }
        XCTAssertEqual(result.summaries[.note("pages")]?.value, .value(.number(2_637)))
        XCTAssertEqual(result.summaries[.note("rating")]?.value, .value(.number(4.4)))
        XCTAssertEqual(result.summaries[.note("finished")]?.value.value?.displayText, "2025-03-14")
        XCTAssertTrue(result.problems.isEmpty, "\(result.problems)")
    }

    func testBooksGroupedGalleryAndList() async throws {
        let byStatus = try await run(.file(VaultPath("Books.base")), viewName: "By status")
        XCTAssertEqual(byStatus.groups.map { group in group.key?.value?.displayText ?? "" }, ["done", "dropped", "reading", "to-read"])
        XCTAssertEqual(byStatus.groups[0].summaries[.note("pages")]?.value, .value(.number(594.5)))
        let gallery = try await run(.file(VaultPath("Books.base")), viewName: "Gallery")
        let covers = gallery.rows.compactMap(\.presentation.coverImage)
        XCTAssertEqual(covers.count, 5)
        XCTAssertTrue(covers.contains(.vaultFile(try VaultPath("Books/covers/dune.png"))), "Wikilinks to images resolve by name through the index.")
        let readingList = try await run(.file(VaultPath("Books.base")), viewName: "Reading list")
        XCTAssertEqual(readingList.rows.count, 4, "The dropped book is filtered out by the view.")
    }

    func testPlacesMapUsesCoordinatesColorsAndThis() async throws {
        let map = try await run(.file(VaultPath("Places.base")), viewName: "Map")
        XCTAssertEqual(map.rows.count, 7)
        XCTAssertEqual(map.rows.compactMap(\.presentation.coordinate).count, 6, "The place without coordinates has no marker.")
        let eiffelTower = try XCTUnwrap(map.rows.first { row in row.path.stem == "Eiffel Tower" })
        XCTAssertEqual(eiffelTower.presentation.coordinate, BaseCoordinate(latitude: 48.85837, longitude: 2.294481))
        XCTAssertEqual(eiffelTower.presentation.markerColor, "red")
        XCTAssertEqual(eiffelTower.presentation.markerIcon, "star")
        XCTAssertEqual(map.rows.first { row in row.path.stem == "Jardin des Plantes" }?.presentation.markerColor, "#2e8b57")
        let museums = try await run(.file(VaultPath("Places.base")), viewName: "Type map", this: VaultPath("Places/Museums.md"))
        XCTAssertEqual(Set(museums.rows.map(\.path.stem)), ["Louvre", "Musée d'Orsay", "Centre Pompidou"])
        XCTAssertEqual(museums.mapCenter, BaseCoordinate(latitude: 48.8605, longitude: 2.34))
        XCTAssertEqual(museums.view.map.embeddedHeight, 360)
        let table = try await run(.file(VaultPath("Places.base")), viewName: "All places")
        XCTAssertEqual(table.summaries[.note("rating")]?.value, .value(.number(4.5)))
        XCTAssertEqual(table.summaries[.note("coordinates")]?.value, .value(.number(1)))
    }

    func testTaskTrackerFromTheDocumentation() async throws {
        let active = try await run(.file(VaultPath("Tasks.base")), viewName: "Active Tasks")
        XCTAssertEqual(active.groups.map { group in group.key?.value?.displayText ?? "" }, ["doing", "todo"])
        let daysUntilDue = cells(active, .formula("days_until_due"))
        XCTAssertEqual(daysUntilDue["Write lab report"], .value(.number(2)))
        XCTAssertEqual(daysUntilDue["Fix testbench"], .value(.number(-3)))
        XCTAssertEqual(daysUntilDue["Plan study group"], .value(.string("")))
        XCTAssertEqual(cells(active, .formula("is_overdue"))["Fix testbench"], .value(.boolean(true)))
        XCTAssertEqual(active.groups[1].summaries[.note("done")]?.value, .value(.number(0)))
        let completed = try await run(.file(VaultPath("Tasks.base")), viewName: "Completed")
        XCTAssertEqual(completed.rows.map(\.path.stem), ["Email the TA"])
    }

    func testCoursesBacklinksAndUnsupportedViews() async throws {
        let lectures = try await run(.file(VaultPath("Courses.base")), viewName: "Lectures")
        XCTAssertEqual(cells(lectures, .formula("backlink_count"))["4_Logic design"], .value(.number(2)), "Links in `related` properties are backlinks.")
        XCTAssertEqual(cells(lectures, .formula("backlink_count"))["12_Datapath subsystems design"], .value(.number(0)))
        let definition = try BaseDefinition.parse(try String(contentsOf: vault.appendingPathComponent("Courses.base"), encoding: .utf8))
        XCTAssertEqual(definition.views[1].type, .unsupported("kanban"))
    }

    func testCodeBlockBaseInsideANote() async throws {
        let note = try String(contentsOf: vault.appendingPathComponent("Books/Reading notes.md"), encoding: .utf8)
        let blockStart = try XCTUnwrap(note.range(of: "```base\n"))
        let blockEnd = try XCTUnwrap(note.range(of: "\n```", range: blockStart.upperBound..<note.endIndex))
        let yaml = String(note[blockStart.upperBound..<blockEnd.lowerBound])
        let result = try await run(.inline(yaml), viewName: "Up next", this: VaultPath("Books/Reading notes.md"))
        XCTAssertEqual(Set(result.rows.map(\.path.stem)), ["The Left Hand of Darkness", "Middlemarch"])
    }
}
