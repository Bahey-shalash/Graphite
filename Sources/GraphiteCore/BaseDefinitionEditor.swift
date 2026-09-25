import Foundation
import Yams

/// Changes a base's view configuration and writes the YAML back. Edits are made on the
/// parsed YAML tree, so keys Graphite does not know (other view options, plugin
/// settings) are kept with their values. Writing back replaces only the lines of the
/// entries that changed, such as one view's `limit:` line, so comments, indentation,
/// flow style, tags and document markers elsewhere stay exactly as written. When the
/// changed lines cannot be replaced exactly, the whole file is written from the tree;
/// YAML has no comment nodes, so its comments are then lost.
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
        let rootNode: Node?
        do { rootNode = try Yams.compose(yaml: yaml) }
        catch { throw BaseDefinitionError.invalidYAML(String(describing: error)) }
        if let rootNode, YAMLAliasExpansion.exceedsLimits(rootNode, sourceByteCount: yaml.utf8.count) {
            throw BaseDefinitionError.invalidYAML(BaseDefinitionError.aliasesExpandTooFarReason)
        }
        originalText = yaml
        lineEnding = Self.predominantLineEnding(in: yaml)
        let sourceLines = YAMLSourceLine.lines(of: yaml)
        originalTree = rootNode.map { node in WrittenYAMLNode(node, sourceLines: sourceLines) }
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
        let output = try Self.serializedYAML(of: .mapping(rootMapping))
        return lineEnding == "\n" ? output : output.replacingOccurrences(of: "\n", with: lineEnding)
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
            outputLines = splicer.sourceText(0..<sourceLines.count) + (splicer.serializedEntryLines(of: rootMapping, firstLinePrefix: "", continuationPrefix: "") ?? [])
        }
        guard let outputLines else { return nil }
        let splicedText = splicer.joined(outputLines)
        guard let readBack = try? Yams.compose(yaml: splicedText), let readBackMapping = readBack.mapping,
              WrittenYAMLNode(.mapping(readBackMapping), sourceLines: nil).hasSameMeaning(as: editedTree) else { return nil }
        return splicedText
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
            return try Yams.serialize(node: Self.writableNode(node) { text in text }, indent: 2, width: -1, allowUnicode: true)
        }
        let protectedNode = Self.writableNode(node) { text in
            String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in placeholderByScalar[scalar] ?? scalar }))
        }
        let output = try Yams.serialize(node: protectedNode, indent: 2, width: -1, allowUnicode: true)
        let scalarByPlaceholder = Dictionary(uniqueKeysWithValues: placeholderByScalar.map { entry in (entry.value, entry.key) })
        return String(String.UnicodeScalarView(output.unicodeScalars.map { scalar in scalarByPlaceholder[scalar] ?? scalar }))
    }

    /// Unicode's Private Use Area in the Basic Multilingual Plane.
    private static let privateUseRange: ClosedRange<UInt32> = 0xE000...0xF8FF

    private static func visitText(in node: Node, _ visit: (String) -> Void) {
        switch node {
        case .scalar(let scalar): visit(scalar.string)
        case .sequence(let sequence): sequence.forEach { item in visitText(in: item, visit) }
        case .mapping(let mapping): mapping.forEach { pair in visitText(in: pair.key, visit); visitText(in: pair.value, visit) }
        case .alias: break
        }
    }

    /// A copy for the YAML writer. It has new tag objects, because the writer resolves
    /// implicit tags in place and the editor's own tree must keep them unresolved. The
    /// writer never writes tags, so each scalar's style is chosen to keep its type:
    /// `!!str 123` is quoted to stay text, and `!!int "7"` is written plain to stay a
    /// number. Other tags (a plugin's `!custom`) cannot be kept.
    private static func writableNode(_ node: Node, _ transformText: (String) -> String) -> Node {
        switch node {
        case .scalar(let scalar):
            let tagName = scalar.tag.rawValue
            let plainTypeName = Resolver.default.resolveTag(of: Node(scalar.string)).rawValue
            let isQuoted = scalar.style != .plain && scalar.style != .any
            var style = scalar.style
            if (tagName == Tag.Name.str.rawValue || tagName == Tag.Name.nonSpecific.rawValue), !isQuoted, plainTypeName != Tag.Name.str.rawValue {
                style = .doubleQuoted
            } else if WrittenYAMLNode.writableTypeNames.contains(tagName), tagName != Tag.Name.str.rawValue, isQuoted, plainTypeName == tagName {
                style = .plain
            }
            return .scalar(Node.Scalar(transformText(scalar.string), Tag(.implicit), style))
        case .sequence(let sequence):
            return .sequence(Node.Sequence(sequence.map { item in writableNode(item, transformText) }, Tag(.implicit), sequence.style))
        case .mapping(let mapping):
            return .mapping(Node.Mapping(mapping.map { pair in (writableNode(pair.key, transformText), writableNode(pair.value, transformText)) }, Tag(.implicit), mapping.style))
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

    /// Keeps each property's existing spelling (`status` stays `status`), and writes new
    /// ones with their prefix as Obsidian does (`note.status`).
    public mutating func setOrder(_ order: [BasePropertyIdentifier], forViewAt viewIndex: Int) throws {
        try updateView(at: viewIndex) { viewMapping in
            let existingSpellings = (viewMapping["order"]?.sequence ?? []).compactMap { node in node.scalar?.string }
            var spellingByProperty: [BasePropertyIdentifier: String] = [:]
            for spelling in existingSpellings { spellingByProperty[BasePropertyIdentifier(spelling)] = spelling }
            viewMapping["order"] = order.isEmpty ? nil : .sequence(Node.Sequence(order.map { property in Self.textNode(spellingByProperty[property] ?? property.rawValue) }))
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
/// and where it starts in the original text. It is taken before anything asks Yams for
/// a resolved tag, because Yams resolves implicit tags in place on objects that copies
/// of the tree share.
struct WrittenYAMLNode {
    enum Content {
        case scalar(text: String, typeName: String)
        case sequence([WrittenYAMLNode])
        case mapping([(key: WrittenYAMLNode, value: WrittenYAMLNode)])
    }

    /// Tags whose type survives writing, through the scalar's style.
    static let writableTypeNames = Set([Tag.Name.str, .int, .float, .bool, .null, .timestamp].map(\.rawValue))

    let node: Node
    let content: Content
    /// Zero-based line and column (in Unicode scalars, as libyaml counts) where the
    /// node starts in the original text; nil for an edited tree. An alias has the
    /// position of the node it repeats.
    let line: Int?
    let column: Int?
    /// A block-style list or mapping; flow collections are only ever replaced whole.
    let isBlockCollection: Bool

    init(_ node: Node, sourceLines: [YAMLSourceLine]?) {
        self.node = node
        var firstCharacter: Unicode.Scalar?
        if let sourceLines, let mark = node.mark, sourceLines.indices.contains(mark.line - 1) {
            line = mark.line - 1
            column = mark.column - 1
            firstCharacter = sourceLines[mark.line - 1].content.unicodeScalars.dropFirst(mark.column - 1).first
        } else {
            line = nil
            column = nil
        }
        switch node {
        case .scalar(let scalar):
            content = .scalar(text: scalar.string, typeName: Self.typeName(of: scalar))
            isBlockCollection = false
        case .sequence(let sequence):
            content = .sequence(sequence.map { item in WrittenYAMLNode(item, sourceLines: sourceLines) })
            isBlockCollection = firstCharacter == "-"
        case .mapping(let mapping):
            content = .mapping(mapping.map { pair in (key: WrittenYAMLNode(pair.key, sourceLines: sourceLines), value: WrittenYAMLNode(pair.value, sourceLines: sourceLines)) })
            isBlockCollection = !mapping.isEmpty && firstCharacter != nil && firstCharacter != "{" && firstCharacter != "["
        case .alias:
            content = .scalar(text: "", typeName: Tag.Name.null.rawValue)
            isBlockCollection = false
        }
    }

    /// The type a reader gives the scalar once it is written: an explicit core tag,
    /// `str` for quoted text, and otherwise what the plain text resolves to. Other tags
    /// are dropped by the writer, so they do not count.
    private static func typeName(of scalar: Node.Scalar) -> String {
        let tagName = scalar.tag.rawValue
        if writableTypeNames.contains(tagName) { return tagName }
        if tagName == Tag.Name.nonSpecific.rawValue || (scalar.style != .plain && scalar.style != .any) { return Tag.Name.str.rawValue }
        return Resolver.default.resolveTag(of: Node(scalar.string)).rawValue
    }

    func hasSameMeaning(as other: WrittenYAMLNode) -> Bool {
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

    /// `node` written as YAML: the first line after `firstLinePrefix`, the others after
    /// `continuationPrefix`, every line ending with the file's line ending.
    func serializedLines(of node: Node, firstLinePrefix: String, continuationPrefix: String) -> [String]? {
        guard let text = try? BaseDefinitionEditor.serializedYAML(of: node) else { return nil }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if listIndentation > 0 { lines = Self.indentingListsUnderKeys(lines, by: listIndentation) }
        return lines.enumerated().map { lineIndex, line in
            (line.isEmpty ? "" : (lineIndex == 0 ? firstLinePrefix : continuationPrefix) + line) + lineEnding
        }
    }

    /// Mapping entries written as YAML like `serializedLines`.
    func serializedEntryLines(of mapping: Node.Mapping, firstLinePrefix: String, continuationPrefix: String) -> [String]? {
        var output: [String] = []
        for (entryIndex, pair) in mapping.enumerated() {
            guard let entryLines = serializedLines(of: .mapping(Node.Mapping([pair])), firstLinePrefix: entryIndex == 0 ? firstLinePrefix : continuationPrefix, continuationPrefix: continuationPrefix) else { return nil }
            output += entryLines
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
        guard original.isBlockCollection, case .mapping(let originalEntries) = original.content, case .mapping(let editedEntries) = edited.content,
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
                    let entryMapping = Node.Mapping([(editedEntry.key.node, editedEntry.value.node)])
                    guard let entryLines = serializedEntryLines(of: entryMapping, firstLinePrefix: linePrefix, continuationPrefix: continuationPrefix) else { return nil }
                    output += entryLines
                }
            } else if originalIndex == 0, !firstLinePrefix.allSatisfy({ character in character == " " }) {
                // Removing it would also remove the list item's `- ` on its line.
                return nil
            }
            if originalIndex == originalEntries.count - 1 {
                let newEntries = Node.Mapping(newEditedIndices.map { editedIndex in (editedEntries[editedIndex].key.node, editedEntries[editedIndex].value.node) })
                guard let entryLines = serializedEntryLines(of: newEntries, firstLinePrefix: continuationPrefix, continuationPrefix: continuationPrefix) else { return nil }
                output += entryLines
            }
            output += sourceText(entryContentEnd..<entryEnd)
        }
        return output
    }

    /// The lines after a key for a changed block list or mapping that starts on a later
    /// line than its key, spliced in turn. Comment lines between the key and the value
    /// stay.
    private func valueLines(original: WrittenYAMLNode, edited: WrittenYAMLNode, keyLine: Int, regionEnd: Int) -> [String]? {
        guard original.isBlockCollection, let valueLine = original.line, valueLine > keyLine, valueLine < regionEnd else { return nil }
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
        guard original.isBlockCollection, case .sequence(let originalItems) = original.content, case .sequence(let editedItems) = edited.content,
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
            guard let lastItemLine = itemLines.last, !editedItems.isEmpty,
                  let rewrittenLines = serializedLines(of: .sequence(Node.Sequence(editedItems.map(\.node))), firstLinePrefix: itemPrefix, continuationPrefix: itemPrefix) else { return nil }
            return rewrittenLines + sourceText(contentEnd(start: lastItemLine, end: regionEnd)..<regionEnd)
        }

        func insertedItemLines() -> [String]? {
            guard let insertedEditedIndex else { return [] }
            return serializedLines(of: .sequence(Node.Sequence([editedItems[insertedEditedIndex].node])), firstLinePrefix: itemPrefix, continuationPrefix: itemPrefix)
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
                } else if let lines = mappingLines(original: originalItem, edited: editedItem, regionEnd: itemContentEnd) {
                    output += lines
                } else {
                    guard let lines = serializedLines(of: .sequence(Node.Sequence([editedItem.node])), firstLinePrefix: itemPrefix, continuationPrefix: itemPrefix) else { return nil }
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
