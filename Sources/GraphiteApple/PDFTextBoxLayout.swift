import Foundation
import CoreGraphics
import CoreText
import GraphiteCore

/// A text box's text laid out with Core Text: where each line, glyph, underline and link
/// is, in the box's own space. Its origin is the box's bottom-left corner, before the box
/// is placed and turned on its page, and y counts upward, as on a PDF page. The same
/// layout draws the box's appearance in the PDF, the box on a shown page, its picture on
/// screen above the ink, and measures its height, so they all agree.
///
/// Immutable once made: Core Text's frames and fonts may be read from any thread.
public final class PDFTextBoxLayout: @unchecked Sendable {
    // Unchecked: every stored value is an immutable Core Foundation object or a value.
    public let box: PDFTextBox
    let frame: CTFrame
    /// Each line's origin, in the box's space.
    let lineOrigins: [CGPoint]
    let lines: [CTLine]
    /// The height the text takes with the padding, at least one line's.
    public let fittedHeight: Double

    /// The name under which a run's link is kept in the attributed string.
    static let linkAttribute = NSAttributedString.Key("GraphiteTextBoxLink")
    /// Taller than any box, so Core Text never stops for want of room; the text starts at its top.
    private static let unboundedHeight: CGFloat = 100_000

    public init(box: PDFTextBox) {
        self.box = box
        let padding = CGFloat(box.style.padding)
        let textWidth = max(CGFloat(box.width) - 2 * padding, 1)
        let string = Self.attributedString(of: box)
        let framesetter = CTFramesetterCreateWithAttributedString(string as CFAttributedString)
        let pathRectangle = CGRect(x: padding, y: CGFloat(box.height) - padding - Self.unboundedHeight, width: textWidth, height: Self.unboundedHeight)
        frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: pathRectangle, transform: nil), nil)
        lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        if !lines.isEmpty { CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins) }
        // Core Text gives the origins from the corner of the path's rectangle; in the box's
        // space they are moved by that corner.
        lineOrigins = origins.map { origin in CGPoint(x: origin.x + pathRectangle.minX, y: origin.y + pathRectangle.minY) }
        fittedHeight = Self.measuredHeight(of: box, framesetter: framesetter, textWidth: textWidth)
    }

    /// The box with the height its text takes: as the text grows, the box grows downward.
    public static func fitted(_ box: PDFTextBox) -> PDFTextBox {
        var fitted = box
        fitted.height = PDFTextBoxLayout(box: box).fittedHeight
        return fitted
    }

    // MARK: Attributes

    static func attributedString(of box: PDFTextBox) -> NSAttributedString {
        let string = NSMutableAttributedString()
        let paragraphStyle = paragraphStyle(of: box.style)
        for run in box.runs {
            string.append(NSAttributedString(string: run.text, attributes: attributes(of: run.attributes, paragraphStyle: paragraphStyle)))
        }
        return string
    }

    static func attributes(of attributes: PDFTextAttributes, paragraphStyle: CTParagraphStyle) -> [NSAttributedString.Key: Any] {
        var coreTextAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): PDFTextBoxFonts.font(for: attributes),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor(attributes.color),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle,
        ]
        if let link = attributes.link { coreTextAttributes[linkAttribute] = link }
        return coreTextAttributes
    }

    static func paragraphStyle(of style: PDFTextBoxStyle) -> CTParagraphStyle {
        let alignment: CTTextAlignment = switch style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
        let lineHeightMultiple = CGFloat(style.lineSpacing)
        return withUnsafePointer(to: alignment) { alignmentPointer in
            withUnsafePointer(to: lineHeightMultiple) { multiplePointer in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer),
                    CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: multiplePointer),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }

    public static func cgColor(_ color: PDFTextColor) -> CGColor {
        CGColor(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }

    // MARK: Measuring

    /// The text's height with the padding. A last line that is empty (the text ends in a
    /// line break, as just after Return) still counts, so the caret on it is inside the box.
    private static func measuredHeight(of box: PDFTextBox, framesetter: CTFramesetter, textWidth: CGFloat) -> Double {
        let padding = box.style.padding
        let lineHeight = oneLineHeight(of: box)
        let plainText = box.plainText
        guard !plainText.isEmpty else { return lineHeight + 2 * padding }
        let constraints = CGSize(width: textWidth, height: unboundedHeight)
        var height = Double(CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraints, nil).height)
        if plainText.hasSuffix("\n") { height += lineHeight }
        return max(height, lineHeight) + 2 * padding
    }

    /// The height of one line in the look the text ends with, as Core Text lays it out at the
    /// box's line spacing: the height an empty box, or the empty line after Return, takes.
    private static func oneLineHeight(of box: PDFTextBox) -> Double {
        let looks = box.runs.last?.attributes ?? box.leadingAttributes
        let oneLine = NSAttributedString(string: " ", attributes: attributes(of: looks, paragraphStyle: paragraphStyle(of: box.style)))
        let framesetter = CTFramesetterCreateWithAttributedString(oneLine as CFAttributedString)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil,
                                                                 CGSize(width: unboundedHeight, height: unboundedHeight), nil)
        return Double(size.height)
    }

    /// How much of the text, in UTF-16 units from its start, fits in whole lines within a
    /// height of the box, its padding included: where a text that flows onto the next page,
    /// as Notability's typed text does, is cut (`PDFTextRun.split`). All of it when it fits.
    public func textLengthFitting(height: Double) -> Int {
        let bottomLimit = CGFloat(box.height - height + box.style.padding)
        var fittingLength = 0
        for (line, origin) in zip(lines, lineOrigins) {
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, nil, &descent, nil)
            guard origin.y - descent >= bottomLimit - 0.5 else { break }
            let range = CTLineGetStringRange(line)
            fittingLength = range.location + range.length
        }
        return lines.isEmpty ? 0 : fittingLength
    }

    // MARK: Placing on the page

    /// From the box's own space to the page's: its bottom-left corner moved to where the box
    /// is, turned about the top-left corner, which stays at `origin`.
    public var boxToPage: CGAffineTransform {
        CGAffineTransform(translationX: box.origin.x, y: box.origin.y)
            .rotated(by: -CGFloat(box.rotationRadians))
            .translatedBy(x: 0, y: -CGFloat(box.height))
    }

    /// The box's own rectangle in its space.
    public var boxRectangle: CGRect { CGRect(x: 0, y: 0, width: box.width, height: box.height) }
}
