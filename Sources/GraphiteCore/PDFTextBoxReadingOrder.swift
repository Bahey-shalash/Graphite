import Foundation
import CoreGraphics

/// The order text boxes are read in, as a person reads a page: from the top down, and
/// boxes whose tops are about level from left to right, all as the page is shown.
public enum PDFTextBoxReadingOrder {
    /// Tops closer than this, in points, are taken as level, as boxes placed by hand rarely
    /// line up exactly.
    public static let levelTolerancePoints: Double = 8

    /// The boxes in reading order on a page shown turned by quarter turns clockwise.
    public static func sorted(_ boxes: [PDFTextBox], pageQuarterTurns: Int) -> [PDFTextBox] {
        let turns = ((pageQuarterTurns % 4) + 4) % 4
        let placed = boxes.map { box in (box: box, topLeft: shownTopLeft(of: box.annotationBounds, quarterTurns: turns)) }
        return placed.sorted { first, second in
            if abs(first.topLeft.y - second.topLeft.y) > levelTolerancePoints { return first.topLeft.y < second.topLeft.y }
            if first.topLeft.x != second.topLeft.x { return first.topLeft.x < second.topLeft.x }
            return first.box.name < second.box.name
        }.map(\.box)
    }

    /// The corner of a page rectangle shown at the top left, as distances from the left and
    /// down from the top of the page as shown (the page's own origin cancels out in an order).
    static func shownTopLeft(of rectangle: CGRect, quarterTurns: Int) -> (x: Double, y: Double) {
        switch quarterTurns {
        case 1: (Double(rectangle.minY), Double(rectangle.minX))
        case 2: (-Double(rectangle.maxX), Double(rectangle.minY))
        case 3: (-Double(rectangle.maxY), -Double(rectangle.maxX))
        default: (Double(rectangle.minX), -Double(rectangle.maxY))
        }
    }
}
