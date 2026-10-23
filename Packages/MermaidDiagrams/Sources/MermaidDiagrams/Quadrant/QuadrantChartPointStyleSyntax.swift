import Foundation

/// Reads the styles a quadrant chart's point or `classDef` writes, as Mermaid's quadrant database does: `radius: 10`
/// (whole points), `color: #ff3300` and `stroke-color: #10f0f0` (six or three hexadecimal digits, the `#` optional) and
/// `stroke-width: 5px`. Another name, or a value of the wrong form, is an error, as in Mermaid.
enum QuadrantChartPointStyleSyntax {
    /// The styles `styles` give, each read as `name: value`; a later style of a name replaces an earlier one.
    static func style(from styles: [String], line: Int) throws(MermaidDiagramReadError) -> QuadrantChartPointStyle {
        var style = QuadrantChartPointStyle()
        for written in styles {
            let (name, value) = nameAndValue(written)
            let invalid = MermaidDiagramReadError.invalidSyntax(line: line, problem: .invalidPointStyleValue(name: name, value: value))
            switch name {
            case radiusName:
                guard let radius = wholeNumber(value) else { throw invalid }
                style.radius = radius
            case colorName:
                guard let color = color(value) else { throw invalid }
                style.color = color
            case strokeColorName:
                guard let color = color(value) else { throw invalid }
                style.strokeColor = color
            case strokeWidthName:
                guard value.hasSuffix(pixelUnit), let width = wholeNumber(String(value.dropLast(pixelUnit.count))) else { throw invalid }
                style.strokeWidth = width
            default:
                throw .invalidSyntax(line: line, problem: .unsupportedPointStyle(name: name))
            }
        }
        return style
    }

    /// The name before the first colon and the value after it up to a second colon, without the spaces around them;
    /// `undefined` as the value when there is no colon, as Mermaid's split leaves it.
    static func nameAndValue(_ written: String) -> (name: String, value: String) {
        let trimmed = written.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return (trimmed, missingValue) }
        let name = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
        let rest = trimmed[trimmed.index(after: colon)...].drop { character in character.isWhitespace }
        let value = rest.prefix { character in character != ":" }
        return (name, rest.contains(":") ? value.trimmingCharacters(in: .whitespaces) : String(value))
    }

    /// Digits only, as a number of points; a number too large for an integer is the largest one.
    private static func wholeNumber(_ text: String) -> Double? {
        guard !text.isEmpty, text.utf8.allSatisfy(MermaidByte.isDigit) else { return nil }
        return Double(text)
    }

    /// Six or three hexadecimal digits, the `#` before them optional; three stand for each one doubled.
    private static func color(_ text: String) -> QuadrantChartColor? {
        let digits = Array(text.hasPrefix("#") ? text.utf8.dropFirst() : text.utf8[...])
        guard digits.count == 6 || digits.count == 3 else { return nil }
        let values = digits.compactMap(hexadecimalValue)
        guard values.count == digits.count else { return nil }
        let channels = values.count == 3 ? values.map { value in value * shortDigitScale }
            : stride(from: 0, to: values.count, by: 2).map { offset in values[offset] * 16 + values[offset + 1] }
        return QuadrantChartColor(red: channels[0], green: channels[1], blue: channels[2])
    }

    private static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// A short color's digit stands for itself twice: `f` for `ff`, 15 × 17 = 255.
    private static let shortDigitScale: UInt8 = 17
    private static let radiusName = "radius"
    private static let colorName = "color"
    private static let strokeColorName = "stroke-color"
    private static let strokeWidthName = "stroke-width"
    private static let pixelUnit = "px"
    private static let missingValue = "undefined"
}
