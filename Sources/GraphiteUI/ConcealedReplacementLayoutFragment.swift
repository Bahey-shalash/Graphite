#if canImport(UIKit)
import UIKit
import SwiftUI
import Textual

/// Draws Live Preview's replacements (bullets, task checkboxes, the " > " of
/// `[[Note#Heading]]`, and inline math) over the invisible markup they stand for. The
/// note's text is never changed, so saving and undo stay exact.
final class ConcealedReplacementLayoutFragment: NSTextLayoutFragment {
    /// Whether the paragraph holds inline math. TextKit makes a new element and fragment
    /// when the paragraph's attributes change, so this is decided once, when it is made.
    private let containsInlineMath: Bool

    override init(textElement: NSTextElement, range rangeInElement: NSTextRange?) {
        if let attributedString = (textElement as? NSTextParagraph)?.attributedString {
            var foundInlineMath = false
            attributedString.enumerateAttribute(ConcealedReplacement.mathAttributeKey, in: NSRange(location: 0, length: attributedString.length)) { layout, _, stop in
                guard layout != nil else { return }
                foundInlineMath = true
                stop.pointee = true
            }
            containsInlineMath = foundInlineMath
        } else {
            containsInlineMath = false
        }
        super.init(textElement: textElement, range: rangeInElement)
    }

    required init?(coder: NSCoder) {
        containsInlineMath = false
        super.init(coder: coder)
    }

    /// Only a formula can reach above or below its line box, for example while its
    /// antialiased edge meets the line's top; bullets, checkboxes, the subpath separator,
    /// and quote bars stay within the line's height. A checkbox symbol can be a little wider
    /// than the `[ ]` it covers, so every paragraph keeps a narrow margin at the sides; only
    /// paragraphs with formulas get the taller surface, which is more memory to back.
    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.insetBy(dx: -2, dy: containsInlineMath ? -12 : 0)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        // A quoted line's bars, found on its first line fragment and drawn on every one, so
        // the lines a long quote wraps onto have bars too. Offsets are from `point.x`.
        var quoteBars: (offsets: [CGFloat], color: UIColor)?
        for lineFragment in textLineFragments {
            let attributedString = lineFragment.attributedString
            let lineOrigin = CGPoint(x: point.x + lineFragment.typographicBounds.minX, y: point.y + lineFragment.typographicBounds.minY)
            let baseline = lineOrigin.y + lineFragment.glyphOrigin.y
            attributedString.enumerateAttribute(ConcealedReplacement.attributeKey, in: lineFragment.characterRange) { value, range, _ in
                // Formulas are drawn by `drawInlineMath`, once each.
                guard let rawValue = value as? String, let replacement = ConcealedReplacement(rawValue: rawValue), replacement != .inlineMath else { return }
                let startX = lineOrigin.x + lineFragment.locationForCharacter(at: range.location).x
                let endX = lineOrigin.x + lineFragment.locationForCharacter(at: NSMaxRange(range)).x
                let color = attributedString.attribute(ConcealedReplacement.colorAttributeKey, at: range.location, effectiveRange: nil) as? UIColor ?? .secondaryLabel
                if replacement == .quoteBar {
                    // One bar per `>`, so each level of a nested quote shows.
                    let marker = attributedString.attributedSubstring(from: range).string as NSString
                    let offsets = (0..<marker.length).filter { offset in marker.character(at: offset) == UInt16(UInt8(ascii: ">")) }.map { offset in
                        lineOrigin.x + lineFragment.locationForCharacter(at: range.location + offset).x - point.x
                    }
                    quoteBars = (offsets, color)
                    return
                }
                let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont ?? .preferredFont(forTextStyle: .body)
                let box = CGRect(x: startX, y: baseline - font.ascender, width: max(endX - startX, 1), height: font.ascender - font.descender)
                Self.draw(replacement, in: box, font: font, color: color)
            }
            if let quoteBars {
                // The whole line's height, so the bars of consecutive quoted lines join.
                quoteBars.color.withAlphaComponent(0.6).setFill()
                for offset in quoteBars.offsets {
                    UIBezierPath(rect: CGRect(x: point.x + offset + 1, y: lineOrigin.y, width: 2.5, height: lineFragment.typographicBounds.height)).fill()
                }
            }
            drawInlineMath(in: lineFragment, lineOrigin: lineOrigin, baseline: baseline)
        }
    }

    /// Draws each formula whose last source character is on this line. The styler reserves
    /// the formula's room after that character; the rest of the source is hidden and nearly
    /// zero-width, and may wrap onto the line before, which must not draw it again.
    private func drawInlineMath(in lineFragment: NSTextLineFragment, lineOrigin: CGPoint, baseline: CGFloat) {
        let attributedString = lineFragment.attributedString
        let wholeString = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(ConcealedReplacement.mathAttributeKey, in: lineFragment.characterRange) { value, range, _ in
            guard let layout = value as? InlineMathLayout else { return }
            var formulaRange = NSRange(location: NSNotFound, length: 0)
            _ = attributedString.attribute(ConcealedReplacement.mathAttributeKey, at: range.location, longestEffectiveRange: &formulaRange, in: wholeString)
            let lastCharacterLocation = NSMaxRange(formulaRange) - 1
            guard formulaRange.length > 0, NSLocationInRange(lastCharacterLocation, lineFragment.characterRange) else { return }
            let roomStartX = lineOrigin.x + lineFragment.locationForCharacter(at: lastCharacterLocation).x
            Self.draw(layout, atX: roomStartX + InlineMathLayout.horizontalPadding, baseline: baseline)
        }
    }

    private static func draw(_ replacement: ConcealedReplacement, in box: CGRect, font: UIFont, color: UIColor) {
        switch replacement {
        case .bullet:
            // A dot centered on the lowercase letters, like Obsidian's list bullets.
            let diameter = max(5, font.pointSize * 0.3)
            let centerY = box.minY + font.ascender - font.xHeight / 2
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: box.midX - diameter / 2, y: centerY - diameter / 2, width: diameter, height: diameter)).fill()
        case .subpathSeparator:
            drawCentered(ConcealedReplacement.subpathSeparatorText, in: box, font: font, color: color)
        case .uncheckedTask, .checkedTask:
            let symbolName = replacement == .checkedTask ? "checkmark.square.fill" : "square"
            let configuration = UIImage.SymbolConfiguration(pointSize: font.pointSize * 0.95, weight: .regular)
            guard let symbol = UIImage(systemName: symbolName, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
            symbol.draw(at: CGPoint(x: box.midX - symbol.size.width / 2, y: box.midY - symbol.size.height / 2))
        case .inlineMath, .quoteBar:
            break
        }
    }

    private static func drawCentered(_ text: String, in box: CGRect, font: UIFont, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attributes)
    }

    /// Formulas are drawn in the current appearance's text color, rendered when first seen.
    private static func draw(_ layout: InlineMathLayout, atX originX: CGFloat, baseline: CGFloat) {
        guard Thread.isMainThread else { return }
        let traits = UITraitCollection.current
        let color = UIColor.label.resolvedColor(with: traits)
        let scale = max(traits.displayScale, 2)
        guard let image = MainActor.assumeIsolated({ InlineMathImageCache.image(for: layout, color: color, scale: scale) }) else { return }
        let metrics = layout.metrics
        UIImage(cgImage: image, scale: scale, orientation: .up)
            .draw(in: CGRect(x: originX, y: baseline - metrics.ascent, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
    }
}

/// Rendered formulas by LaTeX, size, color, and scale, so scrolling does not typeset again.
/// Bounded by bitmap bytes, and emptied by the system under memory pressure: a formula
/// dropped from it is typeset again, in about half a millisecond, when it is next drawn.
@MainActor
enum InlineMathImageCache {
    /// Well above the formulas of one screen, which use a few megabytes at most.
    private static let maximumCachedBytes = 16 * 1_048_576
    private static let imagesByKey: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = maximumCachedBytes
        return cache
    }()

    static func image(for layout: InlineMathLayout, color: UIColor, scale: CGFloat) -> CGImage? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let key = "\(layout.fontSize)|\(scale)|\(red),\(green),\(blue),\(alpha)|\(layout.latex)" as NSString
        if let image = imagesByKey.object(forKey: key) { return image }
        guard let image = InlineMathRendering.image(for: layout.latex, fontSize: layout.fontSize, color: Color(uiColor: color), scale: scale) else { return nil }
        imagesByKey.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
#endif
