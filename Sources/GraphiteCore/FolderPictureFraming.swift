import CoreGraphics

/// How a picture sits in a square frame, as the icon maker moves and zooms it: at zoom 1 it
/// fills the frame (cropping the longer side), larger zooms in, smaller leaves background
/// around it. The offset is in frame widths, so the framing is the same at every size.
public struct FolderPictureFraming: Equatable, Sendable {
    public static let minimumZoom = 0.5
    public static let maximumZoom = 5.0
    public static let filling = FolderPictureFraming(zoom: 1, horizontalOffset: 0, verticalOffset: 0)

    public var zoom: Double
    /// From the frame's middle, in frame widths; positive is right and down.
    public var horizontalOffset: Double
    public var verticalOffset: Double

    public init(zoom: Double, horizontalOffset: Double, verticalOffset: Double) {
        self.zoom = min(max(zoom, Self.minimumZoom), Self.maximumZoom)
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
    }

    /// Where the whole picture is drawn in a frame of `frameSide` with its origin at the top
    /// left: scaled to fill the frame times the zoom, centred, then moved by the offset.
    public func drawingRect(pictureSize: CGSize, frameSide: CGFloat) -> CGRect {
        guard pictureSize.width > 0, pictureSize.height > 0 else { return .zero }
        let fillingScale = max(frameSide / pictureSize.width, frameSide / pictureSize.height)
        let scale = fillingScale * zoom
        let size = CGSize(width: pictureSize.width * scale, height: pictureSize.height * scale)
        let center = CGPoint(x: frameSide / 2 + horizontalOffset * frameSide, y: frameSide / 2 + verticalOffset * frameSide)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}
