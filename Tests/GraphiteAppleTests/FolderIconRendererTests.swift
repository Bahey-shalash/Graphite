import XCTest
import ImageIO
import GraphiteCore
@testable import GraphiteApple

final class FolderIconRendererTests: XCTestCase {
    /// A wide picture, red on its left half and blue on its right.
    private func twoColorPicture(width: Int = 200, height: Int = 100) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(of image: CGImage, x: Int, yFromTop: Int) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = (yFromTop * image.width + x) * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }

    func testFramedPictureFillsASquare() throws {
        let framed = try XCTUnwrap(FolderIconRenderer.framedPicture(twoColorPicture(), framing: .filling, layout: .onFolder, background: .none))
        XCTAssertEqual(framed.width, FolderIconRenderer.outputPixels)
        XCTAssertEqual(framed.height, FolderIconRenderer.outputPixels)
        XCTAssertEqual(try pixel(of: framed, x: 10, yFromTop: 10), [255, 0, 0, 255])
        XCTAssertEqual(try pixel(of: framed, x: 500, yFromTop: 500), [0, 0, 255, 255])
    }

    func testAWholeIconWithABackgroundHasRoundedCorners() throws {
        let zoomedOut = FolderPictureFraming(zoom: 0.5, horizontalOffset: 0, verticalOffset: 0)
        let framed = try XCTUnwrap(FolderIconRenderer.framedPicture(twoColorPicture(), framing: zoomedOut, layout: .wholeIcon, background: .white))
        XCTAssertEqual(try pixel(of: framed, x: 1, yFromTop: 1)[3], 0)
        XCTAssertEqual(try pixel(of: framed, x: 256, yFromTop: 20), [255, 255, 255, 255])
    }

    func testPNGRoundTripAndBoundedDecoding() throws {
        let pngData = try FolderIconRenderer.pngData(of: twoColorPicture(width: 4_000, height: 1_000))
        let decoded = try XCTUnwrap(FolderIconRenderer.decodedPicture(from: pngData, maximumPixels: 400))
        XCTAssertEqual(max(decoded.width, decoded.height), 400)
        XCTAssertNil(FolderIconRenderer.decodedPicture(from: Data("not a picture".utf8)))
    }

    func testAPictureOnTheFolderSitsInTheBody() throws {
        let folder = try twoColorPicture(width: 100, height: 100)
        let square = try XCTUnwrap(FolderIconRenderer.framedPicture(twoColorPicture(), framing: .filling, layout: .onFolder, background: .none))
        let icon = try XCTUnwrap(FolderIconRenderer.finderIcon(picture: square, layout: .onFolder, folderIcon: folder))
        XCTAssertEqual(icon.width, 100)
        XCTAssertEqual(try pixel(of: icon, x: 5, yFromTop: 57), [255, 0, 0, 255])
        XCTAssertTrue(try FolderIconRenderer.finderIcon(picture: square, layout: .wholeIcon, folderIcon: folder) === square)
    }
}
