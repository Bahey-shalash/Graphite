import CoreGraphics
import Foundation

/// Plans one Goodnotes picture (`Docs/Goodnotes-format.md`, Pictures): its attachment's file drawn stretched to the
/// placement's size, centered on the placement's center and turned clockwise about it by the placement's angle.
/// Goodnotes units are 6/11 of a point with the page's origin and direction, so the frame is the unit frame times
/// 6/11. A picture cropped in Goodnotes already names a file of the kept part, so no crop is planned.
enum GoodnotesPicturePlanner {
    /// The picture to place, or nil when the notebook does not have its file, which is counted. An animated GIF is
    /// counted too: the PDF keeps its first frame.
    static func picture(for picture: GoodnotesPicture, tally: inout ImportReportTally) -> ImportedPicture? {
        guard let file = picture.attachment?.file else {
            tally.count(.pictureFileMissing)
            return nil
        }
        if picture.kind == .animatedGIF { tally.count(.animatedPicture) }
        let pointsPerUnit = GoodnotesPagePlanner.pointsPerUnit
        let width = picture.size.width * pointsPerUnit, height = picture.size.height * pointsPerUnit
        let frame = CGRect(x: picture.center.x * pointsPerUnit - width / 2, y: picture.center.y * pointsPerUnit - height / 2,
                           width: width, height: height)
        return ImportedPicture(file: ImportedSourceFile(path: file), frame: frame, rotationRadiansClockwise: picture.rotationRadians,
                               cropRectangleInPixels: nil, isFlippedHorizontally: false, isFlippedVertically: false)
    }
}
