import CoreGraphics
import Foundation

/// Builds the path through an edge's route the way Pele draws it: between two points that are not in line, one S
/// that leaves and arrives along the flow; between points in line, a straight segment.
enum DiagramRouteDrawing {
    /// - Parameters:
    ///   - points: The route, from the source's outline to the target's, at least two points.
    ///   - flowIsVertical: Whether ranks follow each other down or up the page (rather than across it).
    ///   - startTrim: How much of the line the source's mark takes.
    ///   - endTrim: How much of the line the target's mark takes.
    /// - Returns: The path, and the unit directions the edge leaves its source and arrives at its target in.
    static func path(through points: [CGPoint], flowIsVertical: Bool, startTrim: CGFloat,
                     endTrim: CGFloat) -> (path: DiagramPath, startDirection: CGVector, endDirection: CGVector) {
        var points = points
        let startDirection = direction(from: points[0], to: points[1], flowIsVertical: flowIsVertical)
        let endDirection = direction(from: points[points.count - 2], to: points[points.count - 1], flowIsVertical: flowIsVertical)
        points[0] = CGPoint(x: points[0].x + startDirection.dx * startTrim, y: points[0].y + startDirection.dy * startTrim)
        let last = points.count - 1
        points[last] = CGPoint(x: points[last].x - endDirection.dx * endTrim, y: points[last].y - endDirection.dy * endTrim)
        var segments: [DiagramPathSegment] = []
        for index in 1..<points.count {
            let from = points[index - 1]
            let to = points[index]
            if isInLine(from, to) {
                segments.append(.line(to: to))
            } else if flowIsVertical {
                let half = (to.y - from.y) / 2
                segments.append(.curve(to: to, control1: CGPoint(x: from.x, y: from.y + half), control2: CGPoint(x: to.x, y: to.y - half)))
            } else {
                let half = (to.x - from.x) / 2
                segments.append(.curve(to: to, control1: CGPoint(x: from.x + half, y: from.y), control2: CGPoint(x: to.x - half, y: to.y)))
            }
        }
        return (DiagramPath(start: points[0], segments: segments), startDirection, endDirection)
    }

    /// The way the path heads from `from` to `to`: along the flow when an S joins them, straight at the other otherwise.
    private static func direction(from: CGPoint, to: CGPoint, flowIsVertical: Bool) -> CGVector {
        if !isInLine(from, to) {
            return flowIsVertical ? CGVector(dx: 0, dy: to.y >= from.y ? 1 : -1) : CGVector(dx: to.x >= from.x ? 1 : -1, dy: 0)
        }
        let length = max(hypot(to.x - from.x, to.y - from.y), 0.0001)
        return CGVector(dx: (to.x - from.x) / length, dy: (to.y - from.y) / length)
    }

    /// Two points are in line when they share a coordinate, to a hundredth of a point.
    private static func isInLine(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < 0.01 || abs(first.y - second.y) < 0.01
    }
}
