import Foundation

/// Where the PostgreSQL Mirror copies the vault. The password is kept apart, in the keychain.
public struct PostgreSQLMirrorConfiguration: Codable, Hashable, Sendable {
    /// Whether the connection is encrypted, in the terms of PostgreSQL's own `sslmode`.
    public enum TransportSecurity: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Encrypted when the server offers it, without checking its certificate (`prefer`).
        case preferred
        /// Always encrypted, and only to a server whose certificate is valid for its name (`verify-full`).
        case verified
        /// Never encrypted, for a server on this device or a network the person trusts (`disable`).
        case off

        public var id: String { rawValue }
    }

    public static let defaultPort = 5432
    public static let defaultSchemaName = "graphite"

    public var host: String
    public var port: Int
    public var databaseName: String
    public var userName: String
    /// The PostgreSQL schema the mirror's tables and views live in, created if missing.
    public var schemaName: String
    public var transportSecurity: TransportSecurity

    public init(host: String = "", port: Int = defaultPort, databaseName: String = "", userName: String = "",
                schemaName: String = defaultSchemaName, transportSecurity: TransportSecurity = .preferred) {
        self.host = host
        self.port = port
        self.databaseName = databaseName
        self.userName = userName
        self.schemaName = schemaName
        self.transportSecurity = transportSecurity
    }

    /// What must still be filled in before a copy can start, in words for the settings page;
    /// nil when nothing is missing.
    public var missingSetting: String? {
        if Self.trimmed(host).isEmpty { return "the server's address" }
        if !(1...65_535).contains(port) { return "a port between 1 and 65535" }
        if Self.trimmed(databaseName).isEmpty { return "the database's name" }
        if Self.trimmed(userName).isEmpty { return "the user's name" }
        if Self.trimmed(schemaName).isEmpty { return "the schema's name" }
        return nil
    }

    /// The settings as they are sent: without the spaces a pasted value often carries.
    var trimmedForConnection: PostgreSQLMirrorConfiguration {
        PostgreSQLMirrorConfiguration(host: Self.trimmed(host), port: port, databaseName: Self.trimmed(databaseName),
                                      userName: Self.trimmed(userName), schemaName: Self.trimmed(schemaName), transportSecurity: transportSecurity)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
