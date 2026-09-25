import Foundation
import Yams

/// Obsidian's property types, spelled as `.obsidian/types.json` stores them.
public enum PropertyType: String, CaseIterable, Codable, Sendable, Identifiable {
    case text, multitext, number, checkbox, date, datetime, tags, aliases
    public var id: String { rawValue }
}

/// One frontmatter value, interpreted the way Obsidian's Properties view does.
public enum PropertyValue: Equatable, Hashable, Sendable {
    case empty
    case text(String)
    case list([String])
    case number(Double)
    case checkbox(Bool)
    /// As written, for example `2026-09-23`.
    case date(String)
    /// As written, for example `2026-09-23T14:30`.
    case dateTime(String)
    /// Nested YAML Graphite does not edit; kept verbatim so saving never loses it.
    case unsupported(String)

    public var displayText: String {
        switch self {
        case .empty: ""
        case .text(let text): text
        case .list(let items): items.joined(separator: ", ")
        case .number(let number): NoteProperties.formatted(number)
        case .checkbox(let isChecked): isChecked ? "true" : "false"
        case .date(let date), .dateTime(let date): date
        case .unsupported(let yaml): yaml
        }
    }
}

public struct NoteProperty: Equatable, Hashable, Sendable, Identifiable {
    public var key: String
    public var value: PropertyValue
    public var id: String { key }
    public init(key: String, value: PropertyValue) {
        self.key = key
        self.value = value
    }
}

public enum NoteProperties {
    /// Properties in written order, or nil when the YAML is not a key/value mapping
    /// (Obsidian then shows the frontmatter as invalid and leaves it alone). Frontmatter
    /// holding only comments has no properties.
    public static func parse(_ yaml: String, declaredTypes: [String: PropertyType] = [:]) -> [NoteProperty]? {
        guard let entries = mappingEntries(ofYAML: yaml) else { return nil }
        return entries.compactMap { entry in
            guard let key = entry.key.string else { return nil }
            return NoteProperty(key: key, value: value(of: entry.value, declaredType: declaredTypes[key] ?? defaultType(forKey: key)))
        }
    }

    /// The YAML body in Obsidian's own style: block lists, minimal quoting.
    public static func serialize(_ properties: [NoteProperty], lineEnding: String = "\n") -> String {
        properties.flatMap(serializedLines).map { line in line + lineEnding }.joined()
    }

    /// Replaces (or adds, or removes when empty) the frontmatter's properties and leaves
    /// the rest of the note byte-for-byte unchanged.
    ///
    /// Only properties whose value differs from the note's are written anew. Every other
    /// property keeps its exact YAML: comments, quoting, the spelling of numbers (`007`,
    /// `1.10`, IDs longer than a Double holds), anchors, explicit tags, and nested items
    /// Graphite cannot edit. `declaredTypes` must be the types `properties` were parsed
    /// with, so that an unchanged value is recognized as unchanged.
    public static func replacingFrontmatter(in source: String, with properties: [NoteProperty], declaredTypes: [String: PropertyType] = [:]) -> String {
        let sourceText = source as NSString
        guard let frontmatter = FrontmatterRegion(in: sourceText) else {
            guard !properties.isEmpty else { return source }
            let lineEnding = firstLineEnding(in: source) ?? "\n"
            return "---" + lineEnding + serialize(properties, lineEnding: lineEnding) + "---" + lineEnding + source
        }
        let body = sourceText.substring(from: frontmatter.length)
        let yaml = sourceText.substring(with: frontmatter.yamlRange)
        if let splicedYAML = splicedYAML(yaml, with: properties, declaredTypes: declaredTypes, lineEnding: frontmatter.lineEnding) {
            // Entries Graphite cannot name (`? [a, b]`) keep the frontmatter alive.
            guard !properties.isEmpty || mappingEntries(ofYAML: splicedYAML)?.isEmpty == false else { return body }
            return sourceText.replacingCharacters(in: frontmatter.yamlRange, with: splicedYAML)
        }
        // Rewriting every property loses comments and most original spellings, so it is only
        // the fallback for YAML whose lines cannot be matched to its entries, such as a flow mapping.
        guard !properties.isEmpty else { return body }
        let rewrittenYAML = rewrittenYAML(properties, keepingNumberSpellingsOf: yaml, declaredTypes: declaredTypes, lineEnding: frontmatter.lineEnding)
        return "---" + frontmatter.lineEnding + rewrittenYAML + "---" + frontmatter.lineEnding + body
    }

    /// Every property written anew, except that a number the edit left unchanged keeps its
    /// written spelling (`007`, `1.10`, an ID longer than a Double holds) instead of the
    /// number it reads as.
    private static func rewrittenYAML(_ properties: [NoteProperty], keepingNumberSpellingsOf yaml: String, declaredTypes: [String: PropertyType], lineEnding: String) -> String {
        var writtenNumbers: [String: (value: PropertyValue, spelling: String)] = [:]
        for entry in mappingEntries(ofYAML: yaml) ?? [] {
            guard let key = entry.key.string, writtenNumbers[key] == nil, case .scalar(let scalar) = entry.value, scalar.style == .plain else { continue }
            let originalValue = value(of: entry.value, declaredType: declaredTypes[key] ?? defaultType(forKey: key))
            guard case .number = originalValue else { continue }
            writtenNumbers[key] = (originalValue, scalar.string)
        }
        let lines = properties.flatMap { property -> [String] in
            guard let writtenNumber = writtenNumbers[property.key], isSameValue(property.value, writtenNumber.value) else { return serializedLines(of: property) }
            return ["\(quotedIfNeeded(property.key)): \(writtenNumber.spelling)"]
        }
        return lines.map { line in line + lineEnding }.joined()
    }

    static func formatted(_ number: Double) -> String {
        // YAML's own spellings, so the value reads back as a number rather than the text `inf`.
        if number.isNaN { return ".nan" }
        if number.isInfinite { return number < 0 ? "-.inf" : ".inf" }
        // Whole numbers never get `.0` or an exponent, which `String(Double)` writes from 1e16 on.
        if number.rounded() == number {
            if let wholeNumber = Int64(exactly: number) { return String(wholeNumber) }
            return String(format: "%.0f", number)
        }
        return String(number)
    }

    /// The type Obsidian gives a property by its name alone, such as `tags`.
    public static func defaultType(forKey key: String) -> PropertyType? {
        switch key {
        case "tags", "tag": .tags
        case "aliases", "alias": .aliases
        case "cssclasses": .multitext
        default: nil
        }
    }

    // MARK: Reading values

    /// The root mapping's entries, an empty list for empty or comment-only YAML, or nil
    /// when the YAML is invalid or not a mapping.
    private static func mappingEntries(ofYAML yaml: String) -> [(key: Node, value: Node)]? {
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard !YAMLNesting.exceedsSafeDepth(yaml), !YAMLAliasExpansion.exceedsAnchorCount(yaml) else { return nil }
        let rootNode: Node?
        do { rootNode = try Yams.compose(yaml: yaml) } catch { return nil }
        // Yams composes no document at all from YAML that holds only comments.
        guard let rootNode else { return [] }
        guard !YAMLAliasExpansion.exceedsLimits(rootNode, sourceByteCount: yaml.utf8.count), let mapping = rootNode.mapping else { return nil }
        return mapping.map { keyNode, valueNode in (key: keyNode, value: valueNode) }
    }

    private static func value(of node: Node, declaredType: PropertyType?) -> PropertyValue {
        switch node {
        case .sequence(let sequence):
            // A list holding mappings or lists cannot be shown as text items; it is kept as
            // YAML so that writing it back never drops those items.
            guard sequence.allSatisfy({ itemNode in itemNode.scalar != nil }) else { return unsupportedValue(of: node) }
            return .list(sequence.compactMap { itemNode in itemNode.scalar?.string })
        case .scalar(let scalar):
            return value(ofScalar: scalar, declaredType: declaredType)
        case .mapping, .alias:
            return unsupportedValue(of: node)
        }
    }

    private static func unsupportedValue(of node: Node) -> PropertyValue {
        .unsupported((try? Yams.serialize(node: node).trimmingCharacters(in: .newlines)) ?? "")
    }

    /// The type Obsidian gives a property across the vault: the one assigned in
    /// `types.json`, else the one its name implies (`tags`), else the one its first
    /// non-empty value suggests, else text.
    public static func type(ofKey key: String, sampleValues: [BaseFrontmatterNode], declaredTypes: [String: PropertyType]) -> PropertyType {
        if let declaredType = declaredTypes[key] ?? declaredTypes.first(where: { entry in entry.key.caseInsensitiveCompare(key) == .orderedSame })?.value {
            return declaredType
        }
        if let typeByName = defaultType(forKey: key.lowercased()) { return typeByName }
        for sampleValue in sampleValues {
            switch sampleValue {
            case .sequence: return .multitext
            case .mapping: continue
            case .scalar(let text, let isPlain):
                switch value(ofScalarText: text, isPlain: isPlain, declaredType: nil) {
                case .empty, .unsupported: continue
                case .text, .list: return .text
                case .number: return .number
                case .checkbox: return .checkbox
                case .date: return .date
                case .dateTime: return .datetime
                }
            }
        }
        return .text
    }

    private static func value(ofScalar scalar: Node.Scalar, declaredType: PropertyType?) -> PropertyValue {
        value(ofScalarText: scalar.string, isPlain: isReadByValue(scalar), declaredType: declaredType)
    }

    /// Whether the scalar's type comes from its text, as for an unquoted value. An explicit
    /// tag decides instead, as `BaseFrontmatter` reads it: `!!str 007` is the text `007`
    /// (and is written back quoted), and `!!int "7"` is a number. Quoted scalars carry the
    /// `str` tag. Yams resolves an implicit tag in place when a node is compared, hashed or
    /// written, so this reads the tag before any of those.
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

    private static func value(ofScalarText text: String, isPlain: Bool, declaredType: PropertyType?) -> PropertyValue {
        if isPlain && ["", "~", "null", "Null", "NULL"].contains(text) {
            return declaredType == .multitext || declaredType == .tags || declaredType == .aliases ? .list([]) : .empty
        }
        switch declaredType {
        case .text: return .text(text)
        // Obsidian reads `tags: fiction, classic` as two tags, as the index does.
        case .tags: return .list(tagNames(inText: text))
        case .multitext, .aliases: return .list([text])
        case .number: return (coreSchemaNumber(text) ?? Double(text)).map(PropertyValue.number) ?? .text(text)
        case .checkbox: return .checkbox(text.lowercased() == "true")
        case .date: return .date(text)
        case .datetime: return .dateTime(text)
        case nil: break
        }
        // Quoted values are text (or a date written in quotes); plain ones follow the
        // YAML 1.2 core schema, which is what Obsidian's parser uses.
        if !isPlain { return looksLikeDate(text) ? dateValue(text) : .text(text) }
        if ["true", "True", "TRUE"].contains(text) { return .checkbox(true) }
        if ["false", "False", "FALSE"].contains(text) { return .checkbox(false) }
        if let number = coreSchemaNumber(text) { return .number(number) }
        if looksLikeDate(text) { return dateValue(text) }
        return .text(text)
    }

    /// The tags a text `tags` value names: `fiction, classic` and `fiction classic` are two.
    static func tagNames(inText text: String) -> [String] {
        text.split(whereSeparator: { character in character == "," || character.isWhitespace }).map(String.init)
    }

    /// A number spelled as the YAML 1.2 core schema spells one, including `.inf` and `.nan`.
    private static func coreSchemaNumber(_ text: String) -> Double? {
        switch text {
        case ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF": return .infinity
        case "-.inf", "-.Inf", "-.INF": return -.infinity
        case ".nan", ".NaN", ".NAN": return .nan
        default:
            guard text.range(of: "^[-+]?(\\.[0-9]+|[0-9]+(\\.[0-9]*)?)([eE][-+]?[0-9]+)?$", options: .regularExpression) != nil else { return nil }
            return Double(text)
        }
    }

    private static func looksLikeDate(_ text: String) -> Bool {
        text.range(of: "^\\d{4}-\\d{2}-\\d{2}([T ]\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?)?$", options: .regularExpression) != nil
    }

    private static func dateValue(_ text: String) -> PropertyValue {
        text.count > 10 ? .dateTime(text) : .date(text)
    }

    /// Equality that also treats two `.nan` numbers as the same value, so a `.nan` property
    /// counts as unchanged.
    private static func isSameValue(_ leftValue: PropertyValue, _ rightValue: PropertyValue) -> Bool {
        if case .number(let leftNumber) = leftValue, case .number(let rightNumber) = rightValue, leftNumber.isNaN, rightNumber.isNaN { return true }
        return leftValue == rightValue
    }

    // MARK: Writing values

    private static func serializedLines(of property: NoteProperty) -> [String] {
        let key = quotedIfNeeded(property.key)
        switch property.value {
        case .empty:
            return ["\(key):"]
        case .text(let text):
            return ["\(key): \(quotedIfNeeded(text))"]
        case .list(let items):
            if items.isEmpty { return ["\(key): []"] }
            return ["\(key):"] + items.map { item in "  - \(quotedIfNeeded(item))" }
        case .number(let number):
            return ["\(key): \(formatted(number))"]
        case .checkbox(let isChecked):
            return ["\(key): \(isChecked ? "true" : "false")"]
        case .date(let date), .dateTime(let date):
            // Plain, as Obsidian writes dates, only when it reads back as a date: other text
            // in a date property, such as `TBD: later`, needs quotes to stay valid YAML.
            return ["\(key): \(looksLikeDate(date) ? date : quotedIfNeeded(date))"]
        case .unsupported(let yaml):
            return ["\(key):"] + yaml.split(separator: "\n", omittingEmptySubsequences: false).map { line in "  " + line }
        }
    }

    /// Quotes only when plain YAML would change the meaning, as Obsidian does.
    static func quotedIfNeeded(_ text: String) -> String {
        guard needsQuotes(text) else { return text }
        var quoted = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": quoted += "\\\\"
            case "\"": quoted += "\\\""
            case "\n": quoted += "\\n"
            case "\r": quoted += "\\r"
            case "\t": quoted += "\\t"
            default:
                if mustBeEscaped(scalar) { quoted += String(format: "\\u%04X", scalar.value) } else { quoted.unicodeScalars.append(scalar) }
            }
        }
        return quoted + "\""
    }

    private static func needsQuotes(_ text: String) -> Bool {
        guard let firstScalar = text.unicodeScalars.first, let lastScalar = text.unicodeScalars.last else { return true }
        if CharacterSet.whitespaces.contains(firstScalar) || CharacterSet.whitespaces.contains(lastScalar) { return true }
        if "-?:,[]{}#&*!|>'\"%@`".unicodeScalars.contains(firstScalar) || text.hasSuffix(":") { return true }
        if ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(text.lowercased()) { return true }
        if Double(text) != nil || coreSchemaNumber(text) != nil || looksLikeDate(text) { return true }
        var previousScalar: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            // `#` after a space or tab starts a comment, and `:` before a space or tab ends a key.
            if scalar == "#", previousScalar == " " || previousScalar == "\t" { return true }
            if scalar == " " || scalar == "\t", previousScalar == ":" { return true }
            if mustBeEscaped(scalar) { return true }
            previousScalar = scalar
        }
        return false
    }

    /// Characters a plain YAML scalar cannot hold: control characters (tab aside), and
    /// the line breaks libyaml recognizes beyond LF (CR, NEL, LS, PS). A leading byte
    /// order mark would also be dropped by the reader.
    private static func mustBeEscaped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x08, 0x0A...0x1F, 0x7F...0x9F, 0x2028, 0x2029, 0xFEFF, 0xFFFE, 0xFFFF: true
        default: false
        }
    }

    // MARK: Rewriting only what changed

    /// `yaml` with each changed property's lines replaced, each removed property's lines
    /// dropped, and new properties appended, or nil when the entries cannot be matched to
    /// their lines or the result would not read back as `properties`.
    private static func splicedYAML(_ yaml: String, with properties: [NoteProperty], declaredTypes: [String: PropertyType], lineEnding: String) -> String? {
        guard let entries = mappingEntries(ofYAML: yaml) else { return nil }
        let lines = yamlLines(of: yaml)
        var entryStartLineIndices: [Int] = []
        for entry in entries {
            guard let keyLine = entry.key.mark?.line, keyLine - 1 < lines.count, keyLine - 1 > (entryStartLineIndices.last ?? -1) else { return nil }
            // In a block mapping at the left margin every entry starts its line. Flow mappings
            // (`{a: 1}`) and indented roots are left to the full rewrite.
            guard let firstScalar = lines[keyLine - 1].unicodeScalars.first, !CharacterSet.whitespacesAndNewlines.contains(firstScalar), firstScalar != "{" else { return nil }
            entryStartLineIndices.append(keyLine - 1)
        }
        var newPropertiesByKey: [String: NoteProperty] = [:]
        for property in properties {
            guard newPropertiesByKey.updateValue(property, forKey: property.key) == nil else { return nil }
        }
        let originalKeys = entries.compactMap { entry in entry.key.string }
        let originalKeySet = Set(originalKeys)
        // Kept properties must keep their order; appending new ones is the only reordering.
        guard properties.map(\.key).filter(originalKeySet.contains) == originalKeys.filter({ key in newPropertiesByKey[key] != nil }) else { return nil }

        // Callers read the YAML without its last line break, and a block scalar at the end
        // (`desc: >`) then has no final newline, so either reading counts as unchanged.
        let valuesWithoutLastLineBreak = Dictionary(
            (parse(textWithoutLastLineBreak(yaml), declaredTypes: declaredTypes) ?? []).map { property in (property.key, property.value) },
            uniquingKeysWith: { firstValue, _ in firstValue })

        var splicedLines = Array(lines[0..<(entryStartLineIndices.first ?? lines.count)])
        var unchangedOriginalValues: [String: PropertyValue] = [:]
        for (entryPosition, entry) in entries.enumerated() {
            let entryEnd = entryPosition + 1 < entryStartLineIndices.count ? entryStartLineIndices[entryPosition + 1] : lines.count
            let entryLines = entryStartLineIndices[entryPosition]..<entryEnd
            guard let key = entry.key.string else {
                splicedLines += lines[entryLines]
                continue
            }
            guard let property = newPropertiesByKey[key] else {
                // Comment lines after a removed value may describe the next property.
                splicedLines += lines[valueLinesEnd(of: entryLines, in: lines, entry: entry)..<entryLines.upperBound]
                continue
            }
            let originalValue = value(of: entry.value, declaredType: declaredTypes[key] ?? defaultType(forKey: key))
            if isSameValue(property.value, originalValue) || valuesWithoutLastLineBreak[key].map({ value in isSameValue(property.value, value) }) == true {
                unchangedOriginalValues[key] = originalValue
                splicedLines += lines[entryLines]
                continue
            }
            let valueEnd = valueLinesEnd(of: entryLines, in: lines, entry: entry)
            var replacementLines = serializedLines(of: property)
            if valueEnd - entryLines.lowerBound == 1, replacementLines.count == 1,
               let comment = trailingComment(of: lineContent(lines[entryLines.lowerBound]), entry: entry) {
                replacementLines[0] += " " + comment
            }
            splicedLines += replacementLines.map { line in line + lineEnding }
            splicedLines += lines[valueEnd..<entryLines.upperBound]
        }
        let addedProperties = properties.filter { property in !originalKeySet.contains(property.key) }
        if !addedProperties.isEmpty, let lastLine = splicedLines.last, lineContent(lastLine) == lastLine {
            splicedLines[splicedLines.count - 1] += lineEnding
        }
        splicedLines += addedProperties.flatMap(serializedLines).map { line in line + lineEnding }
        let splicedText = splicedLines.joined()

        // Anything that would not read back exactly (an anchor that moved away from its
        // aliases, for example) makes the caller fall back to rewriting every property.
        guard let splicedEntries = mappingEntries(ofYAML: splicedText),
              splicedEntries.count - splicedEntries.filter({ entry in entry.key.string != nil }).count == entries.count - originalKeys.count,
              let reparsedProperties = parse(splicedText, declaredTypes: declaredTypes), reparsedProperties.count == properties.count else { return nil }
        let reparsedValues = Dictionary(reparsedProperties.map { property in (property.key, property.value) }, uniquingKeysWith: { firstValue, _ in firstValue })
        for property in properties {
            let expectedValue = unchangedOriginalValues[property.key] ?? parse(serialize([property]), declaredTypes: declaredTypes)?.first?.value
            guard let reparsedValue = reparsedValues[property.key], let expectedValue, isSameValue(reparsedValue, expectedValue) else { return nil }
        }
        return splicedText
    }

    /// The end of the lines that hold an entry's value. Comment and blank lines after the
    /// value are layout rather than value and survive when the value is rewritten or removed.
    private static func valueLinesEnd(of entryLines: Range<Int>, in lines: [String], entry: (key: Node, value: Node)) -> Int {
        var end = entryLines.upperBound
        while end > entryLines.lowerBound + 1 && isCommentOrBlank(lines[end - 1]) { end -= 1 }
        guard end < entryLines.upperBound else { return end }
        // A line that looks like a comment can still be value text, such as `#b"` closing a
        // quoted scalar, and blank lines can belong to a `|+` block scalar: the lines stay
        // with the value unless the entry reads the same without them.
        guard let entriesWithoutLayout = mappingEntries(ofYAML: lines[entryLines.lowerBound..<end].joined()),
              entriesWithoutLayout.count == 1, entriesWithoutLayout[0].key == entry.key, entriesWithoutLayout[0].value == entry.value else { return entryLines.upperBound }
        return end
    }

    /// The comment after a one-line entry (`status: todo # keep me`): the first ` #` whose
    /// removal leaves the entry reading the same, so a `#` inside quotes is never taken for one.
    private static func trailingComment(of line: String, entry: (key: Node, value: Node)) -> String? {
        let scalars = Array(line.unicodeScalars)
        for index in scalars.indices.dropFirst() where scalars[index] == "#" && (scalars[index - 1] == " " || scalars[index - 1] == "\t") {
            var entryText = String.UnicodeScalarView()
            entryText.append(contentsOf: scalars[..<index])
            guard let entries = mappingEntries(ofYAML: String(entryText)), entries.count == 1,
                  entries[0].key == entry.key, entries[0].value == entry.value else { continue }
            var comment = String.UnicodeScalarView()
            comment.append(contentsOf: scalars[index...])
            return String(comment)
        }
        return nil
    }

    private static func isCommentOrBlank(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLine.isEmpty || trimmedLine.hasPrefix("#")
    }

    /// The lines of `yaml`, each with its own line break, split wherever libyaml starts a
    /// new line (LF, CR LF, CR, NEL, LS, PS) so that Yams' line marks index this array.
    private static func yamlLines(of yaml: String) -> [String] {
        let scalars = Array(yaml.unicodeScalars)
        var lines: [String] = []
        var line = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            line.append(scalar)
            index += 1
            if scalar == "\r", index < scalars.count, scalars[index] == "\n" {
                line.append(scalars[index])
                index += 1
            }
            if isYAMLLineBreak(scalar) {
                lines.append(String(line))
                line = String.UnicodeScalarView()
            }
        }
        if !line.isEmpty { lines.append(String(line)) }
        return lines
    }

    private static func isYAMLLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"].contains(scalar)
    }

    private static func lineContent(_ line: String) -> String {
        var content = line.unicodeScalars
        while let lastScalar = content.last, isYAMLLineBreak(lastScalar) { content.removeLast() }
        return String(content)
    }

    private static func textWithoutLastLineBreak(_ text: String) -> String {
        var scalars = text.unicodeScalars
        if scalars.last == "\n" { scalars.removeLast() }
        if scalars.last == "\r" { scalars.removeLast() }
        return String(scalars)
    }

    /// The first line ending in `text`, which a new frontmatter block follows.
    private static func firstLineEnding(in text: String) -> String? {
        guard let lineFeedIndex = text.utf16.firstIndex(of: 0x0A) else { return nil }
        guard lineFeedIndex != text.utf16.startIndex else { return "\n" }
        return text.utf16[text.utf16.index(before: lineFeedIndex)] == 0x0D ? "\r\n" : "\n"
    }
}

/// Where a note's frontmatter block is, matched the way `FrontmatterLocator` matches it.
private struct FrontmatterRegion {
    private static let pattern = try? NSRegularExpression(pattern: "\\A---(\\r?\\n)((?:[\\s\\S]*?\\r?\\n)?)(?:---|\\.\\.\\.)[ \\t]*(?:\\r?\\n|$)")

    /// The line ending of the opening `---` line, which rewritten property lines use, so a
    /// single CR LF line in the body does not change the frontmatter's line endings.
    let lineEnding: String
    /// The YAML between the delimiter lines: whole lines, each with its line break.
    let yamlRange: NSRange
    /// The whole block, delimiter lines included.
    let length: Int

    init?(in sourceText: NSString) {
        guard let match = Self.pattern?.firstMatch(in: sourceText as String, range: NSRange(location: 0, length: sourceText.length)) else { return nil }
        lineEnding = sourceText.substring(with: match.range(at: 1))
        yamlRange = match.range(at: 2)
        length = match.range.length
    }
}
