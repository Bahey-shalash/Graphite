import Foundation
import GraphiteCore

/// The view a note was left in, reading, Live Preview or source, remembered on the device as
/// folds are, never in the vault. Settings › Editor › Remember View chooses whether each note
/// keeps its own view or the vault keeps one view that every note opens in. A note with
/// nothing remembered opens in "Default view for new notes".
extension WorkspaceModel {
    /// Per note: a dictionary from a note's vault path to its view.
    static func noteViewsKey(for vaultIdentifier: UUID) -> String {
        "GraphiteNoteViews." + vaultIdentifier.uuidString
    }

    /// Per vault: the one view of the vault.
    static func vaultNoteViewKey(for vaultIdentifier: UUID) -> String {
        "GraphiteVaultNoteView." + vaultIdentifier.uuidString
    }

    private var noteViewsByPath: [String: String] {
        get {
            guard let currentVaultIdentifier else { return [:] }
            return deviceDefaults.dictionary(forKey: Self.noteViewsKey(for: currentVaultIdentifier)) as? [String: String] ?? [:]
        }
        set {
            guard let currentVaultIdentifier else { return }
            deviceDefaults.set(newValue, forKey: Self.noteViewsKey(for: currentVaultIdentifier))
        }
    }

    private var vaultNoteView: NoteViewMode? {
        get {
            guard let currentVaultIdentifier else { return nil }
            let storedView = deviceDefaults.string(forKey: Self.vaultNoteViewKey(for: currentVaultIdentifier))
            return storedView.flatMap(NoteViewMode.init(rawValue:))
        }
        set {
            guard let currentVaultIdentifier else { return }
            deviceDefaults.set(newValue?.rawValue, forKey: Self.vaultNoteViewKey(for: currentVaultIdentifier))
        }
    }

    /// Opens a note that was just read in its remembered view, and keeps each switch.
    func restoreViewMode(of session: MarkdownSession) {
        let path = session.path
        let rememberedView: NoteViewMode? = switch preferences.noteViewMemory {
        case .perNote: noteViewsByPath[path.rawValue].flatMap(NoteViewMode.init(rawValue:))
        case .perVault: vaultNoteView
        }
        session.viewMode = rememberedView ?? preferences.initialNoteViewMode
        session.didChangeViewMode = { [weak self] viewMode in
            guard let self else { return }
            switch preferences.noteViewMemory {
            case .perNote:
                var views = noteViewsByPath
                views[path.rawValue] = viewMode.rawValue
                noteViewsByPath = views
            case .perVault:
                vaultNoteView = viewMode
            }
        }
    }

    /// Keeps views with their notes when a file or folder is renamed or moved.
    func followMoveInNoteViews(from oldPath: VaultPath, to newPath: VaultPath) {
        var views = noteViewsByPath
        var changed = false
        for (rawPath, view) in views {
            // A stored path that no longer parses, or moves nowhere valid, stays as it was.
            guard let path = try? VaultPath(rawPath), path.isInside(oldPath), // harmless: kept as it was
                  let movedPath = try? path.replacingPrefix(oldPath, with: newPath) else { continue } // harmless: kept as it was
            views[rawPath] = nil
            views[movedPath.rawValue] = view
            changed = true
        }
        if changed { noteViewsByPath = views }
    }

    func forgetNoteViews(inside removedPath: VaultPath) {
        var views = noteViewsByPath
        let removed = views.keys.filter { rawPath in (try? VaultPath(rawPath))?.isInside(removedPath) == true } // unparsable: not inside
        guard !removed.isEmpty else { return }
        for rawPath in removed { views[rawPath] = nil }
        noteViewsByPath = views
    }
}
