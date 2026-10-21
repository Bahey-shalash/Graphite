import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import GraphiteCore

/// A picture placed on a PDF page, as in a paper notebook where a printed figure is glued
/// in. It is saved as a standard stamp annotation whose appearance is the picture, so every
/// PDF reader shows it. The annotation also keeps the picture's own bytes under a Graphite
/// key, so Graphite can move, resize, turn, remove and restore it exactly, without reading
/// the appearance back.
public struct PDFPicture: Sendable, Equatable {
    /// The annotation's name, unique in its document.
    public let name: String
    /// PNG or JPEG data with any orientation already applied.
    public var imageData: Data
    /// Where the picture is before it is turned by hand, in the page's own coordinates.
    public var bounds: CGRect
    /// How many quarter turns clockwise the page was shown at when the picture was placed.
    /// The picture is drawn turned back by as many, so it is upright as the page is read.
    public let quarterTurns: Int
    /// How far the picture is turned by hand about the middle of its bounds, in radians,
    /// clockwise as the page is shown, from -π to π (`PictureRotation.normalized`). The
    /// annotation's rectangle is then the box around it (`annotationBounds`).
    public var rotationRadians: Double {
        didSet {
            let normalizedRadians = PictureRotation.normalized(rotationRadians)
            if normalizedRadians != rotationRadians { rotationRadians = normalizedRadians }
        }
    }

    /// Bound on one picture's bytes, which the annotation stores twice.
    public static let maximumImageBytes = 8 * 1_048_576
    public static let annotationTypeName = "Stamp"
    /// Written before the base64 text of the picture. PDFKit writes a text value that starts
    /// with a slash as a PDF name instead of a string, and the base64 text of every JPEG
    /// starts with one (`/9j/`), which came back without its first characters.
    static let storedImagePrefix = "base64:"

    public init(name: String = UUID().uuidString, imageData: Data, bounds: CGRect, quarterTurns: Int, rotationRadians: Double = 0) {
        self.name = name
        self.imageData = imageData
        self.bounds = bounds
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.rotationRadians = PictureRotation.normalized(rotationRadians)
    }

    /// The picture a Graphite stamp annotation holds, or nil for any other annotation. A
    /// turned picture is under `turnedPictureKey`; one turned by a build of 2026-10-11 is
    /// under `pictureKey` with its angle, and is read turned as well.
    public init?(annotation: PDFAnnotation) {
        guard annotation.type == Self.annotationTypeName,
              let storedImage = PDFPageManager.storedPictureKeys.lazy.compactMap({ key in annotation.value(forAnnotationKey: key) }).first as? String,
              storedImage.hasPrefix(Self.storedImagePrefix),
              storedImage.utf8.count <= Self.storedImagePrefix.utf8.count + (Self.maximumImageBytes + 2) / 3 * 4,
              let imageData = Data(base64Encoded: String(storedImage.dropFirst(Self.storedImagePrefix.count))), !imageData.isEmpty,
              let name = annotation.persistentName else { return nil }
        let storedTurns = (annotation.value(forAnnotationKey: PDFPageManager.pictureTurnsKey) as? NSNumber)?.intValue ?? 0
        let turn = Self.storedTurn(of: annotation)
        self.init(name: name, imageData: imageData, bounds: turn?.bounds ?? annotation.bounds, quarterTurns: storedTurns, rotationRadians: turn?.rotationRadians ?? 0)
    }

    /// The frame and angle of a picture turned by hand, from its annotation: nil for an
    /// upright one, or when the stored angle or size cannot be used, which shows the
    /// picture upright in the annotation's rectangle.
    private static func storedTurn(of annotation: PDFAnnotation) -> (bounds: CGRect, rotationRadians: Double)? {
        guard let rotationRadians = (annotation.value(forAnnotationKey: PDFPageManager.pictureRotationKey) as? NSNumber)?.doubleValue,
              rotationRadians.isFinite, rotationRadians != 0,
              let storedWidth = (annotation.value(forAnnotationKey: PDFPageManager.pictureWidthKey) as? NSNumber)?.doubleValue,
              let storedHeight = (annotation.value(forAnnotationKey: PDFPageManager.pictureHeightKey) as? NSNumber)?.doubleValue,
              storedWidth.isFinite, storedHeight.isFinite, storedWidth > 0, storedHeight > 0 else { return nil }
        let annotationBounds = annotation.bounds
        let middle = CGPoint(x: annotationBounds.midX, y: annotationBounds.midY)
        var size = CGSize(width: storedWidth, height: storedHeight)
        // Another application may have resized the annotation's rectangle: the picture then
        // keeps its proportions and fills the new rectangle's width as turned.
        let expectedWidth = Double(PictureRotation.boundingRectangle(of: CGRect(origin: .zero, size: size), turnedBy: rotationRadians).width)
        if expectedWidth > 0, abs(expectedWidth - Double(annotationBounds.width)) > Self.storedSizeTolerance {
            let scale = Double(annotationBounds.width) / expectedWidth
            size = CGSize(width: storedWidth * scale, height: storedHeight * scale)
        }
        return (CGRect(x: Double(middle.x) - Double(size.width) / 2, y: Double(middle.y) - Double(size.height) / 2,
                       width: Double(size.width), height: Double(size.height)), rotationRadians)
    }

    /// A rectangle written to a file and read back differs in its last digits.
    private static let storedSizeTolerance = 0.01

    public var isTurned: Bool { rotationRadians != 0 }

    /// The annotation's rectangle: the upright box around the picture as turned.
    public var annotationBounds: CGRect {
        // Page coordinates count upward, where a clockwise turn is a negative angle.
        PictureRotation.boundingRectangle(of: bounds, turnedBy: -rotationRadians)
    }

    /// Whether the picture, as turned, covers a point of the page.
    public func contains(_ pagePoint: CGPoint) -> Bool {
        PictureRotation.rectangle(bounds, turnedBy: -rotationRadians, contains: pagePoint)
    }

    public var hasValidGeometry: Bool {
        !imageData.isEmpty && imageData.count <= Self.maximumImageBytes
            && [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) && bounds.width > 0 && bounds.height > 0
            && rotationRadians.isFinite
    }

    public func reference(onPageAt pageIndex: Int) -> PDFAnnotationReference {
        PDFAnnotationReference(pageIndex: pageIndex, name: name, annotationType: Self.annotationTypeName, bounds: annotationBounds)
    }

    /// - Parameter isForWrittenDocument: Whether the annotation's document will be written,
    ///   where PDFKit asks the annotation for its appearance, or is shown, where it asks the
    ///   annotation to draw itself on the page; see `PDFPictureAnnotation`.
    func makeAnnotation(isForWrittenDocument: Bool) throws -> PDFAnnotation {
        guard hasValidGeometry, let image = Self.decodedImage(imageData) else {
            throw GraphiteError.invalidFile("This image cannot be placed on the page.")
        }
        let annotation = PDFPictureAnnotation(bounds: annotationBounds, image: image, pictureSize: bounds.size, quarterTurns: quarterTurns,
                                              rotationRadians: rotationRadians, drawsAppearance: isForWrittenDocument)
        annotation.setPersistentName(name)
        // An upright picture stays under the key every build reads; see `turnedPictureKey`.
        annotation.setValue(Self.storedImagePrefix + imageData.base64EncodedString(),
                            forAnnotationKey: isTurned ? PDFPageManager.turnedPictureKey : PDFPageManager.pictureKey)
        annotation.setValue(NSNumber(value: quarterTurns), forAnnotationKey: PDFPageManager.pictureTurnsKey)
        if isTurned {
            annotation.setValue(NSNumber(value: rotationRadians), forAnnotationKey: PDFPageManager.pictureRotationKey)
            annotation.setValue(NSNumber(value: Double(bounds.width)), forAnnotationKey: PDFPageManager.pictureWidthKey)
            annotation.setValue(NSNumber(value: Double(bounds.height)), forAnnotationKey: PDFPageManager.pictureHeightKey)
        }
        // A picture has no border or note of its own.
        annotation.shouldPrint = true
        return annotation
    }

    /// JPEG data is handed to Core Graphics as it is, which decodes it only when it is drawn;
    /// other formats are decoded. (PDFKit still writes a stamp's appearance image as Flate
    /// pixels, not the JPEG's own bytes.)
    static func decodedImage(_ imageData: Data) -> CGImage? {
        if imageData.starts(with: [0xFF, 0xD8]), let provider = CGDataProvider(data: imageData as CFData),
           let jpegImage = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            return jpegImage
        }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

/// Draws a picture as a stamp annotation: its appearance in a document that is written, and
/// itself on the page in a document that is shown. A picture turned by hand is drawn turned
/// about the middle of the annotation's rectangle, the box around it.
///
/// PDFKit calls the same method for both, with different coordinates. For an appearance
/// the origin is the MediaBox's origin and the page's rotation is not applied; on a shown
/// page the annotation is expected to apply the page's rotation and display box itself
/// (`PDFPage.transform(_:for:)`). An annotation cannot tell the two calls apart, so each
/// one is made for one of them.
///
/// In a shown document PDFKit also makes every stamp it reads from the file one of these
/// (`PDFAnnotationDrawingDelegate`). Such an annotation has no picture of its own: at its
/// first drawing it reads Graphite's picture from its keys and from then on draws it
/// itself, as after an edit, instead of leaving PDFKit to draw the saved appearance. Any
/// other stamp is drawn by PDFKit as before.
final class PDFPictureAnnotation: PDFAnnotation {
    // Optional references only, set before the annotation is shared; see
    // `PDFOutlinedInkAnnotation` for why.
    private var picture: PDFPictureAnnotationDrawing?
    /// For a stamp PDFKit read from a shown document's file: what was read at the first
    /// drawing, which is nil inside when the stamp is not one of Graphite's pictures. Set
    /// once, under `fileReadingLock`, since PDFKit draws pages on several threads.
    private var pictureReadFromFile: PDFPictureReadFromFile?
    private static let fileReadingLock = NSLock()

    init(bounds: CGRect, image: CGImage, pictureSize: CGSize, quarterTurns: Int, rotationRadians: Double, drawsAppearance: Bool) {
        picture = PDFPictureAnnotationDrawing(image: image, pictureSize: pictureSize, quarterTurns: quarterTurns,
                                              rotationRadians: rotationRadians, drawsAppearance: drawsAppearance)
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    override init(bounds: CGRect, forType annotationType: PDFAnnotationSubtype, withProperties properties: [AnyHashable: Any]?) {
        super.init(bounds: bounds, forType: annotationType, withProperties: properties)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        let copiedAnnotation = super.copy(with: zone)
        if let copiedAnnotation = copiedAnnotation as? PDFPictureAnnotation {
            copiedAnnotation.picture = picture
            // The copy reads its own keys again, which may differ once it is changed.
        }
        return copiedAnnotation
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let drawing = picture ?? readPictureFromFile() else {
            super.draw(with: box, in: context)
            return
        }
        let annotationBounds = bounds
        context.saveGState()
        if drawing.drawsAppearance {
            if let mediaBoxOrigin = page?.bounds(for: .mediaBox).origin {
                context.translateBy(x: -mediaBoxOrigin.x, y: -mediaBoxOrigin.y)
            }
        } else {
            page?.transform(context, for: box)
        }
        // A stamp's saved appearance is drawn with the image interpolation of the context
        // it is drawn into, and PDFView on iOS draws it with low interpolation even with
        // its `interpolationQuality` set to high: a picture shown much smaller than its
        // pixels then shows moiré and jagged edges. Drawn here, it is drawn at high quality.
        context.interpolationQuality = .high
        context.translateBy(x: annotationBounds.midX, y: annotationBounds.midY)
        // Page coordinates count upward, where a positive angle turns counterclockwise:
        // the picture is turned back against the page's own clockwise rotation, and by the
        // clockwise turn given by hand.
        context.rotate(by: CGFloat(drawing.quarterTurns) * .pi / 2 - CGFloat(drawing.rotationRadians))
        let isSideways = drawing.quarterTurns % 2 == 1
        let pictureSize = drawing.pictureSize
        let drawnSize = isSideways ? CGSize(width: pictureSize.height, height: pictureSize.width) : pictureSize
        context.draw(drawing.image, in: CGRect(x: -drawnSize.width / 2, y: -drawnSize.height / 2, width: drawnSize.width, height: drawnSize.height))
        context.restoreGState()
    }

    /// The picture a stamp read from a shown document's file holds, read once; nil for a
    /// stamp that is not one of Graphite's pictures or whose picture cannot be decoded,
    /// which PDFKit then draws from its saved appearance.
    private func readPictureFromFile() -> PDFPictureAnnotationDrawing? {
        Self.fileReadingLock.lock()
        let earlierReading = pictureReadFromFile
        Self.fileReadingLock.unlock()
        if let earlierReading { return earlierReading.drawing }
        // Decoded outside the lock, so pages drawn at the same time do not wait for each
        // other's pictures; two threads may both decode it the first time, harmlessly.
        let drawing = PDFPicture(annotation: self).flatMap { storedPicture -> PDFPictureAnnotationDrawing? in
            guard storedPicture.hasValidGeometry, let image = PDFPicture.decodedImage(storedPicture.imageData) else { return nil }
            return PDFPictureAnnotationDrawing(image: image, pictureSize: storedPicture.bounds.size, quarterTurns: storedPicture.quarterTurns,
                                               rotationRadians: storedPicture.rotationRadians, drawsAppearance: false)
        }
        Self.fileReadingLock.lock()
        defer { Self.fileReadingLock.unlock() }
        if pictureReadFromFile == nil { pictureReadFromFile = PDFPictureReadFromFile(drawing: drawing) }
        return pictureReadFromFile?.drawing
    }
}

/// What a `PDFPictureAnnotation` draws, fixed when it is made.
final class PDFPictureAnnotationDrawing: Sendable {
    let image: CGImage
    /// The picture's own width and height before it is turned.
    let pictureSize: CGSize
    let quarterTurns: Int
    /// The angle turned by hand, clockwise as the page is shown.
    let rotationRadians: Double
    /// Whether it draws the appearance of a document that is written, rather than itself
    /// on a shown page.
    let drawsAppearance: Bool

    init(image: CGImage, pictureSize: CGSize, quarterTurns: Int, rotationRadians: Double, drawsAppearance: Bool) {
        self.image = image
        self.pictureSize = pictureSize
        self.quarterTurns = quarterTurns
        self.rotationRadians = rotationRadians
        self.drawsAppearance = drawsAppearance
    }
}

/// The result of reading a stamp from a shown document's file, kept so it is read once.
final class PDFPictureReadFromFile: Sendable {
    let drawing: PDFPictureAnnotationDrawing?

    init(drawing: PDFPictureAnnotationDrawing?) { self.drawing = drawing }
}
