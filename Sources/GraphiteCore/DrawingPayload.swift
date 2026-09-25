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

public enum DrawingLimits {
    /// Bound on untrusted PencilKit data before decoding it.
    public static let maximumStrokeBytes = 32 * 1_048_576
    /// Bound on the encoded metadata record that wraps the stroke data.
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
}

/// Editable drawing metadata embedded in PNG, SVG, and PDF drawings. Version 1 is the
/// original PNG `grPK` record; its field names are part of the stored format.
public struct DrawingPayload: Codable, Sendable, Equatable {
    public let version: Int
    public let width: Double
    public let height: Double
    public let background: DrawingBackground
    public let strokes: Data
    /// Digest of the visible content this metadata was written with. Another application
    /// that changes the visible drawing makes the metadata stale, so it is ignored.
    public let visibleContentDigest: Data

    private enum CodingKeys: String, CodingKey {
        case version, width, height, background, strokes
        case visibleContentDigest = "pixelDigest"
    }

    public init(width: Double, height: Double, background: DrawingBackground, strokes: Data, visibleContentDigest: Data = Data()) {
        version = 1
        self.width = width
        self.height = height
        self.background = background
        self.strokes = strokes
        self.visibleContentDigest = visibleContentDigest
    }

    public func replacingVisibleContentDigest(_ digest: Data) -> DrawingPayload {
        DrawingPayload(width: width, height: height, background: background, strokes: strokes, visibleContentDigest: digest)
    }

    public var hasValidGeometry: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
            && width <= DrawingLimits.maximumCanvasWidth && height <= DrawingLimits.maximumCanvasHeight
            && strokes.count <= DrawingLimits.maximumStrokeBytes
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
              payload.version == 1, payload.hasValidGeometry else { return nil }
        return payload
    }

    /// The record is one dictionary of six fields: about 13 property list objects.
    static let maximumPropertyListObjectCount: UInt64 = 64

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
