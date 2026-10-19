import XCTest
import GRDB
@testable import GraphiteIndex

/// The shape of the index database: the migrations it records, its full-text tokenizer, the
/// tables and columns they leave, and the SQL function a search calls.
final class VaultIndexMigrationsTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("VaultIndexMigrationsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory) // Best-effort removal of a temporary folder.
    }

    private static let migrationIdentifiers = [
        "inventory-and-links-1", "bounded-update-lookups-2", "filename-search-and-row-identities-3",
        "vault-path-markdown-link-targets-4", "base-properties-and-creation-dates-5", "unicode-name-keys-6",
        "search-whole-note-text-7", "case-folded-link-keys-8", "markdown-link-written-targets-9",
    ]

    private func recordedMigrations(in index: VaultIndex) async throws -> [String] {
        try await index.databaseQueue.read { database in
            try String.fetchAll(database, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
        }
    }

    func testANewDatabaseRecordsEveryMigrationInOrder() async throws {
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))

        let recorded = try await recordedMigrations(in: index)

        XCTAssertEqual(recorded, Self.migrationIdentifiers)
    }

    func testOpeningAMigratedDatabaseAgainChangesNothing() async throws {
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        let firstIndex = try VaultIndex(databaseURL: databaseURL)
        let firstSchema = try await schemaDescription(of: firstIndex)

        let reopened = try VaultIndex(databaseURL: databaseURL)

        let reopenedMigrations = try await recordedMigrations(in: reopened)
        let reopenedSchema = try await schemaDescription(of: reopened)
        XCTAssertEqual(reopenedMigrations, Self.migrationIdentifiers)
        XCTAssertEqual(reopenedSchema, firstSchema)
    }

    func testTheSearchTableUsesTheDiacriticFoldingUnicodeTokenizer() async throws {
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))

        let statement = try await index.databaseQueue.read { database in
            try String.fetchOne(database, sql: "SELECT sql FROM sqlite_master WHERE name = 'search'")
        }

        let createStatement = try XCTUnwrap(statement)
        XCTAssertTrue(createStatement.contains("fts5(path, title, body, tokenize='unicode61 remove_diacritics 2')"), createStatement)
    }

    func testTheTablesHoldTheseColumnsAndIndexes() async throws {
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))

        let schema = try await schemaDescription(of: index)

        XCTAssertEqual(schema.columnsByTable, [
            "files": ["path", "basename", "title", "size", "modified", "generation", "contentIndexed", "created",
                      "path_key", "name_key", "folded_path", "folded_name"],
            "links": ["source", "target", "isWiki", "isEmbed", "folded_target"],
            "aliases": ["alias", "path", "folded_alias"],
            "tags": ["tag", "path"],
            "headings": ["heading", "path"],
            "properties": ["path", "position", "key", "node"],
            "property_links": ["path", "target", "folded_target"],
        ])
        XCTAssertEqual(schema.indexNames, [
            "aliases_folded_alias", "aliases_name", "aliases_path", "files_basename", "files_folded_name", "files_folded_path",
            "headings_path", "links_folded_target", "links_source", "links_target", "properties_key", "properties_path",
            "property_links_folded_target", "property_links_path", "property_links_target", "tags_name", "tags_path",
        ])
    }

    func testTheRegularExpressionFunctionReadsItsCaseFromTheArgumentPrefix() async throws {
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))

        let results = try await index.databaseQueue.read { database in
            try [
                Bool.fetchOne(database, sql: "SELECT graphite_regexp('c:a+b', 'xaab')"),
                Bool.fetchOne(database, sql: "SELECT graphite_regexp('c:A+B', 'xaab')"),
                Bool.fetchOne(database, sql: "SELECT graphite_regexp('i:A+B', 'xaab')"),
                Bool.fetchOne(database, sql: "SELECT graphite_regexp('i:z', 'xaab')"),
            ]
        }

        XCTAssertEqual(results, [true, false, true, false])
        XCTAssertEqual(RegularExpressionFunction.argument(pattern: "a+b", isCaseSensitive: true), "c:a+b")
        XCTAssertEqual(RegularExpressionFunction.argument(pattern: "a+b", isCaseSensitive: false), "i:a+b")
    }

    /// A database as the first release of the index made it: only the first migration applied.
    func testADatabaseFromTheFirstMigrationIsBroughtToTheCurrentSchemaAndEmptied() async throws {
        let databaseURL = directory.appendingPathComponent("index.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let firstReleaseQueue = try DatabaseQueue(path: databaseURL.path)
        var firstReleaseMigrator = DatabaseMigrator()
        firstReleaseMigrator.registerMigration("inventory-and-links-1") { database in
            try database.execute(sql: """
                CREATE TABLE files (
                  path TEXT PRIMARY KEY, basename TEXT NOT NULL, title TEXT NOT NULL,
                  size INTEGER NOT NULL, modified REAL NOT NULL, generation TEXT NOT NULL,
                  contentIndexed INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX files_basename ON files(basename COLLATE NOCASE);
                CREATE VIRTUAL TABLE search USING fts5(path, title, body, tokenize='unicode61 remove_diacritics 2');
                CREATE TABLE links (source TEXT NOT NULL, target TEXT NOT NULL, isWiki INTEGER NOT NULL, isEmbed INTEGER NOT NULL);
                CREATE INDEX links_source ON links(source);
                CREATE INDEX links_target ON links(target COLLATE NOCASE);
                CREATE TABLE aliases (alias TEXT NOT NULL, path TEXT NOT NULL);
                CREATE INDEX aliases_name ON aliases(alias COLLATE NOCASE);
                CREATE TABLE tags (tag TEXT NOT NULL, path TEXT NOT NULL);
                CREATE INDEX tags_name ON tags(tag COLLATE NOCASE);
                CREATE TABLE headings (heading TEXT NOT NULL, path TEXT NOT NULL);
                """)
        }
        try firstReleaseMigrator.migrate(firstReleaseQueue)
        try await firstReleaseQueue.write { database in
            try database.execute(sql: "INSERT INTO files(path, basename, title, size, modified, generation, contentIndexed) VALUES ('Old.md', 'Old.md', 'Old', 3, 0, 'g', 1)")
            try database.execute(sql: "INSERT INTO search(rowid, path, title, body) VALUES (1, 'Old.md', 'Old', 'old text')")
            try database.execute(sql: "INSERT INTO links(source, target, isWiki, isEmbed) VALUES ('Old.md', 'Other', 1, 0)")
        }
        try firstReleaseQueue.close()

        let index = try VaultIndex(databaseURL: databaseURL)

        let migrations = try await recordedMigrations(in: index)
        XCTAssertEqual(migrations, Self.migrationIdentifiers)
        let counts = try await index.databaseQueue.read { database in
            try ["files", "search", "links"].map { table in try Int.fetchOne(database, sql: "SELECT count(*) FROM \(table)") }
        }
        XCTAssertEqual(counts, [0, 0, 0], "The fourth migration empties the cache; the next scan rebuilds it from the vault.")
        let schema = try await schemaDescription(of: index)
        XCTAssertEqual(schema.columnsByTable["files"], ["path", "basename", "title", "size", "modified", "generation", "contentIndexed", "created",
                                                         "path_key", "name_key", "folded_path", "folded_name"])
    }

    // MARK: Helpers

    private struct SchemaDescription: Equatable {
        var columnsByTable: [String: [String]]
        var indexNames: [String]
    }

    private func schemaDescription(of index: VaultIndex) async throws -> SchemaDescription {
        try await index.databaseQueue.read { database in
            var columnsByTable: [String: [String]] = [:]
            for table in ["files", "links", "aliases", "tags", "headings", "properties", "property_links"] {
                columnsByTable[table] = try Row.fetchAll(database, sql: "PRAGMA table_info(\(table))").map { row in row["name"] as String }
            }
            let indexNames = try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            return SchemaDescription(columnsByTable: columnsByTable, indexNames: indexNames)
        }
    }
}
