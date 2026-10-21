#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// Graphite's text boxes of one PDF page, drawn over the page's Pencil canvas, as they are
/// over the ink in the file (`PDFPageTextBoxes`). It sits in the page's overlay
/// (`PDFPageOverlayView`), in the page's points with its top-left corner at the origin, and
/// takes no touches.
///
/// The text is drawn as its outlines in shape layers (`PDFTextBoxLayout.textOutlines`), which
/// Core Animation draws at the resolution they are shown at: the text is as sharp as the page
/// at any zoom, without a bitmap the size of the zoomed page. While a page shows this view,
/// the boxes' own annotations are hidden, so a box is not drawn twice. Another application's
/// box is left to PDFKit, which draws the appearance its application wrote, where that
/// application put it among the page's annotations.
final class PDFPageTextBoxesView: UIView {
    /// The box being typed in, which the text editor shows instead.
    private(set) var hiddenBoxName: String?
    /// The boxes the lasso's frame carries while it is dragged, which it shows instead.
    private var carriedBoxNames: Set<String> = []
    private var shownBoxes: [PDFTextBox] = []
    private var cropBox: CGRect = .zero
    /// The boxes in the page's points, scaled to the view's size in `layoutSubviews`: PDFKit
    /// may make a page's overlay another size than the page.
    private let pageLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isOpaque = false
        // Pages are white paper; the boxes keep their colors in dark appearance.
        overrideUserInterfaceStyle = .light
        pageLayer.anchorPoint = .zero
        layer.addSublayer(pageLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard cropBox.width > 0, cropBox.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageLayer.bounds = CGRect(origin: .zero, size: cropBox.size)
        pageLayer.position = .zero
        pageLayer.setAffineTransform(CGAffineTransform(scaleX: bounds.width / cropBox.width, y: bounds.height / cropBox.height))
        CATransaction.commit()
    }

    required init?(coder: NSCoder) { nil }

    /// Draws the page's boxes that Graphite wrote, except the one being typed in.
    func show(_ boxes: [PDFTextBox], cropBox: CGRect, hiding hiddenBoxName: String?) {
        guard boxes != shownBoxes || cropBox != self.cropBox || hiddenBoxName != self.hiddenBoxName else { return }
        shownBoxes = boxes
        self.cropBox = cropBox
        self.hiddenBoxName = hiddenBoxName
        rebuildLayers()
    }

    func setCarriedBoxNames(_ names: Set<String>) {
        guard names != carriedBoxNames else { return }
        carriedBoxNames = names
        rebuildLayers()
    }

    private func rebuildLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageLayer.sublayers?.forEach { sublayer in sublayer.removeFromSuperlayer() }
        let pageToView = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -cropBox.minX, ty: cropBox.maxY)
        for box in shownBoxes where box.name != hiddenBoxName && !carriedBoxNames.contains(box.name) {
            pageLayer.addSublayer(Self.boxLayer(for: box, pageToView: pageToView, displayScale: traitCollection.displayScale))
        }
        CATransaction.commit()
        setNeedsLayout()
    }

    /// One box: its fill, its text's outlines in each of its colors, and its border; or, for a
    /// box with emoji, whose glyphs are pictures, the whole box drawn as a picture.
    private static func boxLayer(for box: PDFTextBox, pageToView: CGAffineTransform, displayScale: CGFloat) -> CALayer {
        let layout = PDFTextBoxLayout(box: box)
        if layout.usesColorGlyphs { return PDFTextBoxPictureLayer(layout: layout, pageToView: pageToView, displayScale: displayScale) }
        var boxToView = layout.boxToPage.concatenating(pageToView)
        let container = CALayer()
        let outline = CGPath(rect: layout.boxRectangle, transform: &boxToView)
        if let fillColor = box.style.fillColor {
            container.addSublayer(shapeLayer(outline, fill: PDFTextBoxLayout.cgColor(fillColor), displayScale: displayScale))
        }
        for text in layout.textOutlines() {
            guard let path = text.path.copy(using: &boxToView) else { continue }
            container.addSublayer(shapeLayer(path, fill: PDFTextBoxLayout.cgColor(text.color), displayScale: displayScale))
        }
        if box.style.hasBorder, let borderColor = box.style.borderColor {
            let inset = CGFloat(box.style.borderWidth) / 2
            let borderPath = CGPath(rect: layout.boxRectangle.insetBy(dx: inset, dy: inset), transform: &boxToView)
            let border = shapeLayer(borderPath, fill: nil, displayScale: displayScale)
            border.strokeColor = PDFTextBoxLayout.cgColor(borderColor)
            border.lineWidth = CGFloat(box.style.borderWidth)
            container.addSublayer(border)
        }
        return container
    }

    private static func shapeLayer(_ path: CGPath, fill: CGColor?, displayScale: CGFloat) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = fill
        shape.strokeColor = nil
        // Core Animation draws the shape at the zoom it is shown at.
        shape.contentsScale = displayScale
        return shape
    }

    /// Whether the annotation is drawn by this view while it shows its page: one of
    /// Graphite's text boxes.
    static func drawsAnnotation(_ annotation: PDFAnnotation) -> Bool {
        annotation.type == PDFTextBox.annotationTypeName && annotation.value(forAnnotationKey: PDFPageManager.textBoxRecordKey) != nil
    }
}
/// A text box drawn as a picture, for one with emoji, whose glyphs have no outlines to draw
/// as shapes. It is drawn as sharp as the PDF view's largest zoom shows it, within a bound of
/// pixels, as the page's canvas is (`PDFPageOverlayView.maximumRenderingScale`).
final class PDFTextBoxPictureLayer: CALayer {
    private let layout: PDFTextBoxLayout?
    /// The most pixels one box is drawn with: 16 megapixels, 64 MB.
    private static let maximumPixelCount: CGFloat = 16_777_216

    init(layout: PDFTextBoxLayout, pageToView: CGAffineTransform, displayScale: CGFloat) {
        self.layout = layout
        super.init()
        let bounds = layout.box.annotationBounds
        frame = bounds.applying(pageToView)
        let wantedScale = displayScale * PDFPageOverlayView.maximumRenderingScale
        let pixelLimitedScale = (Self.maximumPixelCount / max(frame.width * frame.height, 1)).squareRoot()
        contentsScale = max(min(wantedScale, pixelLimitedScale), 1)
        setNeedsDisplay()
    }

    override init(layer: Any) {
        layout = (layer as? PDFTextBoxPictureLayer)?.layout
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(in context: CGContext) {
        guard let layout else { return }
        let pageBounds = layout.box.annotationBounds
        // The layer counts downward from the box's top; the page upward from its bottom.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        layout.draw(inPageContext: context)
    }
}
#endif
