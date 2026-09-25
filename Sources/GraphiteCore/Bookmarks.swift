import Foundation

/// A JSON value kept as written, so an Obsidian settings file keeps what Graphite does not
/// understand. Whole numbers stay whole, as `ctime` milliseconds must.
public enum JSONValue: Hashable, Sendable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// One item of Obsidian's Bookmarks: a file (with a heading or block as `subpath`), a
/// folder, a search, a group of bookmarks, or a kind Graphite only keeps (a graph, a web
/// page). All of its fields are kept, known or not.
public struct Bookmark: Hashable, Sendable, Identifiable {
    public private(set) var fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    public var type: String { fields["type"]?.stringValue ?? "" }
    public var path: String? { fields["path"]?.stringValue }
    /// `#Heading`, `#Parent#Child` or `#^block`, as Obsidian writes it.
    public var subpath: String? { fields["subpath"]?.stringValue.flatMap { subpath in subpath.isEmpty ? nil : subpath } }
    public var query: String? { fields["query"]?.stringValue }
    public var url: String? { fields["url"]?.stringValue }
    /// The name given to the bookmark, if any.
    public var title: String? {
        get { fields["title"]?.stringValue.flatMap { title in title.isEmpty ? nil : title } }
        set { fields["title"] = newValue.flatMap { title in title.isEmpty ? nil : JSONValue.string(title) } }
    }
    /// When it was bookmarked, in milliseconds since 1970.
    public var creationTime: Int64? {
        switch fields["ctime"] {
        case .integer(let value): value
        case .number(let value): Int64(exactly: value.rounded())
        default: nil
        }
    }

    public var children: [Bookmark] {
        get {
            guard case .array(let values) = fields["items"] else { return [] }
            return values.compactMap { value in if case .object(let object) = value { Bookmark(fields: object) } else { nil } }
        }
        set { fields["items"] = .array(newValue.map { child in JSONValue.object(child.fields) }) }
    }

    public var vaultPath: VaultPath? { path.flatMap { path in try? VaultPath(path) } }

    /// Tells bookmarks apart across reloads of the file: kind, time and target.
    public var id: String {
        [type, creationTime.map(String.init) ?? "", path ?? query ?? url ?? title ?? "", subpath ?? ""].joined(separator: "|")
    }

    /// What the Bookmarks view shows: the given name, else the note's name with its
    /// heading, the folder's name, or the search.
    public var displayTitle: String {
        if let title { return title }
        switch type {
        case "file":
            guard let vaultPath else { return path ?? "" }
            let name = DocumentKind(path: vaultPath) == .markdown ? vaultPath.stem : vaultPath.name
            guard let subpath else { return name }
            // The innermost heading of `#Parent#Child`, or the `^block`.
            return name + " › " + (subpath.split(separator: "#").last.map(String.init) ?? subpath)
        case "folder": return vaultPath?.name ?? path ?? ""
        case "search": return query ?? ""
        case "url": return url ?? ""
        case "graph": return "Graph view"
        default: return type.isEmpty ? "Bookmark" : type.capitalized
        }
    }

    public static func file(_ path: VaultPath, subpath: String? = nil, at date: Date = .now) -> Bookmark {
        var fields = base("file", at: date)
        fields["path"] = .string(path.rawValue)
        if let subpath, !subpath.isEmpty { fields["subpath"] = .string(subpath.hasPrefix("#") ? subpath : "#" + subpath) }
        return Bookmark(fields: fields)
    }

    public static func folder(_ path: VaultPath, at date: Date = .now) -> Bookmark {
        var fields = base("folder", at: date)
        fields["path"] = .string(path.rawValue)
        return Bookmark(fields: fields)
    }

    public static func search(_ query: String, at date: Date = .now) -> Bookmark {
        var fields = base("search", at: date)
        fields["query"] = .string(query)
        return Bookmark(fields: fields)
    }

    public static func group(_ title: String, at date: Date = .now) -> Bookmark {
        var fields = base("group", at: date)
        fields["title"] = .string(title)
        fields["items"] = .array([])
        return Bookmark(fields: fields)
    }

    private static func base(_ type: String, at date: Date) -> [String: JSONValue] {
        ["type": .string(type), "ctime": .integer(Int64((date.timeIntervalSince1970 * 1000).rounded()))]
    }

    /// Changes a file or folder path when it moves; true when something changed.
    mutating func followMove(from oldPath: VaultPath, to newPath: VaultPath) -> Bool {
        var changed = false
        if type == "file" || type == "folder", let vaultPath, vaultPath.isInside(oldPath),
           let movedPath = try? vaultPath.replacingPrefix(oldPath, with: newPath) {
            fields["path"] = .string(movedPath.rawValue)
            changed = true
        }
        if type == "group" {
            var movedChildren = children
            for index in movedChildren.indices where movedChildren[index].followMove(from: oldPath, to: newPath) { changed = true }
            if changed { children = movedChildren }
        }
        return changed
    }
}

/// Obsidian's `.obsidian/bookmarks.json`, read and written keeping everything else in it.
public struct BookmarkList: Equatable, Sendable {
    public static let configurationPath = ".obsidian/bookmarks.json"

    public var items: [Bookmark]
    /// Keys beside `items`, kept as they were.
    private var otherFields: [String: JSONValue]

    public init(items: [Bookmark] = []) {
        self.items = items
        otherFields = [:]
    }

    /// Reads the file's data; nothing means no bookmarks. Throws for a file that is not
    /// Obsidian's format, so it is never overwritten.
    public init(configurationData: Data?) throws {
        guard let configurationData, !configurationData.isEmpty else { items = []; otherFields = [:]; return }
        guard case .object(var object) = try? JSONDecoder().decode(JSONValue.self, from: configurationData) else {
            throw GraphiteError.invalidFile("“\(Self.configurationPath)” is not a JSON object, so Graphite leaves your bookmarks unchanged.")
        }
        let itemValues: [JSONValue]
        switch object.removeValue(forKey: "items") {
        case .array(let values): itemValues = values
        case nil, .null: itemValues = []
        default: throw GraphiteError.invalidFile("“\(Self.configurationPath)” has no list of bookmarks, so Graphite leaves it unchanged.")
        }
        items = itemValues.compactMap { value in if case .object(let fields) = value { Bookmark(fields: fields) } else { nil } }
        otherFields = object
    }

    public func configurationData() throws -> Data {
        var object = otherFields
        object["items"] = .array(items.map { item in JSONValue.object(item.fields) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(object))
    }

    /// Every bookmark, groups' contents included, in order.
    public var allBookmarks: [Bookmark] {
        func flatten(_ bookmarks: [Bookmark]) -> [Bookmark] { bookmarks.flatMap { bookmark in [bookmark] + flatten(bookmark.children) } }
        return flatten(items)
    }

    /// The bookmark of a file (and heading or block), wherever it is.
    public func fileBookmark(for path: VaultPath, subpath: String? = nil) -> Bookmark? {
        allBookmarks.first { bookmark in bookmark.type == "file" && bookmark.vaultPath == path && bookmark.subpath == subpath }
    }

    public func folderBookmark(for path: VaultPath) -> Bookmark? {
        allBookmarks.first { bookmark in bookmark.type == "folder" && bookmark.vaultPath == path }
    }

    public func searchBookmark(for query: String) -> Bookmark? {
        allBookmarks.first { bookmark in bookmark.type == "search" && bookmark.query == query }
    }

    /// Adds a bookmark at the end, as Obsidian does; to a group when one is given.
    public mutating func add(_ bookmark: Bookmark, toGroup groupID: String? = nil) {
        guard let groupID else { items.append(bookmark); return }
        _ = Self.update(&items, id: groupID) { group in group.children.append(bookmark) }
    }

    /// Removes a bookmark, a group with its contents; false when it is not there.
    @discardableResult
    public mutating func remove(id: String) -> Bool {
        Self.remove(from: &items, id: id)
    }

    /// Names a bookmark; an empty name goes back to the default one.
    @discardableResult
    public mutating func rename(id: String, to title: String) -> Bool {
        Self.update(&items, id: id) { bookmark in bookmark.title = title.trimmingCharacters(in: .whitespaces) }
    }

    /// Keeps bookmarks on files and folders that were renamed or moved; true when any changed.
    @discardableResult
    public mutating func followMove(from oldPath: VaultPath, to newPath: VaultPath) -> Bool {
        var changed = false
        for index in items.indices where items[index].followMove(from: oldPath, to: newPath) { changed = true }
        return changed
    }

    private static func update(_ bookmarks: inout [Bookmark], id: String, _ change: (inout Bookmark) -> Void) -> Bool {
        for index in bookmarks.indices {
            if bookmarks[index].id == id { change(&bookmarks[index]); return true }
            var children = bookmarks[index].children
            if !children.isEmpty, update(&children, id: id, change) {
                bookmarks[index].children = children
                return true
            }
        }
        return false
    }

    private static func remove(from bookmarks: inout [Bookmark], id: String) -> Bool {
        if let index = bookmarks.firstIndex(where: { bookmark in bookmark.id == id }) {
            bookmarks.remove(at: index)
            return true
        }
        for index in bookmarks.indices {
            var children = bookmarks[index].children
            if !children.isEmpty, remove(from: &children, id: id) {
                bookmarks[index].children = children
                return true
            }
        }
        return false
    }
}
