import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// What a picture chosen or taken becomes as a file in the vault: JPEG, PNG and GIF are kept as
/// they are, anything else (HEIC from the photo library, TIFF) is stored as JPEG, which Obsidian
/// and every other app can show.
public enum PictureFileEncoding {
    public static let convertedQuality = 0.92

    /// The data and file extension to save `pictureData` under; nil when it is not a picture.
    public static func fileContents(of pictureData: Data) -> (data: Data, fileExtension: String)? {
        guard let source = CGImageSourceCreateWithData(pictureData as CFData, nil), CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source) as String? else { return nil }
        switch typeIdentifier {
        case UTType.jpeg.identifier: return (pictureData, "jpg")
        case UTType.png.identifier: return (pictureData, "png")
        case UTType.gif.identifier: return (pictureData, "gif")
        default: return jpegContents(of: source).map { converted in (converted, "jpg") }
        }
    }

    /// The picture of a camera, as JPEG.
    public static func jpegData(of image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: convertedQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// The first image of the source as JPEG, with its orientation kept as metadata.
    private static func jpegContents(of source: CGImageSource) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImageDestinationLossyCompressionQuality: convertedQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
