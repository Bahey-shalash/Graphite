import XCTest
import GraphiteCore
@testable import GraphiteIndex

final class BaseIndexTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("BaseVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Courses/EE330"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Places"), withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
    }

    private func write(_ text: String, to relativePath: String) throws {
        try Data(text.utf8).write(to: vault.appendingPathComponent(relativePath))
    }

    private func paths(_ batch: BaseRecordBatch) -> [String] { batch.records.map(\.path.rawValue) }

    func testPropertiesTagsLinksAndDatesAreStoredPerFile() async throws {
        try write("""
            ---
            title: Datapath Subsystems Design
            course: EE330
            pages: 54
            quoted: "007"
            tags:
              - VLSI
              - datapath
            related:
              - "[[4_Logic design]]"
            location:
              city: Lausanne
            ---
            # Datapath
            See [[Adders]] and ![[figure.png]]. #inline
            """, to: "Courses/EE330/Datapath.md")
        try write("# Adders", to: "Courses/EE330/Adders.md")
        try write("# Logic", to: "Courses/EE330/4_Logic design.md")
        _ = try await index.reconcile(root: vault)

        let storedRecord = try await index.baseRecord(at: VaultPath("Courses/EE330/Datapath.md"))
        let record = try XCTUnwrap(storedRecord)
        XCTAssertEqual(record.properties.map(\.key), ["title", "course", "pages", "quoted", "tags", "related", "location"], "Written order is kept.")
        XCTAssertEqual(record.propertyEntry(named: "quoted")?.node, .scalar(text: "007", isPlain: false), "Quoting survives the cache, so declared types still apply.")
        XCTAssertEqual(record.propertyEntry(named: "location")?.node, .mapping([BaseFrontmatterEntry(key: "city", node: .scalar(text: "Lausanne", isPlain: true))]))
        XCTAssertEqual(record.tags, ["VLSI", "datapath", "inline"].sorted())
        XCTAssertEqual(Set(record.links.map(\.target)), ["Adders", "figure.png"])
        XCTAssertEqual(record.links.first { link in link.target == "figure.png" }?.isEmbed, true)
        XCTAssertGreaterThan(record.size, 0)
        XCTAssertLessThanOrEqual(record.createdDate, record.modifiedDate.addingTimeInterval(1))

        let provider = index.baseRecordProvider
        let logicPath = try VaultPath("Courses/EE330/4_Logic design.md")
        XCTAssertEqual(provider.backlinks(to: logicPath).map(\.rawValue), ["Courses/EE330/Datapath.md"], "Links in properties count as backlinks in bases.")
        let noteBacklinks = try await index.backlinks(to: logicPath)
        XCTAssertTrue(noteBacklinks.isEmpty, "The note backlinks panel keeps counting body links only.")
        XCTAssertEqual(provider.resolveLinkTarget("Adders", from: record.path)?.rawValue, "Courses/EE330/Adders.md")
        XCTAssertEqual(provider.record(at: logicPath)?.path, logicPath)
        XCTAssertNil(provider.record(at: try VaultPath("Missing.md")))
    }

    func testRefreshReplacesPropertiesAndRemovesDeletedFiles() async throws {
        let path = try VaultPath("Courses/EE330/Note.md")
        try write("---\nstatus: draft\n---\nBody", to: path.rawValue)
        try await index.refresh(paths: [path], root: vault)
        var record = try await index.baseRecord(at: path)
        XCTAssertEqual(record?.propertyEntry(named: "status")?.node, .scalar(text: "draft", isPlain: true))
        try write("---\nstatus: final\nreviewer: Ana\n---\nBody", to: path.rawValue)
        try await index.refresh(paths: [path], root: vault)
        record = try await index.baseRecord(at: path)
        XCTAssertEqual(record?.properties.map(\.key), ["status", "reviewer"])
        XCTAssertEqual(record?.propertyEntry(named: "status")?.node, .scalar(text: "final", isPlain: true))
        try write("No frontmatter any more", to: path.rawValue)
        try await index.refresh(paths: [path], root: vault)
        record = try await index.baseRecord(at: path)
        XCTAssertEqual(record?.properties, [])
        try FileManager.default.removeItem(at: vault.appendingPathComponent(path.rawValue))
        try await index.refresh(paths: [path], root: vault)
        let removedRecord = try await index.baseRecord(at: path)
        XCTAssertNil(removedRecord)
        let batch = try await index.baseRecords(matching: BaseRecordPrefilter(requirements: [.hasAnyProperty(["status"])]))
        XCTAssertTrue(batch.records.isEmpty, "No property rows outlive their file.")
    }

    func testReconcilePrunesPropertiesOfDeletedFiles() async throws {
        try write("---\nstatus: open\nrelated: \"[[Kept]]\"\n---\n", to: "Deleted.md")
        try write("---\nstatus: open\n---\n", to: "Kept.md")
        _ = try await index.reconcile(root: vault)
        var batch = try await index.baseRecords(matching: BaseRecordPrefilter(requirements: [.hasAnyProperty(["status"])]))
        XCTAssertEqual(paths(batch), ["Deleted.md", "Kept.md"])
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Deleted.md"))
        _ = try await index.reconcile(root: vault)
        batch = try await index.baseRecords(matching: BaseRecordPrefilter(requirements: [.hasAnyProperty(["status"])]))
        XCTAssertEqual(paths(batch), ["Kept.md"])
        XCTAssertTrue(index.baseRecordProvider.backlinks(to: try VaultPath("Kept.md")).isEmpty, "Property links of deleted files are pruned.")
    }

    func testPrefilterRequirementsNarrowTheQuery() async throws {
        try write("---\ntags: [lecture]\nstatus: done\n---\n", to: "Courses/EE330/L1.md")
        try write("---\ntags: [lecture/recorded]\n---\nSee [[Syllabus]]", to: "Courses/EE330/L2.md")
        try write("---\nStatus: done\n---\n#exam", to: "Courses/Exam.md")
        try write("---\nrelated: \"[[Syllabus]]\"\n---\n", to: "Places/Trip.md")
        try write("# Syllabus", to: "Courses/Syllabus.md")
        try write("binary", to: "Courses/EE330/slides.pdf")
        try write("# Other", to: "Courses_Old.md")
        _ = try await index.reconcile(root: vault)

        func query(_ requirements: [BasePrefilterRequirement]) async throws -> [String] {
            paths(try await index.baseRecords(matching: BaseRecordPrefilter(requirements: requirements)))
        }
        let inCourses = try await query([.inAnyFolder(["Courses"])])
        XCTAssertEqual(inCourses, ["Courses/EE330/L1.md", "Courses/EE330/L2.md", "Courses/EE330/slides.pdf", "Courses/Exam.md", "Courses/Syllabus.md"])
        let lectures = try await query([.hasAnyTag(["lecture"])])
        XCTAssertEqual(lectures, ["Courses/EE330/L1.md", "Courses/EE330/L2.md"], "Nested tags match.")
        let exams = try await query([.hasAnyTag(["EXAM", "missing"])])
        XCTAssertEqual(exams, ["Courses/Exam.md"])
        let pdfs = try await query([.hasAnyExtension(["pdf"])])
        XCTAssertEqual(pdfs, ["Courses/EE330/slides.pdf"])
        let withStatus = try await query([.hasAnyProperty(["status"]), .inAnyFolder(["Courses"])])
        XCTAssertEqual(withStatus, ["Courses/EE330/L1.md", "Courses/Exam.md"], "Property names match in any capitalization.")
        let linking = try await query([.linksTo(.path(try VaultPath("Courses/Syllabus.md")))])
        XCTAssertEqual(linking, ["Courses/EE330/L2.md", "Places/Trip.md"], "Body links and property links both count.")
        let linkingByName = try await query([.linksTo(.target("Syllabus"))])
        XCTAssertEqual(linkingByName, linking)
        let unresolvable = try await query([.linksTo(.target("Nowhere")), .hasAnyExtension(["md"])])
        XCTAssertEqual(unresolvable.count, 6, "An unresolvable target does not narrow the query; the evaluator decides.")
        let escaped = try await query([.inAnyFolder(["Course_"])])
        XCTAssertTrue(escaped.isEmpty, "LIKE wildcards in folder names are escaped.")
    }

    func testQueriesAreBoundedAndReportTruncation() async throws {
        let files = try (0..<30).map { number in
            IndexedFile(path: try VaultPath(String(format: "Bulk/Note %02d.md", number)), size: 10, modified: .now, markdown: "---\nrank: \(number)\n---\n")
        }
        try await index.update(files, generation: "bulk")
        let batch = try await index.baseRecords(matching: BaseRecordPrefilter(), limit: 10)
        XCTAssertEqual(batch.records.count, 10)
        XCTAssertEqual(batch.candidateCount, 30)
        XCTAssertTrue(batch.isTruncated)
        XCTAssertEqual(batch.records.first?.path.rawValue, "Bulk/Note 00.md", "Truncation is deterministic, in path order.")
        let complete = try await index.baseRecords(matching: BaseRecordPrefilter(), limit: 30)
        XCTAssertFalse(complete.isTruncated)
        let clamped = try await index.baseRecords(matching: BaseRecordPrefilter(), limit: 0)
        XCTAssertEqual(clamped.records.count, 1, "Limits are clamped to at least one record.")
    }

    /// A base evaluated end to end over index records, with `this` as the embedding note.
    func testBaseRunsOverIndexRecordsWithTheIndexProvider() async throws {
        try write("---\ncolor: blue\n---\n", to: "Places/Museums.md")
        try write("---\ncolor: red\n---\n", to: "Places/Landmarks.md")
        try write("---\ncategories: [\"[[Places]]\"]\ntype: [\"[[Museums]]\"]\ncoordinates: [\"48.8606\", \"2.3376\"]\n---\n", to: "Places/Louvre.md")
        try write("---\ncategories: [\"[[Places]]\"]\ntype: [\"[[Landmarks]]\"]\ncoordinates: [\"48.85837\", \"2.294481\"]\n---\n", to: "Places/Eiffel Tower.md")
        try write("# Places", to: "Places.md")
        _ = try await index.reconcile(root: vault)
        let definition = try BaseDefinition.parse("""
            filters:
              and:
                - categories.containsAny(link("Places"))
            formulas:
              Type color: list(type)[0].asFile().properties.color
            views:
              - type: map
                name: This type
                filters:
                  and:
                    - list(type).contains(this)
                coordinates: note.coordinates
                markerColor: formula.Type color
              - type: map
                name: All
                coordinates: note.coordinates
                markerColor: formula.Type color
            """)
        let storedThisRecord = try await index.baseRecord(at: VaultPath("Places/Museums.md"))
        let thisRecord = try XCTUnwrap(storedThisRecord)
        let environment = BaseEvaluationEnvironment()
        let filters = [definition.filters, definition.views[0].filters].compactMap { filter in filter }
        let prefilter = BaseRecordPrefilter.extract(from: filters, definition: definition, environment: environment, thisRecord: thisRecord)
        XCTAssertEqual(prefilter.requirements, [.hasAnyProperty(["categories"])])
        let batch = try await index.baseRecords(matching: prefilter)
        XCTAssertEqual(paths(batch), ["Places/Eiffel Tower.md", "Places/Louvre.md"])
        let provider = index.baseRecordProvider
        let (thisTypeResult, allResult) = await Task.detached {
            let engine = BaseQueryEngine(definition: definition, environment: environment, thisRecord: thisRecord, provider: provider)
            return (engine.run(viewIndex: 0, records: batch.records), engine.run(viewIndex: 1, records: batch.records))
        }.value
        XCTAssertEqual(thisTypeResult.rows.map(\.path.rawValue), ["Places/Louvre.md"])
        XCTAssertEqual(thisTypeResult.rows.first?.presentation.markerColor, "blue")
        XCTAssertEqual(thisTypeResult.rows.first?.presentation.coordinate?.latitude, 48.8606)
        let eiffelTower = allResult.rows.first { row in row.path.stem == "Eiffel Tower" }
        XCTAssertEqual(eiffelTower?.presentation.markerColor, "red", "asFile() reads a note outside the query through the index.")
    }
}
