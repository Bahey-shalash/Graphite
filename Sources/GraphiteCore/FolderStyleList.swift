import Foundation

/// The keys of `.obsidian/graphite-folder-styles.json`.
private enum FieldName {
    static let folders = "folders"
    static let color = "color"
    static let symbol = "symbol"
}

/// Why `.obsidian/graphite-folder-styles.json` is refused rather than read; the file is then
/// left as it is, never overwritten.
public enum FolderStyleListError: Error, Equatable {
    case notAJSONObject
    case foldersNotAnObject
}

/// A folder tile's color in the library.
public enum FolderColor: Equatable, Hashable, Sendable {
    case blue, green, yellow, orange, red, pink, purple, indigo, teal, gray
    /// A color written by a newer Graphite, kept as written.
    case unknown(String)

    public static let knownColors: [FolderColor] = [.blue, .green, .yellow, .orange, .red, .pink, .purple, .indigo, .teal, .gray]

    public init(rawValue: String) {
        self = Self.knownColors.first { color in color.rawValue == rawValue } ?? .unknown(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .blue: "blue"
        case .green: "green"
        case .yellow: "yellow"
        case .orange: "orange"
        case .red: "red"
        case .pink: "pink"
        case .purple: "purple"
        case .indigo: "indigo"
        case .teal: "teal"
        case .gray: "gray"
        case .unknown(let rawValue): rawValue
        }
    }
}

/// How one folder looks in the library: its color, and an SF Symbol drawn on it.
public struct FolderStyle: Equatable, Sendable {
    public var color: FolderColor
    /// An SF Symbol name; nil for a plain folder.
    public var symbolName: String?
    /// Keys this build does not know, kept as they were.
    fileprivate var otherFields: [String: JSONValue]

    public init(color: FolderColor, symbolName: String? = nil) {
        self.color = color
        self.symbolName = symbolName
        otherFields = [:]
    }

    fileprivate init?(fields: [String: JSONValue]) {
        var fields = fields
        guard case .string(let colorName) = fields.removeValue(forKey: FieldName.color) else { return nil }
        color = FolderColor(rawValue: colorName)
        if case .string(let symbolName) = fields.removeValue(forKey: FieldName.symbol) { self.symbolName = symbolName } else { symbolName = nil }
        otherFields = fields
    }

    fileprivate var fields: [String: JSONValue] {
        var fields = otherFields
        fields[FieldName.color] = .string(color.rawValue)
        if let symbolName { fields[FieldName.symbol] = .string(symbolName) }
        return fields
    }
}

/// Graphite's optional `.obsidian/graphite-folder-styles.json`: each styled folder's color and
/// symbol, by vault path. Obsidian ignores the file; without it every folder looks plain.
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

    /// Sets a folder's style; nil makes it plain again.
    public mutating func setStyle(_ style: FolderStyle?, for folder: VaultPath) {
        if var style {
            // Keys another build wrote stay with the folder when its color changes here.
            style.otherFields = styles[folder]?.otherFields ?? style.otherFields
            styles[folder] = style
        } else {
            styles[folder] = nil
        }
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
