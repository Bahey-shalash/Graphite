import Foundation
import GraphiteCore
import GraphiteIndex

/// Everything a copy reads from the open vault, taken when the copy is asked for: its name in
/// the database, its index and store, its folder (for the plugins that name its place
/// properties) and the server settings.
public struct PostgreSQLMirrorSource: Sendable {
    public let vaultName: String
    public let index: VaultIndex
    public let store: VaultStore
    public let vaultRoot: URL
    public let configuration: PostgreSQLMirrorConfiguration

    public init(vaultName: String, index: VaultIndex, store: VaultStore, vaultRoot: URL, configuration: PostgreSQLMirrorConfiguration) {
        self.vaultName = vaultName
        self.index = index
        self.store = store
        self.vaultRoot = vaultRoot
        self.configuration = configuration
    }
}
