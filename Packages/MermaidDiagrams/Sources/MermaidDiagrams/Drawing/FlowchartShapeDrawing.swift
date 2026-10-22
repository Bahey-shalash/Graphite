import CoreGraphics

/// The outline of each node shape, Pele's, as Core Graphics paths in a frame: the filled outline, and the lines
/// drawn over it (a subroutine's inner sides, a cylinder's front rim, a double circle's inner circle).
enum FlowchartShapeDrawing {
    /// The corner radius of a rectangle: Pele's `--pele-radius`.
    static let rectangleCornerRadius: CGFloat = 4
    /// The largest corner radius of a rounded rectangle.
    static let roundedCornerRadius: CGFloat = 12
    /// How far a subroutine's inner sides are from its outer ones.
    static let subroutineInset: CGFloat = 8
    /// How far a double circle's inner circle is inside its outer one.
    static let doubleCircleGap: CGFloat = 5

    /// The filled and stroked outline, or nil for a shape drawn as text alone.
    static func outline(of shape: FlowchartNodeShape, in frame: CGRect) -> CGPath? {
        let width = frame.width
        let height = frame.height
        switch shape {
        case .rectangle, .subroutine: return CGPath(roundedRect: frame, cornerWidth: rectangleCornerRadius, cornerHeight: rectangleCornerRadius, transform: nil)
        case .roundedRectangle:
            let radius = min(roundedCornerRadius, height / 2)
            return CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        case .stadium: return CGPath(roundedRect: frame, cornerWidth: min(height, width) / 2, cornerHeight: height / 2, transform: nil)
        case .circle, .doubleCircle: return CGPath(ellipseIn: frame, transform: nil)
        case .cylinder: return cylinderBody(in: frame)
        case .text: return nil
        case .asymmetric, .diamond, .hexagon, .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid:
            return polygon(corners(of: shape, width: width, height: height), around: CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    /// The lines drawn over the filled outline, or nil.
    static func innerLines(of shape: FlowchartNodeShape, in frame: CGRect) -> CGPath? {
        switch shape {
        case .subroutine:
            let path = CGMutablePath()
            for x in [frame.minX + subroutineInset, frame.maxX - subroutineInset] {
                path.move(to: CGPoint(x: x, y: frame.minY))
                path.addLine(to: CGPoint(x: x, y: frame.maxY))
            }
            return path
        case .cylinder:
            let capDepth = FlowchartShapeGeometry.cylinderCapDepth(width: frame.width)
            let path = CGMutablePath()
            addHalfEllipse(to: path, center: CGPoint(x: frame.midX, y: frame.minY + capDepth), radiusX: frame.width / 2, radiusY: capDepth, lowerHalf: true,
                           startingOnLeft: true)
            return path
        case .doubleCircle:
            return CGPath(ellipseIn: frame.insetBy(dx: doubleCircleGap, dy: doubleCircleGap), transform: nil)
        case .rectangle, .roundedRectangle, .stadium, .circle, .asymmetric, .diamond, .hexagon, .leanRight, .leanLeft, .trapezoid,
             .invertedTrapezoid, .text:
            return nil
        }
    }

    /// A polygon's corners around its center, clockwise from the top left.
    private static func corners(of shape: FlowchartNodeShape, width: CGFloat, height: CGFloat) -> [CGPoint] {
        let left = -width / 2
        let right = width / 2
        let top = -height / 2
        let bottom = height / 2
        let slant = height / 4
        func corner(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        switch shape {
        case .asymmetric: return [corner(left, top), corner(right, top), corner(right, bottom), corner(left, bottom), corner(left + slant, 0)]
        case .diamond: return [corner(0, top), corner(right, 0), corner(0, bottom), corner(left, 0)]
        case .hexagon:
            return [corner(left + slant, top), corner(right - slant, top), corner(right, 0), corner(right - slant, bottom),
                    corner(left + slant, bottom), corner(left, 0)]
        case .leanRight: return [corner(left + slant, top), corner(right, top), corner(right - slant, bottom), corner(left, bottom)]
        case .leanLeft: return [corner(left, top), corner(right - slant, top), corner(right, bottom), corner(left + slant, bottom)]
        case .trapezoid: return [corner(left + slant, top), corner(right - slant, top), corner(right, bottom), corner(left, bottom)]
        case .invertedTrapezoid: return [corner(left, top), corner(right, top), corner(right - slant, bottom), corner(left + slant, bottom)]
        case .rectangle, .roundedRectangle, .stadium, .subroutine, .cylinder, .circle, .doubleCircle, .text: return []
        }
    }

    private static func polygon(_ corners: [CGPoint], around center: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: corners.map { corner in CGPoint(x: center.x + corner.x, y: center.y + corner.y) })
        path.closeSubpath()
        return path
    }

    /// A cylinder's body: the top cap's far half, the right side, the bottom cap's near half, the left side.
    private static func cylinderBody(in frame: CGRect) -> CGPath {
        let capDepth = FlowchartShapeGeometry.cylinderCapDepth(width: frame.width)
        let radiusX = frame.width / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: frame.minX, y: frame.minY + capDepth))
        addHalfEllipse(to: path, center: CGPoint(x: frame.midX, y: frame.minY + capDepth), radiusX: radiusX, radiusY: capDepth, lowerHalf: false,
                       startingOnLeft: true)
        path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - capDepth))
        addHalfEllipse(to: path, center: CGPoint(x: frame.midX, y: frame.maxY - capDepth), radiusX: radiusX, radiusY: capDepth, lowerHalf: true,
                       startingOnLeft: false)
        path.closeSubpath()
        return path
    }

    /// Half an ellipse from one end of its horizontal axis to the other, as two quarter arcs (cubic approximations).
    private static func addHalfEllipse(to path: CGMutablePath, center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, lowerHalf: Bool, startingOnLeft: Bool) {
        // The control-point distance that makes a cubic follow a quarter circle closely.
        let quarterCircleControl: CGFloat = 0.5523
        let vertical = lowerHalf ? radiusY : -radiusY
        let startX = startingOnLeft ? center.x - radiusX : center.x + radiusX
        let endX = startingOnLeft ? center.x + radiusX : center.x - radiusX
        let apex = CGPoint(x: center.x, y: center.y + vertical)
        if path.isEmpty { path.move(to: CGPoint(x: startX, y: center.y)) }
        path.addCurve(to: apex, control1: CGPoint(x: startX, y: center.y + vertical * quarterCircleControl),
                      control2: CGPoint(x: center.x + (startX - center.x) * quarterCircleControl, y: apex.y))
        path.addCurve(to: CGPoint(x: endX, y: center.y), control1: CGPoint(x: center.x + (endX - center.x) * quarterCircleControl, y: apex.y),
                      control2: CGPoint(x: endX, y: center.y + vertical * quarterCircleControl))
    }
}
