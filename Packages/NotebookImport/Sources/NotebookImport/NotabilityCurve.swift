import CoreGraphics
import Foundation

/// One curve of a note's ink: a chain of cubic Bézier segments (knot, control, control, knot, …), so its 3k + 1
/// points make k segments and k + 1 knots. The stroke is drawn along the chain with width `width` × each knot's
/// `widthFactor`, interpolated between knots, with round ends.
public struct NotabilityCurve: Sendable, Equatable {
    /// The curve's place in the drawing order, from 0.
    public let index: Int
    /// Recordings refer to the curve by this UUID.
    public let uuid: UUID
    public let style: NotabilityCurveStyle
    public let width: Double
    public let color: NotebookImportColor
    /// The points of the Bézier chain in document units, y downwards.
    public let points: [CGPoint]
    /// One value set per knot: the first point and every third point after it.
    public let knots: [NotabilityKnot]

    public init(index: Int, uuid: UUID, style: NotabilityCurveStyle, width: Double, color: NotebookImportColor, points: [CGPoint],
                knots: [NotabilityKnot]) {
        self.index = index
        self.uuid = uuid
        self.style = style
        self.width = width
        self.color = color
        self.points = points
        self.knots = knots
    }
}

/// The per-knot values of a curve. The altitude and azimuth are nil when the note does not store them for every
/// knot (the reader then reports `perKnotArrayIgnored`).
public struct NotabilityKnot: Sendable, Equatable {
    /// Multiplies the curve's width at this knot.
    public let widthFactor: Double
    /// The Pencil's force; 1.0 for mouse or finger ink.
    public let force: Double
    /// The Pencil's altitude angle in radians; π/2 for mouse or finger ink.
    public let altitudeAngle: Double?
    /// The Pencil's azimuth as a unit vector.
    public let azimuthUnitVector: NotabilityAzimuthVector?

    public init(widthFactor: Double, force: Double, altitudeAngle: Double?, azimuthUnitVector: NotabilityAzimuthVector?) {
        self.widthFactor = widthFactor
        self.force = force
        self.altitudeAngle = altitudeAngle
        self.azimuthUnitVector = azimuthUnitVector
    }
}

/// The direction the Pencil pointed in on the page, as a unit vector.
public struct NotabilityAzimuthVector: Sendable, Equatable {
    public let horizontal: Double
    public let vertical: Double

    public init(horizontal: Double, vertical: Double) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

/// `curvesstyles`: the tool that drew the curve.
public enum NotabilityCurveStyle: Sendable, Hashable {
    case pen
    /// Highlighter ink; its transparency is in the curve's colour.
    case highlighter
    case unknown(UInt8)

    public init(rawStyle: UInt8) {
        switch rawStyle {
        case 3: self = .pen
        case 4: self = .highlighter
        default: self = .unknown(rawStyle)
        }
    }
}
