import Foundation
import GraphiteCore

/// Folded headings and list items, remembered per note on the device as Obsidian keeps
/// them, never in the note itself.
extension WorkspaceModel {
    private static func foldsKey(for vaultIdentifier: UUID) -> String {
        "GraphiteFolds." + vaultIdentifier.uuidString
    }

    private var foldsByPath: [String: [String]] {
        get {
            guard let currentVaultIdentifier else { return [:] }
            return UserDefaults.standard.dictionary(forKey: Self.foldsKey(for: currentVaultIdentifier)) as? [String: [String]] ?? [:]
        }
        set {
            guard let currentVaultIdentifier else { return }
            UserDefaults.standard.set(newValue, forKey: Self.foldsKey(for: currentVaultIdentifier))
        }
    }

    /// Gives a note that was just opened its folds, and keeps them as they change.
    func restoreFolds(of session: MarkdownSession) {
        session.foldedKeys = Set(foldsByPath[session.path.rawValue] ?? [])
        let path = session.path
        session.didChangeFolds = { [weak self] keys in
            guard let self else { return }
            var folds = self.foldsByPath
            folds[path.rawValue] = keys.isEmpty ? nil : keys.sorted()
            self.foldsByPath = folds
        }
    }

    /// Keeps folds with their notes when a file or folder is renamed or moved.
    func followMoveInFolds(from oldPath: VaultPath, to newPath: VaultPath) {
        var folds = foldsByPath
        var changed = false
        for (rawPath, keys) in folds {
            guard let path = try? VaultPath(rawPath), path.isInside(oldPath),
                  let movedPath = try? path.replacingPrefix(oldPath, with: newPath) else { continue }
            folds[rawPath] = nil
            folds[movedPath.rawValue] = keys
            changed = true
        }
        if changed { foldsByPath = folds }
    }

    func forgetFolds(inside removedPath: VaultPath) {
        var folds = foldsByPath
        let removed = folds.keys.filter { rawPath in (try? VaultPath(rawPath))?.isInside(removedPath) == true }
        guard !removed.isEmpty else { return }
        for rawPath in removed { folds[rawPath] = nil }
        foldsByPath = folds
    }
}
