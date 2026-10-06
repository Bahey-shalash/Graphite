import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import GraphiteCore

/// A picture placed on a PDF page, as in a paper notebook where a printed figure is glued
/// in. It is saved as a standard stamp annotation whose appearance is the picture, so every
/// PDF reader shows it. The annotation also keeps the picture's own bytes under a Graphite
/// key, so Graphite can move, resize, remove and restore it exactly, without reading the
/// appearance back.
public struct PDFPicture: Sendable, Equatable {
    /// The annotation's name, unique in its document.
    public let name: String
    /// PNG or JPEG data with any orientation already applied.
    public var imageData: Data
    /// Where the picture is, in the page's own coordinates.
    public var bounds: CGRect
    /// How many quarter turns clockwise the page was shown at when the picture was placed.
    /// The picture is drawn turned back by as many, so it is upright as the page is read.
    public let quarterTurns: Int

    /// Bound on one picture's bytes, which the annotation stores twice.
    public static let maximumImageBytes = 8 * 1_048_576
    public static let annotationTypeName = "Stamp"
    /// Written before the base64 text of the picture. PDFKit writes a text value that starts
    /// with a slash as a PDF name instead of a string, and the base64 text of every JPEG
    /// starts with one (`/9j/`), which came back without its first characters.
    static let storedImagePrefix = "base64:"

    public init(name: String = UUID().uuidString, imageData: Data, bounds: CGRect, quarterTurns: Int) {
        self.name = name
        self.imageData = imageData
        self.bounds = bounds
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    }

    /// The picture a Graphite stamp annotation holds, or nil for any other annotation.
    public init?(annotation: PDFAnnotation) {
        guard annotation.type == Self.annotationTypeName,
              let storedImage = annotation.value(forAnnotationKey: PDFPageManager.pictureKey) as? String,
              storedImage.hasPrefix(Self.storedImagePrefix),
              storedImage.utf8.count <= Self.storedImagePrefix.utf8.count + (Self.maximumImageBytes + 2) / 3 * 4,
              let imageData = Data(base64Encoded: String(storedImage.dropFirst(Self.storedImagePrefix.count))), !imageData.isEmpty,
              let name = annotation.persistentName else { return nil }
        let storedTurns = (annotation.value(forAnnotationKey: PDFPageManager.pictureTurnsKey) as? NSNumber)?.intValue ?? 0
        self.init(name: name, imageData: imageData, bounds: annotation.bounds, quarterTurns: storedTurns)
    }

    public var hasValidGeometry: Bool {
        !imageData.isEmpty && imageData.count <= Self.maximumImageBytes
            && [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) && bounds.width > 0 && bounds.height > 0
    }

    public func reference(onPageAt pageIndex: Int) -> PDFAnnotationReference {
        PDFAnnotationReference(pageIndex: pageIndex, name: name, annotationType: Self.annotationTypeName, bounds: bounds)
    }

    /// - Parameter isForWrittenDocument: Whether the annotation's document will be written,
    ///   where PDFKit asks the annotation for its appearance, or is shown, where it asks the
    ///   annotation to draw itself on the page; see `PDFPictureAnnotation`.
    func makeAnnotation(isForWrittenDocument: Bool) throws -> PDFAnnotation {
        guard hasValidGeometry, let image = Self.decodedImage(imageData) else {
            throw GraphiteError.invalidFile("This image cannot be placed on the page.")
        }
        let annotation = PDFPictureAnnotation(bounds: bounds, image: image, quarterTurns: quarterTurns, drawsAppearance: isForWrittenDocument)
        annotation.setPersistentName(name)
        annotation.setValue(Self.storedImagePrefix + imageData.base64EncodedString(), forAnnotationKey: PDFPageManager.pictureKey)
        annotation.setValue(NSNumber(value: quarterTurns), forAnnotationKey: PDFPageManager.pictureTurnsKey)
        // A picture has no border or note of its own.
        annotation.shouldPrint = true
        return annotation
    }

    /// JPEG data is handed to Core Graphics as it is, so the PDF stores the same compressed
    /// bytes instead of every pixel; other formats are decoded.
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
/// itself on the page in a document that is shown.
///
/// PDFKit calls the same method for both, with different coordinates. For an appearance
/// the origin is the MediaBox's origin and the page's rotation is not applied; on a shown
/// page the annotation is expected to apply the page's rotation and display box itself
/// (`PDFPage.transform(_:for:)`). An annotation cannot tell the two calls apart, so each
/// one is made for one of them. After a save and a reopen the annotation is an ordinary one
/// that PDFKit draws from its saved appearance.
final class PDFPictureAnnotation: PDFAnnotation {
    // Optional references only, set before the annotation is shared; see
    // `PDFOutlinedInkAnnotation` for why.
    private var image: CGImage?
    private var quarterTurns: NSNumber?
    private var drawsAppearance: NSNumber?

    init(bounds: CGRect, image: CGImage, quarterTurns: Int, drawsAppearance: Bool) {
        self.image = image
        self.quarterTurns = NSNumber(value: quarterTurns)
        self.drawsAppearance = NSNumber(value: drawsAppearance)
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
            copiedAnnotation.image = image
            copiedAnnotation.quarterTurns = quarterTurns
            copiedAnnotation.drawsAppearance = drawsAppearance
        }
        return copiedAnnotation
    }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let image else {
            super.draw(with: box, in: context)
            return
        }
        let pictureBounds = bounds
        let turns = quarterTurns?.intValue ?? 0
        context.saveGState()
        if drawsAppearance?.boolValue == true {
            if let mediaBoxOrigin = page?.bounds(for: .mediaBox).origin {
                context.translateBy(x: -mediaBoxOrigin.x, y: -mediaBoxOrigin.y)
            }
        } else {
            page?.transform(context, for: box)
        }
        context.interpolationQuality = .high
        context.translateBy(x: pictureBounds.midX, y: pictureBounds.midY)
        // Page coordinates count upward, where a positive angle turns counterclockwise:
        // the picture is turned back against the page's own clockwise rotation.
        context.rotate(by: CGFloat(turns) * .pi / 2)
        let isSideways = turns % 2 == 1
        let drawnSize = isSideways ? CGSize(width: pictureBounds.height, height: pictureBounds.width) : pictureBounds.size
        context.draw(image, in: CGRect(x: -drawnSize.width / 2, y: -drawnSize.height / 2, width: drawnSize.width, height: drawnSize.height))
        context.restoreGState()
    }
}
