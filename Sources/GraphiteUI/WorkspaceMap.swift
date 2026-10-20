import Foundation
import GraphiteCore

/// The Map View core plugin.
extension WorkspaceModel {
    /// The notes the map places, read again after the index takes in changes or the vault's
    /// map plugins name other properties.
    func placedNotes() async -> [PlacedNote]? {
        guard let index, let root = folderAccess?.root else { return nil }
        let version = indexVersion
        let propertyNames = await Task.detached(priority: .userInitiated) { PlacedNote.propertyNames(vaultRoot: root) }.value
        if let placedNotesCache, placedNotesCache.indexVersion == version, placedNotesCache.propertyNames == propertyNames {
            return placedNotesCache.notes
        }
        do {
            let notes = try await index.placedNotes(propertyNames: propertyNames)
            // Notes of a vault left during the query are neither kept nor shown.
            guard self.index === index else { return nil }
            placedNotesCache = (version, propertyNames, notes)
            return notes
        } catch {
            if self.index === index { errorMessage = error.localizedDescription }
            return nil
        }
    }
}
