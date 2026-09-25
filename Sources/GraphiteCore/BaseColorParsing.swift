import Foundation

/// A color written in a note for a map marker: a CSS color or an Obsidian theme color.
public enum BaseColorSpecification: Hashable, Sendable {
    /// Components between 0 and 1.
    case rgba(red: Double, green: Double, blue: Double, alpha: Double)
    /// `var(--color-accent)` or `var(--interactive-accent)`.
    case accent
    /// `var(--color-red)` and the other Obsidian palette variables, by name.
    case theme(String)
}

/// Parses the CSS color syntaxes the Maps plugin accepts for `markerColor`: hex,
/// `rgb()`/`rgba()`, `hsl()`/`hsla()`, the CSS named colors and Obsidian's color variables.
/// Text that CSS would reject gives nil rather than a guessed color.
public enum BaseColorParsing {
    public static func color(from text: String) -> BaseColorSpecification? {
        let trimmedText = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedText.isEmpty, trimmedText.count <= 64 else { return nil }
        if trimmedText.hasPrefix("#") { return hexColor(String(trimmedText.dropFirst())) }
        if trimmedText.hasPrefix("var(") && trimmedText.hasSuffix(")") { return variableColor(trimmedText.dropFirst(4).dropLast()) }
        if let arguments = functionArguments(trimmedText, names: ["rgb", "rgba"]) { return rgbColor(arguments) }
        if let arguments = functionArguments(trimmedText, names: ["hsl", "hsla"]) { return hslColor(arguments) }
        guard let hexValue = namedColors[trimmedText] else { return nil }
        return hexColor(hexValue)
    }

    /// Obsidian's palette variables, `--color-red` through `--color-pink`.
    private static let obsidianPaletteNames: Set<String> = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"]

    /// `var(--name)` or `var(--name, fallback)`. As in CSS, the fallback applies when the
    /// variable is not one Obsidian defines.
    private static func variableColor(_ argumentText: Substring) -> BaseColorSpecification? {
        let argumentParts = argumentText.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let variable = argumentParts[0].trimmingCharacters(in: .whitespaces)
        let fallback = argumentParts.count > 1 ? argumentParts[1].trimmingCharacters(in: .whitespaces) : ""
        if ["--color-accent", "--interactive-accent", "--text-accent"].contains(variable) { return .accent }
        let paletteName = variable.hasPrefix("--color-") ? String(variable.dropFirst("--color-".count)) : nil
        if let paletteName, obsidianPaletteNames.contains(paletteName) { return .theme(paletteName) }
        if !fallback.isEmpty { return color(from: fallback) }
        // Without a fallback, another `--color-` name still names a theme color, which
        // the view draws in the accent color.
        if let paletteName, !paletteName.isEmpty { return .theme(paletteName) }
        return nil
    }

    private static func rgbColor(_ arguments: [String]) -> BaseColorSpecification? {
        func channel(_ argument: String) -> Double? {
            if argument.hasSuffix("%") { return Double(decimalText: argument.dropLast()).map { percent in percent / 100 } }
            return Double(decimalText: argument).map { value in value / 255 }
        }
        guard let red = channel(arguments[0]), let green = channel(arguments[1]), let blue = channel(arguments[2]),
              let alpha = alpha(arguments.count > 3 ? arguments[3] : nil) else { return nil }
        return .rgba(red: clamp(red), green: clamp(green), blue: clamp(blue), alpha: alpha)
    }

    private static func hslColor(_ arguments: [String]) -> BaseColorSpecification? {
        // Saturation and lightness are percentages; the `%` is optional, as in CSS Color 4.
        func percentage(_ argument: String) -> Double? {
            Double(decimalText: argument.hasSuffix("%") ? argument.dropLast() : Substring(argument))
        }
        guard let hue = hueDegrees(arguments[0]), let saturation = percentage(arguments[1]), let lightness = percentage(arguments[2]),
              let alpha = alpha(arguments.count > 3 ? arguments[3] : nil) else { return nil }
        let (red, green, blue) = rgb(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
        return .rgba(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// CSS angle units in degrees per unit. `grad` comes before `rad`, which it ends with.
    private static let hueUnits: [(suffix: String, degreesPerUnit: Double)] = [("deg", 1), ("grad", 0.9), ("rad", 180 / .pi), ("turn", 360)]

    /// A hue in degrees; a bare number is already degrees.
    private static func hueDegrees(_ argument: String) -> Double? {
        let unit = hueUnits.first { unit in argument.hasSuffix(unit.suffix) }
        let numberText = unit.map { unit in argument.dropLast(unit.suffix.count) } ?? Substring(argument)
        // An infinite hue, written (`1e999`) or reached through the unit (`1e308turn`), has
        // no remainder modulo 360, so it names no hue.
        guard let number = Double(decimalText: numberText) else { return nil }
        let degrees = number * (unit?.degreesPerUnit ?? 1)
        return degrees.isFinite ? degrees : nil
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    /// Opaque when absent; nil when present but not a number or percentage.
    private static func alpha(_ argument: String?) -> Double? {
        guard let argument else { return 1 }
        if argument.hasSuffix("%") { return Double(decimalText: argument.dropLast()).map { percent in clamp(percent / 100) } }
        return Double(decimalText: argument).map(clamp)
    }

    /// The arguments of `name(a, b, c)`, `name(a, b, c, alpha)`, `name(a b c)` or
    /// `name(a b c / alpha)`: three components and an optional alpha, as CSS requires.
    /// Empty arguments (`rgb(255,,0,0)`), extra arguments and mixed separators give nil.
    private static func functionArguments(_ text: String, names: [String]) -> [String]? {
        guard let openIndex = text.firstIndex(of: "("), text.hasSuffix(")"), names.contains(String(text[..<openIndex])) else { return nil }
        let inner = text[text.index(after: openIndex)..<text.index(before: text.endIndex)]
        let arguments: [String]
        if inner.contains(",") {
            arguments = inner.split(separator: ",", omittingEmptySubsequences: false).map { argument in argument.trimmingCharacters(in: .whitespaces) }
            let isWellFormed = arguments.allSatisfy { argument in
                !argument.isEmpty && !argument.contains("/") && !argument.contains(where: \.isWhitespace)
            }
            guard isWellFormed else { return nil }
        } else {
            let slashParts = inner.split(separator: "/", omittingEmptySubsequences: false)
            guard slashParts.count <= 2 else { return nil }
            var components = slashParts[0].split(whereSeparator: \.isWhitespace).map(String.init)
            guard components.count == 3 else { return nil }
            if slashParts.count == 2 {
                let alphaParts = slashParts[1].split(whereSeparator: \.isWhitespace)
                guard alphaParts.count == 1 else { return nil }
                components.append(String(alphaParts[0]))
            }
            arguments = components
        }
        return (3...4).contains(arguments.count) ? arguments : nil
    }

    private static func hexColor(_ digits: String) -> BaseColorSpecification? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let expandedDigits: String
        switch digits.count {
        case 3, 4: expandedDigits = digits.map { digit in "\(digit)\(digit)" }.joined()
        case 6, 8: expandedDigits = digits
        default: return nil
        }
        guard let value = UInt64(expandedDigits, radix: 16) else { return nil }
        let hasAlpha = expandedDigits.count == 8
        let shift = hasAlpha ? 8 : 0
        return .rgba(red: Double((value >> (16 + shift)) & 0xFF) / 255, green: Double((value >> (8 + shift)) & 0xFF) / 255,
                     blue: Double((value >> shift) & 0xFF) / 255, alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1)
    }

    private static func rgb(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        let normalizedHue = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let clampedSaturation = clamp(saturation), clampedLightness = clamp(lightness)
        guard clampedSaturation > 0 else { return (clampedLightness, clampedLightness, clampedLightness) }
        let upper = clampedLightness < 0.5 ? clampedLightness * (1 + clampedSaturation) : clampedLightness + clampedSaturation - clampedLightness * clampedSaturation
        let lower = 2 * clampedLightness - upper
        func component(_ offset: Double) -> Double {
            var position = normalizedHue + offset
            if position < 0 { position += 1 }
            if position > 1 { position -= 1 }
            if position < 1.0 / 6 { return lower + (upper - lower) * 6 * position }
            if position < 0.5 { return upper }
            if position < 2.0 / 3 { return lower + (upper - lower) * (2.0 / 3 - position) * 6 }
            return lower
        }
        return (component(1.0 / 3), component(0), component(-1.0 / 3))
    }

    /// Every CSS named color (CSS Color Module Level 4), including `transparent`.
    private static let namedColors: [String: String] = [
        "aliceblue": "f0f8ff", "antiquewhite": "faebd7", "aqua": "00ffff", "aquamarine": "7fffd4", "azure": "f0ffff",
        "beige": "f5f5dc", "bisque": "ffe4c4", "black": "000000", "blanchedalmond": "ffebcd", "blue": "0000ff",
        "blueviolet": "8a2be2", "brown": "a52a2a", "burlywood": "deb887", "cadetblue": "5f9ea0",
        "chartreuse": "7fff00", "chocolate": "d2691e", "coral": "ff7f50", "cornflowerblue": "6495ed",
        "cornsilk": "fff8dc", "crimson": "dc143c", "cyan": "00ffff", "darkblue": "00008b", "darkcyan": "008b8b",
        "darkgoldenrod": "b8860b", "darkgray": "a9a9a9", "darkgreen": "006400", "darkgrey": "a9a9a9",
        "darkkhaki": "bdb76b", "darkmagenta": "8b008b", "darkolivegreen": "556b2f", "darkorange": "ff8c00",
        "darkorchid": "9932cc", "darkred": "8b0000", "darksalmon": "e9967a", "darkseagreen": "8fbc8f",
        "darkslateblue": "483d8b", "darkslategray": "2f4f4f", "darkslategrey": "2f4f4f", "darkturquoise": "00ced1",
        "darkviolet": "9400d3", "deeppink": "ff1493", "deepskyblue": "00bfff", "dimgray": "696969",
        "dimgrey": "696969", "dodgerblue": "1e90ff", "firebrick": "b22222", "floralwhite": "fffaf0",
        "forestgreen": "228b22", "fuchsia": "ff00ff", "gainsboro": "dcdcdc", "ghostwhite": "f8f8ff", "gold": "ffd700",
        "goldenrod": "daa520", "gray": "808080", "green": "008000", "greenyellow": "adff2f", "grey": "808080",
        "honeydew": "f0fff0", "hotpink": "ff69b4", "indianred": "cd5c5c", "indigo": "4b0082", "ivory": "fffff0",
        "khaki": "f0e68c", "lavender": "e6e6fa", "lavenderblush": "fff0f5", "lawngreen": "7cfc00",
        "lemonchiffon": "fffacd", "lightblue": "add8e6", "lightcoral": "f08080", "lightcyan": "e0ffff",
        "lightgoldenrodyellow": "fafad2", "lightgray": "d3d3d3", "lightgreen": "90ee90", "lightgrey": "d3d3d3",
        "lightpink": "ffb6c1", "lightsalmon": "ffa07a", "lightseagreen": "20b2aa", "lightskyblue": "87cefa",
        "lightslategray": "778899", "lightslategrey": "778899", "lightsteelblue": "b0c4de", "lightyellow": "ffffe0",
        "lime": "00ff00", "limegreen": "32cd32", "linen": "faf0e6", "magenta": "ff00ff", "maroon": "800000",
        "mediumaquamarine": "66cdaa", "mediumblue": "0000cd", "mediumorchid": "ba55d3", "mediumpurple": "9370db",
        "mediumseagreen": "3cb371", "mediumslateblue": "7b68ee", "mediumspringgreen": "00fa9a",
        "mediumturquoise": "48d1cc", "mediumvioletred": "c71585", "midnightblue": "191970", "mintcream": "f5fffa",
        "mistyrose": "ffe4e1", "moccasin": "ffe4b5", "navajowhite": "ffdead", "navy": "000080", "oldlace": "fdf5e6",
        "olive": "808000", "olivedrab": "6b8e23", "orange": "ffa500", "orangered": "ff4500", "orchid": "da70d6",
        "palegoldenrod": "eee8aa", "palegreen": "98fb98", "paleturquoise": "afeeee", "palevioletred": "db7093",
        "papayawhip": "ffefd5", "peachpuff": "ffdab9", "peru": "cd853f", "pink": "ffc0cb", "plum": "dda0dd",
        "powderblue": "b0e0e6", "purple": "800080", "rebeccapurple": "663399", "red": "ff0000", "rosybrown": "bc8f8f",
        "royalblue": "4169e1", "saddlebrown": "8b4513", "salmon": "fa8072", "sandybrown": "f4a460",
        "seagreen": "2e8b57", "seashell": "fff5ee", "sienna": "a0522d", "silver": "c0c0c0", "skyblue": "87ceeb",
        "slateblue": "6a5acd", "slategray": "708090", "slategrey": "708090", "snow": "fffafa",
        "springgreen": "00ff7f", "steelblue": "4682b4", "tan": "d2b48c", "teal": "008080", "thistle": "d8bfd8",
        "tomato": "ff6347", "turquoise": "40e0d0", "violet": "ee82ee", "wheat": "f5deb3", "white": "ffffff",
        "whitesmoke": "f5f5f5", "yellow": "ffff00", "yellowgreen": "9acd32", "transparent": "00000000",
    ]
}
