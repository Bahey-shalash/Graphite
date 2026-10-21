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

    func testFolderCenterKeepsTheFramedPictureAlone() throws {
        let kept = try XCTUnwrap(FolderIconRenderer.keptPicture(FolderIconDesign(template: .folderCenter), picture: twoColorPicture(), folderArt: nil))
        XCTAssertEqual(kept.width, FolderIconRenderer.outputPixels)
        XCTAssertEqual(try pixel(of: kept, x: 10, yFromTop: 10), [255, 0, 0, 255])
        XCTAssertEqual(try pixel(of: kept, x: 500, yFromTop: 500), [0, 0, 255, 255])
    }

    func testARoundIconWithABackgroundIsTransparentOutsideTheCircle() throws {
        let zoomedOut = FolderPictureFraming(zoom: 0.5, horizontalOffset: 0, verticalOffset: 0)
        let design = FolderIconDesign(template: .round, framing: zoomedOut, background: CGColorComponents(red: 1, green: 1, blue: 1))
        let icon = try XCTUnwrap(FolderIconRenderer.icon(design, picture: twoColorPicture(), folderArt: nil, pixels: 200))
        XCTAssertEqual(try pixel(of: icon, x: 2, yFromTop: 2)[3], 0)
        XCTAssertEqual(try pixel(of: icon, x: 100, yFromTop: 30), [255, 255, 255, 255])
    }

    func testFolderFullFillsTheFrontFaceOverTheFolderArt() throws {
        let folderArt = try twoColorPicture(width: 100, height: 100)
        let green = try solidPicture(red: 0, green: 255, blue: 0)
        let icon = try XCTUnwrap(FolderIconRenderer.icon(FolderIconDesign(template: .folderFull), picture: green, folderArt: folderArt, pixels: 100))
        XCTAssertEqual(try pixel(of: icon, x: 50, yFromTop: 60), [0, 255, 0, 255])
        // Above the front face, the folder art shows.
        XCTAssertEqual(try pixel(of: icon, x: 10, yFromTop: 10), [255, 0, 0, 255])
    }

    func testRotationTurnsThePicture() throws {
        let turned = FolderIconDesign(template: .folderCenter, framing: FolderPictureFraming(zoom: 1, horizontalOffset: 0, verticalOffset: 0, rotationDegrees: 180))
        let kept = try XCTUnwrap(FolderIconRenderer.keptPicture(turned, picture: twoColorPicture(), folderArt: nil))
        XCTAssertEqual(try pixel(of: kept, x: 10, yFromTop: 10), [0, 0, 255, 255])
    }

    private func solidPicture(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        return try XCTUnwrap(context.makeImage())
    }

    func testPNGRoundTripAndBoundedDecoding() throws {
        let pngData = try FolderIconRenderer.pngData(of: twoColorPicture(width: 4_000, height: 1_000))
        let decoded = try XCTUnwrap(FolderIconRenderer.decodedPicture(from: pngData, maximumPixels: 400))
        XCTAssertEqual(max(decoded.width, decoded.height), 400)
        XCTAssertNil(FolderIconRenderer.decodedPicture(from: Data("not a picture".utf8)))
    }

    func testAPictureOnTheFolderSitsInTheBody() throws {
        let folder = try twoColorPicture(width: 100, height: 100)
        let square = try XCTUnwrap(FolderIconRenderer.keptPicture(FolderIconDesign(template: .folderCenter), picture: twoColorPicture(), folderArt: nil))
        let icon = try XCTUnwrap(FolderIconRenderer.finderIcon(picture: square, layout: .onFolder, folderIcon: folder))
        XCTAssertEqual(icon.width, 100)
        XCTAssertEqual(try pixel(of: icon, x: 5, yFromTop: 57), [255, 0, 0, 255])
        XCTAssertTrue(try FolderIconRenderer.finderIcon(picture: square, layout: .wholeIcon, folderIcon: folder) === square)
    }
}
