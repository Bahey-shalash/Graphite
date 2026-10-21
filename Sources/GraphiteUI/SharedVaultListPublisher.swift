import Foundation
import OSLog
import ShareInbox
import GraphiteCore

/// Writes the vault list the share extension offers (`Known Vaults.json` in the App Group),
/// off the main actor. Lists arrive numbered; one older than the last written is dropped, so
/// the file always ends at the newest list whatever order the writes run in.
actor SharedVaultListPublisher {
    private static let logger = Logger(subsystem: "com.graphite.study", category: "ShareInbox")
    private let inbox: ShareInbox
    private var lastWrittenNumber = 0

    init(inbox: ShareInbox) {
        self.inbox = inbox
    }

    /// The names and identifiers of `vaults`, the only things the extension is told.
    nonisolated static func sharedList(of vaults: [KnownVault]) -> SharedVaultList {
        SharedVaultList(vaults: vaults.map { vault in SharedVaultList.Vault(id: vault.id, name: vault.name, lastOpenedDate: vault.lastOpenedDate) })
    }

    func publish(_ vaultList: SharedVaultList, number: Int) {
        guard number > lastWrittenNumber else { return }
        lastWrittenNumber = number
        do {
            try inbox.saveVaultList(vaultList)
        } catch {
            // The share sheet keeps the list written before; the next change of the list writes it again.
            Self.logger.error("The vault list for the share extension was not written: \(String(describing: error), privacy: .public)")
        }
    }
}
