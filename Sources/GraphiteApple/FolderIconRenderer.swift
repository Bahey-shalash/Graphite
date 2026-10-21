import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore

/// What fills a folder icon's square around and behind the picture.
public enum FolderIconBackground: Equatable, Hashable, Sendable {
    /// Transparent: a picture with a transparent background keeps its own shape.
    case none
    case white
    case black
    case color(red: UInt8, green: UInt8, blue: UInt8)
}

/// Draws the pictures folders carry, with CoreGraphics only, so the same pixels come out on
/// iOS and the Mac: a picture decoded at a bounded size, framed into a square as the icon
/// maker shows it, and encoded as PNG for the vault.
public enum FolderIconRenderer {
    /// The stored picture's side in pixels: sharp at Finder's largest icon view and on the tile.
    public static let outputPixels = 512
    /// The largest picture decoded; a photo of the camera is scaled down while decoding.
    public static let maximumDecodedPixels = 2_048
    /// The share of a whole icon's side its rounded corners take, as macOS app icons have.
    public static let wholeIconCornerFraction: CGFloat = 0.2237

    /// A picture's pixels from a file's bytes, scaled down while decoding and turned upright.
    public static func decodedPicture(from imageData: Data, maximumPixels: Int = maximumDecodedPixels) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The picture framed into a square of `outputPixels`: the background, then the picture.
    /// A whole icon with a background gets rounded corners; the picture placed on a folder is
    /// kept square, and rounded where it is drawn on the folder.
    public static func framedPicture(_ picture: CGImage, framing: FolderPictureFraming, layout: FolderPictureLayout,
                                     background: FolderIconBackground) -> CGImage? {
        let side = CGFloat(outputPixels)
        guard let context = CGContext(data: nil, width: outputPixels, height: outputPixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let square = CGRect(x: 0, y: 0, width: side, height: side)
        if layout == .wholeIcon, background != .none {
            let radius = side * wholeIconCornerFraction
            context.addPath(CGPath(roundedRect: square, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
        }
        if let backgroundColor = cgColor(of: background) {
            context.setFillColor(backgroundColor)
            context.fill(square)
        }
        let pictureSize = CGSize(width: picture.width, height: picture.height)
        let topLeftRect = framing.drawingRect(pictureSize: pictureSize, frameSide: side)
        // CoreGraphics counts up from the bottom; the framing counts down from the top.
        let drawingRect = CGRect(x: topLeftRect.minX, y: side - topLeftRect.maxY, width: topLeftRect.width, height: topLeftRect.height)
        context.interpolationQuality = .high
        context.draw(picture, in: drawingRect)
        return context.makeImage()
    }

    /// Where a picture placed on a folder sits on the system's folder icon, in fractions of
    /// the icon's side: the middle of the folder's body, below its tab, as Finder draws app folders.
    public static let pictureOnFolderSideFraction: CGFloat = 0.42
    public static let pictureOnFolderCenterFromTopFraction: CGFloat = 0.57
    /// The rounding of a picture placed on a folder, in fractions of the picture's side.
    public static let pictureOnFolderCornerFraction: CGFloat = 0.18

    /// The folder's whole icon for Finder: the picture alone, or the picture rounded on the
    /// system's folder, `folderIcon`, drawn at the same size.
    public static func finderIcon(picture: CGImage, layout: FolderPictureLayout, folderIcon: CGImage?) -> CGImage? {
        guard layout != .wholeIcon, let folderIcon else { return picture }
        let side = CGFloat(folderIcon.width)
        guard let context = CGContext(data: nil, width: folderIcon.width, height: folderIcon.width, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(folderIcon, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pictureSide = side * pictureOnFolderSideFraction
        // CoreGraphics counts up from the bottom.
        let pictureRect = CGRect(x: (side - pictureSide) / 2, y: side * (1 - pictureOnFolderCenterFromTopFraction) - pictureSide / 2,
                                 width: pictureSide, height: pictureSide)
        let radius = pictureSide * pictureOnFolderCornerFraction
        context.addPath(CGPath(roundedRect: pictureRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.interpolationQuality = .high
        context.draw(picture, in: pictureRect)
        return context.makeImage()
    }

    /// Why a folder's picture was not made.
    public enum Failure: Error, Equatable {
        case notEncoded
    }

    public static func pngData(of image: CGImage) throws -> Data {
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else { throw Failure.notEncoded }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.notEncoded }
        return encoded as Data
    }

    static func cgColor(of background: FolderIconBackground) -> CGColor? {
        switch background {
        case .none: nil
        case .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case .black: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        case .color(let red, let green, let blue): CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        }
    }
}
