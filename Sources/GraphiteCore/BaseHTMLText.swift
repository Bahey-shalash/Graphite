import Foundation

/// The text and formatting Graphite shows for a Bases `html()` value.
///
/// Obsidian sanitizes the markup and hands it to its web view. A base cell in Graphite
/// is native text, so the markup is read here into runs of text with a fixed set of
/// formatting: bold, italic, underline, strikethrough, code, highlight, small, raised and
/// lowered text, colors, and links to web and mail addresses. The markup often holds
/// text from notes, which is not trusted, so nothing in it can run or load anything:
/// scripts, styles, frames, forms and embedded media are left out with their content, an
/// image shows its alternative text instead of being fetched, and any other link
/// destination is plain text.
public struct BaseHTMLText: Hashable, Sendable {
    public enum Baseline: Hashable, Sendable {
        case normal, raised, lowered
    }

    public struct Style: Hashable, Sendable {
        public var isBold = false
        public var isItalic = false
        public var isUnderlined = false
        public var isStruckThrough = false
        public var isMonospaced = false
        public var isHighlighted = false
        public var isSmall = false
        public var baseline = Baseline.normal
        public var foregroundColor: BaseColorSpecification?
        public var backgroundColor: BaseColorSpecification?
        /// A web (`http`, `https`) or mail (`mailto`) address.
        public var linkDestination: URL?
        public init() {}
    }

    public struct Run: Hashable, Sendable {
        public var text: String
        public var style: Style
        public init(text: String, style: Style = Style()) {
            self.text = text
            self.style = style
        }
    }

    /// Markup beyond this many characters is not read; a cell shows far less.
    public static let maximumSourceCharacters = 20_000
    /// Elements nested deeper than this keep the formatting of this depth.
    static let maximumElementDepth = 64

    public let runs: [Run]

    public init(source: String) {
        var parser = Parser(source: source)
        parser.parse()
        runs = parser.runs
    }

    /// The text without its formatting.
    public var plainText: String { runs.map(\.text).joined() }
}

// MARK: Reading markup

extension BaseHTMLText {
    /// Elements left out with everything inside them.
    private static let omittedElements: Set<String> = [
        "script", "style", "iframe", "frameset", "object", "applet", "template", "noscript", "head", "title", "svg", "math",
        "canvas", "audio", "video", "select", "option", "optgroup", "datalist", "textarea", "button", "map", "noembed", "noframes", "xmp", "plaintext",
    ]
    /// Omitted elements whose content is not markup, so only their own end tag ends them.
    private static let rawTextElements: Set<String> = ["script", "style", "iframe", "textarea", "title", "noscript", "noembed", "noframes", "xmp", "plaintext"]
    /// Elements without content or an end tag.
    private static let voidElements: Set<String> = ["br", "hr", "img", "wbr", "input", "meta", "link", "base", "source", "track", "area", "col", "param", "keygen", "embed", "frame"]
    /// Elements that start and end a line.
    private static let blockElements: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "main", "aside", "nav", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "dl", "dt", "dd",
        "table", "thead", "tbody", "tfoot", "tr", "caption", "blockquote", "pre", "figure", "figcaption", "address", "details", "summary", "fieldset", "form", "center",
    ]
    private static let boldElements: Set<String> = ["b", "strong", "h1", "h2", "h3", "h4", "h5", "h6", "th", "dt", "summary"]
    private static let italicElements: Set<String> = ["i", "em", "cite", "dfn", "var", "address"]
    private static let underlinedElements: Set<String> = ["u", "ins"]
    private static let struckThroughElements: Set<String> = ["s", "strike", "del"]
    private static let monospacedElements: Set<String> = ["code", "kbd", "samp", "tt", "pre"]
    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]

    private static let namedCharacters: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}", "copy": "©", "reg": "®", "trade": "™", "hellip": "…",
        "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»", "bull": "•", "middot": "·",
        "deg": "°", "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§",
        "para": "¶", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "check": "✓", "cross": "✗", "star": "☆", "starf": "★",
        "hearts": "♥", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}", "shy": "\u{AD}", "micro": "µ", "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥",
    ]

    private enum Separator: Int {
        case none, space, lineBreak
    }

    private struct OpenElement {
        let name: String
        /// The formatting and visibility that applied before the element opened.
        let outerStyle: Style
        let outerIsOmitted: Bool
        let outerPreservesWhitespace: Bool
        /// Text written when the element closes, such as the closing mark of `<q>`.
        let closingText: String?
    }

    private struct Parser {
        private let characters: [Character]
        private var position = 0
        private(set) var runs: [Run] = []
        private var openElements: [OpenElement] = []
        private var style = Style()
        private var isOmitted = false
        private var preservesWhitespace = false
        /// What separates the next text from the text before it, once there is any.
        private var pendingSeparator = Separator.none
        /// The formatting of the text a pending space was written in, which it keeps: the
        /// space between `<u>a</u> <u>b</u>` is not underlined.
        private var pendingSpaceStyle = Style()

        init(source: String) {
            characters = Array(source.prefix(BaseHTMLText.maximumSourceCharacters))
        }

        mutating func parse() {
            while position < characters.count {
                if characters[position] == "<", readTag() { continue }
                if characters[position] == "&", let decodedText = readCharacterReference() {
                    appendText(decodedText, collapsesWhitespace: false)
                    continue
                }
                let textStart = position
                position += 1
                while position < characters.count, characters[position] != "<", characters[position] != "&" { position += 1 }
                appendText(String(characters[textStart..<position]), collapsesWhitespace: !preservesWhitespace)
            }
            removeTrailingLineBreaks()
        }

        /// Line breaks after the last text, from `<br>` or preformatted text, show nothing.
        private mutating func removeTrailingLineBreaks() {
            while let lastIndex = runs.indices.last {
                while runs[lastIndex].text.last?.isNewline == true { runs[lastIndex].text.removeLast() }
                guard runs[lastIndex].text.isEmpty else { return }
                runs.removeLast()
            }
        }

        // MARK: Text

        private mutating func appendText(_ text: String, collapsesWhitespace: Bool) {
            guard !isOmitted else { return }
            guard collapsesWhitespace else {
                guard !text.isEmpty else { return }
                flushSeparator()
                append(text, style: style)
                return
            }
            var word = ""
            for character in text {
                if character.isWhitespace, character != "\u{A0}" {
                    if !word.isEmpty {
                        flushSeparator()
                        append(word, style: style)
                        word = ""
                    }
                    requestSeparator(.space, style: style)
                } else {
                    word.append(character)
                }
            }
            if !word.isEmpty {
                flushSeparator()
                append(word, style: style)
            }
        }

        private mutating func requestSeparator(_ separator: Separator, style spaceStyle: Style = Style()) {
            guard separator.rawValue > pendingSeparator.rawValue else { return }
            pendingSeparator = separator
            pendingSpaceStyle = spaceStyle
        }

        /// Writes the space or line break owed since the last text. Nothing is owed before
        /// the first text, which is how leading and trailing whitespace drop away.
        private mutating func flushSeparator() {
            defer { pendingSeparator = .none }
            guard !runs.isEmpty else { return }
            switch pendingSeparator {
            case .none: break
            case .space: append(" ", style: pendingSpaceStyle)
            case .lineBreak: append("\n", style: Style())
            }
        }

        private mutating func append(_ text: String, style: Style) {
            if let lastIndex = runs.indices.last, runs[lastIndex].style == style {
                runs[lastIndex].text += text
            } else {
                runs.append(Run(text: text, style: style))
            }
        }

        // MARK: Character references

        /// Reads `&name;`, `&#123;` or `&#x1F;` at the position; nil leaves the `&` as text.
        private mutating func readCharacterReference() -> String? {
            var end = position + 1
            while end < characters.count, end - position <= 12, characters[end] != ";", characters[end].isLetter || characters[end].isNumber || characters[end] == "#" { end += 1 }
            guard end < characters.count, characters[end] == ";", end > position + 1 else { return nil }
            let name = String(characters[(position + 1)..<end])
            let decodedText: String?
            if name.hasPrefix("#") {
                let digits = name.dropFirst()
                let codePoint = digits.hasPrefix("x") || digits.hasPrefix("X") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10)
                // A code point that is no character (zero, a surrogate, beyond Unicode) shows
                // as the replacement character, as browsers show it.
                decodedText = codePoint.map { codePoint in codePoint == 0 ? "\u{FFFD}" : String(Unicode.Scalar(codePoint) ?? "\u{FFFD}") }
            } else {
                decodedText = BaseHTMLText.namedCharacters[name]
            }
            guard let decodedText else { return nil }
            position = end + 1
            return decodedText
        }

        private static func decodingCharacterReferences(in text: String) -> String {
            guard text.contains("&") else { return text }
            var parser = Parser(source: text)
            var decodedText = ""
            while parser.position < parser.characters.count {
                if parser.characters[parser.position] == "&", let reference = parser.readCharacterReference() {
                    decodedText += reference
                } else {
                    decodedText.append(parser.characters[parser.position])
                    parser.position += 1
                }
            }
            return decodedText
        }

        // MARK: Tags

        /// Reads the tag, comment or declaration at the position. False when the `<` is
        /// not the start of one and stays text.
        private mutating func readTag() -> Bool {
            let next = position + 1 < characters.count ? characters[position + 1] : nil
            if next == "!" || next == "?" {
                if matches("<!--", at: position) {
                    position = index(after: "-->", from: position + 4) ?? characters.count
                } else {
                    position = index(after: ">", from: position + 2) ?? characters.count
                }
                return true
            }
            let isEndTag = next == "/"
            let nameStart = position + (isEndTag ? 2 : 1)
            guard nameStart < characters.count, characters[nameStart].isASCII, characters[nameStart].isLetter else { return false }
            var nameEnd = nameStart
            while nameEnd < characters.count, characters[nameEnd].isASCII, characters[nameEnd].isLetter || characters[nameEnd].isNumber || characters[nameEnd] == "-" { nameEnd += 1 }
            let name = String(characters[nameStart..<nameEnd]).lowercased()
            var attributes: [String: String] = [:]
            var scanPosition = nameEnd
            func skipWhitespace() {
                while scanPosition < characters.count, characters[scanPosition].isWhitespace { scanPosition += 1 }
            }
            while scanPosition < characters.count, characters[scanPosition] != ">" {
                if characters[scanPosition].isWhitespace || characters[scanPosition] == "/" { scanPosition += 1; continue }
                let attributeStart = scanPosition
                while scanPosition < characters.count, !characters[scanPosition].isWhitespace, characters[scanPosition] != "=", characters[scanPosition] != ">", characters[scanPosition] != "/" {
                    scanPosition += 1
                }
                let attributeName = String(characters[attributeStart..<scanPosition]).lowercased()
                skipWhitespace()
                var attributeValue = ""
                if scanPosition < characters.count, characters[scanPosition] == "=" {
                    scanPosition += 1
                    skipWhitespace()
                    if scanPosition < characters.count, characters[scanPosition] == "\"" || characters[scanPosition] == "'" {
                        let quote = characters[scanPosition]
                        let valueStart = scanPosition + 1
                        scanPosition = valueStart
                        while scanPosition < characters.count, characters[scanPosition] != quote { scanPosition += 1 }
                        attributeValue = String(characters[valueStart..<scanPosition])
                        scanPosition = min(scanPosition + 1, characters.count)
                    } else {
                        let valueStart = scanPosition
                        while scanPosition < characters.count, !characters[scanPosition].isWhitespace, characters[scanPosition] != ">" { scanPosition += 1 }
                        attributeValue = String(characters[valueStart..<scanPosition])
                    }
                }
                // The first of a repeated attribute counts, as in HTML.
                if !attributeName.isEmpty, attributes[attributeName] == nil { attributes[attributeName] = Self.decodingCharacterReferences(in: attributeValue) }
            }
            // A tag the text ends in is left out: it is markup, never text to show.
            position = min(scanPosition + 1, characters.count)
            if isEndTag { closeElement(named: name) } else { openElement(named: name, attributes: attributes) }
            return true
        }

        private func matches(_ text: String, at start: Int) -> Bool {
            let textCharacters = Array(text)
            guard start + textCharacters.count <= characters.count else { return false }
            return zip(textCharacters, characters[start...]).allSatisfy { expected, actual in expected == actual }
        }

        /// The position after the next `text` at or after `start`.
        private func index(after text: String, from start: Int) -> Int? {
            let textCharacters = Array(text)
            var candidate = start
            while candidate + textCharacters.count <= characters.count {
                if characters[candidate] == textCharacters[0], matches(text, at: candidate) { return candidate + textCharacters.count }
                candidate += 1
            }
            return nil
        }

        // MARK: Elements

        private mutating func openElement(named name: String, attributes: [String: String]) {
            switch name {
            case "br":
                // Every line break counts, unlike the space between blocks.
                if !isOmitted {
                    if pendingSeparator == .lineBreak, !runs.isEmpty { append("\n", style: Style()) }
                    pendingSeparator = .lineBreak
                }
                return
            case "hr":
                requestSeparator(.lineBreak)
                return
            case "img":
                // Never fetched: its alternative text stands for it.
                if let alternativeText = attributes["alt"], !alternativeText.isEmpty { appendText(alternativeText, collapsesWhitespace: true) }
                return
            default:
                if BaseHTMLText.voidElements.contains(name) { return }
            }
            if BaseHTMLText.rawTextElements.contains(name) {
                skipRawText(untilEndOf: name)
                return
            }
            let isBlock = BaseHTMLText.blockElements.contains(name)
            if isBlock { requestSeparator(.lineBreak) }
            if name == "td" || name == "th" { requestSeparator(.space) }
            guard openElements.count < BaseHTMLText.maximumElementDepth else { return }
            var closingText: String?
            let outerStyle = style, outerIsOmitted = isOmitted, outerPreservesWhitespace = preservesWhitespace

            if BaseHTMLText.omittedElements.contains(name) { isOmitted = true }
            if BaseHTMLText.boldElements.contains(name) { style.isBold = true }
            if BaseHTMLText.italicElements.contains(name) { style.isItalic = true }
            if BaseHTMLText.underlinedElements.contains(name) { style.isUnderlined = true }
            if BaseHTMLText.struckThroughElements.contains(name) { style.isStruckThrough = true }
            if BaseHTMLText.monospacedElements.contains(name) { style.isMonospaced = true }
            switch name {
            case "mark": style.isHighlighted = true
            case "small": style.isSmall = true
            case "sup": style.baseline = .raised
            case "sub": style.baseline = .lowered
            case "pre": preservesWhitespace = true
            case "a": style.linkDestination = attributes["href"].flatMap(Self.linkDestination)
            case "font": if let color = attributes["color"].flatMap(BaseColorParsing.color(from:)) { style.foregroundColor = color }
            case "li": appendText("•\u{A0}", collapsesWhitespace: true)
            case "q":
                appendText("“", collapsesWhitespace: true)
                closingText = "”"
            default: break
            }
            if let styleText = attributes["style"] { applyStyleAttribute(styleText) }
            if attributes["hidden"] != nil { isOmitted = true }
            openElements.append(OpenElement(name: name, outerStyle: outerStyle, outerIsOmitted: outerIsOmitted,
                                            outerPreservesWhitespace: outerPreservesWhitespace, closingText: closingText))
        }

        private mutating func closeElement(named name: String) {
            // An end tag without its start tag is ignored; one that skips over open
            // elements closes them too, as a browser does for misnested markup.
            guard let elementIndex = openElements.lastIndex(where: { element in element.name == name }) else {
                if name == "br" { openElement(named: "br", attributes: [:]) }
                if name == "p" { requestSeparator(.lineBreak) }
                return
            }
            while openElements.count > elementIndex {
                guard let element = openElements.popLast() else { break }
                if let closingText = element.closingText { appendText(closingText, collapsesWhitespace: true) }
                style = element.outerStyle
                isOmitted = element.outerIsOmitted
                preservesWhitespace = element.outerPreservesWhitespace
                if BaseHTMLText.blockElements.contains(element.name) { requestSeparator(.lineBreak) }
            }
        }

        /// Moves past the content and end tag of an element whose content is not markup.
        private mutating func skipRawText(untilEndOf name: String) {
            let endTag = Array("</" + name)
            var candidate = position
            while candidate + endTag.count <= characters.count {
                if characters[candidate] == "<", zip(endTag, characters[candidate...]).allSatisfy({ expected, actual in String(actual).lowercased() == String(expected) }) {
                    position = index(after: ">", from: candidate) ?? characters.count
                    return
                }
                candidate += 1
            }
            position = characters.count
        }

        /// A destination a tap may open: a web or mail address. Anything else, such as
        /// `javascript:`, `file:` or another app's scheme, is no link.
        private static func linkDestination(_ reference: String) -> URL? {
            let trimmedReference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let destination = URL(string: trimmedReference), let scheme = destination.scheme?.lowercased(), BaseHTMLText.linkSchemes.contains(scheme) else { return nil }
            return destination
        }

        /// The declarations of a `style` attribute that are text formatting.
        private mutating func applyStyleAttribute(_ styleText: String) {
            for declaration in styleText.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let property = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
                switch property {
                case "color":
                    if let color = BaseColorParsing.color(from: value) { style.foregroundColor = color }
                case "background-color", "background":
                    if let color = BaseColorParsing.color(from: value) { style.backgroundColor = color }
                case "font-weight":
                    if let weight = Int(value) { style.isBold = weight >= 600 } else if value == "bold" || value == "bolder" { style.isBold = true } else if value == "normal" || value == "lighter" { style.isBold = false }
                case "font-style":
                    if value == "italic" || value.hasPrefix("oblique") { style.isItalic = true } else if value == "normal" { style.isItalic = false }
                case "text-decoration", "text-decoration-line":
                    if value.contains("underline") { style.isUnderlined = true }
                    if value.contains("line-through") { style.isStruckThrough = true }
                    if value == "none" { style.isUnderlined = false; style.isStruckThrough = false }
                case "font-family":
                    if value.contains("monospace") { style.isMonospaced = true }
                case "display":
                    if value == "none" { isOmitted = true }
                case "visibility":
                    if value == "hidden" || value == "collapse" { isOmitted = true }
                default:
                    break
                }
            }
        }
    }
}
