import CoreGraphics
import Foundation

/// The outline of each mindmap node, Pele's, as a Core Graphics path in a frame: the flowchart's shapes, a pill,
/// a cloud of four arcs over a flat base, and a bang of fourteen spikes.
enum MindmapShapeDrawing {
    /// How many spikes a bang has.
    static let bangSpikeCount = 14
    /// How far in a bang's notches are, as a fraction of its radii.
    static let bangNotchRatio: CGFloat = 0.82

    /// The outline to fill and stroke, or nil for a node drawn as its text alone.
    static func outline(of outline: MindmapNodeOutline, in frame: CGRect) -> CGPath? {
        if let shape = outline.flowchartShape { return FlowchartShapeDrawing.outline(of: shape, in: frame) }
        switch outline {
        case .pill:
            return CGPath(roundedRect: frame, cornerWidth: min(frame.width, frame.height) / 2, cornerHeight: frame.height / 2, transform: nil)
        case .cloud: return cloud(in: frame)
        case .bang: return bang(in: frame)
        case .text, .stadium, .rectangle, .roundedRectangle, .circle, .hexagon: return nil
        }
    }

    /// Pele's cloud: from the bottom left, a round lobe up the left side, two wide lobes over the top and a round lobe
    /// down the right side, then straight back along the bottom.
    private static func cloud(in frame: CGRect) -> CGPath {
        let halfWidth = frame.width / 2
        let halfHeight = frame.height / 2
        let lobeRadius = halfHeight * 0.55
        func point(_ across: CGFloat, _ down: CGFloat) -> CGPoint { CGPoint(x: frame.midX + across, y: frame.midY + down) }
        let corners = [point(-halfWidth + lobeRadius, halfHeight), point(-halfWidth + lobeRadius * 0.6, -halfHeight * 0.1),
                       point(-halfWidth * 0.1, -halfHeight * 0.72), point(halfWidth * 0.62, -halfHeight * 0.42), point(halfWidth - lobeRadius, halfHeight)]
        let radii = [CGSize(width: lobeRadius, height: lobeRadius), CGSize(width: halfWidth * 0.42, height: halfHeight * 0.7),
                     CGSize(width: halfWidth * 0.4, height: halfHeight * 0.62), CGSize(width: lobeRadius * 1.05, height: lobeRadius * 1.05)]
        let path = CGMutablePath()
        path.move(to: corners[0])
        for (index, radius) in radii.enumerated() {
            DiagramEllipticalArc.addArc(to: path, from: corners[index], to: corners[index + 1], radii: radius)
        }
        path.closeSubpath()
        return path
    }

    /// Pele's bang: points around the frame's ellipse, alternately on it and `bangNotchRatio` of the way in, from the top.
    private static func bang(in frame: CGRect) -> CGPath {
        let pointCount = 2 * bangSpikeCount
        let points = (0..<pointCount).map { index in
            let angle = CGFloat.pi * CGFloat(index) / CGFloat(bangSpikeCount) - CGFloat.pi / 2
            let reach: CGFloat = index.isMultiple(of: 2) ? 1 : bangNotchRatio
            return CGPoint(x: frame.midX + cos(angle) * frame.width / 2 * reach, y: frame.midY + sin(angle) * frame.height / 2 * reach)
        }
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }
}
