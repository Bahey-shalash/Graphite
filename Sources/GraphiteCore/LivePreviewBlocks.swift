import Foundation

/// A region of note source that Live Preview replaces with a rendered view while the
/// cursor is elsewhere, as Obsidian does for properties, tables, math, and embeds.
public struct LivePreviewBlock: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case frontmatter
        case table
        case mathBlock
        case embed(EmbedReference)
        case baseDefinition(String)
        case horizontalRule
        /// A `> [!type]` callout with its quoted body.
        case callout
    }
    public let kind: Kind
    /// Whole lines, including the final line break when there is one.
    public let range: NSRange
    /// The Markdown to render for tables, math blocks, and callouts.
    public let markdown: String
}

public enum LivePreviewBlockScanner {
    private static let standaloneEmbedPattern = try? NSRegularExpression(pattern: "^[ \\t]*(!\\[\\[[^\\]\\n]+\\]\\]|!\\[[^\\]\\n]*\\]\\([^)\\n]+\\))[ \\t]*$")
    private static let calloutHeaderPattern = try? NSRegularExpression(pattern: "^>[ \\t]?\\[![A-Za-z0-9_-]+\\][+-]?")
    private static let horizontalRulePattern = try? NSRegularExpression(pattern: "^ {0,3}(?:(?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,})$")

    public static func blocks(in text: NSString) -> [LivePreviewBlock] {
        var blocks: [LivePreviewBlock] = []
        let frontmatterLength = FrontmatterLocator.length(in: text)
        if frontmatterLength > 0 {
            blocks.append(LivePreviewBlock(kind: .frontmatter, range: NSRange(location: 0, length: frontmatterLength), markdown: text.substring(to: frontmatterLength)))
        }
        let lines = lines(in: text, from: frontmatterLength)
        let mathLines = DisplayMathLines(lines.map(\.content))
        var lineIndex = 0
        // The line after a table, fence, math block or callout, which cannot be a
        // paragraph line that a following `---` underlines.
        var lineIndexAfterBlock = -1
        func span(_ firstIndex: Int, _ lastIndex: Int) -> NSRange {
            NSRange(location: lines[firstIndex].range.location, length: NSMaxRange(lines[lastIndex].range) - lines[firstIndex].range.location)
        }
        func markdown(_ firstIndex: Int, _ lastIndex: Int) -> String {
            lines[firstIndex...lastIndex].map(\.content).joined(separator: "\n")
        }
        while lineIndex < lines.count {
            let content = lines[lineIndex].content
            let trimmedContent = content.trimmingCharacters(in: .whitespaces)
            let fullRange = NSRange(location: 0, length: (content as NSString).length)
            if let (fence, info) = CodeFence.opening(trimmedContent) {
                let language = info.lowercased()
                var closingIndex = lineIndex + 1
                while closingIndex < lines.count && !CodeFence.closes(fence, lines[closingIndex].content.trimmingCharacters(in: .whitespaces)) { closingIndex += 1 }
                let lastIndex = min(closingIndex, lines.count - 1)
                // An unclosed fence runs to the end of the note, as in CommonMark and reading view.
                if language == "base" {
                    let lastContentIndex = closingIndex < lines.count ? closingIndex - 1 : lastIndex
                    let yaml = lineIndex + 1 <= lastContentIndex ? markdown(lineIndex + 1, lastContentIndex) : ""
                    blocks.append(LivePreviewBlock(kind: .baseDefinition(yaml), range: span(lineIndex, lastIndex), markdown: yaml))
                }
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            // Display math is a block of its own, found as reading view finds it, so a
            // closing `$$` is never taken for a new opener.
            if trimmedContent.hasPrefix("$$") {
                let opening = mathLines.opening(at: lineIndex)
                if let opening, opening.isAtLineStart {
                    let lastIndex = opening.closingLineIndex ?? lines.count - 1
                    blocks.append(LivePreviewBlock(kind: .mathBlock, range: span(lineIndex, lastIndex), markdown: markdown(lineIndex, lastIndex)))
                    lineIndex = lastIndex + 1
                    lineIndexAfterBlock = lineIndex
                    continue
                }
                // A closed `$$…$$` alone on its line is display math too. With text after
                // it (`$$E=mc^2$$ where…`) it is inline math in a paragraph.
                if opening == nil, trimmedContent.hasSuffix("$$") {
                    blocks.append(LivePreviewBlock(kind: .mathBlock, range: lines[lineIndex].range, markdown: content))
                    lineIndex += 1
                    lineIndexAfterBlock = lineIndex
                    continue
                }
            }
            if calloutHeaderPattern?.firstMatch(in: content, range: fullRange) != nil {
                var lastIndex = lineIndex
                while lastIndex + 1 < lines.count && lines[lastIndex + 1].content.hasPrefix(">") { lastIndex += 1 }
                blocks.append(LivePreviewBlock(kind: .callout, range: span(lineIndex, lastIndex), markdown: markdown(lineIndex, lastIndex)))
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            // A table needs a header row and a delimiter row, like GFM.
            if trimmedContent.hasPrefix("|"), lineIndex + 1 < lines.count, isTableDelimiterRow(lines[lineIndex + 1].content) {
                var lastIndex = lineIndex + 1
                while lastIndex + 1 < lines.count && lines[lastIndex + 1].content.trimmingCharacters(in: .whitespaces).hasPrefix("|") { lastIndex += 1 }
                blocks.append(LivePreviewBlock(kind: .table, range: span(lineIndex, lastIndex), markdown: markdown(lineIndex, lastIndex)))
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            if standaloneEmbedPattern?.firstMatch(in: content, range: fullRange) != nil,
               let embed = EmbedLocator.embed(at: (content as NSString).range(of: "!").location + 1, in: content as NSString) {
                if !isRemoteImage(embed) {
                    blocks.append(LivePreviewBlock(kind: .embed(embed), range: lines[lineIndex].range, markdown: content))
                }
            } else if MarkdownEditing.headingLevel(of: content) == nil,
                      let opening = mathLines.opening(at: lineIndex), let closingLineIndex = opening.closingLineIndex {
                // A formula opened after other text (`- $$` in a list item, `Energy is $$`)
                // stays in its paragraph, closing line included, so that line does not
                // start a formula of its own.
                lineIndex = closingLineIndex + 1
                continue
            } else if horizontalRulePattern?.firstMatch(in: content, range: fullRange) != nil,
                      MarkdownStyleScanner.setextUnderlineLevel(content) == nil || lineIndex == 0 || lineIndex == lineIndexAfterBlock
                        || !MarkdownStyleScanner.isParagraphText(lines[lineIndex - 1].content) {
                // Directly after paragraph text, `---` underlines a heading instead of
                // drawing a rule; after a heading, a list item or a blank line it is a rule.
                blocks.append(LivePreviewBlock(kind: .horizontalRule, range: lines[lineIndex].range, markdown: content))
            }
            lineIndex += 1
        }
        return blocks
    }

    /// Lines where CommonMark and reading view end them: at "\n", "\r\n" or a lone "\r".
    /// Each range includes its line break; the content excludes it, so a Windows note's
    /// "\r" never reaches fence, math or table detection. U+2028 and U+2029 stay inside a
    /// line, as reading view keeps them.
    private static func lines(in text: NSString, from start: Int) -> [(range: NSRange, content: String)] {
        var lines: [(range: NSRange, content: String)] = []
        var lineStart = start
        while lineStart < text.length {
            let breakLocation = text.rangeOfCharacter(from: lineBreakCharacters, options: .literal, range: NSRange(location: lineStart, length: text.length - lineStart)).location
            let contentEnd = breakLocation == NSNotFound ? text.length : breakLocation
            var nextLineStart = contentEnd
            if breakLocation != NSNotFound {
                nextLineStart = contentEnd + 1
                let isCRLF = text.character(at: contentEnd) == carriageReturn && nextLineStart < text.length && text.character(at: nextLineStart) == lineFeed
                if isCRLF { nextLineStart += 1 }
            }
            lines.append((NSRange(location: lineStart, length: nextLineStart - lineStart), text.substring(with: NSRange(location: lineStart, length: contentEnd - lineStart))))
            lineStart = nextLineStart
        }
        return lines
    }

    private static let lineBreakCharacters = CharacterSet(charactersIn: "\r\n")
    private static let lineFeed = UInt16(UInt8(ascii: "\n"))
    private static let carriageReturn = UInt16(UInt8(ascii: "\r"))

    /// A web image (`![](https://…)`) is not a vault file, so it gets no embed widget and
    /// stays Markdown, as reading view leaves it. Only the destination counts, not a title
    /// written after it.
    private static func isRemoteImage(_ embed: EmbedReference) -> Bool {
        let destination = embed.target.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? embed.target
        return !embed.isWiki && URL(string: destination)?.scheme != nil
    }

    private static func isTableDelimiterRow(_ line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.contains("-") else { return false }
        return trimmedLine.allSatisfy { character in "|-: \t".contains(character) }
    }
}
