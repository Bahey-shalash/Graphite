import Foundation
import CoreGraphics

/// The ordinary file format a Pencil drawing is saved as. Every format stores complete
/// visible content; the embedded stroke data only adds re-editing in Graphite.
public enum DrawingFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case png, pdf, svg
    public var id: String { rawValue }
    public var fileExtension: String { rawValue }

    public init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }
}

public enum DrawingBackground: String, CaseIterable, Codable, Sendable, Identifiable {
    case white, transparent
    public var id: String { rawValue }
}

/// The paper a drawing is made on: a guide of squares, lines or dots under the ink.
public enum DrawingPaperPattern: String, CaseIterable, Codable, Sendable, Identifiable {
    case plain, squared, ruled, dotted
    public var id: String { rawValue }
}

/// A drawing's paper, and whether the pattern is only a guide while drawing or part of the
/// saved drawing, which notes and other applications then show.
public struct DrawingPaper: Sendable, Equatable {
    public var pattern: DrawingPaperPattern
    public var appearsInSavedDrawing: Bool

    public init(pattern: DrawingPaperPattern, appearsInSavedDrawing: Bool) {
        self.pattern = pattern
        self.appearsInSavedDrawing = appearsInSavedDrawing
    }

    public static let plain = DrawingPaper(pattern: .plain, appearsInSavedDrawing: false)

    /// Whether the saved file shows a pattern at all.
    public var isVisibleInSavedDrawing: Bool { appearsInSavedDrawing && pattern != .plain }
}

/// Where a paper pattern's lines and dots are, in drawing points. The pattern starts at the
/// drawing's origin, and a saved drawing starts on a line of its pattern, so the pattern
/// stays in step with the ink when the drawing is opened again.
public enum DrawingPaperGeometry {
    /// The side of a square, and the distance between dots.
    public static let squareSize = 24.0
    /// The distance between ruled lines, for handwriting at the zoom a note is drawn at.
    public static let ruledLineSpacing = 32.0
    public static let lineWidth = 1.0
    public static let dotDiameter = 3.0

    /// The distance between a pattern's lines; nil for plain paper.
    public static func spacing(of pattern: DrawingPaperPattern) -> Double? {
        switch pattern {
        case .plain: nil
        case .squared, .dotted: squareSize
        case .ruled: ruledLineSpacing
        }
    }

    /// The positions of the pattern's lines that cross `region`: the vertical coordinates of
    /// horizontal lines and the horizontal coordinates of vertical lines. Dots are where a
    /// dotted pattern's two sets cross.
    public static func linePositions(of pattern: DrawingPaperPattern, in region: CGRect) -> (horizontal: [Double], vertical: [Double]) {
        guard let spacing = spacing(of: pattern), region.width > 0, region.height > 0,
              region.minX.isFinite, region.minY.isFinite, region.maxX.isFinite, region.maxY.isFinite else { return ([], []) }
        func positions(from minimum: Double, to maximum: Double) -> [Double] {
            let firstIndex = Int((minimum / spacing).rounded(.up)), lastIndex = Int((maximum / spacing).rounded(.down))
            guard lastIndex >= firstIndex else { return [] }
            return (firstIndex...lastIndex).map { lineIndex in Double(lineIndex) * spacing }
        }
        let horizontal = positions(from: region.minY, to: region.maxY)
        return (horizontal, pattern == .ruled ? [] : positions(from: region.minX, to: region.maxX))
    }

    /// `coordinate` moved back to the pattern line at or before it.
    public static func snappedToLine(_ coordinate: Double, of pattern: DrawingPaperPattern) -> Double {
        guard let spacing = spacing(of: pattern) else { return coordinate }
        return (coordinate / spacing).rounded(.down) * spacing
    }
}

public enum DrawingLimits {
    /// Bound on untrusted PencilKit data before decoding it.
    public static let maximumStrokeBytes = 32 * 1_048_576
    /// Bound on the encoded metadata record that wraps the stroke data and the pictures.
    /// Every reader of a drawing may hold this much, so pictures share it with the strokes
    /// rather than raising it.
    public static let maximumPayloadBytes = 34 * 1_048_576
    public static let maximumCanvasWidth = 8_192.0
    public static let maximumCanvasHeight = 65_536.0
    /// Raster budget for PNG export (48 megapixels, about 192 MB of RGBA pixels).
    public static let maximumPNGPixelCount = 48_000_000.0
    public static let preferredPNGScale = 2.0
    /// Below this scale handwriting becomes blurry, so a vector format is required instead.
    public static let minimumPNGScale = 1.0
    /// Space kept around the ink when a drawing is cropped for embedding.
    public static let exportMargin = 24.0
    public static let minimumExportHeight = 96.0
    /// Bound on the pictures kept in a drawing's metadata, together: the picture of a
    /// drawing made on an image and the pictures placed on a drawing. Each is stored no
    /// sharper than the drawing is saved, which stays far below this.
    public static let maximumBackgroundImageBytes = 16 * 1_048_576
    /// Bound on the pictures placed on one drawing.
    public static let maximumPictureCount = 32
}

/// The picture under the ink of a drawing made on an image. It is drawn into the saved
/// file's visible content, and kept in the editing metadata so the ink can be edited again
/// over the same picture, even after the original image is moved, changed, or deleted.
public struct DrawingBackgroundImage: Sendable, Equatable {
    /// PNG or JPEG data with any orientation already applied.
    public let imageData: Data
    /// Where the picture is drawn, in the drawing's coordinates.
    public let frame: CGRect

    public init(imageData: Data, frame: CGRect) {
        self.imageData = imageData
        self.frame = frame
    }

    public var hasValidGeometry: Bool {
        !imageData.isEmpty && imageData.count <= DrawingLimits.maximumBackgroundImageBytes
            && frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
            && frame.width <= DrawingLimits.maximumCanvasWidth && frame.height <= DrawingLimits.maximumCanvasHeight
    }

    public func offsetBy(dx: Double, dy: Double) -> DrawingBackgroundImage {
        DrawingBackgroundImage(imageData: imageData, frame: frame.offsetBy(dx: dx, dy: dy))
    }
}

/// Editable drawing metadata embedded in PNG, SVG, and PDF drawings. Version 1 is the
/// original PNG `grPK` record; its field names are part of the stored format. Version 2
/// adds the picture of a drawing made on an image. Version 3 adds pictures placed on the
/// drawing and a paper pattern that is part of the saved drawing. A build that does not
/// know a version treats the file as an ordinary image, so it never saves the ink without
/// what was under it. A paper pattern that is only a guide while drawing does not raise the
/// version: a build that does not know it loses the guide and nothing visible.
public struct DrawingPayload: Codable, Sendable, Equatable {
    public let version: Int
    public let width: Double
    public let height: Double
    public let background: DrawingBackground
    public let strokes: Data
    /// Digest of the visible content this metadata was written with. Another application
    /// that changes the visible drawing makes the metadata stale, so it is ignored.
    public let visibleContentDigest: Data
    private let backgroundImageData: Data?
    private let backgroundImageFrame: CGRect?
    private let pictureData: [Data]?
    private let pictureFrames: [CGRect]?
    private let paperPattern: DrawingPaperPattern?
    private let paperAppearsInSavedDrawing: Bool?

    private enum CodingKeys: String, CodingKey {
        case version, width, height, background, strokes
        case visibleContentDigest = "pixelDigest"
        case backgroundImageData = "backgroundImage"
        case backgroundImageFrame
        case pictureData = "pictures"
        case pictureFrames
        case paperPattern
        case paperAppearsInSavedDrawing = "paperIsVisible"
    }

    public init(width: Double, height: Double, background: DrawingBackground, strokes: Data, visibleContentDigest: Data = Data(),
                backgroundImage: DrawingBackgroundImage? = nil, pictures: [DrawingBackgroundImage] = [], paper: DrawingPaper = .plain) {
        version = !pictures.isEmpty || paper.isVisibleInSavedDrawing ? 3 : backgroundImage == nil ? 1 : 2
        self.width = width
        self.height = height
        self.background = background
        self.strokes = strokes
        self.visibleContentDigest = visibleContentDigest
        backgroundImageData = backgroundImage?.imageData
        backgroundImageFrame = backgroundImage?.frame
        pictureData = pictures.isEmpty ? nil : pictures.map(\.imageData)
        pictureFrames = pictures.isEmpty ? nil : pictures.map(\.frame)
        paperPattern = paper.pattern == .plain ? nil : paper.pattern
        paperAppearsInSavedDrawing = paper.isVisibleInSavedDrawing ? true : nil
    }

    /// The picture under the ink, for a drawing made on an image.
    public var backgroundImage: DrawingBackgroundImage? {
        guard let backgroundImageData, let backgroundImageFrame else { return nil }
        return DrawingBackgroundImage(imageData: backgroundImageData, frame: backgroundImageFrame)
    }

    /// The pictures placed on the drawing, the lowest first.
    public var pictures: [DrawingBackgroundImage] {
        guard let pictureData, let pictureFrames, pictureData.count == pictureFrames.count else { return [] }
        return zip(pictureData, pictureFrames).map { imageData, frame in DrawingBackgroundImage(imageData: imageData, frame: frame) }
    }

    public var paper: DrawingPaper {
        DrawingPaper(pattern: paperPattern ?? .plain, appearsInSavedDrawing: paperAppearsInSavedDrawing ?? false)
    }

    public func replacingVisibleContentDigest(_ digest: Data) -> DrawingPayload {
        DrawingPayload(width: width, height: height, background: background, strokes: strokes, visibleContentDigest: digest,
                       backgroundImage: backgroundImage, pictures: pictures, paper: paper)
    }

    public var hasValidGeometry: Bool {
        let hasBackgroundImageFields = backgroundImageData != nil || backgroundImageFrame != nil
        let hasValidBackgroundImage = !hasBackgroundImageFields || backgroundImage?.hasValidGeometry == true
        let hasPictureFields = pictureData != nil || pictureFrames != nil
        let storedPictures = pictures
        let hasValidPictures = !hasPictureFields
            || (!storedPictures.isEmpty && storedPictures.count == pictureData?.count && storedPictures.count <= DrawingLimits.maximumPictureCount
                && storedPictures.allSatisfy(\.hasValidGeometry))
        let pictureBytes = (backgroundImageData?.count ?? 0) + (pictureData ?? []).reduce(0) { total, imageData in total + imageData.count }
        let hasContentOfItsVersion: Bool
        switch version {
        case 1: hasContentOfItsVersion = !hasBackgroundImageFields && !hasPictureFields && paperAppearsInSavedDrawing != true
        case 2: hasContentOfItsVersion = hasBackgroundImageFields && !hasPictureFields && paperAppearsInSavedDrawing != true
        case 3: hasContentOfItsVersion = hasPictureFields || paper.isVisibleInSavedDrawing
        default: hasContentOfItsVersion = false
        }
        return width.isFinite && height.isFinite && width > 0 && height > 0
            && width <= DrawingLimits.maximumCanvasWidth && height <= DrawingLimits.maximumCanvasHeight
            && strokes.count <= DrawingLimits.maximumStrokeBytes
            && hasValidBackgroundImage && hasValidPictures && pictureBytes <= DrawingLimits.maximumBackgroundImageBytes && hasContentOfItsVersion
    }

    public func encoded() throws -> Data {
        guard hasValidGeometry else { throw GraphiteError.oversized("This drawing exceeds the supported canvas size.") }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let encodedPayload = try encoder.encode(self)
        guard encodedPayload.count <= DrawingLimits.maximumPayloadBytes else {
            throw GraphiteError.oversized("Editable stroke data exceeds the drawing metadata budget.")
        }
        return encodedPayload
    }

    /// Returns nil for anything unexpected: unknown versions, oversized or corrupt data.
    public static func decodeIfValid(_ encodedPayload: Data) -> DrawingPayload? {
        guard encodedPayload.count <= DrawingLimits.maximumPayloadBytes,
              isSmallBinaryPropertyList(encodedPayload),
              let payload = try? PropertyListDecoder().decode(DrawingPayload.self, from: encodedPayload),
              (1...3).contains(payload.version), payload.hasValidGeometry else { return nil }
        return payload
    }

    /// The record is one dictionary of at most twelve fields, about 30 property list objects,
    /// and eight more for each picture placed on the drawing.
    static let maximumPropertyListObjectCount: UInt64 = 64 + 8 * UInt64(DrawingLimits.maximumPictureCount)

    /// Graphite writes this record only as a small binary property list. Anything else is
    /// refused before decoding: the decoder recurses into nested containers, and a file
    /// from a synced vault with a few hundred nested arrays would exhaust the stack each
    /// time the drawing is shown, including at launch when its note reopens. Nesting can
    /// be no deeper than the object count, which the binary trailer states up front.
    static func isSmallBinaryPropertyList(_ encodedPayload: Data) -> Bool {
        let header = Data("bplist00".utf8)
        // Trailer: six unused bytes, the offset and reference sizes, then the object count,
        // the top object and the offset table position as big-endian 64-bit numbers.
        let trailerLength = 32
        guard encodedPayload.count >= header.count + trailerLength, encodedPayload.prefix(header.count) == header else { return false }
        let objectCountBytes = encodedPayload.suffix(trailerLength).dropFirst(8).prefix(8)
        let objectCount = objectCountBytes.reduce(UInt64(0)) { total, byte in (total << 8) | UInt64(byte) }
        return objectCount <= maximumPropertyListObjectCount
    }
}

/// Result of reading optional editing metadata from an ordinary drawing file.
public struct DrawingMetadataReading: Sendable {
    public let payload: DrawingPayload?
    /// True when metadata was present but stale, corrupt, or unsupported.
    public let metadataWasDiscarded: Bool

    public init(payload: DrawingPayload?, metadataWasDiscarded: Bool) {
        self.payload = payload
        self.metadataWasDiscarded = metadataWasDiscarded
    }
}

public enum DrawingCanvasGeometry {
    /// The region saved for a drawing: the full canvas width, and vertically the ink
    /// plus a margin, so an embed is only as tall as its content. Ink outside the canvas
    /// width is kept rather than cropped.
    public static func exportBounds(inkBounds: CGRect?, canvasWidth: Double) -> CGRect {
        let margin = DrawingLimits.exportMargin
        guard let inkBounds, !inkBounds.isNull, !inkBounds.isInfinite, inkBounds.width > 0 || inkBounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: canvasWidth, height: DrawingLimits.minimumExportHeight)
        }
        let minimumX = min(0, inkBounds.minX - margin)
        let maximumX = max(canvasWidth, inkBounds.maxX + margin)
        let minimumY = inkBounds.minY - margin
        let height = max(inkBounds.maxY + margin - minimumY, DrawingLimits.minimumExportHeight)
        return CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX, height: height).integral
    }

    /// The region saved for a drawing made on an image: exactly the picture while the ink
    /// stays on it, so the annotated image has the picture's proportions; ink beyond the
    /// picture widens the region to include it with a margin.
    public static func exportBounds(inkBounds: CGRect?, backgroundImageFrame: CGRect) -> CGRect {
        guard let inkBounds, !inkBounds.isNull, !inkBounds.isInfinite, inkBounds.width > 0 || inkBounds.height > 0,
              !backgroundImageFrame.contains(inkBounds) else { return backgroundImageFrame.integral }
        let margin = DrawingLimits.exportMargin
        return backgroundImageFrame.union(inkBounds.insetBy(dx: -margin, dy: -margin)).integral
    }

    /// The smallest rectangle around the ink and the pictures placed on a drawing, or nil
    /// when there is neither.
    public static func contentBounds(inkBounds: CGRect?, pictureFrames: [CGRect]) -> CGRect? {
        var bounds: CGRect?
        for rectangle in [inkBounds].compactMap({ rectangle in rectangle }) + pictureFrames
        where !rectangle.isNull && !rectangle.isInfinite && (rectangle.width > 0 || rectangle.height > 0) {
            bounds = bounds?.union(rectangle) ?? rectangle
        }
        return bounds
    }

    /// `bounds` grown up and to the left to start on lines of the paper pattern, so the
    /// pattern of a saved drawing is in step with its ink when it is opened again.
    public static func startingOnPaperLines(_ bounds: CGRect, of pattern: DrawingPaperPattern) -> CGRect {
        guard DrawingPaperGeometry.spacing(of: pattern) != nil else { return bounds }
        let minimumX = pattern == .ruled ? bounds.minX : DrawingPaperGeometry.snappedToLine(bounds.minX, of: pattern)
        let minimumY = DrawingPaperGeometry.snappedToLine(bounds.minY, of: pattern)
        return CGRect(x: minimumX, y: minimumY, width: bounds.maxX - minimumX, height: bounds.maxY - minimumY)
    }

    /// The PNG scale for a drawing of this size, or nil when a readable raster would
    /// exceed the pixel budget.
    public static func pngScale(for size: CGSize) -> Double? {
        let area = Double(size.width * size.height)
        guard area > 0 else { return nil }
        let affordableScale = (DrawingLimits.maximumPNGPixelCount / area).squareRoot()
        let scale = min(DrawingLimits.preferredPNGScale, affordableScale)
        return scale >= DrawingLimits.minimumPNGScale ? scale : nil
    }
}
