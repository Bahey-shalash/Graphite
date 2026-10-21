#if canImport(UIKit)
import UIKit
import GraphiteCore
import GraphiteApple

/// A text box's runs as the attributed text of the view it is typed in, and back. The view
/// shows the box at the PDF's zoom: every size is the box's times `scale`, so the text is
/// laid out as on the page and drawn as sharp as the screen.
enum PDFTextBoxTextConversion {
    /// Where the looks of a run are kept in the attributed text, so a family the font does
    /// not name the same (a family this device lacks) comes back as the box had it.
    static let attributesKey = NSAttributedString.Key("GraphiteTextBoxAttributes")

    static func attributedText(of runs: [PDFTextRun], style: PDFTextBoxStyle, scale: CGFloat) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for run in runs {
            text.append(NSAttributedString(string: run.text, attributes: textAttributes(of: run.attributes, style: style, scale: scale)))
        }
        return text
    }

    /// The attributes text typed with these looks takes, at `scale`.
    static func textAttributes(of attributes: PDFTextAttributes, style: PDFTextBoxStyle, scale: CGFloat) -> [NSAttributedString.Key: Any] {
        let postScriptFont = PDFTextBoxFonts.postScriptFont(for: attributes, scale: Double(scale))
        let font = UIFont(name: postScriptFont.name, size: CGFloat(postScriptFont.pointSize)) ?? UIFont.systemFont(ofSize: CGFloat(attributes.fontSize) * scale)
        var textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(cgColor: PDFTextBoxLayout.cgColor(attributes.color)),
            .paragraphStyle: paragraphStyle(of: style),
            attributesKey: PDFTextAttributesBox(attributes),
        ]
        if attributes.isUnderlined { textAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let link = attributes.link { textAttributes[.link] = link }
        return textAttributes
    }

    static func paragraphStyle(of style: PDFTextBoxStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
        paragraph.lineHeightMultiple = CGFloat(style.lineSpacing)
        return paragraph
    }

    /// The runs of the attributed text, sizes taken back to the page's by `scale`. Bold,
    /// italic and underline changed in the text view (⌘B, its menu) are read from the font and
    /// the underline; the rest of each run's looks from what it was typed with.
    static func runs(of text: NSAttributedString, scale: CGFloat, typingDefaults: PDFTextAttributes) -> [PDFTextRun] {
        var runs: [PDFTextRun] = []
        let string = text.string as NSString
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var looks = (attributes[attributesKey] as? PDFTextAttributesBox)?.attributes ?? typingDefaults
            if let font = attributes[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                looks.isBold = traits.contains(.traitBold)
                looks.isItalic = traits.contains(.traitItalic)
                if scale > 0 { looks.fontSize = min(max(Double(font.pointSize / scale), PDFTextAttributes.fontSizeRange.lowerBound),
                                                    PDFTextAttributes.fontSizeRange.upperBound) }
            }
            looks.isUnderlined = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
            if let color = (attributes[.foregroundColor] as? UIColor).flatMap(textColor(of:)) { looks.color = color }
            looks.link = attributes[.link] as? URL ?? (attributes[.link] as? String).flatMap(URL.init(string:))
            runs.append(PDFTextRun(text: string.substring(with: range), attributes: looks))
        }
        return PDFTextRun.normalized(runs)
    }

    private static func textColor(of color: UIColor) -> PDFTextColor? {
        guard let components = color.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                       intent: .defaultIntent, options: nil)?.components, components.count >= 3 else { return nil }
        return PDFTextColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}

/// A run's looks kept as an attribute value of attributed text, which takes objects.
final class PDFTextAttributesBox: NSObject {
    let attributes: PDFTextAttributes

    init(_ attributes: PDFTextAttributes) {
        self.attributes = attributes
    }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? PDFTextAttributesBox)?.attributes == attributes
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(attributes)
        return hasher.finalize()
    }
}
#endif
