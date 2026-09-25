import Foundation

/// Obsidian's footnotes: references `[^label]`, definitions `[^label]: text` (with lines
/// indented under them), and inline footnotes `^[text]`. Footnotes are numbered in the
/// order they are first referenced, as Obsidian numbers them.
public enum Footnotes {
    public struct Definition: Equatable, Sendable {
        public let label: String
        public let text: String
        /// The definition's lines, with their line breaks.
        public let range: NSRange
    }

    public struct Reference: Equatable, Sendable {
        /// Nil for an inline footnote.
        public let label: String?
        /// The text of an inline footnote.
        public let inlineText: String?
        public let range: NSRange
    }

    /// One footnote as the reading view lists it.
    public struct Note: Equatable, Sendable {
        public let number: Int
        public let text: String
    }

    private static let referencePattern = try? NSRegularExpression(pattern: "\\[\\^([^\\]\\s]+)\\](?!:)")
    private static let inlinePattern = try? NSRegularExpression(pattern: "(?<![\\\\!\\]])\\^\\[([^\\]\\n]+)\\]")
    private static let definitionPattern = try? NSRegularExpression(pattern: "^\\[\\^([^\\]\\s]+)\\]:[ \\t]?(.*)$")

    /// The definitions and references in `text`, outside code.
    public static func parse(_ text: String) -> (definitions: [Definition], references: [Reference]) {
        let source = text as NSString
        var definitions: [Definition] = []
        var references: [Reference] = []
        var tracker = CodeFenceTracker()
        var lineStart = FrontmatterLocator.length(in: source)
        var openDefinition: (label: String, text: String, start: Int, end: Int)?
        func closeDefinition() {
            guard let definition = openDefinition else { return }
            definitions.append(Definition(label: definition.label, text: definition.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                          range: NSRange(location: definition.start, length: definition.end - definition.start)))
            openDefinition = nil
        }
        while lineStart < source.length {
            let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
            var contentsEnd = 0
            source.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: lineRange)
            let line = source.substring(with: NSRange(location: lineRange.location, length: contentsEnd - lineRange.location))
            defer { lineStart = NSMaxRange(lineRange) }
            if tracker.isCodeLine(line.trimmingCharacters(in: .whitespaces)) { closeDefinition(); continue }
            let lineLength = (line as NSString).length
            if let match = definitionPattern?.firstMatch(in: line, range: NSRange(location: 0, length: lineLength)) {
                closeDefinition()
                openDefinition = ((line as NSString).substring(with: match.range(at: 1)), (line as NSString).substring(with: match.range(at: 2)),
                                  lineRange.location, NSMaxRange(lineRange))
                continue
            }
            // Lines indented under a definition continue it.
            if var definition = openDefinition, line.hasPrefix("    ") || line.hasPrefix("\t") {
                definition.text += "\n" + line.trimmingCharacters(in: .whitespaces)
                definition.end = NSMaxRange(lineRange)
                openDefinition = definition
                continue
            }
            closeDefinition()
            let codeRanges = MarkdownCodeRanges.ranges(in: line as NSString)
            func isInCode(_ range: NSRange) -> Bool { codeRanges.contains { codeRange in NSIntersectionRange(codeRange, range).length > 0 } }
            for match in referencePattern?.matches(in: line, range: NSRange(location: 0, length: lineLength)) ?? [] where !isInCode(match.range) {
                references.append(Reference(label: (line as NSString).substring(with: match.range(at: 1)), inlineText: nil,
                                            range: NSRange(location: lineRange.location + match.range.location, length: match.range.length)))
            }
            for match in inlinePattern?.matches(in: line, range: NSRange(location: 0, length: lineLength)) ?? [] where !isInCode(match.range) {
                references.append(Reference(label: nil, inlineText: (line as NSString).substring(with: match.range(at: 1)),
                                            range: NSRange(location: lineRange.location + match.range.location, length: match.range.length)))
            }
        }
        closeDefinition()
        return (definitions, references.sorted { first, second in first.range.location < second.range.location })
    }

    /// The footnotes as the Footnotes view lists them: numbered as when reading, each with
    /// where it is first referenced (or defined, when nothing refers to it).
    public static func listed(in text: String) -> [(note: Note, location: Int)] {
        numbered(text).notes
    }

    /// The note for reading: definitions removed, each reference replaced by `render(number)`,
    /// and the footnotes in number order. A reference without a definition stays as written,
    /// as does a definition nothing refers to, which Obsidian lists last.
    public static func preparedForReading(_ text: String, render: (Int) -> String) -> (text: String, notes: [Note]) {
        let numbering = numbered(text)
        guard !numbering.notes.isEmpty || !numbering.definitionRanges.isEmpty else { return (text, []) }
        let replacements = numbering.referenceNumbers.map { reference in (range: reference.range, text: render(reference.number)) }
            + numbering.definitionRanges.map { range in (range: range, text: "") }
        let prepared = NSMutableString(string: text)
        for replacement in replacements.sorted(by: { first, second in first.range.location > second.range.location }) {
            prepared.replaceCharacters(in: replacement.range, with: replacement.text)
        }
        return (prepared as String, numbering.notes.map(\.note))
    }

    /// Numbers footnotes in the order of their first reference; labels ignore case.
    private static func numbered(_ text: String) -> (notes: [(note: Note, location: Int)], referenceNumbers: [(range: NSRange, number: Int)], definitionRanges: [NSRange]) {
        let (definitions, references) = parse(text)
        var definitionsByLabel: [String: Definition] = [:]
        for definition in definitions where definitionsByLabel[definition.label.lowercased()] == nil { definitionsByLabel[definition.label.lowercased()] = definition }
        var numbersByLabel: [String: Int] = [:]
        var notes: [(note: Note, location: Int)] = []
        var referenceNumbers: [(range: NSRange, number: Int)] = []
        for reference in references {
            if let inlineText = reference.inlineText {
                notes.append((Note(number: notes.count + 1, text: inlineText), reference.range.location))
                referenceNumbers.append((reference.range, notes.count))
            } else if let label = reference.label?.lowercased(), let definition = definitionsByLabel[label] {
                let number: Int
                if let existing = numbersByLabel[label] { number = existing } else {
                    notes.append((Note(number: notes.count + 1, text: definition.text), reference.range.location))
                    number = notes.count
                    numbersByLabel[label] = number
                }
                referenceNumbers.append((reference.range, number))
            }
        }
        for definition in definitions where numbersByLabel[definition.label.lowercased()] == nil {
            notes.append((Note(number: notes.count + 1, text: definition.text), definition.range.location))
            numbersByLabel[definition.label.lowercased()] = notes.count
        }
        return (notes, referenceNumbers, definitions.map(\.range))
    }
}
