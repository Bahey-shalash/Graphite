#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import SwiftUI
import Textual

#if canImport(UIKit)
private typealias DrawingPath = UIBezierPath
#else
private typealias DrawingPath = NSBezierPath

private extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, cornerRadius: CGFloat) {
        self.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    }

    func addLine(to point: CGPoint) { line(to: point) }
}
#endif

/// Draws Live Preview's replacements (bullets, task checkboxes, the " > " of
/// `[[Note#Heading]]`, and inline math) over the invisible markup they stand for. The
/// note's text is never changed, so saving and undo stay exact. Both editors install it.
final class ConcealedReplacementLayoutFragment: NSTextLayoutFragment {
    /// Whether the paragraph holds inline math. TextKit makes a new element and fragment
    /// when the paragraph's attributes change, so this is decided once, when it is made.
    private let containsInlineMath: Bool
    /// A theme's text before the heading, drawn in the left margin, which the surface must reach.
    private let headingPrefixWidth: CGFloat

    override init(textElement: NSTextElement, range rangeInElement: NSTextRange?) {
        if let attributedString = (textElement as? NSTextParagraph)?.attributedString {
            var foundInlineMath = false
            let wholeString = NSRange(location: 0, length: attributedString.length)
            attributedString.enumerateAttribute(ConcealedReplacement.mathAttributeKey, in: wholeString) { layout, _, stop in
                guard layout != nil else { return }
                foundInlineMath = true
                stop.pointee = true
            }
            containsInlineMath = foundInlineMath
            var prefixWidth: CGFloat = 0
            attributedString.enumerateAttribute(ConcealedReplacement.headingOrnamentKey, in: wholeString) { value, range, stop in
                guard let ornament = value as? ThemedHeadingOrnament, let prefix = ornament.prefix else { return }
                let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont ?? .preferredFont(forTextStyle: .body)
                prefixWidth = Self.prefixFont(for: font).map { prefixFont in (prefix as NSString).size(withAttributes: [.font: prefixFont]).width + 8 } ?? 0
                stop.pointee = true
            }
            headingPrefixWidth = prefixWidth
        } else {
            containsInlineMath = false
            headingPrefixWidth = 0
        }
        super.init(textElement: textElement, range: rangeInElement)
    }

    required init?(coder: NSCoder) {
        containsInlineMath = false
        headingPrefixWidth = 0
        super.init(coder: coder)
    }

    /// A heading's prefix is set smaller than the heading, as themes set level markers.
    private static func prefixFont(for headingFont: PlatformFont) -> PlatformFont? {
        PlatformFont.systemFont(ofSize: max(headingFont.pointSize * 0.55, 11), weight: .semibold)
    }

    /// Makes `context` the one UIKit's or AppKit's drawing calls draw into while `drawing` runs.
    /// TextKit's context is flipped, top to bottom, as the text view is.
    private static func drawing(in context: CGContext, _ drawing: () -> Void) {
        #if canImport(UIKit)
        UIGraphicsPushContext(context)
        drawing()
        UIGraphicsPopContext()
        #else
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawing()
        NSGraphicsContext.restoreGraphicsState()
        #endif
    }

    private static var secondaryLabelColor: PlatformColor {
        #if canImport(UIKit)
        .secondaryLabel
        #else
        .secondaryLabelColor
        #endif
    }

    /// Only a formula can reach above or below its line box, for example while its
    /// antialiased edge meets the line's top; bullets, checkboxes, the subpath separator,
    /// and quote bars stay within the line's height. A checkbox symbol can be a little wider
    /// than the `[ ]` it covers, so every paragraph keeps a narrow margin at the sides; only
    /// paragraphs with formulas get the taller surface, which is more memory to back.
    override var renderingSurfaceBounds: CGRect {
        var bounds = super.renderingSurfaceBounds.insetBy(dx: -2, dy: containsInlineMath ? -12 : 0)
        // A theme's heading background and underline reach across the column, and its prefix into the margin.
        if headingPrefixWidth > 0 { bounds.origin.x -= headingPrefixWidth; bounds.size.width += headingPrefixWidth }
        bounds.size.width = max(bounds.width, columnWidth + 4)
        // A code block's box fills the whole line, from the column's left edge, the space
        // between its lines included.
        if codeBlockDecoration != nil {
            bounds = bounds.union(CGRect(x: -indentationFromColumn, y: 0, width: columnWidth + indentationFromColumn, height: layoutFragmentFrame.height + 1))
        }
        return bounds
    }

    /// How far this fragment starts right of the text column's left edge: TextKit places a
    /// paragraph's fragment at its head indent, as for the inset lines of a code block.
    private var indentationFromColumn: CGFloat {
        let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
        return max(0, layoutFragmentFrame.minX - padding)
    }

    /// The text column's width from this fragment's left edge. A fragment is only as wide as
    /// its text; a theme's quote and heading backgrounds and underlines reach across the
    /// column, as in Obsidian.
    private var columnWidth: CGFloat {
        guard let container = textLayoutManager?.textContainer, container.size.width > 0, container.size.width < 100_000 else { return layoutFragmentFrame.width }
        return max(layoutFragmentFrame.width, container.size.width - container.lineFragmentPadding - layoutFragmentFrame.minX)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        Self.drawing(in: context) { drawThemeShapesBehindText(at: point) }
        super.draw(at: point, in: context)
        Self.drawing(in: context) { drawReplacementsOverText(at: point) }
    }

    private func drawReplacementsOverText(at point: CGPoint) {
        drawHeadingOrnamentsOverText(at: point)
        // A quoted line's bars, found on its first line fragment and drawn on every one, so
        // the lines a long quote wraps onto have bars too. Offsets are from `point.x`.
        var quoteBars: (offsets: [CGFloat], color: PlatformColor)?
        for lineFragment in textLineFragments {
            let attributedString = lineFragment.attributedString
            let lineOrigin = CGPoint(x: point.x + lineFragment.typographicBounds.minX, y: point.y + lineFragment.typographicBounds.minY)
            let baseline = lineOrigin.y + lineFragment.glyphOrigin.y
            attributedString.enumerateAttribute(ConcealedReplacement.attributeKey, in: lineFragment.characterRange) { value, range, _ in
                // Formulas are drawn by `drawInlineMath`, once each.
                guard let rawValue = value as? String, let replacement = ConcealedReplacement(rawValue: rawValue), replacement != .inlineMath else { return }
                let startX = lineOrigin.x + lineFragment.locationForCharacter(at: range.location).x
                let endX = lineOrigin.x + lineFragment.locationForCharacter(at: NSMaxRange(range)).x
                let color = attributedString.attribute(ConcealedReplacement.colorAttributeKey, at: range.location, effectiveRange: nil) as? PlatformColor ?? Self.secondaryLabelColor
                if replacement == .quoteBar {
                    // One bar per `>`, so each level of a nested quote shows.
                    let marker = attributedString.attributedSubstring(from: range).string as NSString
                    let offsets = (0..<marker.length).filter { offset in marker.character(at: offset) == UInt16(UInt8(ascii: ">")) }.map { offset in
                        lineOrigin.x + lineFragment.locationForCharacter(at: range.location + offset).x - point.x
                    }
                    quoteBars = (offsets, color)
                    return
                }
                let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont ?? .preferredFont(forTextStyle: .body)
                let box = CGRect(x: startX, y: baseline - font.ascender, width: max(endX - startX, 1), height: font.ascender - font.descender)
                if let checkboxStyle = attributedString.attribute(ConcealedReplacement.checkboxStyleKey, at: range.location, effectiveRange: nil) as? ThemedCheckboxStyle {
                    Self.drawCheckbox(isChecked: replacement == .checkedTask, style: checkboxStyle, in: box, font: font)
                    return
                }
                Self.draw(replacement, in: box, font: font, color: color)
            }
            if let quoteBars {
                // The whole line's height, so the bars of consecutive quoted lines join.
                quoteBars.color.withAlphaComponent(0.6).setFill()
                for offset in quoteBars.offsets {
                    DrawingPath(rect: CGRect(x: point.x + offset + 1, y: lineOrigin.y, width: 2.5, height: lineFragment.typographicBounds.height)).fill()
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

    // MARK: A theme's shapes (theme Phase 3)

    /// Rounded backgrounds behind tag pills and highlights, quote boxes, and heading
    /// backgrounds, under the text.
    private func drawThemeShapesBehindText(at point: CGPoint) {
        if let codeBlockDecoration { drawCodeBlock(codeBlockDecoration, at: point) }
        for lineFragment in textLineFragments {
            let attributedString = lineFragment.attributedString
            let lineOrigin = CGPoint(x: point.x + lineFragment.typographicBounds.minX, y: point.y + lineFragment.typographicBounds.minY)
            let lineHeight = lineFragment.typographicBounds.height
            if let quoteBackground = Self.firstValue(ConcealedReplacement.quoteBackgroundKey, in: lineFragment) as? PlatformColor {
                quoteBackground.setFill()
                DrawingPath(rect: CGRect(x: point.x, y: lineOrigin.y, width: columnWidth, height: lineHeight)).fill()
            }
            if let ornament = Self.firstValue(ConcealedReplacement.headingOrnamentKey, in: lineFragment) as? ThemedHeadingOrnament, let background = ornament.background {
                background.setFill()
                DrawingPath(roundedRect: CGRect(x: point.x - 4, y: lineOrigin.y, width: columnWidth + 8, height: lineHeight), cornerRadius: 4).fill()
            }
            attributedString.enumerateAttribute(ConcealedReplacement.roundedBackgroundKey, in: lineFragment.characterRange) { value, range, _ in
                guard let shape = value as? ThemedTextShape else { return }
                let startX = lineOrigin.x + lineFragment.locationForCharacter(at: range.location).x
                let endX = lineOrigin.x + lineFragment.locationForCharacter(at: NSMaxRange(range)).x
                let font = attributedString.attribute(.font, at: range.location, effectiveRange: nil) as? PlatformFont ?? .preferredFont(forTextStyle: .body)
                let baseline = lineOrigin.y + lineFragment.glyphOrigin.y
                // One point either side: a space between two tags still shows between their pills.
                let box = CGRect(x: startX - 1, y: baseline - font.ascender - 1, width: max(endX - startX, 1) + 2, height: font.ascender - font.descender + 2)
                let path = DrawingPath(roundedRect: box, cornerRadius: min(shape.cornerRadius, box.height / 2))
                shape.color.setFill()
                path.fill()
                if let borderColor = shape.borderColor, shape.borderWidth > 0 {
                    borderColor.setStroke()
                    path.lineWidth = shape.borderWidth
                    path.stroke()
                }
            }
        }
    }

    // MARK: Code blocks

    /// The paragraph's code block decoration, when it is a line of a fenced code block. Each
    /// line of a block is a paragraph, so the paragraph's first character says.
    private var codeBlockDecoration: CodeBlockLineDecoration? {
        guard let paragraph = (textElement as? NSTextParagraph)?.attributedString, paragraph.length > 0 else { return nil }
        return paragraph.attribute(ConcealedReplacement.codeBlockKey, at: 0, effectiveRange: nil) as? CodeBlockLineDecoration
    }

    /// This line's slice of its block's box, its indentation guides, and on the first line
    /// the language at the right.
    private func drawCodeBlock(_ decoration: CodeBlockLineDecoration, at point: CGPoint) {
        let height = layoutFragmentFrame.height
        // Each slice reaches half a point into the next, so no seam shows between lines.
        let box = CGRect(x: point.x - indentationFromColumn, y: point.y, width: columnWidth + indentationFromColumn, height: height + (decoration.isLastLine ? 0 : 0.5))
        decoration.background.setFill()
        Self.path(box, cornerRadius: decoration.cornerRadius, roundsTop: decoration.isFirstLine, roundsBottom: decoration.isLastLine).fill()
        decoration.border.setStroke()
        let border = Self.borderPath(box.insetBy(dx: 0.5, dy: 0), cornerRadius: decoration.cornerRadius, isFirstLine: decoration.isFirstLine, isLastLine: decoration.isLastLine)
        border.lineWidth = 1
        border.stroke()
        if let firstLine = textLineFragments.first, !decoration.guideOffsets.isEmpty {
            decoration.guideColor.setFill()
            let lineOriginX = point.x + firstLine.typographicBounds.minX
            for offset in decoration.guideOffsets where offset < firstLine.attributedString.length {
                let guideX = (lineOriginX + firstLine.locationForCharacter(at: offset).x + 1).rounded()
                DrawingPath(rect: CGRect(x: guideX, y: point.y, width: 1, height: height + 0.5)).fill()
            }
        }
        if let label = decoration.languageLabel {
            let attributes: [NSAttributedString.Key: Any] = [.font: decoration.labelFont, .foregroundColor: decoration.labelColor]
            let size = (label as NSString).size(withAttributes: attributes)
            let origin = CGPoint(x: point.x + columnWidth - decoration.horizontalPadding - size.width, y: point.y + max(0, height - size.height) * 0.6)
            (label as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    /// This slice's part of the box's border: its two sides, and the top with its rounded
    /// corners on the first line, the bottom with its corners on the last. The line is drawn
    /// half a point inside the box, so it stays crisp and within the slice.
    private static func borderPath(_ rect: CGRect, cornerRadius: CGFloat, isFirstLine: Bool, isLastLine: Bool) -> DrawingPath {
        let radius = min(cornerRadius, rect.height / 2, rect.width / 2)
        let top = isFirstLine ? rect.minY + 0.5 : rect.minY
        let bottom = isLastLine ? rect.maxY - 0.5 : rect.maxY
        let path = CGMutablePath()
        // Down the left side, along the bottom on the last line, and up the right side.
        if isFirstLine {
            path.move(to: CGPoint(x: rect.maxX, y: top + radius))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX - radius, y: top), radius: radius)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.minX, y: top + radius), radius: radius)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: top))
        }
        if isLastLine {
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.minX + radius, y: bottom), radius: radius)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.maxX, y: bottom - radius), radius: radius)
            path.addLine(to: CGPoint(x: rect.maxX, y: isFirstLine ? top + radius : top))
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: bottom))
            path.move(to: CGPoint(x: rect.maxX, y: bottom))
            path.addLine(to: CGPoint(x: rect.maxX, y: isFirstLine ? top + radius : top))
        }
        return DrawingPath(cgPath: path)
    }

    /// `rect` with its top corners, its bottom corners, both or neither rounded.
    private static func path(_ rect: CGRect, cornerRadius: CGFloat, roundsTop: Bool, roundsBottom: Bool) -> DrawingPath {
        let topRadius = roundsTop ? min(cornerRadius, rect.height / 2, rect.width / 2) : 0
        let bottomRadius = roundsBottom ? min(cornerRadius, rect.height / 2, rect.width / 2) : 0
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topRadius, y: rect.minY), radius: topRadius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRadius), radius: topRadius)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY), radius: bottomRadius)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius), radius: bottomRadius)
        path.closeSubpath()
        return DrawingPath(cgPath: path)
    }

    /// A heading's underline across the column under its last line, and its prefix in the margin.
    private func drawHeadingOrnamentsOverText(at point: CGPoint) {
        guard let lastLine = textLineFragments.last, let firstLine = textLineFragments.first,
              let ornament = Self.firstValue(ConcealedReplacement.headingOrnamentKey, in: firstLine) as? ThemedHeadingOrnament else { return }
        if let underlineColor = ornament.underlineColor {
            underlineColor.setFill()
            let bottom = point.y + lastLine.typographicBounds.maxY
            DrawingPath(rect: CGRect(x: point.x, y: bottom - ornament.underlineWidth, width: columnWidth, height: ornament.underlineWidth)).fill()
        }
        if let prefix = ornament.prefix {
            let attributedString = firstLine.attributedString
            let font = attributedString.attribute(.font, at: max(firstLine.characterRange.location, NSMaxRange(firstLine.characterRange) - 1), effectiveRange: nil) as? PlatformFont
                ?? .preferredFont(forTextStyle: .body)
            guard let prefixFont = Self.prefixFont(for: font) else { return }
            let attributes: [NSAttributedString.Key: Any] = [.font: prefixFont, .foregroundColor: ornament.prefixColor ?? Self.secondaryLabelColor]
            let size = (prefix as NSString).size(withAttributes: attributes)
            let baseline = point.y + firstLine.typographicBounds.minY + firstLine.glyphOrigin.y
            (prefix as NSString).draw(at: CGPoint(x: point.x - size.width - 6, y: baseline - prefixFont.ascender), withAttributes: attributes)
        }
    }

    private static func firstValue(_ key: NSAttributedString.Key, in lineFragment: NSTextLineFragment) -> Any? {
        var found: Any?
        lineFragment.attributedString.enumerateAttribute(key, in: lineFragment.characterRange) { value, _, stop in
            guard let value else { return }
            found = value
            stop.pointee = true
        }
        return found
    }

    /// A theme's checkbox: its corners, border and colors, with a check mark when done.
    private static func drawCheckbox(isChecked: Bool, style: ThemedCheckboxStyle, in box: CGRect, font: PlatformFont) {
        let side = font.pointSize * 0.85
        let frame = CGRect(x: box.midX - side / 2, y: box.midY - side / 2, width: side, height: side)
        let path = DrawingPath(roundedRect: frame.insetBy(dx: style.borderWidth / 2, dy: style.borderWidth / 2),
                                cornerRadius: min(style.radiusScale * font.pointSize, side / 2))
        path.lineWidth = style.borderWidth
        if isChecked {
            style.fill.setFill(); path.fill()
            style.fill.setStroke(); path.stroke()
            let mark = DrawingPath()
            mark.move(to: CGPoint(x: frame.minX + side * 0.24, y: frame.midY + side * 0.02))
            mark.addLine(to: CGPoint(x: frame.minX + side * 0.43, y: frame.minY + side * 0.72))
            mark.addLine(to: CGPoint(x: frame.minX + side * 0.78, y: frame.minY + side * 0.3))
            mark.lineWidth = max(1.5, side * 0.12)
            mark.lineCapStyle = .round; mark.lineJoinStyle = .round
            style.checkmark.setStroke(); mark.stroke()
        } else {
            style.border.setStroke(); path.stroke()
        }
    }

    private static func draw(_ replacement: ConcealedReplacement, in box: CGRect, font: PlatformFont, color: PlatformColor) {
        switch replacement {
        case .bullet:
            // A dot centered on the lowercase letters, like Obsidian's list bullets.
            let diameter = max(5, font.pointSize * 0.3)
            let centerY = box.minY + font.ascender - font.xHeight / 2
            color.setFill()
            DrawingPath(ovalIn: CGRect(x: box.midX - diameter / 2, y: centerY - diameter / 2, width: diameter, height: diameter)).fill()
        case .subpathSeparator:
            drawCentered(ConcealedReplacement.subpathSeparatorText, in: box, font: font, color: color)
        case .uncheckedTask, .checkedTask:
            drawSymbol(named: replacement == .checkedTask ? "checkmark.square.fill" : "square", pointSize: font.pointSize * 0.95, color: color, centeredIn: box)
        case .inlineMath, .quoteBar:
            break
        }
    }

    private static func drawSymbol(named symbolName: String, pointSize: CGFloat, color: PlatformColor, centeredIn box: CGRect) {
        #if canImport(UIKit)
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = UIImage(systemName: symbolName, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        symbol.draw(at: CGPoint(x: box.midX - symbol.size.width / 2, y: box.midY - symbol.size.height / 2))
        #else
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        // In one color, its cut-out parts left clear, as UIKit tints it: the check mark of a
        // filled box shows the page through it.
        let tintedSymbol = NSImage(size: symbol.size, flipped: false) { bounds in
            symbol.draw(in: bounds)
            color.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        let frame = CGRect(x: box.midX - symbol.size.width / 2, y: box.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height)
        tintedSymbol.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #endif
    }

    private static func drawCentered(_ text: String, in box: CGRect, font: PlatformFont, color: PlatformColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2), withAttributes: attributes)
    }

    /// Formulas are drawn in the current appearance's text color, rendered when first seen.
    private static func draw(_ layout: InlineMathLayout, atX originX: CGFloat, baseline: CGFloat) {
        guard Thread.isMainThread else { return }
        #if canImport(UIKit)
        let traits = UITraitCollection.current
        let color = UIColor.label.resolvedColor(with: traits)
        let scale = max(traits.displayScale, 2)
        #else
        // The drawing appearance's text color, in RGB so the cache can key it by components.
        var color = NSColor.black
        NSAppearance.currentDrawing().performAsCurrentDrawingAppearance { color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black }
        let scale = max(MainActor.assumeIsolated { NSScreen.main?.backingScaleFactor ?? 2 }, 2)
        #endif
        guard let image = MainActor.assumeIsolated({ InlineMathImageCache.image(for: layout, color: color, scale: scale) }) else { return }
        let metrics = layout.metrics
        let frame = CGRect(x: originX, y: baseline - metrics.ascent, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        #if canImport(UIKit)
        UIImage(cgImage: image, scale: scale, orientation: .up).draw(in: frame)
        #else
        NSImage(cgImage: image, size: frame.size).draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        #endif
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

    static func image(for layout: InlineMathLayout, color: PlatformColor, scale: CGFloat) -> CGImage? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let key = "\(layout.fontSize)|\(scale)|\(red),\(green),\(blue),\(alpha)|\(layout.latex)" as NSString
        if let image = imagesByKey.object(forKey: key) { return image }
        #if canImport(UIKit)
        let formulaColor = Color(uiColor: color)
        #else
        let formulaColor = Color(nsColor: color)
        #endif
        guard let image = InlineMathRendering.image(for: layout.latex, fontSize: layout.fontSize, color: formulaColor, scale: scale) else { return nil }
        imagesByKey.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
