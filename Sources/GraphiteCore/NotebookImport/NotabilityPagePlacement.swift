import CoreGraphics
import Foundation

/// Which export pages an element of a note's continuous document is on, and how many pages the note fills. An element
/// is on every page its vertical extent touches, from the page of its lowest y to the page of its highest y, so a
/// stroke that crosses a page is drawn there; positions are assigned to pages as the reference reader assigns them
/// (`NotabilityPageGeometry.pagePosition`). One extent rule serves the page count and the pages' contents.
struct NotabilityPagePlacement {
    let geometry: NotabilityPageGeometry

    func isOnPage(_ pageNumber: Int, lowestY: Double, highestY: Double) -> Bool {
        guard let firstPage = geometry.pagePosition(ofVerticalPosition: lowestY),
              let lastPage = geometry.pagePosition(ofVerticalPosition: highestY) else { return false }
        return firstPage <= Double(pageNumber) && Double(pageNumber) <= lastPage
    }

    /// The number of pages content reaches: the page of the bottom of the ink and of the pictures' turned frames, at
    /// least 1; nil when the page height is not known.
    func pageCount(inkBottomY: Double?, pictures: [NotabilityPicture]) -> Int? {
        let pictureBottoms = pictures.map { picture in Self.verticalExtent(of: picture).highest }
        let bottomOfContent = ((inkBottomY.map { bottomY in [bottomY] } ?? []) + pictureBottoms + [0]).max() ?? 0
        return geometry.pagePosition(ofVerticalPosition: bottomOfContent).flatMap(NotabilityPageGeometry.pageNumber(fromPagePosition:))
    }

    /// From the top to the bottom of the picture as turned about its center.
    static func verticalExtent(of picture: NotabilityPicture) -> (lowest: Double, highest: Double) {
        let center = Double(picture.origin.y + picture.size.height / 2)
        let halfHeight = abs(Double(picture.size.width) / 2 * sin(picture.rotationRadiansClockwise))
            + abs(Double(picture.size.height) / 2 * cos(picture.rotationRadiansClockwise))
        return (center - halfHeight, center + halfHeight)
    }

    /// From the lowest to the highest of a shape's start, end and control point.
    static func verticalExtent(of shape: NotabilityShape) -> (lowest: Double, highest: Double) {
        let positions = [shape.start.y, shape.end.y] + (shape.quadraticControlPoint.map { point in [point.y] } ?? [])
        return (Double(positions.min() ?? 0), Double(positions.max() ?? 0))
    }
}
