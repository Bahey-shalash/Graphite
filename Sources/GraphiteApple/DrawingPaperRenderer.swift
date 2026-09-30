import Foundation
import CoreGraphics
import GraphiteCore

/// Draws a drawing's paper pattern: into a bitmap for PNG drawings and the editor, and as
/// outlines for the vector formats, from the same positions (`DrawingPaperGeometry`).
public enum DrawingPaperRenderer {
    /// Light enough to stay behind handwriting, as the lines of printed paper do (`#ccd4e0`).
    /// Whole color bytes, so every format writes exactly the same color.
    public static let lineColor = VectorInkColor(red: 204.0 / 255, green: 212.0 / 255, blue: 224.0 / 255, alpha: 1)
    /// Dots are small, so they are a little darker than lines (`#a3adbf`).
    public static let dotColor = VectorInkColor(red: 163.0 / 255, green: 173.0 / 255, blue: 191.0 / 255, alpha: 1)
    private static let dotSideCount = 8

    /// Fills the pattern's lines or dots that cross `region`, in a context whose coordinates
    /// are the drawing's.
    public static func draw(_ pattern: DrawingPaperPattern, in region: CGRect, context: CGContext) {
        let positions = DrawingPaperGeometry.linePositions(of: pattern, in: region.insetBy(dx: -DrawingPaperGeometry.dotDiameter, dy: -DrawingPaperGeometry.dotDiameter))
        switch pattern {
        case .plain:
            return
        case .squared, .ruled:
            context.setFillColor(CGColor(srgbRed: lineColor.red, green: lineColor.green, blue: lineColor.blue, alpha: lineColor.alpha))
            context.fill(lineRectangles(positions, in: region))
        case .dotted:
            context.setFillColor(CGColor(srgbRed: dotColor.red, green: dotColor.green, blue: dotColor.blue, alpha: dotColor.alpha))
            let radius = DrawingPaperGeometry.dotDiameter / 2
            for vertical in positions.horizontal {
                for horizontal in positions.vertical {
                    context.fillEllipse(in: CGRect(x: horizontal - radius, y: vertical - radius, width: 2 * radius, height: 2 * radius))
                }
            }
        }
    }

    /// The pattern over `region` as one shape, drawn under the ink of a vector drawing.
    public static func shape(for pattern: DrawingPaperPattern, in region: CGRect) -> VectorShape? {
        let positions = DrawingPaperGeometry.linePositions(of: pattern, in: region)
        switch pattern {
        case .plain:
            return nil
        case .squared, .ruled:
            let subpaths = lineRectangles(positions, in: region).map { rectangle in
                [CGPoint(x: rectangle.minX, y: rectangle.minY), CGPoint(x: rectangle.maxX, y: rectangle.minY),
                 CGPoint(x: rectangle.maxX, y: rectangle.maxY), CGPoint(x: rectangle.minX, y: rectangle.maxY)]
            }
            return subpaths.isEmpty ? nil : VectorShape(subpaths: subpaths, color: lineColor)
        case .dotted:
            let radius = DrawingPaperGeometry.dotDiameter / 2
            var subpaths: [[CGPoint]] = []
            for vertical in positions.horizontal {
                for horizontal in positions.vertical {
                    subpaths.append((0..<dotSideCount).map { cornerIndex in
                        let angle = 2 * Double.pi * Double(cornerIndex) / Double(dotSideCount)
                        return CGPoint(x: horizontal + radius * cos(angle), y: vertical + radius * sin(angle))
                    })
                }
            }
            return subpaths.isEmpty ? nil : VectorShape(subpaths: subpaths, color: dotColor)
        }
    }

    private static func lineRectangles(_ positions: (horizontal: [Double], vertical: [Double]), in region: CGRect) -> [CGRect] {
        let halfWidth = DrawingPaperGeometry.lineWidth / 2
        return positions.horizontal.map { vertical in CGRect(x: region.minX, y: vertical - halfWidth, width: region.width, height: 2 * halfWidth) }
            + positions.vertical.map { horizontal in CGRect(x: horizontal - halfWidth, y: region.minY, width: 2 * halfWidth, height: region.height) }
    }
}
