import XCTest
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// Pins M-18: a save returns no drawing file unless the editing record read back from the
/// encoded bytes holds the strokes, pictures and paper it was written from. Each test plays
/// a broken encoder by writing a file whose record differs from what the save asked for.
final class DrawingEditingDataVerificationTests: XCTestCase {
    private let intended = DrawingPayload(width: 400, height: 200, background: .white, strokes: Data("pencil strokes".utf8),
                                          paper: DrawingPaper(pattern: .ruled, appearsInSavedDrawing: true))

    func testAFileWhoseRecordMatchesIsAcceptedInEveryFormat() throws {
        for format in DrawingFormat.allCases {
            let fileData = try encode(format: format, payload: intended)
            XCTAssertNoThrow(try DrawingMetadataReader.verifyEditingData(in: fileData, format: format, payload: intended), "\(format)")
        }
    }

    func testAFileWithOtherStrokesIsRefusedInEveryFormat() throws {
        let otherStrokes = DrawingPayload(width: 400, height: 200, background: .white, strokes: Data("other strokes".utf8), paper: intended.paper)
        for format in DrawingFormat.allCases {
            let fileData = try encode(format: format, payload: otherStrokes)
            XCTAssertThrowsError(try DrawingMetadataReader.verifyEditingData(in: fileData, format: format, payload: intended), "\(format)")
        }
    }

    func testAFileThatLostThePaperIsRefusedInEveryFormat() throws {
        let plainPaper = DrawingPayload(width: 400, height: 200, background: .white, strokes: intended.strokes)
        for format in DrawingFormat.allCases {
            let fileData = try encode(format: format, payload: plainPaper)
            XCTAssertThrowsError(try DrawingMetadataReader.verifyEditingData(in: fileData, format: format, payload: intended), "\(format)")
        }
    }

    func testAFileThatLostAPictureIsRefusedInEveryFormat() throws {
        let picture = DrawingBackgroundImage(imageData: try ImageEncoding.pngData(from: solidImage()), frame: CGRect(x: 10, y: 10, width: 40, height: 30))
        let withPicture = DrawingPayload(width: 400, height: 200, background: .white, strokes: intended.strokes, pictures: [picture], paper: intended.paper)
        for format in DrawingFormat.allCases {
            let fileData = try encode(format: format, payload: intended)
            XCTAssertThrowsError(try DrawingMetadataReader.verifyEditingData(in: fileData, format: format, payload: withPicture), "\(format)")
        }
    }

    func testAFileWithNoRecordIsRefusedInEveryFormat() throws {
        for format in DrawingFormat.allCases {
            let fileData = try encode(format: format, payload: nil)
            XCTAssertThrowsError(try DrawingMetadataReader.verifyEditingData(in: fileData, format: format, payload: intended), "\(format)")
        }
    }

    func testACutOffFileIsRefusedInEveryFormat() throws {
        for format in DrawingFormat.allCases {
            let fileData = try encode(format: format, payload: intended)
            let cutOff = fileData.prefix(fileData.count / 2)
            XCTAssertThrowsError(try DrawingMetadataReader.verifyEditingData(in: cutOff, format: format, payload: intended), "\(format)")
        }
    }

    private func encode(format: DrawingFormat, payload: DrawingPayload?) throws -> Data {
        let drawing = VectorDrawing(size: CGSize(width: 400, height: 200), background: .white, shapes: [])
        switch format {
        case .svg: return try SVGDrawingFile.encode(drawing, payload: payload)
        case .pdf: return try PDFDrawingFile.encode(drawing, payload: payload)
        case .png:
            let imageData = try ImageEncoding.pngData(from: solidImage())
            guard let payload else { return imageData }
            return try GraphitePNG.encode(imageData: imageData, drawing: payload)
        }
    }

    private func solidImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        return try XCTUnwrap(context.makeImage())
    }
}
