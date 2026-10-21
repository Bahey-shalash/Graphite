import Foundation
import CoreText
import GraphiteCore

/// The fonts typed text is drawn in, found by family and face with Core Text, the same on
/// iPad, iPhone and Mac. A family this device does not have is drawn in Helvetica, and a
/// face a family lacks (a bold of a font without one) in the family's regular face; the
/// box keeps the family it names, so another device that has the font draws it.
public enum PDFTextBoxFonts {
    /// The families offered for new text, each on every device Graphite runs on.
    public static let offeredFamilies = ["Helvetica", "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Courier New", "Menlo"]
    static let fallbackFamily = "Helvetica"

    public static func font(for attributes: PDFTextAttributes) -> CTFont {
        let size = CGFloat(attributes.fontSize)
        let regular = regularFont(family: attributes.fontFamily, size: size)
        var traits: CTFontSymbolicTraits = []
        if attributes.isBold { traits.insert(.traitBold) }
        if attributes.isItalic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return regular }
        let mask: CTFontSymbolicTraits = [.traitBold, .traitItalic]
        return CTFontCreateCopyWithSymbolicTraits(regular, size, nil, traits, mask)
            ?? CTFontCreateCopyWithSymbolicTraits(regular, size, nil, traits.intersection(.traitBold), mask)
            ?? regular
    }

    /// The family's regular face, or Helvetica's when the device lacks the family.
    private static func regularFont(family: String, size: CGFloat) -> CTFont {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: family] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        if (CTFontCopyFamilyName(font) as String).caseInsensitiveCompare(family) == .orderedSame { return font }
        let fallback = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: fallbackFamily] as CFDictionary)
        return CTFontCreateWithFontDescriptor(fallback, size, nil)
    }

    /// The PostScript name and size of the font the looks are drawn in, at `scale` times
    /// their size, for a font of UIKit or AppKit.
    public static func postScriptFont(for attributes: PDFTextAttributes, scale: Double) -> (name: String, pointSize: Double) {
        let scaled = PDFTextAttributes(fontFamily: attributes.fontFamily, fontSize: attributes.fontSize * scale, color: attributes.color,
                                       isBold: attributes.isBold, isItalic: attributes.isItalic)
        let font = font(for: scaled)
        return (CTFontCopyPostScriptName(font) as String, Double(CTFontGetSize(font)))
    }

    /// Whether this device draws the family as itself, not in Helvetica.
    public static func isAvailable(family: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute as String: family] as CFDictionary)
        return (CTFontCopyFamilyName(CTFontCreateWithFontDescriptor(descriptor, 12, nil)) as String).caseInsensitiveCompare(family) == .orderedSame
    }

    /// The family and face a PostScript name gives, as `/DA` names its font ("Helvetica-Bold",
    /// "TimesNewRomanPS-ItalicMT", or the standard abbreviations "Helv", "TiBo").
    public static func attributes(fromPostScriptName postScriptName: String, size: Double, color: PDFTextColor) -> PDFTextAttributes {
        if let standard = standardAbbreviations[postScriptName] {
            return PDFTextAttributes(fontFamily: standard.family, fontSize: size, color: color, isBold: standard.isBold, isItalic: standard.isItalic)
        }
        let font = CTFontCreateWithName(postScriptName as CFString, CGFloat(max(size, 1)), nil)
        let traits = CTFontGetSymbolicTraits(font)
        let family = CTFontCopyFamilyName(font) as String
        let isKnown = (CTFontCopyPostScriptName(font) as String) == postScriptName
        return PDFTextAttributes(fontFamily: isKnown ? family : fallbackFamily, fontSize: size, color: color,
                                 isBold: isKnown ? traits.contains(.traitBold) : postScriptName.localizedCaseInsensitiveContains("bold"),
                                 isItalic: isKnown ? traits.contains(.traitItalic)
                                    : postScriptName.localizedCaseInsensitiveContains("italic") || postScriptName.localizedCaseInsensitiveContains("oblique"))
    }

    /// The abbreviations of the standard 14 fonts that Acrobat writes in `/DA`.
    private static let standardAbbreviations: [String: (family: String, isBold: Bool, isItalic: Bool)] = [
        "Helv": ("Helvetica", false, false), "HeBo": ("Helvetica", true, false), "HeOb": ("Helvetica", false, true), "HeBO": ("Helvetica", true, true),
        "TiRo": ("Times New Roman", false, false), "TiBo": ("Times New Roman", true, false), "TiIt": ("Times New Roman", false, true),
        "TiBI": ("Times New Roman", true, true), "Cour": ("Courier", false, false), "CoBo": ("Courier", true, false),
        "CoOb": ("Courier", false, true), "CoBO": ("Courier", true, true),
    ]
}
