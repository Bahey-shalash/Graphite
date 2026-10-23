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
        /// A fenced block in a language a community plugin draws (`registerMarkdownCodeBlockProcessor`),
        /// with the code between its fences in `markdown`.
        case pluginCodeBlock(language: String)
        /// A fenced block whose whole info text is `mermaid`, in any case, that no community plugin draws: a diagram,
        /// as reading view finds it (`NotePreviewBlock.mermaidDiagram`), with the code between its fences in `markdown`.
        case mermaidDiagram
    }
    public let kind: Kind
    /// Whole lines, including the final line break when there is one.
    public let range: NSRange
    /// The Markdown to render for tables, math blocks, and callouts.
    public let markdown: String

    /// The same block, found in text that starts `distance` characters later, as when
    /// some lines are scanned on their own.
    public func offset(by distance: Int) -> LivePreviewBlock {
        LivePreviewBlock(kind: kind, range: NSRange(location: range.location + distance, length: range.length), markdown: markdown)
    }
}

public enum LivePreviewBlockScanner {
    /// - Parameter pluginCodeBlockLanguages: Languages community plugins draw. As in Obsidian,
    ///   a fenced block in one of them is drawn by its plugin in Live Preview too, `mermaid` included.
    public static func blocks(in text: NSString, pluginCodeBlockLanguages: Set<String> = []) -> [LivePreviewBlock] {
        var blocks: [LivePreviewBlock] = []
        let frontmatter = frontmatterBlock(in: text)
        if let frontmatter { blocks.append(frontmatter) }
        let frontmatterLength = frontmatter?.range.length ?? 0
        let lines = lines(in: text, from: frontmatterLength)
        let mathLines = DisplayMathLines(lines.map(\.content))
        var listItems = ListItemContainers()
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
            if let (fence, info, _) = listItems.fenceOpening(of: content) {
                let language = info.lowercased()
                var closingIndex = lineIndex + 1
                while closingIndex < lines.count && !MarkdownFenceSyntax.closes(fence, lines[closingIndex].content.trimmingCharacters(in: .whitespaces)) { closingIndex += 1 }
                let lastIndex = min(closingIndex, lines.count - 1)
                // An unclosed fence runs to the end of the note, as in CommonMark and reading view.
                let lastContentIndex = closingIndex < lines.count ? closingIndex - 1 : lastIndex
                // Joined only for a block: most fences are code that stays text.
                func code() -> String { lineIndex + 1 <= lastContentIndex ? markdown(lineIndex + 1, lastContentIndex) : "" }
                // The language a plugin draws is read only while plugins draw some.
                let pluginLanguage = pluginCodeBlockLanguages.isEmpty ? "" : MarkdownFenceSyntax.language(ofInfo: info)
                if language == "base" {
                    let yaml = code()
                    blocks.append(LivePreviewBlock(kind: .baseDefinition(yaml), range: span(lineIndex, lastIndex), markdown: yaml))
                } else if !pluginLanguage.isEmpty, pluginCodeBlockLanguages.contains(pluginLanguage) {
                    blocks.append(LivePreviewBlock(kind: .pluginCodeBlock(language: pluginLanguage), range: span(lineIndex, lastIndex), markdown: code()))
                } else if language == "mermaid" {
                    blocks.append(LivePreviewBlock(kind: .mermaidDiagram, range: span(lineIndex, lastIndex), markdown: code()))
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
            if MarkdownQuoteSyntax.isCalloutHeader(content) {
                var lastIndex = lineIndex
                while lastIndex + 1 < lines.count && lines[lastIndex + 1].content.hasPrefix(">") { lastIndex += 1 }
                blocks.append(LivePreviewBlock(kind: .callout, range: span(lineIndex, lastIndex), markdown: markdown(lineIndex, lastIndex)))
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            // A table needs a header row and a delimiter row, like GFM; its outer pipes may
            // be left out (`a | b` over `--|--`), as Obsidian and GFM allow.
            if lineIndex + 1 < lines.count, MarkdownTableSyntax.startsTable(header: trimmedContent, delimiter: lines[lineIndex + 1].content) {
                let hasOuterPipes = trimmedContent.hasPrefix("|")
                var lastIndex = lineIndex + 1
                while lastIndex + 1 < lines.count {
                    let row = lines[lastIndex + 1].content.trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") || (!hasOuterPipes && !row.isEmpty && row.contains("|")) else { break }
                    lastIndex += 1
                }
                blocks.append(LivePreviewBlock(kind: .table, range: span(lineIndex, lastIndex), markdown: markdown(lineIndex, lastIndex)))
                lineIndex = lastIndex + 1
                lineIndexAfterBlock = lineIndex
                continue
            }
            if let embed = EmbedLocator.standaloneEmbed(onLine: content) {
                // A web image is not a vault file, so it gets no embed widget and stays
                // Markdown, as reading view leaves it.
                if !embed.isRemoteImage {
                    blocks.append(LivePreviewBlock(kind: .embed(embed), range: lines[lineIndex].range, markdown: content))
                }
            } else if MarkdownHeadingSyntax.level(of: content) == nil,
                      let opening = mathLines.opening(at: lineIndex), let closingLineIndex = opening.closingLineIndex {
                // A formula opened after other text (`- $$` in a list item, `Energy is $$`)
                // stays in its paragraph, closing line included, so that line does not
                // start a formula of its own.
                lineIndex = closingLineIndex + 1
                continue
            } else if MarkdownListSyntax.isThematicBreak(content), lineIndex == 0 || lineIndex == lineIndexAfterBlock
                        || MarkdownHeadingSyntax.setextHeadingLevel(ofLine: lines[lineIndex - 1].content, nextLine: content) == nil {
                // Directly after paragraph text, `---` underlines a heading instead of
                // drawing a rule; after a heading, a list item or a blank line it is a rule.
                blocks.append(LivePreviewBlock(kind: .horizontalRule, range: lines[lineIndex].range, markdown: content))
            }
            lineIndex += 1
        }
        return blocks
    }

    /// The leading frontmatter alone, for an editor that renders only the properties. It
    /// reads the start of the note, not every line.
    public static func frontmatterBlock(in text: NSString) -> LivePreviewBlock? {
        let frontmatterLength = FrontmatterLocator.length(in: text)
        guard frontmatterLength > 0 else { return nil }
        return LivePreviewBlock(kind: .frontmatter, range: NSRange(location: 0, length: frontmatterLength), markdown: text.substring(to: frontmatterLength))
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

    /// Where the one fenced block in `language` holding `code` is in `text`: its zero-based
    /// first line (the opening fence) and the lines it spans. Nil when no block or more than
    /// one matches, since a plugin editing "its" lines must not reach another block.
    public static func onlyPluginCodeBlock(language: String, code: String, in text: String) -> (firstLine: Int, lineCount: Int)? {
        let source = text as NSString
        let matches = blocks(in: source, pluginCodeBlockLanguages: [language]).filter { block in
            block.kind == .pluginCodeBlock(language: language) && block.markdown == code
        }
        guard matches.count == 1, let block = matches.first else { return nil }
        // Lines end as `lines(in:)` ends them: at `\n`, `\r\n`, or a lone `\r`, which a
        // note saved by an old Mac app has.
        func lineNumber(at location: Int) -> Int {
            var lines = 0
            var index = 0
            while index < location {
                let unit = source.character(at: index)
                if unit == 0x0D {
                    lines += 1
                    if index + 1 < location, source.character(at: index + 1) == 0x0A { index += 1 }
                } else if unit == 0x0A {
                    lines += 1
                }
                index += 1
            }
            return lines
        }
        let firstLine = lineNumber(at: block.range.location)
        let lastLine = lineNumber(at: max(block.range.location, NSMaxRange(block.range) - 1))
        return (firstLine, lastLine - firstLine + 1)
    }
}
