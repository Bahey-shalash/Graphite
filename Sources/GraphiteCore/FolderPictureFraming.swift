import CoreGraphics

/// How a picture sits in its frame, as the icon maker moves, zooms and turns it: at zoom 1 it
/// fills the frame (cropping the longer side), larger zooms in, smaller leaves background
/// around it. Offsets are in frame widths and heights, so the framing is the same at every size.
public struct FolderPictureFraming: Equatable, Hashable, Sendable {
    public static let minimumZoom = 0.25
    public static let maximumZoom = 5.0
    /// The farthest a picture moves from the middle, in frame sizes.
    public static let maximumOffset = 1.0
    public static let filling = FolderPictureFraming(zoom: 1, horizontalOffset: 0, verticalOffset: 0)

    public var zoom: Double { didSet { zoom = Self.clamped(zoom, Self.minimumZoom, Self.maximumZoom) } }
    /// From the frame's middle, in frame widths; positive is right.
    public var horizontalOffset: Double { didSet { horizontalOffset = Self.clamped(horizontalOffset, -Self.maximumOffset, Self.maximumOffset) } }
    /// From the frame's middle, in frame heights; positive is down.
    public var verticalOffset: Double { didSet { verticalOffset = Self.clamped(verticalOffset, -Self.maximumOffset, Self.maximumOffset) } }
    /// Clockwise, in degrees, about the picture's middle.
    public var rotationDegrees: Double

    public init(zoom: Double, horizontalOffset: Double, verticalOffset: Double, rotationDegrees: Double = 0) {
        self.zoom = Self.clamped(zoom, Self.minimumZoom, Self.maximumZoom)
        self.horizontalOffset = Self.clamped(horizontalOffset, -Self.maximumOffset, Self.maximumOffset)
        self.verticalOffset = Self.clamped(verticalOffset, -Self.maximumOffset, Self.maximumOffset)
        self.rotationDegrees = rotationDegrees
    }

    /// Where the whole picture is drawn, before it is turned, in a frame of `frameSize` with
    /// its origin at the top left: scaled to fill the frame times the zoom, centred, then moved.
    public func drawingRect(pictureSize: CGSize, frameSize: CGSize) -> CGRect {
        guard pictureSize.width > 0, pictureSize.height > 0 else { return .zero }
        let fillingScale = max(frameSize.width / pictureSize.width, frameSize.height / pictureSize.height)
        let scale = fillingScale * zoom
        let size = CGSize(width: pictureSize.width * scale, height: pictureSize.height * scale)
        let center = CGPoint(x: frameSize.width / 2 + horizontalOffset * frameSize.width, y: frameSize.height / 2 + verticalOffset * frameSize.height)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// The framing after a drag of `translation` points over a frame of `frameSize` points.
    public func moved(by translation: CGSize, frameSize: CGSize) -> FolderPictureFraming {
        guard frameSize.width > 0, frameSize.height > 0 else { return self }
        var moved = self
        moved.horizontalOffset += translation.width / frameSize.width
        moved.verticalOffset += translation.height / frameSize.height
        return moved
    }

    private static func clamped(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}
