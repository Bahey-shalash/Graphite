import Foundation

/// Links to a PDF page and quotes from a PDF, written as Obsidian writes them: a link shows
/// the file and page (`[[Paper.pdf#page=3|Paper, p.3]]`) and a quote is a Markdown quote
/// followed by that link.
public enum PDFCitation {
    /// The link text a note gets for a page of a PDF.
    /// - Parameters:
    ///   - linkTarget: The PDF as the vault's link format names it (see `LinkCompletion.linkTarget`).
    ///   - displayName: The PDF's name without extension, shown in the link.
    ///   - pageNumber: One-based.
    public static func pageLink(linkTarget: String, displayName: String, pageNumber: Int, usesWikilinks: Bool) -> String {
        let label = "\(displayName), p.\(pageNumber)"
        if usesWikilinks { return "[[\(linkTarget)#page=\(pageNumber)|\(label)]]" }
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        let destination = linkTarget.addingPercentEncoding(withAllowedCharacters: unreserved) ?? linkTarget
        return "[\(escapedLabel(label))](\(destination)#page=\(pageNumber))"
    }

    /// Selected PDF text as a Markdown quote, followed by the link to its page.
    public static func quote(_ selectedText: String, link: String) -> String {
        let paragraphs = readableParagraphs(of: selectedText)
        let quotedLines = paragraphs.enumerated().flatMap { index, paragraph in
            index == 0 ? ["> " + paragraph] : [">", "> " + paragraph]
        }
        return quotedLines.joined(separator: "\n") + "\n\n" + link
    }

    /// Text selected in a PDF comes with the page's line breaks and hyphenation. Lines are
    /// joined into paragraphs, a word split by a hyphen at a line end is joined again, and
    /// blank lines separate paragraphs.
    static func readableParagraphs(of text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        var paragraphs: [String] = []
        var current = ""
        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !current.isEmpty { paragraphs.append(current); current = "" }
                continue
            }
            if current.isEmpty {
                current = line
            } else if current.hasSuffix("-"), let first = line.first, let beforeHyphen = current.dropLast().last, beforeHyphen.isLetter || beforeHyphen.isNumber {
                // "hyphen-" + "ation" was one word broken at the line's end; "1990-" + "2000"
                // and "Mid-" + "Atlantic" keep their hyphen. A compound such as "well-known"
                // broken at its hyphen cannot be told from hyphenation and loses it.
                current = first.isLowercase && beforeHyphen.isLetter ? String(current.dropLast()) + line : current + line
            } else {
                current += " " + line
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.map { paragraph in
            paragraph.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }
    }

    private static func escapedLabel(_ label: String) -> String {
        label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
