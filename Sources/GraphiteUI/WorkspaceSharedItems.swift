import Foundation
import ShareInbox
import GraphiteCore
import GraphiteApple

/// What other apps shared to Graphite. The share extension cannot reach a vault, so it
/// leaves each share in the App Group's inbox; here, when Graphite starts and each time it
/// becomes active, every item goes into the vault chosen in the share sheet, through the
/// vault's own settings (`SharedItemDelivery`). An item leaves the inbox only once it is in
/// the vault; one that fails stays for the next time, and the person is told why.
extension WorkspaceModel {
    /// Delivers every item in the share inbox, then opens the note when one item went to the
    /// open vault. `now` dates a failure in the item's record and ages abandoned drafts.
    func receiveSharedItems(at now: Date) async {
        guard let receiver = sharedItemReceiver else { return }
        await receiver.receiveInPasses { await deliverSharedItems(with: receiver, at: now) }
    }

    private func deliverSharedItems(with receiver: SharedItemReceiver, at now: Date) async {
        let entries: [ShareInboxEntry]
        do {
            entries = try await receiver.pendingEntries(now: now)
        } catch {
            errorMessage = SharedItemFailureMessage.inboxUnreadable(error)
            return
        }
        var receipt = SharedItemReceipt()
        var otherVaults: [UUID: OtherVaultTarget] = [:]
        for entry in entries {
            switch entry {
            case .unreadable(let folder, let error):
                reportShareFailure(SharedItemFailureMessage.unreadable(error), ofItemIn: folder, receiver: receiver)
            case .item(let item):
                await deliverSharedItem(item, with: receiver, at: now, receipt: &receipt, otherVaults: &otherVaults)
            }
        }
        await finishReceiving(receipt)
    }

    /// The vault an item goes to and the store that writes it.
    private struct SharedItemTarget {
        let vaultIdentifier: UUID
        let vaultName: String
        let store: VaultStore
        let isOpenVault: Bool
    }

    /// A vault other than the open one, opened for delivery only, for as long as `access` lives.
    private struct OtherVaultTarget {
        let access: FolderAccess
        let target: SharedItemTarget
    }

    private func deliverSharedItem(_ item: PendingSharedItem, with receiver: SharedItemReceiver, at now: Date, receipt: inout SharedItemReceipt,
                                   otherVaults: inout [UUID: OtherVaultTarget]) async {
        do {
            // Nothing can be delivered before a vault is open: the item waits.
            guard let target = try await sharedItemTarget(for: item.manifest, otherVaults: &otherVaults) else { return }
            let delivery = SharedItemDelivery(store: target.store, inbox: receiver.inbox, vaultIdentifier: target.vaultIdentifier, timeZone: .current,
                                              maximumNoteBytes: MarkdownSession.maximumEditableBytes)
            let outcome = try await delivery.deliver(item, now: now, embedText: embedTextForSharedItem(isOpenVault: target.isOpenVault),
                                                     appendToExistingNote: appendingForSharedItem(store: target.store, isOpenVault: target.isOpenVault))
            receipt.record(outcome, inVault: target.vaultName, isOpenVault: target.isOpenVault, wasChosenVaultMissing: isChosenVaultMissing(item.manifest))
            try await receiver.removeDeliveredItem(item)
        } catch {
            let vaultName = item.manifest.vaultName ?? title
            reportShareFailure(SharedItemFailureMessage.notDelivered(title: item.manifest.title, vaultName: vaultName, error: error),
                               ofItemIn: item.folder, receiver: receiver)
        }
    }

    /// The vault chosen in the share sheet: the open one, another known one reached through
    /// its saved location, or the open one when the chosen vault is no longer in the list.
    private func sharedItemTarget(for manifest: SharedItemManifest, otherVaults: inout [UUID: OtherVaultTarget]) async throws -> SharedItemTarget? {
        guard let store, let currentVaultIdentifier else { return nil }
        let openTarget = SharedItemTarget(vaultIdentifier: currentVaultIdentifier, vaultName: title, store: store, isOpenVault: true)
        guard let chosenIdentifier = manifest.vaultIdentifier, chosenIdentifier != currentVaultIdentifier,
              let chosenVault = vaultLibrary.vault(withIdentifier: chosenIdentifier) else { return openTarget }
        if let opened = otherVaults[chosenIdentifier] { return opened.target }
        let (access, _) = try await VaultLocator.accessInBackground(chosenVault.location)
        let target = SharedItemTarget(vaultIdentifier: chosenIdentifier, vaultName: chosenVault.name, store: VaultStore(root: access.root), isOpenVault: false)
        otherVaults[chosenIdentifier] = OtherVaultTarget(access: access, target: target)
        return target
    }

    private func isChosenVaultMissing(_ manifest: SharedItemManifest) -> Bool {
        guard let chosenIdentifier = manifest.vaultIdentifier else { return false }
        return vaultLibrary.vault(withIdentifier: chosenIdentifier) == nil
    }

    /// Embeds as the open vault writes them (a shortest link once the index proves the name
    /// unique); in another vault, whose index is not open, the full path.
    private func embedTextForSharedItem(isOpenVault: Bool) -> SharedItemDelivery.EmbedText {
        guard isOpenVault else {
            let resolver = resolver
            return { attachment, note, settings in resolver.embed(attachment: attachment, note: note, settings: settings, isNameUniqueInVault: false) }
        }
        return { [weak self] attachment, note, settings in
            guard let self else { return AttachmentResolver().embed(attachment: attachment, note: note, settings: settings, isNameUniqueInVault: false) }
            return await self.embed(for: attachment, in: note, settings: settings)
        }
    }

    /// Adds to a note open in the open vault through its editor, so it shows at once and can
    /// be undone, and saves it; any other note through its file.
    private func appendingForSharedItem(store: VaultStore, isOpenVault: Bool) -> SharedItemDelivery.NoteAppending {
        let appendingInFile = SharedItemDelivery.appendingInFile(store: store, maximumNoteBytes: MarkdownSession.maximumEditableBytes)
        guard isOpenVault else { return appendingInFile }
        return { [weak self] note, block in
            guard let self, try await self.appendThroughOpenEditor(block, to: note) else {
                try await appendingInFile(note, block)
                return
            }
        }
    }

    /// Appends `block` through the note's open editor; false when the note is not open. A
    /// note in conflict with another app's version is refused, so the item waits for it.
    private func appendThroughOpenEditor(_ block: String, to note: VaultPath) async throws -> Bool {
        guard let session = openMarkdownSession(at: note) else { return false }
        guard !session.hasExternalConflict else { throw GraphiteError.conflict }
        let suffix = SharedNoteComposition.suffixAppending(block, to: session.text)
        let endLocation = (session.text as NSString).length
        session.apply(MarkdownTextEdit(range: NSRange(location: endLocation, length: 0), replacement: suffix, selectionAfter: session.selection))
        // Saved now, with the editor's queued insertions: the item leaves the inbox only once the text is in the file.
        try await session.save()
        return true
    }

    private func reportShareFailure(_ message: String, ofItemIn folder: URL, receiver: SharedItemReceiver) {
        guard receiver.isNewFailure(message, ofItemIn: folder) else { return }
        errorMessage = message
    }

    /// Shows what arrived: the open vault's files are refreshed, and a single note shared
    /// to it opens in a tab of its own.
    private func finishReceiving(_ receipt: SharedItemReceipt) async {
        guard !receipt.isEmpty else { return }
        if !receipt.openVaultPaths.isEmpty {
            filesSavedOutsideEditors(receipt.openVaultPaths)
            await refreshDirectory()
        }
        notice = receipt.notice
        if let notePath = receipt.noteToOpen { await open(notePath, placement: .newTab) }
    }
}
