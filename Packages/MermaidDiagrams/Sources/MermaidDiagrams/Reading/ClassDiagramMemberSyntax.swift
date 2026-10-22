/// Reads a class member's text the way Mermaid splits it (`ClassMember` in Mermaid 12.1.0, as Pele reads it in one
/// pass): a method is the text with an opening parenthesis after its first character and a closing one later, its
/// visibility mark first, its classifier (`$` static, `*` abstract) right after the closing parenthesis or at the
/// end, and its return type after; anything else is an attribute, with its visibility first and its classifier last.
/// Generic types written with tildes are shown in angle brackets.
enum ClassDiagramMemberSyntax {
    /// The member `text` (trimmed, not empty) describes, and whether it is a method.
    static func member(from text: String) -> (member: ClassDiagramMember, isMethod: Bool) {
        let bytes = Array(text.utf8)
        if let method = method(from: bytes) { return (method, true) }
        return (attribute(from: bytes), false)
    }

    /// `name(parameters)` with what surrounds it, or nil when no parenthesis opens after the first character and
    /// closes later.
    private static func method(from bytes: [UInt8]) -> ClassDiagramMember? {
        guard let close = bytes.lastIndex(of: closingParenthesis), close > 0,
              let open = bytes[..<close].lastIndex(of: openingParenthesis), open > 0 else { return nil }
        let visibility = isVisibility(bytes[0]) && open > 1 ? text(bytes[0..<1]) : ""
        let nameStart = visibility.isEmpty ? 0 : 1
        let name = normalizedName(text(bytes[nameStart..<open]))
        let parameters = trimmed(text(bytes[(open + 1)..<close]))
        var rest = close + 1
        var classifier = ClassDiagramMemberClassifier.plain
        if rest < bytes.count {
            let next = bytes[rest]
            if let marked = classifierMarked(by: next) { classifier = marked }
            if classifier != .plain || MermaidByte.isWhitespace(next) { rest += 1 }
        }
        var returnType = trimmed(text(bytes[rest...]))
        if classifier == .plain, let last = returnType.utf8.last, let marked = classifierMarked(by: last) {
            classifier = marked
            returnType = String(returnType.dropLast())
        }
        var shown = visibility + angleBracketed(name) + "(" + angleBracketed(parameters) + ")"
        if !returnType.isEmpty { shown += " : " + angleBracketed(returnType) }
        return ClassDiagramMember(text: displayed(shown), classifier: classifier)
    }

    private static func attribute(from bytes: [UInt8]) -> ClassDiagramMember {
        guard let first = bytes.first, let last = bytes.last else { return ClassDiagramMember(text: "") }
        let visibility = isVisibility(first) ? text(bytes[0..<1]) : ""
        let classifier = classifierMarked(by: last) ?? .plain
        let start = visibility.isEmpty ? 0 : 1
        let end = max(start, classifier == .plain ? bytes.count : bytes.count - 1)
        let name = normalizedName(text(bytes[start..<end]))
        return ClassDiagramMember(text: displayed(visibility + angleBracketed(name)), classifier: classifier)
    }

    /// Generic types in angle brackets: `List~List~T~~` is `List<List<T>>`. Tildes pair from the outside in, a
    /// leading odd one stays, and `A~K, V~` stays one pair across its comma, as Mermaid's `parseGenericTypes` does.
    static func angleBracketed(_ text: String) -> String {
        guard text.utf8.contains(MermaidByte.tilde) else { return text }
        let parts = commaSeparated(text)
        var shown: [String] = []
        var index = 0
        while index < parts.count {
            var part = parts[index]
            if part == ",", index > 0, index + 1 < parts.count, tildeCount(parts[index - 1]) == 1, tildeCount(parts[index + 1]) == 1 {
                part = parts[index - 1] + "," + parts[index + 1]
                index += 1
                shown.removeLast()
            }
            shown.append(pairingTildes(part))
            index += 1
        }
        return shown.joined()
    }

    /// The text split at commas, each comma kept as a part of its own: `a,b` is `a`, `,`, `b`.
    private static func commaSeparated(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        for character in text {
            if character == "," {
                parts.append(current)
                parts.append(",")
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    private static func pairingTildes(_ text: String) -> String {
        var bytes = Array(text.utf8)
        let count = bytes.reduce(0) { count, byte in byte == MermaidByte.tilde ? count + 1 : count }
        guard count > 1 else { return text }
        let skipsLeading = !count.isMultiple(of: 2) && bytes.first == MermaidByte.tilde
        let positions = bytes.indices.dropFirst(skipsLeading ? 1 : 0).filter { index in bytes[index] == MermaidByte.tilde }
        var low = 0
        var high = positions.count - 1
        while low < high {
            bytes[positions[low]] = MermaidByte.lessThan
            bytes[positions[high]] = MermaidByte.greaterThan
            low += 1
            high -= 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func tildeCount(_ text: String) -> Int {
        text.utf8.reduce(0) { count, byte in byte == MermaidByte.tilde ? count + 1 : count }
    }

    private static func isVisibility(_ byte: UInt8) -> Bool {
        visibilityMarks.contains(byte)
    }

    private static func classifierMarked(by byte: UInt8) -> ClassDiagramMemberClassifier? {
        switch byte {
        case dollarSign: .static
        case asterisk: .abstract
        default: nil
        }
    }

    /// A name keeps one space where it started with spaces, as Mermaid keeps it (`+ getName()`).
    private static func normalizedName(_ name: String) -> String {
        name.utf8.first == MermaidByte.space ? " " + trimmed(name) : trimmed(name)
    }

    /// The text drawn: trimmed, with entity codes read.
    private static func displayed(_ shown: String) -> String {
        trimmed(DiagramLabelDecoder.decodingEntities(trimmed(shown)))
    }

    /// The text without the spaces, tabs and line breaks at either end, trimmed on its bytes.
    static func trimmed(_ text: String) -> String {
        var bytes = text.utf8[...]
        while let first = bytes.first, MermaidByte.isWhitespace(first) { bytes = bytes.dropFirst() }
        while let last = bytes.last, MermaidByte.isWhitespace(last) { bytes = bytes.dropLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func text(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    private static let openingParenthesis = UInt8(ascii: "(")
    private static let closingParenthesis = UInt8(ascii: ")")
    private static let dollarSign = UInt8(ascii: "$")
    private static let asterisk = UInt8(ascii: "*")
    /// `+` public, `-` private, `#` protected, `~` package.
    private static let visibilityMarks: Set<UInt8> = [UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "#"), MermaidByte.tilde]
}
