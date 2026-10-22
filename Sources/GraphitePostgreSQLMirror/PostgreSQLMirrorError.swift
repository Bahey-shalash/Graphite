import Foundation
import PostgresNIO

/// Why a connection or a copy failed, as values the settings page words. PostgresNIO's own
/// description is deliberately generic, so the server's message is read out of the error.
public enum PostgreSQLMirrorError: Error, Equatable {
    /// The server (`host:port`) answered the connection with an error: its message, detail and hint.
    case connectionRefused(server: String, message: String)
    /// The settings ask for encryption and the server does not offer it.
    case encryptionUnavailable(server: String)
    /// Nothing answered at `server`; `reason` is the network's.
    case unreachable(server: String, reason: String)
    /// The server refused a statement of the copy: its message, detail and hint.
    case copyRefused(message: String)
    /// The copy stopped for another reason.
    case copyStopped(reason: String)

    static func connecting(_ error: any Error, to configuration: PostgreSQLMirrorConfiguration) -> PostgreSQLMirrorError {
        let server = "\(configuration.host):\(configuration.port)"
        if let serverMessage = serverMessage(of: error) { return .connectionRefused(server: server, message: serverMessage) }
        if let postgresError = error as? PSQLError, postgresError.code == .sslUnsupported { return .encryptionUnavailable(server: server) }
        // Network.framework keeps retrying a refused connection, so a wrong port or a stopped
        // server usually ends in the connection timeout rather than in a refusal.
        return .unreachable(server: server, reason: underlyingDescription(of: error))
    }

    static func running(_ error: any Error) -> PostgreSQLMirrorError {
        if let serverMessage = serverMessage(of: error) { return .copyRefused(message: serverMessage) }
        if let mirrorError = error as? PostgreSQLMirrorError { return mirrorError }
        return .copyStopped(reason: underlyingDescription(of: error))
    }

    /// The server's message with its detail and hint, as `psql` prints them.
    private static func serverMessage(of error: any Error) -> String? {
        guard let serverInformation = (error as? PSQLError)?.serverInfo, let message = serverInformation[.message] else { return nil }
        return [message, serverInformation[.detail], serverInformation[.hint]].compactMap { part in part }.joined(separator: " ")
    }

    private static func underlyingDescription(of error: any Error) -> String {
        if let postgresError = error as? PSQLError {
            if let underlying = postgresError.underlying { return underlyingDescription(of: underlying) }
            return "\(postgresError.code)"
        }
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription { return description }
        return String(describing: error)
    }
}
