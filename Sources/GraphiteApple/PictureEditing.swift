import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore

/// Turning and cropping a picture placed on a drawing or a PDF page. The picture's own
/// bytes change, so every reader shows the result without Graphite; the picture as it was
/// stays in the document's undo history. A photograph stays a JPEG and a picture with
/// transparency a PNG.
public enum PictureEditing {
    /// A cropped picture keeps at least this many pixels along each side.
    public static let minimumSidePixels = 8
    static let photographQuality = 0.92

    /// The picture turned a quarter turn clockwise.
    public static func rotatedClockwise(_ imageData: Data) throws -> Data {
        let picture = try decodedImage(imageData)
        guard let context = context(width: picture.height, height: picture.width, like: picture) else {
            throw GraphiteError.invalidFile("This image could not be turned.")
        }
        // Core Graphics counts up from the bottom: a clockwise turn on screen is a negative
        // angle here, about the new image's middle.
        context.translateBy(x: CGFloat(picture.height) / 2, y: CGFloat(picture.width) / 2)
        context.rotate(by: -.pi / 2)
        context.draw(picture, in: CGRect(x: -CGFloat(picture.width) / 2, y: -CGFloat(picture.height) / 2, width: CGFloat(picture.width), height: CGFloat(picture.height)))
        guard let turnedPicture = context.makeImage() else { throw GraphiteError.invalidFile("This image could not be turned.") }
        return try encode(turnedPicture, like: imageData)
    }

    /// The part of the picture inside `region`, given as fractions of the picture's width
    /// and height from its top-left corner.
    public static func cropped(_ imageData: Data, to region: CGRect) throws -> Data {
        let picture = try decodedImage(imageData)
        let unitRegion = region.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !unitRegion.isNull else { throw GraphiteError.invalidFile("Nothing of the image is inside the crop.") }
        let pixelRegion = CGRect(x: unitRegion.minX * CGFloat(picture.width), y: unitRegion.minY * CGFloat(picture.height),
                                 width: unitRegion.width * CGFloat(picture.width), height: unitRegion.height * CGFloat(picture.height)).integral
        guard pixelRegion.width >= CGFloat(minimumSidePixels), pixelRegion.height >= CGFloat(minimumSidePixels),
              let croppedPicture = picture.cropping(to: pixelRegion) else {
            throw GraphiteError.invalidFile("The crop is too small to keep.")
        }
        return try encode(croppedPicture, like: imageData)
    }

    /// The region of a picture's own image, as fractions from its top-left corner, that is
    /// shown as `displayedRegion` of the picture turned `quarterTurnsClockwise` on screen.
    public static func imageRegion(forDisplayedRegion displayedRegion: CGRect, turnedClockwise quarterTurnsClockwise: Int) -> CGRect {
        let region = displayedRegion.standardized
        switch ((quarterTurnsClockwise % 4) + 4) % 4 {
        case 1: return CGRect(x: region.minY, y: 1 - region.maxX, width: region.height, height: region.width)
        case 2: return CGRect(x: 1 - region.maxX, y: 1 - region.maxY, width: region.width, height: region.height)
        case 3: return CGRect(x: 1 - region.maxY, y: region.minX, width: region.height, height: region.width)
        default: return region
        }
    }

    private static func decodedImage(_ imageData: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0, let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw GraphiteError.invalidFile("This image could not be read.")
        }
        return picture
    }

    private static func context(width: Int, height: Int, like picture: CGImage) -> CGContext? {
        let colorSpace = picture.colorSpace.flatMap { colorSpace in colorSpace.model == .rgb ? colorSpace : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace else { return nil }
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.interpolationQuality = .high
        return context
    }

    /// A JPEG stays a JPEG; anything else becomes a PNG, which keeps transparency.
    private static func encode(_ picture: CGImage, like original: Data) throws -> Data {
        let isPhotograph = original.starts(with: [0xFF, 0xD8])
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, (isPhotograph ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil) else {
            throw GraphiteError.invalidFile("Cannot prepare the image.")
        }
        let options = isPhotograph ? [kCGImageDestinationLossyCompressionQuality: photographQuality] as CFDictionary : nil
        CGImageDestinationAddImage(destination, picture, options)
        guard CGImageDestinationFinalize(destination) else { throw GraphiteError.invalidFile("Cannot prepare the image.") }
        return output as Data
    }
}
