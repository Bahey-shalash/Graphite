import Foundation
import CoreGraphics

/// PDFKit rotates its page overlay itself. Map its unrotated, top-left local
/// coordinate system into the bottom-left PDF crop box exactly once.
public struct PageCoordinates: Sendable {
    public let cropBox: CGRect
    public let overlaySize: CGSize
    public init(cropBox: CGRect, overlaySize: CGSize) throws {
        guard cropBox.width > 0, cropBox.height > 0, overlaySize.width > 0, overlaySize.height > 0,
              [cropBox.minX, cropBox.minY, cropBox.width, cropBox.height, overlaySize.width, overlaySize.height].allSatisfy(\.isFinite)
        else { throw GraphiteError.invalidFile("Invalid page geometry.") }
        self.cropBox = cropBox; self.overlaySize = overlaySize
    }
    public func pdfPoint(fromOverlay point: CGPoint) -> CGPoint {
        CGPoint(x: cropBox.minX + point.x * cropBox.width / overlaySize.width,
                y: cropBox.maxY - point.y * cropBox.height / overlaySize.height)
    }
    public func overlayPoint(fromPDF point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - cropBox.minX) * overlaySize.width / cropBox.width,
                y: (cropBox.maxY - point.y) * overlaySize.height / cropBox.height)
    }
}
