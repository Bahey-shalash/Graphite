import CoreGraphics

/// A line through a diagram, made of straight and cubic segments from a start point.
public struct DiagramPath: Equatable, Sendable {
    public let start: CGPoint
    public let segments: [DiagramPathSegment]
}

public enum DiagramPathSegment: Equatable, Sendable {
    case line(to: CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
}

extension DiagramPath {
    func translated(by offset: CGVector) -> DiagramPath {
        DiagramPath(start: start.translated(by: offset), segments: segments.map { segment in
            switch segment {
            case .line(let end): .line(to: end.translated(by: offset))
            case .curve(let end, let firstControl, let secondControl):
                .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset), control2: secondControl.translated(by: offset))
            }
        })
    }
}

extension CGPoint {
    func translated(by offset: CGVector) -> CGPoint {
        CGPoint(x: x + offset.dx, y: y + offset.dy)
    }
}
