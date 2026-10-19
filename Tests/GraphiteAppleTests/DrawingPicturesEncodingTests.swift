import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteApple

/// How a picture to draw on, and a picture edited on a drawing or a PDF page, is prepared:
/// orientation applied, at most two pixels per point, JPEG at 0.9 for an opaque picture and PNG
/// for one with transparency, and edited pictures staying JPEG (0.92) or PNG.
final class DrawingPicturesEncodingTests: XCTestCase {
    private static let jpegSignature: [UInt8] = [0xFF, 0xD8]
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    /// A bitmap of varied colours, so its JPEG size depends on the quality it is written at.
    private static func bitmap(width: Int, height: Int, hasAlpha: Bool) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let alphaInfo = hasAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: alphaInfo.rawValue))
        var state: UInt32 = 12_345
        for row in stride(from: 0, to: height, by: 4) {
            for column in stride(from: 0, to: width, by: 4) {
                state = state &* 1_664_525 &+ 1_013_904_223
                context.setFillColor(CGColor(srgbRed: CGFloat(state >> 24 & 0xFF) / 255, green: CGFloat(state >> 16 & 0xFF) / 255,
                                             blue: CGFloat(state >> 8 & 0xFF) / 255, alpha: 1))
                context.fill(CGRect(x: column, y: row, width: 4, height: 4))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private static func encoded(_ image: CGImage, as type: UTType, quality: Double? = nil, orientation: Int? = nil) throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        if let orientation { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func pixelSize(of data: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return CGSize(width: try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), height: try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    func testTheSharpnessAndQualityConstantsAreTwoPixelsPerPointAndNinetyAndNinetyTwoPercent() {
        XCTAssertEqual(DrawingPictures.pixelsPerPoint, 2)
        XCTAssertEqual(DrawingPictures.photographQuality, 0.9)
        XCTAssertEqual(PictureEditing.photographQuality, 0.92)
    }

    func testAnOpaquePictureIsPreparedAsAJPEGAndOneWithTransparencyAsAPNG() throws {
        let opaque = try Self.encoded(try Self.bitmap(width: 64, height: 32, hasAlpha: false), as: .png)
        let transparent = try Self.encoded(try Self.bitmap(width: 64, height: 32, hasAlpha: true), as: .png)
        XCTAssertTrue(try DrawingPictures.picture(from: opaque, canvasWidth: 100).imageData.starts(with: Self.jpegSignature))
        XCTAssertTrue(try DrawingPictures.picture(from: transparent, canvasWidth: 100).imageData.starts(with: Self.pngSignature))
    }

    func testAPictureIsKeptAtNoMoreThanTwoPixelsPerPointOfTheCanvasAndIsNeverEnlarged() throws {
        let large = try Self.encoded(try Self.bitmap(width: 1_200, height: 600, hasAlpha: false), as: .jpeg, quality: 0.5)
        let reduced = try DrawingPictures.picture(from: large, canvasWidth: 200)
        XCTAssertEqual(reduced.frame, CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(try Self.pixelSize(of: reduced.imageData), CGSize(width: 400, height: 200), "Two pixels per point of the canvas width.")

        let small = try Self.encoded(try Self.bitmap(width: 60, height: 30, hasAlpha: false), as: .png)
        let kept = try DrawingPictures.picture(from: small, canvasWidth: 200)
        XCTAssertEqual(kept.frame, CGRect(x: 0, y: 0, width: 200, height: 100), "It is shown across the canvas all the same.")
        XCTAssertEqual(try Self.pixelSize(of: kept.imageData), CGSize(width: 60, height: 30), "A small picture keeps its pixels.")

        let tall = try Self.encoded(try Self.bitmap(width: 300, height: 900, hasAlpha: false), as: .png)
        let tallPicture = try DrawingPictures.picture(from: tall, canvasWidth: 100)
        XCTAssertEqual(tallPicture.frame, CGRect(x: 0, y: 0, width: 100, height: 300))
        XCTAssertEqual(try Self.pixelSize(of: tallPicture.imageData), CGSize(width: 200, height: 600), "The longer side is the one limited to two pixels per point.")
    }

    func testThePicturesOrientationIsAppliedBeforeItIsSizedAndSaved() throws {
        // Stored 200 wide and 100 tall; orientation 6 shows it turned a quarter, 100 wide and 200 tall.
        let turned = try Self.encoded(try Self.bitmap(width: 200, height: 100, hasAlpha: false), as: .jpeg, quality: 0.8, orientation: 6)
        let picture = try DrawingPictures.picture(from: turned, canvasWidth: 50)
        XCTAssertEqual(picture.frame, CGRect(x: 0, y: 0, width: 50, height: 100), "The frame follows the displayed shape.")
        XCTAssertEqual(try Self.pixelSize(of: picture.imageData), CGSize(width: 100, height: 200), "The pixels are turned, not only labelled.")
        let upright = try DrawingPictures.picture(from: try Self.encoded(try Self.bitmap(width: 200, height: 100, hasAlpha: false), as: .jpeg, quality: 0.8, orientation: 1),
                                                  canvasWidth: 50)
        XCTAssertEqual(upright.frame, CGRect(x: 0, y: 0, width: 50, height: 25))
    }

    func testAnEditedJPEGStaysAJPEGWrittenAtNinetyTwoPercentAndAnEditedPNGStaysAPNG() throws {
        let image = try Self.bitmap(width: 80, height: 40, hasAlpha: false)
        let photograph = try Self.encoded(image, as: .jpeg, quality: 0.5)
        let cropped = try PictureEditing.cropped(photograph, to: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertTrue(cropped.starts(with: Self.jpegSignature))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(photograph as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(cropped, try Self.encoded(decoded, as: .jpeg, quality: 0.92), "The picture is written again at 0.92.")
        XCTAssertNotEqual(cropped, try Self.encoded(decoded, as: .jpeg, quality: 0.9), "Not the 0.9 of a picture prepared to draw on.")

        let turned = try PictureEditing.rotatedClockwise(photograph)
        XCTAssertTrue(turned.starts(with: Self.jpegSignature))
        XCTAssertEqual(try Self.pixelSize(of: turned), CGSize(width: 40, height: 80))

        let transparent = try Self.encoded(try Self.bitmap(width: 80, height: 40, hasAlpha: true), as: .png)
        let turnedPNG = try PictureEditing.rotatedClockwise(transparent)
        XCTAssertTrue(turnedPNG.starts(with: Self.pngSignature))
        XCTAssertEqual(try Self.pixelSize(of: turnedPNG), CGSize(width: 40, height: 80))
        XCTAssertTrue(try PictureEditing.cropped(transparent, to: CGRect(x: 0, y: 0, width: 0.5, height: 1)).starts(with: Self.pngSignature))
    }
}
