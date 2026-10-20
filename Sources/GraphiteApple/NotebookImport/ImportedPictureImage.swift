import Foundation
import CoreGraphics
import ImageIO
import GraphiteCore

/// The PNG or JPEG bytes a `PDFPicture` holds for an imported picture: the shown part of its file, flipped as planned.
///
/// A PNG or JPEG file that is upright as stored, needs no crop or flip, and fits `PDFPicture`'s limits is kept byte for
/// byte. Any other is decoded upright (its EXIF orientation applied) and at most `maximumSidePixels` along its longer
/// side, so one picture's bitmap stays bounded, then drawn cropped and flipped into a new bitmap and encoded: as JPEG
/// when the file was a JPEG and the crop stays inside it, as PNG otherwise, which keeps transparency and the clear
/// margin of a crop that reaches past the image. An animated GIF becomes its first frame. A crop is in the pixels of
/// the image as shown and is stretched to fill the new bitmap exactly, so a crop of fractional pixels keeps its size.
enum ImportedPictureImage {
    enum Failure: Error, Equatable {
        /// ImageIO does not decode the file, or the picture could not be drawn and encoded again.
        case notDecodable
        case cropUnusable
        /// The smallest encoding tried, in bytes.
        case tooLarge(byteCount: Int)
    }

    /// The longest side, in pixels, of a picture as decoded and as placed: a full page at about 7 pixels per point.
    static let maximumSidePixels = 4096
    static let photographQuality = 0.92
    /// A crop this close to the whole image, in pixels, along each edge, is the whole image.
    static let wholeImageTolerancePixels = 0.5
    /// How many smaller encodings are tried before a picture is refused as too large.
    static let maximumEncodingAttempts = 4
    /// ImageIO's names of the two formats a `PDFPicture` holds (`UTType.jpeg` and `UTType.png`).
    private static let jpegTypeIdentifier = "public.jpeg"
    private static let pngTypeIdentifier = "public.png"

    private enum FileFormat { case jpeg, png, other }

    /// A file's first image, decoded upright and perhaps reduced.
    private struct ShownImage {
        let image: CGImage
        let fileFormat: FileFormat
        /// The image as shown, before it is reduced, in the file's pixels.
        let shownSize: CGSize
    }

    static func imageData(fromFile fileBytes: Data, for picture: ImportedPicture) throws(Failure) -> Data {
        guard let source = CGImageSourceCreateWithData(fileBytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int, let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              storedWidth > 0, storedHeight > 0 else { throw .notDecodable }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // EXIF orientations 5 to 8 turn the image a quarter turn.
        let isQuarterTurned = (5...8).contains(orientation)
        let shownSize = CGSize(width: isQuarterTurned ? storedHeight : storedWidth, height: isQuarterTurned ? storedWidth : storedHeight)
        let crop = try shownCrop(picture.cropRectangleInPixels, shownSize: shownSize)
        let fileFormat = fileFormat(of: fileBytes)
        if crop == nil, !picture.isFlippedHorizontally, !picture.isFlippedVertically, orientation == 1, fileFormat != .other,
           max(storedWidth, storedHeight) <= maximumSidePixels, fileBytes.count <= PDFPicture.maximumImageBytes {
            return fileBytes
        }
        guard let image = decodedUpright(source, longestShownSide: max(storedWidth, storedHeight)) else { throw .notDecodable }
        return try encoded(ShownImage(image: image, fileFormat: fileFormat, shownSize: shownSize),
                           crop: crop ?? CGRect(origin: .zero, size: shownSize), picture: picture)
    }

    /// The crop in the image's shown pixels, or nil when it shows the whole image.
    private static func shownCrop(_ cropRectangle: CGRect?, shownSize: CGSize) throws(Failure) -> CGRect? {
        guard let cropRectangle else { return nil }
        let crop = cropRectangle.standardized
        guard [crop.minX, crop.minY, crop.width, crop.height].allSatisfy(\.isFinite), crop.width > 0, crop.height > 0 else { throw .cropUnusable }
        let tolerance = wholeImageTolerancePixels
        let isWholeImage = abs(crop.minX) <= tolerance && abs(crop.minY) <= tolerance
            && abs(crop.width - shownSize.width) <= tolerance && abs(crop.height - shownSize.height) <= tolerance
        return isWholeImage ? nil : crop
    }

    private static func fileFormat(of fileBytes: Data) -> FileFormat {
        if fileBytes.starts(with: [0xFF, 0xD8]) { return .jpeg }
        if fileBytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        return .other
    }

    /// The first image of the file, upright, at most `maximumSidePixels` along its longer side.
    private static func decodedUpright(_ source: CGImageSource, longestShownSide: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longestShownSide, maximumSidePixels),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    /// The crop drawn into a bitmap of its size in decoded pixels (at most `maximumSidePixels`), encoded, and made
    /// smaller until it fits `PDFPicture.maximumImageBytes`.
    private static func encoded(_ shownImage: ShownImage, crop: CGRect, picture: ImportedPicture) throws(Failure) -> Data {
        let decodedScale = Double(shownImage.image.width) / Double(shownImage.shownSize.width)
        var outputScale = min(decodedScale, Double(maximumSidePixels) / Double(max(crop.width, crop.height)))
        let isInsideImage = CGRect(origin: .zero, size: shownImage.shownSize).insetBy(dx: -wholeImageTolerancePixels, dy: -wholeImageTolerancePixels)
            .contains(crop)
        let encodesAsJPEG = shownImage.fileFormat == .jpeg && isInsideImage
        var smallestByteCount = Int.max
        for _ in 0..<maximumEncodingAttempts {
            let pixelWidth = max(1, Int((crop.width * outputScale).rounded())), pixelHeight = max(1, Int((crop.height * outputScale).rounded()))
            guard let drawnImage = drawn(shownImage, crop: crop, pixelWidth: pixelWidth, pixelHeight: pixelHeight, picture: picture),
                  let imageData = encodedData(drawnImage, asJPEG: encodesAsJPEG) else { throw .notDecodable }
            if imageData.count <= PDFPicture.maximumImageBytes { return imageData }
            smallestByteCount = min(smallestByteCount, imageData.count)
            // Bytes grow with the pixel count: shrink both sides by the square root of the excess, with room to spare.
            outputScale *= 0.9 * (Double(PDFPicture.maximumImageBytes) / Double(imageData.count)).squareRoot()
        }
        throw .tooLarge(byteCount: smallestByteCount)
    }

    /// The crop of the image, stretched to the bitmap's size and flipped as planned.
    private static func drawn(_ shownImage: ShownImage, crop: CGRect, pixelWidth: Int, pixelHeight: Int, picture: ImportedPicture) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let width = CGFloat(pixelWidth), height = CGFloat(pixelHeight)
        if picture.isFlippedHorizontally {
            context.translateBy(x: width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        if picture.isFlippedVertically {
            context.translateBy(x: 0, y: height)
            context.scaleBy(x: 1, y: -1)
        }
        // From here on the units are the file's shown pixels, from the crop's bottom-left corner: Core Graphics counts
        // up, so the image's top edge, `crop.minY` above the crop's top edge, is at `crop.height + crop.minY`.
        context.scaleBy(x: width / crop.width, y: height / crop.height)
        let imageSize = shownImage.shownSize
        context.draw(shownImage.image, in: CGRect(x: -crop.minX, y: crop.height + crop.minY - imageSize.height, width: imageSize.width,
                                                  height: imageSize.height))
        return context.makeImage()
    }

    private static func encodedData(_ image: CGImage, asJPEG: Bool) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, (asJPEG ? jpegTypeIdentifier : pngTypeIdentifier) as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, asJPEG ? [kCGImageDestinationLossyCompressionQuality: photographQuality] as CFDictionary : nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
