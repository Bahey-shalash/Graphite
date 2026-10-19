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

    /// Moves a folder-color file this build cannot read to a free name beside it, such as
    /// `.obsidian/graphite-folder-styles.unreadable.json`, so it is kept as it is and
    /// Graphite can start a new one. Returns where it went.
    public func moveFolderStylesAside() throws -> VaultPath {
        let path = try VaultPath(FolderStyleList.configurationPath)
        let keptCopy = try uniquePath(directory: path.parent, stem: FolderStyleList.unreadableCopyStem, extension: "json")
        try move(path, to: keptCopy)
        return keptCopy
    }
}
