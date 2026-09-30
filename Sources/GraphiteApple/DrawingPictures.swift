import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore

/// Prepares an image file to be drawn on: the picture is decoded with its orientation
/// applied, reduced to the sharpness a saved drawing has (twice the canvas width in
/// pixels), and placed at the full canvas width. The original file is only read.
public enum DrawingPictures {
    /// Pixels kept per point of canvas, the scale of a saved PNG drawing.
    static let pixelsPerPoint = DrawingLimits.preferredPNGScale
    /// JPEG quality for opaque pictures; photos keep their detail at a fraction of PNG's size.
    static let photographQuality = 0.9

    public static func picture(from imageData: Data, canvasWidth: Double) throws -> DrawingBackgroundImage {
        guard canvasWidth.isFinite, canvasWidth > 0,
              let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int, let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              storedWidth > 0, storedHeight > 0 else {
            throw GraphiteError.invalidFile("Graphite cannot draw on this kind of image.")
        }
        // EXIF orientations 5 to 8 turn the picture a quarter turn.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let isTurned = (5...8).contains(orientation)
        let displayedWidth = Double(isTurned ? storedHeight : storedWidth)
        let displayedHeight = Double(isTurned ? storedWidth : storedHeight)
        let frameHeight = canvasWidth * displayedHeight / displayedWidth
        guard frameHeight <= DrawingLimits.maximumCanvasHeight else {
            throw GraphiteError.oversized("This image is too tall to draw on.")
        }
        let longestStoredSide = max(storedWidth, storedHeight)
        let longestKeptSide = min(longestStoredSide, Int((max(canvasWidth, frameHeight) * pixelsPerPoint).rounded(.up)))
        guard let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestKeptSide,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else {
            throw GraphiteError.invalidFile("This image could not be read.")
        }
        let encodedPicture = try encode(picture)
        guard encodedPicture.count <= DrawingLimits.maximumBackgroundImageBytes else {
            throw GraphiteError.oversized("This image is too large to draw on.")
        }
        return DrawingBackgroundImage(imageData: encodedPicture, frame: CGRect(x: 0, y: 0, width: canvasWidth, height: frameHeight))
    }

    /// JPEG for opaque pictures, PNG for pictures with transparency.
    private static func encode(_ picture: CGImage) throws -> Data {
        let hasTransparency = ![CGImageAlphaInfo.none, .noneSkipFirst, .noneSkipLast].contains(picture.alphaInfo)
        let type = hasTransparency ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw GraphiteError.invalidFile("Cannot prepare the image.")
        }
        let options = hasTransparency ? nil : [kCGImageDestinationLossyCompressionQuality: photographQuality] as CFDictionary
        CGImageDestinationAddImage(destination, picture, options)
        guard CGImageDestinationFinalize(destination) else { throw GraphiteError.invalidFile("Cannot prepare the image.") }
        return output as Data
    }
}
