import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import GraphiteCore

/// Why a PDF page or a picture cannot become a paper template.
public enum MyPaperTemplateError: Error, Equatable {
    case notAPDF
    case locked
    case noSuchPage(Int)
    case notAPicture
    case notDrawn
    /// The template's file is missing or is not a PDF with a page.
    case unreadableTemplate
    /// A notebook has 1 to 1,000 pages.
    case pageCountOutOfRange
}

/// Makes the one-page PDFs the person's own paper templates are kept as. A PDF page is
/// copied as it is, so its text and drawings stay vector and nothing is drawn into a bitmap; a
/// picture is placed on a page of its own with its JPEG or PNG data embedded unchanged.
public enum MyPaperTemplateBuilder {
    /// A picture's page is as long as an A4 page, in PDF points, along its longer side.
    public static let pictureLongerSidePoints = 841.89
    /// The quality a picture of a type PDF cannot hold (HEIC, TIFF, ...) is stored at, as JPEG.
    static let convertedPictureQuality = 0.92

    // MARK: A page of a PDF

    public static func pageCount(ofPDF pdfData: Data) throws -> Int {
        try openedDocument(pdfData).pageCount
    }

    /// A one-page PDF holding page `pageIndex` (from 0) of `pdfData`. Markup on the page (ink,
    /// notes, highlights) is left out: a template is paper, which every page of a new notebook
    /// carries and the person writes on.
    public static func templateData(fromPDF pdfData: Data, pageIndex: Int) throws -> Data {
        let document = try openedDocument(pdfData)
        guard pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex),
              let pageCopy = page.copy() as? PDFPage else { throw MyPaperTemplateError.noSuchPage(pageIndex) }
        for annotation in pageCopy.annotations { pageCopy.removeAnnotation(annotation) }
        let template = PDFDocument()
        template.insert(pageCopy, at: 0)
        guard let templateData = template.dataRepresentation() else { throw MyPaperTemplateError.notDrawn }
        return templateData
    }

    /// A picture of page `pageIndex`, for choosing it; nil when the page cannot be drawn.
    public static func previewImage(ofPDF pdfData: Data, pageIndex: Int, longerSidePixels: Int) -> CGImage? {
        let document = try? openedDocument(pdfData) // A file that cannot be opened has no picture.
        guard let document, pageIndex >= 0, pageIndex < document.pageCount, let page = document.page(at: pageIndex) else { return nil }
        return LibraryPreviewLoader.thumbnail(of: page, longerSidePixels: longerSidePixels)
    }

    /// A picture of a picture, for choosing it, with its orientation applied; nil when it cannot be read.
    public static func previewImage(ofPicture pictureData: Data, longerSidePixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(pictureData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: max(longerSidePixels, 1), kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func openedDocument(_ pdfData: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else { throw MyPaperTemplateError.notAPDF }
        guard !document.isLocked else { throw MyPaperTemplateError.locked }
        return document
    }

    // MARK: A picture

    /// A one-page PDF with the picture filling the page. The page is the picture's shape with
    /// a longer side of `pictureLongerSidePoints`; a picture's orientation is applied.
    public static func templateData(fromPicture pictureData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(pictureData as CFData, nil), CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source) as String?, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw MyPaperTemplateError.notAPicture
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        let embeddedImage = try embeddable(image, of: typeIdentifier)
        return try pdfData(drawing: embeddedImage, orientation: orientation)
    }

    /// JPEG and PNG go into a PDF as they are; any other type is stored as JPEG.
    private static func embeddable(_ image: CGImage, of typeIdentifier: String) throws -> CGImage {
        if typeIdentifier == UTType.jpeg.identifier || typeIdentifier == UTType.png.identifier { return image }
        let converted = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(converted, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw MyPaperTemplateError.notDrawn
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: convertedPictureQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let convertedSource = CGImageSourceCreateWithData(converted as CFData, nil),
              let convertedImage = CGImageSourceCreateImageAtIndex(convertedSource, 0, nil) else { throw MyPaperTemplateError.notDrawn }
        return convertedImage
    }

    private static func pdfData(drawing image: CGImage, orientation: CGImagePropertyOrientation) throws -> Data {
        let turnsSideways = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let pixelWidth = Double(image.width), pixelHeight = Double(image.height)
        let scale = pictureLongerSidePoints / max(pixelWidth, pixelHeight)
        let storedWidth = pixelWidth * scale, storedHeight = pixelHeight * scale
        var pageBox = CGRect(x: 0, y: 0, width: turnsSideways ? storedHeight : storedWidth, height: turnsSideways ? storedWidth : storedHeight)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &pageBox, nil) else {
            throw MyPaperTemplateError.notDrawn
        }
        context.beginPDFPage(nil)
        context.concatenate(upright(orientation, storedWidth: storedWidth, storedHeight: storedHeight))
        context.draw(image, in: CGRect(x: 0, y: 0, width: storedWidth, height: storedHeight))
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    /// The transform that turns a picture stored in `orientation` upright, in a drawing context
    /// whose origin is at the lower left and whose size is the picture as shown.
    static func upright(_ orientation: CGImagePropertyOrientation, storedWidth width: Double, storedHeight height: Double) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        switch orientation {
        case .down, .downMirrored: transform = transform.translatedBy(x: width, y: height).rotated(by: .pi)
        case .left, .leftMirrored: transform = transform.translatedBy(x: height, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored: transform = transform.translatedBy(x: 0, y: width).rotated(by: -.pi / 2)
        case .up, .upMirrored: break
        }
        switch orientation {
        case .upMirrored, .downMirrored: transform = transform.translatedBy(x: width, y: 0).scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored: transform = transform.translatedBy(x: height, y: 0).scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right: break
        }
        return transform
    }
}
