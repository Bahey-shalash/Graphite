#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// What Graphite's lasso takes on a PDF page besides the ink: the page's pictures, in the
/// canvas's drawing coordinates (the page unturned, its top-left corner at the origin),
/// moved, resized and removed through the session as ordinary steps of the PDF's history;
/// and the page itself, for a picture of an area.
extension PDFPageCanvasView: LassoCanvasContent {
    private var session: PDFSession? { annotationCoordinator?.session }

    private var pageCoordinates: PageCoordinates? {
        guard let page else { return nil }
        return try? PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: drawingSize)
    }

    /// A rectangle of the page's coordinates, which count upward, in the drawing's.
    private func drawingRectangle(fromPage rectangle: CGRect, coordinates: PageCoordinates) -> CGRect {
        let topLeft = coordinates.overlayPoint(fromPDF: CGPoint(x: rectangle.minX, y: rectangle.maxY))
        let bottomRight = coordinates.overlayPoint(fromPDF: CGPoint(x: rectangle.maxX, y: rectangle.minY))
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    private func pageRectangle(fromDrawing rectangle: CGRect, coordinates: PageCoordinates) -> CGRect {
        let bottomLeft = coordinates.pdfPoint(fromOverlay: CGPoint(x: rectangle.minX, y: rectangle.maxY))
        let topRight = coordinates.pdfPoint(fromOverlay: CGPoint(x: rectangle.maxX, y: rectangle.minY))
        return CGRect(x: bottomLeft.x, y: bottomLeft.y, width: topRight.x - bottomLeft.x, height: topRight.y - bottomLeft.y)
    }

    private func pagePictures() -> [PDFPicture] {
        guard let page, let session else { return [] }
        return session.pictures(on: page)
    }

    func lassoPictures() -> [LassoPicture] {
        guard let coordinates = pageCoordinates else { return [] }
        // A picture is turned clockwise as the page is shown, which on the unturned page,
        // whose coordinates count downward like the screen's, is the same angle.
        return pagePictures().map { picture in
            LassoPicture(identifier: picture.name, frame: drawingRectangle(fromPage: picture.bounds, coordinates: coordinates),
                         rotationRadians: picture.rotationRadians)
        }
    }

    /// The picture as the unturned page draws it: turned back by the quarter turns the page
    /// was shown at when the picture was placed, so it is upright on a page shown that way.
    func lassoPictureImage(_ identifier: String) -> UIImage? {
        guard let picture = pagePictures().first(where: { picture in picture.name == identifier }),
              let image = UIImage(data: picture.imageData) else { return nil }
        return LassoAreaCapture.turned(image, quarterTurnsClockwise: -picture.quarterTurns)
    }

    func moveLassoPictures(to frames: [String: CGRect]) {
        guard let page, let session, let coordinates = pageCoordinates else { return }
        let historyPage = session.historyPage(for: page)
        do {
            for (identifier, frame) in frames.sorted(by: { first, second in first.key < second.key }) {
                try session.movePicture(PDFPictureSelection(pictureName: identifier, page: historyPage),
                                        to: pageRectangle(fromDrawing: frame, coordinates: coordinates))
            }
            session.undoManager.setActionName("Move Selection")
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    func deleteLassoPictures(_ identifiers: [String]) {
        guard let page, let session else { return }
        let historyPage = session.historyPage(for: page)
        do {
            for identifier in identifiers {
                try session.removePicture(PDFPictureSelection(pictureName: identifier, page: historyPage))
            }
            session.undoManager.setActionName("Delete Selection")
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    /// The pictures' annotations are hidden while the selection's frame carries them, and
    /// shown again after; a picture's annotation is the box around it as turned.
    func setLassoPicturesHidden(_ identifiers: Set<String>) {
        guard let page else { return }
        let hiddenBounds = pagePictures().filter { picture in identifiers.contains(picture.name) }.map(\.annotationBounds)
        for annotation in page.annotations where annotation.type == PDFPicture.annotationTypeName {
            let isHidden = hiddenBounds.contains { bounds in
                abs(bounds.minX - annotation.bounds.minX) < 0.5 && abs(bounds.minY - annotation.bounds.minY) < 0.5
                    && abs(bounds.width - annotation.bounds.width) < 0.5 && abs(bounds.height - annotation.bounds.height) < 0.5
            }
            if annotation.shouldDisplay == isHidden { annotation.shouldDisplay = !isHidden }
        }
    }

    /// The page as PDFKit draws it, with its pictures and every annotation that shows: white
    /// paper, then the page's content, unturned, in the drawing's coordinates. The ink this
    /// canvas edits is hidden on the page while the canvas shows it, and is drawn over this.
    func drawContentUnderInk(in context: CGContext, region: CGRect) {
        guard let page, let coordinates = pageCoordinates else { return }
        let cropBox = coordinates.cropBox
        context.saveGState()
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: coordinates.overlaySize).intersection(region))
        // `draw(with:to:)` applies the page's own transform, which moves the box to the
        // origin and turns the page; undone, the page's coordinates are flipped into the
        // drawing's, whose top-left corner is the box's.
        let scaleX = coordinates.overlaySize.width / cropBox.width, scaleY = coordinates.overlaySize.height / cropBox.height
        let pageToDrawing = CGAffineTransform(a: scaleX, b: 0, c: 0, d: -scaleY, tx: -cropBox.minX * scaleX, ty: cropBox.maxY * scaleY)
        context.concatenate(page.transform(for: .cropBox).inverted().concatenating(pageToDrawing))
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }

    var lassoDisplayQuarterTurns: Int { ((page?.rotation ?? 0) / 90 % 4 + 4) % 4 }

    var lassoDrawingBounds: CGRect { CGRect(origin: .zero, size: drawingSize) }

    var lassoCaptureName: String {
        guard let session, let page else { return "Screenshot" }
        let pageIndex = session.document.index(for: page)
        let name = session.location.deletingPathExtension().lastPathComponent
        return pageIndex == NSNotFound ? name : "\(name), page \(pageIndex + 1)"
    }

    var lassoNoteDestination: LassoNoteDestination? { annotationCoordinator?.noteDestination }
}
#endif
