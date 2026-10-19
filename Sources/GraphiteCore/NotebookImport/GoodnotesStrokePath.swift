import CoreGraphics
import Foundation

/// A stroke's path in one of the four layouts Goodnotes writes, decoded from its tpl image. Coordinates are page
/// units before the stroke's offset is added.
public enum GoodnotesStrokePath: Sendable, Equatable {
    /// Ball pen, highlighter and shapes: a centre line drawn at one width with round ends.
    case constantWidth(GoodnotesConstantWidthPath)
    /// Fountain pen, brush pen and tape (schema 25 on): a centre line with a width at each point, and the outline
    /// Goodnotes fills.
    case varyingWidth(GoodnotesVaryingWidthPath)
    /// Ink 4: a width and the outline; its centre-line codes are not worked out.
    case olderVaryingWidth(GoodnotesOlderVaryingWidthPath)
    /// Pencil (schema 25 on): points that carry the Apple Pencil's azimuth, altitude and force.
    case pencil(GoodnotesPencilPath)
}

/// A quadratic Bézier segment from the current point.
public struct GoodnotesQuadraticCurve: Sendable, Equatable {
    public let control: CGPoint
    public let end: CGPoint
}

public struct GoodnotesSubpath: Sendable, Equatable {
    public let start: CGPoint
    public let curves: [GoodnotesQuadraticCurve]
}

public struct GoodnotesConstantWidthPath: Sendable, Equatable {
    public let width: Double
    public let subpaths: [GoodnotesSubpath]
    /// Dash and gap lengths; empty for a solid line.
    public let dashPattern: [Double]
}

/// A centre-line point with the stroke's width there.
public struct GoodnotesWidthPoint: Sendable, Equatable {
    public let point: CGPoint
    public let width: Double
}

public struct GoodnotesWidthCurve: Sendable, Equatable {
    public let control: GoodnotesWidthPoint
    public let end: GoodnotesWidthPoint
}

public struct GoodnotesCentreLine: Sendable, Equatable {
    public let start: GoodnotesWidthPoint
    public let curves: [GoodnotesWidthCurve]
}

/// One command of a stroke outline. Each centre-line segment has its own closed outline.
public enum GoodnotesOutlineCommand: Sendable, Equatable {
    case move(to: CGPoint)
    case cubic(control1: CGPoint, control2: CGPoint, end: CGPoint)
    /// Continues from the current point, which lies on the circle at the start angle, to the end angle.
    case arc(centre: CGPoint, radius: Double, startAngleRadians: Double, endAngleRadians: Double)
    /// Tape's flat end: a straight edge through the point.
    case flatCap(through: CGPoint)
}

public struct GoodnotesVaryingWidthPath: Sendable, Equatable {
    /// Nil when the path has no centre-line codes.
    public let centreLine: GoodnotesCentreLine?
    /// One closed outline per centre-line segment.
    public let outline: [[GoodnotesOutlineCommand]]
}

public struct GoodnotesOlderVaryingWidthPath: Sendable, Equatable {
    public let width: Double
    public let outline: [[GoodnotesOutlineCommand]]
}

/// A pencil point: the position and the Apple Pencil's state there.
public struct GoodnotesPencilSample: Sendable, Equatable {
    public let point: CGPoint
    /// −π to π.
    public let azimuthRadians: Double
    /// 0 (on its side) to π/2 (upright).
    public let altitudeRadians: Double
    /// 0 to 4.17, the Pencil's maximum; 0 throughout with a mouse.
    public let force: Double
}

public struct GoodnotesPencilCurve: Sendable, Equatable {
    public let control: GoodnotesPencilSample
    public let end: GoodnotesPencilSample
    /// The first 32-bit value of each curve, which is not a sensible float (perhaps a texture seed).
    public let leadingValue: UInt32
}

public struct GoodnotesPencilSubpath: Sendable, Equatable {
    public let start: GoodnotesPencilSample
    public let curves: [GoodnotesPencilCurve]
}

public struct GoodnotesPencilPath: Sendable, Equatable {
    public let width: Double
    public let subpaths: [GoodnotesPencilSubpath]
}
