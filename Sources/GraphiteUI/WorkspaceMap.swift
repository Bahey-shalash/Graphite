import Foundation
import GraphiteCore

/// The Map View core plugin.
extension WorkspaceModel {
    /// The notes the map places, read again only after the index takes in changes.
    func placedNotes() async -> [PlacedNote]? {
        guard let index else { return nil }
        let version = indexVersion
        if let placedNotesCache, placedNotesCache.indexVersion == version { return placedNotesCache.notes }
        do {
            let notes = try await index.placedNotes()
            placedNotesCache = (version, notes)
            return notes
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
