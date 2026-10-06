import Foundation
import Yams

/// Changes a base's view configuration and writes the YAML back. Edits are made on the
/// parsed YAML tree, so keys Graphite does not know (other view options, plugin
/// settings) are kept with their values. Writing back replaces only the lines of the
/// entries that changed, such as one view's `limit:` line, so comments, indentation,
/// flow style, tags and document markers elsewhere stay exactly as written. Inside a
/// rewritten entry, the parts that did not change keep their anchors, aliases, tags and
/// flow style (`RewrittenYAMLWriter`). When the changed lines cannot be replaced exactly,
/// the whole file is written from the tree; YAML has no comment nodes, so its comments
/// are then lost. Every output is read back, and an edit whose result would not mean
/// what the edited configuration means is refused.
///
/// Not `Sendable` (Yams nodes hold anchors); create and use it inside one task.
public struct BaseDefinitionEditor {
    private var rootMapping: Node.Mapping
    private let originalText: String
    /// The file's tree before any edit, with where each node starts in `originalText`.
    private let originalTree: WrittenYAMLNode?
    /// The file's most common line ending, used for the lines Graphite writes.
    private let lineEnding: String
    /// An edit that would have lost content in the file. `yaml()` throws it, so nothing
    /// is saved.
    private var refusedEdit: GraphiteError?

    public init(yaml: String) throws {
        guard yaml.utf8.count <= BaseDefinition.maximumSourceBytes else { throw BaseDefinitionError.oversized }
        guard !YAMLNesting.exceedsSafeDepth(yaml) else { throw BaseDefinitionError.invalidYAML(BaseDefinitionError.nestedTooDeeplyReason) }
        guard !YAMLAliasExpansion.exceedsAnchorCount(yaml) else { throw BaseDefinitionError.invalidYAML(BaseDefinitionError.aliasesExpandTooFarReason) }
        let parser: Yams.Parser
        let rootNode: Node?
        do {
            parser = try Yams.Parser(yaml: yaml)
            rootNode = try parser.singleRoot()
        } catch { throw BaseDefinitionError.invalidYAML(String(describing: error)) }
        if let rootNode, YAMLAliasExpansion.exceedsLimits(rootNode, sourceByteCount: yaml.utf8.count) {
            throw BaseDefinitionError.invalidYAML(BaseDefinitionError.aliasesExpandTooFarReason)
        }
        originalText = yaml
        lineEnding = Self.predominantLineEnding(in: yaml)
        let sourceLines = YAMLSourceLine.lines(of: yaml)
        // Yams keeps a node's anchor only as long as its parser lives, so the tree is
        // described, anchors included, before the parser goes.
        originalTree = withExtendedLifetime(parser) { rootNode.map { node in WrittenYAMLNode(node, sourceLines: sourceLines) } }
        switch rootNode {
        case nil:
            rootMapping = Node.Mapping([])
        case .mapping(let mapping)?:
            rootMapping = mapping
        case let node? where BaseDefinition.isNullValue(node):
            rootMapping = Node.Mapping([])
        default:
            throw BaseDefinitionError.notAMapping
        }
    }

    /// The edited YAML. Unchanged entries keep their text; changed ones are written
    /// with two-space indentation, no line wrapping and Unicode kept as written.
    public func yaml() throws -> String {
        if let refusedEdit { throw refusedEdit }
        let editedTree = WrittenYAMLNode(.mapping(rootMapping), sourceLines: nil)
        // An empty or null document reads as an empty mapping.
        var originalMeaning = WrittenYAMLNode(.mapping(Node.Mapping([])), sourceLines: nil)
        if let originalTree, case .mapping = originalTree.content { originalMeaning = originalTree }
        if editedTree.hasSameMeaning(as: originalMeaning) { return originalText }
        if let splicedText = splicedYAML(editedTree: editedTree) { return splicedText }
        let sourceLines = YAMLSourceLine.lines(of: originalText)
        // Anchors, aliases and tags are kept when the text then reads back as the edited
        // configuration. An anchor whose value changed, for one, can leave an alias meaning
        // something else; every value is then written out where it is used.
        let replacedLines = sourceLines.map { lines in 0..<lines.count }
        var output = try RewrittenYAMLWriter.yaml(of: [(editedTree, originalTree)], as: .document, replacedLines: replacedLines, sourceLines: sourceLines)
        if !Self.reads(output, as: editedTree) {
            output = try RewrittenYAMLWriter.yaml(of: [(editedTree, nil)], as: .document, replacedLines: nil, sourceLines: sourceLines)
        }
        // A write that would drop a custom tag, or change what the file means otherwise,
        // is refused rather than saved.
        guard Self.reads(output, as: editedTree) else {
            throw GraphiteError.invalidFile("Graphite cannot preserve this base's YAML tags or anchors while making that edit. The file has been left unchanged. Edit it in source instead.")
        }
        return lineEnding == "\n" ? output : output.replacingOccurrences(of: "\n", with: lineEnding)
    }

    /// Whether `yaml` is a mapping that means exactly what `editedTree` means.
    fileprivate static func reads(_ yaml: String, as editedTree: WrittenYAMLNode) -> Bool {
        guard let readBack = try? Yams.compose(yaml: yaml), let readBackMapping = readBack.mapping else { return false }
        return WrittenYAMLNode(.mapping(readBackMapping), sourceLines: nil).hasSameMeaning(as: editedTree)
    }

    /// The original text with only the changed entries rewritten, or nil when that
    /// cannot be done exactly. The result is read back and must mean exactly what the
    /// edited tree means.
    private func splicedYAML(editedTree: WrittenYAMLNode) -> String? {
        guard let sourceLines = YAMLSourceLine.lines(of: originalText) else { return nil }
        let splicer = YAMLSplicer(sourceLines: sourceLines, lineEnding: lineEnding, originalTree: originalTree)
        let outputLines: [String]?
        if let originalTree {
            outputLines = splicer.documentLines(original: originalTree, edited: editedTree)
        } else {
            // Only comments or blank lines so far: the new keys follow them.
            guard case .mapping(let editedEntries) = editedTree.content else { return nil }
            outputLines = splicer.serializedEntryLines(of: editedEntries.map { entry in YAMLSplicer.RewrittenEntry(key: entry.key, value: entry.value, original: nil) },
                                                       replacedLines: nil, firstLinePrefix: "", continuationPrefix: "")
                .map { entryLines in splicer.sourceText(0..<sourceLines.count) + entryLines }
        }
        guard let outputLines else { return nil }
        let splicedText = splicer.joined(outputLines)
        return Self.reads(splicedText, as: editedTree) ? splicedText : nil
    }

    /// The line ending most lines use. Lines Graphite writes get it; lines it keeps
    /// keep their own, so a file with mixed endings changes only where it was edited.
    static func predominantLineEnding(in text: String) -> String {
        var countsByLineEnding: [String: Int] = ["\n": 0, "\r\n": 0, "\r": 0]
        for character in text where character == "\n" || character == "\r\n" || character == "\r" {
            countsByLineEnding[String(character), default: 0] += 1
        }
        // Ties go to LF, then CRLF, which is what a file without line breaks gets.
        return ["\n", "\r\n", "\r"].max { leftEnding, rightEnding in (countsByLineEnding[leftEnding] ?? 0) < (countsByLineEnding[rightEnding] ?? 0) } ?? "\n"
    }

    /// `node` as YAML text with two-space indentation, no line wrapping and Unicode kept as
    /// written. The node must be one made for the writer (`RewrittenYAMLWriter`): the
    /// writer resolves implicit tags in place.
    static func serializedYAML(of node: Node) throws -> String {
        // libyaml treats every character outside the Basic Multilingual Plane (emoji such
        // as 🔴) as unprintable and re-quotes the whole scalar with `\U…` escapes. Such
        // characters are swapped for private-use characters the text does not use,
        // which libyaml prints as they are, and restored afterwards.
        var usedScalars = Set<Unicode.Scalar>()
        Self.visitText(in: node) { text in usedScalars.formUnion(text.unicodeScalars) }
        let supplementaryScalars = usedScalars.filter { scalar in scalar.value > 0xFFFF }
        let freePlaceholders = (Self.privateUseRange).lazy.compactMap(Unicode.Scalar.init).filter { scalar in !usedScalars.contains(scalar) }
        var placeholderByScalar: [Unicode.Scalar: Unicode.Scalar] = [:]
        for (scalar, placeholder) in zip(supplementaryScalars, freePlaceholders) { placeholderByScalar[scalar] = placeholder }
        guard placeholderByScalar.count == supplementaryScalars.count, !placeholderByScalar.isEmpty else {
            return try Yams.serialize(node: node, indent: 2, width: -1, allowUnicode: true)
        }
        let protectedNode = Self.replacingText(in: node) { text in
            String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in placeholderByScalar[scalar] ?? scalar }))
        }
        let output = try Yams.serialize(node: protectedNode, indent: 2, width: -1, allowUnicode: true)
        let scalarByPlaceholder = Dictionary(uniqueKeysWithValues: placeholderByScalar.map { entry in (entry.value, entry.key) })
        return String(String.UnicodeScalarView(output.unicodeScalars.map { scalar in scalarByPlaceholder[scalar] ?? scalar }))
    }

    /// Unicode's Private Use Area in the Basic Multilingual Plane.
    private static let privateUseRange: ClosedRange<UInt32> = 0xE000...0xF8FF

    static func visitText(in node: Node, _ visit: (String) -> Void) {
        switch node {
        case .scalar(let scalar): visit(scalar.string)
        case .sequence(let sequence): sequence.forEach { item in visitText(in: item, visit) }
        case .mapping(let mapping): mapping.forEach { pair in visitText(in: pair.key, visit); visitText(in: pair.value, visit) }
        case .alias: break
        }
    }

    /// `node` with every scalar's text replaced; tags, styles and anchors stay.
    private static func replacingText(in node: Node, _ transformText: (String) -> String) -> Node {
        switch node {
        case .scalar(let scalar):
            return .scalar(Node.Scalar(transformText(scalar.string), scalar.tag, scalar.style, nil, scalar.anchor))
        case .sequence(let sequence):
            return .sequence(Node.Sequence(sequence.map { item in replacingText(in: item, transformText) }, sequence.tag, sequence.style, nil, sequence.anchor))
        case .mapping(let mapping):
            let pairs = mapping.map { pair in (replacingText(in: pair.key, transformText), replacingText(in: pair.value, transformText)) }
            return .mapping(Node.Mapping(pairs, mapping.tag, mapping.style, nil, mapping.anchor))
        case .alias:
            return node
        }
    }

    // MARK: Views

    /// The number of entries in the file's `views` list. The default table shown for a
    /// base without views is not counted, though edits can address it as view 0.
    var viewCount: Int { rootMapping["views"]?.sequence?.count ?? 0 }

    /// Appends a view and returns its position. When the file's `views` cannot take a
    /// new view without losing what is written there, nothing changes and `yaml()`
    /// throws.
    @discardableResult
    public mutating func addView(type: BaseViewType, name: String, order: [BasePropertyIdentifier] = [.file("name")]) -> Int {
        var views: Node.Sequence
        do { views = try ensuredViews() } catch {
            refusedEdit = (error as? GraphiteError) ?? Self.unreadableViews
            return 0
        }
        var viewMapping = Node.Mapping([])
        viewMapping["type"] = Self.textNode(type.rawValue)
        viewMapping["name"] = Self.textNode(name)
        if !order.isEmpty { viewMapping["order"] = .sequence(Node.Sequence(order.map { property in Self.textNode(property.rawValue) })) }
        views.append(.mapping(viewMapping))
        rootMapping["views"] = .sequence(views)
        return views.count - 1
    }

    @discardableResult
    public mutating func duplicateView(at viewIndex: Int, name: String) throws -> Int {
        var views = try ensuredViews()
        guard views.indices.contains(viewIndex), var copy = views[viewIndex].mapping else { throw Self.missingView(viewIndex) }
        copy["name"] = Self.textNode(name)
        views.insert(.mapping(copy), at: viewIndex + 1)
        rootMapping["views"] = .sequence(views)
        return viewIndex + 1
    }

    public mutating func removeView(at viewIndex: Int) throws {
        var views = try ensuredViews()
        guard views.indices.contains(viewIndex) else { throw Self.missingView(viewIndex) }
        views.remove(at: viewIndex)
        rootMapping["views"] = .sequence(views)
    }

    public mutating func setName(_ name: String, forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in viewMapping["name"] = Self.textNode(name) }
    }

    public mutating func setType(_ type: BaseViewType, forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in viewMapping["type"] = Self.textNode(type.rawValue) }
    }

    public mutating func setLimit(_ limit: Int?, forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in viewMapping["limit"] = limit.map { limit in Node(String(max(limit, 1))) } }
    }

    /// Keeps each property's existing entry, so its spelling (`status` stays `status`),
    /// its quoting and its tag stay as written, and writes new ones with their prefix as
    /// Obsidian does (`note.status`). A tag on the list itself stays too.
    public mutating func setOrder(_ order: [BasePropertyIdentifier], forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in
            let existingOrder = viewMapping["order"]?.sequence
            var existingNodeByProperty: [BasePropertyIdentifier: Node] = [:]
            for node in existingOrder ?? [] {
                guard let spelling = node.scalar?.string else { continue }
                existingNodeByProperty[BasePropertyIdentifier(spelling)] = node
            }
            let orderNodes = order.map { property in existingNodeByProperty[property] ?? Self.textNode(property.rawValue) }
            viewMapping["order"] = order.isEmpty ? nil : .sequence(Node.Sequence(orderNodes, existingOrder?.tag ?? .implicit))
        }
    }

    public mutating func setSort(_ sortKeys: [BaseSortKey], forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in
            viewMapping["sort"] = sortKeys.isEmpty ? nil : .sequence(Node.Sequence(sortKeys.map(Self.sortNode)))
        }
    }

    public mutating func setGroupBy(_ groupBy: BaseSortKey?, forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in viewMapping["groupBy"] = groupBy.map(Self.sortNode) }
    }

    /// Replaces the view's filters with "all of these" expressions, or removes them.
    /// Refuses when the file's filters are more than such a list (nested groups, or
    /// groups Graphite cannot read), since replacing them would lose conditions.
    public mutating func setFilterExpressions(_ expressions: [String], forViewAt viewIndex: Int) throws {
        let trimmedExpressions = expressions.map { expression in expression.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { expression in !expression.isEmpty }
        let views = try ensuredViews()
        if views.indices.contains(viewIndex), let filtersNode = views[viewIndex].mapping?["filters"], !Self.isExpressionList(filtersNode) {
            throw GraphiteError.invalidFile("This view's filters use groups that Graphite cannot edit, so it left them unchanged. Edit them in the file.")
        }
        try updateView(at: viewIndex) { viewMapping in
            guard !trimmedExpressions.isEmpty else { viewMapping["filters"] = nil; return }
            var filterMapping = Node.Mapping([])
            filterMapping["and"] = .sequence(Node.Sequence(trimmedExpressions.map(Self.textNode)))
            viewMapping["filters"] = .mapping(filterMapping)
        }
    }

    /// Sets the width of one table column in the view's `columnSize`, or removes it with
    /// nil so the column takes its default width again. As in Obsidian, the width is whole
    /// points under the property's full name (`note.status`), the only spelling Obsidian
    /// reads. The widths of other columns stay as written.
    public mutating func setColumnWidth(_ width: Double?, of property: BasePropertyIdentifier, forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in
            var widths = viewMapping["columnSize"]?.mapping ?? Node.Mapping([])
            // A width under another spelling of the property (`status`) would stay beside
            // the new one and leave the column two widths.
            for keyNode in widths.keys where keyNode.string != property.rawValue && keyNode.string.map(BasePropertyIdentifier.init) == property {
                widths[keyNode] = nil
            }
            let keyNode = widths.keys.first { keyNode in keyNode.string == property.rawValue } ?? Self.textNode(property.rawValue)
            widths[keyNode] = width.map { width in
                Node(String(Int(min(max(width, BaseView.minimumColumnWidth), BaseView.maximumColumnWidth).rounded())))
            }
            viewMapping["columnSize"] = widths.isEmpty ? nil : .mapping(widths)
        }
    }

    /// Sets (or removes, with nil) a view option such as `image`, `coordinates` or `cardSize`.
    public mutating func setOption(_ key: String, text: String?, forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in viewMapping[key] = text.map(Self.textNode) }
    }

    public mutating func setOption(_ key: String, number: Double?, forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in viewMapping[key] = number.map { number in Node(BaseValue.formatted(number)) } }
    }

    // MARK: Helpers

    /// Filters written as nothing, one expression, a list of expressions, or `and:` with
    /// one or a list of expressions: what `BaseFilter.flatExpressions` can offer for
    /// editing.
    private static func isExpressionList(_ filtersNode: Node) -> Bool {
        func isExpression(_ node: Node) -> Bool { node.scalar != nil }
        func isExpressionSequence(_ node: Node) -> Bool { node.sequence.map { sequence in sequence.allSatisfy(isExpression) } ?? false }
        switch filtersNode {
        case .scalar: return true
        case .sequence: return isExpressionSequence(filtersNode)
        case .mapping(let mapping):
            guard mapping.count == 1, let onlyPair = mapping.first, onlyPair.key.string == "and" else { return false }
            return isExpression(onlyPair.value) || isExpressionSequence(onlyPair.value)
        case .alias: return false
        }
    }

    /// The file's views, or the default table Obsidian shows when there are none.
    /// Throws when `views` holds something else, which an edit would overwrite.
    private func ensuredViews() throws -> Node.Sequence {
        switch rootMapping["views"] {
        case let viewsNode? where !BaseDefinition.isNullValue(viewsNode):
            guard let views = viewsNode.sequence else { throw Self.unreadableViews }
            if views.isEmpty { break }
            // Parsing skips entries that are not mappings; with none left it shows the
            // default table, which has no entry here to edit.
            guard views.contains(where: { viewNode in viewNode.mapping != nil }) else { throw Self.unreadableViews }
            return views
        default:
            break
        }
        var defaultView = Node.Mapping([])
        defaultView["type"] = Node("table")
        defaultView["name"] = Node("Table")
        return Node.Sequence([.mapping(defaultView)])
    }

    private static let unreadableViews = GraphiteError.invalidFile("This base's “views” is not a list of view settings, so Graphite left the file unchanged. Fix “views” in the file first.")

    private mutating func updateView(at viewIndex: Int, _ change: (inout Node.Mapping) -> Void) throws {
        var views = try ensuredViews()
        guard views.indices.contains(viewIndex), var viewMapping = views[viewIndex].mapping else { throw Self.missingView(viewIndex) }
        change(&viewMapping)
        views[viewIndex] = .mapping(viewMapping)
        rootMapping["views"] = .sequence(views)
    }

    private static func missingView(_ viewIndex: Int) -> GraphiteError {
        GraphiteError.invalidFile("View \(viewIndex + 1) no longer exists in this base. Reload it and try again.")
    }

    private static func sortNode(_ sortKey: BaseSortKey) -> Node {
        var mapping = Node.Mapping([])
        mapping["property"] = textNode(sortKey.property.rawValue)
        mapping["direction"] = Node(sortKey.direction.rawValue)
        return .mapping(mapping)
    }

    /// Text that YAML would read as another type (`true`, `12`, `null`) is quoted, so
    /// names and expressions stay text; everything else lets the emitter choose.
    static func textNode(_ text: String) -> Node {
        let plainNode = Node(text)
        return Resolver.default.resolveTag(of: plainNode) == .str ? plainNode : Node(text, .implicit, .doubleQuoted)
    }
}

extension BaseFilter {
    /// The expressions of a filter that is empty, one expression, or an `and` of
    /// expressions; nil for nested groups, which only the file can express.
    public static func flatExpressions(of filter: BaseFilter?) -> [String]? {
        switch filter {
        case nil: return []
        case .expression(let expression)?: return [expression]
        case .and(let children)?:
            var expressions: [String] = []
            for child in children {
                guard case .expression(let expression) = child else { return nil }
                expressions.append(expression)
            }
            return expressions
        default: return nil
        }
    }
}

// MARK: Writing back only what changed

/// One line of the original text and the line break that ends it (empty for a last
/// line without one).
struct YAMLSourceLine {
    let content: Substring
    let terminator: Substring

    /// The lines of `text`, or nil when libyaml would count lines differently: it also
    /// breaks lines at NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR, and skips a byte
    /// order mark.
    static func lines(of text: String) -> [YAMLSourceLine]? {
        let otherLineBreaks: Set<Unicode.Scalar> = ["\u{85}", "\u{2028}", "\u{2029}", "\u{FEFF}"]
        guard !text.unicodeScalars.contains(where: { scalar in otherLineBreaks.contains(scalar) }) else { return nil }
        var lines: [YAMLSourceLine] = []
        var lineStart = text.startIndex
        var position = text.startIndex
        while position < text.endIndex {
            let nextPosition = text.index(after: position)
            // `\r\n` is one Character, so it ends a line once.
            if text[position] == "\n" || text[position] == "\r\n" || text[position] == "\r" {
                lines.append(YAMLSourceLine(content: text[lineStart..<position], terminator: text[position..<nextPosition]))
                lineStart = nextPosition
            }
            position = nextPosition
        }
        if lineStart < text.endIndex { lines.append(YAMLSourceLine(content: text[lineStart...], terminator: "")) }
        return lines
    }
}

/// A YAML node reduced to what it means (scalar text and type, the order of entries)
/// and how the file writes it: where it starts, its anchor or alias, its tag, and
/// whether it is in flow style. It is taken before anything asks Yams for a resolved
/// tag, because Yams resolves implicit tags in place on objects that copies of the tree
/// share.
struct WrittenYAMLNode {
    enum Content {
        case scalar(text: String, typeName: String)
        case sequence([WrittenYAMLNode])
        case mapping([(key: WrittenYAMLNode, value: WrittenYAMLNode)])
    }

    /// Tags whose type survives writing, through the scalar's style.
    static let writableTypeNames = Set([Tag.Name.str, .int, .float, .bool, .null, .timestamp].map(\.rawValue))

    /// Tags a node has without one being written: none, `!`, and the types plain text, a
    /// list and a mapping resolve to. Any other tag (a plugin's `!custom`, `!!binary`,
    /// `!!set`) must be written for the node to keep it.
    private static let impliedTagNames = Set([Tag.Name.implicit, .nonSpecific, .str, .seq, .map, .bool, .float, .null, .int, .merge, .timestamp, .value].map(\.rawValue))

    let node: Node
    let content: Content
    /// Zero-based line and column (in Unicode scalars, as libyaml counts) where the
    /// node starts in the original text; nil for an edited tree. An alias has the
    /// position of the node it repeats.
    let line: Int?
    let column: Int?
    /// A block-style list or mapping; flow collections are only ever replaced whole.
    let isBlockCollection: Bool
    /// A list or mapping written in flow style (`[…]`, `{…}`) in the original text. Yams
    /// does not report the style of a collection it read.
    let isFlowCollection: Bool
    /// The anchor written on the node (`&name`), or the anchor its alias (`*name`)
    /// repeats. Yams keeps anchors only while the parser that read them lives, so this is
    /// nil in an edited tree.
    let anchorName: String?
    /// Whether the original text writes this node as an alias of an earlier one.
    let isAlias: Bool
    /// The node's tag when it is not an implied one.
    let customTagName: String?

    init(_ node: Node, sourceLines: [YAMLSourceLine]?) {
        var anchoredPositions = Set<AnchoredPosition>()
        self.init(node, sourceLines: sourceLines, anchoredPositions: &anchoredPositions)
    }

    private struct AnchoredPosition: Hashable {
        let line: Int
        let column: Int
        let anchorName: String
    }

    /// - Parameter anchoredPositions: Where anchored nodes were seen so far, in document
    ///   order. Yams hands an alias the anchored node itself, position included, so a
    ///   second node at an anchored position is an alias of the first.
    private init(_ node: Node, sourceLines: [YAMLSourceLine]?, anchoredPositions: inout Set<AnchoredPosition>) {
        self.node = node
        var startsFlowCollection = false
        if let sourceLines, let mark = node.mark, sourceLines.indices.contains(mark.line - 1) {
            line = mark.line - 1
            column = mark.column - 1
            startsFlowCollection = Self.startsFlowCollection(sourceLines[mark.line - 1], column: mark.column - 1)
        } else {
            line = nil
            column = nil
        }
        anchorName = node.anchor?.rawValue
        if let anchorName, let line, let column {
            isAlias = !anchoredPositions.insert(AnchoredPosition(line: line, column: column, anchorName: anchorName)).inserted
        } else {
            isAlias = false
        }
        let isInOriginalText = line != nil
        switch node {
        case .scalar(let scalar):
            content = .scalar(text: scalar.string, typeName: Self.typeName(of: scalar))
            customTagName = Self.customTagName(scalar.tag)
            isFlowCollection = false
            isBlockCollection = false
        case .sequence(let sequence):
            content = .sequence(sequence.map { item in WrittenYAMLNode(item, sourceLines: sourceLines, anchoredPositions: &anchoredPositions) })
            customTagName = Self.customTagName(sequence.tag)
            isFlowCollection = startsFlowCollection
            isBlockCollection = isInOriginalText && !startsFlowCollection && !sequence.isEmpty
        case .mapping(let mapping):
            content = .mapping(mapping.map { pair in
                (key: WrittenYAMLNode(pair.key, sourceLines: sourceLines, anchoredPositions: &anchoredPositions),
                 value: WrittenYAMLNode(pair.value, sourceLines: sourceLines, anchoredPositions: &anchoredPositions))
            })
            customTagName = Self.customTagName(mapping.tag)
            isFlowCollection = startsFlowCollection
            isBlockCollection = isInOriginalText && !startsFlowCollection && !mapping.isEmpty
        case .alias:
            content = .scalar(text: "", typeName: Tag.Name.null.rawValue)
            customTagName = nil
            isFlowCollection = false
            isBlockCollection = false
        }
    }

    /// Whether the text at `column` of a line, after any anchor and tag written there,
    /// opens a flow list or mapping.
    static func startsFlowCollection(_ sourceLine: YAMLSourceLine, column: Int) -> Bool {
        var remainder = sourceLine.content.unicodeScalars.dropFirst(column)
        while let first = remainder.first {
            switch first {
            case " ", "\t":
                remainder = remainder.dropFirst()
            case "&":
                // libyaml reads an anchor name of letters, digits, `-` and `_`.
                remainder = remainder.dropFirst().drop { scalar in scalar == "-" || scalar == "_" || (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) }
            case "!":
                remainder = remainder.drop { scalar in scalar != " " && scalar != "\t" }
            default:
                return first == "[" || first == "{"
            }
        }
        return false
    }

    private static func customTagName(_ tag: Tag) -> String? {
        impliedTagNames.contains(tag.rawValue) ? nil : tag.rawValue
    }

    /// The type a reader gives the scalar once it is written: an explicit core tag,
    /// `str` for quoted text, and otherwise what the plain text resolves to. A custom tag
    /// is compared on its own (`customTagName`).
    private static func typeName(of scalar: Node.Scalar) -> String {
        let tagName = scalar.tag.rawValue
        if writableTypeNames.contains(tagName) { return tagName }
        if tagName == Tag.Name.nonSpecific.rawValue || (scalar.style != .plain && scalar.style != .any) { return Tag.Name.str.rawValue }
        return Resolver.default.resolveTag(of: Node(scalar.string)).rawValue
    }

    /// The line where a block list's or mapping's first item or key starts. With an
    /// anchor or a tag on the key's line (`order: &columns`), the collection itself
    /// starts there, before its content.
    var firstContentLine: Int? {
        switch content {
        case .scalar: nil
        case .sequence(let items): items.first?.line
        case .mapping(let entries): entries.first?.key.line
        }
    }

    func hasSameMeaning(as other: WrittenYAMLNode) -> Bool {
        guard customTagName == other.customTagName else { return false }
        switch (content, other.content) {
        case (.scalar(let text, let typeName), .scalar(let otherText, let otherTypeName)):
            return text == otherText && typeName == otherTypeName
        case (.sequence(let items), .sequence(let otherItems)):
            return items.count == otherItems.count && zip(items, otherItems).allSatisfy { item, otherItem in item.hasSameMeaning(as: otherItem) }
        case (.mapping(let entries), .mapping(let otherEntries)):
            return entries.count == otherEntries.count && zip(entries, otherEntries).allSatisfy { entry, otherEntry in
                entry.key.hasSameMeaning(as: otherEntry.key) && entry.value.hasSameMeaning(as: otherEntry.value)
            }
        default:
            return false
        }
    }
}

/// Turns nodes Graphite rewrites into YAML text. What the file wrote on the parts that
/// did not change is written again: an anchor (`&name`), an alias (`*name`), a tag no
/// plain text implies (`!custom`), and flow style. Yams reads none of these back on its
/// own: it hands an alias a copy of the anchored node, drops anchors with the parser, never
/// writes a scalar's tag and does not report a collection's style.
///
/// Each node to write comes with the node it replaces in the original text, when there
/// is one. Only a node that still means what its original meant is written as an alias,
/// and the caller reads the result back, so a kept anchor or alias can never change
/// what the file means.
struct RewrittenYAMLWriter {
    typealias ReplacingNode = (edited: WrittenYAMLNode, original: WrittenYAMLNode?)

    enum Layout {
        /// One node: the whole document.
        case document
        /// The entries of a mapping, as alternating keys and values.
        case mappingEntries
        /// The items of a list.
        case sequenceItems
    }

    /// The original lines the written text replaces. An anchor defined within them is
    /// written again with its node; one defined before them is still in the file for an
    /// alias to repeat.
    private let replacedLines: Range<Int>?
    private let sourceLines: [YAMLSourceLine]?
    /// Yams nodes hold their anchors weakly, so the anchors live here until the text is written.
    private var anchors: [Anchor] = []
    /// What each anchor written so far stands for.
    private var definedAnchors: [String: WrittenYAMLNode] = [:]
    /// A scalar's tag is written in place of a marker anchor, by marker name.
    private var scalarTagTexts: [String: String] = [:]
    /// What every marker name starts with: text that appears nowhere in what is written.
    private let tagMarkerStem: String

    /// The YAML text of `nodes`, laid out as a document, mapping entries or list items.
    static func yaml(of nodes: [ReplacingNode], as layout: Layout, replacedLines: Range<Int>?, sourceLines: [YAMLSourceLine]?) throws -> String {
        var tagMarkerStem = "GraphiteTagMarker"
        while nodes.contains(where: { node in Self.contains(tagMarkerStem, in: node.edited) || (node.original.map { original in Self.contains(tagMarkerStem, in: original) } ?? false) }) {
            tagMarkerStem += "X"
        }
        var writer = RewrittenYAMLWriter(replacedLines: replacedLines, sourceLines: sourceLines, tagMarkerStem: tagMarkerStem + "_")
        let writableNodes = nodes.map { node in writer.writableNode(for: node.edited, replacing: node.original) }
        let rootNode: Node
        switch layout {
        case .document:
            guard let onlyNode = writableNodes.first, writableNodes.count == 1 else { throw GraphiteError.invalidFile("A YAML document has one root.") }
            rootNode = onlyNode
        case .mappingEntries:
            var pairs: [(Node, Node)] = []
            for pairStart in stride(from: 0, to: writableNodes.count - 1, by: 2) { pairs.append((writableNodes[pairStart], writableNodes[pairStart + 1])) }
            rootNode = .mapping(Node.Mapping(pairs))
        case .sequenceItems:
            rootNode = .sequence(Node.Sequence(writableNodes))
        }
        return try writer.text(of: rootNode)
    }

    private init(replacedLines: Range<Int>?, sourceLines: [YAMLSourceLine]?, tagMarkerStem: String) {
        self.replacedLines = replacedLines
        self.sourceLines = sourceLines
        self.tagMarkerStem = tagMarkerStem
    }

    /// Whether `text` appears in a scalar or an anchor name of the tree.
    private static func contains(_ text: String, in node: WrittenYAMLNode) -> Bool {
        if node.anchorName?.contains(text) == true { return true }
        switch node.content {
        case .scalar(let scalarText, _): return scalarText.contains(text)
        case .sequence(let items): return items.contains { item in contains(text, in: item) }
        case .mapping(let entries): return entries.contains { entry in contains(text, in: entry.key) || contains(text, in: entry.value) }
        }
    }

    // MARK: Nodes for the writer

    /// A node for the YAML writer. It has new tag objects, because the writer resolves
    /// implicit tags in place and the editor's own tree must keep them unresolved.
    private mutating func writableNode(for edited: WrittenYAMLNode, replacing original: WrittenYAMLNode?) -> Node {
        var anchor: Anchor?
        if let original, let anchorName = original.anchorName {
            if let definedNode = definedAnchors[anchorName] {
                // Already written with its anchor. A node that means something else by now
                // is written out in full, so the anchor keeps meaning what it meant.
                if edited.hasSameMeaning(as: definedNode) { return .alias(Node.Alias(makeAnchor(named: anchorName))) }
            } else if !original.isAlias || original.line.map({ definitionLine in replacedLines?.contains(definitionLine) == true }) == true {
                // The anchored node itself, or the first alias of one whose own lines are
                // being replaced: the anchor is written here.
                anchor = makeAnchor(named: anchorName)
                definedAnchors[anchorName] = edited
            } else if edited.hasSameMeaning(as: original) {
                return .alias(Node.Alias(makeAnchor(named: anchorName)))
            }
        }
        switch edited.content {
        case .scalar:
            guard case .scalar(let scalar) = edited.node else { return edited.node }
            return writableScalar(scalar, customTagName: edited.customTagName, anchor: anchor)
        case .sequence(let items):
            var originalItems: [WrittenYAMLNode] = []
            if case .sequence(let items)? = original?.content { originalItems = items }
            let pairedItems = Self.pairing(items, with: originalItems)
            var style = Node.Sequence.Style.any
            if case .sequence(let sequence) = edited.node { style = isWrittenInFlowStyle(sequence.mark) ? .flow : sequence.style }
            let writableItems = zip(items, pairedItems).map { item, pairedItem in writableNode(for: item, replacing: pairedItem) }
            return .sequence(Node.Sequence(writableItems, collectionTag(edited.customTagName), style, nil, anchor))
        case .mapping(let entries):
            var unusedOriginalEntries: [(key: WrittenYAMLNode, value: WrittenYAMLNode)] = []
            if case .mapping(let entries)? = original?.content { unusedOriginalEntries = entries }
            var style = Node.Mapping.Style.any
            if case .mapping(let mapping) = edited.node { style = isWrittenInFlowStyle(mapping.mark) ? .flow : mapping.style }
            var pairs: [(Node, Node)] = []
            for entry in entries {
                let originalEntry = unusedOriginalEntries.firstIndex { originalEntry in originalEntry.key.hasSameMeaning(as: entry.key) }
                    .map { entryIndex in unusedOriginalEntries.remove(at: entryIndex) }
                pairs.append((writableNode(for: entry.key, replacing: originalEntry?.key), writableNode(for: entry.value, replacing: originalEntry?.value)))
            }
            return .mapping(Node.Mapping(pairs, collectionTag(edited.customTagName), style, nil, anchor))
        }
    }

    /// The original item each edited item replaces: the one at its place when it means
    /// the same, else an item elsewhere that means the same (a reordered list), else the
    /// one at its place, changed where it is.
    static func pairing(_ editedItems: [WrittenYAMLNode], with originalItems: [WrittenYAMLNode]) -> [WrittenYAMLNode?] {
        var pairedOriginalIndices = [Int?](repeating: nil, count: editedItems.count)
        var unusedOriginalIndices = Set(originalItems.indices)
        for editedIndex in editedItems.indices where unusedOriginalIndices.contains(editedIndex) && editedItems[editedIndex].hasSameMeaning(as: originalItems[editedIndex]) {
            pairedOriginalIndices[editedIndex] = unusedOriginalIndices.remove(editedIndex)
        }
        for editedIndex in editedItems.indices where pairedOriginalIndices[editedIndex] == nil {
            guard let originalIndex = unusedOriginalIndices.sorted().first(where: { originalIndex in editedItems[editedIndex].hasSameMeaning(as: originalItems[originalIndex]) }) else { continue }
            pairedOriginalIndices[editedIndex] = unusedOriginalIndices.remove(originalIndex)
        }
        for editedIndex in editedItems.indices where pairedOriginalIndices[editedIndex] == nil && unusedOriginalIndices.contains(editedIndex) {
            pairedOriginalIndices[editedIndex] = unusedOriginalIndices.remove(editedIndex)
        }
        return pairedOriginalIndices.map { originalIndex in originalIndex.map { originalIndex in originalItems[originalIndex] } }
    }

    private mutating func makeAnchor(named name: String) -> Anchor {
        let anchor = Anchor(rawValue: name)
        anchors.append(anchor)
        return anchor
    }

    private func collectionTag(_ customTagName: String?) -> Tag {
        customTagName.map { tagName in Tag(Tag.Name(rawValue: tagName)) } ?? Tag(.implicit)
    }

    /// Whether the collection read at `mark` is in flow style in the original text. A
    /// node Graphite made has no mark and takes the writer's block style.
    private func isWrittenInFlowStyle(_ mark: Mark?) -> Bool {
        guard let sourceLines, let mark, sourceLines.indices.contains(mark.line - 1) else { return false }
        return WrittenYAMLNode.startsFlowCollection(sourceLines[mark.line - 1], column: mark.column - 1)
    }

    /// The writer never writes a scalar's tag, so each scalar's style is chosen to keep
    /// its type: `!!str 123` is quoted to stay text, and `!!int "7"` is written plain to
    /// stay a number. A tag that no style implies is written through a marker anchor,
    /// which `text(of:)` replaces with the tag.
    private mutating func writableScalar(_ scalar: Node.Scalar, customTagName: String?, anchor: Anchor?) -> Node {
        if let customTagName, let tagText = Self.tagText(customTagName) {
            let markerName = tagMarkerStem + String(scalarTagTexts.count) + "_"
            scalarTagTexts[markerName] = (anchor.map { anchor in "&" + anchor.rawValue + " " } ?? "") + tagText
            return .scalar(Node.Scalar(scalar.string, Tag(.implicit), scalar.style, nil, makeAnchor(named: markerName)))
        }
        let tagName = scalar.tag.rawValue
        let plainTypeName = Resolver.default.resolveTag(of: Node(scalar.string)).rawValue
        let isQuoted = scalar.style != .plain && scalar.style != .any
        var style = scalar.style
        if (tagName == Tag.Name.str.rawValue || tagName == Tag.Name.nonSpecific.rawValue), !isQuoted, plainTypeName != Tag.Name.str.rawValue {
            style = .doubleQuoted
        } else if WrittenYAMLNode.writableTypeNames.contains(tagName), tagName != Tag.Name.str.rawValue, isQuoted, plainTypeName == tagName {
            style = .plain
        }
        return .scalar(Node.Scalar(scalar.string, Tag(.implicit), style, nil, anchor))
    }

    // MARK: Text

    private static let standardTagPrefix = "tag:yaml.org,2002:"
    /// Characters a tag can be written with as it is. Others would need escaping, and
    /// such a tag is left out, which the caller's reading back then notices.
    private static let plainTagCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/~")

    /// A tag as YAML writes it: `!!set` for a standard type, `!custom` for a local tag,
    /// and `!<…>` for any other.
    private static func tagText(_ tagName: String) -> String? {
        let writtenText: String
        let suffix: Substring
        if tagName.hasPrefix(standardTagPrefix) {
            suffix = tagName.dropFirst(standardTagPrefix.count)
            writtenText = "!!" + suffix
        } else if tagName.hasPrefix("!") {
            suffix = tagName.dropFirst()
            writtenText = tagName
        } else {
            suffix = Substring(tagName)
            writtenText = "!<" + tagName + ">"
        }
        guard !suffix.isEmpty, suffix.unicodeScalars.allSatisfy(plainTagCharacters.contains) else { return nil }
        return writtenText
    }

    private func text(of rootNode: Node) throws -> String {
        var output = try withExtendedLifetime(anchors) { try BaseDefinitionEditor.serializedYAML(of: rootNode) }
        for (markerName, tagText) in scalarTagTexts { output = output.replacingOccurrences(of: "&" + markerName, with: tagText) }
        return output
    }
}

/// Rebuilds a document from its original lines, keeping every line of an entry whose
/// meaning did not change and writing only changed entries anew. Block mappings are
/// compared key by key and block lists item by item, so a changed view option replaces
/// one entry, not the view or the file. Any layout it does not recognize returns nil,
/// and the caller writes the whole file instead.
struct YAMLSplicer {
    let sourceLines: [YAMLSourceLine]
    let lineEnding: String
    /// How far the file indents a list under its key (`order:` then `  - name` is 2),
    /// so lists Graphite writes look like the file's own. libyaml writes them at the
    /// key's column.
    let listIndentation: Int

    init(sourceLines: [YAMLSourceLine], lineEnding: String, originalTree: WrittenYAMLNode?) {
        self.sourceLines = sourceLines
        self.lineEnding = lineEnding
        listIndentation = originalTree.flatMap(Self.listIndentation(under:)) ?? 0
    }

    /// The indentation of the first block list written under a key, searched depth first.
    private static func listIndentation(under node: WrittenYAMLNode) -> Int? {
        switch node.content {
        case .scalar:
            return nil
        case .sequence(let items):
            return items.lazy.compactMap(listIndentation(under:)).first
        case .mapping(let entries):
            for entry in entries {
                if case .sequence = entry.value.content, entry.value.isBlockCollection, let keyColumn = entry.key.column, let listColumn = entry.value.column {
                    return max(listColumn - keyColumn, 0)
                }
                if let indentation = listIndentation(under: entry.value) { return indentation }
            }
            return nil
        }
    }

    /// The document: lines before the root mapping as they are, then the mapping.
    func documentLines(original: WrittenYAMLNode, edited: WrittenYAMLNode) -> [String]? {
        guard let firstLine = original.line, let mappingLines = mappingLines(original: original, edited: edited, regionEnd: sourceLines.count) else { return nil }
        return sourceText(0..<firstLine) + mappingLines
    }

    func sourceText(_ lineRange: Range<Int>) -> [String] {
        lineRange.map { lineIndex in String(sourceLines[lineIndex].content) + String(sourceLines[lineIndex].terminator) }
    }

    /// Joins lines, ending any line that lacks a line break (the original last line,
    /// when more follows) with the file's line ending.
    func joined(_ lines: [String]) -> String {
        var text = ""
        for (lineIndex, line) in lines.enumerated() {
            text += line
            // Compared by Unicode scalar: `"\r\n"` is one Character, which is neither "\n" nor "\r".
            if lineIndex < lines.count - 1, line.unicodeScalars.last != "\n", line.unicodeScalars.last != "\r" { text += lineEnding }
        }
        return text
    }

    /// A mapping entry to write, with the entry it replaces in the original text.
    struct RewrittenEntry {
        let key: WrittenYAMLNode
        let value: WrittenYAMLNode
        let original: (key: WrittenYAMLNode, value: WrittenYAMLNode)?
    }

    /// YAML text as lines: the first line after `firstLinePrefix`, the others after
    /// `continuationPrefix`, every line ending with the file's line ending.
    private func lines(ofYAML text: String, firstLinePrefix: String, continuationPrefix: String) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if listIndentation > 0 { lines = Self.indentingListsUnderKeys(lines, by: listIndentation) }
        return lines.enumerated().map { lineIndex, line in
            (line.isEmpty ? "" : (lineIndex == 0 ? firstLinePrefix : continuationPrefix) + line) + lineEnding
        }
    }

    /// List items written as YAML lines.
    /// - Parameter replacedLines: The original lines the items replace, if any.
    func serializedItemLines(of items: [RewrittenYAMLWriter.ReplacingNode], replacedLines: Range<Int>?, firstLinePrefix: String, continuationPrefix: String) -> [String]? {
        guard let text = try? RewrittenYAMLWriter.yaml(of: items, as: .sequenceItems, replacedLines: replacedLines, sourceLines: sourceLines) else { return nil }
        return lines(ofYAML: text, firstLinePrefix: firstLinePrefix, continuationPrefix: continuationPrefix)
    }

    /// Mapping entries written as YAML lines.
    /// - Parameter replacedLines: The original lines the entries replace, if any.
    func serializedEntryLines(of entries: [RewrittenEntry], replacedLines: Range<Int>?, firstLinePrefix: String, continuationPrefix: String) -> [String]? {
        var output: [String] = []
        for (entryIndex, entry) in entries.enumerated() {
            let nodes: [RewrittenYAMLWriter.ReplacingNode] = [(entry.key, entry.original?.key), (entry.value, entry.original?.value)]
            guard let text = try? RewrittenYAMLWriter.yaml(of: nodes, as: .mappingEntries, replacedLines: replacedLines, sourceLines: sourceLines) else { return nil }
            output += lines(ofYAML: text, firstLinePrefix: entryIndex == 0 ? firstLinePrefix : continuationPrefix, continuationPrefix: continuationPrefix)
        }
        return output
    }

    /// libyaml writes a list that is a mapping value at its key's column (`order:` then
    /// `- name`). This moves each such list, with everything nested in it, right by
    /// `indentation` columns. Moving a block node's lines together keeps its meaning;
    /// the content of block scalars (`|`, `>`) is recognized and never read as keys.
    static func indentingListsUnderKeys(_ lines: [String], by indentation: Int) -> [String] {
        var shiftedLines = lines
        let listPrefix = String(repeating: " ", count: indentation)
        var lineIndex = 0
        while lineIndex < shiftedLines.count {
            let line = shiftedLines[lineIndex]
            let lineIndentation = line.prefix { character in character == " " }.count
            if isBlockScalarHeader(line) {
                // Skip the scalar's text: every following line indented more than this one.
                lineIndex += 1
                while lineIndex < shiftedLines.count, shiftedLines[lineIndex].isEmpty || shiftedLines[lineIndex].prefix(while: { character in character == " " }).count > lineIndentation {
                    lineIndex += 1
                }
                continue
            }
            if let keyColumn = keyColumnOfEmptyValue(line), lineIndex + 1 < shiftedLines.count, startsListItem(shiftedLines[lineIndex + 1], atColumn: keyColumn) {
                var blockEnd = lineIndex + 1
                while blockEnd < shiftedLines.count {
                    let blockLine = shiftedLines[blockEnd]
                    let blockIndentation = blockLine.prefix { character in character == " " }.count
                    guard blockLine.isEmpty || blockIndentation > keyColumn || startsListItem(blockLine, atColumn: keyColumn) else { break }
                    blockEnd += 1
                }
                for blockIndex in lineIndex + 1..<blockEnd where !shiftedLines[blockIndex].isEmpty {
                    shiftedLines[blockIndex] = listPrefix + shiftedLines[blockIndex]
                }
            }
            lineIndex += 1
        }
        return shiftedLines
    }

    /// The column where the key starts on a line such as `order:` or `- sort:`, a key
    /// whose value follows on the next lines; nil for any other line.
    private static func keyColumnOfEmptyValue(_ line: String) -> Int? {
        guard line.hasSuffix(":") else { return nil }
        var keyColumn = line.prefix { character in character == " " }.count
        var remainder = line.dropFirst(keyColumn)
        while remainder.hasPrefix("- ") {
            keyColumn += 2
            remainder = remainder.dropFirst(2)
        }
        guard let first = remainder.first, first != "-", first != "\"", first != "'", first != "[", first != "{", first != "?" else { return nil }
        return keyColumn
    }

    private static func startsListItem(_ line: String, atColumn column: Int) -> Bool {
        let indentation = line.prefix { character in character == " " }.count
        let remainder = line.dropFirst(indentation)
        return indentation == column && (remainder == "-" || remainder.hasPrefix("- "))
    }

    /// A line ending in a block scalar indicator, such as `text: |-` or `- >`.
    private static func isBlockScalarHeader(_ line: String) -> Bool {
        guard let lastWord = line.split(separator: " ").last, let indicator = lastWord.first, indicator == "|" || indicator == ">" else { return false }
        return lastWord.dropFirst().allSatisfy { character in character == "-" || character == "+" || character.isNumber }
    }

    /// The text of `line` before `columnCount` Unicode scalars, or nil when it is shorter.
    private func prefix(ofLine line: Int, columnCount: Int) -> String? {
        let scalars = sourceLines[line].content.unicodeScalars
        guard scalars.count >= columnCount else { return nil }
        return String(String.UnicodeScalarView(scalars.prefix(columnCount)))
    }

    /// Blank lines, comment lines and document end markers after an entry's content.
    /// They stay where they are whatever happens to the entry, since they usually
    /// describe what follows.
    private func isTrailingLine(_ line: Int) -> Bool {
        let trimmedContent = sourceLines[line].content.trimmingCharacters(in: .whitespaces)
        return trimmedContent.isEmpty || trimmedContent.hasPrefix("#") || trimmedContent == "..."
    }

    private func contentEnd(start: Int, end: Int) -> Int {
        var contentEnd = end
        while contentEnd > start + 1, isTrailingLine(contentEnd - 1) { contentEnd -= 1 }
        return contentEnd
    }

    /// A block mapping whose first key starts on its first line and whose entries end
    /// before `regionEnd`. The first key may follow a list item's `- ` on that line.
    private func mappingLines(original: WrittenYAMLNode, edited: WrittenYAMLNode, regionEnd: Int) -> [String]? {
        // An alias has the lines of the node it repeats, which are not its own to replace.
        guard original.isBlockCollection, !original.isAlias, case .mapping(let originalEntries) = original.content, case .mapping(let editedEntries) = edited.content,
              let keyColumn = originalEntries.first?.key.column else { return nil }
        var startLines: [Int] = []
        for (entryIndex, entry) in originalEntries.enumerated() {
            guard let line = entry.key.line, entry.key.column == keyColumn, (startLines.last ?? -1) < line, line < regionEnd,
                  let linePrefix = prefix(ofLine: line, columnCount: keyColumn) else { return nil }
            if entryIndex > 0, !linePrefix.allSatisfy({ character in character == " " }) { return nil }
            startLines.append(line)
        }
        guard let firstLinePrefix = prefix(ofLine: startLines[0], columnCount: keyColumn) else { return nil }
        let continuationPrefix = String(repeating: " ", count: keyColumn)

        // Kept keys must stay in their order, and new keys come after them, as the
        // editor's changes leave them; anything else is written whole by the caller.
        var editedIndexByOriginalIndex: [Int: Int] = [:]
        var newEditedIndices: [Int] = []
        var lastOriginalIndex = -1
        for (editedIndex, editedEntry) in editedEntries.enumerated() {
            if let originalIndex = originalEntries.firstIndex(where: { originalEntry in originalEntry.key.hasSameMeaning(as: editedEntry.key) }) {
                guard originalIndex > lastOriginalIndex, newEditedIndices.isEmpty else { return nil }
                lastOriginalIndex = originalIndex
                editedIndexByOriginalIndex[originalIndex] = editedIndex
            } else {
                newEditedIndices.append(editedIndex)
            }
        }

        var output: [String] = []
        for originalIndex in originalEntries.indices {
            let entryStart = startLines[originalIndex]
            let entryEnd = originalIndex + 1 < startLines.count ? startLines[originalIndex + 1] : regionEnd
            let entryContentEnd = contentEnd(start: entryStart, end: entryEnd)
            let linePrefix = originalIndex == 0 ? firstLinePrefix : continuationPrefix
            if let editedIndex = editedIndexByOriginalIndex[originalIndex] {
                let originalEntry = originalEntries[originalIndex]
                let editedEntry = editedEntries[editedIndex]
                if originalEntry.value.hasSameMeaning(as: editedEntry.value) {
                    output += sourceText(entryStart..<entryContentEnd)
                } else if let valueLines = valueLines(original: originalEntry.value, edited: editedEntry.value, keyLine: entryStart, regionEnd: entryContentEnd) {
                    output += sourceText(entryStart..<entryStart + 1) + valueLines
                } else {
                    let rewrittenEntry = RewrittenEntry(key: editedEntry.key, value: editedEntry.value, original: originalEntry)
                    guard let entryLines = serializedEntryLines(of: [rewrittenEntry], replacedLines: entryStart..<entryEnd,
                                                                firstLinePrefix: linePrefix, continuationPrefix: continuationPrefix) else { return nil }
                    output += entryLines
                }
            } else if originalIndex == 0, !firstLinePrefix.allSatisfy({ character in character == " " }) {
                // Removing it would also remove the list item's `- ` on its line.
                return nil
            }
            if originalIndex == originalEntries.count - 1 {
                let newEntries = newEditedIndices.map { editedIndex in RewrittenEntry(key: editedEntries[editedIndex].key, value: editedEntries[editedIndex].value, original: nil) }
                guard let entryLines = serializedEntryLines(of: newEntries, replacedLines: nil, firstLinePrefix: continuationPrefix, continuationPrefix: continuationPrefix) else { return nil }
                output += entryLines
            }
            output += sourceText(entryContentEnd..<entryEnd)
        }
        return output
    }

    /// The lines after a key for a changed block list or mapping whose content starts on a
    /// later line than its key, spliced in turn. The key's line stays, with an anchor or a
    /// tag written on it (`order: &columns`), and so do comment lines between the key and
    /// the value.
    private func valueLines(original: WrittenYAMLNode, edited: WrittenYAMLNode, keyLine: Int, regionEnd: Int) -> [String]? {
        guard original.isBlockCollection, !original.isAlias, let valueLine = original.firstContentLine, valueLine > keyLine, valueLine < regionEnd else { return nil }
        let nestedLines: [String]?
        switch (original.content, edited.content) {
        case (.mapping, .mapping): nestedLines = mappingLines(original: original, edited: edited, regionEnd: regionEnd)
        case (.sequence, .sequence): nestedLines = sequenceLines(original: original, edited: edited, regionEnd: regionEnd)
        default: nestedLines = nil
        }
        return nestedLines.map { lines in sourceText(keyLine + 1..<valueLine) + lines }
    }

    /// A block list whose items each start on their own line after `- `, ending before
    /// `regionEnd`. The editor changes items in place, or inserts or removes one; other
    /// changes (a reordered `order`) rewrite every item at the list's indentation.
    private func sequenceLines(original: WrittenYAMLNode, edited: WrittenYAMLNode, regionEnd: Int) -> [String]? {
        guard original.isBlockCollection, !original.isAlias, case .sequence(let originalItems) = original.content, case .sequence(let editedItems) = edited.content,
              !originalItems.isEmpty else { return nil }
        var itemLines: [Int] = []
        var dashColumn: Int?
        for item in originalItems {
            guard let line = item.line, let column = item.column, (itemLines.last ?? -1) < line, line < regionEnd,
                  let linePrefix = prefix(ofLine: line, columnCount: column), let itemDashColumn = Self.dashColumn(ofItemPrefix: linePrefix),
                  dashColumn == nil || dashColumn == itemDashColumn else { return nil }
            dashColumn = itemDashColumn
            itemLines.append(line)
        }
        guard let dashColumn else { return nil }

        func itemsMatch(_ originalRange: Range<Int>, _ editedRange: Range<Int>) -> Bool {
            originalRange.count == editedRange.count && zip(originalRange, editedRange).allSatisfy { originalIndex, editedIndex in
                originalItems[originalIndex].hasSameMeaning(as: editedItems[editedIndex])
            }
        }
        let comparedCount = min(originalItems.count, editedItems.count)
        let firstDifference = (0..<comparedCount).first { itemIndex in !originalItems[itemIndex].hasSameMeaning(as: editedItems[itemIndex]) } ?? comparedCount
        let itemPrefix = String(repeating: " ", count: dashColumn)
        // The original item each edited item replaces, wherever it was in the list.
        let replacedItems = RewrittenYAMLWriter.pairing(editedItems, with: originalItems)
        var insertedEditedIndex: Int?
        var removedOriginalIndex: Int?
        switch editedItems.count - originalItems.count {
        case 0:
            break
        case 1 where itemsMatch(firstDifference..<originalItems.count, firstDifference + 1..<editedItems.count):
            insertedEditedIndex = firstDifference
        case -1 where itemsMatch(firstDifference + 1..<originalItems.count, firstDifference..<editedItems.count):
            removedOriginalIndex = firstDifference
        default:
            guard let firstItemLine = itemLines.first, let lastItemLine = itemLines.last, !editedItems.isEmpty,
                  let rewrittenLines = serializedItemLines(of: Array(zip(editedItems, replacedItems)), replacedLines: firstItemLine..<regionEnd,
                                                           firstLinePrefix: itemPrefix, continuationPrefix: itemPrefix) else { return nil }
            return rewrittenLines + sourceText(contentEnd(start: lastItemLine, end: regionEnd)..<regionEnd)
        }

        func insertedItemLines() -> [String]? {
            guard let insertedEditedIndex else { return [] }
            return serializedItemLines(of: [(editedItems[insertedEditedIndex], nil)], replacedLines: nil, firstLinePrefix: itemPrefix, continuationPrefix: itemPrefix)
        }
        var output: [String] = []
        for originalIndex in originalItems.indices {
            let itemStart = itemLines[originalIndex]
            let itemEnd = originalIndex + 1 < itemLines.count ? itemLines[originalIndex + 1] : regionEnd
            let itemContentEnd = contentEnd(start: itemStart, end: itemEnd)
            if insertedEditedIndex == originalIndex {
                guard let lines = insertedItemLines() else { return nil }
                output += lines
            }
            if removedOriginalIndex != originalIndex {
                var editedIndex = originalIndex
                if let insertedEditedIndex, originalIndex >= insertedEditedIndex { editedIndex += 1 }
                if let removedOriginalIndex, originalIndex > removedOriginalIndex { editedIndex -= 1 }
                let originalItem = originalItems[originalIndex]
                let editedItem = editedItems[editedIndex]
                if originalItem.hasSameMeaning(as: editedItem) {
                    output += sourceText(itemStart..<itemContentEnd)
                } else if let firstKeyLine = originalItem.firstContentLine, firstKeyLine >= itemStart,
                          let lines = mappingLines(original: originalItem, edited: editedItem, regionEnd: itemContentEnd) {
                    // An item whose keys start under its dash (`- &shared`) keeps that line.
                    output += sourceText(itemStart..<firstKeyLine) + lines
                } else {
                    guard let lines = serializedItemLines(of: [(editedItem, replacedItems[editedIndex])], replacedLines: itemStart..<itemEnd,
                                                          firstLinePrefix: itemPrefix, continuationPrefix: itemPrefix) else { return nil }
                    output += lines
                }
            }
            if originalIndex == originalItems.count - 1, insertedEditedIndex == originalItems.count {
                guard let lines = insertedItemLines() else { return nil }
                output += lines
            }
            output += sourceText(itemContentEnd..<itemEnd)
        }
        return output
    }

    /// The column of `-` in the text before a list item (`  - `), or nil when that text
    /// is anything else.
    private static func dashColumn(ofItemPrefix linePrefix: String) -> Int? {
        let indentation = linePrefix.prefix { character in character == " " }
        let afterIndentation = linePrefix.dropFirst(indentation.count)
        guard afterIndentation.first == "-", afterIndentation.count > 1, afterIndentation.dropFirst().allSatisfy({ character in character == " " }) else { return nil }
        return indentation.count
    }
}
