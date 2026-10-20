import Foundation
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Fenced code blocks in the editors: their colors by language, their formatting state, and
/// the box each is drawn in.
extension MarkdownTextStyler {
    /// The colors of code blocks, for the code theme and the vault's theme.
    private var codePalette: CodePalette { CodeSyntaxColors.palette(codeTheme: configuration.codeColorTheme, noteTheme: theme) }

    /// Holds, on each highlighted line of a fenced code block, the `CodeLineState` the line
    /// starts in, as its `storedValue`. A restyle compares the state its last line ends in
    /// with the one stored on the next line, to recolor the lines after an edit that opens
    /// or closes a block comment or a string spanning lines, and only those.
    static let codeLineStateKey = NSAttributedString.Key("GraphiteCodeLineState")

    /// Colors the code lines among `spans`, block by block, in the language each block's
    /// fence names. Lines of a language Graphite does not highlight keep the code color.
    func highlightCode(in spans: [MarkdownStyleSpan], to textStorage: NSTextStorage, source: NSString, hiddenRanges: [NSRange]) {
        let codeSpans = spans.filter { span in span.style == .codeBlock && span.fencedCodeBlock != nil && NSMaxRange(span.range) <= source.length }
        var groupStart = 0
        while groupStart < codeSpans.count {
            var groupEnd = groupStart + 1
            while groupEnd < codeSpans.count, codeSpans[groupEnd].fencedCodeBlock == codeSpans[groupStart].fencedCodeBlock { groupEnd += 1 }
            if let block = codeSpans[groupStart].fencedCodeBlock, let language = CodeLanguage.named(block.language) {
                highlightLines(of: codeSpans[groupStart..<groupEnd], in: block, language: language, textStorage: textStorage, source: source, hiddenRanges: hiddenRanges)
            }
            groupStart = groupEnd
        }
    }

    /// Colors the lines of `lineSpans`, all in `block`, from the state the first starts in,
    /// found by following the block's lines above it without making tokens. Then recolors
    /// the lines after them while they were colored for another state.
    private func highlightLines(of lineSpans: ArraySlice<MarkdownStyleSpan>, in block: FencedCodeBlock, language: CodeLanguage,
                                textStorage: NSTextStorage, source: NSString, hiddenRanges: [NSRange]) {
        guard let firstSpan = lineSpans.first, let lastSpan = lineSpans.last, block.codeStart <= firstSpan.range.location else { return }
        let firstLineStart = source.lineRange(for: NSRange(location: firstSpan.range.location, length: 0)).location
        let lastLineEnd = NSMaxRange(source.lineRange(for: NSRange(location: lastSpan.range.location, length: 0)))
        guard block.codeStart <= firstLineStart, lastLineEnd <= source.length else { return }
        var units = [UInt16](repeating: 0, count: lastLineEnd - block.codeStart)
        source.getCharacters(&units, range: NSRange(location: block.codeStart, length: units.count))
        var highlighter = CodeLineHighlighter(language: language)
        let lineRanges = CodeSyntaxHighlighter.lineRanges(in: units)
        for (lineIndex, lineRange) in lineRanges.enumerated() {
            // The empty range after the last line break starts the line after the block's.
            if lineRange.lowerBound == units.count, lineIndex > 0 { break }
            let lineStart = block.codeStart + lineRange.lowerBound
            let codeRange = Self.codeRange(of: lineRange, in: units, quoteDepth: block.quoteDepth)
            guard lineStart >= firstLineStart else {
                highlighter.advance(pastLine: codeRange, of: units)
                continue
            }
            let lineEnd = lineIndex + 1 < lineRanges.count ? block.codeStart + lineRanges[lineIndex + 1].lowerBound : lastLineEnd
            textStorage.addAttribute(Self.codeLineStateKey, value: highlighter.state.storedValue, range: NSRange(location: lineStart, length: lineEnd - lineStart))
            for token in highlighter.tokens(inLine: codeRange, of: units) {
                textStorage.addAttribute(.foregroundColor, value: codePalette.color(for: token.kind), range: token.range.shifted(by: block.codeStart))
            }
        }
        recolorLinesColoredForAnotherState(after: lastLineEnd, entering: highlighter, in: block, textStorage: textStorage, source: source, hiddenRanges: hiddenRanges)
    }

    /// Recolors the block's lines from `location` on while the state each starts in differs
    /// from the one stored on it: typing `/*` colors the code after it as a comment, up to
    /// a line already colored for that state. A line without a stored state ends the block.
    private func recolorLinesColoredForAnotherState(after location: Int, entering startingHighlighter: CodeLineHighlighter, in block: FencedCodeBlock,
                                                    textStorage: NSTextStorage, source: NSString, hiddenRanges: [NSRange]) {
        var highlighter = startingHighlighter
        var lineStart = location
        let codeColor = codePalette.text
        while lineStart < source.length,
              let storedValue = textStorage.attribute(Self.codeLineStateKey, at: lineStart, effectiveRange: nil) as? Int,
              storedValue != highlighter.state.storedValue {
            let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
            var units = [UInt16](repeating: 0, count: lineRange.length)
            source.getCharacters(&units, range: lineRange)
            let contentLength = CodeSyntaxHighlighter.lineRanges(in: units).first?.upperBound ?? units.count
            let codeRange = Self.codeRange(of: 0..<contentLength, in: units, quoteDepth: block.quoteDepth)
            textStorage.addAttribute(Self.codeLineStateKey, value: highlighter.state.storedValue, range: lineRange)
            let tokens = highlighter.tokens(inLine: codeRange, of: units)
            // Hidden lines (a folded section, a callout drawn as a view) stay hidden.
            if !hiddenRanges.contains(where: { hiddenRange in NSIntersectionRange(hiddenRange, lineRange).length > 0 }) {
                textStorage.addAttribute(.foregroundColor, value: codeColor, range: NSRange(location: lineStart, length: contentLength))
                for token in tokens {
                    textStorage.addAttribute(.foregroundColor, value: codePalette.color(for: token.kind), range: token.range.shifted(by: lineStart))
                }
            }
            lineStart = NSMaxRange(lineRange)
        }
    }

    /// The unquoted fenced code block whose lines, fences included, `selection` starts or
    /// ends on. Prose lines are answered from their first character and the block context,
    /// without scanning them.
    func fencedCodeBlock(touchedBy selection: NSRange, in textStorage: NSTextStorage, source: NSString,
                         blockContextCheckpoints: MarkdownBlockContextCheckpoints?) -> FencedCodeBlock? {
        guard textStorage.length == source.length else { return nil }
        let space = UInt16(UInt8(ascii: " ")), fenceCharacters: Set<UInt16> = [UInt16(UInt8(ascii: "`")), UInt16(UInt8(ascii: "~"))]
        for location in Set([selection.location, NSMaxRange(selection)]) where location <= source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            var firstVisible = lineRange.location
            while firstVisible < NSMaxRange(lineRange), source.character(at: firstVisible) == space { firstVisible += 1 }
            let mayBeFence = firstVisible < NSMaxRange(lineRange) && fenceCharacters.contains(source.character(at: firstVisible))
            let context = blockContextCheckpoints?.blockContext(atLineStart: lineRange.location, in: textStorage, source: source)
                ?? MarkdownStyleScanner.blockContext(atLineContaining: lineRange.location, in: source)
            guard mayBeFence || context == .fencedCode else { continue }
            let lineStart = NSRange(location: lineRange.location, length: 0)
            let spans = blockContextCheckpoints?.spans(in: textStorage, source: source, range: lineStart) ?? MarkdownStyleScanner.spans(in: source, range: lineStart)
            let block = spans.first { span in span.fencedCodeBlock != nil && span.range.location >= lineRange.location && span.range.location <= NSMaxRange(lineRange) }?
                .fencedCodeBlock
            if let block, block.quoteDepth == 0 { return block }
        }
        return nil
    }

    /// A code block's opening fence's line and its closing one's, when it has one.
    static func fenceLineRanges(of block: FencedCodeBlock, in source: NSString) -> [NSRange] {
        guard block.codeStart > 0, block.codeStart <= source.length else { return [] }
        var ranges = [source.lineRange(for: NSRange(location: block.codeStart - 1, length: 0))]
        let codeEnd = NSMaxRange(block.codeRange(in: source))
        if codeEnd < source.length { ranges.append(source.lineRange(for: NSRange(location: codeEnd, length: 0))) }
        return ranges
    }

    /// What the lines of the code blocks drawn together share.
    private struct CodeBoxStyles {
        let palette: CodePalette
        let codeFont: PlatformFont
        let labelFont: PlatformFont
        let padding: CGFloat
        let cornerRadius: CGFloat
        let indentationWidth: Int
        /// Of a line of code, of a hidden fence over the code (with room for the language
        /// label, or without it) and of a hidden fence under it.
        let lineStyle: NSParagraphStyle
        let labeledOpeningStyle: NSParagraphStyle
        let openingPaddingStyle: NSParagraphStyle
        let closingPaddingStyle: NSParagraphStyle
    }

    /// One line of a code block, fence or code, as `drawCodeBlocksAsBoxes` meets it.
    private struct CodeBoxLine {
        let span: MarkdownStyleSpan
        let block: FencedCodeBlock
        let lineRange: NSRange
        let isFence: Bool
        let isOpening: Bool
        let showsFence: Bool
    }

    /// Draws each fenced code block in `spans` as one box (`CodeBlockLineDecoration`): its
    /// lines are inset from the box's edges and set without the space between paragraphs,
    /// and in Live Preview its fences are hidden, unless the selection starts or ends in it,
    /// leaving short lines that pad the box above and below. Quoted code (in a callout)
    /// keeps the plain background, inside its quote's bars.
    func drawCodeBlocksAsBoxes(in spans: [MarkdownStyleSpan], to textStorage: NSTextStorage, source: NSString, revealedMarkup: RevealedMarkup?,
                               fonts: MarkdownStyleFonts, blockContextCheckpoints: MarkdownBlockContextCheckpoints?) {
        let styles = codeBoxStyles(codeFont: fonts.codeFont)
        /// The block whose fences show, found once, when a fence is styled.
        var codeBlockShowingFences: FencedCodeBlock??
        for span in spans {
            guard let block = span.fencedCodeBlock, block.quoteDepth == 0, span.style == .codeBlock || span.style == .syntaxMarker,
                  span.range.location <= source.length else { continue }
            let lineRange = source.lineRange(for: NSRange(location: span.range.location, length: 0))
            guard lineRange.length > 0, NSMaxRange(span.range) <= source.length else { continue }
            let isFence = span.style == .syntaxMarker
            var showsFence = true
            if isFence, configuration.mode == .livePreview {
                if codeBlockShowingFences == nil {
                    codeBlockShowingFences = .some(revealedMarkup.flatMap { markup in
                        fencedCodeBlock(touchedBy: markup.selection, in: textStorage, source: source, blockContextCheckpoints: blockContextCheckpoints)
                    })
                }
                showsFence = codeBlockShowingFences??.codeStart == block.codeStart
            }
            let line = CodeBoxLine(span: span, block: block, lineRange: lineRange, isFence: isFence,
                                   isOpening: isFence && span.range.location < block.codeStart, showsFence: showsFence)
            styleCodeBoxLine(line, styles: styles, in: textStorage, source: source)
        }
    }

    private func codeBoxStyles(codeFont: PlatformFont) -> CodeBoxStyles {
        let padding: CGFloat = 14
        let palette = codePalette
        let labelFont = PlatformFont.systemFont(ofSize: max(codeFont.pointSize * 0.8, 10))
        func paragraphStyle(fixedHeight: CGFloat?) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = padding
            style.headIndent = padding
            style.tailIndent = -padding
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            if let fixedHeight {
                style.minimumLineHeight = fixedHeight
                style.maximumLineHeight = fixedHeight
            } else {
                style.lineSpacing = codeFont.pointSize * 0.35
            }
            return style
        }
        // A hidden fence leaves a short line that pads the box; above the code, room for the language.
        let edgePadding: CGFloat = 9
        return CodeBoxStyles(
            palette: palette, codeFont: codeFont, labelFont: labelFont, padding: padding,
            cornerRadius: CodeSyntaxColors.blockCornerRadius(theme: theme), indentationWidth: max(1, configuration.editingBehavior.tabSize),
            lineStyle: paragraphStyle(fixedHeight: nil),
            labeledOpeningStyle: paragraphStyle(fixedHeight: (labelFont.ascender - labelFont.descender + edgePadding).rounded()),
            openingPaddingStyle: paragraphStyle(fixedHeight: edgePadding), closingPaddingStyle: paragraphStyle(fixedHeight: edgePadding))
    }

    /// Colors, spaces and decorates one line of a code block as part of its box.
    private func styleCodeBoxLine(_ line: CodeBoxLine, styles: CodeBoxStyles, in textStorage: NSTextStorage, source: NSString) {
        var style = styles.lineStyle
        if !line.isFence {
            textStorage.addAttribute(.foregroundColor, value: styles.palette.text, range: line.span.range)
        } else if line.showsFence {
            textStorage.addAttribute(.font, value: styles.codeFont, range: line.span.range)
            textStorage.addAttribute(.foregroundColor, value: styles.palette.quietText, range: line.span.range)
        } else {
            conceal(line.span.range, in: textStorage)
            style = !line.isOpening ? styles.closingPaddingStyle : line.block.language.isEmpty ? styles.openingPaddingStyle : styles.labeledOpeningStyle
        }
        textStorage.removeAttribute(.backgroundColor, range: line.lineRange)
        textStorage.addAttribute(.paragraphStyle, value: style, range: line.lineRange)
        textStorage.addAttribute(ConcealedReplacement.codeBlockKey, value: codeBoxDecoration(for: line, styles: styles, source: source), range: line.lineRange)
    }

    private func codeBoxDecoration(for line: CodeBoxLine, styles: CodeBoxStyles, source: NSString) -> CodeBlockLineDecoration {
        let label = line.isOpening && !line.showsFence && !line.block.language.isEmpty ? line.block.language : nil
        let guideOffsets = line.isFence ? [] : Self.indentationGuideOffsets(of: line.lineRange, in: source, indentationWidth: styles.indentationWidth)
        return CodeBlockLineDecoration(
            background: styles.palette.background, cornerRadius: styles.cornerRadius, isFirstLine: line.isOpening, isLastLine: line.isFence && !line.isOpening,
            languageLabel: label, labelColor: styles.palette.quietText, labelFont: styles.labelFont, horizontalPadding: styles.padding,
            guideOffsets: guideOffsets, guideColor: styles.palette.guide, border: styles.palette.border)
    }

    /// The fence lines of the code blocks the selection enters or leaves when the revealed
    /// markup goes from `previousMarkup` to `revealedMarkup`: a block's fences show while the
    /// selection touches the block, however far from the selection they are. Found before any
    /// restyling, which changes what the scanner's checkpoints say about the text.
    func fenceLinesOfCodeBlocksTouched(by previousMarkup: RevealedMarkup?, and revealedMarkup: RevealedMarkup?, in textStorage: NSTextStorage,
                                       source: NSString, blockContextCheckpoints: MarkdownBlockContextCheckpoints?) -> [NSRange] {
        let previousCodeBlock = previousMarkup.flatMap { markup in
            fencedCodeBlock(touchedBy: markup.selection, in: textStorage, source: source, blockContextCheckpoints: blockContextCheckpoints)
        }
        let codeBlock = revealedMarkup.flatMap { markup in
            fencedCodeBlock(touchedBy: markup.selection, in: textStorage, source: source, blockContextCheckpoints: blockContextCheckpoints)
        }
        guard previousCodeBlock?.codeStart != codeBlock?.codeStart else { return [] }
        return [previousCodeBlock, codeBlock].compactMap { block in block }.flatMap { block in Self.fenceLineRanges(of: block, in: source) }
    }

    /// Where a code line's indentation guides go, counted from the line's start: at the
    /// start of each level of its leading tabs and spaces (`indentationWidth` columns, a tab
    /// reaching the next level), once the level is filled. A blank line has none.
    static func indentationGuideOffsets(of lineRange: NSRange, in source: NSString, indentationWidth: Int) -> [Int] {
        let space = UInt16(UInt8(ascii: " ")), tab = UInt16(UInt8(ascii: "\t"))
        var levelStarts: [(offset: Int, column: Int)] = []
        var column = 0
        var offset = 0
        while offset < lineRange.length {
            let unit = source.character(at: lineRange.location + offset)
            guard unit == space || unit == tab else { break }
            if column % indentationWidth == 0 { levelStarts.append((offset, column)) }
            column = unit == tab ? column + indentationWidth - column % indentationWidth : column + 1
            offset += 1
        }
        guard offset < lineRange.length, let scalar = Unicode.Scalar(source.character(at: lineRange.location + offset)),
              !CharacterSet.newlines.contains(scalar) else { return [] }
        return levelStarts.filter { levelStart in levelStart.column + indentationWidth <= column }.map(\.offset)
    }

    /// The part of a code line after the quote markers its block repeats (`> ` in a callout).
    private static func codeRange(of lineRange: Range<Int>, in units: [UInt16], quoteDepth: Int) -> Range<Int> {
        var start = lineRange.lowerBound
        for _ in 0..<quoteDepth {
            while start < lineRange.upperBound, units[start] == CodeUnitsForQuotes.space || units[start] == CodeUnitsForQuotes.tab { start += 1 }
            guard start < lineRange.upperBound, units[start] == CodeUnitsForQuotes.greaterThan else { break }
            start += 1
            if start < lineRange.upperBound, units[start] == CodeUnitsForQuotes.space { start += 1 }
        }
        return start..<lineRange.upperBound
    }

    private enum CodeUnitsForQuotes {
        static let space = UInt16(UInt8(ascii: " "))
        static let tab = UInt16(UInt8(ascii: "\t"))
        static let greaterThan = UInt16(UInt8(ascii: ">"))
    }
}
