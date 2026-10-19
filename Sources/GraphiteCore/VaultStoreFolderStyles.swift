import Foundation

/// Graphite's folder colors and symbols, read and written as bookmarks are.
extension VaultStore {
    /// Graphite's folder colors and symbols (`.obsidian/graphite-folder-styles.json`); none when missing.
    public func folderStyles() throws -> FolderStyleList {
        try FolderStyleList(configurationData: configurationData(at: FolderStyleList.configurationPath))
    }

    /// Changes the folder styles, keeping what other builds wrote. A vault gets the file only
    /// once there is a style to keep; an unchanged list leaves the file as it was.
    public func updateFolderStyles(_ change: (inout FolderStyleList) -> Void) throws -> FolderStyleList {
        var updated = FolderStyleList()
        if try configurationData(at: FolderStyleList.configurationPath) == nil {
            change(&updated)
            if updated.styles.isEmpty { return updated }
            updated = FolderStyleList()
        }
        try saveConfiguration(at: FolderStyleList.configurationPath) { existingData in
            let existing = try FolderStyleList(configurationData: existingData)
            updated = existing
            change(&updated)
            if updated == existing, let existingData { return existingData }
            return try updated.configurationData()
        }
        return updated
    }
}
