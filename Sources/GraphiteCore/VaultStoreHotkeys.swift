import Foundation

/// The vault's keyboard shortcuts in Obsidian's `.obsidian/hotkeys.json`.
extension VaultStore {
    /// The shortcuts the vault changed (`.obsidian/hotkeys.json`); none when missing. Throws a
    /// `HotkeyFileProblem` when the file is there and is not Obsidian's format.
    public func hotkeys() throws -> HotkeyFile {
        try HotkeyFile(configurationData: configurationData(at: HotkeyFile.configurationPath))
    }

    /// Applies `change` to the shortcuts as they are in the file now, so a change Obsidian made
    /// meanwhile is kept, and returns the result. A file that cannot be read is never written:
    /// the read throws first. A vault without the file gets one only when there is a change.
    @discardableResult
    public func updateHotkeys(_ change: @Sendable (HotkeyFile) -> HotkeyFile) throws -> HotkeyFile {
        if try configurationData(at: HotkeyFile.configurationPath) == nil, change(HotkeyFile()) == HotkeyFile() { return HotkeyFile() }
        var updated = HotkeyFile()
        try saveConfiguration(at: HotkeyFile.configurationPath) { existingData in
            let existing = try HotkeyFile(configurationData: existingData)
            updated = change(existing)
            // An unchanged file keeps its bytes.
            if updated == existing, let existingData { return existingData }
            return updated.configurationData()
        }
        return updated
    }
}
