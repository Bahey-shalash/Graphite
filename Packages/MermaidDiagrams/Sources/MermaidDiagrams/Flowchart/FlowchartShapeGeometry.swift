import CoreGraphics
import Foundation

/// The geometry of each node shape, Pele's: the size around a text, how far the outline lies inside the bounding
/// box along each side (where an edge meets it), and how much of a side edges may spread along.
enum FlowchartShapeGeometry {
    static let horizontalPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 12
    /// Kept clear at each end of a straight side, for its corner.
    static let cornerClearance: CGFloat = 12

    /// A shape's size around a text of `textSize`, and how far below the shape's center the text's center is.
    static func size(of shape: FlowchartNodeShape, textSize: CGSize) -> (size: CGSize, textOffset: CGFloat) {
        let textWidth = textSize.width
        let paddedHeight = textSize.height + 2 * verticalPadding
        switch shape {
        case .rectangle, .roundedRectangle:
            return (CGSize(width: max(textWidth + 2 * horizontalPadding, 2 * horizontalPadding + 12), height: paddedHeight), 0)
        case .stadium:
            return (CGSize(width: textWidth + paddedHeight * 0.5 + 2 * horizontalPadding - 8, height: paddedHeight), 0)
        case .subroutine:
            return (CGSize(width: textWidth + 2 * horizontalPadding + 16, height: paddedHeight), 0)
        case .cylinder:
            let width = max(textWidth + 2 * horizontalPadding, 56)
            let capDepth = cylinderCapDepth(width: width)
            return (CGSize(width: width, height: paddedHeight + 2 * capDepth), capDepth / 2)
        case .circle, .doubleCircle:
            let diagonal = (textWidth * textWidth + textSize.height * textSize.height).squareRoot()
            let diameter = shape == .circle ? max(diagonal + 16, 44) : max(diagonal + 26, 54)
            return (CGSize(width: diameter, height: diameter), 0)
        case .diamond:
            let across = textWidth + 16
            let down = textSize.height + 8
            return (CGSize(width: across + 1.6 * down, height: across / 1.6 + down), 0)
        case .asymmetric:
            return (CGSize(width: textWidth + 2 * horizontalPadding + paddedHeight / 4, height: paddedHeight), 0)
        case .hexagon, .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid:
            return (CGSize(width: textWidth + 2 * horizontalPadding + paddedHeight / 2, height: paddedHeight), 0)
        case .text:
            return (CGSize(width: textWidth + 8, height: textSize.height + 8), 0)
        }
    }

    /// The depth of a cylinder's elliptical cap.
    static func cylinderCapDepth(width: CGFloat) -> CGFloat {
        min(12, max(6, width / 14))
    }

    /// How far inside the bounding box the outline is on `side`, `offset` from the side's middle (to the right on a
    /// horizontal side, downward on a vertical one).
    static func inset(of shape: FlowchartNodeShape, size: CGSize, side: DiagramSide, offset: CGFloat) -> CGFloat {
        let width = size.width
        let height = size.height
        switch shape {
        case .rectangle, .roundedRectangle, .subroutine, .text: return 0
        case .stadium: return side.isHorizontal ? 0 : bulge(offset: offset, halfLength: height / 2, depth: height / 2)
        case .cylinder: return side.isHorizontal ? bulge(offset: offset, halfLength: width / 2, depth: cylinderCapDepth(width: width)) : 0
        case .circle, .doubleCircle:
            return side.isHorizontal ? bulge(offset: offset, halfLength: width / 2, depth: height / 2)
                                     : bulge(offset: offset, halfLength: height / 2, depth: width / 2)
        case .diamond: return side.isHorizontal ? abs(offset) * height / width : abs(offset) * width / height
        case .hexagon: return side.isHorizontal ? 0 : abs(offset) / 2
        case .asymmetric: return side == .left ? height / 4 : 0
        case .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid: return side.isHorizontal ? 0 : height / 8
        }
    }

    /// How much of `side`, centered on its middle, the edges meeting it may spread along.
    static func span(of shape: FlowchartNodeShape, size: CGSize, side: DiagramSide) -> CGFloat {
        let length = side.isHorizontal ? size.width : size.height
        let span: CGFloat
        switch shape {
        case .rectangle, .roundedRectangle, .subroutine, .text: span = length - 2 * cornerClearance
        case .stadium: span = side.isHorizontal ? size.width - size.height : size.height * 0.6
        case .cylinder: span = side.isHorizontal ? size.width * 0.6 : size.height - 2 * cornerClearance - 12
        case .circle, .doubleCircle, .diamond: span = length * 0.6
        case .hexagon: span = side.isHorizontal ? size.width - size.height / 2 - cornerClearance : size.height * 0.5
        case .asymmetric: span = side.isHorizontal ? size.width - 2 * cornerClearance : 0
        case .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid:
            span = side.isHorizontal ? size.width - size.height / 2 - 2 * cornerClearance : 0
        }
        return max(0, span)
    }

    /// How far an ellipse's outline has fallen away from its bounding box, `offset` from the middle of a side
    /// `halfLength` long, for an ellipse `depth` deep at the side's ends.
    private static func bulge(offset: CGFloat, halfLength: CGFloat, depth: CGFloat) -> CGFloat {
        guard halfLength > 0 else { return 0 }
        let fraction = min(1, abs(offset) / halfLength)
        return depth * (1 - (1 - fraction * fraction).squareRoot())
    }
}
