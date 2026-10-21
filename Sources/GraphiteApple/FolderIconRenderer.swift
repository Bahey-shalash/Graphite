import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore

/// Draws the pictures folders carry, with CoreGraphics only, so the same pixels come out on
/// iOS and the Mac: a picture decoded at a bounded size, drawn into a template of the icon
/// maker over Apple's folder art, and encoded as PNG for the vault.
public enum FolderIconRenderer {
    /// The stored picture's side in pixels: sharp at Finder's largest icon view and on the tile.
    public static let outputPixels = 512
    /// The largest picture decoded; a photo of the camera is scaled down while decoding.
    public static let maximumDecodedPixels = 2_048
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

    /// The whole icon as the design draws it, `pixels` wide: the folder art behind (for the
    /// folder templates), the picture clipped to the template's shape over its background,
    /// then the template's top layer.
    public static func icon(_ design: FolderIconDesign, picture: CGImage, folderArt: CGImage?, pixels: Int) -> CGImage? {
        guard let context = makeContext(pixels: pixels) else { return nil }
        let side = CGFloat(pixels)
        let template = design.template
        if template.isOnFolder, let folderArt {
            context.draw(folderArt, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        let unitFrame = template.pictureFrame
        // CoreGraphics counts up from the bottom; the template counts down from the top.
        let frame = CGRect(x: unitFrame.minX * side, y: (1 - unitFrame.maxY) * side, width: unitFrame.width * side, height: unitFrame.height * side)
        let shape = clipPath(template.clip, in: frame)
        if case .page = template.clip {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -side * 0.01), blur: side * 0.03, color: CGColor(gray: 0, alpha: 0.3))
            context.addPath(shape)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillPath()
            context.restoreGState()
        }
        drawPicture(picture, design: design, in: frame, clippedTo: shape, context: context)
        drawTopLayer(of: template, in: frame, side: side, context: context)
        return context.makeImage()
    }

    /// What is kept in the vault for a design: for Folder (Center) the framed picture alone,
    /// a square of `outputPixels` that the folder's art takes in its own color; otherwise the
    /// whole icon.
    public static func keptPicture(_ design: FolderIconDesign, picture: CGImage, folderArt: CGImage?) -> CGImage? {
        guard design.template.layout == .onFolder else { return icon(design, picture: picture, folderArt: folderArt, pixels: outputPixels) }
        guard let context = makeContext(pixels: outputPixels) else { return nil }
        let square = CGRect(x: 0, y: 0, width: outputPixels, height: outputPixels)
        drawPicture(picture, design: design, in: square, clippedTo: CGPath(rect: square, transform: nil), context: context)
        return context.makeImage()
    }

    private static func makeContext(pixels: Int) -> CGContext? {
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.interpolationQuality = .high
        return context
    }

    static func clipPath(_ clip: FolderIconTemplate.Clip, in frame: CGRect) -> CGPath {
        switch clip {
        case .roundedRectangle(let cornerFraction):
            let radius = min(frame.width * cornerFraction, frame.height / 2)
            return CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: frame, transform: nil)
        case .page(let foldFraction):
            let fold = frame.width * foldFraction
            let path = CGMutablePath()
            path.move(to: CGPoint(x: frame.minX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.maxX - fold, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - fold))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
            path.closeSubpath()
            return path
        }
    }

    /// The background, then the picture moved, zoomed and turned as the framing says.
    private static func drawPicture(_ picture: CGImage, design: FolderIconDesign, in frame: CGRect, clippedTo shape: CGPath, context: CGContext) {
        context.saveGState()
        context.addPath(shape)
        context.clip()
        if let background = design.effectiveBackground {
            context.setFillColor(CGColor(srgbRed: background.red, green: background.green, blue: background.blue, alpha: 1))
            context.fill(frame)
        }
        let topLeftRect = design.framing.drawingRect(pictureSize: CGSize(width: picture.width, height: picture.height), frameSize: frame.size)
        let center = CGPoint(x: frame.minX + topLeftRect.midX, y: frame.maxY - topLeftRect.midY)
        context.translateBy(x: center.x, y: center.y)
        // Clockwise on screen is a negative angle when y counts up.
        context.rotate(by: -design.framing.rotationDegrees * .pi / 180)
        context.draw(picture, in: CGRect(x: -topLeftRect.width / 2, y: -topLeftRect.height / 2, width: topLeftRect.width, height: topLeftRect.height))
        context.restoreGState()
    }

    /// A page's turned corner and edge; the folder's front face keeps a light top edge.
    private static func drawTopLayer(of template: FolderIconTemplate, in frame: CGRect, side: CGFloat, context: CGContext) {
        switch template.clip {
        case .page(let foldFraction):
            let fold = frame.width * foldFraction
            let corner = CGMutablePath()
            corner.move(to: CGPoint(x: frame.maxX - fold, y: frame.maxY))
            corner.addLine(to: CGPoint(x: frame.maxX - fold, y: frame.maxY - fold))
            corner.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - fold))
            corner.closeSubpath()
            context.saveGState()
            context.setShadow(offset: CGSize(width: -side * 0.004, height: -side * 0.004), blur: side * 0.01, color: CGColor(gray: 0, alpha: 0.25))
            context.addPath(corner)
            context.setFillColor(CGColor(gray: 0.88, alpha: 1))
            context.fillPath()
            context.restoreGState()
            context.addPath(clipPath(template.clip, in: frame))
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
            context.setLineWidth(max(side * 0.004, 1))
            context.strokePath()
        case .roundedRectangle where template == .folderFull:
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
            context.setLineWidth(max(side * 0.006, 1))
            context.move(to: CGPoint(x: frame.minX + frame.width * 0.06, y: frame.maxY - side * 0.003))
            context.addLine(to: CGPoint(x: frame.maxX - frame.width * 0.06, y: frame.maxY - side * 0.003))
            context.strokePath()
        case .roundedRectangle, .ellipse:
            return
        }
    }

    /// Where a picture placed on a folder sits on the system's folder icon, in fractions of
    /// the icon's side, as the Folder (Center) template places it.
    public static var pictureOnFolderSideFraction: CGFloat { FolderIconTemplate.folderCenter.pictureFrame.width }
    public static var pictureOnFolderCenterFromTopFraction: CGFloat { FolderIconTemplate.folderCenter.pictureFrame.midY }
    /// The rounding of a picture placed on a folder, in fractions of the picture's side.
    public static var pictureOnFolderCornerFraction: CGFloat {
        if case .roundedRectangle(let cornerFraction) = FolderIconTemplate.folderCenter.clip { cornerFraction } else { 0 }
    }

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
}
