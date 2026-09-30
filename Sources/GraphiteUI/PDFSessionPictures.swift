import Foundation
import PDFKit
import GraphiteCore
import GraphiteApple

/// The picture of a PDF page that is selected for moving, resizing or removing.
struct PDFPictureSelection: Equatable {
    let pictureName: String
    let page: PDFHistoryPage

    static func == (leftSelection: PDFPictureSelection, rightSelection: PDFPictureSelection) -> Bool {
        leftSelection.pictureName == rightSelection.pictureName && leftSelection.page === rightSelection.page
    }
}

/// Pictures placed on PDF pages. Each change is an ordinary `PDFEdit` that saving replays
/// on the file, and one step of the PDF's undo history.
extension PDFSession {
    /// A new picture is this wide at most, as a fraction of the page as it is shown.
    static let newPictureWidthFraction = 0.6

    func pictures(on page: PDFPage) -> [PDFPicture] {
        PDFPageManager.pictures(on: page)
    }

    /// Places an image on the page in view, in the middle of what is shown of it, upright
    /// as the page is read, and selects it so it can be moved into place.
    ///
    /// - Parameter imageData: Any image ImageIO reads; it is prepared off the main actor.
    func addPicture(imageData: Data) async throws {
        let placement = visiblePageCenter?()
        let pageIndex = placement?.pageIndex ?? currentPageIndex
        guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else {
            throw GraphiteError.invalidFile("Page no longer exists.")
        }
        let cropBox = page.bounds(for: .cropBox)
        let quarterTurns = ((page.rotation / 90) % 4 + 4) % 4
        let isSideways = quarterTurns % 2 == 1
        // The page as it is read: a page turned a quarter is as wide as its box is tall.
        let shownPageWidth = isSideways ? cropBox.height : cropBox.width
        let shownPictureWidth = shownPageWidth * Self.newPictureWidthFraction
        let prepared = try await Task.detached(priority: .userInitiated) {
            try DrawingPictures.picture(from: imageData, canvasWidth: shownPictureWidth)
        }.value
        guard prepared.imageData.count <= PDFPicture.maximumImageBytes else { throw GraphiteError.oversized("This image is too large to place on a page.") }
        // The page may have changed while the image was prepared.
        guard page.document === document, document.index(for: page) != NSNotFound else { throw GraphiteError.invalidFile("Page no longer exists.") }
        let shownSize = prepared.frame.size
        let sizeOnPage = isSideways ? CGSize(width: shownSize.height, height: shownSize.width) : shownSize
        let center = placement?.pageIndex == document.index(for: page) ? placement?.center : nil
        let middle = center ?? CGPoint(x: cropBox.midX, y: cropBox.midY)
        let bounds = Self.keepingCenter(of: CGRect(x: middle.x - sizeOnPage.width / 2, y: middle.y - sizeOnPage.height / 2,
                                                   width: sizeOnPage.width, height: sizeOnPage.height), inside: cropBox)
        let picture = PDFPicture(imageData: prepared.imageData, bounds: bounds.integral, quarterTurns: quarterTurns)
        let historyPage = historyPage(for: page)
        try apply(.addPicture(page: document.index(for: page), picture: picture))
        registerStep(named: "Add Image") { session in
            try session.removePictureWithoutHistory(picture, on: historyPage)
        } redo: { session in
            try session.apply(.addPicture(page: session.currentIndex(of: historyPage), picture: picture))
        }
        selectedPicture = PDFPictureSelection(pictureName: picture.name, page: historyPage)
    }

    /// Moves or resizes the picture; undo puts it back where it was.
    func movePicture(_ selection: PDFPictureSelection, to newBounds: CGRect) throws {
        guard let page = selection.page.page, let picture = pictures(on: page).first(where: { picture in picture.name == selection.pictureName }) else {
            throw GraphiteError.invalidFile("This image no longer exists.")
        }
        let cropBox = page.bounds(for: .cropBox)
        let bounds = Self.keepingCenter(of: newBounds, inside: cropBox)
        guard bounds != picture.bounds, bounds.width > 0, bounds.height > 0 else { return }
        let previousBounds = picture.bounds
        let historyPage = selection.page
        let pictureName = picture.name
        func move(in session: PDFSession, from currentBounds: CGRect, to targetBounds: CGRect) throws {
            let reference = PDFAnnotationReference(pageIndex: try session.currentIndex(of: historyPage), name: pictureName,
                                                   annotationType: PDFPicture.annotationTypeName, bounds: currentBounds)
            try session.apply(.movePicture(reference, to: targetBounds))
        }
        try move(in: self, from: previousBounds, to: bounds)
        registerStep(named: "Move Image") { session in
            try move(in: session, from: bounds, to: previousBounds)
        } redo: { session in
            try move(in: session, from: previousBounds, to: bounds)
        }
    }

    /// Removes the picture; undo puts it back exactly, from the bytes its annotation kept.
    func removePicture(_ selection: PDFPictureSelection) throws {
        guard let page = selection.page.page, let picture = pictures(on: page).first(where: { picture in picture.name == selection.pictureName }) else {
            throw GraphiteError.invalidFile("This image no longer exists.")
        }
        let historyPage = selection.page
        try removePictureWithoutHistory(picture, on: historyPage)
        registerStep(named: "Delete Image") { session in
            try session.apply(.addPicture(page: session.currentIndex(of: historyPage), picture: picture))
        } redo: { session in
            try session.removePictureWithoutHistory(picture, on: historyPage)
        }
    }

    private func removePictureWithoutHistory(_ picture: PDFPicture, on page: PDFHistoryPage) throws {
        let pageIndex = try currentIndex(of: page)
        // The picture may have been moved since this step was recorded; its name finds it.
        try apply(.removeAnnotation(PDFAnnotationReference(pageIndex: pageIndex, name: picture.name,
                                                           annotationType: PDFPicture.annotationTypeName, bounds: picture.bounds)))
        if selectedPicture?.pictureName == picture.name { selectedPicture = nil }
    }

    /// The topmost picture at a point of the page, in the page's coordinates.
    func picture(at pagePoint: CGPoint, on page: PDFPage) -> PDFPicture? {
        pictures(on: page).last { picture in picture.bounds.contains(pagePoint) }
    }

    /// The rectangle moved so its middle is on the page: a picture can hang over an edge
    /// but cannot be lost beside the page.
    static func keepingCenter(of rectangle: CGRect, inside pageBox: CGRect) -> CGRect {
        let centerX = min(max(rectangle.midX, pageBox.minX), pageBox.maxX), centerY = min(max(rectangle.midY, pageBox.minY), pageBox.maxY)
        return CGRect(x: centerX - rectangle.width / 2, y: centerY - rectangle.height / 2, width: rectangle.width, height: rectangle.height)
    }
}
