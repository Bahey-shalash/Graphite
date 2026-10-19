import XCTest
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

final class PaperPreviewRendererTests: XCTestCase {
    func testPictureKeepsThePagesProportions() throws {
        let landscape = PaperSpecification(template: .dotted).sized(NotebookPageSize.a4.pointSize(in: .landscape))
        let image = try PaperPreviewRenderer.image(of: landscape, longerSidePixels: 200)
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 141)
    }

    func testPictureSizeIsBounded() throws {
        let image = try PaperPreviewRenderer.image(of: PaperSpecification(template: .blank), longerSidePixels: 50_000)
        XCTAssertEqual(max(image.width, image.height), PaperPreviewRenderer.maximumSidePixels)
    }

    func testBlankPaperIsOneColorAndRuledPaperIsNot() throws {
        XCTAssertEqual(try distinctColorCount(of: PaperSpecification(template: .blank)), 1)
        XCTAssertGreaterThan(try distinctColorCount(of: PaperSpecification(template: .ruled)), 1)
    }

    func testPaperColorIsDrawn() throws {
        let ivory = PaperSpecification(template: .blank, paperColorHex: "#fbf7ea")
        let pixel = try cornerPixel(of: try PaperPreviewRenderer.image(of: ivory, longerSidePixels: 64))
        XCTAssertEqual(pixel.red, 0xfb, accuracy: 2)
        XCTAssertEqual(pixel.green, 0xf7, accuracy: 2)
        XCTAssertEqual(pixel.blue, 0xea, accuracy: 2)
    }

    func testAnInvalidPaperIsAnErrorNotAPicture() {
        let tooSmall = PaperSpecification(template: .blank).sized(CGSize(width: 10, height: 10))
        XCTAssertThrowsError(try PaperPreviewRenderer.image(of: tooSmall, longerSidePixels: 64))
    }

    private func pixels(of image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    private func distinctColorCount(of paper: PaperSpecification) throws -> Int {
        let bytes = try pixels(of: try PaperPreviewRenderer.image(of: paper, longerSidePixels: 256))
        var colors = Set<UInt32>()
        for pixelStart in stride(from: 0, to: bytes.count, by: 4) {
            colors.insert(UInt32(bytes[pixelStart]) << 16 | UInt32(bytes[pixelStart + 1]) << 8 | UInt32(bytes[pixelStart + 2]))
        }
        return colors.count
    }

    private func cornerPixel(of image: CGImage) throws -> (red: Double, green: Double, blue: Double) {
        let bytes = try pixels(of: image)
        return (Double(bytes[0]), Double(bytes[1]), Double(bytes[2]))
    }
}
