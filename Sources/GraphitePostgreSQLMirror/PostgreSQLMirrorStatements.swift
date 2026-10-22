import Foundation
import GraphiteCore

/// A property the vault uses, with the type it has across the vault and how many notes have it.
struct MirroredPropertyColumn: Hashable, Sendable {
    /// The spelling the Properties view shows; a note's JSON uses it for every capitalization.
    let propertyName: String
    let propertyType: PropertyType
    let noteCount: Int
}

/// The SQL the mirror runs, for one schema. Names Graphite does not choose (the schema) are
/// always quoted; values are bound as parameters.
struct PostgreSQLMirrorStatements: Sendable {
    /// The schema version these statements create. A later version adds a migration.
    static let schemaVersion = 1

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

    /// QGIS listens on the `qgis` channel; a layer set to "Refresh layer on notification"
    /// draws again when a copy commits.
    static let notification = "NOTIFY qgis, 'graphite'"
}
