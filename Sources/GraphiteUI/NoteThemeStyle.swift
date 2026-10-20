import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The vault's Obsidian theme as notes draw it: each value the theme sets, made into a color
/// that follows light, dark and Increase Contrast, and kept readable on the theme's own page
/// (`ThemeContrastGuard`). A value the theme leaves alone is nil, and Graphite draws it as
/// it always does. Made once per resolved theme, never while typing.
struct NoteThemeStyle: Equatable {
    let tokens: VaultThemeTokens

    // Colors; nil means Graphite's own.
    let background: PlatformColor?
    let textNormal: PlatformColor?
    let textMuted: PlatformColor?
    /// Decoration only (Markdown syntax markers); never used for content.
    let textFaint: PlatformColor?
    let accent: PlatformColor?
    let boldColor: PlatformColor?
    let italicColor: PlatformColor?
    let headingColors: [PlatformColor?]
    let linkColor: PlatformColor?
    let unresolvedLinkColor: PlatformColor?
    let externalLinkColor: PlatformColor?
    let tagColor: PlatformColor?
    let tagBackground: PlatformColor?
    let checkboxColor: PlatformColor?
    let checkboxBorderColor: PlatformColor?
    let codeBackground: PlatformColor?
    let codeColor: PlatformColor?
    /// Syntax colors in code blocks, readable on the theme's code background; empty when the
    /// theme leaves them to Graphite (`CodeSyntaxColors`).
    let codeTokenColors: [CodeTokenKind: PlatformColor]
    /// Obsidian's code palette with this theme's values, made once here because it depends on nothing else.
    let obsidianCodePalette: CodePalette
    let blockquoteBorderColor: PlatformColor?
    let highlightBackground: PlatformColor?
    let horizontalRuleColor: PlatformColor?
    let tableBorderColor: PlatformColor?
    let tableHeaderBackground: PlatformColor?
    /// Callout tint and title color by Obsidian callout type.
    let calloutColors: [String: (tint: PlatformColor, title: PlatformColor)]

    // Shapes and ornaments (theme Phase 3). Lengths are points at a 16-point text size; use
    // `scaled(_:textSize:)` to draw them at the note's size.
    struct HeadingOrnament {
        let underlineColor: PlatformColor?
        let underlineWidth: Double?
        let background: PlatformColor?
        let prefix: String?
        let prefixColor: PlatformColor?
        let isUppercase: Bool
        var isEmpty: Bool { underlineColor == nil && background == nil && prefix == nil && !isUppercase }
    }
    let headingOrnaments: [HeadingOrnament]
    let blockquoteBackground: PlatformColor?
    let blockquoteRadius: Double?
    let calloutRadius: Double?
    let calloutBorderWidth: Double?
    let calloutTintOpacity: Double?
    let tableHeaderTextColor: PlatformColor?
    let tableStripeBackground: PlatformColor?
    let listMarkerColor: PlatformColor?
    let tagRadius: Double?
    let tagBorderColor: PlatformColor?
    let tagBorderWidth: Double?
    let checkboxBorderWidth: Double?
    let checkmarkColor: PlatformColor?
    /// `dashed` or `dotted`; nil for a solid rule.
    let horizontalRuleStyle: String?
    let codeBlockBackground: PlatformColor?
    let codeBlockRadius: Double?
    let codeBlockBorderColor: PlatformColor?
    let codeBlockBorderWidth: Double?
    let highlightRadius: Double?
    let highlightTextColor: PlatformColor?
    let inlineTitleColor: PlatformColor?
    let inlineTitleScale: Double?
    let inlineTitleWeight: PlatformFont.Weight?
    let inlineTitleFamily: ResolvedFontFamily?

    /// A radius larger than any line: Graphite's tags are pills, as Obsidian's are by default.
    static let pillRadius: CGFloat = 1_000

    /// A length the theme gives at Obsidian's 16-pixel text, at `textSize`.
    static func scaled(_ length: Double, textSize: Double) -> CGFloat { CGFloat(length * textSize / 16) }

    // Sizes and fonts, the same in both appearances (light's, else dark's).
    let headingScales: [Double?]
    let headingWeights: [PlatformFont.Weight?]
    let headingFamilies: [ResolvedFontFamily?]
    let headingItalic: [Bool]
    let linksAreUnderlined: Bool
    let checkboxRadiusScale: Double?
    let blockquoteBorderThickness: Double?
    let horizontalRuleThickness: Double?
    /// The readable line width in points at Obsidian's 16-pixel text size.
    let lineWidth: Double?
    /// Line height as a multiple of the text size.
    let lineHeight: Double?
    /// The theme's text and monospace fonts, used when `appearance.json` names none.
    let textFamily: ResolvedFontFamily?
    let monospaceFamily: ResolvedFontFamily?

    static func == (left: NoteThemeStyle, right: NoteThemeStyle) -> Bool { left.tokens.fingerprint == right.tokens.fingerprint }

    /// How much contrast a color needs against the page.
    enum ContrastRole {
        case text, largeText, decoration
        func target(isIncreased: Bool) -> Double? {
            switch self {
            case .text: isIncreased ? AccentLegibility.increasedTextContrast : ThemeContrastGuard.textContrast
            case .largeText: isIncreased ? ThemeContrastGuard.textContrast : ThemeContrastGuard.largeTextContrast
            case .decoration: nil
            }
        }
    }

    /// - Parameter graphiteAccent: Graphite's accent, which accent-like colors keep in an
    ///   appearance the theme leaves alone.
    @MainActor
    init(tokens: VaultThemeTokens, graphiteAccent: PlatformColor = .systemBlue) {
        self.tokens = tokens
        let light = tokens.light, dark = tokens.dark
        // The page each appearance's colors are checked against: the theme's, else Graphite's.
        let lightPage = light.background ?? ThemeColor(red: 1, green: 1, blue: 1)
        let darkPage = dark.background ?? ThemeColor(red: 0, green: 0, blue: 0)
        func color(_ path: KeyPath<ThemeModeTokens, ThemeColor?>, _ role: ContrastRole, fallback: PlatformColor? = nil) -> PlatformColor? {
            Self.dynamicColor(light: light[keyPath: path], dark: dark[keyPath: path], role: role, lightPage: lightPage, darkPage: darkPage, fallback: fallback)
        }
        /// Text drawn on a theme's own surface (a tag pill, a table header, a highlight, code)
        /// is made readable on that surface over the page, not on the page alone.
        func color(_ path: KeyPath<ThemeModeTokens, ThemeColor?>, on surface: KeyPath<ThemeModeTokens, ThemeColor?>, fallback: PlatformColor? = nil) -> PlatformColor? {
            Self.dynamicColor(light: light[keyPath: path], dark: dark[keyPath: path], role: .text,
                              lightPage: light[keyPath: surface]?.composited(over: lightPage) ?? lightPage,
                              darkPage: dark[keyPath: surface]?.composited(over: darkPage) ?? darkPage, fallback: fallback)
        }
        background = Self.dynamicColor(light: light.background, dark: dark.background, role: .decoration, lightPage: lightPage, darkPage: darkPage,
                                       fallback: Self.systemBackground)
        textNormal = color(\.textNormal, .text, fallback: Self.systemLabel)
        textMuted = color(\.textMuted, .text, fallback: Self.systemSecondaryLabel)
        textFaint = color(\.textFaint, .decoration, fallback: Self.systemTertiaryLabel)
        // In an appearance the theme leaves alone, each color is Graphite's own.
        accent = color(\.accent, .text, fallback: graphiteAccent)
        boldColor = color(\.boldColor, .text, fallback: Self.systemLabel)
        italicColor = color(\.italicColor, .text, fallback: Self.systemLabel)
        headingColors = (0..<6).map { index in
            Self.dynamicColor(light: light.headings[index].color, dark: dark.headings[index].color, role: .largeText,
                              lightPage: lightPage, darkPage: darkPage, fallback: Self.systemLabel)
        }
        linkColor = color(\.linkColor, .text, fallback: graphiteAccent)
        unresolvedLinkColor = color(\.unresolvedLinkColor, .text, fallback: graphiteAccent)
        externalLinkColor = color(\.externalLinkColor, .text, fallback: graphiteAccent)
        tagColor = color(\.tagColor, on: \.tagBackground, fallback: graphiteAccent)
        tagBackground = color(\.tagBackground, .decoration, fallback: .clear)
        checkboxColor = color(\.checkboxColor, .decoration, fallback: graphiteAccent)
        checkboxBorderColor = color(\.checkboxBorderColor, .decoration, fallback: Self.systemSecondaryLabel)
        codeBackground = color(\.codeBackground, .decoration, fallback: MarkdownTextStyler.codeBackgroundColor)
        codeColor = color(\.codeColor, on: \.codeBackground, fallback: Self.systemLabel)
        var codeTokenColors: [CodeTokenKind: PlatformColor] = [:]
        for kind in CodeTokenKind.allCases {
            let lightColor = light.codeTokenColors?[kind.rawValue], darkColor = dark.codeTokenColors?[kind.rawValue]
            // In an appearance the theme leaves alone, Graphite's own syntax color.
            codeTokenColors[kind] = Self.dynamicColor(light: lightColor, dark: darkColor, role: .text,
                                                      lightPage: light.codeBlockBackground?.composited(over: lightPage) ?? light.codeBackground?.composited(over: lightPage) ?? lightPage,
                                                      darkPage: dark.codeBlockBackground?.composited(over: darkPage) ?? dark.codeBackground?.composited(over: darkPage) ?? darkPage,
                                                      fallback: CodeSyntaxColors.graphiteColor(for: kind))
        }
        self.codeTokenColors = codeTokenColors
        blockquoteBorderColor = color(\.blockquoteBorderColor, .decoration, fallback: graphiteAccent)
        // A highlight that could be taken for Read Aloud's blue word highlight is not used.
        let lightHighlight = light.highlightBackground.flatMap { highlight in ThemeContrastGuard.resemblesReadAloudHighlight(highlight) ? nil : highlight }
        let darkHighlight = dark.highlightBackground.flatMap { highlight in ThemeContrastGuard.resemblesReadAloudHighlight(highlight) ? nil : highlight }
        highlightBackground = Self.dynamicColor(light: lightHighlight, dark: darkHighlight, role: .decoration, lightPage: lightPage, darkPage: darkPage,
                                                fallback: MarkdownTextStyler.highlightBackgroundColor)
        horizontalRuleColor = color(\.horizontalRuleColor, .decoration, fallback: Self.systemSeparator)
        tableBorderColor = color(\.tableBorderColor, .decoration, fallback: Self.systemSeparator)
        tableHeaderBackground = color(\.tableHeaderBackground, .decoration, fallback: Self.systemFill)
        var callouts: [String: (tint: PlatformColor, title: PlatformColor)] = [:]
        for type in Set(light.calloutColors.keys).union(dark.calloutColors.keys) {
            let lightColor = light.calloutColors[type], darkColor = dark.calloutColors[type]
            guard let tint = Self.dynamicColor(light: lightColor, dark: darkColor, role: .decoration, lightPage: lightPage, darkPage: darkPage,
                                               fallback: PlatformColor.systemBlue),
                  let title = Self.dynamicCalloutTitle(light: lightColor, dark: darkColor, lightPage: lightPage, darkPage: darkPage) else { continue }
            callouts[type] = (tint, title)
        }
        calloutColors = callouts

        func either<Value>(_ path: KeyPath<ThemeModeTokens, Value?>) -> Value? { light[keyPath: path] ?? dark[keyPath: path] }
        headingOrnaments = (0..<6).map { index in
            let lightHeading = light.headings[index], darkHeading = dark.headings[index]
            return HeadingOrnament(
                underlineColor: Self.dynamicColor(light: lightHeading.underlineColor, dark: darkHeading.underlineColor, role: .decoration,
                                                  lightPage: lightPage, darkPage: darkPage, fallback: .clear),
                underlineWidth: lightHeading.underlineWidth ?? darkHeading.underlineWidth,
                background: Self.dynamicColor(light: lightHeading.background, dark: darkHeading.background, role: .decoration,
                                              lightPage: lightPage, darkPage: darkPage, fallback: .clear),
                prefix: lightHeading.prefix ?? darkHeading.prefix,
                prefixColor: Self.dynamicColor(light: lightHeading.prefixColor, dark: darkHeading.prefixColor, role: .largeText,
                                               lightPage: lightPage, darkPage: darkPage, fallback: Self.systemSecondaryLabel),
                isUppercase: (lightHeading.isUppercase ?? darkHeading.isUppercase) == true)
        }
        blockquoteBackground = color(\.blockquoteBackground, .decoration, fallback: .clear)
        blockquoteRadius = either(\.blockquoteRadius)
        calloutRadius = either(\.calloutRadius)
        calloutBorderWidth = either(\.calloutBorderWidth)
        calloutTintOpacity = either(\.calloutTintOpacity)
        tableHeaderTextColor = color(\.tableHeaderTextColor, on: \.tableHeaderBackground, fallback: Self.systemLabel)
        tableStripeBackground = color(\.tableStripeBackground, .decoration, fallback: .clear)
        // Bullets are not words, but they must still be seen: 3:1, as for large text.
        listMarkerColor = color(\.listMarkerColor, .largeText, fallback: Self.systemSecondaryLabel)
        tagRadius = either(\.tagRadius)
        tagBorderColor = color(\.tagBorderColor, .decoration, fallback: .clear)
        tagBorderWidth = either(\.tagBorderWidth)
        checkboxBorderWidth = either(\.checkboxBorderWidth)
        checkmarkColor = color(\.checkmarkColor, .decoration, fallback: .white)
        horizontalRuleStyle = either(\.horizontalRuleStyle).flatMap { style in style == "dashed" || style == "dotted" ? style : nil }
        codeBlockBackground = color(\.codeBlockBackground, .decoration, fallback: MarkdownTextStyler.codeBackgroundColor)
        codeBlockRadius = either(\.codeBlockRadius)
        codeBlockBorderColor = color(\.codeBlockBorderColor, .decoration, fallback: .clear)
        codeBlockBorderWidth = either(\.codeBlockBorderWidth)
        obsidianCodePalette = CodeSyntaxColors.obsidianPalette(
            themeTokenColors: codeTokenColors, codeColor: codeColor, codeBackground: codeBackground, codeBlockBackground: codeBlockBackground,
            quietText: textMuted, borderWidth: codeBlockBorderWidth, borderColor: codeBlockBorderColor)
        highlightRadius = either(\.highlightRadius)
        highlightTextColor = color(\.highlightTextColor, on: \.highlightBackground, fallback: Self.systemLabel)
        inlineTitleColor = Self.dynamicColor(light: light.inlineTitle.color, dark: dark.inlineTitle.color, role: .largeText,
                                             lightPage: lightPage, darkPage: darkPage, fallback: Self.systemLabel)
        inlineTitleScale = (light.inlineTitle.sizeScale ?? dark.inlineTitle.sizeScale).flatMap { scale in (1.0...4.0).contains(scale) ? scale : nil }
        inlineTitleWeight = (light.inlineTitle.weight ?? dark.inlineTitle.weight).map(Self.fontWeight)
        inlineTitleFamily = (light.inlineTitle.fontFamilies ?? dark.inlineTitle.fontFamilies).flatMap { families in
            FontFamilyList(families: families).firstAvailableFamily { name in InstalledFontFamilies.family(named: name) }
        }
        headingScales = (0..<6).map { index in light.headings[index].sizeScale ?? dark.headings[index].sizeScale }
        headingWeights = (0..<6).map { index in (light.headings[index].weight ?? dark.headings[index].weight).map(Self.fontWeight) }
        headingFamilies = (0..<6).map { index in
            (light.headings[index].fontFamilies ?? dark.headings[index].fontFamilies).flatMap { families in
                FontFamilyList(families: families).firstAvailableFamily { name in InstalledFontFamilies.family(named: name) }
            }
        }
        headingItalic = (0..<6).map { index in light.headings[index].isItalic ?? dark.headings[index].isItalic ?? false }
        linksAreUnderlined = either(\.linksAreUnderlined) ?? false
        checkboxRadiusScale = either(\.checkboxRadius).map { radius in radius / 16 }
        blockquoteBorderThickness = either(\.blockquoteBorderThickness)
        horizontalRuleThickness = either(\.horizontalRuleThickness)
        lineWidth = either(\.lineWidth)
        lineHeight = either(\.lineHeight).flatMap { height in (1.0...3.0).contains(height) ? height : nil }
        textFamily = either(\.textFontFamilies).flatMap { families in
            FontFamilyList(families: families).firstAvailableFamily { name in InstalledFontFamilies.family(named: name) }
        }
        monospaceFamily = either(\.codeFontFamilies).flatMap { families in
            FontFamilyList(families: families).firstAvailableFamily { name in InstalledFontFamilies.family(named: name) }
        }
    }

    /// A CSS weight (100 to 900) as a font weight.
    static func fontWeight(_ cssWeight: Double) -> PlatformFont.Weight {
        switch cssWeight {
        case ..<150: .ultraLight
        case ..<250: .thin
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        case ..<850: .heavy
        default: .black
        }
    }

    /// The paragraph line spacing for a line height, as TextKit adds it below a line of the
    /// font's own height (about 1.2 of its size): Obsidian's 1.5 is Graphite's 0.3.
    func lineSpacing(forTextSize textSize: CGFloat) -> CGFloat? {
        lineHeight.map { height in max(0, CGFloat(height - 1.2)) * textSize }
    }

    /// The readable column for a text size: the theme's width, which Obsidian sets in pixels
    /// for its 16-pixel text, grown with the text so as many words fit on a line.
    func readableColumnWidth(forTextSize textSize: Double) -> CGFloat? {
        lineWidth.map { width in CGFloat(width * max(textSize, 11) / 16) }
    }

    // MARK: Colors that follow the appearance

    #if canImport(UIKit)
    static let systemBackground: PlatformColor = .systemBackground
    static let systemLabel: PlatformColor = .label
    static let systemSecondaryLabel: PlatformColor = .secondaryLabel
    static let systemTertiaryLabel: PlatformColor = .tertiaryLabel
    static let systemSeparator: PlatformColor = .separator
    static let systemFill: PlatformColor = .quaternarySystemFill
    #else
    static let systemBackground: PlatformColor = .textBackgroundColor
    static let systemLabel: PlatformColor = .labelColor
    static let systemSecondaryLabel: PlatformColor = .secondaryLabelColor
    static let systemTertiaryLabel: PlatformColor = .tertiaryLabelColor
    static let systemSeparator: PlatformColor = .separatorColor
    static let systemFill: PlatformColor = .quaternaryLabelColor
    #endif

    /// A color for both appearances, each checked against its page; nil when the theme sets
    /// the value in neither, and `fallback` (Graphite's own) in the appearance it leaves alone.
    /// Every caller names Graphite's own color as the fallback: without one, an appearance
    /// the theme leaves alone would draw nothing.
    static func dynamicColor(light: ThemeColor?, dark: ThemeColor?, role: ContrastRole, lightPage: ThemeColor, darkPage: ThemeColor,
                             fallback: PlatformColor?) -> PlatformColor? {
        guard light != nil || dark != nil else { return nil }
        func variant(_ themeColor: ThemeColor?, page: ThemeColor, isIncreased: Bool) -> PlatformColor? {
            guard let themeColor else { return nil }
            guard let target = role.target(isIncreased: isIncreased) else { return platformColor(themeColor) }
            return platformColor(ThemeContrastGuard.readable(themeColor, on: page, target: target))
        }
        let lightColor = variant(light, page: lightPage, isIncreased: false), lightIncreased = variant(light, page: lightPage, isIncreased: true)
        let darkColor = variant(dark, page: darkPage, isIncreased: false), darkIncreased = variant(dark, page: darkPage, isIncreased: true)
        return appearanceColor(light: lightColor, lightIncreased: lightIncreased, dark: darkColor, darkIncreased: darkIncreased, fallback: fallback)
    }

    /// A callout title: its color, made readable on the callout's tint over the page.
    private static func dynamicCalloutTitle(light: ThemeColor?, dark: ThemeColor?, lightPage: ThemeColor, darkPage: ThemeColor) -> PlatformColor? {
        func variant(_ themeColor: ThemeColor?, page: ThemeColor, target: Double) -> PlatformColor? {
            guard let themeColor else { return nil }
            var tint = themeColor
            tint.alpha = CalloutAppearance.tintOpacity
            let tintedPage = tint.composited(over: page)
            return platformColor(ThemeContrastGuard.readable(themeColor, on: tintedPage, target: target))
        }
        guard light != nil || dark != nil else { return nil }
        return appearanceColor(light: variant(light, page: lightPage, target: ThemeContrastGuard.textContrast),
                               lightIncreased: variant(light, page: lightPage, target: AccentLegibility.increasedTextContrast),
                               dark: variant(dark, page: darkPage, target: ThemeContrastGuard.textContrast),
                               darkIncreased: variant(dark, page: darkPage, target: AccentLegibility.increasedTextContrast),
                               fallback: PlatformColor.systemBlue)
    }

    static func platformColor(_ color: ThemeColor) -> PlatformColor {
        #if canImport(UIKit)
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        #else
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        #endif
    }

    private static func appearanceColor(light: PlatformColor?, lightIncreased: PlatformColor?, dark: PlatformColor?, darkIncreased: PlatformColor?,
                                        fallback: PlatformColor?) -> PlatformColor {
        let fallbackColor = fallback ?? PlatformColor.clear
        #if canImport(UIKit)
        return UIColor { traits in
            let isIncreased = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return (isIncreased ? darkIncreased : dark) ?? fallbackColor.resolvedColor(with: traits)
            }
            return (isIncreased ? lightIncreased : light) ?? fallbackColor.resolvedColor(with: traits)
        }
        #else
        return NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
            switch match {
            case .darkAqua: return dark ?? fallbackColor
            case .accessibilityHighContrastDarkAqua: return darkIncreased ?? fallbackColor
            case .accessibilityHighContrastAqua: return lightIncreased ?? fallbackColor
            default: return light ?? fallbackColor
            }
        }
        #endif
    }
}

/// The theme's page color behind a note; nothing without a theme, so Graphite's page shows.
struct NoteThemeBackground: View {
    let theme: NoteThemeStyle?

    var body: some View {
        if let background = theme?.background {
            Color(background).ignoresSafeArea()
        }
    }
}

extension EnvironmentValues {
    /// The vault's Obsidian theme as notes draw it, or nil for Graphite's own look.
    @Entry var noteTheme: NoteThemeStyle? = nil
}
