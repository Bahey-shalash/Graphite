import Foundation
import CoreGraphics
import CoreText
import GraphiteCore

/// What a laid-out text box draws, in the box's own space (`PDFTextBoxLayout`): its fill,
/// its text, the text's underlines, and its border, in that order.
extension PDFTextBoxLayout {
    /// One run of one line: where it is, how it looks, and the glyphs Core Text chose for it.
    struct PlacedRun {
        let run: CTRun
        let font: CTFont
        let attributes: PDFTextAttributes
        let lineOrigin: CGPoint
        /// The run's typographic rectangle, from its descent to its ascent.
        let rectangle: CGRect
    }

    /// Draws the box into a context whose coordinates are its page's.
    public func draw(inPageContext context: CGContext) {
        context.saveGState()
        context.concatenate(boxToPage)
        drawInBoxSpace(context)
        context.restoreGState()
    }

    /// Draws the box into a context whose coordinates are the box's own.
    public func drawInBoxSpace(_ context: CGContext) {
        if let fillColor = box.style.fillColor {
            context.setFillColor(Self.cgColor(fillColor))
            context.fill(boxRectangle)
        }
        context.saveGState()
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
        for underline in underlines() {
            context.setFillColor(Self.cgColor(underline.color))
            context.fill(underline.rectangle)
        }
        if box.style.hasBorder, let borderColor = box.style.borderColor {
            let width = CGFloat(box.style.borderWidth)
            context.setStrokeColor(Self.cgColor(borderColor))
            context.setLineWidth(width)
            context.stroke(boxRectangle.insetBy(dx: width / 2, dy: width / 2))
        }
    }

    // MARK: Runs

    /// Every run of every line, with the looks of the box's run it comes from.
    func placedRuns() -> [PlacedRun] {
        let boxRuns = boxRunRanges()
        var placed: [PlacedRun] = []
        for (line, lineOrigin) in zip(lines, lineOrigins) {
            for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
                let stringRange = CTRunGetStringRange(run)
                guard let attributes = boxRuns.last(where: { range in range.start <= stringRange.location })?.attributes else { continue }
                var ascent: CGFloat = 0, descent: CGFloat = 0
                let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))
                var firstPosition = CGPoint.zero
                if CTRunGetGlyphCount(run) > 0 { CTRunGetPositions(run, CFRange(location: 0, length: 1), &firstPosition) }
                let rectangle = CGRect(x: lineOrigin.x + firstPosition.x, y: lineOrigin.y - descent, width: width, height: ascent + descent)
                placed.append(PlacedRun(run: run, font: Self.font(of: run) ?? PDFTextBoxFonts.font(for: attributes), attributes: attributes,
                                        lineOrigin: lineOrigin, rectangle: rectangle))
            }
        }
        return placed
    }

    /// Where each of the box's runs starts in its text, in UTF-16 units, as Core Text counts.
    private func boxRunRanges() -> [(start: Int, attributes: PDFTextAttributes)] {
        var start = 0
        return box.runs.map { run in
            defer { start += run.text.utf16.count }
            return (start, run.attributes)
        }
    }

    /// The font Core Text drew a run in, which is another than the run's own where the run's
    /// font lacks a character (an emoji, a script it does not cover).
    private static func font(of run: CTRun) -> CTFont? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String] as AnyObject?, CFGetTypeID(value) == CTFontGetTypeID() else { return nil }
        return unsafeBitCast(value, to: CTFont.self)
    }

    // MARK: Underlines and links

    /// The underline under each underlined run, as the font places it, without the space a
    /// line break takes.
    func underlines() -> [(rectangle: CGRect, color: PDFTextColor)] {
        placedRuns().compactMap { placed in
            guard placed.attributes.isUnderlined, placed.rectangle.width > 0 else { return nil }
            let thickness = max(CTFontGetUnderlineThickness(placed.font), 0.5)
            let position = CTFontGetUnderlinePosition(placed.font)
            let rectangle = CGRect(x: placed.rectangle.minX, y: placed.lineOrigin.y + position - thickness / 2,
                                   width: placed.rectangle.width, height: thickness)
            return (rectangle, placed.attributes.color)
        }
    }

    /// The area of each linked run on each line, in the box's space, with where it links.
    public func linkAreas() -> [(url: URL, rectangle: CGRect)] {
        placedRuns().compactMap { placed in
            guard let link = placed.attributes.link, placed.rectangle.width > 0 else { return nil }
            return (link, placed.rectangle)
        }
    }

    /// Whether a run is drawn in a font of color glyphs, an emoji's, which have no outlines:
    /// such a box is shown as a picture, not as `textOutlines`.
    public var usesColorGlyphs: Bool {
        placedRuns().contains { placed in CTFontGetSymbolicTraits(placed.font).contains(.traitColorGlyphs) }
    }

    // MARK: Outlines

    /// The text as outlines, one path for each color, in the box's space: what is shown on
    /// screen above the ink, drawn by Core Animation as shapes, so it is sharp at any zoom
    /// without a bitmap the size of the zoomed page.
    public func textOutlines() -> [(path: CGPath, color: PDFTextColor)] {
        var pathsByColor: [PDFTextColor: CGMutablePath] = [:]
        var colorOrder: [PDFTextColor] = []
        for placed in placedRuns() {
            let glyphCount = CTRunGetGlyphCount(placed.run)
            guard glyphCount > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(placed.run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(placed.run, CFRange(location: 0, length: 0), &positions)
            let path: CGMutablePath
            if let existing = pathsByColor[placed.attributes.color] {
                path = existing
            } else {
                path = CGMutablePath()
                pathsByColor[placed.attributes.color] = path
                colorOrder.append(placed.attributes.color)
            }
            for (glyph, position) in zip(glyphs, positions) {
                var placement = CGAffineTransform(translationX: placed.lineOrigin.x + position.x, y: placed.lineOrigin.y + position.y)
                if let glyphPath = CTFontCreatePathForGlyph(placed.font, glyph, &placement) { path.addPath(glyphPath) }
            }
        }
        for underline in underlines() {
            if pathsByColor[underline.color] == nil {
                pathsByColor[underline.color] = CGMutablePath()
                colorOrder.append(underline.color)
            }
            pathsByColor[underline.color]?.addRect(underline.rectangle)
        }
        return colorOrder.compactMap { color in pathsByColor[color].map { path in (path: path as CGPath, color: color) } }
    }
}
