import Foundation
import GraphiteCore

/// Recordings Graphite did not finish, offered back when their vault is open.
extension WorkspaceModel {
    /// Unfinished recordings that belong to the open vault, or to no known vault.
    func recordingsToRecover() -> [RecoverableRecording] {
        let knownVaults = Set(vaultLibrary.vaults.map(\.id))
        return recording.unfinishedRecordings().filter { unfinished in
            guard let vaultIdentifier = unfinished.manifest?.vaultIdentifier, knownVaults.contains(vaultIdentifier) else { return true }
            return vaultIdentifier == currentVaultIdentifier
        }
    }

    /// Looks for unfinished recordings, as after the app stopped while recording.
    func checkForUnfinishedRecordings() {
        guard store != nil, !recording.state.isActive else { return }
        recordingRecoveryOffer = recordingsToRecover().first
    }

    /// Saves an unfinished recording where it was meant to go, beside anything already
    /// there, or in the attachment folder when that is unknown.
    func recover(_ unfinished: RecoverableRecording) async {
        guard let store, let root = folderAccess?.root else { return }
        do {
            let intended = unfinished.destination
            let directory = intended?.parent ?? newFileDirectory(nil)
            let stem = intended?.stem ?? "Recovered recording " + unfinished.startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: stem, extension: "m4a")
            try await recording.recover(unfinished, to: try path.url(in: root))
            await refreshDirectory()
            refreshIndex(for: [path])
            await open(path)
        } catch { errorMessage = error.localizedDescription }
        checkForUnfinishedRecordings()
    }

    func discard(_ unfinished: RecoverableRecording) {
        do { try RecordingRecoveryFolder.remove(unfinished) } catch { errorMessage = error.localizedDescription }
        checkForUnfinishedRecordings()
    }
}
