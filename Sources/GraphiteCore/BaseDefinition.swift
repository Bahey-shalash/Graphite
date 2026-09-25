import Foundation
import Yams

/// A property a view can show: `note.status` (or plain `status`), `file.name`, or
/// `formula.total`.
public enum BasePropertyIdentifier: Hashable, Sendable, Comparable {
    case note(String)
    case file(String)
    case formula(String)

    /// Accepts the spellings `.base` files use. A name without a known prefix is a
    /// note property, so `status` and `note.status` are the same column.
    public init(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        if trimmedText.hasPrefix("note.") { self = .note(String(trimmedText.dropFirst(5))) }
        else if trimmedText.hasPrefix("file.") { self = .file(String(trimmedText.dropFirst(5))) }
        else if trimmedText.hasPrefix("formula.") { self = .formula(String(trimmedText.dropFirst(8))) }
        else { self = .note(trimmedText) }
    }

    /// Canonical spelling with its prefix, as Obsidian writes it back.
    public var rawValue: String {
        switch self {
        case .note(let name): "note.\(name)"
        case .file(let name): "file.\(name)"
        case .formula(let name): "formula.\(name)"
        }
    }

    public var name: String {
        switch self {
        case .note(let name), .file(let name), .formula(let name): name
        }
    }

    /// The column title Obsidian shows when no `displayName` is configured.
    public var defaultDisplayName: String {
        switch self {
        case .note(let name), .formula(let name): return name
        case .file(let name):
            switch name {
            case "name": return "file name"
            case "basename": return "file base name"
            case "path": return "file path"
            case "folder": return "folder"
            case "ext": return "extension"
            case "size": return "file size"
            case "ctime": return "created time"
            case "mtime": return "modified time"
            case "tags": return "file tags"
            case "links": return "file links"
            case "embeds": return "file embeds"
            case "backlinks": return "backlinks"
            case "properties": return "properties"
            default: return "file \(name)"
            }
        }
    }

    public static func < (leftIdentifier: Self, rightIdentifier: Self) -> Bool { leftIdentifier.rawValue < rightIdentifier.rawValue }
}

/// A filter as written: one expression, or an `and` / `or` / `not` list of filters.
/// `not` means none of its children are true.
public indirect enum BaseFilter: Hashable, Sendable {
    case expression(String)
    case and([BaseFilter])
    case or([BaseFilter])
    case not([BaseFilter])
}

public enum BaseSortDirection: String, Hashable, Sendable {
    case ascending = "ASC"
    case descending = "DESC"
}

public struct BaseSortKey: Hashable, Sendable {
    public var property: BasePropertyIdentifier
    public var direction: BaseSortDirection
    public init(property: BasePropertyIdentifier, direction: BaseSortDirection) {
        self.property = property
        self.direction = direction
    }
}

public enum BaseViewType: Hashable, Sendable {
    case table, cards, list, map
    /// A view type Graphite does not render (for example a community plugin's).
    case unsupported(String)

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "table": self = .table
        case "cards": self = .cards
        case "list": self = .list
        case "map": self = .map
        default: self = .unsupported(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .table: "table"
        case .cards: "cards"
        case .list: "list"
        case .map: "map"
        case .unsupported(let name): name
        }
    }
}

public enum BaseImageFit: String, Hashable, Sendable {
    case cover, contain
}

/// Cards view options (`image`, `imageFit`, `imageAspectRatio`, `cardSize`).
public struct BaseCardsOptions: Hashable, Sendable {
    public var imageProperty: BasePropertyIdentifier?
    public var imageFit: BaseImageFit = .cover
    /// Cover height as a fraction of card width.
    public var imageAspectRatio: Double?
    /// Card width in points.
    public var cardSize: Double?
    public init() {}
}

public enum BaseListMarker: String, Hashable, Sendable {
    case bullets, numbers, none
}

/// List view options (`markers`, `indentProperties`, `separator`).
public struct BaseListOptions: Hashable, Sendable {
    public var marker: BaseListMarker = .bullets
    public var indentsProperties = false
    public var separator = ", "
    public init() {}
}

/// Options of the Maps plugin's `map` view, with the plugin's own keys.
public struct BaseMapOptions: Hashable, Sendable {
    public static let defaultZoom = 4.0
    public static let defaultEmbeddedHeight = 400.0
    /// `coordinates`: a property holding `"lat, lng"` or `[lat, lng]`.
    public var coordinatesProperty: BasePropertyIdentifier?
    /// `markerIcon`: a property holding a Lucide icon name.
    public var markerIconProperty: BasePropertyIdentifier?
    /// `markerColor`: a property holding a CSS color.
    public var markerColorProperty: BasePropertyIdentifier?
    public var defaultZoom: Double?
    /// `center`: a formula (or `[lat, lng]` text) evaluated against `this`.
    public var center: String?
    public var minimumZoom = 0.0
    public var maximumZoom = 18.0
    /// `mapHeight`, used only when the base is embedded in a note.
    public var embeddedHeight = defaultEmbeddedHeight
    /// `mapTiles` / `mapTilesDark`: tile or style URLs. MapKit cannot draw these.
    public var tileURLs: [String] = []
    public var darkTileURLs: [String] = []
    public init() {}
}

public struct BaseView: Hashable, Sendable, Identifiable {
    /// Position in the file's `views` list; names may repeat.
    public let id: Int
    public var type: BaseViewType
    public var name: String
    public var limit: Int?
    public var filters: BaseFilter?
    /// The file has filters for this view that were not fully read (an unknown group,
    /// or `and` and `or` side by side). `filters` then holds only the readable part, so
    /// it must not be offered for editing as if it were the whole filter.
    public var hasUnreadableFilters = false
    public var order: [BasePropertyIdentifier]
    public var sort: [BaseSortKey]
    public var groupBy: BaseSortKey?
    /// Property → summary name (a default such as `Average`, or a key of the base's
    /// own `summaries`).
    public var summaries: [BasePropertyIdentifier: String]
    /// `columnSize`: widths in points.
    public var columnWidths: [BasePropertyIdentifier: Double]
    public var rowHeight: String?
    public var cards = BaseCardsOptions()
    public var list = BaseListOptions()
    public var map = BaseMapOptions()

    public init(id: Int, type: BaseViewType, name: String) {
        self.id = id
        self.type = type
        self.name = name
        limit = nil
        filters = nil
        order = []
        sort = []
        groupBy = nil
        summaries = [:]
        columnWidths = [:]
    }

    /// Columns to show. Obsidian shows the file name when `order` is empty.
    public var visibleProperties: [BasePropertyIdentifier] { order.isEmpty ? [.file("name")] : order }
}

public struct BaseFormula: Hashable, Sendable {
    public var name: String
    public var sourceText: String
    public init(name: String, sourceText: String) {
        self.name = name
        self.sourceText = sourceText
    }
}

public enum BaseDefinitionError: Error, Equatable, LocalizedError, Sendable {
    case invalidYAML(String)
    case notAMapping
    case oversized

    /// Deeper YAML would exhaust the stack while parsing (see YAMLNesting).
    static let nestedTooDeeplyReason = "It nests lists or mappings too deeply to read safely."
    /// Too many anchors, or aliases that repeat them beyond what the file's size can
    /// hold (see YAMLAliasExpansion).
    static let aliasesExpandTooFarReason = "Its anchors and aliases (&name, *name) repeat values too much to read safely."

    public var errorDescription: String? {
        switch self {
        case .invalidYAML(let reason): "This base is not valid YAML. \(reason)"
        case .notAMapping: "This base must be a YAML mapping with keys such as filters, formulas and views."
        case .oversized: "This base file is too large to open."
        }
    }
}

/// The contents of a `.base` file or a ```` ```base ```` block. Parsing never changes
/// the source; edits go through `BaseDefinitionEditor`, which keeps unknown keys.
public struct BaseDefinition: Hashable, Sendable {
    /// Base files are small configuration; a larger file is not a real base.
    public static let maximumSourceBytes = 1_048_576
    public var filters: BaseFilter?
    public var formulas: [BaseFormula]
    public var displayNames: [BasePropertyIdentifier: String]
    /// Custom summary formulas by name; `values` is the column's list of values.
    public var summaryFormulas: [String: String]
    public var views: [BaseView]
    /// Problems that did not stop the base from opening, shown to the user.
    public var issues: [String]

    public init(filters: BaseFilter? = nil, formulas: [BaseFormula] = [], displayNames: [BasePropertyIdentifier: String] = [:], summaryFormulas: [String: String] = [:], views: [BaseView] = [], issues: [String] = []) {
        self.filters = filters
        self.formulas = formulas
        self.displayNames = displayNames
        self.summaryFormulas = summaryFormulas
        self.views = views
        self.issues = issues
    }

    public func displayName(for property: BasePropertyIdentifier) -> String {
        displayNames[property] ?? property.defaultDisplayName
    }

    public static func parse(_ yaml: String) throws -> BaseDefinition {
        guard yaml.utf8.count <= maximumSourceBytes else { throw BaseDefinitionError.oversized }
        guard !YAMLNesting.exceedsSafeDepth(yaml) else { throw BaseDefinitionError.invalidYAML(BaseDefinitionError.nestedTooDeeplyReason) }
        guard !YAMLAliasExpansion.exceedsAnchorCount(yaml) else { throw BaseDefinitionError.invalidYAML(BaseDefinitionError.aliasesExpandTooFarReason) }
        var definition = BaseDefinition()
        let rootNode: Node?
        do { rootNode = try Yams.compose(yaml: yaml) }
        catch { throw BaseDefinitionError.invalidYAML(Self.describe(error)) }
        if let rootNode {
            guard !YAMLAliasExpansion.exceedsLimits(rootNode, sourceByteCount: yaml.utf8.count) else {
                throw BaseDefinitionError.invalidYAML(BaseDefinitionError.aliasesExpandTooFarReason)
            }
            guard let mapping = rootNode.mapping else {
                // An empty document or a lone null (`~`, `null`, `NULL`, …) is an empty base.
                if isNullValue(rootNode) { return definition.withDefaultView() }
                throw BaseDefinitionError.notAMapping
            }
            definition.read(readableMapping(mapping))
        }
        return definition.withDefaultView()
    }

    // MARK: YAML as Obsidian reads it

    /// YAML's null: an empty value, `~`, `null`, `Null`, `NULL`, or a `!!null` tag.
    /// Obsidian treats a key whose value is null as absent. Quoted `"null"` is text.
    static func isNullValue(_ node: Node) -> Bool {
        guard case .scalar(let scalar) = node else { return false }
        if scalar.tag.rawValue == Tag.Name.null.rawValue { return true }
        guard scalar.style == .plain, scalar.tag.rawValue == Tag.Name.implicit.rawValue else { return false }
        return ["", "~", "null", "Null", "NULL"].contains(scalar.string)
    }

    /// The mapping as Obsidian's YAML reader (js-yaml) sees it: merge keys applied, and
    /// keys whose value is null left out.
    static func readableMapping(_ mapping: Node.Mapping) -> Node.Mapping {
        let mergedMapping = applyingMergeKeys(mapping)
        let pairs = mergedMapping.filter { _, valueNode in !isNullValue(valueNode) }.map { keyNode, valueNode in (keyNode, valueNode) }
        return Node.Mapping(pairs, mergedMapping.tag, mergedMapping.style)
    }

    /// A merge key (`<<: *defaults`, or `<<: [*first, *second]`) copies the entries of
    /// anchored mappings. Keys written in the mapping itself win, then earlier merged
    /// mappings over later ones. Recursion is bounded by `YAMLAliasExpansion.maximumDepth`.
    static func applyingMergeKeys(_ mapping: Node.Mapping) -> Node.Mapping {
        guard mapping.contains(where: { keyNode, _ in isMergeKey(keyNode) }) else { return mapping }
        var pairs = mapping.filter { keyNode, _ in !isMergeKey(keyNode) }.map { keyNode, valueNode in (keyNode, valueNode) }
        var presentKeys = Set(pairs.map { keyNode, _ in keyNode })
        for (keyNode, valueNode) in mapping where isMergeKey(keyNode) {
            let mergedMappings = valueNode.mapping.map { mergedMapping in [mergedMapping] } ?? (valueNode.sequence ?? []).compactMap(\.mapping)
            for mergedMapping in mergedMappings {
                for (mergedKey, mergedValue) in applyingMergeKeys(mergedMapping) where presentKeys.insert(mergedKey).inserted {
                    pairs.append((mergedKey, mergedValue))
                }
            }
        }
        return Node.Mapping(pairs, mapping.tag, mapping.style)
    }

    private static func isMergeKey(_ node: Node) -> Bool {
        guard case .scalar(let scalar) = node else { return false }
        return scalar.string == "<<" && scalar.style == .plain
    }

    /// Obsidian shows a table when a base defines no views.
    private func withDefaultView() -> BaseDefinition {
        guard views.isEmpty else { return self }
        var definition = self
        definition.views = [BaseView(id: 0, type: .table, name: "Table")]
        return definition
    }

    private static func describe(_ error: Error) -> String {
        if let yamlError = error as? YamlError { return yamlError.description }
        return error.localizedDescription
    }

    private mutating func read(_ mapping: Node.Mapping) {
        if let filtersNode = mapping["filters"] { filters = parseFilter(filtersNode, location: "filters") }
        if let formulasNode = mapping["formulas"] {
            if let formulasMapping = formulasNode.mapping.map(Self.readableMapping) {
                formulas = formulasMapping.compactMap { keyNode, valueNode in
                    guard let name = keyNode.string else { return nil }
                    guard let sourceText = valueNode.scalar?.string else {
                        issues.append("Formula “\(name)” must be text.")
                        return nil
                    }
                    return BaseFormula(name: name, sourceText: sourceText)
                }
            } else if formulasNode.scalar?.string.isEmpty == false { issues.append("“formulas” must map names to expressions.") }
        }
        if let propertiesMapping = mapping["properties"]?.mapping {
            for (keyNode, valueNode) in propertiesMapping {
                guard let key = keyNode.string, let displayName = valueNode.mapping.map(Self.readableMapping)?["displayName"]?.scalar?.string else { continue }
                displayNames[BasePropertyIdentifier(key)] = displayName
            }
        }
        if let summariesMapping = mapping["summaries"]?.mapping.map(Self.readableMapping) {
            for (keyNode, valueNode) in summariesMapping {
                guard let name = keyNode.string, let sourceText = valueNode.scalar?.string else { continue }
                summaryFormulas[name] = sourceText
            }
        }
        if let viewsNode = mapping["views"] {
            if let viewNodes = viewsNode.sequence {
                for (position, viewNode) in viewNodes.enumerated() {
                    guard let viewMapping = viewNode.mapping else {
                        issues.append("View \(position + 1) is not a mapping and was skipped.")
                        continue
                    }
                    views.append(parseView(Self.readableMapping(viewMapping), position: position))
                }
            } else if viewsNode.scalar?.string.isEmpty == false || viewsNode.mapping != nil {
                issues.append("“views” must be a list.")
            }
        }
    }

    private mutating func parseView(_ mapping: Node.Mapping, position: Int) -> BaseView {
        let typeName = mapping["type"]?.scalar?.string ?? "table"
        let name = mapping["name"]?.scalar?.string ?? "View \(position + 1)"
        var view = BaseView(id: position, type: BaseViewType(rawValue: typeName), name: name)
        if let limitText = mapping["limit"]?.scalar?.string {
            if let limit = Int(limitText), limit > 0 { view.limit = limit }
            else { issues.append("View “\(name)” has an invalid limit “\(limitText)”.") }
        }
        if let filtersNode = mapping["filters"] {
            let issueCountBeforeFilters = issues.count
            view.filters = parseFilter(filtersNode, location: "view “\(name)”")
            view.hasUnreadableFilters = issues.count > issueCountBeforeFilters
        }
        // A property listed twice is shown once; columns are identified by their property.
        var listedProperties = Set<BasePropertyIdentifier>()
        view.order = (mapping["order"]?.sequence ?? []).filter { node in !Self.isNullValue(node) }.compactMap { node in node.scalar?.string }.map(BasePropertyIdentifier.init)
            .filter { property in listedProperties.insert(property).inserted }
        view.sort = (mapping["sort"]?.sequence ?? []).compactMap(parseSortKey)
        if let groupNode = mapping["groupBy"] {
            view.groupBy = parseSortKey(groupNode) ?? groupNode.scalar.map { scalar in BaseSortKey(property: BasePropertyIdentifier(scalar.string), direction: .ascending) }
        }
        for (keyNode, valueNode) in mapping["summaries"]?.mapping.map(Self.readableMapping) ?? [:] {
            guard let key = keyNode.string, let summaryName = valueNode.scalar?.string else { continue }
            view.summaries[BasePropertyIdentifier(key)] = summaryName
        }
        for (keyNode, valueNode) in mapping["columnSize"]?.mapping ?? [:] {
            guard let key = keyNode.string, let width = valueNode.scalar.flatMap({ scalar in Double(scalar.string) }), width > 0 else { continue }
            view.columnWidths[BasePropertyIdentifier(key)] = min(width, 2_000)
        }
        view.rowHeight = mapping["rowHeight"]?.scalar?.string
        view.cards = parseCardsOptions(mapping)
        view.list = parseListOptions(mapping)
        view.map = parseMapOptions(mapping)
        return view
    }

    /// Sort entries are `{property, direction}`; early Obsidian builds wrote `column`.
    private func parseSortKey(_ node: Node) -> BaseSortKey? {
        guard let writtenMapping = node.mapping else { return nil }
        let mapping = Self.readableMapping(writtenMapping)
        guard let propertyText = (mapping["property"] ?? mapping["column"])?.scalar?.string else { return nil }
        let direction = BaseSortDirection(rawValue: (mapping["direction"]?.scalar?.string ?? "ASC").uppercased()) ?? .ascending
        return BaseSortKey(property: BasePropertyIdentifier(propertyText), direction: direction)
    }

    private func parseCardsOptions(_ mapping: Node.Mapping) -> BaseCardsOptions {
        var options = BaseCardsOptions()
        if let imageText = mapping["image"]?.scalar?.string, !imageText.isEmpty { options.imageProperty = BasePropertyIdentifier(imageText) }
        if let fitText = mapping["imageFit"]?.scalar?.string { options.imageFit = BaseImageFit(rawValue: fitText.lowercased()) ?? .cover }
        if let ratioText = mapping["imageAspectRatio"]?.scalar?.string { options.imageAspectRatio = Self.aspectRatio(from: ratioText) }
        if let sizeText = mapping["cardSize"]?.scalar?.string, let size = Double(sizeText), size > 0 { options.cardSize = min(max(size, 80), 1_200) }
        return options
    }

    /// Accepts a number (`1.5`) or a ratio written as `3:2` / `3/2` (width to height).
    static func aspectRatio(from text: String) -> Double? {
        if let number = Double(text), number > 0 { return min(max(number, 0.1), 10) }
        let parts = text.split(whereSeparator: { character in character == ":" || character == "/" }).compactMap { part in Double(part.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return min(max(parts[1] / parts[0], 0.1), 10)
    }

    private func parseListOptions(_ mapping: Node.Mapping) -> BaseListOptions {
        var options = BaseListOptions()
        switch mapping["markers"]?.scalar?.string.lowercased() {
        case "numbers", "number", "numbered": options.marker = .numbers
        case "none": options.marker = .none
        default: options.marker = .bullets
        }
        options.indentsProperties = mapping["indentProperties"]?.scalar.map { scalar in scalar.string.lowercased() == "true" } ?? false
        if let separator = mapping["separator"]?.scalar?.string { options.separator = separator }
        return options
    }

    private func parseMapOptions(_ mapping: Node.Mapping) -> BaseMapOptions {
        var options = BaseMapOptions()
        func property(_ key: String) -> BasePropertyIdentifier? {
            guard let text = mapping[key]?.scalar?.string, !text.isEmpty else { return nil }
            return BasePropertyIdentifier(text)
        }
        // Swift reads `nan` as a number, and NaN passes through the clamps below into
        // MapKit, which throws on a region with a NaN span.
        func number(_ key: String) -> Double? { mapping[key]?.scalar.flatMap { scalar in Double(scalar.string) }.flatMap { number in number.isNaN ? nil : number } }
        func textList(_ key: String) -> [String] {
            if let sequence = mapping[key]?.sequence { return sequence.compactMap { node in node.scalar?.string }.filter { text in !text.isEmpty } }
            if let text = mapping[key]?.scalar?.string, !text.isEmpty { return [text] }
            return []
        }
        options.coordinatesProperty = property("coordinates")
        options.markerIconProperty = property("markerIcon")
        options.markerColorProperty = property("markerColor")
        // The plugin clamps zoom levels to 0...24 and the embedded height to 100...2000.
        options.minimumZoom = min(max(number("minZoom") ?? 0, 0), 24)
        options.maximumZoom = min(max(number("maxZoom") ?? 18, 0), 24)
        // `zoom` and `height` are accepted too; some published bases use those names.
        options.defaultZoom = (number("defaultZoom") ?? number("zoom")).map { zoom in min(max(zoom, options.minimumZoom), options.maximumZoom) }
        options.embeddedHeight = min(max(number("mapHeight") ?? number("height") ?? BaseMapOptions.defaultEmbeddedHeight, 100), 2_000)
        if let centerNode = mapping["center"] {
            if let sequence = centerNode.sequence {
                options.center = "[" + sequence.compactMap { node in node.scalar?.string }.joined(separator: ", ") + "]"
            } else if let text = centerNode.scalar?.string, !text.isEmpty {
                options.center = text
            }
        }
        options.tileURLs = textList("mapTiles")
        options.darkTileURLs = textList("mapTilesDark")
        return options
    }

    private mutating func parseFilter(_ node: Node, location: String) -> BaseFilter? {
        switch node {
        case .scalar(let scalar):
            guard !Self.isNullValue(node) else { return nil }
            let text = scalar.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : .expression(text)
        case .mapping(let writtenMapping):
            // Null values stay: `and:` with nothing after it is an empty group, not a missing key.
            let mapping = Self.applyingMergeKeys(writtenMapping)
            guard mapping.count == 1, let onlyPair = mapping.first, let key = onlyPair.key.string else {
                issues.append("A filter in \(location) must have exactly one of “and”, “or” or “not”.")
                return nil
            }
            let childNodes = onlyPair.value.sequence.map { sequence in Array(sequence) } ?? [onlyPair.value]
            let children = childNodes.compactMap { childNode in parseFilter(childNode, location: location) }
            switch key {
            case "and": return .and(children)
            case "or": return .or(children)
            case "not": return .not(children)
            default:
                issues.append("Unknown filter group “\(key)” in \(location); use and, or or not.")
                return nil
            }
        case .sequence(let sequence):
            // A bare list is read as "all of these", which is what people mean by it.
            return .and(sequence.compactMap { childNode in parseFilter(childNode, location: location) })
        case .alias:
            return nil
        }
    }
}
