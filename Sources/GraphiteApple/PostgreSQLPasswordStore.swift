import Foundation
import Security

/// The PostgreSQL Mirror's password, in the device's keychain: never in the vault, which may
/// sync or be shared, nor in the preferences.
public struct PostgreSQLPasswordStore: Sendable {
    private static let service = "Graphite PostgreSQL Mirror"

    public init() {}

    private var item: KeychainGenericPasswordItem {
        KeychainGenericPasswordItem(service: Self.service, account: "password")
    }

    /// The stored password; empty when none is stored, as for a server that asks for none.
    public func password() -> String {
        let (status, data) = item.read()
        guard status == errSecSuccess, let data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Keeps `password`, or forgets the stored one when it is empty.
    public func setPassword(_ password: String) throws {
        guard !password.isEmpty else {
            let status = item.delete()
            guard status == errSecSuccess || status == errSecItemNotFound else { throw PostgreSQLPasswordError(status: status) }
            return
        }
        let status = item.write(Data(password.utf8))
        guard status == errSecSuccess else { throw PostgreSQLPasswordError(status: status) }
    }
}

public struct PostgreSQLPasswordError: LocalizedError {
    let status: OSStatus
    public var errorDescription: String? { "The keychain did not keep the password (\(status))." }
}
