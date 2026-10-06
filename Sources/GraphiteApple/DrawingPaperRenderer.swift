import Foundation
import CoreGraphics
import GraphiteCore

/// Draws a drawing's paper pattern: into a bitmap for PNG drawings and the editor, and as
/// outlines for the vector formats, from the same positions (`DrawingPaperGeometry`).
public enum DrawingPaperRenderer {
    private static let dotSideCount = 8

    /// The color of the paper's lines, or of its dots, in whole color bytes, so every format
    /// writes exactly the same color. The standard gray is light enough to stay behind
    /// handwriting, as the lines of printed paper do (`#ccd4e0`); dots are small, so they
    /// are a little darker (`#a3adbf`). Light is halfway to white and strong halfway to the
    /// darkest the color goes; both stay opaque, so lines that cross are not darker where
    /// they cross.
    public static func color(of paper: DrawingPaper, forDots: Bool) -> VectorInkColor {
        let (lineBytes, dotBytes, strongBytes): ((Int, Int, Int), (Int, Int, Int), (Int, Int, Int)) = switch paper.lineColor {
        case .gray: ((204, 212, 224), (163, 173, 191), (120, 130, 150))
        case .blue: ((181, 204, 238), (137, 172, 222), (84, 128, 196))
        case .green: ((189, 224, 199), (143, 196, 158), (86, 150, 105))
        case .red: ((240, 196, 196), (222, 150, 150), (192, 90, 90))
        }
        let standard = forDots ? dotBytes : lineBytes
        let target: (Int, Int, Int) = switch paper.lineStrength {
        case .light: (255, 255, 255)
        case .standard: standard
        case .strong: strongBytes
        }
        func mixed(_ standardByte: Int, _ targetByte: Int) -> Double {
            let byte = paper.lineStrength == .standard ? standardByte : (standardByte + targetByte) / 2
            return Double(byte) / 255
        }
        return VectorInkColor(red: mixed(standard.0, target.0), green: mixed(standard.1, target.1), blue: mixed(standard.2, target.2), alpha: 1)
    }

    /// The color of the paper itself, from its `#rrggbb`; nil when there is none.
    public static func paperColor(of background: DrawingBackground) -> VectorInkColor? {
        guard let hex = background.colorHex, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return VectorInkColor(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255, alpha: 1)
    }

    /// Fills the paper's lines or dots that cross `region`, in a context whose coordinates
    /// are the drawing's.
    public static func draw(_ paper: DrawingPaper, in region: CGRect, context: CGContext) {
        let reach = DrawingPaperGeometry.dotDiameter
        let positions = DrawingPaperGeometry.linePositions(of: paper.pattern, spacing: paper.spacing, in: region.insetBy(dx: -reach, dy: -reach))
        switch paper.pattern {
        case .plain:
            return
        case .squared, .ruled:
            let color = color(of: paper, forDots: false)
            context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
            context.fill(lineRectangles(positions, in: region))
        case .dotted:
            let color = color(of: paper, forDots: true)
            context.setFillColor(CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha))
            let radius = DrawingPaperGeometry.dotDiameter / 2
            for vertical in positions.horizontal {
                for horizontal in positions.vertical {
                    context.fillEllipse(in: CGRect(x: horizontal - radius, y: vertical - radius, width: 2 * radius, height: 2 * radius))
                }
            }
        }
    }

    /// The paper's pattern over `region` as one shape, drawn under the ink of a vector drawing.
    public static func shape(for paper: DrawingPaper, in region: CGRect) -> VectorShape? {
        let positions = DrawingPaperGeometry.linePositions(of: paper.pattern, spacing: paper.spacing, in: region)
        switch paper.pattern {
        case .plain:
            return nil
        case .squared, .ruled:
            let subpaths = lineRectangles(positions, in: region).map { rectangle in
                [CGPoint(x: rectangle.minX, y: rectangle.minY), CGPoint(x: rectangle.maxX, y: rectangle.minY),
                 CGPoint(x: rectangle.maxX, y: rectangle.maxY), CGPoint(x: rectangle.minX, y: rectangle.maxY)]
            }
            return subpaths.isEmpty ? nil : VectorShape(subpaths: subpaths, color: color(of: paper, forDots: false))
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
            return subpaths.isEmpty ? nil : VectorShape(subpaths: subpaths, color: color(of: paper, forDots: true))
        }
    }

    private static func lineRectangles(_ positions: (horizontal: [Double], vertical: [Double]), in region: CGRect) -> [CGRect] {
        let halfWidth = DrawingPaperGeometry.lineWidth / 2
        return positions.horizontal.map { vertical in CGRect(x: region.minX, y: vertical - halfWidth, width: region.width, height: 2 * halfWidth) }
            + positions.vertical.map { horizontal in CGRect(x: horizontal - halfWidth, y: region.minY, width: 2 * halfWidth, height: region.height) }
    }
}
