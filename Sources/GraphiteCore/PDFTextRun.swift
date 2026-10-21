import Foundation

/// A color of typed text on a PDF page, in sRGB, each component from 0 to 1.
public struct PDFTextColor: Sendable, Hashable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        func clamped(_ component: Double) -> Double { component.isFinite ? min(max(component, 0), 1) : 0 }
        self.red = clamped(red)
        self.green = clamped(green)
        self.blue = clamped(blue)
    }

    public static let black = PDFTextColor(red: 0, green: 0, blue: 0)

    /// A color written `#rrggbb` or `#rgb`, in either case; nil for anything else.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        guard digits.hasPrefix("#") else { return nil }
        digits.removeFirst()
        if digits.count == 3 { digits = digits.map { digit in "\(digit)\(digit)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// `#rrggbb` in lowercase.
    public var hex: String {
        let bytes = [red, green, blue].map { component in Int((component * 255).rounded()) }
        return String(format: "#%02x%02x%02x", bytes[0], bytes[1], bytes[2])
    }
}

/// How the lines of a text box sit between its sides.
public enum PDFTextAlignment: String, Sendable, Hashable, Codable, CaseIterable {
    case left, center, right, justified

    /// The `/Q` value of a `/FreeText` annotation, which has no justified form.
    public var quadding: Int {
        switch self {
        case .left, .justified: 0
        case .center: 1
        case .right: 2
        }
    }

    /// The alignment a `/Q` value names; left for any other value, as the standard says.
    public init(quadding: Int) {
        switch quadding {
        case 1: self = .center
        case 2: self = .right
        default: self = .left
        }
    }
}

/// How a stretch of typed text looks: its font, size and color, bold, italic and
/// underline, and the web address it links to.
public struct PDFTextAttributes: Sendable, Hashable, Codable {
    /// The font family as fonts name it ("Helvetica Neue", "Georgia"); the face follows
    /// `isBold` and `isItalic`.
    public var fontFamily: String
    /// In points of the page.
    public var fontSize: Double
    public var color: PDFTextColor
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    /// Where a tap on the text goes; written as a `/Link` annotation over the text.
    public var link: URL?

    /// Sizes a box can be set to; a size outside is brought inside.
    public static let fontSizeRange: ClosedRange<Double> = 1...512
    public static let defaultFontFamily = "Helvetica"
    public static let defaultFontSize: Double = 14
    public static let plain = PDFTextAttributes(fontFamily: defaultFontFamily, fontSize: defaultFontSize, color: .black)

    public init(fontFamily: String, fontSize: Double, color: PDFTextColor, isBold: Bool = false, isItalic: Bool = false,
                isUnderlined: Bool = false, link: URL? = nil) {
        let trimmedFamily = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fontFamily = trimmedFamily.isEmpty ? Self.defaultFontFamily : trimmedFamily
        self.fontSize = fontSize.isFinite ? min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound) : Self.defaultFontSize
        self.color = color
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.link = link
    }

    /// The same attributes at another size, for a box resized together with ink.
    public func scaled(by factor: Double) -> PDFTextAttributes {
        PDFTextAttributes(fontFamily: fontFamily, fontSize: fontSize * factor, color: color, isBold: isBold, isItalic: isItalic,
                          isUnderlined: isUnderlined, link: link)
    }
}

/// A stretch of a text box's text that looks the same throughout. Line breaks are `\n`.
public struct PDFTextRun: Sendable, Hashable, Codable {
    public var text: String
    public var attributes: PDFTextAttributes

    public init(text: String, attributes: PDFTextAttributes) {
        self.text = text
        self.attributes = attributes
    }

    /// Runs with no empty text, neighbours that look the same joined into one, and line
    /// breaks as `\n` alone: the form every box keeps, so two boxes with the same text and
    /// looks are equal however they were made.
    public static func normalized(_ runs: [PDFTextRun]) -> [PDFTextRun] {
        var normalizedRuns: [PDFTextRun] = []
        for run in runs {
            let text = run.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            guard !text.isEmpty else { continue }
            if let last = normalizedRuns.last, last.attributes == run.attributes {
                normalizedRuns[normalizedRuns.count - 1].text += text
            } else {
                normalizedRuns.append(PDFTextRun(text: text, attributes: run.attributes))
            }
        }
        return normalizedRuns
    }

    /// The runs cut in two at a place in their text, counted in UTF-16 units, as a text that
    /// flows onto the next page is cut where the page is full.
    public static func split(_ runs: [PDFTextRun], atUTF16Offset offset: Int) -> (before: [PDFTextRun], after: [PDFTextRun]) {
        var before: [PDFTextRun] = []
        var after: [PDFTextRun] = []
        var start = 0
        for run in runs {
            let length = run.text.utf16.count
            defer { start += length }
            if start + length <= offset {
                before.append(run)
            } else if start >= offset {
                after.append(run)
            } else {
                let utf16 = Array(run.text.utf16)
                let cut = offset - start
                before.append(PDFTextRun(text: String(decoding: utf16[..<cut], as: UTF16.self), attributes: run.attributes))
                after.append(PDFTextRun(text: String(decoding: utf16[cut...], as: UTF16.self), attributes: run.attributes))
            }
        }
        return (normalized(before), normalized(after))
    }
}
