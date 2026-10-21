import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import GraphiteApple

final class PictureFileEncodingTests: XCTestCase {
    private func picture(type: UTType) throws -> Data {
        var pixels = [UInt8](repeating: 200, count: 40 * 20 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testJPEGPNGAndGIFAreKeptByteForByte() throws {
        for (type, fileExtension) in [(UTType.jpeg, "jpg"), (UTType.png, "png"), (UTType.gif, "gif")] {
            let original = try picture(type: type)
            let contents = try XCTUnwrap(PictureFileEncoding.fileContents(of: original), fileExtension)
            XCTAssertEqual(contents.data, original, fileExtension)
            XCTAssertEqual(contents.fileExtension, fileExtension)
        }
    }

    func testAPictureOfAnotherTypeIsStoredAsJPEG() throws {
        let contents = try XCTUnwrap(PictureFileEncoding.fileContents(of: try picture(type: .tiff)))
        XCTAssertEqual(contents.fileExtension, "jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(contents.data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    }

    func testSomethingThatIsNotAPictureIsRefused() {
        XCTAssertNil(PictureFileEncoding.fileContents(of: Data("text".utf8)))
    }

    func testACameraImageBecomesJPEG() throws {
        var pixels = [UInt8](repeating: 120, count: 16 * 16 * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = try XCTUnwrap(PictureFileEncoding.jpegData(of: try XCTUnwrap(context.makeImage())))
        XCTAssertEqual(PictureFileEncoding.fileContents(of: data)?.fileExtension, "jpg")
    }
}
