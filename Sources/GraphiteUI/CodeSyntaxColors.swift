import SwiftUI
import GraphiteCore
import Textual

/// The colors one code block is drawn in, resolved for a code theme and a vault theme.
/// Each color follows light, dark and Increase Contrast by itself.
struct CodePalette {
    let colors: [CodeTokenKind: PlatformColor]
    /// Code that is no token, such as punctuation, and the text of an unknown language.
    let text: PlatformColor
    let background: PlatformColor
    /// The language label, and a fence while it shows.
    let quietText: PlatformColor
    /// The thin lines that show each level of indentation.
    let guide: PlatformColor
    /// The box's one-point border.
    let border: PlatformColor

    /// Reading view's colors for the same palette, made with it so they are made once.
    let highlighterTheme: StructuredText.HighlighterTheme

    init(colors: [CodeTokenKind: PlatformColor], text: PlatformColor, background: PlatformColor, quietText: PlatformColor,
         guide: PlatformColor, border: PlatformColor) {
        self.colors = colors
        self.text = text
        self.background = background
        self.quietText = quietText
        self.guide = guide
        self.border = border
        highlighterTheme = CodeSyntaxColors.makeHighlighterTheme(colors: colors, text: text, background: background)
    }

    func color(for kind: CodeTokenKind) -> PlatformColor { colors[kind] ?? text }
}

/// The colors of highlighted code, the same in Live Preview, Source mode and reading view.
/// Graphite's own colors are Obsidian's default syntax colors (`--code-keyword` pink, types
/// in `--code-function` yellow, names in `--code-property` cyan, values purple, operators
/// red, strings green, comments and directives faint), one set for light appearance and one
/// for dark, moved just enough to read as text on the code background (`AccentLegibility`),
/// and further when Increase Contrast is on. Function names keep the code's text color, as
/// Obsidian's editor draws them. A vault theme's syntax colors win where it sets them.
@MainActor
enum CodeSyntaxColors {
    /// `#rrggbb` for light and dark appearance: Obsidian's `--color-*` and `--text-faint`.
    private static let hexByKind: [CodeTokenKind: (light: String, dark: String)] = [
        .keyword: ("#d53984", "#fa99cd"),
        .typeName: ("#e0ac00", "#e0de71"),
        .string: ("#08b94e", "#44cf6e"),
        .number: ("#7852ee", "#a882ff"),
        .constant: ("#7852ee", "#a882ff"),
        .comment: ("#ababab", "#666666"),
        .preprocessor: ("#ababab", "#666666"),
        .attribute: ("#ec7500", "#e9973f"),
        .property: ("#00bfbc", "#53dfdd"),
        .identifier: ("#00bfbc", "#53dfdd"),
        .variable: ("#ec7500", "#e9973f"),
        .operator: ("#e93147", "#fb464c"),
    ]

    private static let graphiteColors: [CodeTokenKind: PlatformColor] = hexByKind.compactMapValues { hexes in
        guard let light = PlatformColor(graphiteHex: hexes.light)?.sRGBComponents,
              let dark = PlatformColor(graphiteHex: hexes.dark)?.sRGBComponents else { return nil }
        func color(_ components: (red: Double, green: Double, blue: Double)) -> PlatformColor {
            PlatformColor.sRGB(red: components.red, green: components.green, blue: components.blue, alpha: 1)
        }
        return PlatformColor.appearanceDependent(AppearanceVariants(
            light: color(AccentLegibility.darkenedForLightBackground(red: light.red, green: light.green, blue: light.blue)),
            lightIncreasedContrast: color(AccentLegibility.darkenedForLightBackground(
                red: light.red, green: light.green, blue: light.blue, targetContrast: AccentLegibility.increasedTextContrast)),
            dark: color(AccentLegibility.lightenedForDarkBackground(red: dark.red, green: dark.green, blue: dark.blue)),
            darkIncreasedContrast: color(AccentLegibility.lightenedForDarkBackground(
                red: dark.red, green: dark.green, blue: dark.blue, targetContrast: AccentLegibility.increasedTextContrast))))
    }

    /// The color of `kind`: the vault theme's, else Graphite's.
    static func color(for kind: CodeTokenKind, theme: NoteThemeStyle?) -> PlatformColor {
        theme?.codeTokenColors[kind] ?? graphiteColors[kind] ?? theme?.codeColor ?? MarkdownTextStyler.primaryTextColor
    }

    static func graphiteColor(for kind: CodeTokenKind) -> PlatformColor {
        graphiteColors[kind] ?? MarkdownTextStyler.primaryTextColor
    }

    // MARK: The code block

    private static let graphiteBlockBackground = PlatformColor.appearanceDependent(AppearanceVariants(
        light: PlatformColor.sRGB(red: 0.960784, green: 0.960784, blue: 0.968627, alpha: 1),
        lightIncreasedContrast: PlatformColor.sRGB(red: 0.92, green: 0.92, blue: 0.93, alpha: 1),
        dark: PlatformColor.sRGB(red: 0.120543, green: 0.122844, blue: 0.141312, alpha: 1),
        darkIncreasedContrast: PlatformColor.sRGB(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)))

    /// The thin lines that show each level of indentation: the text color, faint, and less
    /// faint with Increase Contrast. Made in an appearance-dependent provider, because a
    /// system color given another opacity is drawn for the wrong appearance outside text.
    private static let indentationGuideColor = PlatformColor.primaryText(opacity: 0.14, increasedContrastOpacity: 0.3)

    /// The corner radius of a code block: the theme's, else 4 points.
    static func blockCornerRadius(theme: NoteThemeStyle?) -> CGFloat {
        theme?.codeBlockRadius.map { radius in CGFloat(min(radius, 24)) } ?? 4
    }

    private static let graphiteBlockBorder = PlatformColor.appearanceDependent(AppearanceVariants(
        light: PlatformColor.sRGB(red: 210 / 255, green: 210 / 255, blue: 215 / 255, alpha: 1),
        lightIncreasedContrast: PlatformColor.sRGB(red: 160 / 255, green: 160 / 255, blue: 166 / 255, alpha: 1),
        dark: PlatformColor.sRGB(red: 66 / 255, green: 66 / 255, blue: 69 / 255, alpha: 1),
        darkIncreasedContrast: PlatformColor.sRGB(red: 110 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1)))

    // MARK: Palettes

    /// The colors code blocks are drawn in, for the code theme chosen and the vault's
    /// Obsidian theme, which only Obsidian's own colors follow. Every palette is made once:
    /// the other themes' in `themedPalettes`, Obsidian's without a vault theme in
    /// `graphiteObsidianPalette`, and Obsidian's with one by `NoteThemeStyle`, so the same
    /// palette hands out the same colors on every call.
    static func palette(codeTheme: CodeColorTheme, noteTheme: NoteThemeStyle?) -> CodePalette {
        if codeTheme == .obsidian { return noteTheme?.obsidianCodePalette ?? graphiteObsidianPalette }
        return themedPalettes[codeTheme] ?? graphiteObsidianPalette
    }

    private static let themedPalettes: [CodeColorTheme: CodePalette] = Dictionary(
        uniqueKeysWithValues: CodeColorTheme.allCases.compactMap { codeTheme in codeTheme.palette().map { palette in (codeTheme, palette) } })

    private static let graphiteObsidianPalette = obsidianPalette(
        themeTokenColors: [:], codeColor: nil, codeBackground: nil, codeBlockBackground: nil, quietText: nil, borderWidth: nil, borderColor: nil)

    /// Obsidian's palette for the values a vault theme sets (all nil: Graphite's own). A
    /// theme's values win; the box is the theme's block background, else its code background.
    static func obsidianPalette(themeTokenColors: [CodeTokenKind: PlatformColor], codeColor: PlatformColor?, codeBackground: PlatformColor?,
                                codeBlockBackground: PlatformColor?, quietText: PlatformColor?, borderWidth: Double?,
                                borderColor: PlatformColor?) -> CodePalette {
        var colors: [CodeTokenKind: PlatformColor] = [:]
        for kind in CodeTokenKind.allCases {
            colors[kind] = themeTokenColors[kind] ?? graphiteColors[kind] ?? codeColor ?? MarkdownTextStyler.primaryTextColor
        }
        // The border: the vault theme's, when it gives one, else a light gray a step darker
        // than the box (lighter in dark appearance).
        let border: PlatformColor
        if let borderWidth, borderWidth > 0, let borderColor { border = borderColor } else { border = graphiteBlockBorder }
        return CodePalette(
            colors: colors, text: codeColor ?? MarkdownTextStyler.primaryTextColor,
            background: codeBlockBackground ?? codeBackground ?? graphiteBlockBackground,
            quietText: quietText ?? MarkdownTextStyler.secondaryTextColor, guide: indentationGuideColor, border: border)
    }

    /// Reading view's colors, for Textual: one entry per token type, for Graphite's tokens
    /// and for the Prism token types Textual's own highlighter gives the languages Graphite
    /// does not tokenize itself, so both read alike.
    static func highlighterTheme(codeTheme: CodeColorTheme, noteTheme: NoteThemeStyle?) -> StructuredText.HighlighterTheme {
        palette(codeTheme: codeTheme, noteTheme: noteTheme).highlighterTheme
    }

    nonisolated static func makeHighlighterTheme(colors: [CodeTokenKind: PlatformColor], text: PlatformColor,
                                                 background: PlatformColor) -> StructuredText.HighlighterTheme {
        func dynamic(_ color: PlatformColor) -> DynamicColor {
            // The platform color resolves itself for the appearance and contrast it is drawn in.
            DynamicColor(light: Color(color), dark: Color(color))
        }
        var tokenProperties: [StructuredText.HighlighterTheme.TokenType: AnyTextProperty] = [:]
        for kind in CodeTokenKind.allCases {
            let property = AnyTextProperty(.foregroundColor(dynamic(colors[kind] ?? text)))
            for tokenType in tokenTypes(of: kind) { tokenProperties[tokenType] = property }
        }
        return StructuredText.HighlighterTheme(foregroundColor: dynamic(text), backgroundColor: dynamic(background),
                                                tokenProperties: tokenProperties)
    }

    /// Textual's token types, after Prism's, that take the color of `kind`.
    nonisolated private static func tokenTypes(of kind: CodeTokenKind) -> [StructuredText.HighlighterTheme.TokenType] {
        switch kind {
        case .keyword: [.keyword, .tag, .atrule, .important, .selector]
        case .typeName: [.className, .namespace]
        case .function: [.function, .functionName, .functionDefinition, .builtin, .label]
        case .string: [.string, .char, .regex, .url, .attributeValue, .inserted]
        case .number: [.number]
        case .constant: [.constant, .boolean, .literal, .nil, .symbol, .entity]
        case .comment: [.comment, .blockComment, .docComment, .prolog, .doctype, .cdata]
        case .preprocessor: [.preprocessor, .directive, .otherDirective]
        case .attribute: [.attribute]
        case .property: [.property, .attributeName]
        case .variable: [.variable, .deleted, .shortArgument]
        case .identifier: [identifierTokenType]
        case .operator: [.operator]
        }
    }

    /// Reading view's tokens of `code` in `language`, or nil when Graphite does not
    /// highlight the language, which leaves it to Textual. Made off the main actor by
    /// Textual's view, and cached by `CodeSyntaxHighlighter`.
    nonisolated static func readingSegments(code: String, language: String) -> [StructuredText.CodeSegment]? {
        guard let codeLanguage = CodeSyntaxHighlighter.language(forFenceInfo: language) else { return nil }
        let source = code as NSString
        var segments: [StructuredText.CodeSegment] = []
        var location = 0
        for token in CodeSyntaxHighlighter.tokens(in: code, language: codeLanguage) {
            if token.range.location > location {
                let gap = NSRange(location: location, length: token.range.location - location)
                segments.append(StructuredText.CodeSegment(content: source.substring(with: gap), type: .plain))
            }
            segments.append(StructuredText.CodeSegment(content: source.substring(with: token.range), type: readingTokenTypes[token.kind] ?? .plain))
            location = NSMaxRange(token.range)
        }
        if location < source.length { segments.append(StructuredText.CodeSegment(content: source.substring(from: location), type: .plain)) }
        return segments
    }

    nonisolated private static let readingTokenTypes: [CodeTokenKind: StructuredText.HighlighterTheme.TokenType] = [
        .keyword: .keyword, .typeName: .className, .function: .function, .string: .string, .number: .number, .constant: .constant,
        .comment: .comment, .preprocessor: .preprocessor, .attribute: .attribute, .property: .property, .variable: .variable,
        .identifier: identifierTokenType, .operator: .operator,
    ]

    /// Graphite's own token type for names, which Prism has none for.
    nonisolated private static let identifierTokenType: StructuredText.HighlighterTheme.TokenType = "graphite-identifier"
}
