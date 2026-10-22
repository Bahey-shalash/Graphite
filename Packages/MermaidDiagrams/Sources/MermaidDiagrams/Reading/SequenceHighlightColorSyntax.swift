import Foundation

/// Reads the CSS color a `rect` block's line writes: `rgb()` and `rgba()`, `hsl()` and `hsla()` (with commas, or with
/// spaces and `/ alpha`), `transparent` and the 148 color names. A `#` hex color cannot be written there: Mermaid reads
/// `#` as the start of a comment.
enum SequenceHighlightColorSyntax {
    /// The color `text` names, or nil when it names none of those.
    static func color(from text: String) -> SequenceHighlightColor? {
        let written = text.trimmingCharacters(in: .whitespaces).lowercased()
        if written.hasSuffix(")"), let opening = written.firstIndex(of: "(") {
            let function = written[..<opening].trimmingCharacters(in: .whitespaces)
            let arguments = written[written.index(after: opening)..<written.index(before: written.endIndex)]
            guard let (channels, alpha) = channelsAndAlpha(arguments) else { return nil }
            switch function {
            case "rgb", "rgba": return rgb(channels, alpha: alpha)
            case "hsl", "hsla": return hsl(channels, alpha: alpha)
            default: return nil
            }
        }
        if written == "transparent" { return SequenceHighlightColor(red: 0, green: 0, blue: 0, alpha: 0) }
        return namedColor(written)
    }

    /// The three channels and the alpha, if given: `a, b, c[, alpha]` or `a b c[ / alpha]`.
    private static func channelsAndAlpha(_ arguments: Substring) -> ([Substring], Substring?)? {
        if arguments.contains(",") {
            let parts = arguments.split(separator: ",", omittingEmptySubsequences: false).map { part in Substring(part.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 3 || parts.count == 4 else { return nil }
            return (Array(parts.prefix(3)), parts.count == 4 ? parts[3] : nil)
        }
        let halves = arguments.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count <= 2 else { return nil }
        let channels = halves[0].split(whereSeparator: { character in character == " " || character == "\t" })
        guard channels.count == 3 else { return nil }
        return (channels, halves.count == 2 ? Substring(halves[1].trimmingCharacters(in: .whitespaces)) : nil)
    }

    private static func rgb(_ channels: [Substring], alpha: Substring?) -> SequenceHighlightColor? {
        guard let red = fraction(channels[0], fullScale: 255), let green = fraction(channels[1], fullScale: 255),
              let blue = fraction(channels[2], fullScale: 255), let opacity = alphaFraction(alpha) else { return nil }
        return SequenceHighlightColor(red: red, green: green, blue: blue, alpha: opacity)
    }

    private static func hsl(_ channels: [Substring], alpha: Substring?) -> SequenceHighlightColor? {
        guard let hueTurns = turns(channels[0]), let saturation = fraction(channels[1], fullScale: 100),
              let lightness = fraction(channels[2], fullScale: 100), let opacity = alphaFraction(alpha) else { return nil }
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        func channel(_ offset: Double) -> Double {
            let position = (offset + hueTurns * 12).truncatingRemainder(dividingBy: 12)
            return lightness - chroma / 2 * max(-1, min(position - 3, 9 - position, 1))
        }
        return SequenceHighlightColor(red: channel(0), green: channel(8), blue: channel(4), alpha: opacity)
    }

    /// A channel from 0 to 1: a number out of `fullScale`, a percentage, or `none` (zero).
    private static func fraction(_ written: Substring, fullScale: Double) -> Double? {
        if written == "none" { return 0 }
        if written.hasSuffix("%") { return Double(written.dropLast()).map { percent in clamped(percent / 100) } }
        return Double(written).map { number in clamped(number / fullScale) }
    }

    /// The alpha from 0 to 1, 1 when none is written.
    private static func alphaFraction(_ written: Substring?) -> Double? {
        guard let written else { return 1 }
        return fraction(written, fullScale: 1)
    }

    /// A hue in turns: degrees by default, or with its unit (`deg`, `grad`, `rad`, `turn`).
    private static func turns(_ written: Substring) -> Double? {
        let units: [(suffix: String, perTurn: Double)] = [("deg", 360), ("grad", 400), ("rad", 2 * Double.pi), ("turn", 1)]
        for unit in units where written.hasSuffix(unit.suffix) {
            return Double(written.dropLast(unit.suffix.count)).map { value in positiveRemainder(value / unit.perTurn) }
        }
        if written == "none" { return 0 }
        return Double(written).map { degrees in positiveRemainder(degrees / 360) }
    }

    private static func positiveRemainder(_ turns: Double) -> Double {
        let remainder = turns.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Looks `name` up in `namedColors`, a name then its six hexadecimal digits, by spaces and line breaks.
    private static func namedColor(_ name: String) -> SequenceHighlightColor? {
        let tokens = namedColors.split(whereSeparator: { character in character == " " || character == "\n" })
        var index = 0
        while index + 1 < tokens.count {
            if tokens[index] == name, let value = UInt32(tokens[index + 1], radix: 16) {
                let maximumChannel: Double = 255
                return SequenceHighlightColor(red: Double(value >> 16 & 0xFF) / maximumChannel, green: Double(value >> 8 & 0xFF) / maximumChannel,
                                              blue: Double(value & 0xFF) / maximumChannel)
            }
            index += 2
        }
        return nil
    }

    /// CSS's color names (CSS Color Module Level 4) and their sRGB values.
    private static let namedColors = """
        aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff beige f5f5dc bisque ffe4c4
        black 000000 blanchedalmond ffebcd blue 0000ff blueviolet 8a2be2 brown a52a2a burlywood deb887 cadetblue 5f9ea0
        chartreuse 7fff00 chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c cyan 00ffff
        darkblue 00008b darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 darkgreen 006400 darkgrey a9a9a9 darkkhaki bdb76b
        darkmagenta 8b008b darkolivegreen 556b2f darkorange ff8c00 darkorchid 9932cc darkred 8b0000 darksalmon e9967a
        darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f darkslategrey 2f4f4f darkturquoise 00ced1
        darkviolet 9400d3 deeppink ff1493 deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff firebrick b22222
        floralwhite fffaf0 forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc ghostwhite f8f8ff gold ffd700 goldenrod daa520
        gray 808080 green 008000 greenyellow adff2f grey 808080 honeydew f0fff0 hotpink ff69b4 indianred cd5c5c indigo 4b0082
        ivory fffff0 khaki f0e68c lavender e6e6fa lavenderblush fff0f5 lawngreen 7cfc00 lemonchiffon fffacd lightblue add8e6
        lightcoral f08080 lightcyan e0ffff lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3
        lightpink ffb6c1 lightsalmon ffa07a lightseagreen 20b2aa lightskyblue 87cefa lightslategray 778899
        lightslategrey 778899 lightsteelblue b0c4de lightyellow ffffe0 lime 00ff00 limegreen 32cd32 linen faf0e6
        magenta ff00ff maroon 800000 mediumaquamarine 66cdaa mediumblue 0000cd mediumorchid ba55d3 mediumpurple 9370db
        mediumseagreen 3cb371 mediumslateblue 7b68ee mediumspringgreen 00fa9a mediumturquoise 48d1cc mediumvioletred c71585
        midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 moccasin ffe4b5 navajowhite ffdead navy 000080 oldlace fdf5e6
        olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 palegoldenrod eee8aa palegreen 98fb98
        paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 peachpuff ffdab9 peru cd853f pink ffc0cb plum dda0dd
        powderblue b0e0e6 purple 800080 rebeccapurple 663399 red ff0000 rosybrown bc8f8f royalblue 4169e1 saddlebrown 8b4513
        salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee sienna a0522d silver c0c0c0 skyblue 87ceeb
        slateblue 6a5acd slategray 708090 slategrey 708090 snow fffafa springgreen 00ff7f steelblue 4682b4 tan d2b48c
        teal 008080 thistle d8bfd8 tomato ff6347 turquoise 40e0d0 violet ee82ee wheat f5deb3 white ffffff whitesmoke f5f5f5
        yellow ffff00 yellowgreen 9acd32
        """
}
