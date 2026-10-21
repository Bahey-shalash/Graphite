import CoreGraphics
import Foundation

/// A picture of the note (`ImageMediaObject`). The export draws the whole image at `unitsPerImagePixel` with its top
/// left at `origin`, clipped to `cropRectangle`, turned about the picture's center, and under all ink.
public struct NotabilityPicture: Sendable, Equatable {
    /// The image file, relative to the note's folder, such as `Images/Image 1.jpg`.
    public let file: NotebookArchivePath
    /// The top-left corner of the unturned picture, in document units.
    public let origin: CGPoint
    /// The size on the page of the shown (cropped) part, in document units.
    public let size: CGSize
    /// Radians, clockwise on the page, about the picture's center (stored as `rotationDegrees`).
    public let rotationRadiansClockwise: Double
    /// The order among the pictures, from 0.
    public let zIndex: Int
    /// The part of the image shown, in the image's pixels from its top left.
    public let cropRectangle: CGRect
    public let isFlippedHorizontally: Bool
    public let isFlippedVertically: Bool

    public init(file: NotebookArchivePath, origin: CGPoint, size: CGSize, rotationRadiansClockwise: Double, zIndex: Int, cropRectangle: CGRect,
                isFlippedHorizontally: Bool, isFlippedVertically: Bool) {
        self.file = file
        self.origin = origin
        self.size = size
        self.rotationRadiansClockwise = rotationRadiansClockwise
        self.zIndex = zIndex
        self.cropRectangle = cropRectangle
        self.isFlippedHorizontally = isFlippedHorizontally
        self.isFlippedVertically = isFlippedVertically
    }

    /// Document units per image pixel: the shown width over the crop's width (the reader refuses a crop of no width).
    public var unitsPerImagePixel: Double { Double(size.width / cropRectangle.width) }
}
