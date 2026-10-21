import CoreGraphics
import Foundation

/// A recognised shape of the note's `shapes` property list. A shape is not one of the curves: it is drawn just
/// before the curve whose index is `drawnBeforeCurveIndex`.
public struct NotabilityShape: Sendable, Equatable {
    public let kind: NotabilityShapeKind
    public let drawnBeforeCurveIndex: Int
    public let start: CGPoint
    public let end: CGPoint
    /// With a control point, the line is a quadratic Bézier curve from `start` through it to `end`.
    public let quadraticControlPoint: CGPoint?
    public let width: Double?
    public let color: NotebookImportColor
    /// The dash pattern of a dashed shape (`appearance.dashStyle.pattern`); nil for a solid one.
    public let dashPattern: [Double]?

    public init(kind: NotabilityShapeKind, drawnBeforeCurveIndex: Int, start: CGPoint, end: CGPoint, quadraticControlPoint: CGPoint?,
                width: Double?, color: NotebookImportColor, dashPattern: [Double]?) {
        self.kind = kind
        self.drawnBeforeCurveIndex = drawnBeforeCurveIndex
        self.start = start
        self.end = end
        self.quadraticControlPoint = quadraticControlPoint
        self.width = width
        self.color = color
        self.dashPattern = dashPattern
    }
}

/// The shape's entry in `kinds`.
public enum NotabilityShapeKind: Sendable, Hashable {
    /// A straight line, or a quadratic curve when the shape has a control point.
    case line
    case unknown(String)

    public init(rawKind: String) {
        switch rawKind {
        case "line": self = .line
        default: self = .unknown(rawKind)
        }
    }
}
