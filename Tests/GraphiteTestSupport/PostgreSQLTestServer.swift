import Foundation
import XCTest

/// The PostgreSQL server the PostgreSQL Mirror's tests copy into: a capability of the machine
/// that runs them, as on-device text recognition is. GitHub's runners have none, so those
/// tests skip there and say what to set; a Mac with a server runs them
/// (`Docs/Coverage.md` › PostgreSQL Mirror says how to start one).
///
/// - `GRAPHITE_POSTGRESQL_TEST_URL`: `postgres://user:password@host:port/database`, a
///   database with PostGIS.
/// - `GRAPHITE_POSTGRESQL_TEST_PLAIN_DATABASE`: a database of the same server without PostGIS.
/// - `GRAPHITE_POSTGRESQL_BENCHMARK_NOTES`: how many notes the benchmark's vault has.
public struct PostgreSQLTestServer: Sendable {
    public let host: String
    public let port: Int
    public let databaseName: String
    public let userName: String
    public let password: String

    /// The server, or a skip of the calling test when none is named.
    public static func require() throws -> PostgreSQLTestServer {
        guard let address = environment["GRAPHITE_POSTGRESQL_TEST_URL"], let components = URLComponents(string: address),
              let host = components.host, let userName = components.user else {
            try skip("Set GRAPHITE_POSTGRESQL_TEST_URL (postgres://user:password@host:port/database) to copy into a real server.")
        }
        return PostgreSQLTestServer(host: host, port: components.port ?? 5432, databaseName: String(components.path.dropFirst()),
                                    userName: userName, password: components.password ?? "")
    }

    /// A database of the server without PostGIS, or a skip of the calling test.
    public static func requirePlainDatabaseName() throws -> String {
        guard let databaseName = environment["GRAPHITE_POSTGRESQL_TEST_PLAIN_DATABASE"] else {
            try skip("Set GRAPHITE_POSTGRESQL_TEST_PLAIN_DATABASE to a database without PostGIS.")
        }
        return databaseName
    }

    /// The benchmark's number of notes, or a skip of the calling test.
    public static func requireBenchmarkNoteCount() throws -> Int {
        guard let countText = environment["GRAPHITE_POSTGRESQL_BENCHMARK_NOTES"], let noteCount = Int(countText) else {
            try skip("Set GRAPHITE_POSTGRESQL_BENCHMARK_NOTES to a number of notes.")
        }
        return noteCount
    }

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// The one place the mirror's tests skip, naming what to set.
    private static func skip(_ reason: String) throws -> Never {
        throw XCTSkip(reason)
    }
}
