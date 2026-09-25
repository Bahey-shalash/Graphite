import Foundation

/// Where new attachments are stored. Mirrors Obsidian's "Default location for new
/// attachments", persisted as `attachmentFolderPath` in `.obsidian/app.json`.
public enum AttachmentLocation: Equatable, Hashable, Sendable {
    case vaultFolder
    case specifiedFolder(String)
    case sameFolderAsNote
    case subfolderUnderNote(String)

    public init(obsidianValue: String?) {
        let trimmedValue = (obsidianValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty || trimmedValue == "/" { self = .vaultFolder; return }
        if trimmedValue == "." || trimmedValue == "./" { self = .sameFolderAsNote; return }
        if trimmedValue.hasPrefix("./") {
            self = .subfolderUnderNote(Self.withoutSurroundingSlashes(String(trimmedValue.dropFirst(2))))
            return
        }
        self = .specifiedFolder(Self.withoutSurroundingSlashes(trimmedValue))
    }

    /// The exact string Obsidian writes for this choice.
    public var obsidianValue: String {
        switch self {
        case .vaultFolder: return "/"
        case .specifiedFolder(let folder):
            // Stored as typed, "./Images" would read back as a subfolder under the note and
            // "." as the note's own folder, so the folder is written as its vault path.
            guard let path = try? Self.specifiedFolderPath(folder) else { return folder }
            return path.rawValue.isEmpty ? "/" : path.rawValue
        case .sameFolderAsNote: return "./"
        case .subfolderUnderNote(let folder): return "./" + folder
        }
    }

    /// The vault folder a `.specifiedFolder` value names, read the way `init(obsidianValue:)`
    /// reads the stored text, so a folder means the same before and after a reload.
    static func specifiedFolderPath(_ folder: String) throws -> VaultPath {
        try VaultPath(withoutSurroundingSlashes(folder.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static func withoutSurroundingSlashes(_ folder: String) -> String {
        folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// Obsidian's "New link format", persisted as `newLinkFormat`.
public enum LinkFormat: String, CaseIterable, Sendable, Identifiable {
    case shortest, relative, absolute
    public var id: String { rawValue }
}

/// Obsidian's "Default location for new notes" (`newFileLocation` and `newFileFolderPath`).
public enum NewNoteLocation: Equatable, Hashable, Sendable {
    /// `root`, Obsidian's default.
    case vaultFolder
    /// `current`: beside the file that is open.
    case sameFolderAsCurrentFile
    /// `folder`, with its path.
    case specifiedFolder(String)

    init(locationValue: String?, folderPath: String?) {
        switch locationValue {
        case "current": self = .sameFolderAsCurrentFile
        case "folder": self = .specifiedFolder((folderPath ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))
        default: self = .vaultFolder
        }
    }

    var locationValue: String {
        switch self {
        case .vaultFolder: "root"
        case .sameFolderAsCurrentFile: "current"
        case .specifiedFolder: "folder"
        }
    }

    /// The folder for a new note while `currentFile` is open.
    public func directory(currentFile: VaultPath?) throws -> VaultPath {
        switch self {
        case .vaultFolder: return .root
        case .sameFolderAsCurrentFile: return currentFile?.parent ?? .root
        case .specifiedFolder(let folder): return folder.isEmpty ? .root : try VaultPath(folder)
        }
    }
}

/// Obsidian's file explorer sort order (`fileSortOrder`).
public enum FileSortOrder: String, CaseIterable, Identifiable, Sendable {
    case alphabetical, alphabeticalReverse
    /// Newest first.
    case byModifiedTime
    case byModifiedTimeReverse
    /// Newest first.
    case byCreatedTime
    case byCreatedTimeReverse
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alphabetical: "File name (A to Z)"
        case .alphabeticalReverse: "File name (Z to A)"
        case .byModifiedTime: "Modified time (new to old)"
        case .byModifiedTimeReverse: "Modified time (old to new)"
        case .byCreatedTime: "Created time (new to old)"
        case .byCreatedTimeReverse: "Created time (old to new)"
        }
    }

    /// Folders first, as Obsidian lists them, then files in this order.
    public func sorted(_ entries: [VaultEntry]) -> [VaultEntry] {
        // Each name is taken from its path once, not twice per comparison.
        let namedEntries = entries.map { entry in (entry: entry, name: entry.path.name) }
        return namedEntries.sorted { left, right in
            let leftEntry = left.entry, rightEntry = right.entry
            if leftEntry.isDirectory != rightEntry.isDirectory { return leftEntry.isDirectory }
            let nameOrder = left.name.localizedStandardCompare(right.name)
            // Folders keep name order under date sorts, as in Obsidian.
            if leftEntry.isDirectory { return self == .alphabeticalReverse ? nameOrder == .orderedDescending : nameOrder == .orderedAscending }
            switch self {
            case .alphabetical: return nameOrder == .orderedAscending
            case .alphabeticalReverse: return nameOrder == .orderedDescending
            case .byModifiedTime: return leftEntry.modified != rightEntry.modified ? leftEntry.modified > rightEntry.modified : nameOrder == .orderedAscending
            case .byModifiedTimeReverse: return leftEntry.modified != rightEntry.modified ? leftEntry.modified < rightEntry.modified : nameOrder == .orderedAscending
            case .byCreatedTime: return leftEntry.created != rightEntry.created ? leftEntry.created > rightEntry.created : nameOrder == .orderedAscending
            case .byCreatedTimeReverse: return leftEntry.created != rightEntry.created ? leftEntry.created < rightEntry.created : nameOrder == .orderedAscending
            }
        }.map { namedEntry in namedEntry.entry }
    }
}

/// The subset of `.obsidian/app.json` that Graphite reads and writes. Every other
/// key in that file belongs to Obsidian and is preserved untouched on save.
public struct ObsidianSettings: Equatable, Sendable {
    public static let attachmentFolderPathKey = "attachmentFolderPath"
    public static let newLinkFormatKey = "newLinkFormat"
    public static let useMarkdownLinksKey = "useMarkdownLinks"
    public static let strictLineBreaksKey = "strictLineBreaks"
    public static let trashOptionKey = "trashOption"
    public static let alwaysUpdateLinksKey = "alwaysUpdateLinks"
    public static let promptDeleteKey = "promptDelete"
    public static let fileSortOrderKey = "fileSortOrder"
    public static let newFileLocationKey = "newFileLocation"
    public static let newFileFolderPathKey = "newFileFolderPath"
    public static let autoPairBracketsKey = "autoPairBrackets"
    public static let autoPairMarkdownKey = "autoPairMarkdown"
    public static let smartIndentListKey = "smartIndentList"
    public static let useTabKey = "useTab"
    public static let tabSizeKey = "tabSize"
    public static let autoConvertHtmlKey = "autoConvertHtml"

    public var attachmentLocation: AttachmentLocation
    public var linkFormat: LinkFormat
    public var usesWikilinks: Bool
    /// When false (Obsidian's default), a single newline shows as a line break when reading.
    public var usesStrictLineBreaks: Bool
    /// "Deleted files": where deleted files go.
    public var deletionMethod: DeletionMethod = .systemTrash
    /// "Automatically update internal links" when a file is renamed or moved. When off,
    /// Graphite asks, as Obsidian does.
    public var updatesLinksAutomatically = false
    /// "Confirm file deletion".
    public var confirmsDeletion = true
    public var fileSortOrder: FileSortOrder = .alphabetical
    public var newNoteLocation: NewNoteLocation = .vaultFolder
    /// "Auto pair brackets".
    public var pairsBrackets = true
    /// "Auto pair Markdown syntax": `*`, `=` and the like wrap a selection.
    public var pairsMarkdown = true
    /// "Smart indent lists": Return continues a list and Tab indents it.
    public var continuesLists = true
    /// "Indent using tabs".
    public var indentsWithTabs = true
    /// "Tab indent size", in spaces.
    public var tabSize = 4
    /// "Auto convert HTML": pasted web pages become Markdown.
    public var convertsPastedHTML = true

    /// What one level of indentation inserts.
    public var indentUnit: String { indentsWithTabs ? "\t" : String(repeating: " ", count: min(max(tabSize, 1), 8)) }

    /// Obsidian's defaults when `app.json` or a key is missing.
    public init(attachmentLocation: AttachmentLocation = .vaultFolder, linkFormat: LinkFormat = .shortest, usesWikilinks: Bool = true, usesStrictLineBreaks: Bool = false) {
        self.attachmentLocation = attachmentLocation
        self.linkFormat = linkFormat
        self.usesWikilinks = usesWikilinks
        self.usesStrictLineBreaks = usesStrictLineBreaks
    }

    /// Reads `app.json`. An empty file means Obsidian's defaults, as it does in Obsidian.
    public init(applicationConfigurationData: Data) throws {
        self.init(configuration: try ApplicationConfigurationObject(data: applicationConfigurationData))
    }

    private init(configuration: ApplicationConfigurationObject) {
        self.init(
            attachmentLocation: AttachmentLocation(obsidianValue: configuration.value(named: Self.attachmentFolderPathKey) as? String),
            linkFormat: (configuration.value(named: Self.newLinkFormatKey) as? String).flatMap(LinkFormat.init(rawValue:)) ?? .shortest,
            usesWikilinks: (configuration.value(named: Self.useMarkdownLinksKey) as? Bool).map { usesMarkdownLinks in !usesMarkdownLinks } ?? true,
            usesStrictLineBreaks: configuration.value(named: Self.strictLineBreaksKey) as? Bool ?? false
        )
        deletionMethod = (configuration.value(named: Self.trashOptionKey) as? String).flatMap(DeletionMethod.init(rawValue:)) ?? .systemTrash
        updatesLinksAutomatically = configuration.value(named: Self.alwaysUpdateLinksKey) as? Bool ?? false
        confirmsDeletion = configuration.value(named: Self.promptDeleteKey) as? Bool ?? true
        fileSortOrder = (configuration.value(named: Self.fileSortOrderKey) as? String).flatMap(FileSortOrder.init(rawValue:)) ?? .alphabetical
        newNoteLocation = NewNoteLocation(locationValue: configuration.value(named: Self.newFileLocationKey) as? String,
                                          folderPath: configuration.value(named: Self.newFileFolderPathKey) as? String)
        pairsBrackets = configuration.value(named: Self.autoPairBracketsKey) as? Bool ?? true
        pairsMarkdown = configuration.value(named: Self.autoPairMarkdownKey) as? Bool ?? true
        continuesLists = configuration.value(named: Self.smartIndentListKey) as? Bool ?? true
        indentsWithTabs = configuration.value(named: Self.useTabKey) as? Bool ?? true
        tabSize = (configuration.value(named: Self.tabSizeKey) as? Int).map { size in min(max(size, 1), 8) } ?? 4
        convertsPastedHTML = configuration.value(named: Self.autoConvertHtmlKey) as? Bool ?? true
    }

    /// Returns `existingData` with only the Graphite keys whose value differs from
    /// `previousSettings` replaced, laid out as Obsidian writes the file.
    ///
    /// `previousSettings` are the settings the change started from. Keys the user did not
    /// change keep what the file holds now, even if Obsidian changed them since, and keep
    /// values Graphite reads differently (a `tabSize` of 12, a future `newLinkFormat`).
    /// Without them, the settings `existingData` holds are the starting point. Unknown keys
    /// and their values survive exactly as written.
    public func mergedApplicationConfigurationData(existingData: Data?, changedFrom previousSettings: ObsidianSettings? = nil) throws -> Data {
        var configuration: ApplicationConfigurationObject
        do { configuration = try ApplicationConfigurationObject(data: existingData) }
        catch { throw GraphiteError.invalidFile("The Obsidian settings file is not a JSON object, so Graphite will not change it.") }
        let previousValueTexts = Dictionary((previousSettings ?? ObsidianSettings(configuration: configuration)).ownedValueTexts) { firstText, _ in firstText }
        let changedValueTexts = ownedValueTexts.filter { key, valueText in previousValueTexts[key] != valueText }
        if changedValueTexts.isEmpty, let existingData { return existingData }
        for (key, valueText) in changedValueTexts { configuration.setValueText(valueText, forName: key) }
        return configuration.formattedData
    }

    /// Every key Graphite owns with the JSON text Obsidian stores for its value, in the
    /// order Graphite adds missing keys. `newFileFolderPath` is present only for a folder.
    private var ownedValueTexts: [(key: String, valueText: String)] {
        var valueTexts: [(key: String, valueText: String)] = [
            (Self.attachmentFolderPathKey, ApplicationConfigurationObject.jsonText(for: attachmentLocation.obsidianValue)),
            (Self.newLinkFormatKey, ApplicationConfigurationObject.jsonText(for: linkFormat.rawValue)),
            (Self.useMarkdownLinksKey, String(!usesWikilinks)),
            (Self.strictLineBreaksKey, String(usesStrictLineBreaks)),
            (Self.trashOptionKey, ApplicationConfigurationObject.jsonText(for: deletionMethod.rawValue)),
            (Self.alwaysUpdateLinksKey, String(updatesLinksAutomatically)),
            (Self.promptDeleteKey, String(confirmsDeletion)),
            (Self.fileSortOrderKey, ApplicationConfigurationObject.jsonText(for: fileSortOrder.rawValue)),
            (Self.newFileLocationKey, ApplicationConfigurationObject.jsonText(for: newNoteLocation.locationValue)),
        ]
        if case .specifiedFolder(let folder) = newNoteLocation {
            valueTexts.append((Self.newFileFolderPathKey, ApplicationConfigurationObject.jsonText(for: folder)))
        }
        valueTexts += [
            (Self.autoPairBracketsKey, String(pairsBrackets)),
            (Self.autoPairMarkdownKey, String(pairsMarkdown)),
            (Self.smartIndentListKey, String(continuesLists)),
            (Self.useTabKey, String(indentsWithTabs)),
            (Self.tabSizeKey, String(tabSize)),
            (Self.autoConvertHtmlKey, String(convertsPastedHTML)),
        ]
        return valueTexts
    }
}

/// The top-level members of `.obsidian/app.json` in file order, each value kept as the text
/// the file holds. A rewrite changes only the members Graphite sets and prints the file as
/// Obsidian does (`JSON.stringify(settings, null, 2)`), so other values keep their exact
/// digits and layout, and a synced or versioned vault sees only the changed lines.
struct ApplicationConfigurationObject {
    private struct Member {
        /// The name as written in the file, with its quotes and escapes.
        var nameText: String
        var valueText: String
    }

    private var members: [Member] = []
    /// Each decoded name's position in `members`.
    private var memberPositions: [String: Int] = [:]

    private static let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\"), colon = UInt8(ascii: ":"), comma = UInt8(ascii: ",")
    private static let openingBrace = UInt8(ascii: "{"), closingBrace = UInt8(ascii: "}"), openingBracket = UInt8(ascii: "["), closingBracket = UInt8(ascii: "]")
    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Missing, empty or blank data is an empty object, which Obsidian also reads as its
    /// defaults (a sync can leave a zero-byte file). Anything else must be a JSON object.
    ///
    /// A name that appears twice keeps its first position and its last value, as
    /// JavaScript's `JSON.parse` in Obsidian reads it; Foundation would keep the first value.
    init(data: Data?) throws {
        guard let data else { return }
        var bytes = [UInt8](data)
        if bytes.starts(with: Self.byteOrderMark) { bytes.removeFirst(Self.byteOrderMark.count) }
        guard bytes.contains(where: { byte in !Self.isWhitespace(byte) }) else { return }
        guard let object = try JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any] else {
            throw GraphiteError.invalidFile("The Obsidian settings file is not a JSON object.")
        }
        // UTF-8 JSON never holds a zero byte; UTF-16 and UTF-32 JSON, which Foundation also
        // reads, always does. Those rare files keep Foundation's reading, in name order.
        if !bytes.contains(0), let scannedMembers = Self.scannedMembers(of: bytes) {
            for member in scannedMembers { setValueText(member.valueText, forName: member.name, nameText: member.nameText) }
        } else {
            for name in object.keys.sorted() {
                guard let value = object[name] else { continue }
                let valueData = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
                setValueText(String(decoding: valueData, as: UTF8.self), forName: name)
            }
        }
    }

    /// The member's value as Foundation reads it, or nil when there is no such member.
    func value(named name: String) -> Any? {
        guard let position = memberPositions[name] else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(members[position].valueText.utf8), options: .fragmentsAllowed)
    }

    /// Replaces the member's value in place, or adds the member at the end.
    mutating func setValueText(_ valueText: String, forName name: String, nameText: String? = nil) {
        if let position = memberPositions[name] {
            members[position].valueText = valueText
        } else {
            memberPositions[name] = members.count
            members.append(Member(nameText: nameText ?? Self.jsonText(for: name), valueText: valueText))
        }
    }

    /// The object with two-space indentation and `"name": value` members, as Obsidian writes it.
    var formattedData: Data {
        guard !members.isEmpty else { return Data("{}".utf8) }
        let memberLines = members.map { member in "  " + member.nameText + ": " + member.valueText }
        return Data(("{\n" + memberLines.joined(separator: ",\n") + "\n}").utf8)
    }

    /// `text` as a JSON string, escaped as JavaScript's `JSON.stringify` escapes it.
    static func jsonText(for text: String) -> String {
        var escapedText = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": escapedText += "\\\""
            case "\\": escapedText += "\\\\"
            case "\n": escapedText += "\\n"
            case "\r": escapedText += "\\r"
            case "\t": escapedText += "\\t"
            case "\u{8}": escapedText += "\\b"
            case "\u{C}": escapedText += "\\f"
            case "\u{0}"..."\u{1F}": escapedText += String(format: "\\u%04x", scalar.value)
            default: escapedText.unicodeScalars.append(scalar)
            }
        }
        return escapedText + "\""
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    /// The name and text of each top-level member of `bytes`, which JSONSerialization has
    /// already accepted as a JSON object; nil if the layout is not as expected after all.
    /// Nested values are skipped by counting brackets, not by recursion, so depth costs no stack.
    private static func scannedMembers(of bytes: [UInt8]) -> [(name: String, nameText: String, valueText: String)]? {
        var position = 0
        func text(from start: Int) -> String { String(decoding: bytes[start..<position], as: UTF8.self) }
        func skipWhitespace() { while position < bytes.count, isWhitespace(bytes[position]) { position += 1 } }
        func skipString() -> Bool {
            guard position < bytes.count, bytes[position] == quote else { return false }
            position += 1
            while position < bytes.count {
                switch bytes[position] {
                case backslash: position += 2
                case quote: position += 1; return true
                default: position += 1
                }
            }
            return false
        }
        func skipValue() -> Bool {
            guard position < bytes.count else { return false }
            switch bytes[position] {
            case quote:
                return skipString()
            case openingBrace, openingBracket:
                var depth = 0
                while position < bytes.count {
                    switch bytes[position] {
                    case quote:
                        guard skipString() else { return false }
                        continue
                    case openingBrace, openingBracket: depth += 1
                    case closingBrace, closingBracket: depth -= 1
                    default: break
                    }
                    position += 1
                    if depth == 0 { return true }
                }
                return false
            default:
                let start = position
                while position < bytes.count, !isWhitespace(bytes[position]), bytes[position] != comma, bytes[position] != closingBrace, bytes[position] != closingBracket {
                    position += 1
                }
                return position > start
            }
        }

        skipWhitespace()
        guard position < bytes.count, bytes[position] == openingBrace else { return nil }
        position += 1
        skipWhitespace()
        var members: [(name: String, nameText: String, valueText: String)] = []
        if position < bytes.count, bytes[position] == closingBrace { return members }
        while true {
            skipWhitespace()
            let nameStart = position
            guard skipString() else { return nil }
            let nameText = text(from: nameStart)
            guard let name = try? JSONSerialization.jsonObject(with: Data(nameText.utf8), options: .fragmentsAllowed) as? String else { return nil }
            skipWhitespace()
            guard position < bytes.count, bytes[position] == colon else { return nil }
            position += 1
            skipWhitespace()
            let valueStart = position
            guard skipValue() else { return nil }
            members.append((name, nameText, text(from: valueStart)))
            skipWhitespace()
            guard position < bytes.count else { return nil }
            if bytes[position] == comma { position += 1; continue }
            return bytes[position] == closingBrace ? members : nil
        }
    }
}
