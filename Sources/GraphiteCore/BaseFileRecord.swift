import Foundation
import Yams

/// Frontmatter as parsed YAML structure, before any type interpretation. Keeping the
/// scalar text and whether it was quoted lets `.obsidian/types.json` decide the type
/// at query time, exactly as it would for a freshly read note (`007` stays text when
/// declared as text).
public indirect enum BaseFrontmatterNode: Codable, Hashable, Sendable {
    case scalar(text: String, isPlain: Bool)
    case sequence([BaseFrontmatterNode])
    case mapping([BaseFrontmatterEntry])
}

public struct BaseFrontmatterEntry: Codable, Hashable, Sendable {
    public var key: String
    public var node: BaseFrontmatterNode
    public init(key: String, node: BaseFrontmatterNode) {
        self.key = key
        self.node = node
    }
}

public enum BaseFrontmatter {
    /// Nested YAML deeper than this is kept as text (the rest of the value in YAML flow
    /// style); frontmatter is untrusted input.
    static let maximumNestingDepth = 16

    /// Properties in written order, or nil when the YAML is not a key/value mapping or
    /// its anchors and aliases exceed `YAMLAliasExpansion`'s limits.
    public static func entries(fromYAML yaml: String) -> [BaseFrontmatterEntry]? {
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard !YAMLNesting.exceedsSafeDepth(yaml), !YAMLAliasExpansion.exceedsAnchorCount(yaml) else { return nil }
        let composedNode: Node?
        do { composedNode = try Yams.compose(yaml: yaml) } catch { return nil }
        // Yams composes no document at all from YAML that holds only comments, which is
        // valid, empty frontmatter.
        guard let rootNode = composedNode else { return [] }
        guard let mapping = rootNode.mapping, !YAMLAliasExpansion.exceedsLimits(rootNode, sourceByteCount: yaml.utf8.count) else { return nil }
        return mapping.compactMap { keyNode, valueNode in
            guard let key = keyNode.string else { return nil }
            return BaseFrontmatterEntry(key: key, node: node(from: valueNode, depth: 0))
        }
    }

    private static func node(from yamlNode: Node, depth: Int) -> BaseFrontmatterNode {
        guard depth < maximumNestingDepth else { return .scalar(text: flowText(of: yamlNode), isPlain: false) }
        switch yamlNode {
        case .scalar(let scalar):
            return .scalar(text: scalar.string, isPlain: isReadByValue(scalar))
        case .sequence(let sequence):
            return .sequence(sequence.map { itemNode in node(from: itemNode, depth: depth + 1) })
        case .mapping(let mapping):
            return .mapping(mapping.compactMap { keyNode, valueNode in
                keyNode.string.map { key in BaseFrontmatterEntry(key: key, node: node(from: valueNode, depth: depth + 1)) }
            })
        case .alias:
            // Composing resolves every alias to its anchored node; an unresolved one has no content.
            return .scalar(text: "", isPlain: true)
        }
    }

    /// Whether the scalar's type comes from its text, as for an unquoted value. An
    /// explicit tag decides instead, as it does in Obsidian's YAML reader: `!!str 007`
    /// is text, and `!!int "7"` is a number. Quoted scalars carry the `str` tag.
    private static func isReadByValue(_ scalar: Node.Scalar) -> Bool {
        switch scalar.tag.rawValue {
        case Tag.Name.str.rawValue, Tag.Name.nonSpecific.rawValue:
            return false
        case Tag.Name.int.rawValue, Tag.Name.float.rawValue, Tag.Name.bool.rawValue, Tag.Name.null.rawValue, Tag.Name.timestamp.rawValue:
            return true
        default:
            return scalar.style == .plain
        }
    }

    /// A value nested past `maximumNestingDepth`, written as one line of YAML flow
    /// syntax. Its depth is bounded by `YAMLAliasExpansion.maximumDepth`, which the
    /// YAML writer handles on a small stack.
    private static func flowText(of yamlNode: Node) -> String {
        if case .scalar(let scalar) = yamlNode { return scalar.string }
        let text = (try? Yams.serialize(node: flowStyled(yamlNode), width: -1, allowUnicode: true)) ?? ""
        return text.trimmingCharacters(in: .newlines)
    }

    private static func flowStyled(_ yamlNode: Node) -> Node {
        switch yamlNode {
        case .sequence(let sequence):
            return .sequence(Node.Sequence(sequence.map(flowStyled), sequence.tag, .flow))
        case .mapping(let mapping):
            return .mapping(Node.Mapping(mapping.map { keyNode, valueNode in (flowStyled(keyNode), flowStyled(valueNode)) }, mapping.tag, .flow))
        case .scalar, .alias:
            return yamlNode
        }
    }

    /// Interprets a node the way Obsidian's Properties do: the declared type from
    /// `.obsidian/types.json` wins; otherwise YAML's core schema decides, and text
    /// that is exactly one link becomes a link.
    public static func value(of node: BaseFrontmatterNode, declaredType: PropertyType?, source: VaultPath?, calendar: Calendar) -> BaseValue {
        switch node {
        case .sequence(let items):
            return .list(items.map { itemNode in value(of: itemNode, declaredType: nil, source: source, calendar: calendar) })
        case .mapping(let entries):
            return .object(BaseObject(entries: entries.map { entry in
                BaseObjectEntry(key: entry.key, value: value(of: entry.node, declaredType: nil, source: source, calendar: calendar))
            }))
        case .scalar(let text, let isPlain):
            return scalarValue(text: text, isPlain: isPlain, declaredType: declaredType, source: source, calendar: calendar)
        }
    }

    private static func scalarValue(text: String, isPlain: Bool, declaredType: PropertyType?, source: VaultPath?, calendar: Calendar) -> BaseValue {
        if isPlain && ["", "~", "null", "Null", "NULL"].contains(text) {
            switch declaredType {
            case .multitext, .tags, .aliases: return .list([])
            default: return .null
            }
        }
        func textValue(_ text: String) -> BaseValue {
            BaseLink.parse(text, source: source).map(BaseValue.link) ?? .string(text)
        }
        switch declaredType {
        case .text: return textValue(text)
        case .multitext, .tags, .aliases: return .list([textValue(text)])
        case .number: return Double(text.trimmingCharacters(in: .whitespaces)).map(BaseValue.number) ?? .string(text)
        case .checkbox: return .boolean(text.lowercased() == "true")
        case .date, .datetime: return BaseDateParsing.date(from: text, calendar: calendar).map(BaseValue.date) ?? .string(text)
        case nil: break
        }
        if !isPlain {
            if let date = looksLikeDate(text) ? BaseDateParsing.date(from: text, calendar: calendar) : nil { return .date(date) }
            return textValue(text)
        }
        if ["true", "True", "TRUE"].contains(text) { return .boolean(true) }
        if ["false", "False", "FALSE"].contains(text) { return .boolean(false) }
        if matches(numberPattern, text), let number = Double(text) {
            return .number(number)
        }
        if looksLikeDate(text), let date = BaseDateParsing.date(from: text, calendar: calendar) { return .date(date) }
        return textValue(text)
    }

    // Compiled once: these run for every property read while a base is evaluated.
    // `\z` rather than `$`, which would also match before a final line break.
    private static let numberPattern = try? NSRegularExpression(pattern: "^[-+]?(\\.[0-9]+|[0-9]+(\\.[0-9]*)?)([eE][-+]?[0-9]+)?\\z")
    /// Obsidian's date detection: a date, optionally with a time and a `Z` or `±HH[:mm]` offset.
    private static let datePattern = try? NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}([T ]\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?(Z|[+-]\\d{2}(:?\\d{2})?)?)?\\z")

    private static func looksLikeDate(_ text: String) -> Bool {
        matches(datePattern, text)
    }

    private static func matches(_ pattern: NSRegularExpression?, _ text: String) -> Bool {
        pattern?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Every internal `[[wikilink]]` or `[label](target)` written in property values.
    /// Obsidian counts these in `file.links`.
    public static func links(in entries: [BaseFrontmatterEntry]) -> [BaseRecordLink] {
        var links: [BaseRecordLink] = []
        func collect(_ node: BaseFrontmatterNode) {
            switch node {
            case .scalar(let text, _):
                if let link = BaseLink.parse(text), !link.isExternal {
                    links.append(BaseRecordLink(target: link.target, isEmbed: false, isWiki: text.trimmingCharacters(in: .whitespaces).hasSuffix("]]")))
                }
            case .sequence(let items): items.forEach(collect)
            case .mapping(let entries): entries.forEach { entry in collect(entry.node) }
            }
        }
        entries.forEach { entry in collect(entry.node) }
        return links
    }
}

/// A link written in a note body, as the index stores it.
public struct BaseRecordLink: Hashable, Sendable {
    /// Wikilinks keep their written target; Markdown links hold a vault path.
    public let target: String
    public let isEmbed: Bool
    public let isWiki: Bool
    public init(target: String, isEmbed: Bool, isWiki: Bool) {
        self.target = target
        self.isEmbed = isEmbed
        self.isWiki = isWiki
    }
}

/// Everything a base needs to know about one vault file. Built from the index, never
/// from reading every note body at query time.
public struct BaseFileRecord: Hashable, Sendable, Identifiable {
    public let path: VaultPath
    public let size: Int
    public let createdDate: Date
    public let modifiedDate: Date
    public let properties: [BaseFrontmatterEntry]
    /// Tags from frontmatter and body, without `#`.
    public let tags: [String]
    public let links: [BaseRecordLink]
    public var id: VaultPath { path }

    public init(path: VaultPath, size: Int, createdDate: Date, modifiedDate: Date, properties: [BaseFrontmatterEntry] = [], tags: [String] = [], links: [BaseRecordLink] = []) {
        self.path = path
        self.size = size
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.properties = properties
        self.tags = tags
        self.links = links
    }

    /// The frontmatter entry for a property name: exact spelling first, then any
    /// capitalization, since Obsidian treats property names case-insensitively.
    public func propertyEntry(named key: String) -> BaseFrontmatterEntry? {
        properties.first { entry in entry.key == key } ?? properties.first { entry in entry.key.caseInsensitiveCompare(key) == .orderedSame }
    }
}

/// A bounded set of records loaded for one base query.
public struct BaseRecordBatch: Sendable {
    public let records: [BaseFileRecord]
    /// Files that passed the index's cheap pre-filter, which may exceed `records`.
    public let candidateCount: Int
    public var isTruncated: Bool { candidateCount > records.count }
    public init(records: [BaseFileRecord], candidateCount: Int) {
        self.records = records
        self.candidateCount = candidateCount
    }
}

/// Lookups a base needs beyond the rows being evaluated: `file("…")`, `link.asFile()`,
/// link resolution and backlinks. Implementations may block briefly, so evaluation
/// always runs off the main actor.
public protocol BaseRecordProvider: Sendable {
    func record(at path: VaultPath) -> BaseFileRecord?
    /// The single file a link target written in `source` refers to, or nil when it
    /// is missing or ambiguous. The answer depends on `source` only through its folder,
    /// as a link is resolved in Obsidian, and `BaseEvaluator` caches it per folder.
    func resolveLinkTarget(_ target: String, from source: VaultPath) -> VaultPath?
    func backlinks(to path: VaultPath) -> [VaultPath]
}

/// A provider over records already in memory. Used for tests and for small inputs;
/// production queries use the index's provider, whose rules it follows: a note's
/// aliases name it, and links written in properties count as backlinks.
public struct BaseInMemoryRecordProvider: BaseRecordProvider {
    private let recordsByPath: [VaultPath: BaseFileRecord]
    private let aliasesByPath: [VaultPath: [String]]

    public init(records: [BaseFileRecord]) {
        recordsByPath = Dictionary(records.map { record in (record.path, record) }, uniquingKeysWith: { firstRecord, _ in firstRecord })
        aliasesByPath = recordsByPath.compactMapValues { record in
            let aliases = Self.aliases(of: record)
            return aliases.isEmpty ? nil : aliases
        }
    }

    public func record(at path: VaultPath) -> BaseFileRecord? { recordsByPath[path] }

    public func resolveLinkTarget(_ target: String, from source: VaultPath) -> VaultPath? {
        for candidate in WikiLinkResolver.directCandidates(target: target, source: source, isWiki: true) where recordsByPath[candidate] != nil {
            return candidate
        }
        let pathPart = WikiLinkResolver.comparisonKey(WikiLinkResolver.pathPart(target))
        guard !pathPart.isEmpty else { return nil }
        let aliasMatches = pathPart.contains("/") ? [] : aliasesByPath.compactMap { path, aliases in
            aliases.contains { alias in WikiLinkResolver.comparisonKey(alias).caseInsensitiveCompare(pathPart) == .orderedSame } ? path : nil
        }
        for fileName in WikiLinkResolver.fileNameVariants(for: pathPart) {
            // A partial path, such as `covers/Book cover.png`, names the end of a path.
            let suffix = "/" + (fileName.hasPrefix("/") ? String(fileName.dropFirst()) : fileName)
            let nameMatches = recordsByPath.keys.filter { path in
                let pathKey = WikiLinkResolver.comparisonKey(path.rawValue)
                return pathPart.contains("/")
                    ? ("/" + pathKey).lowercased().hasSuffix(suffix.lowercased())
                    : WikiLinkResolver.comparisonKey(path.name).caseInsensitiveCompare(fileName) == .orderedSame
            }
            let matches = Set(nameMatches + aliasMatches)
            if !matches.isEmpty { return matches.count == 1 ? matches.first : nil }
        }
        return nil
    }

    public func backlinks(to path: VaultPath) -> [VaultPath] {
        recordsByPath.values.filter { record in
            (record.links + BaseFrontmatter.links(in: record.properties)).contains { link in resolveLinkTarget(link.target, from: record.path) == path }
        }.map(\.path).sorted()
    }

    /// The `aliases` property, or `alias` when there is none, as the index reads it.
    private static func aliases(of record: BaseFileRecord) -> [String] {
        guard let node = (record.properties.first { entry in entry.key == "aliases" } ?? record.properties.first { entry in entry.key == "alias" })?.node else { return [] }
        let scalarNodes: [BaseFrontmatterNode]
        switch node {
        case .scalar: scalarNodes = [node]
        case .sequence(let items): scalarNodes = items
        case .mapping: scalarNodes = []
        }
        return scalarNodes.compactMap { itemNode in
            guard case .scalar(let text, _) = itemNode, !text.isEmpty else { return nil }
            return text
        }
    }
}
