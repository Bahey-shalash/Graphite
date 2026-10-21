#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteCore
import GraphiteApple

/// What Graphite's lasso takes on a PDF page besides the ink: the page's pictures and text
/// boxes, in the canvas's drawing coordinates (the page unturned, its top-left corner at the
/// origin), moved, resized and removed through the session as ordinary steps of the PDF's
/// history; and the page itself, for a picture of an area. A text box is one of the lasso's
/// pictures, known by `textBoxIdentifierPrefix` and its name; resized with ink, its text is
/// scaled with it, as everything in the selection is.
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
        let pictures = pagePictures().map { picture in
            LassoPicture(identifier: picture.name, frame: drawingRectangle(fromPage: picture.bounds, coordinates: coordinates),
                         rotationRadians: picture.rotationRadians)
        }
        return pictures + pageTextBoxes().map { box in Self.lassoPicture(of: box, coordinates: coordinates) }
    }

    /// The picture as the unturned page draws it: turned back by the quarter turns the page
    /// was shown at when the picture was placed, so it is upright on a page shown that way.
    func lassoPictureImage(_ identifier: String) -> UIImage? {
        if let box = textBox(identifiedAs: identifier) { return Self.image(of: box) }
        guard let picture = pagePictures().first(where: { picture in picture.name == identifier }),
              let image = UIImage(data: picture.imageData) else { return nil }
        return LassoAreaCapture.turned(image, quarterTurnsClockwise: -picture.quarterTurns)
    }

    func moveLassoPictures(to frames: [String: CGRect]) {
        guard let page, let session, let coordinates = pageCoordinates else { return }
        let historyPage = session.historyPage(for: page)
        do {
            for (identifier, frame) in frames.sorted(by: { first, second in first.key < second.key }) {
                if let box = textBox(identifiedAs: identifier) {
                    let moved = Self.box(box, movedTo: frame, coordinates: coordinates)
                    try session.changeTextBox(from: box, to: moved, on: historyPage, actionName: "Move Selection")
                    continue
                }
                try session.movePicture(PDFPictureSelection(pictureName: identifier, page: historyPage),
                                        to: pageRectangle(fromDrawing: frame, coordinates: coordinates))
            }
            session.undoManager.setActionName("Move Selection")
        } catch {
            session.reportFailedChange(error)
        }
    }

    func deleteLassoPictures(_ identifiers: [String]) {
        guard let page, let session else { return }
        let historyPage = session.historyPage(for: page)
        do {
            for identifier in identifiers {
                if let box = textBox(identifiedAs: identifier) {
                    try session.changeTextBox(from: box, to: nil, on: historyPage, actionName: "Delete Selection")
                    continue
                }
                try session.removePicture(PDFPictureSelection(pictureName: identifier, page: historyPage))
            }
            session.undoManager.setActionName("Delete Selection")
        } catch {
            session.reportFailedChange(error)
        }
    }

    /// The pictures' annotations are hidden while the selection's frame carries them, and
    /// shown again after; a picture's annotation is the box around it as turned.
    /// A picture is known by its annotation's name: two copies of one image pasted at the
    /// same spot have the same bounds, and selecting one hid both.
    func setLassoPicturesHidden(_ identifiers: Set<String>) {
        guard let page else { return }
        setLassoTextBoxesHidden(identifiers)
        let hiddenBounds = pagePictures().filter { picture in identifiers.contains(picture.name) }.map(\.annotationBounds)
        for annotation in page.annotations where annotation.type == PDFPicture.annotationTypeName {
            if let name = annotation.persistentName {
                let isHidden = identifiers.contains(name)
                if annotation.shouldDisplay == isHidden { annotation.shouldDisplay = !isHidden }
                continue
            }
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
        drawTextBoxes(in: context, coordinates: coordinates)
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

    func pastePicture(_ imageData: Data, centeredAt drawingPoint: CGPoint) {
        guard let session, let page, let coordinates = pageCoordinates else { return }
        let pageIndex = session.document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        session.pastePicture(imageData, placement: (pageIndex, coordinates.pdfPoint(fromOverlay: drawingPoint)))
    }
}

extension PDFSession {
    /// Places an image from the pasteboard as a picture on a page, with its middle at a point
    /// of the page, or in the middle of the page in view, at its own size where that fits.
    func pastePicture(_ imageData: Data, placement: (pageIndex: Int, center: CGPoint)?) {
        let preferredWidth = LassoPasteboard.preferredWidth(ofImageData: imageData)
        Task {
            do { try await addPicture(imageData: imageData, placement: placement, preferredWidth: preferredWidth) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

extension PDFAnnotationCoordinator {
    /// ⌘V while a PDF is written on: ink copied with the lasso goes in the middle of the page
    /// in view, as ink; an image goes there as a picture.
    func pasteFromPasteboard() {
        guard let content = LassoPasteboard.content(), let placement = session.visiblePageCenter?(),
              let page = session.document.page(at: placement.pageIndex) else { return }
        switch content {
        case .image(let imageData):
            session.pastePicture(imageData, placement: placement)
        case .ink:
            guard let canvas = editingCanvas(for: page), let coordinates = try? PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: canvas.drawingSize) else { return }
            let drawingPoint = coordinates.overlayPoint(fromPDF: placement.center)
            canvas.inkSelection.pasteInk(at: CGPoint(x: drawingPoint.x * canvas.zoomScale, y: drawingPoint.y * canvas.zoomScale))
        }
    }
}
#endif
