import Foundation

/// Converts pasted HTML (from a web page or a rich-text app) to Markdown, as Obsidian's
/// "Auto convert HTML" does on paste. Headings, emphasis, links, images, lists, quotes,
/// code, tables and line breaks are kept; other markup is dropped and its text kept.
/// A lenient reader: pasted HTML is often not well-formed.
public enum HTMLToMarkdown {
    /// Pasted HTML larger than this is pasted as plain text instead.
    public static let maximumConvertedLength = 2_000_000

    public static func markdown(from html: String) -> String {
        var converter = Converter()
        converter.convert(html)
        return converter.finishedText()
    }

    private struct ListLevel {
        let isOrdered: Bool
        /// The next ordered item's number: 1, or the list's `start`.
        var nextNumber = 1
    }

    /// A block that prefixes every line inside it, in nesting order: a quote writes `> `,
    /// and a list indents its items' continuation lines by one tab.
    private enum Container {
        case quote
        case list(ListLevel)

        var isList: Bool {
            if case .list = self { return true }
            return false
        }
    }

    /// An open inline element. Its opening delimiter is written only when content arrives,
    /// so an empty element writes nothing, whitespace at its edges stays outside the
    /// delimiters, and an element wrapping blocks is closed at each block end and reopened
    /// in the next block.
    private struct InlineElement {
        let tagName: String
        /// Nil for an element that writes no delimiters: a link that is unsafe or has no
        /// destination, or a `<b>` whose style cancels the bold (Google Docs wraps every
        /// copied selection in one).
        let openingDelimiter: String?
        let closingDelimiter: String
        /// The opening delimiter is in the output and the closing one is owed.
        var isOpenInOutput = false
    }

    private static let blockTagNames: Set<String> = ["p", "div", "section", "article", "header", "footer", "main", "figure", "figcaption", "dl", "dt", "dd",
                                                     "h1", "h2", "h3", "h4", "h5", "h6", "hr", "blockquote", "ul", "ol", "li", "pre"]
    private static let inlineTagNames: Set<String> = ["strong", "b", "em", "i", "cite", "del", "s", "strike", "mark", "a", "img"]
    /// Elements whose text is not shown and holds no markup, skipped through their closing tag.
    private static let rawTextTagNames: Set<String> = ["script", "style", "title"]
    /// Deeper inline nesting is ignored, which bounds the work done for every word of
    /// malformed HTML that opens tags without closing them.
    private static let maximumInlineNesting = 64
    /// Deeper quotes and lists are ignored: every line inside them repeats their prefix,
    /// so unclosed ones would make the output grow with the square of the input.
    private static let maximumContainerNesting = 64
    /// Named character references: the Latin-1 set, typographic punctuation and symbols,
    /// and Greek letters, which covers what pasted text uses.
    private static let characterByEntityName: [String: String] = {
        var characters: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
                                            "ndash": "\u{2013}", "mdash": "\u{2014}", "hellip": "\u{2026}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
                                            "sbquo": "\u{201A}", "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "\u{201E}", "lsaquo": "\u{2039}",
                                            "rsaquo": "\u{203A}", "bull": "\u{2022}", "dagger": "\u{2020}", "Dagger": "\u{2021}", "permil": "\u{2030}",
                                            "prime": "\u{2032}", "Prime": "\u{2033}", "euro": "\u{20AC}", "trade": "\u{2122}", "OElig": "\u{152}",
                                            "oelig": "\u{153}", "Scaron": "\u{160}", "scaron": "\u{161}", "Yuml": "\u{178}", "fnof": "\u{192}",
                                            "circ": "\u{2C6}", "tilde": "\u{2DC}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
                                            "zwnj": "\u{200C}", "zwj": "\u{200D}", "lrm": "\u{200E}", "rlm": "\u{200F}", "larr": "\u{2190}",
                                            "uarr": "\u{2191}", "rarr": "\u{2192}", "darr": "\u{2193}", "harr": "\u{2194}", "lArr": "\u{21D0}",
                                            "rArr": "\u{21D2}", "hArr": "\u{21D4}", "forall": "\u{2200}", "part": "\u{2202}", "exist": "\u{2203}",
                                            "empty": "\u{2205}", "nabla": "\u{2207}", "isin": "\u{2208}", "notin": "\u{2209}", "prod": "\u{220F}",
                                            "sum": "\u{2211}", "minus": "\u{2212}", "radic": "\u{221A}", "prop": "\u{221D}", "infin": "\u{221E}",
                                            "ang": "\u{2220}", "and": "\u{2227}", "or": "\u{2228}", "cap": "\u{2229}", "cup": "\u{222A}",
                                            "int": "\u{222B}", "there4": "\u{2234}", "sim": "\u{223C}", "asymp": "\u{2248}", "ne": "\u{2260}",
                                            "equiv": "\u{2261}", "le": "\u{2264}", "ge": "\u{2265}", "sub": "\u{2282}", "sup": "\u{2283}",
                                            "sube": "\u{2286}", "supe": "\u{2287}", "oplus": "\u{2295}", "otimes": "\u{2297}", "perp": "\u{22A5}",
                                            "sdot": "\u{22C5}", "loz": "\u{25CA}", "spades": "\u{2660}", "clubs": "\u{2663}", "hearts": "\u{2665}",
                                            "diams": "\u{2666}"]
        // U+00A0 through U+00FF, in code point order.
        let latin1Names = ["nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf", "laquo", "not", "shy", "reg", "macr",
                           "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest",
                           "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc", "Euml", "Igrave", "Iacute", "Icirc", "Iuml",
                           "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times", "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
                           "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml",
                           "eth", "ntilde", "ograve", "oacute", "ocirc", "otilde", "ouml", "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml"]
        // U+0391 through U+03A9 and U+03B1 through U+03C9; U+03A2 is unassigned.
        let greekNames = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta", "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi", "Omicron", "Pi", "Rho",
                          "", "Sigma", "Tau", "Upsilon", "Phi", "Chi", "Psi", "Omega"]
        let lowercaseGreekNames = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi", "rho",
                                   "sigmaf", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega"]
        for (names, firstCode) in [(latin1Names, 0xA0), (greekNames, 0x391), (lowercaseGreekNames, 0x3B1)] as [([String], UInt32)] {
            for (offset, name) in names.enumerated() where !name.isEmpty {
                if let scalar = Unicode.Scalar(firstCode + UInt32(offset)) { characters[name] = String(scalar) }
            }
        }
        return characters
    }()
    /// Markdown list numbers have at most nine digits.
    private static let maximumOrderedListNumber = 999_999_999
    /// Compiled once: compiling it for every tag was most of the conversion time.
    private static let attributePattern = try? NSRegularExpression(pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))")

    private struct Converter {
        var output = ""
        var containers: [Container] = []
        /// Quotes and lists opened past the nesting limit; their end tags close nothing.
        var ignoredContainerDepth = 0
        var inlineElements: [InlineElement] = []
        /// The closing delimiter just written, so an element reopened right after it
        /// continues instead of writing `****`.
        var lastClosedDelimiter: String?
        /// Inline code text is collected until the element ends, because the backtick run
        /// around it depends on the backticks inside it.
        var inlineCodeDepth = 0
        var inlineCodeText = ""
        /// `pre` text is collected verbatim and written as a fenced block when it ends.
        var preformattedDepth = 0
        var preformattedText = ""
        /// Nothing has come since the `pre` start tag, so a line break is not code: HTML
        /// drops the one right after the tag.
        var isRightAfterPreformattedStartTag = false
        var skippedDepth = 0
        var isAtLineStart = true
        /// The current line holds only a list item's marker, so the item's first block
        /// continues on it instead of leaving an empty bullet.
        var isAfterListMarker = false
        /// A nested list just ended inside an item. Text after it needs a blank line first,
        /// or it would continue the nested list's last item.
        var isAfterNestedList = false
        var pendingSpace = false
        var tableRowCount = 0
        var tableCellCount = 0
        var isInTableRow = false

        var quoteDepth: Int { containers.filter { container in !container.isList }.count }
        var isInList: Bool { containers.contains { container in container.isList } }

        mutating func convert(_ html: String) {
            let characters = Array(html.unicodeScalars)
            // A byte order mark is not text.
            var index = characters.first == "\u{FEFF}" ? 1 : 0
            var text = String.UnicodeScalarView()
            func flushText(_ converter: inout Converter) {
                if !text.isEmpty { converter.appendText(String(text)); text = String.UnicodeScalarView() }
            }
            // After a tag's quote runs to the end of the input, quotes no longer hide `>`:
            // otherwise every later `<` would scan to the end again, which is quadratic.
            var quotesHideClosingBrackets = true
            var nextClosingBracketIndex = 0
            while index < characters.count {
                let character = characters[index]
                guard character == "<" else { text.append(character); index += 1; continue }
                // Comments.
                if matches("<!--", at: index, in: characters) {
                    flushText(&self)
                    var end = index + 4
                    while end < characters.count, !matches("-->", at: end, in: characters) { end += 1 }
                    index = min(end + 3, characters.count)
                    continue
                }
                // "<" not followed by a tag name is text, as in "a < b".
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                guard next.properties.isAlphabetic || next == "/" || next == "!" || next == "?" else { text.append(character); index += 1; continue }
                var end = index + 1
                if quotesHideClosingBrackets {
                    var quote: Unicode.Scalar?
                    while end < characters.count {
                        let scalar = characters[end]
                        if let openQuote = quote { if scalar == openQuote { quote = nil } }
                        else if scalar == "\"" || scalar == "'" { quote = scalar }
                        else if scalar == ">" { break }
                        end += 1
                    }
                    if end == characters.count { quotesHideClosingBrackets = false }
                } else {
                    // Moves only forward, so all these scans together read the input once.
                    nextClosingBracketIndex = max(nextClosingBracketIndex, index + 1)
                    while nextClosingBracketIndex < characters.count && characters[nextClosingBracketIndex] != ">" { nextClosingBracketIndex += 1 }
                    end = nextClosingBracketIndex
                }
                guard end < characters.count else { text.append(character); index += 1; continue }
                flushText(&self)
                let tagContent = String(String.UnicodeScalarView(characters[(index + 1)..<end]))
                index = end + 1
                // Script and style text is not markup: a `<` in it would start a tag that
                // swallows the closing tag. It is skipped through its closing tag.
                if let rawTextTagName = Self.openingRawTextTagName(in: tagContent) {
                    index = Self.indexAfterClosingTag(named: rawTextTagName, from: index, in: characters)
                    continue
                }
                handleTag(tagContent)
            }
            flushText(&self)
            // Code left open by truncated HTML still becomes complete code.
            if preformattedDepth > 0 {
                preformattedDepth = 0
                writeCodeBlock(preformattedText)
            }
            flushInlineCode()
        }

        /// The name of a script, style or title start tag, whose text is not markup.
        static func openingRawTextTagName(in tagContent: String) -> String? {
            let trimmed = tagContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = String(trimmed.prefix { character in character.isLetter || character.isNumber }).lowercased()
            return HTMLToMarkdown.rawTextTagNames.contains(name) ? name : nil
        }

        /// The index after the `</name>` tag that ends a raw text element, or the end of the
        /// input when it is never closed.
        static func indexAfterClosingTag(named tagName: String, from startIndex: Int, in characters: [Unicode.Scalar]) -> Int {
            let nameScalars = Array(tagName.unicodeScalars)
            var index = startIndex
            while index + 1 < characters.count {
                if characters[index] == "<" && characters[index + 1] == "/" {
                    let nameEnd = index + 2 + nameScalars.count
                    let namesMatch = nameEnd <= characters.count && zip(characters[(index + 2)..<nameEnd], nameScalars).allSatisfy { characterScalar, nameScalar in
                        characterScalar.properties.lowercaseMapping == String(nameScalar)
                    }
                    if namesMatch && (nameEnd == characters.count || [" ", "\t", "\n", "\r", "\u{0C}", "/", ">"].contains(characters[nameEnd])) {
                        var closingBracketIndex = nameEnd
                        while closingBracketIndex < characters.count && characters[closingBracketIndex] != ">" { closingBracketIndex += 1 }
                        return min(closingBracketIndex + 1, characters.count)
                    }
                }
                index += 1
            }
            return characters.count
        }

        private func matches(_ literal: String, at index: Int, in characters: [Unicode.Scalar]) -> Bool {
            let literalScalars = Array(literal.unicodeScalars)
            guard index + literalScalars.count <= characters.count else { return false }
            return Array(characters[index..<(index + literalScalars.count)]) == literalScalars
        }

        // MARK: Tags

        private mutating func handleTag(_ content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("!"), !trimmed.hasPrefix("?") else { return }
            let isClosing = trimmed.hasPrefix("/")
            let body = isClosing ? String(trimmed.dropFirst()) : trimmed
            let name = String(body.prefix { character in character.isLetter || character.isNumber }).lowercased()
            let attributeText = body.dropFirst(name.count)
            let attributes = isClosing || attributeText.isEmpty ? [:] : Self.attributes(in: String(attributeText))
            // `head` is not skipped: its end tag is optional, and its visible-text-free
            // children (title, style, script) are skipped on their own.
            if ["noscript", "template"].contains(name) {
                skippedDepth = max(0, skippedDepth + (isClosing ? -1 : 1))
                return
            }
            guard skippedDepth == 0 else { return }
            // Inside `pre` everything is code text: markup would be written into the code.
            // A block inside it (a line `div`, for example) still starts a new line.
            if preformattedDepth > 0 && name != "pre" {
                isRightAfterPreformattedStartTag = false
                if name == "br" {
                    preformattedText += "\n"
                } else if HTMLToMarkdown.blockTagNames.contains(name), !preformattedText.isEmpty, !preformattedText.hasSuffix("\n") {
                    preformattedText += "\n"
                }
                return
            }
            // Markup inside inline code is literal in Markdown, so only its text is kept.
            if inlineCodeDepth > 0 && HTMLToMarkdown.inlineTagNames.contains(name) { return }
            // A table row is one line: a block inside a cell is only a space between its words.
            if isInTableRow && HTMLToMarkdown.blockTagNames.contains(name) {
                if name == "pre" {
                    handleInlineCodeTag(isClosing: isClosing)
                } else {
                    closeAllInlineDelimiters()
                    pendingSpace = true
                }
                return
            }
            switch name {
            case "p", "div", "section", "article", "header", "footer", "main", "figure", "figcaption", "dl", "dt", "dd":
                endBlock()
            case "br":
                closeAllInlineDelimiters()
                if isInTableRow {
                    pendingSpace = true
                } else {
                    write("  \n")
                    isAtLineStart = true
                    pendingSpace = false
                }
            case "hr":
                // `</hr>` is an error that browsers ignore, not a second rule.
                guard !isClosing else { return }
                endBlockBeforeOwnLineBlock()
                writeLinePrefixIfNeeded()
                // Inside a list, blocks are not separated by blank lines, and `---` right
                // under a line of text would turn that line into a heading.
                write(isInList ? "***" : "---")
                endBlock()
            case "h1", "h2", "h3", "h4", "h5", "h6":
                endBlock()
                if !isClosing, let level = Int(name.dropFirst()) {
                    writeLinePrefixIfNeeded()
                    write(String(repeating: "#", count: level) + " ")
                }
            case "strong", "b":
                if isClosing { closeInlineElement(named: name); return }
                let isBold = !Self.declaresNonBoldFontWeight(attributes["style"])
                openInlineElement(named: name, openingDelimiter: isBold ? "**" : nil, closingDelimiter: "**")
            case "em", "i", "cite":
                if isClosing { closeInlineElement(named: name) } else { openInlineElement(named: name, openingDelimiter: "*", closingDelimiter: "*") }
            case "del", "s", "strike":
                if isClosing { closeInlineElement(named: name) } else { openInlineElement(named: name, openingDelimiter: "~~", closingDelimiter: "~~") }
            case "mark":
                if isClosing { closeInlineElement(named: name) } else { openInlineElement(named: name, openingDelimiter: "==", closingDelimiter: "==") }
            case "code":
                handleInlineCodeTag(isClosing: isClosing)
            case "pre":
                if isClosing {
                    guard preformattedDepth > 0 else { return }
                    preformattedDepth -= 1
                    if preformattedDepth == 0 { writeCodeBlock(preformattedText) }
                } else {
                    if preformattedDepth == 0 {
                        endBlockBeforeOwnLineBlock()
                        preformattedText = ""
                        isRightAfterPreformattedStartTag = true
                    }
                    preformattedDepth += 1
                }
            case "blockquote":
                if isClosing, ignoredContainerDepth > 0 {
                    ignoredContainerDepth -= 1
                } else if !isClosing, containers.count >= HTMLToMarkdown.maximumContainerNesting {
                    ignoredContainerDepth += 1
                } else if isClosing {
                    closeAllInlineDelimiters()
                    // The quote's last blank line belongs outside it.
                    let quoteBlankLine = String(repeating: ">", count: quoteDepth) + "\n"
                    if output.hasSuffix("\n" + quoteBlankLine) { output.removeLast(quoteBlankLine.count) }
                    if let quotePosition = containers.lastIndex(where: { container in !container.isList }) { containers.removeSubrange(quotePosition...) }
                    endBlock()
                } else {
                    endBlock()
                    // A quote that is an item's first block starts on the marker's line.
                    if isAfterListMarker {
                        write("> ")
                        isAfterListMarker = true
                    }
                    containers.append(.quote)
                }
            case "ul", "ol":
                if isClosing, ignoredContainerDepth > 0 {
                    ignoredContainerDepth -= 1
                } else if !isClosing, containers.count >= HTMLToMarkdown.maximumContainerNesting {
                    ignoredContainerDepth += 1
                } else if isClosing {
                    if let listPosition = containers.lastIndex(where: { container in container.isList }) { containers.removeSubrange(listPosition...) }
                    if isInList {
                        startLine()
                        isAfterNestedList = true
                    } else {
                        isAfterNestedList = false
                        endBlock()
                    }
                } else {
                    if !isInList { endBlock() }
                    var level = ListLevel(isOrdered: name == "ol")
                    if let start = Self.orderedListNumber(attributes["start"]) { level.nextNumber = start }
                    containers.append(.list(level))
                }
            case "li":
                guard !isClosing else { return }
                startLine()
                var marker = "- "
                if let listPosition = containers.lastIndex(where: { container in container.isList }), case .list(var level) = containers[listPosition] {
                    if let itemNumber = Self.orderedListNumber(attributes["value"]) { level.nextNumber = itemNumber }
                    marker = level.isOrdered ? "\(level.nextNumber). " : "- "
                    level.nextNumber = min(level.nextNumber + 1, HTMLToMarkdown.maximumOrderedListNumber)
                    containers[listPosition] = .list(level)
                }
                write(linePrefix(isListMarkerLine: true) + marker)
                isAtLineStart = false
                pendingSpace = false
                isAfterListMarker = true
                isAfterNestedList = false
            case "a":
                if isClosing { closeInlineElement(named: name); return }
                let href = Self.cleanedURL(attributes["href"] ?? "")
                let isWritten = !href.isEmpty && !Self.isScriptURL(href)
                openInlineElement(named: name, openingDelimiter: isWritten ? "[" : nil, closingDelimiter: "](" + Self.escapedDestination(href) + ")")
            case "img":
                let source = Self.cleanedURL(attributes["src"] ?? "")
                guard !source.isEmpty, !source.lowercased().hasPrefix("data:") else { return }
                let image = "![" + Self.escapedAltText(attributes["alt"] ?? "") + "](" + Self.escapedDestination(source) + ")"
                writeInlineContent(isInTableRow ? Self.escapedTableCellText(image) : image)
            case "table":
                if isClosing {
                    if isInTableRow { endTableRow() }
                    endBlock()
                } else {
                    endBlockBeforeOwnLineBlock()
                    tableRowCount = 0
                }
            case "tr":
                if isClosing {
                    endTableRow()
                } else {
                    // HTML lets a row end where the next one starts, without `</tr>`.
                    if isInTableRow { endTableRow() }
                    startLine()
                    writeLinePrefixIfNeeded()
                    write("|")
                    isInTableRow = true
                    tableCellCount = 0
                }
            case "td", "th":
                if !isClosing {
                    closeAllInlineDelimiters()
                    if tableCellCount > 0 { write(" |") }
                    write(" ")
                    tableCellCount += 1
                    pendingSpace = false
                }
            default:
                break
            }
        }

        /// Ends the row's line; the first row is the header, so the delimiter row follows it.
        private mutating func endTableRow() {
            closeAllInlineDelimiters()
            write(" |")
            isInTableRow = false
            tableRowCount += 1
            if tableRowCount == 1 {
                startLine()
                writeLinePrefixIfNeeded()
                write("|" + String(repeating: " --- |", count: max(tableCellCount, 1)))
            }
        }

        static func attributes(in text: String) -> [String: String] {
            var attributes: [String: String] = [:]
            let source = text as NSString
            for match in HTMLToMarkdown.attributePattern?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? [] {
                let name = source.substring(with: match.range(at: 1)).lowercased()
                let valueRange = [2, 3, 4].map { group in match.range(at: group) }.first { range in range.location != NSNotFound }
                attributes[name] = valueRange.map { range in decodedEntities(source.substring(with: range)) } ?? ""
            }
            return attributes
        }

        /// An `ol start` or `li value` number, clamped to what a Markdown list can start with.
        static func orderedListNumber(_ attribute: String?) -> Int? {
            guard let attribute, let number = Int(attribute.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return min(max(number, 0), HTMLToMarkdown.maximumOrderedListNumber)
        }

        /// Whether an inline style sets a normal font weight, as Google Docs' wrapper
        /// `<b style="font-weight:normal">` does.
        static func declaresNonBoldFontWeight(_ style: String?) -> Bool {
            guard let style else { return false }
            let minimumBoldWeight = 600
            for declaration in style.lowercased().split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1).map { part in part.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts[0] == "font-weight" else { continue }
                let weight = parts[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
                if weight == "normal" || weight == "lighter" { return true }
                if let numericWeight = Int(weight), numericWeight < minimumBoldWeight { return true }
            }
            return false
        }

        /// A URL as a browser reads it: tabs and line breaks inside it are removed, and
        /// control characters and spaces around it are trimmed.
        static func cleanedURL(_ url: String) -> String {
            let withoutLineBreaks = url.unicodeScalars.filter { scalar in scalar != "\t" && scalar != "\n" && scalar != "\r" }
            let isTrimmed = { (scalar: Unicode.Scalar) in scalar.value <= 0x20 }
            let trimmed = withoutLineBreaks.drop(while: isTrimmed).reversed().drop(while: isTrimmed).reversed()
            return String(String.UnicodeScalarView(trimmed))
        }

        /// Script URLs run code when clicked, so their links keep only their text. Schemes
        /// are case-insensitive: `JavaScript:` is one too.
        static func isScriptURL(_ url: String) -> Bool {
            let lowercasedURL = url.lowercased()
            return lowercasedURL.hasPrefix("javascript:") || lowercasedURL.hasPrefix("vbscript:")
        }

        /// A destination with spaces, parentheses or angle brackets is written between `<`
        /// and `>`, with the angle brackets inside it escaped. Backslashes and entity-like
        /// `&name;` text are escaped too, so Markdown reads back exactly the URL that was
        /// checked: `javascript&colon;` would otherwise become a script URL when rendered.
        static func escapedDestination(_ destination: String) -> String {
            var escaped = destination.replacingOccurrences(of: "\\", with: "\\\\")
            if escaped.contains("&") {
                escaped = escaped.replacingOccurrences(of: "&(?=#?[A-Za-z0-9]+;)", with: "\\\\&", options: .regularExpression)
            }
            guard escaped.contains(where: { character in " ()<>".contains(character) }) else { return escaped }
            return "<" + escaped.replacingOccurrences(of: "<", with: "\\<").replacingOccurrences(of: ">", with: "\\>") + ">"
        }

        /// Alt text on one line, with the brackets and backslashes that would end or change
        /// the image syntax escaped.
        static func escapedAltText(_ alt: String) -> String {
            let singleLine = alt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            var escaped = ""
            for character in singleLine {
                if character == "[" || character == "]" || character == "\\" { escaped.append("\\") }
                escaped.append(character)
            }
            return escaped
        }

        // MARK: Inline elements

        private mutating func openInlineElement(named tagName: String, openingDelimiter: String?, closingDelimiter: String) {
            guard inlineElements.count < HTMLToMarkdown.maximumInlineNesting else { return }
            inlineElements.append(InlineElement(tagName: tagName, openingDelimiter: openingDelimiter, closingDelimiter: closingDelimiter))
        }

        /// Closes the innermost element with this name. Elements opened inside it and not
        /// yet closed (misnested HTML) are closed with it and reopened at their next content.
        private mutating func closeInlineElement(named tagName: String) {
            guard let position = inlineElements.lastIndex(where: { element in element.tagName == tagName }) else { return }
            closeInlineDelimiters(from: position)
            inlineElements.remove(at: position)
        }

        private mutating func closeInlineDelimiters(from position: Int) {
            for index in stride(from: inlineElements.count - 1, through: position, by: -1) where inlineElements[index].isOpenInOutput {
                let closingDelimiter = inlineElements[index].closingDelimiter
                // A link's destination can hold a `|`, which would end the cell.
                write(isInTableRow ? Self.escapedTableCellText(closingDelimiter) : closingDelimiter)
                lastClosedDelimiter = closingDelimiter
                inlineElements[index].isOpenInOutput = false
            }
        }

        /// Ends all inline markup before a line or block ends; it reopens with the next content.
        private mutating func closeAllInlineDelimiters() {
            flushInlineCode()
            closeInlineDelimiters(from: 0)
        }

        /// Writes the opening delimiters of elements that have content now.
        private mutating func writePendingInlineDelimiters() {
            for position in inlineElements.indices where !inlineElements[position].isOpenInOutput {
                guard let openingDelimiter = inlineElements[position].openingDelimiter else { continue }
                // `<b><strong>x</strong></b>` is bold once, not `****x****`.
                let repeatsEnclosingElement = inlineElements[..<position].contains { element in
                    element.isOpenInOutput && element.openingDelimiter == openingDelimiter
                }
                guard !repeatsEnclosingElement else { continue }
                if openingDelimiter == inlineElements[position].closingDelimiter, lastClosedDelimiter == openingDelimiter, output.hasSuffix(openingDelimiter) {
                    // `<b>a</b><b>b</b>` continues one bold run: `**ab**`.
                    output.removeLast(openingDelimiter.count)
                    lastClosedDelimiter = nil
                } else {
                    write(openingDelimiter)
                }
                inlineElements[position].isOpenInOutput = true
            }
        }

        private mutating func handleInlineCodeTag(isClosing: Bool) {
            if isClosing {
                guard inlineCodeDepth > 0 else { return }
                inlineCodeDepth -= 1
                if inlineCodeDepth == 0 { flushInlineCode() }
            } else {
                inlineCodeDepth += 1
            }
        }

        /// Writes the collected inline code as a code span whose backtick run is longer than
        /// any run inside it. Spaces at its edges go outside, like emphasis.
        private mutating func flushInlineCode() {
            guard !inlineCodeText.isEmpty else { return }
            let codeText = inlineCodeText
            inlineCodeText = ""
            let hasLeadingSpace = codeText.hasPrefix(" ")
            let hasTrailingSpace = codeText.hasSuffix(" ")
            let trimmedCode = codeText.trimmingCharacters(in: .whitespaces)
            if hasLeadingSpace && !isAtLineStart { pendingSpace = true }
            guard !trimmedCode.isEmpty else { return }
            let code = isInTableRow ? Self.escapedTableCellText(trimmedCode) : trimmedCode
            let fence = String(repeating: "`", count: Self.longestRun(of: "`", in: code) + 1)
            // A space keeps a backtick at the code's edge from joining the fence.
            let padding = code.hasPrefix("`") || code.hasSuffix("`") ? " " : ""
            writeInlineContent(fence + padding + code + padding + fence)
            pendingSpace = hasTrailingSpace
        }

        // MARK: Text

        private mutating func appendText(_ rawText: String) {
            guard skippedDepth == 0 else { return }
            let decoded = Self.decodedEntities(rawText)
            if preformattedDepth > 0 {
                // A no-break space in code is a space: code copied with one would not run.
                var code = decoded.replacingOccurrences(of: "\u{A0}", with: " ")
                if isRightAfterPreformattedStartTag {
                    isRightAfterPreformattedStartTag = false
                    // `\r\n` is one Character.
                    if let firstCharacter = code.first, firstCharacter == "\r\n" || firstCharacter == "\n" || firstCharacter == "\r" { code.removeFirst() }
                }
                preformattedText += code
                return
            }
            if inlineCodeDepth > 0 {
                // Code spans show their text on one line, as the browser does.
                for character in decoded {
                    if character.isWhitespace {
                        if !inlineCodeText.hasSuffix(" ") { inlineCodeText += " " }
                    } else {
                        inlineCodeText.append(character)
                    }
                }
                return
            }
            // Outside `pre`, runs of whitespace are one space, as a browser shows them. No-break
            // spaces are kept between words (`10&nbsp;km`, deliberate spacing), and are spaces
            // like any other at a word's edge, where they would stop emphasis from closing.
            let words = decoded.split { character in character.isWhitespace && character != "\u{A0}" }
                .map { word in word.trimmingCharacters(in: CharacterSet(charactersIn: "\u{A0}")) }
                .filter { word in !word.isEmpty }
            let startsWithSpace = decoded.first?.isWhitespace == true
            let endsWithSpace = decoded.last?.isWhitespace == true
            if startsWithSpace && !isAtLineStart { pendingSpace = true }
            guard !words.isEmpty else { return }
            let joinedWords = words.joined(separator: " ")
            writeInlineContent(isInTableRow ? Self.escapedTableCellText(joinedWords) : joinedWords)
            pendingSpace = endsWithSpace
        }

        /// A `|` in a cell would end the cell.
        static func escapedTableCellText(_ text: String) -> String {
            text.replacingOccurrences(of: "|", with: "\\|")
        }

        static func longestRun(of character: Character, in text: String) -> Int {
            var longestRunLength = 0
            var currentRunLength = 0
            for textCharacter in text {
                currentRunLength = textCharacter == character ? currentRunLength + 1 : 0
                longestRunLength = max(longestRunLength, currentRunLength)
            }
            return longestRunLength
        }

        /// Text, an image or a code span: writes what must precede it on the line first.
        private mutating func writeInlineContent(_ markdown: String) {
            writePendingSpace()
            writeLinePrefixIfNeeded()
            writePendingInlineDelimiters()
            write(markdown)
            isAtLineStart = false
        }

        /// Every write goes through here, so the line is no longer only a list marker and
        /// no delimiter was closed immediately before whatever comes next.
        private mutating func write(_ markdown: String) {
            output += markdown
            isAfterListMarker = false
            lastClosedDelimiter = nil
        }

        private mutating func writePendingSpace() {
            if pendingSpace && !isAtLineStart && !output.hasSuffix(" ") && !output.hasSuffix("\n") { write(" ") }
            pendingSpace = false
        }

        private mutating func writeLinePrefixIfNeeded() {
            guard isAtLineStart else { return }
            if isAfterNestedList {
                isAfterNestedList = false
                write(emptyLinePrefix() + "\n")
            }
            write(linePrefix(isListMarkerLine: false))
            isAtLineStart = false
        }

        /// The quote markers and list indentation of the enclosing blocks. A list item's
        /// marker line is indented one level less than the item's content.
        private func linePrefix(isListMarkerLine: Bool) -> String {
            let markerListPosition = isListMarkerLine ? containers.lastIndex(where: { container in container.isList }) : nil
            var prefix = ""
            for (position, container) in containers.enumerated() {
                switch container {
                case .quote: prefix += "> "
                case .list: if position != markerListPosition { prefix += "\t" }
                }
            }
            return prefix
        }

        /// The line prefix for an empty line: the quote markers without trailing whitespace.
        private func emptyLinePrefix() -> String {
            String(linePrefix(isListMarkerLine: false).reversed().drop { character in character.isWhitespace }.reversed())
        }

        /// Writes collected `pre` text as a fenced code block, each line prefixed for the
        /// enclosing quotes and lists, with a fence longer than any backtick run inside.
        private mutating func writeCodeBlock(_ preformatted: String) {
            // A fence ends the nested list's item by itself, so no blank line is owed after it.
            isAfterNestedList = false
            var code = preformatted.replacingOccurrences(of: "\r\n", with: "\n")
            if code.hasSuffix("\n") { code.removeLast() }
            let fence = String(repeating: "`", count: max(3, Self.longestRun(of: "`", in: code) + 1))
            let prefix = linePrefix(isListMarkerLine: false)
            let prefixOfEmptyLines = emptyLinePrefix()
            var block = prefix + fence + "\n"
            if !code.isEmpty {
                for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                    block += (line.isEmpty ? prefixOfEmptyLines : prefix + line) + "\n"
                }
            }
            write(block + prefix + fence)
            isAtLineStart = false
            endBlock()
        }

        private mutating func startLine() {
            closeAllInlineDelimiters()
            if !output.isEmpty && !output.hasSuffix("\n") { write("\n") }
            isAtLineStart = true
            pendingSpace = false
        }

        /// Ends a block with a blank line, keeping the quote prefix on it.
        private mutating func endBlock() {
            closeAllInlineDelimiters()
            // A list item's first block continues on the marker's line.
            guard !isAfterListMarker else { return }
            guard !output.isEmpty else { isAtLineStart = true; return }
            startLine()
            // Inside a list, blocks stay on consecutive lines so the list is not broken up.
            guard !isInList, !output.hasSuffix("\n\n") else { isAtLineStart = true; return }
            if quoteDepth > 0 {
                let quoteBlankLine = String(repeating: ">", count: quoteDepth) + "\n"
                if !output.hasSuffix("\n" + quoteBlankLine) { write(quoteBlankLine) }
            } else {
                write("\n")
            }
            isAtLineStart = true
        }

        /// Ends the previous block before a code block, table or rule. These cannot share a
        /// list marker's line: the code's lines and the table's rows must all carry the
        /// same indentation, so they start on the next line.
        private mutating func endBlockBeforeOwnLineBlock() {
            if isAfterListMarker { startLine() } else { endBlock() }
        }

        static func decodedEntities(_ text: String) -> String {
            guard text.contains("&") else { return text }
            var decodedText = ""
            var index = text.startIndex
            while index < text.endIndex {
                if text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") {
                    let entity = String(text[text.index(after: index)..<semicolon])
                    var replacement: String?
                    let hexadecimalDigits = entity.dropFirst(2)
                    let decimalDigits = entity.dropFirst()
                    // `UInt32` also reads a sign, which a character reference cannot have.
                    if entity.hasPrefix("#x") || entity.hasPrefix("#X"), hexadecimalDigits.allSatisfy(\.isHexDigit), let code = UInt32(hexadecimalDigits, radix: 16) {
                        replacement = Self.characterReference(code)
                    } else if entity.hasPrefix("#"), decimalDigits.allSatisfy({ character in character.isASCII && character.isWholeNumber }), let code = UInt32(decimalDigits) {
                        replacement = Self.characterReference(code)
                    } else {
                        replacement = HTMLToMarkdown.characterByEntityName[entity]
                    }
                    if let replacement {
                        decodedText += replacement
                        index = text.index(after: semicolon)
                        continue
                    }
                }
                decodedText.append(text[index])
                index = text.index(after: index)
            }
            return decodedText
        }

        /// A numeric character reference. As in browsers, zero, surrogates and numbers past
        /// Unicode are the replacement character instead of a NUL or the literal reference.
        static func characterReference(_ code: UInt32) -> String {
            guard code != 0, let scalar = Unicode.Scalar(code) else { return "\u{FFFD}" }
            return String(scalar)
        }

        /// Blank lines are written only where a block ends, so runs of them inside code are
        /// the code's own and are kept.
        func finishedText() -> String {
            output.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

