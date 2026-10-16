import SwiftUI
import GraphiteCore
import Textual

/// The colors of highlighted code, the same in Live Preview, Source mode and reading view.
/// Graphite's own colors follow Xcode's default themes, one set for light appearance and one
/// for dark, moved just enough to read as text on the code background (`AccentLegibility`),
/// and further when Increase Contrast is on. A vault theme's syntax colors win where it sets
/// them.
@MainActor
enum CodeSyntaxColors {
    /// `#rrggbb` for light and dark appearance.
    private static let hexByKind: [CodeTokenKind: (light: String, dark: String)] = [
        .keyword: ("#9b2393", "#fc5fa3"),
        .typeName: ("#0b4f79", "#5dd8ff"),
        .function: ("#326d74", "#67b7a4"),
        .string: ("#c41a16", "#fc6a5d"),
        .number: ("#1c00cf", "#d0bf69"),
        .constant: ("#1c00cf", "#d0bf69"),
        .comment: ("#5d6c79", "#7f8c98"),
        .preprocessor: ("#643820", "#fd8f3f"),
        .attribute: ("#815f03", "#bf8555"),
        .property: ("#0f68a0", "#41a1c0"),
        .variable: ("#6c36a9", "#a167e6"),
    ]

    private static let graphiteColors: [CodeTokenKind: PlatformColor] = hexByKind.compactMapValues { hexes in
        guard let light = PlatformColor(graphiteHex: hexes.light)?.sRGBComponents, let dark = PlatformColor(graphiteHex: hexes.dark)?.sRGBComponents else { return nil }
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
        theme?.codeTokenColors[kind] ?? graphiteColor(for: kind)
    }

    static func graphiteColor(for kind: CodeTokenKind) -> PlatformColor {
        graphiteColors[kind] ?? MarkdownTextStyler.primaryTextColor
    }

    /// Reading view's colors, for Textual: one entry per token type, for Graphite's tokens
    /// and for the Prism token types Textual's own highlighter gives the languages Graphite
    /// does not tokenize itself, so both read alike.
    static func highlighterTheme(theme: NoteThemeStyle?) -> StructuredText.HighlighterTheme {
        let fingerprint = theme?.tokens.fingerprint ?? ""
        if let cached = lastHighlighterTheme, cached.fingerprint == fingerprint { return cached.highlighterTheme }
        let highlighterTheme = makeHighlighterTheme(theme: theme)
        lastHighlighterTheme = (fingerprint, highlighterTheme)
        return highlighterTheme
    }

    /// The theme made last, by its vault theme's fingerprint: reading view asks on every
    /// layout of a note.
    private static var lastHighlighterTheme: (fingerprint: String, highlighterTheme: StructuredText.HighlighterTheme)?

    private static func makeHighlighterTheme(theme: NoteThemeStyle?) -> StructuredText.HighlighterTheme {
        func dynamic(_ color: PlatformColor) -> DynamicColor {
            // The platform color resolves itself for the appearance and contrast it is drawn in.
            DynamicColor(light: Color(color), dark: Color(color))
        }
        var tokenProperties: [StructuredText.HighlighterTheme.TokenType: AnyTextProperty] = [:]
        for kind in CodeTokenKind.allCases {
            let property = AnyTextProperty(.foregroundColor(dynamic(color(for: kind, theme: theme))))
            for tokenType in tokenTypes(of: kind) { tokenProperties[tokenType] = property }
        }
        let foreground = theme?.codeColor ?? MarkdownTextStyler.primaryTextColor
        let background = theme?.codeBlockBackground ?? theme?.codeBackground ?? MarkdownTextStyler.codeBackgroundColor
        return StructuredText.HighlighterTheme(foregroundColor: dynamic(foreground), backgroundColor: dynamic(background), tokenProperties: tokenProperties)
    }

    /// Textual's token types, after Prism's, that take the color of `kind`.
    private static func tokenTypes(of kind: CodeTokenKind) -> [StructuredText.HighlighterTheme.TokenType] {
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
                segments.append(StructuredText.CodeSegment(content: source.substring(with: NSRange(location: location, length: token.range.location - location)), type: .plain))
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
    ]
}
