import Foundation
import CoreText
import PDFKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
private typealias PlatformColor = UIColor
#else
import AppKit
private typealias PlatformFont = NSFont
private typealias PlatformColor = NSColor
#endif

/// The text values PDFKit gives a `/FreeText` annotation as UIKit's or AppKit's fonts and
/// colors: what it reads from `/DA`, `/Q` and `/C`, and sets for it to write them.
enum PDFPlatformFont {
    // MARK: Reading

    /// The look `/DA` gives: its font, as PDFKit reads it (the standard abbreviations
    /// included), and its color.
    static func attributes(of annotation: PDFAnnotation) -> PDFTextAttributes {
        let color = annotation.fontColor.flatMap(textColor(of:)) ?? .black
        guard let font = annotation.font else { return PDFTextAttributes(fontFamily: PDFTextAttributes.defaultFontFamily, fontSize: 12, color: color) }
        return PDFTextBoxFonts.attributes(fromPostScriptName: font.fontName, size: Double(font.pointSize), color: color)
    }

    /// `/Q`.
    static func alignment(of annotation: PDFAnnotation) -> PDFTextAlignment {
        // `/Q` has left, center and right; any other alignment PDFKit gives is left.
        let alignment = annotation.alignment
        return alignment == .center ? .center : alignment == .right ? .right : alignment == .justified ? .justified : .left
    }

    /// `/C`, the fill of a `/FreeText`; nil for none or a transparent one.
    static func fillColor(of annotation: PDFAnnotation) -> PDFTextColor? {
        textColor(of: annotation.color)
    }

    private static func textColor(of color: PlatformColor) -> PDFTextColor? {
        guard let components = color.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                                       intent: .defaultIntent, options: nil)?.components,
              components.count >= 3, (components.count < 4 || components[3] > 0) else { return nil }
        return PDFTextColor(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }

    // MARK: Writing

    /// Gives the annotation the font, color and alignment that PDFKit writes as `/DA` and
    /// `/Q`, and the fill it writes as `/C`.
    static func apply(_ box: PDFTextBox, to annotation: PDFAnnotation) {
        let attributes = box.leadingAttributes
        let coreTextFont = PDFTextBoxFonts.font(for: attributes)
        annotation.font = PlatformFont(name: CTFontCopyPostScriptName(coreTextFont) as String, size: CGFloat(attributes.fontSize))
        annotation.fontColor = platformColor(attributes.color)
        annotation.alignment = switch box.style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
        annotation.color = box.style.fillColor.map(platformColor) ?? .clear
    }

    private static func platformColor(_ color: PDFTextColor) -> PlatformColor {
        #if canImport(UIKit)
        UIColor(cgColor: PDFTextBoxLayout.cgColor(color))
        #else
        NSColor(cgColor: PDFTextBoxLayout.cgColor(color)) ?? .black
        #endif
    }
}
