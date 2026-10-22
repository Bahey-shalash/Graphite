import Foundation
import PostgresNIO

/// The server a connection reached.
public struct PostgreSQLServerDescription: Equatable, Sendable {
    public let version: String
    /// The PostGIS version installed in the database; nil without PostGIS.
    public let postGISVersion: String?
}

/// Connects to the PostgreSQL server the vault's notes are copied into, and says what it is.
public actor PostgreSQLMirror {
    private let configuration: PostgreSQLMirrorConfiguration
    private let password: String
    private let logger: Logger

    public init(configuration: PostgreSQLMirrorConfiguration, password: String) {
        self.configuration = configuration.trimmedForConnection
        self.password = password
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
}
