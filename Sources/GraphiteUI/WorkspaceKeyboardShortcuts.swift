import Foundation
import GraphiteCore

/// The open vault's keyboard shortcuts (`VaultKeyboardShortcuts`), read from and written to its
/// `.obsidian/hotkeys.json` so the vault has the same shortcuts in Obsidian.
extension WorkspaceModel {
    /// Reads the vault's shortcuts again. A file that has just become unreadable is reported
    /// once; the default shortcuts apply and the file is left as it is.
    func reloadKeyboardShortcuts(from store: VaultStore) async {
        let reading = await VaultKeyboardShortcuts.reading(from: store)
        if let reason = reading.unreadableReason, keyboardShortcuts.fileReading.unreadableReason != reason {
            errorMessage = "Graphite could not read this vault’s keyboard shortcuts, so the default shortcuts are in use. The file is left as it is. " + reason
        }
        keyboardShortcuts.show(reading)
    }

    /// Makes a change from Settings › Keyboard Shortcuts in the vault's file.
    func changeKeyboardShortcuts(_ change: HotkeyChange) async {
        guard let store else { return }
        do {
            try await keyboardShortcuts.apply(change, pluginCommands: communityPlugins.commands, in: store)
        } catch {
            let reason = (error as? HotkeyFileProblem)?.explanation ?? (error as? GraphiteError)?.errorDescription ?? HotkeyFileProblem.unreadableExplanation
            errorMessage = "The keyboard shortcuts could not be saved in “\(HotkeyFile.configurationPath)”. " + reason
        }
    }
}
