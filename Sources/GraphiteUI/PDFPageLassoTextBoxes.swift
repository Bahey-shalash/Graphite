#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// Text boxes as the lasso takes them on a PDF page (`PDFPageCanvasView: LassoCanvasContent`):
/// each is one of the lasso's pictures, framed by the rectangle it fills before it is turned
/// about its middle, in the canvas's drawing coordinates.
extension PDFPageCanvasView {
    /// Starts the identifier of a text box among the lasso's pictures, which are otherwise
    /// known by their own names.
    static let textBoxIdentifierPrefix = "graphite-text-box:"

    func pageTextBoxes() -> [PDFTextBox] {
        guard let page, let session = annotationCoordinator?.session else { return [] }
        return session.textBoxes(on: page).filter { box in !box.name.isEmpty }
    }

    func textBox(identifiedAs identifier: String) -> PDFTextBox? {
        guard identifier.hasPrefix(Self.textBoxIdentifierPrefix) else { return nil }
        let name = String(identifier.dropFirst(Self.textBoxIdentifierPrefix.count))
        return pageTextBoxes().first { box in box.name == name }
    }

    /// The box as a lasso picture: the drawing's coordinates count downward from the page's
    /// top-left corner, where a clockwise angle is the same as the box's on its page.
    static func lassoPicture(of box: PDFTextBox, coordinates: PageCoordinates) -> LassoPicture {
        let middle = coordinates.overlayPoint(fromPDF: box.middle)
        let scaleX = coordinates.overlaySize.width / max(coordinates.cropBox.width, 1)
        let scaleY = coordinates.overlaySize.height / max(coordinates.cropBox.height, 1)
        let size = CGSize(width: CGFloat(box.width) * scaleX, height: CGFloat(box.height) * scaleY)
        return LassoPicture(identifier: textBoxIdentifierPrefix + box.name,
                            frame: CGRect(x: middle.x - size.width / 2, y: middle.y - size.height / 2, width: size.width, height: size.height),
                            rotationRadians: box.rotationRadians)
    }

    /// The box where the lasso put its frame: scaled as the frame was, with its middle where
    /// the frame's is.
    static func box(_ box: PDFTextBox, movedTo frame: CGRect, coordinates: PageCoordinates) -> PDFTextBox {
        let scaleX = coordinates.overlaySize.width / max(coordinates.cropBox.width, 1)
        let oldWidth = CGFloat(box.width) * scaleX
        let factor = oldWidth > 0 ? Double(frame.width / oldWidth) : 1
        let scaled = abs(factor - 1) < 0.001 ? box : PDFTextBoxLayout.fitted(box.scaled(by: factor))
        return scaled.movingMiddle(to: coordinates.pdfPoint(fromOverlay: CGPoint(x: frame.midX, y: frame.midY)))
    }

    /// The box drawn upright, as the lasso's frame carries it.
    static func image(of box: PDFTextBox) -> UIImage? {
        guard box.width > 0, box.height > 0 else { return nil }
        let layout = PDFTextBoxLayout(box: box)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = LassoAreaCapture.preferredPixelsPerPoint
        return UIGraphicsImageRenderer(size: CGSize(width: box.width, height: box.height), format: format).image { rendererContext in
            rendererContext.cgContext.translateBy(x: 0, y: CGFloat(box.height))
            rendererContext.cgContext.scaleBy(x: 1, y: -1)
            layout.drawInBoxSpace(rendererContext.cgContext)
        }
    }

    /// Hides the boxes the selection's frame carries while it is dragged: Graphite's in the
    /// view that draws them over the ink, another application's through its annotation.
    func setLassoTextBoxesHidden(_ identifiers: Set<String>) {
        guard let page else { return }
        let names = Set(identifiers.filter { identifier in identifier.hasPrefix(Self.textBoxIdentifierPrefix) }
            .map { identifier in String(identifier.dropFirst(Self.textBoxIdentifierPrefix.count)) })
        overlayView?.textBoxesView.setCarriedBoxNames(names)
        for annotation in page.annotations where annotation.type == PDFTextBox.annotationTypeName && !PDFPageTextBoxesView.drawsAnnotation(annotation) {
            guard let name = annotation.persistentName else { continue }
            let isHidden = names.contains(name)
            if annotation.shouldDisplay == isHidden { annotation.shouldDisplay = !isHidden }
        }
    }

    /// Graphite's boxes over what the page draws, as they are over the ink, for a picture of an
    /// area; their annotations are hidden while this page's overlay draws them.
    func drawTextBoxes(in context: CGContext, coordinates: PageCoordinates) {
        guard let page else { return }
        let cropBox = coordinates.cropBox
        let scaleX = coordinates.overlaySize.width / max(cropBox.width, 1), scaleY = coordinates.overlaySize.height / max(cropBox.height, 1)
        context.saveGState()
        context.concatenate(CGAffineTransform(a: scaleX, b: 0, c: 0, d: -scaleY, tx: -cropBox.minX * scaleX, ty: cropBox.maxY * scaleY))
        for annotation in page.annotations where PDFPageTextBoxesView.drawsAnnotation(annotation) && !annotation.shouldDisplay {
            guard let box = PDFTextBox(annotation: annotation) else { continue }
            PDFTextBoxLayout(box: box).draw(inPageContext: context)
        }
        context.restoreGState()
    }
}
#endif
