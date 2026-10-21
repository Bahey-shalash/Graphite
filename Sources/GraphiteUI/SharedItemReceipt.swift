import Foundation
import ShareInbox
import GraphiteCore

/// What one pass over the share inbox delivered, and what the person is told about it.
struct SharedItemReceipt {
    private(set) var openVaultNotes: [VaultPath] = []
    /// The notes and files written into the open vault, for its index and file list.
    private(set) var openVaultPaths: [VaultPath] = []
    private(set) var openVaultName = ""
    /// How many items went to each other vault, by its name.
    private(set) var otherVaultCounts: [String: Int] = [:]
    /// Items whose chosen vault left the vault list, delivered to the open vault instead.
    private(set) var redirectedCount = 0

    var isEmpty: Bool { openVaultNotes.isEmpty && otherVaultCounts.isEmpty }

    mutating func record(_ outcome: SharedItemDeliveryOutcome, inVault vaultName: String, isOpenVault: Bool, wasChosenVaultMissing: Bool) {
        guard isOpenVault else {
            otherVaultCounts[vaultName, default: 0] += 1
            return
        }
        openVaultName = vaultName
        openVaultNotes.append(outcome.notePath)
        openVaultPaths.append(contentsOf: [outcome.notePath] + outcome.attachmentPaths)
        if wasChosenVaultMissing { redirectedCount += 1 }
    }

    /// The note opened afterwards: the only one, when everything shared went to the open vault.
    var noteToOpen: VaultPath? {
        openVaultNotes.count == 1 && otherVaultCounts.isEmpty ? openVaultNotes.first : nil
    }

    var notice: String {
        var sentences: [String] = []
        if openVaultNotes.count == 1, let notePath = openVaultNotes.first {
            sentences.append("Added what you shared to “\(notePath.stem)”.")
        } else if !openVaultNotes.isEmpty {
            sentences.append("Added \(openVaultNotes.count) shared items to “\(openVaultName)”.")
        }
        for (vaultName, count) in otherVaultCounts.sorted(by: { first, second in first.key < second.key }) {
            sentences.append(count == 1 ? "Added a shared item to “\(vaultName)”." : "Added \(count) shared items to “\(vaultName)”.")
        }
        if redirectedCount > 0 {
            sentences.append("The vault chosen when sharing is no longer in Graphite's vault list, so “\(openVaultName)” received it.")
        }
        return sentences.joined(separator: " ")
    }
}
