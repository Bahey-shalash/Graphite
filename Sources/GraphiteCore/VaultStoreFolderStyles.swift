import Foundation
import CryptoKit

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
        // A picture left behind is only a small file in Graphite's own folder; the styles are saved.
        try? removeUnusedFolderPictures(keeping: updated) // A failed clean-up is tried again on the next change.
        return updated
    }

    /// Saves a folder's picture as a PNG in `FolderPicture.directory`, named after its content
    /// so the same picture is kept once, and returns where it is.
    public func saveFolderPicture(_ pngData: Data) throws -> VaultPath {
        let directory = try VaultPath(FolderPicture.directory)
        try createDirectory(directory)
        let name = SHA256.hash(data: pngData).prefix(Self.pictureNameBytes).map { byte in String(format: "%02x", byte) }.joined()
        let path = try directory.appending(name + ".png")
        if try !fileExists(path) { _ = try save(pngData, at: path, expecting: .absent) }
        return path
    }

    /// The bytes of a picture's content hash its file name keeps: 16 hexadecimal digits.
    private static let pictureNameBytes = 8

    /// Deletes the pictures Graphite saved that no folder uses any more: only files in its
    /// own folder named as it names them, so a file put there by hand stays.
    func removeUnusedFolderPictures(keeping styles: FolderStyleList) throws {
        let directory = try VaultPath(FolderPicture.directory)
        guard try fileExists(directory) else { return }
        let usedPictures = Set(styles.styles.values.compactMap(\.picture?.path))
        for entry in try children(of: directory) where !entry.isDirectory && !usedPictures.contains(entry.path) && Self.isSavedPictureName(entry.path.name) {
            _ = try delete(entry.path, method: .permanent)
        }
    }

    static func isSavedPictureName(_ name: String) -> Bool {
        let stem = (name as NSString).deletingPathExtension
        return (name as NSString).pathExtension == "png" && stem.count == pictureNameBytes * 2 && stem.allSatisfy(\.isHexDigit)
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
