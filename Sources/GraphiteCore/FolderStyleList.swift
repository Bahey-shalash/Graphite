import Foundation

/// The top-level key of `.obsidian/graphite-folder-styles.json`.
private enum FieldName {
    static let folders = "folders"
}

/// Why `.obsidian/graphite-folder-styles.json` is refused rather than read; the file is then
/// left as it is, never overwritten.
public enum FolderStyleListError: Error, Equatable {
    case notAJSONObject
    case foldersNotAnObject
}

/// Graphite's optional `.obsidian/graphite-folder-styles.json`: each styled folder's color and
/// symbol or emoji, by vault path. Obsidian ignores the file; without it every folder looks plain.
/// Entries and keys this build does not understand are kept as they were.
public struct FolderStyleList: Equatable, Sendable {
    public static let configurationPath = ".obsidian/graphite-folder-styles.json"
    /// The name a file this build cannot read is kept under, beside `configurationPath`.
    public static let unreadableCopyStem = "graphite-folder-styles.unreadable"

    public private(set) var styles: [VaultPath: FolderStyle]
    /// Folder entries that are not a style this build can read, kept by their key.
    private var unreadableEntries: [String: JSONValue]
    /// Keys beside `folders`, kept as they were.
    private var otherFields: [String: JSONValue]

    public init(styles: [VaultPath: FolderStyle] = [:]) {
        self.styles = styles
        unreadableEntries = [:]
        otherFields = [:]
    }

    /// Reads the file's data; nothing means no styles. Throws for a file that is not this
    /// format, so it is never overwritten.
    public init(configurationData: Data?) throws {
        self.init()
        guard let configurationData, !configurationData.isEmpty else { return }
        // Not JSON is the same refusal as not an object.
        let decoded = try? JSONDecoder().decode(JSONValue.self, from: configurationData) // Not JSON is refused below.
        guard case .object(var object) = decoded else {
            throw FolderStyleListError.notAJSONObject
        }
        switch object.removeValue(forKey: FieldName.folders) {
        case .object(let folders):
            for (key, value) in folders {
                if case .object(let fields) = value, let path = try? VaultPath(key), let style = FolderStyle(fields: fields) { // Unreadable keys are kept.
                    styles[path] = style
                } else {
                    unreadableEntries[key] = value
                }
            }
        case nil, .null: break
        default: throw FolderStyleListError.foldersNotAnObject
        }
        otherFields = object
    }

    public func configurationData() throws -> Data {
        var folders = unreadableEntries
        for (path, style) in styles { folders[path.rawValue] = .object(style.fields) }
        var object = otherFields
        object[FieldName.folders] = .object(folders)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(object))
    }

    public func style(for folder: VaultPath) -> FolderStyle? { styles[folder] }

    /// Sets a folder's style; nil or a plain style makes it plain again. Keys another build
    /// wrote stay with the folder, so a plain folder keeps its entry only for them.
    public mutating func setStyle(_ style: FolderStyle?, for folder: VaultPath) {
        var style = style ?? FolderStyle()
        style.otherFields = styles[folder]?.otherFields ?? style.otherFields
        styles[folder] = style.isPlain && style.otherFields.isEmpty ? nil : style
    }

    /// Keeps the styles of a renamed or moved folder, and of the folders inside it.
    /// Returns whether any style moved.
    @discardableResult
    public mutating func followMove(from oldPath: VaultPath, to newPath: VaultPath) -> Bool {
        let movedFolders = styles.keys.filter { folder in folder.isInside(oldPath) }
        for folder in movedFolders {
            guard let style = styles.removeValue(forKey: folder) else { continue }
            let suffix = String(folder.rawValue.dropFirst(oldPath.rawValue.count))
            if let movedFolder = try? VaultPath(newPath.rawValue + suffix) { styles[movedFolder] = style } // A moved path is always valid.
        }
        return !movedFolders.isEmpty
    }

    /// Forgets the styles of a deleted folder and the folders inside it.
    @discardableResult
    public mutating func forget(_ deletedPath: VaultPath) -> Bool {
        let deletedFolders = styles.keys.filter { folder in folder.isInside(deletedPath) }
        for folder in deletedFolders { styles[folder] = nil }
        return !deletedFolders.isEmpty
    }
}
