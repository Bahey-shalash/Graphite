import Foundation

/// The rich text of a `/FreeText` annotation, its `/RC` entry: XHTML in the subset the PDF
/// standard takes from XFA, as Acrobat writes it. Each line of the box is one `<p>`, each
/// run of one look a `<span>` whose `style` gives all of it.
///
/// Links are not part of that subset; they are kept in Graphite's record of the box and
/// written as `/Link` annotations over the text.
public enum PDFTextBoxRichText {
    /// Bounds what is read from a file: the text, the depth of its elements and its runs.
    public static let maximumUTF16Count = 2_000_000
    public static let maximumNesting = 32

    // MARK: Writing

    public static func richText(of box: PDFTextBox) -> String {
        let bodyStyle = PDFTextStyleDeclarations.styleText(of: box.leadingAttributes) + ";text-align:"
            + PDFTextStyleDeclarations.cssAlignment(box.style.alignment)
        var text = "<?xml version=\"1.0\"?><body xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:xfa=\"http://www.xfa.org/schema/xfa-data/1.0/\""
            + " xfa:APIVersion=\"Acrobat:11.0.0\" xfa:spec=\"2.0.2\" style=\"" + escaped(bodyStyle) + "\">"
        for line in lines(of: box.runs) {
            text += "<p dir=\"ltr\">"
            for run in line {
                text += "<span style=\"" + escaped(PDFTextStyleDeclarations.styleText(of: run.attributes)) + "\">" + escaped(run.text) + "</span>"
            }
            text += "</p>"
        }
        return text + "</body>"
    }

    /// The runs of each line, without the line breaks; an empty line has no runs.
    static func lines(of runs: [PDFTextRun]) -> [[PDFTextRun]] {
        var lines: [[PDFTextRun]] = [[]]
        for run in runs {
            let pieces = run.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (pieceIndex, piece) in pieces.enumerated() {
                if pieceIndex > 0 { lines.append([]) }
                if !piece.isEmpty { lines[lines.count - 1].append(PDFTextRun(text: String(piece), attributes: run.attributes)) }
            }
        }
        return lines
    }

    private static func escaped(_ text: String) -> String {
        var escapedText = ""
        escapedText.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": escapedText += "&amp;"
            case "<": escapedText += "&lt;"
            case ">": escapedText += "&gt;"
            case "\"": escapedText += "&quot;"
            default: escapedText.append(character)
            }
        }
        return escapedText
    }

    // MARK: Reading

    /// What rich text says: its runs and the alignment its body or first paragraph sets.
    public struct Reading: Sendable, Equatable {
        public let runs: [PDFTextRun]
        public let alignment: PDFTextAlignment?
    }

    /// The runs of rich text, each starting from `defaults` (the box's `/DS` and `/DA`), or
    /// nil when the text is not well-formed or past the limits: the box then opens as its
    /// plain text.
    public static func reading(_ richText: String, defaults: PDFTextAttributes) -> Reading? {
        guard richText.utf16.count <= maximumUTF16Count, let data = richText.data(using: .utf8) else { return nil }
        let parser = XMLParser(data: data)
        let reader = RichTextReader(defaults: defaults)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !reader.exceededLimits, reader.hasBody else { return nil }
        return Reading(runs: PDFTextRun.normalized(reader.runs), alignment: reader.alignment)
    }
}

/// Builds runs as `XMLParser` reports the elements of rich text. Each element's looks
/// inherit its parent's; `<b>`, `<i>` and `<u>` and the CSS of `style` change them.
private final class RichTextReader: NSObject, XMLParserDelegate {
    private var attributeStack: [PDFTextAttributes]
    private(set) var runs: [PDFTextRun] = []
    private(set) var alignment: PDFTextAlignment?
    private(set) var exceededLimits = false
    private(set) var hasBody = false
    private var paragraphCount = 0
    private var textUTF16Count = 0
    /// Line breaks of paragraphs and `<br/>` not yet written: each goes before the next text,
    /// in that text's looks, as a line break takes the looks of the line it starts.
    private var pendingLineBreaks = 0

    init(defaults: PDFTextAttributes) {
        attributeStack = [defaults]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        guard attributeStack.count <= PDFTextBoxRichText.maximumNesting else {
            exceededLimits = true
            parser.abortParsing()
            return
        }
        let element = (qualifiedName ?? elementName).split(separator: ":").last.map(String.init)?.lowercased() ?? elementName
        var current = attributeStack.last ?? .plain
        switch element {
        case "body": hasBody = true
        case "p":
            if paragraphCount > 0 { pendingLineBreaks += 1 }
            paragraphCount += 1
        case "br": pendingLineBreaks += 1
        case "b": current.isBold = true
        case "i": current.isItalic = true
        case "u": current.isUnderlined = true
        case "a": current.link = attributes["href"].flatMap(URL.init(string:))
        default: break
        }
        let properties = PDFTextStyleDeclarations.properties(of: attributes["style"] ?? "")
        if alignment == nil, element == "body" || element == "p" { alignment = properties.alignment }
        attributeStack.append(properties.applied(to: current))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if attributeStack.count > 1 { attributeStack.removeLast() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard attributeStack.count > 1 else { return }
        // Text between elements that only holds the file's own line breaks is not the box's text.
        let text = string.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        guard !text.isEmpty else { return }
        append(String(repeating: "\n", count: pendingLineBreaks) + text, with: attributeStack.last ?? .plain)
        pendingLineBreaks = 0
    }

    /// Line breaks of empty paragraphs at the end, in the looks the text ended with.
    func parserDidEndDocument(_ parser: XMLParser) {
        guard pendingLineBreaks > 0 else { return }
        append(String(repeating: "\n", count: pendingLineBreaks), with: runs.last?.attributes ?? attributeStack.first ?? .plain)
        pendingLineBreaks = 0
    }

    private func append(_ text: String, with attributes: PDFTextAttributes) {
        textUTF16Count += text.utf16.count
        guard textUTF16Count <= PDFTextBox.maximumTextUTF16Count, runs.count < PDFTextBox.maximumRunCount else {
            exceededLimits = true
            return
        }
        if let last = runs.last, last.attributes == attributes {
            runs[runs.count - 1].text += text
        } else {
            runs.append(PDFTextRun(text: text, attributes: attributes))
        }
    }
}
