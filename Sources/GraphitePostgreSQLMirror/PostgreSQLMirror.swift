import CryptoKit
import Foundation
import GraphiteCore
import GraphiteIndex
import PostgresNIO

/// A vault as the mirror copies it.
public struct MirroredVault: Sendable {
    /// The vault's folder name, which keys its rows: the same vault opened on the Mac and the
    /// iPad copies into the same rows.
    public let name: String
    /// The types `.obsidian/types.json` assigns.
    public let declaredPropertyTypes: [String: PropertyType]
    /// The properties that place a note, as the Map View reads them (`PlacedNote.propertyNames`).
    public let placePropertyNames: [String]

    public init(name: String, declaredPropertyTypes: [String: PropertyType], placePropertyNames: [String]) {
        self.name = name
        self.declaredPropertyTypes = declaredPropertyTypes
        self.placePropertyNames = placePropertyNames
    }
}

/// What one copy did.
public struct PostgreSQLMirrorReport: Equatable, Sendable {
    /// The vault's notes in the database once the copy committed.
    public let copiedNoteCount: Int
    public let writtenNoteCount: Int
    public let deletedNoteCount: Int
    /// Notes whose links were written again.
    public let rewrittenLinkSourceCount: Int
    /// Whether the notes have a PostGIS point (`geometry`) beside their latitude and longitude.
    public let hasGeometry: Bool
    /// False when nothing had changed in the index since the last copy, which then did not
    /// connect to the server.
    public let didConnect: Bool
    public let elapsedSeconds: Double
}

/// The server a connection reached.
public struct PostgreSQLServerDescription: Equatable, Sendable {
    public let version: String
    /// The PostGIS version installed in the database; nil without PostGIS.
    public let postGISVersion: String?
}

/// Copies a vault's notes from the index into PostgreSQL, one way: notes, typed properties,
/// tags, aliases, links resolved to files, and places, in a schema of tables and views other
/// apps read (QGIS among them). The vault is never written; the database can be emptied and
/// copied again at any time.
///
/// Each copy writes only what changed, in one transaction, under a lock per vault, so a copy
/// from another device waits rather than interleaving. Between copies the mirror remembers
/// what it computed and wrote: a note whose file the index has not read again is not read
/// again, links are resolved again only for changed notes while no file or alias was added,
/// removed or renamed, and the database's state is not read again while its copy number is
/// the one this mirror set.
public actor PostgreSQLMirror {
    /// Notes read from the index, and written, per statement.
    static let noteChunkSize = 500
    /// Deleted notes per statement.
    static let pathChunkSize = 2_000

    private let configuration: PostgreSQLMirrorConfiguration
    private let password: String
    private let clock: any ApplicationClock
    private let statements: PostgreSQLMirrorStatements
    private let logger: Logger
    private var hasPreparedSchema = false
    /// Per vault: what this mirror computed from the index, valid for the notes whose file
    /// revision is unchanged.
    private var computedStates: [String: ComputedVaultState] = [:]
    /// Per vault: what the database holds, as of the copy number this mirror last set.
    private var copiedStates: [String: CopiedVaultState] = [:]
    /// Per vault: what the last copy that committed was made from.
    private var lastCopies: [String: LastCopy] = [:]

    struct ComputedNote: Equatable {
        let fileRevision: String
        let contentDigest: String
    }

    struct ComputedVaultState {
        let notes: [String: ComputedNote]
        let linksDigests: [String: String]
        let linkResolutionState: Int
        let columns: [MirroredPropertyColumn]
        let declaredPropertyTypes: [String: PropertyType]
        let placePropertyNames: [String]
    }

    struct CopiedVaultState {
        let copyNumber: Int64
        let notes: [String: CopiedNoteDigests]
    }

    /// Everything a copy is made from; equal inputs make an equal copy.
    struct CopyInputs: Equatable {
        let revisions: [String: String]
        let linkResolutionState: Int
        let declaredPropertyTypes: [String: PropertyType]
        let placePropertyNames: [String]
    }

    struct LastCopy {
        let inputs: CopyInputs
        let report: PostgreSQLMirrorReport
    }

    /// `clock` times each copy for its report.
    public init(configuration: PostgreSQLMirrorConfiguration, password: String, clock: any ApplicationClock) {
        self.configuration = configuration.trimmedForConnection
        self.password = password
        self.clock = clock
        statements = PostgreSQLMirrorStatements(schemaName: self.configuration.schemaName)
        var logger = Logger(label: "Graphite.PostgreSQLMirror")
        // PostgresNIO logs every query at debug level; the settings page reports what matters.
        logger.logLevel = .critical
        self.logger = logger
    }

    // MARK: Connecting

    /// Connects, reads what the server is, and disconnects: the settings page's test.
    public func describeServer() async throws -> PostgreSQLServerDescription {
        try await withConnection { connection in try await self.serverState(on: connection).description }
    }

    private func withConnection<Answer: Sendable>(_ work: (PostgresConnection) async throws -> Answer) async throws -> Answer {
        let connection: PostgresConnection
        do {
            connection = try await PostgresConnection.connect(configuration: try connectionConfiguration(), id: 1, logger: logger)
        } catch {
            throw PostgreSQLMirrorError.connecting(error, to: configuration)
        }
        do {
            let answer = try await work(connection)
            try? await connection.close() // The answer is in hand; the server drops a connection that does not close cleanly.
            return answer
        } catch {
            try? await connection.close() // The work's own failure is the one to report.
            if error is CancellationError { throw error }
            throw PostgreSQLMirrorError.running(error)
        }
    }

    private func connectionConfiguration() throws -> PostgresConnection.Configuration {
        let transportSecurity: PostgresConnection.Configuration.TLS
        switch configuration.transportSecurity {
        case .off:
            transportSecurity = .disable
        case .preferred:
            var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
            tlsConfiguration.certificateVerification = .none
            transportSecurity = .prefer(try NIOSSLContext(configuration: tlsConfiguration))
        case .verified:
            transportSecurity = .require(try NIOSSLContext(configuration: .makeClientConfiguration()))
        }
        return PostgresConnection.Configuration(host: configuration.host, port: configuration.port, username: configuration.userName,
                                                password: password, database: configuration.databaseName, tls: transportSecurity)
    }

    private struct ServerState {
        let description: PostgreSQLServerDescription
        /// PostgreSQL 16 and later can test a value before a cast (`pg_input_is_valid`).
        let validatesInput: Bool
        let postGISSchema: String?
    }

    private func serverState(on connection: PostgresConnection) async throws -> ServerState {
        var version = ""
        var versionNumber = 0
        let versionSelection: PostgresQuery = "SELECT current_setting('server_version'), current_setting('server_version_num')"
        for try await (versionText, numberText) in try await connection.query(versionSelection, logger: logger).decode((String, String).self) {
            version = versionText
            versionNumber = Int(numberText) ?? 0
        }
        var postGISSchema: String?
        var postGISVersion: String?
        let extensionQuery: PostgresQuery = """
            SELECT namespace.nspname, extension.extversion FROM pg_extension extension
            JOIN pg_namespace namespace ON namespace.oid = extension.extnamespace WHERE extension.extname = 'postgis'
            """
        for try await (schemaName, extensionVersion) in try await connection.query(extensionQuery, logger: logger).decode((String, String).self) {
            postGISSchema = schemaName
            postGISVersion = extensionVersion
        }
        return ServerState(description: PostgreSQLServerDescription(version: version, postGISVersion: postGISVersion),
                           validatesInput: versionNumber >= 160_000, postGISSchema: postGISSchema)
    }

    // MARK: Copying

    /// Copies `vault` from `index`. Call it once the index has read the whole vault: a note
    /// the index does not hold yet would be deleted from the database. When nothing changed
    /// in the index since the last copy, nothing is sent, unless `rechecksDatabase` asks to
    /// compare with the database anyway (Copy Now).
    public func copy(_ vault: MirroredVault, from index: VaultIndex, rechecksDatabase: Bool = false) async throws -> PostgreSQLMirrorReport {
        let start = clock.now
        let revisions = try await index.noteRevisions()
        let linkResolutionState = try await index.linkResolutionState()
        let inputs = CopyInputs(revisions: revisions, linkResolutionState: linkResolutionState,
                                declaredPropertyTypes: vault.declaredPropertyTypes, placePropertyNames: vault.placePropertyNames)
        if !rechecksDatabase, let lastCopy = lastCopies[vault.name], lastCopy.inputs == inputs {
            return PostgreSQLMirrorReport(copiedNoteCount: lastCopy.report.copiedNoteCount, writtenNoteCount: 0, deletedNoteCount: 0,
                                          rewrittenLinkSourceCount: 0, hasGeometry: lastCopy.report.hasGeometry, didConnect: false,
                                          elapsedSeconds: seconds(since: start))
        }
        let (computed, resolvedLinks) = try await computeState(of: vault, from: index, revisions: revisions, linkResolutionState: linkResolutionState)
        computedStates[vault.name] = computed
        var indexedDigests: [String: CopiedNoteDigests] = [:]
        for (path, computedNote) in computed.notes {
            indexedDigests[path] = CopiedNoteDigests(contentDigest: computedNote.contentDigest,
                                                     linksDigest: computed.linksDigests[path] ?? Self.emptyLinksDigest)
        }
        do {
            let report = try await withConnection { connection in
                try await self.write(vault, indexedDigests: indexedDigests, columns: computed.columns, resolvedLinks: resolvedLinks, index: index,
                                     connection: connection, start: start)
            }
            lastCopies[vault.name] = LastCopy(inputs: inputs, report: report)
            return report
        } catch {
            // What the database holds is unknown after a failure; the next copy reads it again.
            copiedStates[vault.name] = nil
            lastCopies[vault.name] = nil
            hasPreparedSchema = false
            throw error
        }
    }

    /// Notes' links as one copy resolved them, and which notes they are (a note without links
    /// has no entry in `linksByNote`).
    struct ResolvedLinks: Sendable {
        var linksByNote: [String: [ResolvedNoteLink]]
        var resolvedPaths: Set<String>
    }

    /// The vault's properties, and each note's digests, reusing what the last copy computed
    /// for notes whose file the index has not read again; with the links it resolved, so the
    /// write does not resolve them again.
    private func computeState(of vault: MirroredVault, from index: VaultIndex, revisions: [String: String],
                              linkResolutionState: Int) async throws -> (ComputedVaultState, ResolvedLinks) {
        let previous = computedStates[vault.name].flatMap { state in state.placePropertyNames == vault.placePropertyNames ? state : nil }
        let changedPaths = revisions.compactMap { path, revision in previous?.notes[path]?.fileRevision == revision ? nil : path }.sorted()
        let notesAreUnchanged = previous.map { previous in changedPaths.isEmpty && previous.notes.count == revisions.count } ?? false

        let columns: [MirroredPropertyColumn]
        if let previous, notesAreUnchanged, previous.declaredPropertyTypes == vault.declaredPropertyTypes {
            columns = previous.columns
        } else {
            columns = MirroredPropertyColumn.columns(from: try await index.propertyUsages(), declaredTypes: vault.declaredPropertyTypes)
        }
        let columnsByKey = Self.columnsByKey(columns)

        // Links resolve as before unless a file or an alias came, went or was renamed.
        var linksDigests: [String: String] = [:]
        let resolvedLinks: ResolvedLinks
        if let previous, previous.linkResolutionState == linkResolutionState {
            for path in revisions.keys { linksDigests[path] = previous.linksDigests[path] }
            resolvedLinks = ResolvedLinks(linksByNote: try await index.resolvedLinks(ofNotesAt: changedPaths), resolvedPaths: Set(changedPaths))
            for path in changedPaths { linksDigests[path] = Self.linksDigest(of: resolvedLinks.linksByNote[path] ?? []) }
        } else {
            resolvedLinks = ResolvedLinks(linksByNote: try await index.resolvedLinks(), resolvedPaths: Set(revisions.keys))
            for path in revisions.keys { linksDigests[path] = Self.linksDigest(of: resolvedLinks.linksByNote[path] ?? []) }
        }

        // Notes whose property's name or type changed read differently, though their files did not change.
        var pathsToCompute = Set(changedPaths)
        if let previous {
            let previousColumnsByKey = Self.columnsByKey(previous.columns)
            for key in Set(previousColumnsByKey.keys).union(columnsByKey.keys)
            where previousColumnsByKey[key]?.propertyName != columnsByKey[key]?.propertyName
                || previousColumnsByKey[key]?.propertyType != columnsByKey[key]?.propertyType {
                let propertyName = columnsByKey[key]?.propertyName ?? previousColumnsByKey[key]?.propertyName ?? key
                pathsToCompute.formUnion(try await index.paths(withPropertyKey: propertyName).map(\.rawValue))
            }
        }
        var notes: [String: ComputedNote] = [:]
        for (path, revision) in revisions where !pathsToCompute.contains(path) {
            if let known = previous?.notes[path], known.fileRevision == revision { notes[path] = known }
        }
        for chunk in Self.chunks(of: pathsToCompute.filter { path in revisions[path] != nil }.sorted(), size: Self.noteChunkSize) {
            try Task.checkCancellation()
            for note in try await index.indexedNotes(atPaths: chunk) {
                let content = MirroredNoteContent(note: note, columnsByKey: columnsByKey, placePropertyNames: vault.placePropertyNames)
                notes[note.record.path.rawValue] = ComputedNote(fileRevision: note.revision, contentDigest: try MirrorJSON.digest(of: content))
            }
        }
        let state = ComputedVaultState(notes: notes, linksDigests: linksDigests, linkResolutionState: linkResolutionState, columns: columns,
                                       declaredPropertyTypes: vault.declaredPropertyTypes, placePropertyNames: vault.placePropertyNames)
        return (state, resolvedLinks)
    }

    private func write(_ vault: MirroredVault, indexedDigests: [String: CopiedNoteDigests], columns: [MirroredPropertyColumn],
                       resolvedLinks: ResolvedLinks, index: VaultIndex, connection: PostgresConnection,
                       start: Duration) async throws -> PostgreSQLMirrorReport {
        let server = try await serverState(on: connection)
        let addsGeometry = try await prepareSchema(on: connection, postGISSchema: server.postGISSchema)
        let columnsByKey = Self.columnsByKey(columns)
        try await run("BEGIN", on: connection)
        do {
            try await run(statements.vaultRegistration, on: connection, vault.name)
            try await run(statements.vaultLock, on: connection, vault.name)
            var copyNumber: Int64 = 0
            for try await number in try await query(statements.copyNumberSelection, on: connection, vault.name).decode(Int64.self) { copyNumber = number }
            var copiedNotes: [String: CopiedNoteDigests]
            if let copiedState = copiedStates[vault.name], copiedState.copyNumber == copyNumber {
                copiedNotes = copiedState.notes
            } else {
                copiedNotes = [:]
                for try await (path, contentDigest, linksDigest) in try await query(statements.copiedNoteSelection, on: connection, vault.name)
                    .decode((String, String, String).self) {
                    copiedNotes[path] = CopiedNoteDigests(contentDigest: contentDigest, linksDigest: linksDigest)
                }
            }
            let plan = PostgreSQLMirrorPlan(indexedNotes: indexedDigests, copiedNotes: copiedNotes)

            for chunk in Self.chunks(of: plan.notePathsToDelete, size: Self.pathChunkSize) {
                try await run(statements.noteDeletion, on: connection, vault.name, chunk)
                for path in chunk { copiedNotes[path] = nil }
            }
            // Links resolved for the digests are written as they are; the notes the database holds
            // differently though they did not change here (another device's copy) are resolved
            // now, all at once: the resolver reads every path and alias each time it is built.
            var linksByNote = resolvedLinks.linksByNote
            let unresolvedPaths = plan.notePathsToWrite.filter { path in !resolvedLinks.resolvedPaths.contains(path) }
            if !unresolvedPaths.isEmpty {
                linksByNote.merge(try await index.resolvedLinks(ofNotesAt: unresolvedPaths)) { _, resolvedNow in resolvedNow }
            }
            var writtenNoteCount = 0
            var rewrittenLinkSourceCount = 0
            for chunk in Self.chunks(of: plan.notePathsToWrite, size: Self.noteChunkSize) {
                try Task.checkCancellation()
                // Read again rather than kept from the digests' pass, so memory follows one chunk.
                // A note that changed since is written as it is now.
                let notes = try await index.indexedNotes(atPaths: chunk)
                var noteRows: [MirroredNoteRow] = []
                var linkSourcePaths: [String] = []
                var linkRows: [MirroredLinkRow] = []
                for note in notes {
                    let path = note.record.path.rawValue
                    let links = linksByNote[path] ?? []
                    let content = MirroredNoteContent(note: note, columnsByKey: columnsByKey, placePropertyNames: vault.placePropertyNames)
                    let digests = CopiedNoteDigests(contentDigest: try MirrorJSON.digest(of: content), linksDigest: Self.linksDigest(of: links))
                    noteRows.append(MirroredNoteRow(content: content, digests: digests))
                    if copiedNotes[path]?.linksDigest != digests.linksDigest {
                        linkSourcePaths.append(path)
                        linkRows += MirroredLinkRow.rows(for: links, from: path)
                    }
                }
                guard !noteRows.isEmpty else { continue }
                try await run(statements.noteUpsert, on: connection, vault.name, try MirrorJSON.encodedText(noteRows))
                if !linkSourcePaths.isEmpty {
                    try await run(statements.linkDeletion, on: connection, vault.name, linkSourcePaths)
                    if !linkRows.isEmpty { try await run(statements.linkInsertion, on: connection, vault.name, try MirrorJSON.encodedText(linkRows)) }
                }
                for row in noteRows { copiedNotes[row.content.path] = row.digests }
                writtenNoteCount += noteRows.count
                rewrittenLinkSourceCount += linkSourcePaths.count
            }

            let changesColumns = try await replacePropertyColumns(of: vault, with: columns, on: connection)
            let viewExists = try await exists(statements.notesWithPropertiesExistence, on: connection)
            if changesColumns || addsGeometry || !viewExists {
                try await replaceViews(postGISSchema: server.postGISSchema, validatesInput: server.validatesInput, on: connection)
            }
            if !plan.isEmpty || changesColumns || addsGeometry || !viewExists {
                for try await number in try await query(statements.copyNumberIncrement, on: connection, vault.name).decode(Int64.self) { copyNumber = number }
                try await run(PostgreSQLMirrorStatements.notification, on: connection)
            }
            try await run("COMMIT", on: connection)
            copiedStates[vault.name] = CopiedVaultState(copyNumber: copyNumber, notes: copiedNotes)
            return PostgreSQLMirrorReport(copiedNoteCount: copiedNotes.count, writtenNoteCount: writtenNoteCount,
                                          deletedNoteCount: plan.notePathsToDelete.count, rewrittenLinkSourceCount: rewrittenLinkSourceCount,
                                          hasGeometry: server.postGISSchema != nil, didConnect: true, elapsedSeconds: seconds(since: start))
        } catch {
            try? await run("ROLLBACK", on: connection) // The server rolls the transaction back itself when the connection ends.
            throw error
        }
    }

    /// Creates the schema the first time, and the geometry column once PostGIS is installed.
    /// Returns whether the geometry column was added now, which the views must then show.
    private func prepareSchema(on connection: PostgresConnection, postGISSchema: String?) async throws -> Bool {
        if !hasPreparedSchema {
            let propertyColumnsTable = PostgreSQLMirrorStatements.quotedLiteral(statements.schema + ".property_columns")
            let tablesExist = try await exists("SELECT to_regclass(\(propertyColumnsTable)) IS NOT NULL", on: connection)
            if !tablesExist {
                // Creating a schema needs a right on the database that using an existing one does not.
                var statementsToRun = statements.schemaCreation
                if try await exists("SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = $1)", on: connection, configuration.schemaName) {
                    statementsToRun.removeFirst()
                }
                for statement in statementsToRun { try await run(statement, on: connection) }
            }
            hasPreparedSchema = true
        }
        guard let postGISSchema else { return false }
        let hasGeometry = try await exists("""
            SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = $1 AND table_name = 'notes' AND column_name = 'geometry')
            """, on: connection, configuration.schemaName)
        guard !hasGeometry else { return false }
        for statement in statements.geometryColumnCreation(postGISSchema: postGISSchema) { try await run(statement, on: connection) }
        return true
    }

    /// Records the vault's properties for the view; returns whether their names or types changed.
    private func replacePropertyColumns(of vault: MirroredVault, with columns: [MirroredPropertyColumn],
                                        on connection: PostgresConnection) async throws -> Bool {
        var storedTypes: [String: String] = [:]
        let storedColumns = try await query(statements.vaultPropertyColumnSelection, on: connection, vault.name).decode((String, String).self)
        for try await (propertyName, propertyType) in storedColumns {
            storedTypes[propertyName] = propertyType
        }
        let currentTypes = Dictionary(columns.map { column in (column.propertyName, column.propertyType.rawValue) }, uniquingKeysWith: { first, _ in first })
        try await run(statements.vaultPropertyColumnDeletion, on: connection, vault.name)
        let rows = columns.map { column in
            MirroredPropertyColumnRow(propertyName: column.propertyName, propertyType: column.propertyType.rawValue, noteCount: column.noteCount)
        }
        if !rows.isEmpty { try await run(statements.vaultPropertyColumnInsertion, on: connection, vault.name, try MirrorJSON.encodedText(rows)) }
        return storedTypes != currentTypes
    }

    /// Defines `notes_with_properties` from every vault's properties, and `links_on_map` with PostGIS.
    private func replaceViews(postGISSchema: String?, validatesInput: Bool, on connection: PostgresConnection) async throws {
        var columns: [MirroredPropertyColumn] = []
        for try await (propertyName, propertyTypeText, noteCount) in try await query(statements.allPropertyColumnSelection, on: connection)
            .decode((String, String, Int32).self) {
            guard let propertyType = PropertyType(rawValue: propertyTypeText) else { continue }
            columns.append(MirroredPropertyColumn(propertyName: propertyName, propertyType: propertyType, noteCount: Int(noteCount)))
        }
        // Dropped and created, not replaced: a replaced view cannot lose or retype a column.
        // A view of the person's own that reads this one makes the drop fail, and the copy says so.
        try await run("DROP VIEW IF EXISTS \(statements.schema).notes_with_properties", on: connection)
        try await run(statements.notesWithPropertiesView(columns: columns, postGISSchema: postGISSchema, validatesInput: validatesInput), on: connection)
        if let postGISSchema { try await run(statements.linksOnMapView(postGISSchema: postGISSchema), on: connection) }
    }

    // MARK: Digests

    static func columnsByKey(_ columns: [MirroredPropertyColumn]) -> [String: MirroredPropertyColumn] {
        Dictionary(columns.map { column in (column.propertyName.lowercased(), column) }, uniquingKeysWith: { first, _ in first })
    }

    static let emptyLinksDigest = linksDigest(of: [])

    /// The first 128 bits of the SHA-256 of a note's links, each written as its target, its
    /// destination and its two flags. Bytes are joined by hand rather than encoded as JSON:
    /// this runs for every note whenever a file is added or renamed.
    static func linksDigest(of links: [ResolvedNoteLink]) -> String {
        var bytes: [UInt8] = []
        for link in links {
            bytes += link.target.utf8
            bytes.append(0)
            bytes += (link.destination?.rawValue ?? "").utf8
            bytes += [0, link.destination == nil ? 0 : 1, link.isEmbed ? 1 : 0, link.isInProperties ? 1 : 0, 0x1E]
        }
        return SHA256.hash(data: bytes).prefix(16).map { byte in String(format: "%02x", byte) }.joined()
    }

    // MARK: Queries

    private func query(_ sql: String, on connection: PostgresConnection, _ firstValue: String? = nil,
                       _ paths: [String]? = nil) async throws -> PostgresRowSequence {
        var bindings = PostgresBindings()
        if let firstValue { bindings.append(firstValue) }
        if let paths { bindings.append(paths) }
        return try await connection.query(PostgresQuery(unsafeSQL: sql, binds: bindings), logger: logger)
    }

    private func run(_ sql: String, on connection: PostgresConnection, _ firstValue: String? = nil, _ paths: [String]) async throws {
        _ = try await query(sql, on: connection, firstValue, paths)
    }

    private func run(_ sql: String, on connection: PostgresConnection, _ firstValue: String? = nil, _ secondValue: String? = nil) async throws {
        var bindings = PostgresBindings()
        if let firstValue { bindings.append(firstValue) }
        if let secondValue { bindings.append(secondValue) }
        _ = try await connection.query(PostgresQuery(unsafeSQL: sql, binds: bindings), logger: logger)
    }

    private func exists(_ sql: String, on connection: PostgresConnection, _ value: String? = nil) async throws -> Bool {
        var answer = false
        for try await isTrue in try await query(sql, on: connection, value).decode(Bool.self) { answer = isTrue }
        return answer
    }

    static func chunks(of paths: [String], size: Int) -> [[String]] {
        stride(from: 0, to: paths.count, by: size).map { chunkStart in Array(paths[chunkStart..<min(chunkStart + size, paths.count)]) }
    }

    private func seconds(since start: Duration) -> Double {
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}
