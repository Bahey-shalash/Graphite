import Foundation
import Yams

/// How the Tags and Properties views order their lists, as in Obsidian.
public enum VaultListSortOrder: String, CaseIterable, Identifiable, Sendable {
    case nameAscending, nameDescending, frequencyDescending, frequencyAscending

    public var id: String { rawValue }

    /// `items` in this order; equal counts fall back to the name, so the list never shuffles.
    public func sorted<Item>(_ items: [Item], name: (Item) -> String, count: (Item) -> Int) -> [Item] {
        items.sorted { first, second in
            let nameOrder = name(first).localizedStandardCompare(name(second))
            switch self {
            case .nameAscending: return nameOrder == .orderedAscending
            case .nameDescending: return nameOrder == .orderedDescending
            case .frequencyDescending: return count(first) != count(second) ? count(first) > count(second) : nameOrder == .orderedAscending
            case .frequencyAscending: return count(first) != count(second) ? count(first) < count(second) : nameOrder == .orderedAscending
            }
        }
    }
}

/// A tag in the Tags view, with the tags nested under it.
public struct TagTreeNode: Identifiable, Equatable, Sendable {
    /// The whole tag, such as `course/math`.
    public let tag: String
    /// The part after the last slash, such as `math`.
    public let name: String
    /// Notes with this tag or a tag nested under it.
    public let fileCount: Int
    public let children: [TagTreeNode]
    public var id: String { tag.lowercased() }
}

public enum TagTree {
    /// Nests `course/math` under `course`, as Obsidian's Tags view does with nested tags
    /// shown. `counts` should hold every level, each counting the notes with that tag or
    /// one below it; a level missing from it is added with the largest count below it.
    public static func nodes(from counts: [(tag: String, fileCount: Int)], sortedBy order: VaultListSortOrder) -> [TagTreeNode] {
        var countByKey: [String: (tag: String, fileCount: Int)] = [:]
        for entry in counts where !entry.tag.isEmpty {
            let key = entry.tag.lowercased()
            countByKey[key] = (entry.tag, max(countByKey[key]?.fileCount ?? 0, entry.fileCount))
        }
        for entry in Array(countByKey.values) {
            var ancestor = parent(of: entry.tag)
            while let ancestorTag = ancestor {
                let key = ancestorTag.lowercased()
                countByKey[key] = (countByKey[key]?.tag ?? ancestorTag, max(countByKey[key]?.fileCount ?? 0, entry.fileCount))
                ancestor = parent(of: ancestorTag)
            }
        }
        var childrenByParentKey: [String: [(tag: String, fileCount: Int)]] = [:]
        for entry in countByKey.values {
            childrenByParentKey[parent(of: entry.tag)?.lowercased() ?? "", default: []].append(entry)
        }
        func nodes(under parentKey: String) -> [TagTreeNode] {
            let children = (childrenByParentKey[parentKey] ?? []).map { entry in
                TagTreeNode(tag: entry.tag, name: name(of: entry.tag), fileCount: entry.fileCount, children: nodes(under: entry.tag.lowercased()))
            }
            return order.sorted(children, name: \.name, count: \.fileCount)
        }
        return nodes(under: "")
    }

    /// `course` for `course/math`; nil for a tag at the top.
    static func parent(of tag: String) -> String? {
        guard let slash = tag.range(of: "/", options: .backwards), slash.lowerBound > tag.startIndex else { return nil }
        return String(tag[..<slash.lowerBound])
    }

    static func name(of tag: String) -> String {
        guard let slash = tag.range(of: "/", options: .backwards) else { return tag }
        let name = String(tag[slash.upperBound...])
        return name.isEmpty ? tag : name
    }
}

/// Renames a property in one note, as Obsidian's Properties view does across the vault.
public enum PropertyRenaming {
    /// The edit that renames `key` (matched ignoring case, as Obsidian matches property
    /// names) to `newKey` where the name is written, changing nothing else, or nil when the
    /// note has no such property. Throws when the note already has a property named
    /// `newKey`, or when its properties cannot be read or would read differently afterwards.
    /// - Parameter selection: The cursor in the note, kept on the same text.
    public static func edit(renaming key: String, to newKey: String, in noteText: String, selection: NSRange = NSRange(location: 0, length: 0)) throws -> MarkdownTextEdit? {
        let newName = newKey.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else { throw GraphiteError.invalidFile("A property needs a name.") }
        let source = noteText as NSString
        let frontmatterLength = FrontmatterLocator.length(in: source)
        guard frontmatterLength > 0, let yaml = BasePropertyEditing.frontmatterYAML(in: noteText) else { return nil }
        guard let properties = NoteProperties.parse(yaml) else {
            throw GraphiteError.invalidFile("This note's properties are not valid YAML, so Graphite leaves them unchanged.")
        }
        guard let property = properties.first(where: { property in property.key == key })
                ?? properties.first(where: { property in property.key.caseInsensitiveCompare(key) == .orderedSame }) else { return nil }
        guard property.key != newName else { return nil }
        if properties.contains(where: { other in other.key != property.key && other.key.caseInsensitiveCompare(newName) == .orderedSame }) {
            throw GraphiteError.unavailable("This note already has a property named “\(newName)”.")
        }
        guard let keyRange = rangeOfKey(property.key, in: source, frontmatterLength: frontmatterLength) else {
            throw GraphiteError.invalidFile("Graphite could not find where “\(property.key)” is written in this note.")
        }
        let replacement = NoteProperties.quotedIfNeeded(newName)
        let renamedText = source.replacingCharacters(in: keyRange, with: replacement)
        // Only the name may change: every value, and the order, must read the same.
        let renamedProperties = BasePropertyEditing.frontmatterYAML(in: renamedText).flatMap { renamedYAML in NoteProperties.parse(renamedYAML) }
        let expectedProperties = properties.map { original in original.key == property.key ? NoteProperty(key: newName, value: original.value) : original }
        guard renamedProperties == expectedProperties else {
            throw GraphiteError.invalidFile("Renaming “\(property.key)” here would change other properties, so this note is left unchanged.")
        }
        let lengthChange = (replacement as NSString).length - keyRange.length
        var selectionAfter = selection
        if selection.location >= NSMaxRange(keyRange) { selectionAfter.location += lengthChange }
        else if NSMaxRange(selection) > keyRange.location { selectionAfter = NSRange(location: keyRange.location + (replacement as NSString).length, length: 0) }
        return MarkdownTextEdit(range: keyRange, replacement: replacement, selectionAfter: selectionAfter)
    }

    /// A top-level mapping key written plainly or in quotes, up to the colon that ends it.
    private static let keyLinePattern = try? NSRegularExpression(pattern: "^(\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^']|'')*'|[^\\s#\"'\\-?:][^\\r\\n]*?|-[^\\s][^\\r\\n]*?)[ \\t]*:(?=[ \\t]|$)")

    private static func rangeOfKey(_ key: String, in source: NSString, frontmatterLength: Int) -> NSRange? {
        guard let keyLinePattern else { return nil }
        // The first line is the opening `---`.
        var location = NSMaxRange(source.lineRange(for: NSRange(location: 0, length: 0)))
        while location < frontmatterLength {
            var lineEnd = 0, contentsEnd = 0
            source.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = source.substring(with: NSRange(location: location, length: contentsEnd - location))
            if let match = keyLinePattern.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let keyText = (line as NSString).substring(with: match.range(at: 1))
                if decodedKey(keyText) == key { return NSRange(location: location + match.range(at: 1).location, length: match.range(at: 1).length) }
            }
            location = lineEnd
        }
        return nil
    }

    /// The key a YAML parser reads from `keyText`, quotes and escapes resolved.
    private static func decodedKey(_ keyText: String) -> String? {
        (try? Yams.compose(yaml: keyText + ": 0"))?.mapping?.first?.key.string
    }
}
