import Foundation

/// The options a diagram's front matter gives its type under `config:`, as Mermaid reads them from block YAML with
/// the JSON schema (`config:`, then `sankey:`, then `showValues: false`, each level indented more): each option's
/// value, a Boolean (`true`, `false`), a number, text (plain or quoted), or a collection (an option followed by a
/// more indented mapping or list, or written in braces or brackets), whose content is not read. Comment lines and
/// blank lines are skipped. Directives (`%%{init: …}%%`) are not read.
struct MermaidFrontMatterOptions {
    enum Value: Equatable {
        case boolean(Bool)
        case number(Double)
        case text(String)
        case collection
    }

    private(set) var values: [String: Value] = [:]

    /// The options under `config:` and then `section:` in the front matter at the start of `bytes`; none without one.
    init(section: String, in bytes: [UInt8]) {
        var keys: [(indent: Int, key: String)] = []
        for line in Self.frontMatterLines(of: bytes) {
            let indent = line.prefix { character in character == " " }.count
            let content = line.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty, !content.hasPrefix("#"), let (key, written) = Self.keyAndValue(content) else { continue }
            while let last = keys.last, last.indent >= indent { keys.removeLast() }
            let isOption = keys.map(\.key) == ["config", section]
            if written.isEmpty {
                if isOption { values[key] = .collection }
                keys.append((indent, key))
            } else if isOption {
                values[key] = Self.value(written)
            }
        }
    }

    /// The lines between the opening `---` and the closing one, the opening first in the text after blank space.
    private static func frontMatterLines(of bytes: [UInt8]) -> [Substring] {
        let text = String(decoding: bytes, as: UTF8.self)
        let lines = text.drop { character in character == "\u{FEFF}" || character.isWhitespace && character != "\n" }
            .split(separator: "\n", omittingEmptySubsequences: false).map { line in line.hasSuffix("\r") ? line.dropLast() : line }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }
        let body = lines.dropFirst()
        guard let closing = body.firstIndex(where: { line in line.trimmingCharacters(in: .whitespaces) == "---" }) else { return [] }
        return Array(body[..<closing])
    }

    /// `key: value` or `key:`, the key plain or quoted: the key and the value as written, empty when none follows.
    private static func keyAndValue(_ content: String) -> (String, String)? {
        guard !content.hasPrefix("- ") else { return nil }
        var key: String
        var rest: Substring
        if let quote = content.first, quote == "\"" || quote == "'", let closing = content.dropFirst().firstIndex(of: quote) {
            key = String(content[content.index(after: content.startIndex)..<closing])
            rest = content[content.index(after: closing)...]
            guard rest.first == ":" else { return nil }
            rest = rest.dropFirst()
        } else {
            guard let colon = content.firstIndex(where: { character in character == ":" }) else { return nil }
            let after = content.index(after: colon)
            guard after == content.endIndex || content[after] == " " else { return nil }
            key = String(content[..<colon]).trimmingCharacters(in: .whitespaces)
            rest = content[after...]
        }
        return (key, withoutComment(rest.trimmingCharacters(in: .whitespaces)))
    }

    /// A plain value without the comment after it (` #`); a quoted one as it is.
    private static func withoutComment(_ written: String) -> String {
        guard let first = written.first, first != "\"", first != "'", let comment = written.range(of: " #") else { return written }
        return written[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    private static func value(_ written: String) -> Value {
        if let first = written.first, first == "{" || first == "[" { return .collection }
        if let first = written.first, first == "\"" || first == "'", written.count >= 2, written.last == first {
            return .text(String(written.dropFirst().dropLast()))
        }
        if written == "true" || written == "false" { return .boolean(written == "true") }
        if isNumber(written), let number = Double(written) { return .number(number) }
        return .text(written)
    }

    /// Whether the text is a number of YAML's JSON schema: a sign, digits with a fraction and an exponent.
    private static func isNumber(_ written: String) -> Bool {
        var bytes = Substring(written).utf8[...]
        if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
        let integerDigits = bytes.prefix { byte in MermaidByte.isDigit(byte) }.count
        bytes = bytes.dropFirst(integerDigits)
        var fractionDigits = 0
        if bytes.first == MermaidByte.period {
            fractionDigits = bytes.dropFirst().prefix { byte in MermaidByte.isDigit(byte) }.count
            bytes = bytes.dropFirst(fractionDigits + 1)
        }
        guard integerDigits + fractionDigits > 0 else { return false }
        if let exponent = bytes.first, exponent == UInt8(ascii: "e") || exponent == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { bytes = bytes.dropFirst() }
            let exponentDigits = bytes.prefix { byte in MermaidByte.isDigit(byte) }.count
            guard exponentDigits > 0 else { return false }
            bytes = bytes.dropFirst(exponentDigits)
        }
        return bytes.isEmpty
    }
}
