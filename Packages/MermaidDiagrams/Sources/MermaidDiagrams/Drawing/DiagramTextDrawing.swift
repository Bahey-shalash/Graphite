import CoreGraphics
import CoreText
import Foundation

/// Draws text blocks with Core Text into a context whose y runs down. The fonts for one drawing are made once.
struct DiagramTextDrawing {
    /// Where a line's baseline sits below the middle of its line, as a fraction of the font size: Pele's.
    static let baselineShiftRatio: CGFloat = 0.35

    private let font: DiagramFont
    private var fontsBySize: [CGFloat: CTFont] = [:]

    init(font: DiagramFont) {
        self.font = font
    }

    /// Draws each line centered on the block's center, one line height below the last.
    mutating func draw(_ block: DiagramTextBlock, color: CGColor, isBold: Bool = false, in context: CGContext) {
        guard !block.lines.isEmpty else { return }
        let coreTextFont = coreTextFont(size: block.fontSize, isBold: isBold)
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: coreTextFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color,
        ]
        let top = block.center.y - block.size.height / 2
        context.saveGState()
        // Core Text draws glyphs upright in a context whose y runs up; this one's runs down.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in block.lines.enumerated() {
            let coreTextLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            let baseline = top + (CGFloat(index) + 0.5) * block.lineHeight + block.fontSize * Self.baselineShiftRatio
            context.textPosition = CGPoint(x: block.center.x - block.lineWidths[index] / 2, y: baseline)
            CTLineDraw(coreTextLine, context)
        }
        context.restoreGState()
    }

    private mutating func coreTextFont(size: CGFloat, isBold: Bool) -> CTFont {
        let regular = fontsBySize[size] ?? font.resized(to: size).makeCoreTextFont()
        fontsBySize[size] = regular
        guard isBold else { return regular }
        return CTFontCreateCopyWithSymbolicTraits(regular, size, nil, .traitBold, .traitBold) ?? regular
    }
}
