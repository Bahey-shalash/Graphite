import Foundation

/// An sRGB color with alpha, as WebKit's computed styles report colors (`rgb(…)`, `rgba(…)`,
/// `color(srgb …)`).
public struct ThemeColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// Reads a computed CSS color: `rgb(46, 52, 64)`, `rgba(0, 0, 0, 0.1)`, the space-separated
    /// forms, and `color(srgb 0.18 0.2 0.25 / 0.5)`, which WebKit gives for `color-mix()`.
    /// Nil for anything else, including `transparent`-like fully transparent values when
    /// `keepsTransparent` is false.
    public init?(computedCSS text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        func numbers(in body: Substring) -> [Double] {
            body.replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: ",", with: " ")
                .split(separator: " ").compactMap { part -> Double? in
                    if part.hasSuffix("%") { return Double(part.dropLast()).map { value in value / 100 } }
                    return Double(part)
                }
        }
        if trimmed.hasPrefix("rgb"), let open = trimmed.firstIndex(of: "("), let close = trimmed.lastIndex(of: ")") {
            let values = numbers(in: trimmed[trimmed.index(after: open)..<close])
            guard values.count >= 3 else { return nil }
            self.init(red: values[0] / 255, green: values[1] / 255, blue: values[2] / 255, alpha: values.count > 3 ? values[3] : 1)
            return
        }
        if trimmed.hasPrefix("color(srgb"), let close = trimmed.lastIndex(of: ")") {
            let body = trimmed[trimmed.index(trimmed.startIndex, offsetBy: "color(srgb".count)..<close]
            let values = numbers(in: body)
            guard values.count >= 3 else { return nil }
            self.init(red: values[0], green: values[1], blue: values[2], alpha: values.count > 3 ? values[3] : 1)
            return
        }
        return nil
    }

    /// `#rrggbb` or `#rrggbbaa` when not opaque.
    public var hex: String {
        func component(_ value: Double) -> String { String(format: "%02x", Int((min(max(value, 0), 1) * 255).rounded())) }
        return "#" + component(red) + component(green) + component(blue) + (alpha < 0.999 ? component(alpha) : "")
    }

    public var isVisible: Bool { alpha > 0.01 }

    /// The color laid over `background`, as it shows on screen.
    public func composited(over background: ThemeColor) -> ThemeColor {
        ThemeColor(red: red * alpha + background.red * (1 - alpha), green: green * alpha + background.green * (1 - alpha),
                   blue: blue * alpha + background.blue * (1 - alpha), alpha: 1)
    }

    public var relativeLuminance: Double { AccentLegibility.relativeLuminance(red: red, green: green, blue: blue) }

    /// WCAG contrast with another opaque color.
    public func contrast(with other: ThemeColor) -> Double {
        AccentLegibility.contrast(betweenLuminance: relativeLuminance, and: other.relativeLuminance)
    }

    /// Hue in degrees, for telling colors apart; nil for grays.
    public var hue: Double? {
        let maximum = max(red, green, blue), minimum = min(red, green, blue), range = maximum - minimum
        guard range > 0.04 else { return nil }
        var hueValue: Double
        switch maximum {
        case red: hueValue = ((green - blue) / range).truncatingRemainder(dividingBy: 6)
        case green: hueValue = (blue - red) / range + 2
        default: hueValue = (red - green) / range + 4
        }
        hueValue *= 60
        return hueValue < 0 ? hueValue + 360 : hueValue
    }
}

/// Keeps a theme's text colors readable on its own page color, as Graphite keeps its accent
/// readable (`AccentLegibility`): a color that reads is kept, one that does not is moved
/// toward black on a light page or white on a dark one by the smallest amount that reads.
public enum ThemeContrastGuard {
    /// Body text and anything a person reads as content.
    public static let textContrast = AccentLegibility.minimumTextContrast
    /// Headings and other large text, which WCAG and Apple's guidelines allow at 3:1.
    public static let largeTextContrast = 3.0

    /// `color` (composited over `background` if translucent) made to reach `target` against
    /// `background`. Increase Contrast asks for `AccentLegibility.increasedTextContrast`.
    public static func readable(_ color: ThemeColor, on background: ThemeColor, target: Double) -> ThemeColor {
        let opaqueColor = color.composited(over: background)
        guard opaqueColor.contrast(with: background) < target else { return opaqueColor }
        let backgroundIsLight = background.relativeLuminance > 0.18
        let moved: (red: Double, green: Double, blue: Double)
        if backgroundIsLight {
            moved = AccentLegibility.darkenedForLightBackground(red: opaqueColor.red, green: opaqueColor.green, blue: opaqueColor.blue,
                                                                backgroundLuminance: background.relativeLuminance, targetContrast: target)
        } else {
            moved = lightened(opaqueColor, on: background, target: target)
        }
        return ThemeColor(red: moved.red, green: moved.green, blue: moved.blue)
    }

    private static func lightened(_ color: ThemeColor, on background: ThemeColor, target: Double) -> (red: Double, green: Double, blue: Double) {
        var lowerFraction = 0.0, upperFraction = 1.0
        func mixed(_ fraction: Double) -> ThemeColor {
            ThemeColor(red: color.red + (1 - color.red) * fraction, green: color.green + (1 - color.green) * fraction, blue: color.blue + (1 - color.blue) * fraction)
        }
        for _ in 0..<24 {
            let middle = (lowerFraction + upperFraction) / 2
            if mixed(middle).contrast(with: background) >= target { upperFraction = middle } else { lowerFraction = middle }
        }
        let result = mixed(upperFraction)
        return (result.red, result.green, result.blue)
    }

    /// Whether a theme's highlight could be taken for Read Aloud's blue word highlight: a
    /// blue or cyan hue. Such a highlight is replaced by Graphite's own yellow.
    public static func resemblesReadAloudHighlight(_ color: ThemeColor) -> Bool {
        guard let hue = color.hue else { return false }
        return (180...255).contains(hue)
    }
}

/// What a theme sets for one appearance, light or dark, resolved by WebKit from the theme,
/// the snippets and Graphite's own default variables. A value the theme leaves at Graphite's
/// default is nil, so Graphite draws it as it always does (system colors, its own sizes).
public struct ThemeModeTokens: Codable, Hashable, Sendable {
    public var background: ThemeColor?
    public var textNormal: ThemeColor?
    public var textMuted: ThemeColor?
    /// Kept for decoration (Markdown syntax markers) only, never for content.
    public var textFaint: ThemeColor?
    public var accent: ThemeColor?
    public var boldColor: ThemeColor?
    public var italicColor: ThemeColor?
    /// Six entries, `h1` to `h6`.
    public var headings: [HeadingTokens] = Array(repeating: HeadingTokens(), count: 6)
    /// By Obsidian callout type (`note`, `warning`, …), each the callout's color.
    public var calloutColors: [String: ThemeColor] = [:]
    public var linkColor: ThemeColor?
    public var unresolvedLinkColor: ThemeColor?
    public var externalLinkColor: ThemeColor?
    public var linksAreUnderlined: Bool?
    public var tagColor: ThemeColor?
    public var tagBackground: ThemeColor?
    public var checkboxColor: ThemeColor?
    public var checkboxBorderColor: ThemeColor?
    /// Checkbox corner radius in points at a 16-point text size.
    public var checkboxRadius: Double?
    public var codeBackground: ThemeColor?
    public var codeColor: ThemeColor?
    /// The theme's monospace font list (`--font-monospace-theme`), when it sets one.
    public var codeFontFamilies: [String]?
    public var textFontFamilies: [String]?
    public var blockquoteBorderColor: ThemeColor?
    public var blockquoteBorderThickness: Double?
    public var highlightBackground: ThemeColor?
    public var horizontalRuleColor: ThemeColor?
    public var horizontalRuleThickness: Double?
    public var tableBorderColor: ThemeColor?
    public var tableHeaderBackground: ThemeColor?
    /// The readable line width in points at a 16-point text size.
    public var lineWidth: Double?
    /// Line height as a multiple of the text size.
    public var lineHeight: Double?

    // Shapes and ornaments the theme gives note elements (theme Phase 3). Lengths are in
    // points at a 16-point text size; Graphite scales them with the text.
    public var blockquoteBackground: ThemeColor?
    public var blockquoteRadius: Double?
    public var calloutRadius: Double?
    public var calloutBorderWidth: Double?
    /// How strongly a callout's color tints its background (Graphite's is 0.1).
    public var calloutTintOpacity: Double?
    public var tableHeaderTextColor: ThemeColor?
    public var tableStripeBackground: ThemeColor?
    public var listMarkerColor: ThemeColor?
    public var tagRadius: Double?
    public var tagBorderColor: ThemeColor?
    public var tagBorderWidth: Double?
    public var checkboxBorderWidth: Double?
    public var checkmarkColor: ThemeColor?
    /// `solid`, `dashed` or `dotted`.
    public var horizontalRuleStyle: String?
    public var codeBlockBackground: ThemeColor?
    public var codeBlockRadius: Double?
    public var codeBlockBorderColor: ThemeColor?
    public var codeBlockBorderWidth: Double?
    public var highlightRadius: Double?
    public var highlightTextColor: ThemeColor?
    public var inlineTitle = HeadingTokens()
    /// Syntax colors in code blocks by `CodeTokenKind` raw value, all of them when the theme
    /// changes any (its palette or its `--code-*` variables), so its colors stay together.
    public var codeTokenColors: [String: ThemeColor]?

    public init() {}

    /// The Prism token class the theme probe reads each `CodeTokenKind`'s color from.
    public static let codeTokenProbeClasses: [String: String] = [
        CodeTokenKind.keyword.rawValue: "keyword", CodeTokenKind.typeName.rawValue: "class-name", CodeTokenKind.function.rawValue: "function",
        CodeTokenKind.string.rawValue: "string", CodeTokenKind.number.rawValue: "number", CodeTokenKind.constant.rawValue: "boolean",
        CodeTokenKind.comment.rawValue: "comment", CodeTokenKind.preprocessor.rawValue: "important", CodeTokenKind.attribute.rawValue: "tag",
        CodeTokenKind.property.rawValue: "property", CodeTokenKind.variable.rawValue: "variable",
        CodeTokenKind.identifier.rawValue: "property", CodeTokenKind.operator.rawValue: "operator",
    ]

    public struct HeadingTokens: Codable, Hashable, Sendable {
        public var color: ThemeColor?
        /// The heading's size as a multiple of the text size.
        public var sizeScale: Double?
        public var weight: Double?
        public var fontFamilies: [String]?
        public var isItalic: Bool?
        /// Ornaments: a line under the heading, a background, and text the theme puts before
        /// it (`::before`), such as a level marker.
        public var underlineColor: ThemeColor?
        public var underlineWidth: Double?
        public var background: ThemeColor?
        public var prefix: String?
        public var prefixColor: ThemeColor?
        public var isUppercase: Bool?

        public init() {}

        public var hasOrnament: Bool { underlineColor != nil || background != nil || prefix != nil || isUppercase == true }
    }

    /// Whether the theme changes each note-styling group, the 19 of Phase 1 first.
    public var changedGroups: [Bool] {
        [
            background != nil, textNormal != nil || textMuted != nil, accent != nil || linkColor != nil,
            headings.contains { heading in heading.color != nil }, headings.contains { heading in heading.sizeScale != nil },
            headings.contains { heading in heading.weight != nil || heading.fontFamilies != nil },
            !calloutColors.isEmpty, tagColor != nil || tagBackground != nil, unresolvedLinkColor != nil || externalLinkColor != nil,
            checkboxColor != nil || checkboxBorderColor != nil, codeBackground != nil || codeColor != nil || codeFontFamilies != nil,
            blockquoteBorderColor != nil, highlightBackground != nil, horizontalRuleColor != nil, tableBorderColor != nil || tableHeaderBackground != nil,
            lineWidth != nil, lineHeight != nil, boldColor != nil || italicColor != nil, textFontFamilies != nil,
            // Phase 3: shapes and ornaments.
            headings.contains { heading in heading.hasOrnament }, blockquoteBackground != nil || blockquoteRadius != nil,
            calloutRadius != nil || calloutBorderWidth != nil || calloutTintOpacity != nil, tableHeaderTextColor != nil || tableStripeBackground != nil,
            listMarkerColor != nil, tagRadius != nil || tagBorderColor != nil, checkboxRadius != nil || checkboxBorderWidth != nil || checkmarkColor != nil,
            horizontalRuleStyle != nil || horizontalRuleThickness != nil, codeBlockBackground != nil || codeBlockRadius != nil || codeBlockBorderColor != nil,
            highlightRadius != nil || highlightTextColor != nil,
            inlineTitle.color != nil || inlineTitle.sizeScale != nil || inlineTitle.weight != nil || inlineTitle.fontFamilies != nil,
        ]
    }

    /// How many of the note-styling groups the theme sets, for reporting coverage.
    public var changedGroupCount: Int { changedGroups.filter { isChanged in isChanged }.count }

    /// The Phase 1 groups alone, to compare a theme's coverage before and after Phase 3.
    public var changedPhaseOneGroupCount: Int { changedGroups.prefix(Self.phaseOneGroupCount).filter { isChanged in isChanged }.count }

    /// 19 groups through Phase 1, and 11 shape and ornament groups from Phase 3.
    public static let groupCount = 30
    public static let phaseOneGroupCount = 19
}

/// A vault theme's resolved values for both appearances, cached per device by `fingerprint`.
public struct VaultThemeTokens: Codable, Hashable, Sendable {
    /// Identifies the inputs the values were resolved from: the default layer's version,
    /// the theme, the snippets and the plugins' classes and variables.
    public var fingerprint: String
    public var themeName: String
    public var light: ThemeModeTokens
    public var dark: ThemeModeTokens

    public init(fingerprint: String, themeName: String, light: ThemeModeTokens, dark: ThemeModeTokens) {
        self.fingerprint = fingerprint; self.themeName = themeName; self.light = light; self.dark = dark
    }
}

/// Reads the values WebKit reports for one appearance's probe elements into tokens, against
/// the same probes resolved with Graphite's default layer alone: whatever equals the default
/// is left nil.
public enum ThemeProbeReading {
    /// One appearance's computed values, by probe name (`h1.color`, `callout.note`, …).
    public typealias Values = [String: String]

    public static func tokens(themed: Values, defaults: Values) -> ThemeModeTokens {
        func changed(_ key: String) -> String? {
            guard let value = themed[key], !value.isEmpty, value != defaults[key] else { return nil }
            return value
        }
        func color(_ key: String) -> ThemeColor? { changed(key).flatMap(ThemeColor.init(computedCSS:)).flatMap { color in color.isVisible ? color : nil } }
        func anyColor(_ key: String) -> ThemeColor? { changed(key).flatMap(ThemeColor.init(computedCSS:)) }
        func number(_ key: String) -> Double? { changed(key).flatMap(pixels) }
        let bodySize = themed["body.fontSize"].flatMap(pixels) ?? 16

        var tokens = ThemeModeTokens()
        tokens.background = color("body.background")
        tokens.textNormal = color("body.color")
        tokens.textMuted = color("muted.color")
        tokens.textFaint = color("faint.color")
        tokens.accent = color("accent.color")
        tokens.boldColor = color("strong.color")
        tokens.italicColor = color("em.color")
        for level in 1...6 {
            var heading = ThemeModeTokens.HeadingTokens()
            heading.color = color("h\(level).color")
            heading.sizeScale = number("h\(level).fontSize").map { size in (size / bodySize * 1000).rounded() / 1000 }
            heading.weight = number("h\(level).fontWeight")
            heading.fontFamilies = changed("h\(level).fontFamily").map(fontFamilies)
            heading.isItalic = changed("h\(level).fontStyle").map { style in style.contains("italic") }
            tokens.headings[level - 1] = heading
        }
        for type in ObsidianCalloutTypes.variableNamesByType.keys.sorted() {
            if let calloutColor = color("callout.\(type)") { tokens.calloutColors[type] = calloutColor }
        }
        tokens.linkColor = color("link.color")
        // Obsidian always draws unresolved links dimmed (`--link-unresolved-opacity`), so with a
        // theme the color is taken as drawn, even where the theme keeps Obsidian's defaults.
        if var unresolved = themed["unresolvedLink.color"].flatMap(ThemeColor.init(computedCSS:)) {
            unresolved.alpha *= themed["unresolvedLink.opacity"].flatMap { opacity in Double(opacity) } ?? 1
            tokens.unresolvedLinkColor = unresolved.isVisible ? unresolved : nil
        }
        tokens.externalLinkColor = color("externalLink.color")
        tokens.linksAreUnderlined = changed("link.textDecorationLine").map { decoration in decoration.contains("underline") }
        tokens.tagColor = color("tag.color")
        tokens.tagBackground = anyColor("tag.background")
        tokens.checkboxColor = color("checkbox.checkedBackground")
        tokens.checkboxBorderColor = color("checkbox.borderColor")
        tokens.checkboxRadius = number("checkbox.borderRadius")
        tokens.codeBackground = anyColor("code.background")
        tokens.codeColor = color("code.color")
        tokens.codeFontFamilies = changed("code.fontFamily").map(fontFamilies)
        let codeTokenKeys = ThemeModeTokens.codeTokenProbeClasses.mapValues { tokenClass in "codeToken." + tokenClass }
        if codeTokenKeys.values.contains(where: { key in changed(key) != nil }) {
            tokens.codeTokenColors = codeTokenKeys.compactMapValues { key in
                themed[key].flatMap(ThemeColor.init(computedCSS:)).flatMap { color in color.isVisible ? color : nil }
            }
        }
        tokens.textFontFamilies = changed("body.fontFamily").map(fontFamilies)
        tokens.blockquoteBorderColor = color("blockquote.borderColor")
        tokens.blockquoteBorderThickness = number("blockquote.borderWidth")
        tokens.highlightBackground = color("mark.background")
        tokens.horizontalRuleColor = color("hr.borderColor")
        tokens.horizontalRuleThickness = number("hr.borderWidth")
        tokens.tableBorderColor = color("td.borderColor")
        tokens.tableHeaderBackground = anyColor("th.background")
        tokens.lineWidth = number("lineWidth.width")
        tokens.lineHeight = number("body.lineHeight").map { lineHeight in (lineHeight / bodySize * 1000).rounded() / 1000 }

        for level in 1...6 {
            tokens.headings[level - 1].underlineWidth = number("h\(level).borderBottomWidth").flatMap { width in width > 0 ? width : nil }
            tokens.headings[level - 1].underlineColor = tokens.headings[level - 1].underlineWidth == nil ? nil
                : themed["h\(level).borderBottomColor"].flatMap(ThemeColor.init(computedCSS:)).flatMap { color in color.isVisible ? color : nil }
            tokens.headings[level - 1].background = color("h\(level).background")
            tokens.headings[level - 1].prefix = changed("h\(level).beforeContent").flatMap(cssContentText)
            tokens.headings[level - 1].prefixColor = tokens.headings[level - 1].prefix == nil ? nil : themed["h\(level).beforeColor"].flatMap(ThemeColor.init(computedCSS:))
            tokens.headings[level - 1].isUppercase = changed("h\(level).textTransform").map { transform in transform == "uppercase" }
        }
        tokens.blockquoteBackground = color("blockquote.background")
        tokens.blockquoteRadius = number("blockquote.borderRadius")
        tokens.calloutRadius = number("callout.borderRadius")
        tokens.calloutBorderWidth = number("callout.borderWidth").flatMap { width in width > 0 ? width : nil }
        // Only a tint clearly unlike Graphite's 0.1 counts; a theme that draws callouts without
        // a tint (a border instead) keeps Graphite's, so callouts stay recognizable.
        tokens.calloutTintOpacity = changed("callout.background").flatMap(ThemeColor.init(computedCSS:)).map { background in background.alpha }
            .flatMap { alpha in (0.03...0.6).contains(alpha) && abs(alpha - 0.1) > 0.02 ? alpha : nil }
        tokens.tableHeaderTextColor = color("th.color")
        tokens.tableStripeBackground = color("stripe.background")
        tokens.listMarkerColor = color("marker.color")
        tokens.tagRadius = number("tag.borderRadius")
        tokens.tagBorderWidth = number("tag.borderWidth").flatMap { width in width > 0 ? width : nil }
        tokens.tagBorderColor = tokens.tagBorderWidth == nil ? nil : themed["tag.borderColor"].flatMap(ThemeColor.init(computedCSS:))
        tokens.checkboxBorderWidth = number("checkbox.borderWidth")
        tokens.checkmarkColor = color("checkbox.markerColor")
        tokens.horizontalRuleStyle = changed("hr.borderStyle")
        tokens.codeBlockBackground = anyColor("pre.background")
        tokens.codeBlockRadius = number("pre.borderRadius")
        tokens.codeBlockBorderWidth = number("pre.borderWidth")
        tokens.codeBlockBorderColor = tokens.codeBlockBorderWidth == nil ? nil : themed["pre.borderColor"].flatMap(ThemeColor.init(computedCSS:))
        tokens.highlightRadius = number("mark.borderRadius")
        tokens.highlightTextColor = color("mark.color")
        tokens.inlineTitle.color = color("inlineTitle.color")
        tokens.inlineTitle.sizeScale = number("inlineTitle.fontSize").map { size in (size / bodySize * 1000).rounded() / 1000 }
        tokens.inlineTitle.weight = number("inlineTitle.fontWeight")
        tokens.inlineTitle.fontFamilies = changed("inlineTitle.fontFamily").map(fontFamilies)
        return tokens
    }

    /// `16px` as 16, and a plain number (`600`) as itself.
    public static func pixels(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("px") { return Double(trimmed.dropLast(2)) }
        return Double(trimmed)
    }

    /// The text of a computed `content` value (`"H1"`, `'§ '`), or nil for `none`, `normal`,
    /// counters and images, which Graphite does not draw.
    public static func cssContentText(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == "\"" || first == "'", trimmed.last == first else { return nil }
        let text = String(trimmed.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, text.count <= 12 else { return nil }
        return text
    }

    /// A computed `font-family` as names, quotes removed.
    public static func fontFamilies(_ text: String) -> [String] {
        FontFamilyList(obsidianValue: text).families
    }
}

/// Obsidian's callout types and the variable each takes its color from, as the developer
/// documentation lists them.
public enum ObsidianCalloutTypes {
    public static let variableNamesByType: [String: String] = [
        "note": "--callout-default", "abstract": "--callout-summary", "summary": "--callout-summary", "tldr": "--callout-summary",
        "info": "--callout-info", "todo": "--callout-todo", "tip": "--callout-tip", "hint": "--callout-tip", "important": "--callout-important",
        "success": "--callout-success", "check": "--callout-success", "done": "--callout-success",
        "question": "--callout-question", "help": "--callout-question", "faq": "--callout-question",
        "warning": "--callout-warning", "caution": "--callout-warning", "attention": "--callout-warning",
        "failure": "--callout-fail", "fail": "--callout-fail", "missing": "--callout-fail",
        "danger": "--callout-error", "error": "--callout-error", "bug": "--callout-bug",
        "example": "--callout-example", "quote": "--callout-quote", "cite": "--callout-quote",
    ]

    /// The type whose color an unknown type takes, as Obsidian draws unknown types as notes.
    public static func canonicalType(_ type: String) -> String {
        let lowercased = type.lowercased()
        return variableNamesByType[lowercased] == nil ? "note" : lowercased
    }
}
