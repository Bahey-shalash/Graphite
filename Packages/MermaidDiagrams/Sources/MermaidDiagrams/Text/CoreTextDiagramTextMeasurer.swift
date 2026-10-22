import CoreGraphics
import CoreText
import Foundation

/// Measures text with Core Text, as it is drawn. Printable ASCII, most of a diagram's text, is measured from a table
/// of the font's advances read once; any other text goes through a Core Text line, which finds fallback fonts for
/// scripts and emoji the font lacks. The table leaves out kerning, which the shapes' padding absorbs.
public struct CoreTextDiagramTextMeasurer: DiagramTextMeasuring {
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    private let font: CTFont
    /// Advances of the characters from space (32) to tilde (126).
    private let printableASCIIAdvances: [CGFloat]

    /// Line height as a multiple of the font size, Pele's.
    static let lineHeightRatio: CGFloat = 1.5
    private static let firstPrintableASCII: UInt8 = 32
    private static let lastPrintableASCII: UInt8 = 126

    public init(font diagramFont: DiagramFont) {
        font = diagramFont.makeCoreTextFont()
        fontSize = diagramFont.size
        lineHeight = (diagramFont.size * Self.lineHeightRatio).rounded()
        let characters = (Self.firstPrintableASCII...Self.lastPrintableASCII).map { byte in UniChar(byte) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        var advances = [CGSize](repeating: .zero, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        printableASCIIAdvances = advances.map(\.width)
    }

    public func width(of text: String) -> CGFloat {
        var width: CGFloat = 0
        for byte in text.utf8 {
            guard byte >= Self.firstPrintableASCII, byte <= Self.lastPrintableASCII else { return lineWidth(of: text) }
            width += printableASCIIAdvances[Int(byte - Self.firstPrintableASCII)]
        }
        return width
    }

    private func lineWidth(of text: String) -> CGFloat {
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}
