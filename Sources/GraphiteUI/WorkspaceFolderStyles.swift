import Foundation
import GraphiteCore

/// Folder colors and symbols follow their folders when Graphite renames, moves or deletes
/// them, as bookmarks do. The library reads them again on its next listing.
extension WorkspaceModel {
    func followMoveInFolderStyles(from oldPath: VaultPath, to newPath: VaultPath) {
        updateFolderStyles { styles in styles.followMove(from: oldPath, to: newPath) }
    }

    func forgetFolderStyles(inside removedPath: VaultPath) {
        updateFolderStyles { styles in styles.forget(removedPath) }
    }

    private func updateFolderStyles(_ change: @escaping @Sendable (inout FolderStyleList) -> Void) {
        guard let store else { return }
        Task {
            do { _ = try await store.updateFolderStyles(change) }
            catch { errorMessage = "Folder colors in “.obsidian/graphite-folder-styles.json” could not be updated. The folders themselves are unchanged." }
        }
    }
}
