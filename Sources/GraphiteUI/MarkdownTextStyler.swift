import Foundation
import SwiftUI
import GraphiteCore
import Textual
#if canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

/// How the Markdown editor shows a note.
struct EditorConfiguration: Equatable {
    var mode: EditingMode = .livePreview
    var usesReadableLineLength = true
    var textSize: Double = 17
    /// The vault's text and monospace fonts (Settings › Appearance › Font).
    var typography = NoteTypography.standard
    /// The vault's Obsidian theme, or nil for Graphite's own look.
    var theme: NoteThemeStyle?
    var usesSpellChecking = true
    /// Whether a fenced code block is formatted when the cursor leaves it after an edit
    /// (`CodeFormatter`).
    var formatsCodeBlocks = true
    var colorsEnabled = true
    var paletteHexByName: [String: String] = [:]
    /// Pairing, list continuation and indentation, from the vault's editor settings.
    var editingBehavior = EditingBehavior()
    var accentHex = GraphiteTheme.defaultAccentHex
    /// The note's name shown as a large title above the text, or nil.
    var inlineTitle: String?
}

/// Obsidian's inline title: the note's name, larger than a first-level heading.
enum InlineTitleStyle {
    static let fontScale = 1.75

    /// The theme's inline title size, else Graphite's, as a multiple of the text size.
    static func fontScale(theme: NoteThemeStyle?) -> Double { theme?.inlineTitleScale ?? fontScale }

    /// The theme's inline title font where `appearance.json` names no text font, else the
    /// text font; the theme's weight, else semibold.
    @MainActor
    static func font(textSize: Double, typography: NoteTypography, theme: NoteThemeStyle?) -> PlatformFont {
        let size = CGFloat(textSize * fontScale(theme: theme))
        let weight = theme?.inlineTitleWeight ?? .semibold
        if !typography.usesAppearanceTextFont, let family = theme?.inlineTitleFamily { return NoteTypography.font(family, size: size, weight: weight) }
        return typography.textFont(ofSize: size, weight: weight)
    }

    static func swiftUIFont(textSize: Double, typography: NoteTypography, theme: NoteThemeStyle?) -> Font {
        let size = textSize * fontScale(theme: theme)
        let weight = ObsidianHeadingStyle.swiftUIWeight(theme?.inlineTitleWeight ?? .semibold)
        if !typography.usesAppearanceTextFont, let family = theme?.inlineTitleFamily { return NoteTypography.swiftUIFont(family, size: size).weight(weight) }
        return typography.textSwiftUIFont(size: size).weight(weight)
    }
}

/// Heading sizes and weight shared by Live Preview, Source mode and Reading view, so a
/// heading keeps its size when a note switches between reading and writing. Restrained,
/// as in Obsidian's Minimal theme: semibold rather than bold, with a gentle step between
/// levels.
enum HeadingTypography {
    /// Multiples of the note's text size, from a first-level heading to a sixth.
    static let fontScales: [CGFloat] = [1.6, 1.4, 1.25, 1.12, 1.05, 1.0]

    static func fontScale(level: Int) -> CGFloat {
        fontScales[min(max(level, 1), fontScales.count) - 1]
    }

    /// A heading's size as a multiple of the text size: the theme's, else Graphite's.
    static func fontScale(level: Int, theme: NoteThemeStyle?) -> CGFloat {
        theme?.headingScales[min(max(level, 1), 6) - 1].map { scale in CGFloat(min(max(scale, 0.75), 3)) } ?? fontScale(level: level)
    }

    static func weight(level: Int, theme: NoteThemeStyle?) -> PlatformFont.Weight {
        theme?.headingWeights[min(max(level, 1), 6) - 1] ?? .semibold
    }

    /// The heading's font: the theme's heading font unless `appearance.json` names a text
    /// font (which wins, as in Obsidian), else the text font; the theme's size and weight.
    @MainActor
    static func font(level: Int, textSize: CGFloat, typography: NoteTypography, theme: NoteThemeStyle?) -> PlatformFont {
        let index = min(max(level, 1), 6) - 1
        let size = textSize * fontScale(level: level, theme: theme)
        let weight = weight(level: level, theme: theme)
        var font: PlatformFont
        if !typography.usesAppearanceTextFont, let family = theme?.headingFamilies[index] {
            font = NoteTypography.font(family, size: size, weight: weight)
        } else {
            font = typography.textFont(ofSize: size, weight: weight)
        }
        if theme?.headingItalic[index] == true {
            #if canImport(UIKit)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) { font = UIFont(descriptor: descriptor, size: size) }
            #else
            font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic)), size: size) ?? font
            #endif
        }
        return font
    }
}

/// A region Live Preview draws as a rendered view: its source is concealed and the space
/// the view needs is reserved after its last line.
struct ConcealedBlock: Equatable {
    let range: NSRange
    let reservedHeight: CGFloat
}

/// Markup Live Preview shows as something else: a bullet for `-`, a checkbox for `[ ]`,
/// and " > " for the `#` in `[[Note#Heading]]`. The characters stay in the text, invisible,
/// and `ConcealedReplacementLayoutFragment` draws the replacement over them.
enum ConcealedReplacement: String {
    case bullet, uncheckedTask, checkedTask, subpathSeparator, inlineMath, quoteBar

    static let attributeKey = NSAttributedString.Key("GraphiteConcealedReplacement")
    static let colorAttributeKey = NSAttributedString.Key("GraphiteConcealedReplacementColor")
    /// Holds the `InlineMathLayout` of an `inlineMath` replacement.
    static let mathAttributeKey = NSAttributedString.Key("GraphiteConcealedReplacementMath")
    static let subpathSeparatorText = " > "
    /// A theme's shapes Live Preview draws behind or around text (theme Phase 3):
    /// a `ThemedTextShape` for tag pills and highlights, a `ThemedCheckboxStyle` for task
    /// checkboxes, a `ThemedHeadingOrnament` for headings, and a color behind quoted lines.
    static let roundedBackgroundKey = NSAttributedString.Key("GraphiteThemedRoundedBackground")
    static let checkboxStyleKey = NSAttributedString.Key("GraphiteThemedCheckbox")
    static let headingOrnamentKey = NSAttributedString.Key("GraphiteThemedHeadingOrnament")
    static let quoteBackgroundKey = NSAttributedString.Key("GraphiteThemedQuoteBackground")
}

/// A rounded background, with an optional border, behind a run of text.
final class ThemedTextShape: NSObject {
    let color: PlatformColor
    let cornerRadius: CGFloat
    let borderColor: PlatformColor?
    let borderWidth: CGFloat

    init(color: PlatformColor, cornerRadius: CGFloat, borderColor: PlatformColor?, borderWidth: CGFloat) {
        self.color = color; self.cornerRadius = cornerRadius; self.borderColor = borderColor; self.borderWidth = borderWidth
    }
}

/// A theme's task checkbox: corner radius as a multiple of the text size, border, and colors.
final class ThemedCheckboxStyle: NSObject {
    let radiusScale: CGFloat
    let borderWidth: CGFloat
    let fill: PlatformColor
    let border: PlatformColor
    let checkmark: PlatformColor

    init(radiusScale: CGFloat, borderWidth: CGFloat, fill: PlatformColor, border: PlatformColor, checkmark: PlatformColor) {
        self.radiusScale = radiusScale; self.borderWidth = borderWidth; self.fill = fill; self.border = border; self.checkmark = checkmark
    }
}

/// A theme's heading ornament: a background and an underline across the column, and text
/// before the heading, drawn in the margin so the heading's own text stays where it is.
final class ThemedHeadingOrnament: NSObject {
    let background: PlatformColor?
    let underlineColor: PlatformColor?
    let underlineWidth: CGFloat
    let prefix: String?
    let prefixColor: PlatformColor?

    init(background: PlatformColor?, underlineColor: PlatformColor?, underlineWidth: CGFloat, prefix: String?, prefixColor: PlatformColor?) {
        self.background = background; self.underlineColor = underlineColor; self.underlineWidth = underlineWidth; self.prefix = prefix; self.prefixColor = prefixColor
    }
}

/// A `$…$` formula Live Preview draws in place of its source.
final class InlineMathLayout: NSObject, Sendable {
    let latex: String
    let fontSize: CGFloat
    let metrics: InlineMathRendering.Metrics
    /// Room left on each side of the formula.
    static let horizontalPadding: CGFloat = 1

    init(latex: String, fontSize: CGFloat, metrics: InlineMathRendering.Metrics) {
        self.latex = latex
        self.fontSize = fontSize
        self.metrics = metrics
    }
}

/// Styles Markdown source in place. Only attributes change; the text is untouched, so
/// saving writes exactly what the user typed.
@MainActor
struct MarkdownTextStyler {
    let configuration: EditorConfiguration
    let accentColor: PlatformColor
    /// Whether the text view draws `ConcealedReplacement`s (bullets, checkboxes, quote bars,
    /// the subpath separator, inline math) over their hidden markup, as both editors do with
    /// `ConcealedReplacementLayoutFragment`. Without it, that markup stays visible as styled
    /// source, because hiding it would leave a blank gap.
    var drawsConcealedReplacements = true
    /// Concealed text stays in the document (so saving and undo are exact) but takes no
    /// visible room.
    private static let concealedFont = PlatformFont.systemFont(ofSize: 0.01)

    var baseFont: PlatformFont { configuration.typography.textFont(ofSize: configuration.textSize) }

    var baseAttributes: [NSAttributedString.Key: Any] { baseAttributes(font: baseFont) }

    private func baseAttributes(font: PlatformFont) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        // The theme's line height, or Graphite's (Obsidian's 1.5).
        paragraphStyle.lineSpacing = configuration.theme?.lineSpacing(forTextSize: font.pointSize) ?? font.pointSize * 0.3
        paragraphStyle.paragraphSpacing = font.pointSize * 0.25
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
    }

    // The theme's colors where it sets them, else Graphite's (`NoteThemeStyle`).
    private var theme: NoteThemeStyle? { configuration.theme }
    var textColor: PlatformColor { theme?.textNormal ?? Self.primaryTextColor }
    private var mutedColor: PlatformColor { theme?.textMuted ?? Self.secondaryTextColor }
    /// Markdown syntax markers only: decoration, never content.
    private var markerColor: PlatformColor { theme?.textFaint ?? Self.tertiaryTextColor }
    private var linkColor: PlatformColor { theme?.linkColor ?? theme?.accent ?? accentColor }
    private var tagColor: PlatformColor { theme?.tagColor ?? theme?.accent ?? accentColor }

    /// The theme's checkbox shape, when it gives one.
    private var checkboxStyle: ThemedCheckboxStyle? {
        guard let theme, theme.checkboxRadiusScale != nil || theme.checkboxBorderWidth != nil || theme.checkmarkColor != nil else { return nil }
        return ThemedCheckboxStyle(radiusScale: CGFloat(theme.checkboxRadiusScale ?? 0.25), borderWidth: CGFloat(min(max(theme.checkboxBorderWidth ?? 1.5, 1), 3)),
                                   fill: theme.checkboxColor ?? theme.accent ?? accentColor, border: theme.checkboxBorderColor ?? mutedColor,
                                   checkmark: theme.checkmarkColor ?? .white)
    }

    private func headingOrnament(level: Int) -> ThemedHeadingOrnament? {
        guard let ornament = theme?.headingOrnaments[min(max(level, 1), 6) - 1], !ornament.isEmpty,
              ornament.background != nil || ornament.underlineColor != nil || ornament.prefix != nil else { return nil }
        return ThemedHeadingOrnament(background: ornament.background, underlineColor: ornament.underlineColor,
                                     underlineWidth: CGFloat(min(max(ornament.underlineWidth ?? 1, 0.5), 6)), prefix: ornament.prefix, prefixColor: ornament.prefixColor)
    }

    /// The lines `applyStyles` restyles for an edited range, before it extends them to the
    /// concealed blocks and folded sections they touch: the range's lines and one line on
    /// each side. A setext heading's text line and its underline style each other; when an
    /// edit makes one of them plain text, the other produces no span, so it is reset only
    /// by being in the restyled lines.
    static func linesRestyled(for range: NSRange, in source: NSString) -> NSRange {
        let clampedLocation = min(max(range.location, 0), source.length)
        var lines = source.lineRange(for: NSRange(location: clampedLocation, length: min(max(range.length, 0), source.length - clampedLocation)))
        if lines.location > 0 { lines = NSUnionRange(lines, source.lineRange(for: NSRange(location: lines.location - 1, length: 0))) }
        if NSMaxRange(lines) < source.length { lines = NSUnionRange(lines, source.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0))) }
        return lines
    }

    /// Restyles whole lines touched by `range`, or the whole document. In Live Preview,
    /// `revealedMarkup` says which markup stays visible around the selection (nil while the
    /// note is only being read, so no markup shows), and `concealedBlocks` are drawn as
    /// views. Source mode shows all markup.
    /// `foldedRegions` are hidden, whatever the mode. `blockContextCheckpoints`, kept by the
    /// editor for its text storage, spares a restyle near the end of a long note from
    /// rescanning the note from its top; without it the scan starts at the top.
    func applyStyles(to textStorage: NSTextStorage, editedRange range: NSRange, restyleEverything: Bool,
                     revealedMarkup: RevealedMarkup?, concealedBlocks: [ConcealedBlock], foldedRegions: [FoldableRegion] = [],
                     blockContextCheckpoints: MarkdownBlockContextCheckpoints? = nil) {
        // A whole-note pass reads an immutable copy: the storage's mutable string proxy is
        // several times slower to scan, and the text does not change while it is styled.
        let source: NSString = restyleEverything ? (textStorage.mutableString.copy() as? NSString ?? textStorage.mutableString) : textStorage.mutableString
        guard source.length > 0 else { return }
        // Blocks and folds come from the editor's last scan, which can describe a different
        // text than the storage holds now. One that no longer fits is left out: attributes
        // applied past the end of the storage raise an exception.
        let concealedBlocks = Self.blocks(concealedBlocks, fitting: source)
        let foldedRegions = Self.regions(foldedRegions, fitting: source)
        var targetRange = restyleEverything ? NSRange(location: 0, length: source.length) : Self.linesRestyled(for: range, in: source)
        // A block is styled as a unit, so extend to any concealed block the range touches.
        for block in concealedBlocks where NSIntersectionRange(block.range, targetRange).length > 0 || NSLocationInRange(targetRange.location, block.range) {
            targetRange = NSUnionRange(targetRange, block.range)
        }
        // A folded section is hidden as a unit, too.
        for region in foldedRegions {
            let foldRange = NSRange(location: region.headerRange.location, length: region.endLocation - region.headerRange.location)
            if NSIntersectionRange(foldRange, targetRange).length > 0 || NSLocationInRange(targetRange.location, foldRange) {
                targetRange = NSUnionRange(targetRange, foldRange)
            }
        }
        targetRange = NSIntersectionRange(targetRange, NSRange(location: 0, length: source.length))
        let spans = blockContextCheckpoints?.spans(in: textStorage, source: source, range: targetRange)
            ?? MarkdownStyleScanner.spans(in: source, range: targetRange)
        let styledRange = spans.reduce(targetRange) { unionRange, span in NSUnionRange(unionRange, span.range) }
        let fonts = MarkdownStyleFonts(baseFont: baseFont, typography: configuration.typography, theme: configuration.theme)
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(font: fonts.baseFont), range: styledRange)
        apply(spans, within: [styledRange], to: textStorage, source: source, revealedMarkup: revealedMarkup, fonts: fonts)
        if configuration.colorsEnabled {
            let sections = coloredSections(touching: styledRange, source: source, textStorage: textStorage, blockContextCheckpoints: blockContextCheckpoints)
            applyColors(of: sections, within: nil, to: textStorage, revealedMarkup: revealedMarkup)
        }
        let hiddenRanges = (configuration.mode == .livePreview ? concealedBlocks.map(\.range) : []) + foldedRegions.map(\.hiddenRange)
        highlightCode(in: spans, to: textStorage, source: source, hiddenRanges: hiddenRanges)
        if configuration.mode == .livePreview {
            for block in concealedBlocks where NSIntersectionRange(block.range, styledRange).length > 0 {
                concealBlock(block, source: source, in: textStorage)
            }
        }
        for region in foldedRegions
        where NSIntersectionRange(region.hiddenRange, styledRange).length > 0 || NSLocationInRange(region.hiddenRange.location, styledRange) {
            hideFoldedSection(region, in: textStorage)
        }
        textStorage.endEditing()
    }

    // MARK: Code

    /// Holds, on each highlighted line of a fenced code block, the `CodeLineState` the line
    /// starts in, as its `storedValue`. A restyle compares the state its last line ends in
    /// with the one stored on the next line, to recolor the lines after an edit that opens
    /// or closes a block comment or a string spanning lines, and only those.
    static let codeLineStateKey = NSAttributedString.Key("GraphiteCodeLineState")

    /// Colors the code lines among `spans`, block by block, in the language each block's
    /// fence names. Lines of a language Graphite does not highlight keep the code color.
    private func highlightCode(in spans: [MarkdownStyleSpan], to textStorage: NSTextStorage, source: NSString, hiddenRanges: [NSRange]) {
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
                textStorage.addAttribute(.foregroundColor, value: CodeSyntaxColors.color(for: token.kind, theme: theme), range: token.range.shifted(by: block.codeStart))
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
        let codeColor = theme?.codeColor ?? textColor
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
                    textStorage.addAttribute(.foregroundColor, value: CodeSyntaxColors.color(for: token.kind, theme: theme), range: token.range.shifted(by: lineStart))
                }
            }
            lineStart = NSMaxRange(lineRange)
        }
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

    /// Restyles the markup that starts or stops showing when the revealed markup goes from
    /// `previousMarkup` to `revealedMarkup`, and nothing else: the text was styled for
    /// `previousMarkup`, so a cursor moving through a long note changes the attributes of
    /// the markers it reaches and leaves, not of their lines. Markup inside
    /// `concealedBlocks` and `foldedRegions` is hidden whatever the selection and is left
    /// alone. Returns the ranges restyled, in text order.
    @discardableResult
    func applyRevealedMarkupChange(to textStorage: NSTextStorage, from previousMarkup: RevealedMarkup?, to revealedMarkup: RevealedMarkup?,
                                   concealedBlocks: [ConcealedBlock], foldedRegions: [FoldableRegion] = [],
                                   blockContextCheckpoints: MarkdownBlockContextCheckpoints? = nil) -> [NSRange] {
        let source: NSString = textStorage.mutableString
        guard configuration.mode == .livePreview, source.length > 0 else { return [] }
        let documentRange = NSRange(location: 0, length: source.length)
        let concealedBlocks = Self.blocks(concealedBlocks, fitting: source)
        let foldedRegions = Self.regions(foldedRegions, fitting: source)
        func isHidden(_ markupRange: NSRange) -> Bool {
            LivePreviewBlockLookup.index(ofElementContaining: markupRange.location, in: concealedBlocks, range: { block in block.range }) != nil
                || foldedRegions.contains { region in NSLocationInRange(markupRange.location, region.hiddenRange) }
        }
        func scannedLines(_ lines: NSRange) -> ScannedLines {
            let spans = blockContextCheckpoints?.spans(in: textStorage, source: source, range: lines) ?? MarkdownStyleScanner.spans(in: source, range: lines)
            let sections = configuration.colorsEnabled
                ? coloredSections(touching: lines, source: source, textStorage: textStorage, blockContextCheckpoints: blockContextCheckpoints) : []
            return ScannedLines(lines: lines, spans: spans, coloredSections: sections)
        }
        var scans: [ScannedLines] = []
        var changingRanges: [NSRange] = []
        for examinedLines in RevealedMarkupChange.examinedLines(from: previousMarkup, to: revealedMarkup, in: source) {
            let scan = scannedLines(NSIntersectionRange(examinedLines, documentRange))
            for span in scan.spans where NSLocationInRange(span.range.location, scan.lines) && NSMaxRange(span.range) <= source.length
                && isStyledByRevealedMarkup(span, in: source)
                && shows(span, revealedMarkup: previousMarkup) != shows(span, revealedMarkup: revealedMarkup) {
                changingRanges.append(span.range)
            }
            for section in scan.coloredSections
            where showsInlineElement(at: section.elementRange, revealedMarkup: previousMarkup) != showsInlineElement(at: section.elementRange, revealedMarkup: revealedMarkup) {
                changingRanges.append(contentsOf: section.markerRanges.map { markerRange in NSIntersectionRange(markerRange, documentRange) })
            }
            scans.append(scan)
        }
        changingRanges = RevealedMarkupChange.merged(changingRanges.filter { changingRange in changingRange.length > 0 && !isHidden(changingRange) })
        guard !changingRanges.isEmpty else { return [] }
        // A color's markers can be on other lines than the ones examined, which hold the
        // text the selection touches.
        let otherMarkerLines = changingRanges.filter { changingRange in !scans.contains { scan in NSLocationInRange(changingRange.location, scan.lines) } }
            .map { markerRange in source.lineRange(for: markerRange) }
        scans.append(contentsOf: RevealedMarkupChange.merged(otherMarkerLines).map(scannedLines))
        let fonts = MarkdownStyleFonts(baseFont: baseFont, typography: configuration.typography, theme: configuration.theme)
        var restyledRanges: [NSRange] = []
        textStorage.beginEditing()
        for scan in scans {
            let rangesInLines = wholeSpanRanges(covering: changingRanges.filter { changingRange in NSLocationInRange(changingRange.location, scan.lines) }, spans: scan.spans)
            guard !rangesInLines.isEmpty else { continue }
            for restyledRange in rangesInLines { textStorage.setAttributes(baseAttributes(font: fonts.baseFont), range: restyledRange) }
            apply(scan.spans, within: rangesInLines, to: textStorage, source: source, revealedMarkup: revealedMarkup, fonts: fonts)
            applyColors(of: scan.coloredSections, within: rangesInLines, to: textStorage, revealedMarkup: revealedMarkup)
            restyledRanges.append(contentsOf: rangesInLines)
        }
        textStorage.endEditing()
        return RevealedMarkupChange.merged(restyledRanges)
    }

    /// Lines looked at for a change of the revealed markup, with what the scanners found.
    private struct ScannedLines {
        let lines: NSRange
        let spans: [MarkdownStyleSpan]
        let coloredSections: [ColoredSection]
    }

    /// `ranges`, each grown to the whole of any span it holds a part of that is drawn as a
    /// unit: a formula or a drawn replacement cannot be styled in part.
    private func wholeSpanRanges(covering ranges: [NSRange], spans: [MarkdownStyleSpan]) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        let unitStyles: Set<MarkdownStyle> = [.math, .subpathSeparator, .listMarker, .taskMarker, .syntaxMarker]
        let partlyCoveredUnits = spans.filter { span in
            guard unitStyles.contains(span.style) else { return false }
            let coveredPieces = Self.pieces(of: span.range, within: ranges)
            return !coveredPieces.isEmpty && coveredPieces != [span.range]
        }
        return RevealedMarkupChange.merged(ranges + partlyCoveredUnits.map(\.range))
    }

    private static func blocks(_ concealedBlocks: [ConcealedBlock], fitting source: NSString) -> [ConcealedBlock] {
        concealedBlocks.filter { block in block.range.location >= 0 && NSMaxRange(block.range) <= source.length }
    }

    private static func regions(_ foldedRegions: [FoldableRegion], fitting source: NSString) -> [FoldableRegion] {
        foldedRegions.filter { region in
            region.headerRange.location >= 0 && region.hiddenRange.location >= 0 && region.headerRange.location <= region.endLocation
                && region.endLocation <= source.length && NSMaxRange(region.hiddenRange) <= source.length
        }
    }

    /// Whether `span` looks different when its markup shows: a marker that hides, a
    /// formula drawn in place of its source, or markup a drawn replacement stands in for.
    /// The text between an element's markers looks the same either way.
    private func isStyledByRevealedMarkup(_ span: MarkdownStyleSpan, in source: NSString) -> Bool {
        if span.style == .concealableMarker { return true }
        guard drawsConcealedReplacements else { return false }
        return (span.style == .math && span.inlineElementRange != nil) || Self.replacement(for: span, in: source) != nil
    }

    /// Whether `span`'s markup shows as written. Source mode shows all markup; Live
    /// Preview shows none while the note is only being read.
    private func shows(_ span: MarkdownStyleSpan, revealedMarkup: RevealedMarkup?) -> Bool {
        guard configuration.mode == .livePreview else { return true }
        return revealedMarkup?.shows(span) ?? false
    }

    private func showsInlineElement(at elementRange: NSRange, revealedMarkup: RevealedMarkup?) -> Bool {
        guard configuration.mode == .livePreview else { return true }
        return revealedMarkup?.showsInlineElement(at: elementRange) ?? false
    }

    /// The parts of `range` inside `restyledRanges`, which are in text order and do not
    /// overlap. A binary search, because selecting a whole note restyles every marker.
    private static func pieces(of range: NSRange, within restyledRanges: [NSRange]) -> [NSRange] {
        var lowerBound = 0
        var upperBound = restyledRanges.count
        // The first restyled range that ends after `range` starts.
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if NSMaxRange(restyledRanges[middle]) <= range.location { lowerBound = middle + 1 } else { upperBound = middle }
        }
        var pieces: [NSRange] = []
        var index = lowerBound
        while index < restyledRanges.count, restyledRanges[index].location < NSMaxRange(range) {
            let piece = NSIntersectionRange(restyledRanges[index], range)
            if piece.length > 0 { pieces.append(piece) }
            index += 1
        }
        return pieces
    }

    /// Styles `spans` inside `restyledRanges`, which are in text order, do not overlap, and
    /// hold base attributes. A span that reaches outside them, such as the heading around a
    /// restyled marker, is applied to its parts inside.
    private func apply(_ spans: [MarkdownStyleSpan], within restyledRanges: [NSRange], to textStorage: NSTextStorage, source: NSString,
                       revealedMarkup: RevealedMarkup?, fonts: MarkdownStyleFonts) {
        let isLivePreview = configuration.mode == .livePreview
        // A task's checkbox replaces its list bullet, as in Obsidian.
        let taskLineStarts = drawsConcealedReplacements
            ? Set(spans.filter { span in span.style == .taskMarker && Self.replacement(for: span, in: source) != nil }.map { span in source.lineRange(for: span.range).location })
            : []
        for span in spans where span.range.length > 0 && NSMaxRange(span.range) <= source.length {
            let isSpanShown = shows(span, revealedMarkup: revealedMarkup)
            for piece in Self.pieces(of: span.range, within: restyledRanges) {
                let isWholeSpan = piece == span.range
                if span.style == .concealableMarker && !isSpanShown {
                    conceal(piece, in: textStorage)
                    continue
                }
                if span.style == .math && isLivePreview && !isSpanShown && drawsConcealedReplacements && isWholeSpan,
                   let layout = inlineMathLayout(for: source.substring(with: span.range), baseFont: fonts.baseFont) {
                    drawInlineMath(layout, over: span.range, in: textStorage)
                    continue
                }
                apply(span.style, to: textStorage, range: piece, fonts: fonts)
                guard drawsConcealedReplacements, !isSpanShown, isWholeSpan, let replacement = Self.replacement(for: span, in: source) else { continue }
                if replacement == .bullet && taskLineStarts.contains(source.lineRange(for: span.range).location) {
                    conceal(span.range, in: textStorage)
                } else {
                    replace(span.range, with: replacement, in: textStorage, baseFont: fonts.baseFont)
                }
            }
            if isLivePreview && span.style == .taskMarker && Self.replacement(for: span, in: source) == .checkedTask {
                for piece in Self.pieces(of: Self.completedTaskTextRange(after: span.range, in: source), within: restyledRanges) {
                    strikeCompletedTask(piece, in: textStorage)
                }
            }
        }
    }

    /// Hides a folded section: its text is concealed and its lines take no height.
    private func hideFoldedSection(_ region: FoldableRegion, in textStorage: NSTextStorage) {
        let hiddenRange = region.hiddenRange
        textStorage.removeAttribute(.backgroundColor, range: hiddenRange)
        textStorage.removeAttribute(ConcealedReplacement.attributeKey, range: hiddenRange)
        textStorage.removeAttribute(ConcealedReplacement.mathAttributeKey, range: hiddenRange)
        textStorage.removeAttribute(.baselineOffset, range: hiddenRange)
        conceal(hiddenRange, in: textStorage)
        // The header's own line break stays in its paragraph; the lines after it collapse.
        let bodyLines = NSRange(location: hiddenRange.location + 1, length: max(0, region.endLocation - hiddenRange.location - 1))
        guard bodyLines.length > 0, NSMaxRange(bodyLines) <= textStorage.length else { return }
        let collapsedParagraph = NSMutableParagraphStyle()
        collapsedParagraph.minimumLineHeight = 0.01
        collapsedParagraph.maximumLineHeight = 0.01
        collapsedParagraph.paragraphSpacing = 0
        collapsedParagraph.paragraphSpacingBefore = 0
        collapsedParagraph.lineSpacing = 0
        textStorage.addAttribute(.paragraphStyle, value: collapsedParagraph, range: bodyLines)
    }

    /// A colored section where it is in the note, with the color its text takes.
    private struct ColoredSection {
        let openingMarkerRange: NSRange
        let closingMarkerRange: NSRange?
        let contentRange: NSRange
        let color: PlatformColor

        var markerRanges: [NSRange] { [openingMarkerRange, closingMarkerRange].compactMap { markerRange in markerRange } }

        /// The section with its markers: an inline element, whose markers show while the
        /// selection touches it.
        var elementRange: NSRange {
            NSRange(location: openingMarkerRange.location, length: NSMaxRange(closingMarkerRange ?? contentRange) - openingMarkerRange.location)
        }
    }

    /// The colored sections that touch `range`, outermost first, so a deeper section's
    /// color wins where they overlap.
    private func coloredSections(touching range: NSRange, source: NSString, textStorage: NSTextStorage,
                                 blockContextCheckpoints: MarkdownBlockContextCheckpoints?) -> [ColoredSection] {
        if let blockContextCheckpoints, !blockContextCheckpoints.mayContainColorMarker(in: textStorage, source: source) { return [] }
        // A color cannot cross a blank line, so the colors touching `range` open and close
        // between the blank lines around it.
        let runStart = Self.paragraphRunStart(atLineContaining: range.location, in: source)
        let runEnd = Self.paragraphRunEnd(atLineContaining: NSMaxRange(range), in: source)
        // Without an opening marker there is nothing to color: the common case, answered
        // without parsing.
        guard source.range(of: "~={", range: NSRange(location: runStart, length: runEnd - runStart)).location != NSNotFound else { return [] }
        let contextStart = colorContextStart(from: runStart, source: source, textStorage: textStorage, blockContextCheckpoints: blockContextCheckpoints)
        let contextText = source.substring(with: NSRange(location: contextStart, length: runEnd - contextStart)) as NSString
        let sections = TextColorMarkup.sections(in: contextText, paletteHexByName: configuration.paletteHexByName)
            .sorted { firstSection, secondSection in firstSection.depth < secondSection.depth }
        return sections.compactMap { section in
            guard let color = PlatformColor(graphiteHex: section.hexColor) else { return nil }
            let coloredSection = ColoredSection(openingMarkerRange: section.openingMarkerRange.shifted(by: contextStart),
                                                closingMarkerRange: section.closingMarkerRange?.shifted(by: contextStart),
                                                contentRange: section.contentRange.shifted(by: contextStart), color: color)
            return NSIntersectionRange(coloredSection.elementRange, range).length > 0 ? coloredSection : nil
        }
    }

    /// Colors the sections' text and hides or tints their markers. Given `restyledRanges`
    /// (in text order, not overlapping, already styled otherwise), only the parts inside
    /// them change; given none, each section is colored whole, so a color just opened
    /// reaches the lines after the restyled ones.
    private func applyColors(of sections: [ColoredSection], within restyledRanges: [NSRange]?, to textStorage: NSTextStorage, revealedMarkup: RevealedMarkup?) {
        let documentRange = NSRange(location: 0, length: textStorage.length)
        func pieces(of range: NSRange) -> [NSRange] {
            let rangeInDocument = NSIntersectionRange(range, documentRange)
            guard let restyledRanges else { return rangeInDocument.length > 0 ? [rangeInDocument] : [] }
            return Self.pieces(of: rangeInDocument, within: restyledRanges)
        }
        for section in sections {
            for piece in pieces(of: section.contentRange) {
                textStorage.addAttribute(.foregroundColor, value: section.color, range: piece)
            }
            let showsMarkers = showsInlineElement(at: section.elementRange, revealedMarkup: revealedMarkup)
            for piece in section.markerRanges.flatMap(pieces) {
                if showsMarkers {
                    textStorage.addAttribute(.foregroundColor, value: section.color.withAlphaComponent(0.55), range: piece)
                } else {
                    conceal(piece, in: textStorage)
                }
            }
        }
    }

    /// Blank lines tried, going back, for one outside fenced code and `$$` math before the
    /// colors are parsed from the top of the note instead.
    private static let maximumColorContextProbes = 8

    /// Where color parsing starts: a blank-line boundary outside fenced code and `$$` math.
    /// `TextColorMarkup` finds code and math blocks only from their opening lines, so a
    /// context starting at a blank line inside a code block would read its closing fence as
    /// an opening one, coloring the code and treating the prose after it as code.
    private func colorContextStart(from runStart: Int, source: NSString, textStorage: NSTextStorage,
                                   blockContextCheckpoints: MarkdownBlockContextCheckpoints?) -> Int {
        var contextStart = runStart
        for _ in 0..<Self.maximumColorContextProbes {
            guard contextStart > 0 else { return 0 }
            let blockContext = blockContextCheckpoints?.blockContext(atLineStart: contextStart, in: textStorage, source: source)
                ?? MarkdownStyleScanner.blockContext(atLineContaining: contextStart, in: source)
            if blockContext == .normal { return contextStart }
            contextStart = Self.paragraphRunStart(atLineContaining: contextStart - 1, in: source)
        }
        return 0
    }

    /// The start of the first line after the nearest blank (whitespace-only) line before
    /// the line containing `location`, or 0. Colors treat these lines as paragraph breaks,
    /// whatever their line endings, so a note with Windows line endings is bounded too.
    static func paragraphRunStart(atLineContaining location: Int, in source: NSString) -> Int {
        var lineStart = source.lineRange(for: NSRange(location: min(max(location, 0), source.length), length: 0)).location
        while lineStart > 0 {
            let previousLine = source.lineRange(for: NSRange(location: lineStart - 1, length: 0))
            if isBlank(previousLine, in: source) { break }
            lineStart = previousLine.location
        }
        return lineStart
    }

    /// The start of the first blank line at or after the line containing `location`, or
    /// the end of the text.
    static func paragraphRunEnd(atLineContaining location: Int, in source: NSString) -> Int {
        var lineStart = source.lineRange(for: NSRange(location: min(max(location, 0), source.length), length: 0)).location
        while lineStart < source.length {
            let line = source.lineRange(for: NSRange(location: lineStart, length: 0))
            if isBlank(line, in: source) { return line.location }
            lineStart = NSMaxRange(line)
        }
        return source.length
    }

    private static func isBlank(_ lineRange: NSRange, in source: NSString) -> Bool {
        for location in lineRange.location..<NSMaxRange(lineRange) {
            guard let scalar = Unicode.Scalar(source.character(at: location)), CharacterSet.whitespacesAndNewlines.contains(scalar) else { return false }
        }
        return true
    }

    private static func replacement(for span: MarkdownStyleSpan, in source: NSString) -> ConcealedReplacement? {
        switch span.style {
        case .listMarker: ["-", "*", "+"].contains(source.substring(with: span.range)) ? .bullet : nil
        case .taskMarker:
            switch source.substring(with: span.range) {
            case "[ ]": .uncheckedTask
            case "[x]", "[X]": .checkedTask
            default: nil
            }
        case .subpathSeparator: .subpathSeparator
        // A quote's `>` becomes the bar Obsidian draws beside quoted text.
        case .syntaxMarker: source.substring(with: span.range).trimmingCharacters(in: .whitespaces).hasPrefix(">") ? .quoteBar : nil
        default: nil
        }
    }

    /// Hides `range` and marks it for `ConcealedReplacementLayoutFragment` to draw over.
    private func replace(_ range: NSRange, with replacement: ConcealedReplacement, in textStorage: NSTextStorage, baseFont: PlatformFont) {
        textStorage.addAttribute(.foregroundColor, value: PlatformColor.clear, range: range)
        textStorage.addAttribute(ConcealedReplacement.attributeKey, value: replacement.rawValue, range: range)
        let color: PlatformColor = switch replacement {
        case .bullet: theme?.listMarkerColor ?? mutedColor
        case .uncheckedTask: theme?.checkboxBorderColor ?? mutedColor
        case .checkedTask: theme?.checkboxColor ?? theme?.accent ?? accentColor
        case .subpathSeparator: linkColor
        case .quoteBar: theme?.blockquoteBorderColor ?? theme?.accent ?? accentColor
        case .inlineMath: textColor
        }
        textStorage.addAttribute(ConcealedReplacement.colorAttributeKey, value: color, range: range)
        if replacement == .checkedTask || replacement == .uncheckedTask, let checkboxStyle { textStorage.addAttribute(ConcealedReplacement.checkboxStyleKey, value: checkboxStyle, range: range) }
        guard replacement == .subpathSeparator else { return }
        // The separator is wider than `#`: kerning after it makes room without changing the text.
        let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont ?? baseFont
        let replacementWidth = (ConcealedReplacement.subpathSeparatorText as NSString).size(withAttributes: [.font: font]).width
        let markerWidth = textStorage.attributedSubstring(from: range).size().width
        textStorage.addAttribute(.kern, value: max(0, replacementWidth - markerWidth), range: range)
    }

    /// Measured formulas by font size and LaTeX; nil marks LaTeX that cannot be typeset,
    /// which stays visible as source.
    private static var inlineMathMetricsByKey: [String: InlineMathRendering.Metrics?] = [:]

    private func inlineMathLayout(for source: String, baseFont: PlatformFont) -> InlineMathLayout? {
        guard source.hasPrefix("$"), !source.hasPrefix("$$"), source.count > 2 else { return nil }
        let latex = LaTeXCompatibility.normalized(String(source.dropFirst().dropLast()))
        // Formulas are set a little larger than text, as in reading view.
        let fontSize = baseFont.pointSize * 1.2
        let key = "\(fontSize)|\(latex)"
        let metrics: InlineMathRendering.Metrics?
        if let cachedMetrics = Self.inlineMathMetricsByKey[key] {
            metrics = cachedMetrics
        } else {
            metrics = InlineMathRendering.metrics(for: latex, fontSize: fontSize)
            if Self.inlineMathMetricsByKey.count > 5000 { Self.inlineMathMetricsByKey.removeAll() }
            Self.inlineMathMetricsByKey[key] = metrics
        }
        return metrics.map { metrics in InlineMathLayout(latex: latex, fontSize: fontSize, metrics: metrics) }
    }

    /// Hides the source and makes room for the formula after its last character:
    /// `ConcealedReplacementLayoutFragment` draws the formula in that room.
    private func drawInlineMath(_ layout: InlineMathLayout, over range: NSRange, in textStorage: NSTextStorage) {
        conceal(range, in: textStorage)
        textStorage.addAttribute(ConcealedReplacement.attributeKey, value: ConcealedReplacement.inlineMath.rawValue, range: range)
        textStorage.addAttribute(ConcealedReplacement.mathAttributeKey, value: layout, range: range)
        let lastCharacter = NSRange(location: NSMaxRange(range) - 1, length: 1)
        textStorage.addAttribute(.kern, value: layout.metrics.width + 2 * InlineMathLayout.horizontalPadding, range: lastCharacter)
        // TextKit sizes a line from the ascent and descent of its characters, moved by their
        // baseline offsets. Raising the hidden last character by the formula's ascent, and
        // lowering the one before it by its descent, makes a tall formula's line tall enough
        // for it instead of overlapping the lines around it. A formula's source has at least
        // three characters (`$x$`), and no line break falls between its last two.
        textStorage.addAttribute(.baselineOffset, value: layout.metrics.ascent, range: lastCharacter)
        textStorage.addAttribute(.baselineOffset, value: -layout.metrics.descent, range: NSRange(location: lastCharacter.location - 1, length: 1))
    }

    /// The text of a task after its checkbox, to the end of its line.
    private static func completedTaskTextRange(after markerRange: NSRange, in source: NSString) -> NSRange {
        let lineRange = source.lineRange(for: markerRange)
        var lineEnd = NSMaxRange(lineRange)
        while lineEnd > NSMaxRange(markerRange), let scalar = Unicode.Scalar(source.character(at: lineEnd - 1)), CharacterSet.newlines.contains(scalar) { lineEnd -= 1 }
        let contentStart = min(NSMaxRange(markerRange) + 1, lineEnd)
        return NSRange(location: contentStart, length: lineEnd - contentStart)
    }

    /// A completed task reads as done: dimmed and struck through, as in Obsidian.
    private func strikeCompletedTask(_ taskTextRange: NSRange, in textStorage: NSTextStorage) {
        guard taskTextRange.length > 0 else { return }
        textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: taskTextRange)
        textStorage.addAttribute(.foregroundColor, value: mutedColor, range: taskTextRange)
    }

    private func conceal(_ range: NSRange, in textStorage: NSTextStorage) {
        textStorage.addAttribute(.font, value: Self.concealedFont, range: range)
        textStorage.addAttribute(.foregroundColor, value: PlatformColor.clear, range: range)
    }

    private func concealBlock(_ block: ConcealedBlock, source: NSString, in textStorage: NSTextStorage) {
        let concealedParagraph = NSMutableParagraphStyle()
        concealedParagraph.minimumLineHeight = 0.01
        concealedParagraph.maximumLineHeight = 0.01
        textStorage.addAttribute(.paragraphStyle, value: concealedParagraph, range: block.range)
        textStorage.removeAttribute(.backgroundColor, range: block.range)
        // The block's view shows its bullets and formulas; nothing is drawn over the hidden
        // source, and no formula makes its lines taller.
        textStorage.removeAttribute(ConcealedReplacement.attributeKey, range: block.range)
        textStorage.removeAttribute(ConcealedReplacement.mathAttributeKey, range: block.range)
        textStorage.removeAttribute(.baselineOffset, range: block.range)
        conceal(block.range, in: textStorage)
        // The rendered view occupies the space after the block's last line.
        let lastLineRange = source.lineRange(for: NSRange(location: max(block.range.location, NSMaxRange(block.range) - 1), length: 0))
        let reservingParagraph = NSMutableParagraphStyle()
        reservingParagraph.minimumLineHeight = 0.01
        reservingParagraph.maximumLineHeight = 0.01
        reservingParagraph.paragraphSpacing = block.reservedHeight
        textStorage.addAttribute(.paragraphStyle, value: reservingParagraph, range: NSIntersectionRange(lastLineRange, block.range))
    }

    private func apply(_ style: MarkdownStyle, to textStorage: NSTextStorage, range: NSRange, fonts: MarkdownStyleFonts) {
        switch style {
        case .heading(let level):
            textStorage.addAttribute(.font, value: fonts.headingFont(level: level), range: range)
            if let headingColor = theme?.headingColors[min(max(level, 1), 6) - 1] { textStorage.addAttribute(.foregroundColor, value: headingColor, range: range) }
            if let ornament = headingOrnament(level: level) { textStorage.addAttribute(ConcealedReplacement.headingOrnamentKey, value: ornament, range: range) }
        case .syntaxMarker, .concealableMarker, .horizontalRule:
            textStorage.addAttribute(.foregroundColor, value: markerColor, range: range)
        case .strong:
            addTrait(bold: true, to: textStorage, range: range, fonts: fonts)
            if let boldColor = theme?.boldColor { textStorage.addAttribute(.foregroundColor, value: boldColor, range: range) }
        case .emphasis:
            addTrait(bold: false, to: textStorage, range: range, fonts: fonts)
            if let italicColor = theme?.italicColor { textStorage.addAttribute(.foregroundColor, value: italicColor, range: range) }
        case .strikethrough:
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            textStorage.addAttribute(.foregroundColor, value: mutedColor, range: range)
        case .highlight:
            if let theme, let background = theme.highlightBackground, !drawsConcealedReplacements {
                // The Mac editor draws no shapes: a plain background there.
                textStorage.addAttribute(.backgroundColor, value: background, range: range)
            } else if let theme, theme.highlightBackground != nil || theme.highlightRadius != nil {
                // Drawn by the layout fragment, with the theme's rounded ends; a theme that only
                // rounds the ends keeps Graphite's color.
                textStorage.addAttribute(ConcealedReplacement.roundedBackgroundKey,
                                         value: ThemedTextShape(color: theme.highlightBackground ?? Self.highlightBackgroundColor, cornerRadius: NoteThemeStyle.scaled(theme.highlightRadius ?? 0, textSize: configuration.textSize),
                                                                borderColor: nil, borderWidth: 0), range: range)
                if let highlightText = theme.highlightTextColor { textStorage.addAttribute(.foregroundColor, value: highlightText, range: range) }
            } else {
                textStorage.addAttribute(.backgroundColor, value: Self.highlightBackgroundColor, range: range)
            }
        case .inlineCode, .codeBlock:
            textStorage.addAttribute(.font, value: fonts.codeFont, range: range)
            textStorage.addAttribute(.backgroundColor, value: theme?.codeBackground ?? Self.codeBackgroundColor, range: range)
            if let codeColor = theme?.codeColor { textStorage.addAttribute(.foregroundColor, value: codeColor, range: range) }
        case .math:
            // Quiet, like code: the formula's source is not a link, so it takes no color of its own.
            textStorage.addAttribute(.font, value: fonts.codeFont, range: range)
            textStorage.addAttribute(.foregroundColor, value: mutedColor, range: range)
        case .link, .embed, .subpathSeparator:
            textStorage.addAttribute(.foregroundColor, value: linkColor, range: range)
            if theme?.linksAreUnderlined == true { textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        case .tag:
            textStorage.addAttribute(.foregroundColor, value: tagColor, range: range)
            if let theme, let tagBackground = theme.tagBackground, !drawsConcealedReplacements {
                textStorage.addAttribute(.backgroundColor, value: tagBackground, range: range)
            } else if let theme, theme.tagBackground != nil || theme.tagBorderColor != nil {
                // A pill, drawn by the layout fragment with the theme's corners and border.
                textStorage.addAttribute(ConcealedReplacement.roundedBackgroundKey,
                                         value: ThemedTextShape(color: theme.tagBackground ?? .clear,
                                                                cornerRadius: theme.tagRadius.map { radius in NoteThemeStyle.scaled(radius, textSize: configuration.textSize) } ?? NoteThemeStyle.pillRadius,
                                                                borderColor: theme.tagBorderColor, borderWidth: CGFloat(theme.tagBorderWidth ?? 0)), range: range)
            }
        case .listMarker, .taskMarker:
            textStorage.addAttribute(.foregroundColor, value: mutedColor, range: range)
        case .quote:
            textStorage.addAttribute(.foregroundColor, value: mutedColor, range: range)
            if let quoteBackground = theme?.blockquoteBackground { textStorage.addAttribute(ConcealedReplacement.quoteBackgroundKey, value: quoteBackground, range: range) }
        case .calloutTitle:
            textStorage.addAttribute(.foregroundColor, value: theme?.accent ?? accentColor, range: range)
            textStorage.addAttribute(.font, value: fonts.calloutTitleFont, range: range)
        case .frontmatter:
            textStorage.addAttribute(.font, value: fonts.frontmatterFont, range: range)
            textStorage.addAttribute(.foregroundColor, value: mutedColor, range: range)
        case .footnote:
            textStorage.addAttribute(.font, value: fonts.footnoteFont, range: range)
            textStorage.addAttribute(.baselineOffset, value: fonts.baseFont.pointSize * 0.35, range: range)
            textStorage.addAttribute(.foregroundColor, value: linkColor, range: range)
        }
    }

    /// Adds bold or italic to whatever font is already there (for example a heading).
    private func addTrait(bold: Bool, to textStorage: NSTextStorage, range: NSRange, fonts: MarkdownStyleFonts) {
        textStorage.enumerateAttribute(.font, in: range) { existingFont, fontRange, _ in
            let currentFont = existingFont as? PlatformFont ?? fonts.baseFont
            textStorage.addAttribute(.font, value: fonts.font(currentFont, addingBold: bold), range: fontRange)
        }
    }

    static let highlightBackgroundColor = PlatformColor.systemYellow.withAlphaComponent(0.3)
    #if canImport(UIKit)
    static let primaryTextColor = UIColor.label
    static let secondaryTextColor = UIColor.secondaryLabel
    static let tertiaryTextColor = UIColor.tertiaryLabel
    static let codeBackgroundColor = UIColor.secondarySystemFill
    #else
    static let primaryTextColor = NSColor.labelColor
    static let secondaryTextColor = NSColor.secondaryLabelColor
    static let tertiaryTextColor = NSColor.tertiaryLabelColor
    static let codeBackgroundColor = NSColor.quaternaryLabelColor
    #endif
}

/// The fonts of one styling pass, each made once: a whole-note restyle would otherwise
/// create a font for every heading, code, math, and emphasis span. Kept for one pass only,
/// so a text size or Dynamic Type change needs no invalidation.
@MainActor
private final class MarkdownStyleFonts {
    let baseFont: PlatformFont
    let typography: NoteTypography
    let theme: NoteThemeStyle?
    private(set) lazy var codeFont = typography.monospaceFont(ofSize: baseFont.pointSize * 0.9)
    private(set) lazy var frontmatterFont = typography.monospaceFont(ofSize: baseFont.pointSize * 0.85)
    private(set) lazy var calloutTitleFont = typography.textFont(ofSize: baseFont.pointSize, weight: .semibold)
    private(set) lazy var footnoteFont = typography.textFont(ofSize: max(baseFont.pointSize * 0.72, GraphitePreferences.smallestNoteTextSize), weight: .semibold)
    private var headingFontsByLevel: [Int: PlatformFont] = [:]
    private var traitFontsByKey: [TraitFontKey: PlatformFont] = [:]

    private struct TraitFontKey: Hashable {
        let font: PlatformFont
        let isBold: Bool
    }

    init(baseFont: PlatformFont, typography: NoteTypography, theme: NoteThemeStyle?) {
        self.baseFont = baseFont
        self.typography = typography
        self.theme = theme
    }

    func headingFont(level: Int) -> PlatformFont {
        let clampedLevel = min(max(level, 1), 6)
        if let font = headingFontsByLevel[clampedLevel] { return font }
        let font = HeadingTypography.font(level: clampedLevel, textSize: baseFont.pointSize, typography: typography, theme: theme)
        headingFontsByLevel[clampedLevel] = font
        return font
    }

    /// `font` made bold, or italic when `addingBold` is false, keeping its other traits.
    func font(_ font: PlatformFont, addingBold: Bool) -> PlatformFont {
        let key = TraitFontKey(font: font, isBold: addingBold)
        if let traitFont = traitFontsByKey[key] { return traitFont }
        #if canImport(UIKit)
        let trait: UIFontDescriptor.SymbolicTraits = addingBold ? .traitBold : .traitItalic
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) ?? font.fontDescriptor
        let traitFont = UIFont(descriptor: descriptor, size: font.pointSize)
        #else
        let trait: NSFontDescriptor.SymbolicTraits = addingBold ? .bold : .italic
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        let traitFont = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
        traitFontsByKey[key] = traitFont
        return traitFont
    }
}

extension NSRange {
    func shifted(by offset: Int) -> NSRange { NSRange(location: location + offset, length: length) }
}

extension PlatformColor {
    /// `#rrggbb` or `#rrggbbaa`, as stored by the Colors syntax.
    convenience init?(graphiteHex hex: String) {
        guard let canonical = TextColorMarkup.canonicalHex(hex) else { return nil }
        let digits = Array(canonical.dropFirst())
        func component(_ position: Int) -> CGFloat { CGFloat(Int(String(digits[position..<position + 2]), radix: 16) ?? 0) / 255 }
        #if canImport(UIKit)
        self.init(red: component(0), green: component(2), blue: component(4), alpha: digits.count == 8 ? component(6) : 1)
        #else
        self.init(srgbRed: component(0), green: component(2), blue: component(4), alpha: digits.count == 8 ? component(6) : 1)
        #endif
    }
}


/// How typing behaves in the editor, from Obsidian's editor settings in `app.json`.
struct EditingBehavior: Equatable {
    var pairsBrackets = true
    var pairsMarkdown = true
    var continuesLists = true
    var indentUnit = "\t"
    /// How many spaces one indentation level is when `indentUnit` is a tab.
    var tabSize = 4
    var convertsPastedHTML = true

    init() {}

    init(settings: ObsidianSettings) {
        pairsBrackets = settings.pairsBrackets
        pairsMarkdown = settings.pairsMarkdown
        continuesLists = settings.continuesLists
        indentUnit = settings.indentUnit
        tabSize = settings.tabSize
        convertsPastedHTML = settings.convertsPastedHTML
    }
}
