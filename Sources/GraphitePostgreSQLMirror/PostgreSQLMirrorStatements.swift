import Foundation
import GraphiteCore

/// A property the vault uses, with the type it has across the vault and how many notes have it.
struct MirroredPropertyColumn: Hashable, Sendable {
    /// The spelling the Properties view shows; a note's JSON uses it for every capitalization.
    let propertyName: String
    let propertyType: PropertyType
    let noteCount: Int
}

/// The SQL the mirror runs, for one schema. Names Graphite does not choose (the schema, the
/// properties) are always quoted; values are bound as parameters, except in the view, whose
/// definition cannot hold parameters, where property names are written as escaped literals.
struct PostgreSQLMirrorStatements: Sendable {
    /// The schema version these statements create. A later version adds a migration.
    static let schemaVersion = 1
    /// PostgreSQL truncates longer identifiers (`NAMEDATALEN` − 1 bytes), which could make two
    /// columns one; a property whose name is longer has no column of its own in the view.
    static let maximumIdentifierBytes = 63
    /// A view holds at most 1,664 columns; the most used properties get one, the rest stay in `properties`.
    static let maximumPropertyColumns = 1_000
    /// The columns `notes_with_properties` has before its property columns.
    static let fixedViewColumns = ["vault", "path", "name", "folder", "created", "modified", "size_bytes", "tags", "aliases",
                                   "latitude", "longitude", "geometry", "properties"]

    /// The quoted schema name.
    let schema: String

    init(schemaName: String) {
        schema = Self.quotedIdentifier(schemaName)
    }

    static func quotedIdentifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A string literal that means the same text whatever `standard_conforming_strings` says:
    /// in the `E'…'` form backslashes are always escapes, so they are doubled.
    static func quotedLiteral(_ text: String) -> String {
        "E'" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "''") + "'"
    }

    // MARK: Tables

    /// The schema, its tables and indexes, each statement on its own (the extended query
    /// protocol runs one statement per query). Every statement can run again harmlessly.
    var schemaCreation: [String] {
        [
            "CREATE SCHEMA IF NOT EXISTS \(schema)",
            "CREATE TABLE IF NOT EXISTS \(schema).mirror_schema (version integer NOT NULL)",
            """
            CREATE TABLE IF NOT EXISTS \(schema).vaults (
              vault text PRIMARY KEY,
              copy_number bigint NOT NULL DEFAULT 0,
              copied_at timestamptz NOT NULL DEFAULT now()
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS \(schema).notes (
              vault text NOT NULL REFERENCES \(schema).vaults (vault) ON DELETE CASCADE,
              path text NOT NULL,
              name text NOT NULL,
              folder text NOT NULL,
              created timestamptz,
              modified timestamptz NOT NULL,
              size_bytes bigint NOT NULL,
              tags text[] NOT NULL,
              aliases text[] NOT NULL,
              properties jsonb NOT NULL,
              latitude double precision,
              longitude double precision,
              content_digest text NOT NULL,
              links_digest text NOT NULL,
              PRIMARY KEY (vault, path)
            )
            """,
            "CREATE INDEX IF NOT EXISTS notes_properties ON \(schema).notes USING gin (properties)",
            "CREATE INDEX IF NOT EXISTS notes_tags ON \(schema).notes USING gin (tags)",
            """
            CREATE TABLE IF NOT EXISTS \(schema).links (
              vault text NOT NULL,
              source_path text NOT NULL,
              link_number integer NOT NULL,
              target text NOT NULL,
              target_path text,
              is_embed boolean NOT NULL,
              is_in_properties boolean NOT NULL,
              PRIMARY KEY (vault, source_path, link_number),
              FOREIGN KEY (vault, source_path) REFERENCES \(schema).notes (vault, path) ON DELETE CASCADE
            )
            """,
            "CREATE INDEX IF NOT EXISTS links_target_path ON \(schema).links (vault, target_path)",
            """
            CREATE TABLE IF NOT EXISTS \(schema).property_columns (
              vault text NOT NULL REFERENCES \(schema).vaults (vault) ON DELETE CASCADE,
              property_name text NOT NULL,
              property_type text NOT NULL,
              note_count integer NOT NULL,
              PRIMARY KEY (vault, property_name)
            )
            """,
            "INSERT INTO \(schema).mirror_schema (version) SELECT \(Self.schemaVersion) WHERE NOT EXISTS (SELECT 1 FROM \(schema).mirror_schema)",
        ]
    }

    /// The notes' point, computed by PostgreSQL from their latitude and longitude, for a
    /// database with PostGIS (installed in `postGISSchema`). Added once PostGIS is there.
    func geometryColumnCreation(postGISSchema: String) -> [String] {
        let postGIS = Self.quotedIdentifier(postGISSchema)
        return [
            """
            ALTER TABLE \(schema).notes ADD COLUMN IF NOT EXISTS geometry \(postGIS).geometry(Point, 4326)
              GENERATED ALWAYS AS (CASE WHEN latitude IS NULL OR longitude IS NULL THEN NULL
                ELSE \(postGIS).st_setsrid(\(postGIS).st_makepoint(longitude, latitude), 4326) END) STORED
            """,
            "CREATE INDEX IF NOT EXISTS notes_geometry ON \(schema).notes USING gist (geometry)",
        ]
    }

    // MARK: Copying

    var vaultRegistration: String {
        "INSERT INTO \(schema).vaults (vault) VALUES ($1) ON CONFLICT (vault) DO NOTHING"
    }

    /// Serializes copies of one vault, from this device and any other, until the transaction ends.
    var vaultLock: String {
        "SELECT pg_advisory_xact_lock(hashtext(\(Self.quotedLiteral(schema + ".")) || $1))"
    }

    var copyNumberSelection: String {
        "SELECT copy_number FROM \(schema).vaults WHERE vault = $1 FOR UPDATE"
    }

    var copyNumberIncrement: String {
        "UPDATE \(schema).vaults SET copy_number = copy_number + 1, copied_at = now() WHERE vault = $1 RETURNING copy_number"
    }

    var copiedNoteSelection: String {
        "SELECT path, content_digest, links_digest FROM \(schema).notes WHERE vault = $1"
    }

    var noteDeletion: String {
        "DELETE FROM \(schema).notes WHERE vault = $1 AND path = ANY($2)"
    }

    /// Writes the notes in `$2`, a JSON array of `MirroredNoteRow`s, replacing those already there.
    var noteUpsert: String {
        """
        INSERT INTO \(schema).notes (vault, path, name, folder, created, modified, size_bytes, tags, aliases, properties,
                                     latitude, longitude, content_digest, links_digest)
        SELECT $1, copied.path, copied.name, copied.folder, copied.created, copied.modified, copied.size_bytes,
               copied.tags, copied.aliases, copied.properties, copied.latitude, copied.longitude,
               copied.content_digest, copied.links_digest
        FROM jsonb_to_recordset($2::jsonb) AS copied(path text, name text, folder text, created timestamptz,
             modified timestamptz, size_bytes bigint, tags text[], aliases text[], properties jsonb,
             latitude double precision, longitude double precision, content_digest text, links_digest text)
        ON CONFLICT (vault, path) DO UPDATE SET name = EXCLUDED.name, folder = EXCLUDED.folder, created = EXCLUDED.created,
          modified = EXCLUDED.modified, size_bytes = EXCLUDED.size_bytes, tags = EXCLUDED.tags, aliases = EXCLUDED.aliases,
          properties = EXCLUDED.properties, latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude,
          content_digest = EXCLUDED.content_digest, links_digest = EXCLUDED.links_digest
        """
    }

    var linkDeletion: String {
        "DELETE FROM \(schema).links WHERE vault = $1 AND source_path = ANY($2)"
    }

    /// Writes the links in `$2`, a JSON array of `MirroredLinkRow`s.
    var linkInsertion: String {
        """
        INSERT INTO \(schema).links (vault, source_path, link_number, target, target_path, is_embed, is_in_properties)
        SELECT $1, copied.source_path, copied.link_number, copied.target, copied.target_path, copied.is_embed, copied.is_in_properties
        FROM jsonb_to_recordset($2::jsonb) AS copied(source_path text, link_number integer, target text, target_path text,
             is_embed boolean, is_in_properties boolean)
        """
    }

    var vaultPropertyColumnSelection: String {
        "SELECT property_name, property_type FROM \(schema).property_columns WHERE vault = $1"
    }

    var vaultPropertyColumnDeletion: String {
        "DELETE FROM \(schema).property_columns WHERE vault = $1"
    }

    var vaultPropertyColumnInsertion: String {
        """
        INSERT INTO \(schema).property_columns (vault, property_name, property_type, note_count)
        SELECT $1, copied.property_name, copied.property_type, copied.note_count
        FROM jsonb_to_recordset($2::jsonb) AS copied(property_name text, property_type text, note_count integer)
        """
    }

    /// Every vault's properties, for the columns of `notes_with_properties`.
    var allPropertyColumnSelection: String {
        "SELECT property_name, property_type, note_count FROM \(schema).property_columns"
    }

    var notesWithPropertiesExistence: String {
        "SELECT to_regclass(\(Self.quotedLiteral(schema + ".notes_with_properties"))) IS NOT NULL"
    }

    /// QGIS listens on the `qgis` channel; a layer set to "Refresh layer on notification"
    /// draws again when a copy commits.
    static let notification = "NOTIFY qgis, 'graphite'"

    // MARK: Views

    /// The links between two placed notes as lines, for a database with PostGIS.
    func linksOnMapView(postGISSchema: String) -> String {
        let postGIS = Self.quotedIdentifier(postGISSchema)
        return """
        CREATE OR REPLACE VIEW \(schema).links_on_map AS
        SELECT link.vault, link.source_path, link.link_number, link.target_path,
               \(postGIS).st_makeline(source.geometry, destination.geometry)::\(postGIS).geometry(LineString, 4326) AS geometry
        FROM \(schema).links link
        JOIN \(schema).notes source ON source.vault = link.vault AND source.path = link.source_path
        JOIN \(schema).notes destination ON destination.vault = link.vault AND destination.path = link.target_path
        WHERE source.geometry IS NOT NULL AND destination.geometry IS NOT NULL AND source.path <> destination.path
        """
    }

    /// The notes with one typed column per property, merged across vaults by name whatever its
    /// capitals; a property typed differently in two vaults is text. With `validatesInput`
    /// (PostgreSQL 16 and later, `pg_input_is_valid`) dates are dates; before, they stay text,
    /// since casting a malformed date would fail the whole query.
    func notesWithPropertiesView(columns: [MirroredPropertyColumn], postGISSchema: String?, validatesInput: Bool) -> String {
        var selections = ["vault.vault", "note.path", "note.name", "note.folder", "note.created", "note.modified", "note.size_bytes",
                          "note.tags", "note.aliases", "note.latitude", "note.longitude"]
        if postGISSchema != nil { selections.append("note.geometry") }
        selections.append("note.properties")
        for column in Self.viewColumns(from: columns) {
            let expression = Self.typedExpression(of: column.spellings, type: column.type, validatesInput: validatesInput)
            selections.append("\(expression) AS \(Self.quotedIdentifier(column.columnName))")
        }
        return "CREATE VIEW \(schema).notes_with_properties AS SELECT " + selections.joined(separator: ",\n  ")
            + "\nFROM \(schema).notes note JOIN \(schema).vaults vault ON vault.vault = note.vault"
    }

    struct ViewColumn: Equatable {
        let columnName: String
        /// Every spelling vaults use for the property; a note's JSON holds one of them.
        let spellings: [String]
        let type: PropertyType?
    }

    /// The property columns: merged by lowercased name (the spelling used by most notes wins),
    /// the most used first, renamed when a fixed column has the name, left out when the name
    /// is too long for an identifier. A nil type means the vaults disagree, read as text.
    static func viewColumns(from columns: [MirroredPropertyColumn]) -> [ViewColumn] {
        struct Merged { var spellings: [(name: String, noteCount: Int)]; var types: Set<PropertyType>; var noteCount: Int }
        var mergedByKey: [String: Merged] = [:]
        for column in columns {
            let key = column.propertyName.lowercased()
            var merged = mergedByKey[key] ?? Merged(spellings: [], types: [], noteCount: 0)
            if let index = merged.spellings.firstIndex(where: { spelling in spelling.name == column.propertyName }) {
                merged.spellings[index].noteCount += column.noteCount
            } else {
                merged.spellings.append((column.propertyName, column.noteCount))
            }
            merged.types.insert(column.propertyType)
            merged.noteCount += column.noteCount
            mergedByKey[key] = merged
        }
        let ordered = mergedByKey.values.sorted { leftMerged, rightMerged in
            leftMerged.noteCount != rightMerged.noteCount ? leftMerged.noteCount > rightMerged.noteCount
                : leftMerged.spellings[0].name < rightMerged.spellings[0].name
        }
        var viewColumns: [ViewColumn] = []
        var usedNames = Set(fixedViewColumns)
        for merged in ordered {
            let spellings = merged.spellings.sorted { leftSpelling, rightSpelling in
                leftSpelling.noteCount != rightSpelling.noteCount ? leftSpelling.noteCount > rightSpelling.noteCount : leftSpelling.name < rightSpelling.name
            }.map(\.name)
            var columnName = spellings[0]
            if usedNames.contains(columnName) { columnName += " (property)" }
            guard columnName.utf8.count <= maximumIdentifierBytes, !usedNames.contains(columnName) else { continue }
            usedNames.insert(columnName)
            viewColumns.append(ViewColumn(columnName: columnName, spellings: spellings, type: merged.types.count == 1 ? merged.types.first : nil))
            if viewColumns.count == maximumPropertyColumns { break }
        }
        return viewColumns
    }

    /// The SQL reading one property from `note.properties` as its type.
    static func typedExpression(of spellings: [String], type: PropertyType?, validatesInput: Bool) -> String {
        let accesses = spellings.map { spelling in "note.properties -> \(quotedLiteral(spelling))" }
        let value = accesses.count == 1 ? accesses[0] : "COALESCE(" + accesses.joined(separator: ", ") + ")"
        let text = "(\(value) #>> '{}')"
        switch type {
        case .number:
            return "CASE WHEN jsonb_typeof(\(value)) = 'number' THEN \(text)::double precision END"
        case .checkbox:
            return "CASE WHEN jsonb_typeof(\(value)) = 'boolean' THEN \(text)::boolean END"
        case .date where validatesInput:
            return "CASE WHEN jsonb_typeof(\(value)) = 'string' AND pg_input_is_valid(\(text), 'date') THEN \(text)::date END"
        case .datetime where validatesInput:
            return "CASE WHEN jsonb_typeof(\(value)) = 'string' AND pg_input_is_valid(\(text), 'timestamp') THEN \(text)::timestamp END"
        case .multitext, .tags, .aliases:
            return "CASE jsonb_typeof(\(value)) WHEN 'array' THEN ARRAY(SELECT jsonb_array_elements_text(\(value))) WHEN 'string' THEN ARRAY[\(text)] END"
        case .text, .date, .datetime, nil:
            return text
        }
    }
}
