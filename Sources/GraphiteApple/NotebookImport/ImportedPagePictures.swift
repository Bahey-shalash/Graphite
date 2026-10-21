import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore
import NotebookImport

/// Puts a page's imported pictures on its PDF page as Graphite's own pictures (`PDFPicture`, invariant M-14), in the
/// plan's order, before the page's ink is added, so the ink stays over them (M-15). Each picture's file is read,
/// prepared (`ImportedPictureImage`) and placed in turn, and its bitmaps are released before the next one.
///
/// A picture whose file the notebook cannot give is left out and counted in the page's report, as the planner counts
/// one the notebook does not list, and so is a file that is not an image ImageIO decodes, as a damaged one; a picture
/// the plan places badly, or one too large even made smaller, is a typed error.
enum ImportedPagePictures {
    /// The pictures of a page left out as it was written.
    struct LeftOut: Equatable {
        var missingFileCount = 0
        var notDecodableCount = 0
    }

    private enum Placement {
        case placed, fileMissing, notDecodable
    }

    /// Places the pictures and returns how many were left out, and why.
    static func place(_ pictures: [ImportedPicture], onPageAt pageIndex: Int, of document: PDFDocument, pageSize: CGSize,
                      sourceFiles: any ImportSourceFiles) throws -> LeftOut {
        var leftOut = LeftOut()
        guard !pictures.isEmpty, let page = document.page(at: pageIndex) else { return leftOut }
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: pageSize)
        for picture in pictures {
            let placement = try autoreleasepool {
                try place(picture, onPageAt: pageIndex, of: document, coordinates: coordinates, sourceFiles: sourceFiles)
            }
            switch placement {
            case .placed: break
            case .fileMissing: leftOut.missingFileCount += 1
            case .notDecodable: leftOut.notDecodableCount += 1
            }
        }
        return leftOut
    }

    /// The page's report with the pictures left out here: missing files added to the planner's count of them, and
    /// pictures that could not be decoded.
    static func report(_ entries: [ImportReportEntry], adding leftOut: LeftOut) -> [ImportReportEntry] {
        var merged = entries
        if leftOut.missingFileCount > 0 {
            if let entryIndex = merged.firstIndex(where: { entry in if case .pictureFilesMissing = entry { true } else { false } }),
               case .pictureFilesMissing(let plannedCount) = merged[entryIndex] {
                merged[entryIndex] = .pictureFilesMissing(count: plannedCount + leftOut.missingFileCount)
            } else {
                merged.append(.pictureFilesMissing(count: leftOut.missingFileCount))
            }
        }
        if leftOut.notDecodableCount > 0 { merged.append(.picturesNotDecodable(count: leftOut.notDecodableCount)) }
        return merged
    }

    private static func place(_ picture: ImportedPicture, onPageAt pageIndex: Int, of document: PDFDocument, coordinates: PageCoordinates,
                              sourceFiles: any ImportSourceFiles) throws -> Placement {
        let frame = picture.frame
        guard [frame.minX, frame.minY, frame.width, frame.height, picture.rotationRadiansClockwise].allSatisfy(\.isFinite),
              frame.width > 0, frame.height > 0 else {
            throw NotebookImportWriterError.pictureGeometryUnusable(picture.file, frame: frame, rotationRadiansClockwise: picture.rotationRadiansClockwise,
                                                                    pageIndex: pageIndex)
        }
        let fileContents: Data
        do {
            fileContents = try sourceFiles.contents(of: picture.file)
        } catch {
            // The reader's error says only that the file is not there to read; the picture is reported as missing.
            return .fileMissing
        }
        guard let imageData = try preparedImageData(fileContents, for: picture, pageIndex: pageIndex) else { return .notDecodable }
        let pdfPicture = PDFPicture(imageData: imageData, bounds: pageBounds(of: frame, coordinates: coordinates), quarterTurns: 0,
                                    rotationRadians: picture.rotationRadiansClockwise)
        try PDFPageManager.apply(.addPicture(page: pageIndex, picture: pdfPicture), to: document, drawsInkOutlines: true)
        return .placed
    }

    /// Nil when the file is not an image ImageIO decodes.
    private static func preparedImageData(_ fileBytes: Data, for picture: ImportedPicture, pageIndex: Int) throws -> Data? {
        do throws(ImportedPictureImage.Failure) {
            return try ImportedPictureImage.imageData(fromFile: fileBytes, for: picture)
        } catch .notDecodable {
            return nil
        } catch .cropUnusable {
            throw NotebookImportWriterError.pictureCropUnusable(picture.file, cropRectangleInPixels: picture.cropRectangleInPixels ?? .null,
                                                                pageIndex: pageIndex)
        } catch .tooLarge(let byteCount) {
            throw NotebookImportWriterError.pictureTooLarge(picture.file, byteCount: byteCount, pageIndex: pageIndex)
        }
    }

    /// The upright frame in PDF page space: the same center, mapped from the plan's top-left page points, and the
    /// same size scaled with the page. Turning about the center is the same clockwise turn in both spaces.
    private static func pageBounds(of frame: CGRect, coordinates: PageCoordinates) -> CGRect {
        let center = coordinates.pdfPoint(fromOverlay: CGPoint(x: frame.midX, y: frame.midY))
        let width = frame.width * coordinates.cropBox.width / coordinates.overlaySize.width
        let height = frame.height * coordinates.cropBox.height / coordinates.overlaySize.height
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }
}
