import Foundation

/// One change of a text box's format, as its format popover makes it: to the look of all its
/// text (font, size, color, bold, italic, underline), or of the box (alignment, fill, border).
public enum PDFTextBoxFormatChange: Sendable, Equatable {
    case fontFamily(String)
    case fontSize(Double)
    case color(PDFTextColor)
    case bold(Bool)
    case italic(Bool)
    case underline(Bool)
    case alignment(PDFTextAlignment)
    case fill(PDFTextColor?)
    /// A border of the text's color and this width, or none at 0.
    case border(width: Double)

    /// The border a box gets from the format popover.
    public static let standardBorderWidth: Double = 1

    /// The looks of text with the change made; a change of the box leaves them as they are.
    public func applied(to attributes: PDFTextAttributes) -> PDFTextAttributes {
        var changed = attributes
        switch self {
        case .fontFamily(let family): changed = PDFTextAttributes(fontFamily: family, fontSize: attributes.fontSize, color: attributes.color,
                                                                 isBold: attributes.isBold, isItalic: attributes.isItalic,
                                                                 isUnderlined: attributes.isUnderlined, link: attributes.link)
        case .fontSize(let size): changed = PDFTextAttributes(fontFamily: attributes.fontFamily, fontSize: size, color: attributes.color,
                                                             isBold: attributes.isBold, isItalic: attributes.isItalic,
                                                             isUnderlined: attributes.isUnderlined, link: attributes.link)
        case .color(let color): changed.color = color
        case .bold(let isBold): changed.isBold = isBold
        case .italic(let isItalic): changed.isItalic = isItalic
        case .underline(let isUnderlined): changed.isUnderlined = isUnderlined
        case .alignment, .fill, .border: break
        }
        return changed
    }

    /// The box's own look with the change made; a change of the text leaves it as it is.
    public func applied(to style: PDFTextBoxStyle, textColor: PDFTextColor) -> PDFTextBoxStyle {
        switch self {
        case .alignment(let alignment):
            return PDFTextBoxStyle(alignment: alignment, lineSpacing: style.lineSpacing, fillColor: style.fillColor, borderColor: style.borderColor,
                                   borderWidth: style.borderWidth, padding: style.padding)
        case .fill(let fillColor):
            return PDFTextBoxStyle(alignment: style.alignment, lineSpacing: style.lineSpacing, fillColor: fillColor, borderColor: style.borderColor,
                                   borderWidth: style.borderWidth, padding: style.padding)
        case .border(let width):
            return PDFTextBoxStyle(alignment: style.alignment, lineSpacing: style.lineSpacing, fillColor: style.fillColor,
                                   borderColor: width > 0 ? textColor : nil, borderWidth: width, padding: style.padding)
        case .fontFamily, .fontSize, .color, .bold, .italic, .underline:
            return style
        }
    }

    /// The box with the change made to all its text, or to the box.
    public func applied(to box: PDFTextBox) -> PDFTextBox {
        var changed = box
        changed.runs = box.runs.map { run in PDFTextRun(text: run.text, attributes: applied(to: run.attributes)) }
        changed.style = applied(to: box.style, textColor: box.leadingAttributes.color)
        return changed
    }
}
