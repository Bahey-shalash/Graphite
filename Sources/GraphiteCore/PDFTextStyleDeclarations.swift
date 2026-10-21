import Foundation

/// The CSS-like style text of PDF rich text: the `style` attributes of `/RC` and the whole
/// of `/DS` ("font: Helvetica,sans-serif 12.0pt; text-align:left; color:#FF0000").
/// It reads the properties the PDF standard lists for rich text and ignores the others.
public enum PDFTextStyleDeclarations {
    /// The properties of one style text, each absent when the text does not set it.
    public struct Properties: Sendable, Equatable {
        public var fontFamily: String?
        public var fontSize: Double?
        public var color: PDFTextColor?
        public var isBold: Bool?
        public var isItalic: Bool?
        public var isUnderlined: Bool?
        public var alignment: PDFTextAlignment?

        public init() {}

        /// `attributes` with every property this text sets applied.
        public func applied(to attributes: PDFTextAttributes) -> PDFTextAttributes {
            PDFTextAttributes(fontFamily: fontFamily ?? attributes.fontFamily, fontSize: fontSize ?? attributes.fontSize,
                              color: color ?? attributes.color, isBold: isBold ?? attributes.isBold, isItalic: isItalic ?? attributes.isItalic,
                              isUnderlined: isUnderlined ?? attributes.isUnderlined, link: attributes.link)
        }
    }

    /// Bounds the style text read, as `/DS` is read from any file.
    public static let maximumUTF16Count = 4_096

    public static func properties(of styleText: String) -> Properties {
        var properties = Properties()
        guard styleText.utf16.count <= maximumUTF16Count else { return properties }
        for declaration in styleText.split(separator: ";") {
            guard let colon = declaration.firstIndex(of: ":") else { continue }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            apply(property: property, value: value, to: &properties)
        }
        return properties
    }

    private static func apply(property: String, value: String, to properties: inout Properties) {
        switch property {
        case "font": applyFontShorthand(value, to: &properties)
        case "font-family": properties.fontFamily = family(fromList: value)
        case "font-size": properties.fontSize = size(value)
        case "font-weight": properties.isBold = isBoldWeight(value)
        case "font-style": properties.isItalic = ["italic", "oblique"].contains(value.lowercased())
        case "color": properties.color = color(value)
        case "text-decoration": properties.isUnderlined = value.lowercased().contains("underline") || value.lowercased() == "word"
        case "text-align": properties.alignment = alignment(value)
        default: break
        }
    }

    /// `font: [style] [weight] size family`, in the order CSS gives it or Acrobat's, family
    /// first: every word that is a size, a style or a weight is taken as such, and the rest
    /// is the family list.
    private static func applyFontShorthand(_ value: String, to properties: inout Properties) {
        var familyWords: [Substring] = []
        for word in value.split(separator: " ", omittingEmptySubsequences: true) {
            let lowercased = word.lowercased()
            if let fontSize = size(String(word)) {
                properties.fontSize = fontSize
            } else if ["italic", "oblique"].contains(lowercased) {
                properties.isItalic = true
            } else if let isBold = isBoldWeight(lowercased), lowercased != "normal" || properties.isBold == nil {
                properties.isBold = isBold
            } else if lowercased != "normal" {
                familyWords.append(word)
            }
        }
        if !familyWords.isEmpty { properties.fontFamily = family(fromList: familyWords.joined(separator: " ")) }
    }

    /// The first family of a list, unquoted; a generic family as the font that stands for it.
    static func family(fromList list: String) -> String? {
        guard let first = list.split(separator: ",").first else { return nil }
        let family = first.trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
        switch family.lowercased() {
        case "": return nil
        case "sans-serif": return "Helvetica"
        case "serif": return "Times New Roman"
        case "monospace": return "Courier"
        default: return family
        }
    }

    /// A size in points: `12pt`, `12.0pt`, `16px` (a CSS pixel is ¾ point) or a bare number.
    static func size(_ value: String) -> Double? {
        let lowercased = value.lowercased()
        let (digits, factor): (Substring, Double) = lowercased.hasSuffix("pt") ? (lowercased.dropLast(2), 1)
            : lowercased.hasSuffix("px") ? (lowercased.dropLast(2), 0.75) : (Substring(lowercased), 1)
        guard let number = Double(digits), number.isFinite, number > 0 else { return nil }
        return number * factor
    }

    private static func isBoldWeight(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "bold", "bolder": true
        case "normal", "lighter": false
        default: Int(value).map { weight in weight >= 600 }
        }
    }

    /// `#rrggbb`, `#rgb` or `rgb(r, g, b)` with components from 0 to 255.
    static func color(_ value: String) -> PDFTextColor? {
        if let hexColor = PDFTextColor(hex: value) { return hexColor }
        let lowercased = value.lowercased()
        guard lowercased.hasPrefix("rgb("), lowercased.hasSuffix(")") else { return nil }
        let components = lowercased.dropFirst(4).dropLast().split(separator: ",").compactMap { component in
            Double(component.trimmingCharacters(in: .whitespaces))
        }
        guard components.count == 3 else { return nil }
        return PDFTextColor(red: components[0] / 255, green: components[1] / 255, blue: components[2] / 255)
    }

    private static func alignment(_ value: String) -> PDFTextAlignment? {
        switch value.lowercased() {
        case "left", "start": .left
        case "center", "centre": .center
        case "right", "end": .right
        case "justify": .justified
        default: nil
        }
    }

    // MARK: Writing

    /// The style text of attributes, as Acrobat writes it in `/RC` spans.
    public static func styleText(of attributes: PDFTextAttributes) -> String {
        "font-family:" + quotedFamily(attributes.fontFamily) + ";font-size:" + pointText(attributes.fontSize) + "pt;color:" + attributes.color.hex
            + ";font-weight:" + (attributes.isBold ? "bold" : "normal") + ";font-style:" + (attributes.isItalic ? "italic" : "normal")
            + ";text-decoration:" + (attributes.isUnderlined ? "underline" : "none")
    }

    /// The box's default style, `/DS`: the font, alignment and color of the start of its text.
    public static func defaultStyleText(of box: PDFTextBox) -> String {
        let attributes = box.leadingAttributes
        let face = (attributes.isItalic ? "italic " : "") + (attributes.isBold ? "bold " : "")
        return "font: " + face + quotedFamily(attributes.fontFamily) + " " + pointText(attributes.fontSize) + "pt; text-align:"
            + cssAlignment(box.style.alignment) + "; color:" + attributes.color.hex
    }

    static func cssAlignment(_ alignment: PDFTextAlignment) -> String {
        switch alignment {
        case .left: "left"
        case .center: "center"
        case .right: "right"
        case .justified: "justify"
        }
    }

    /// A family with spaces in quotes, as CSS needs it.
    private static func quotedFamily(_ family: String) -> String {
        let cleaned = family.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: ";", with: "").replacingOccurrences(of: "\"", with: "")
        return cleaned.contains(" ") ? "'" + cleaned + "'" : cleaned
    }

    /// A size with at most two decimals, written the same on every device.
    static func pointText(_ size: Double) -> String {
        let rounded = (size * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}
