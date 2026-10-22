import XCTest
import GraphiteCore
import GraphiteIndex
import PostgresNIO
import GraphiteTestSupport
@testable import GraphitePostgreSQLMirror

/// Copies against a real PostgreSQL server, read back with SQL; skipped without one
/// (`PostgreSQLTestServer` names what to set). Each test copies into a schema of its own and
/// drops it afterwards.
final class PostgreSQLMirrorServerTests: XCTestCase {
    private var configuration: PostgreSQLMirrorConfiguration!
    private var password = ""
    private var testedDatabases: Set<String> = []
    private let vaultName = "Atlas"
    private let declaredTypes: [String: PropertyType] = ["pages": .number, "date": .date]

    override func setUp() async throws {
        let server = try PostgreSQLTestServer.require()
        password = server.password
        let schemaName = "graphite_test_" + UUID().uuidString.prefix(8).lowercased()
        configuration = PostgreSQLMirrorConfiguration(host: server.host, port: server.port, databaseName: server.databaseName,
                                                      userName: server.userName, schemaName: schemaName, transportSecurity: .off)
    }

    override func tearDown() async throws {
        guard let configuration else { return }
        for databaseName in testedDatabases {
            try? await withConnection(databaseName: databaseName) { connection in
                _ = try await connection.query(PostgresQuery(unsafeSQL: "DROP SCHEMA IF EXISTS \(PostgreSQLMirrorStatements.quotedIdentifier(configuration.schemaName)) CASCADE"),
                                               logger: Self.logger)
            }
        }
    }

    // MARK: A first copy

    func testACopyHoldsTheNotesPropertiesTagsAliasesLinksAndPlaces() async throws {
        let (vault, index) = try await makeVault(Self.atlasNotes)
        let mirror = makeMirror()
        let report = try await mirror.copy(mirroredVault(vault), from: index)
        XCTAssertEqual(report.writtenNoteCount, 4)
        XCTAssertEqual(report.copiedNoteCount, 4)
        XCTAssertTrue(report.hasGeometry)

        let paris = try await row("""
            SELECT jsonb_typeof(properties -> 'pages'), properties ->> 'pages', jsonb_typeof(properties -> 'lu'), properties ->> 'date',
                   properties -> 'auteurs' ->> 1, array_to_string(tags, ','), array_to_string(aliases, ','), latitude::text, longitude::text,
                   ST_AsText(geometry), name, folder
            FROM \(schema).notes WHERE vault = 'Atlas' AND path = 'Voyages/Paris.md'
            """, as: (String, String, String, String, String, String, String, String, String, String, String, String).self)
        XCTAssertEqual(paris.0, "number")
        XCTAssertEqual(paris.1, "12")
        XCTAssertEqual(paris.2, "boolean")
        XCTAssertEqual(paris.3, "2026-10-12")
        XCTAssertEqual(paris.4, "Bob")
        XCTAssertEqual(paris.5, "europe,voyage")
        XCTAssertEqual(paris.6, "Lutèce")
        XCTAssertEqual(paris.7, "48.8566")
        XCTAssertEqual(paris.8, "2.3522")
        XCTAssertEqual(paris.9, "POINT(2.3522 48.8566)")
        XCTAssertEqual(paris.10, "Paris")
        XCTAssertEqual(paris.11, "Voyages")

        let links = try await rows("""
            SELECT link_number, target, coalesce(target_path, '—'), is_embed, is_in_properties FROM \(schema).links
            WHERE vault = 'Atlas' AND source_path = 'Voyages/Paris.md' ORDER BY link_number
            """, as: (Int32, String, String, Bool, Bool).self)
        XCTAssertEqual(links.map(\.1), ["Lausanne", "Inexistante", "photo.png", "Lyon.md"])
        XCTAssertEqual(links.map(\.2), ["Voyages/Lausanne.md", "—", "photo.png", "Lyon.md"], "Links reach files, an unresolved one none.")
        XCTAssertEqual(links.map(\.3), [false, false, true, false])
        let propertyLink = try await row("SELECT target_path, is_in_properties FROM \(schema).links WHERE source_path = 'Voyages/Lausanne.md'",
                                         as: (String, Bool).self)
        XCTAssertEqual(propertyLink.0, "Voyages/Paris.md")
        XCTAssertTrue(propertyLink.1)
        let lines = try await rows("SELECT source_path, ST_NPoints(geometry) FROM \(schema).links_on_map ORDER BY source_path", as: (String, Int32).self)
        XCTAssertEqual(lines.map(\.0), ["Voyages/Lausanne.md", "Voyages/Paris.md"], "Only links between two placed notes are lines.")
        XCTAssertEqual(lines.map(\.1), [2, 2])

        // The typed view: numbers, dates, booleans and lists as such; a value of the wrong
        // kind reads as NULL rather than failing the query.
        let types = try await row("""
            SELECT pg_typeof(pages)::text, pg_typeof(date)::text, pg_typeof(lu)::text, pg_typeof(auteurs)::text, pg_typeof(cours)::text,
                   pg_typeof("tags (property)")::text, pg_typeof(geometry)::text
            FROM \(schema).notes_with_properties LIMIT 1
            """, as: (String, String, String, String, String, String, String).self)
        XCTAssertEqual(types.0, "double precision")
        XCTAssertEqual(types.1, "date")
        XCTAssertEqual(types.2, "boolean")
        XCTAssertEqual(types.3, "text[]")
        XCTAssertEqual(types.4, "text")
        XCTAssertEqual(types.5, "text[]")
        XCTAssertEqual(types.6, "geometry")
        let lyon = try await row("SELECT coalesce(pages::text, 'NULL'), coalesce(date::text, 'NULL'), properties ->> 'pages' FROM \(schema).notes_with_properties WHERE path = 'Lyon.md'",
                                 as: (String, String, String).self)
        XCTAssertEqual(lyon.0, "NULL", "\"douze\" is not a number.")
        XCTAssertEqual(lyon.1, "NULL", "2026-02-30 is not a date.")
        XCTAssertEqual(lyon.2, "douze", "The JSON keeps the value as written.")
        let parisInView = try await row("SELECT pages, date::text, lu, array_to_string(auteurs, ',') FROM \(schema).notes_with_properties WHERE path = 'Voyages/Paris.md'",
                                        as: (Double, String, Bool, String).self)
        XCTAssertEqual(parisInView.0, 12)
        XCTAssertEqual(parisInView.1, "2026-10-12")
        XCTAssertTrue(parisInView.2)
        XCTAssertEqual(parisInView.3, "Alice,Bob")
    }

    // MARK: Later copies

    func testLaterCopiesWriteOnlyWhatChanged() async throws {
        let (vault, index) = try await makeVault(Self.atlasNotes)
        let mirror = makeMirror()
        _ = try await mirror.copy(mirroredVault(vault), from: index)
        let firstCopyNumber = try await copyNumber()

        let unchanged = try await mirror.copy(mirroredVault(vault), from: index)
        XCTAssertEqual([unchanged.writtenNoteCount, unchanged.deletedNoteCount, unchanged.rewrittenLinkSourceCount], [0, 0, 0])
        XCTAssertFalse(unchanged.didConnect, "Nothing changed in the index, so the server was not asked.")
        let rechecked = try await mirror.copy(mirroredVault(vault), from: index, rechecksDatabase: true)
        XCTAssertTrue(rechecked.didConnect)
        XCTAssertEqual(rechecked.writtenNoteCount, 0)
        let unchangedCopyNumber = try await copyNumber()
        XCTAssertEqual(unchangedCopyNumber, firstCopyNumber, "A copy that changes nothing leaves the database as it was.")

        try write("---\ncoordinates: [45.764, 4.8357]\npages: 30\n---\n# Lyon\n", to: "Lyon.md", in: vault)
        _ = try await index.reconcile(root: vault)
        let edited = try await mirror.copy(mirroredVault(vault), from: index)
        XCTAssertEqual(edited.writtenNoteCount, 1)
        let lyon = try await row("SELECT properties ->> 'pages', ST_AsText(geometry) FROM \(schema).notes WHERE path = 'Lyon.md'", as: (String, String).self)
        XCTAssertEqual(lyon.0, "30")
        XCTAssertEqual(lyon.1, "POINT(4.8357 45.764)")

        // Moving Lyon deletes its old row and writes the new one. Paris's link `../Lyon.md` now
        // finds Lyon by name, as the graph finds it, so Paris is written again with its links.
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Archive"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: vault.appendingPathComponent("Lyon.md"), to: vault.appendingPathComponent("Archive/Lyon.md"))
        try FileManager.default.removeItem(at: vault.appendingPathComponent("Notes sans propriétés.md"))
        _ = try await index.reconcile(root: vault)
        let moved = try await mirror.copy(mirroredVault(vault), from: index)
        XCTAssertEqual(moved.deletedNoteCount, 2)
        XCTAssertEqual(moved.writtenNoteCount, 2, "Archive/Lyon.md, and Paris for its link.")
        XCTAssertEqual(moved.copiedNoteCount, 3)
        let paths = try await rows("SELECT path FROM \(schema).notes ORDER BY path", as: String.self)
        XCTAssertEqual(paths, ["Archive/Lyon.md", "Voyages/Lausanne.md", "Voyages/Paris.md"])
        let lyonLink = try await row("SELECT coalesce(target_path, 'NULL') FROM \(schema).links WHERE source_path = 'Voyages/Paris.md' AND target = 'Lyon.md'",
                                     as: String.self)
        XCTAssertEqual(lyonLink, "Archive/Lyon.md")
        let movedCopyNumber = try await copyNumber()
        XCTAssertEqual(movedCopyNumber, firstCopyNumber + 2)
    }

    func testAChangedPropertyTypeRewritesTheNotesWithThatPropertyAndTheView() async throws {
        let (vault, index) = try await makeVault(Self.atlasNotes)
        let mirror = makeMirror()
        _ = try await mirror.copy(mirroredVault(vault), from: index)
        let retyped = try await mirror.copy(mirroredVault(vault, declaredTypes: ["pages": .text, "date": .date]), from: index)
        XCTAssertEqual(retyped.writtenNoteCount, 1, "Paris's 12 becomes text; Lyon's \"douze\" already was, so its row is unchanged.")
        let parisPages = try await row("SELECT jsonb_typeof(properties -> 'pages') FROM \(schema).notes WHERE path = 'Voyages/Paris.md'", as: String.self)
        XCTAssertEqual(parisPages, "string")
        let columnType = try await row("SELECT pg_typeof(pages)::text FROM \(schema).notes_with_properties LIMIT 1", as: String.self)
        XCTAssertEqual(columnType, "text")
    }

    /// Two devices with the same vault: a copy notices the other device's by the copy number,
    /// rather than trusting what it wrote itself. Until its own index changes (or Copy Now),
    /// a device does not ask the server, so the database keeps the other device's copy.
    func testACopyFromAnotherDeviceIsNoticed() async throws {
        let (olderVault, olderIndex) = try await makeVault(["Paris.md": "---\npages: 1\n---\n", "Lyon.md": "# Lyon\n"])
        let (newerVault, newerIndex) = try await makeVault(["Paris.md": "---\npages: 2\n---\n", "Lyon.md": "# Lyon\n"])
        let olderDevice = makeMirror()
        let newerDevice = makeMirror()
        _ = try await newerDevice.copy(mirroredVault(newerVault), from: newerIndex)
        _ = try await olderDevice.copy(mirroredVault(olderVault), from: olderIndex)
        let overwritten = try await row("SELECT properties ->> 'pages' FROM \(schema).notes WHERE path = 'Paris.md'", as: String.self)
        XCTAssertEqual(overwritten, "1")
        let unchanged = try await newerDevice.copy(mirroredVault(newerVault), from: newerIndex)
        XCTAssertFalse(unchanged.didConnect)

        // The newer device's next change: its copy reads the database again, since the copy
        // number moved, and writes Paris back with the changed note.
        try write("# Lyon, revu\n", to: "Lyon.md", in: newerVault)
        _ = try await newerIndex.reconcile(root: newerVault)
        let report = try await newerDevice.copy(mirroredVault(newerVault), from: newerIndex)
        XCTAssertEqual(report.writtenNoteCount, 2)
        let restored = try await row("SELECT properties ->> 'pages' FROM \(schema).notes WHERE path = 'Paris.md'", as: String.self)
        XCTAssertEqual(restored, "2")

        // Copy Now on the older device puts its own copy back without any change in its index.
        let recheck = try await olderDevice.copy(mirroredVault(olderVault), from: olderIndex, rechecksDatabase: true)
        XCTAssertEqual(recheck.writtenNoteCount, 2)
    }

    // MARK: QGIS, failures, servers without PostGIS

    func testACommittedCopyNotifiesQGIS() async throws {
        let (vault, index) = try await makeVault(Self.atlasNotes)
        let mirror = makeMirror()
        let copiedVault = mirroredVault(vault)
        let payload = try await withConnection(databaseName: configuration.databaseName) { connection in
            try await connection.listen(on: "qgis") { notifications in
                // The notification waits in the sequence until it is read.
                _ = try await mirror.copy(copiedVault, from: index)
                let heard = expectation(description: "the copy's notification")
                let reader = Task { () -> String? in
                    defer { heard.fulfill() }
                    for try await notification in notifications { return notification.payload }
                    return nil
                }
                await fulfillment(of: [heard], timeout: 10)
                reader.cancel()
                return try await reader.value
            }
        }
        XCTAssertEqual(payload, "graphite")
    }

    func testAFailedCopyChangesNothingAndSaysWhy() async throws {
        let (vault, index) = try await makeVault(Self.atlasNotes)
        let mirror = makeMirror()
        _ = try await mirror.copy(mirroredVault(vault), from: index)
        // A view of the person's own over the mirror's view keeps it from being replaced.
        try await execute("CREATE VIEW \(schema).my_places AS SELECT path, pages FROM \(schema).notes_with_properties")
        try write("---\npages: 99\n---\n# Lyon\n", to: "Lyon.md", in: vault)
        _ = try await index.reconcile(root: vault)
        do {
            _ = try await mirror.copy(mirroredVault(vault, declaredTypes: ["pages": .text]), from: index)
            XCTFail("The view could not be replaced.")
        } catch {
            guard case .copyRefused(let message) = error as? PostgreSQLMirrorError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("my_places"), message)
        }
        let lyonPages = try await row("SELECT properties ->> 'pages' FROM \(schema).notes WHERE path = 'Lyon.md'", as: String.self)
        XCTAssertEqual(lyonPages, "douze", "The transaction was rolled back.")
        // Once the person's view is gone, the next copy reads the database again and completes.
        try await execute("DROP VIEW \(schema).my_places")
        let retried = try await mirror.copy(mirroredVault(vault, declaredTypes: ["pages": .text]), from: index)
        XCTAssertEqual(retried.writtenNoteCount, 2, "Paris, retyped, and Lyon, edited.")
    }

    func testAWrongPasswordAndAnUnreachableServerAreNamed() async throws {
        do {
            _ = try await PostgreSQLMirror(configuration: configuration, password: "not the password", clock: LiveApplicationClock()).describeServer()
            XCTFail("The password is wrong.")
        } catch {
            guard case .connectionRefused(_, let message) = error as? PostgreSQLMirrorError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("password authentication failed"), message)
        }
        var unreachable = configuration!
        unreachable.port = 1
        do {
            _ = try await PostgreSQLMirror(configuration: unreachable, password: password, clock: LiveApplicationClock()).describeServer()
            XCTFail("Nothing listens on port 1.")
        } catch {
            guard case .unreachable(let server, _) = error as? PostgreSQLMirrorError else { return XCTFail("\(error)") }
            XCTAssertEqual(server, "\(unreachable.host):1")
        }
        let description = try await makeMirror().describeServer()
        XCTAssertFalse(description.version.isEmpty)
        XCTAssertNotNil(description.postGISVersion)
    }

    func testWithoutPostGISNotesKeepTheirLatitudeAndLongitude() async throws {
        configuration.databaseName = try PostgreSQLTestServer.requirePlainDatabaseName()
        let (vault, index) = try await makeVault(Self.atlasNotes)
        let mirror = makeMirror()
        let report = try await mirror.copy(mirroredVault(vault), from: index)
        XCTAssertFalse(report.hasGeometry)
        let description = try await mirror.describeServer()
        XCTAssertNil(description.postGISVersion)
        let paris = try await row("SELECT latitude, longitude FROM \(schema).notes WHERE path = 'Voyages/Paris.md'", as: (Double, Double).self)
        XCTAssertEqual(paris.0, 48.8566)
        XCTAssertEqual(paris.1, 2.3522)
        let objects = try await row("""
            SELECT (SELECT count(*) FROM information_schema.columns WHERE table_schema = '\(configuration.schemaName)' AND column_name = 'geometry'),
                   to_regclass('\(schema).links_on_map') IS NULL, to_regclass('\(schema).notes_with_properties') IS NOT NULL
            """, as: (Int64, Bool, Bool).self)
        XCTAssertEqual(objects.0, 0)
        XCTAssertTrue(objects.1)
        XCTAssertTrue(objects.2)
    }

    // MARK: Scale

    /// A synthetic vault of `GRAPHITE_POSTGRESQL_BENCHMARK_NOTES` notes, each with five
    /// properties, a third of them placed, and two links: the first copy, a copy with nothing
    /// changed, and a copy after one note changed. Prints the times; skipped without the variable.
    func testASyntheticVaultCopiesAndCopiesAgain() async throws {
        let noteCount = try PostgreSQLTestServer.requireBenchmarkNoteCount()
        let directory = try TemporaryVault.make(prefix: "MirrorBenchmark", for: self).root
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        func lecture(_ noteNumber: Int, pages: Int) throws -> IndexedFile {
            var frontmatter = "course: Course \(noteNumber % 100)\npages: \(pages)\ndate: 2026-\(String(format: "%02d", noteNumber % 12 + 1))-\(String(format: "%02d", noteNumber % 28 + 1))\ntags: [engineering, lecture]\n"
            if noteNumber % 3 == 0 { frontmatter += "coordinates: [\(Double(noteNumber % 180) - 90), \(Double(noteNumber % 360) - 180)]\n" }
            let markdown = "---\n\(frontmatter)---\n# Lecture \(noteNumber)\n\nSee [[Lecture \(max(0, noteNumber - 1))]] and [[Lecture \(noteNumber + 1)]]. #signal\n"
            return IndexedFile(path: try VaultPath("Course \(noteNumber % 100)/Lecture \(noteNumber).md"), size: markdown.utf8.count, modified: .now, markdown: markdown)
        }
        for batchStart in stride(from: 0, to: noteCount, by: 256) {
            try await index.update(try (batchStart..<min(batchStart + 256, noteCount)).map { noteNumber in try lecture(noteNumber, pages: noteNumber % 300) },
                                   generation: "benchmark")
        }
        let mirror = makeMirror()
        let vault = MirroredVault(name: vaultName, declaredPropertyTypes: [:], placePropertyNames: PlacedNote.defaultPropertyNames)
        let first = try await mirror.copy(vault, from: index)
        XCTAssertEqual(first.writtenNoteCount, noteCount)
        let unchanged = try await mirror.copy(vault, from: index)
        XCTAssertEqual(unchanged.writtenNoteCount, 0)
        let rechecked = try await mirror.copy(vault, from: index, rechecksDatabase: true)
        XCTAssertEqual(rechecked.writtenNoteCount, 0)
        try await index.update([try lecture(7, pages: 999)], generation: "benchmark")
        let edited = try await mirror.copy(vault, from: index)
        XCTAssertEqual(edited.writtenNoteCount, 1)
        // A new note: a file came, so every note's links are resolved again; only it is written.
        try await index.update([try lecture(noteCount, pages: 1)], generation: "benchmark")
        let added = try await mirror.copy(vault, from: index)
        XCTAssertEqual(added.writtenNoteCount, 2, "The new note, and the last note, whose link to it now resolves.")
        // A new mirror, as after the app starts again: every note is read to compare, none written.
        let restarted = try await makeMirror().copy(vault, from: index)
        XCTAssertEqual(restarted.writtenNoteCount, 0)
        let placedCount = try await row("SELECT count(geometry) FROM \(schema).notes", as: Int64.self)
        XCTAssertEqual(placedCount, Int64((noteCount + 1 + 2) / 3))
        print(String(format: "Mirror benchmark, %d notes: first copy %.2f s; unchanged %.3f s; Copy Now unchanged %.2f s; one note changed %.2f s; one note added %.2f s; after a restart %.2f s",
                     noteCount, first.elapsedSeconds, unchanged.elapsedSeconds, rechecked.elapsedSeconds, edited.elapsedSeconds, added.elapsedSeconds, restarted.elapsedSeconds))
    }

    // MARK: Helpers

    /// Four notes and a picture: two placed notes linking to each other (one in a property),
    /// one with values of the wrong kind, and one without properties.
    private static let atlasNotes: [String: String] = [
        "Voyages/Paris.md": """
            ---
            coordinates: [48.8566, 2.3522]
            cours: Géographie
            pages: 12
            lu: true
            date: 2026-10-12
            auteurs: [Alice, Bob]
            tags: [voyage, europe]
            aliases: [Lutèce]
            ---
            # Paris
            Voir [[Lausanne]] et [[Inexistante]]. ![[photo.png]] Puis [Lyon](../Lyon.md).

            """,
        "Voyages/Lausanne.md": "---\ncoordinates: \"46.5197, 6.6323\"\nrelated: \"[[Paris]]\"\n---\n# Lausanne #suisse\n",
        "Lyon.md": "---\npages: \"douze\"\ndate: 2026-02-30\n---\n# Lyon\n",
        "Notes sans propriétés.md": "# Rien\n",
        "photo.png": "",
    ]

    private static var logger: Logger {
        var logger = Logger(label: "GraphitePostgreSQLMirrorTests")
        logger.logLevel = .critical
        return logger
    }

    private var schema: String { PostgreSQLMirrorStatements.quotedIdentifier(configuration.schemaName) }

    private func makeMirror() -> PostgreSQLMirror {
        testedDatabases.insert(configuration.databaseName)
        return PostgreSQLMirror(configuration: configuration, password: password, clock: LiveApplicationClock())
    }

    private func mirroredVault(_ vault: URL, declaredTypes: [String: PropertyType]? = nil) -> MirroredVault {
        MirroredVault(name: vaultName, declaredPropertyTypes: declaredTypes ?? self.declaredTypes, placePropertyNames: PlacedNote.propertyNames(vaultRoot: vault))
    }

    private func makeVault(_ files: [String: String]) async throws -> (URL, VaultIndex) {
        let vault = try TemporaryVault.make(prefix: "MirrorVault", for: self).root
        for (path, text) in files { try write(text, to: path, in: vault) }
        let index = try VaultIndex(databaseURL: try TemporaryVault.make(prefix: "MirrorVaultIndex", for: self).root.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        return (vault, index)
    }

    private func write(_ text: String, to path: String, in vault: URL) throws {
        let location = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func withConnection<Answer: Sendable>(databaseName: String, _ work: (PostgresConnection) async throws -> Answer) async throws -> Answer {
        let connectionConfiguration = PostgresConnection.Configuration(host: configuration.host, port: configuration.port, username: configuration.userName,
                                                                       password: password, database: databaseName, tls: .disable)
        let connection = try await PostgresConnection.connect(configuration: connectionConfiguration, id: 2, logger: Self.logger)
        do {
            let answer = try await work(connection)
            try await connection.close()
            return answer
        } catch {
            try? await connection.close()
            throw error
        }
    }

    private func execute(_ sql: String) async throws {
        try await withConnection(databaseName: configuration.databaseName) { connection in
            _ = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: Self.logger)
        }
    }

    private func rows<each Column: PostgresDecodable & Sendable>(_ sql: String, as columns: (repeat each Column).Type) async throws -> [(repeat each Column)] {
        let connectionConfiguration = PostgresConnection.Configuration(host: configuration.host, port: configuration.port, username: configuration.userName,
                                                                       password: password, database: configuration.databaseName, tls: .disable)
        let connection = try await PostgresConnection.connect(configuration: connectionConfiguration, id: 3, logger: Self.logger)
        var answers: [(repeat each Column)] = []
        do {
            for try await answer in try await connection.query(PostgresQuery(unsafeSQL: sql), logger: Self.logger).decode((repeat each Column).self) {
                answers.append(answer)
            }
        } catch {
            try? await connection.close()
            throw error
        }
        try await connection.close()
        return answers
    }

    private func row<each Column: PostgresDecodable & Sendable>(_ sql: String, as columns: (repeat each Column).Type) async throws -> (repeat each Column) {
        let answers = try await rows(sql, as: columns)
        XCTAssertEqual(answers.count, 1, sql)
        return try XCTUnwrap(answers.first)
    }

    private func copyNumber() async throws -> Int64 {
        try await row("SELECT copy_number FROM \(schema).vaults WHERE vault = 'Atlas'", as: Int64.self)
    }
}
