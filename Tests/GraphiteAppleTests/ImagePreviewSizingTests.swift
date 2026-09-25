import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import GraphiteApple

/// Embeds are decoded at the width they are shown at rather than a fixed longest side, and
/// never larger than the longest side allows.
final class ImagePreviewSizingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePreviewSizing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bitmap(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// Writes an image file with an independent encoder, optionally with an EXIF orientation.
    private func writeImage(width: Int, height: Int, named name: String, type: UTType, orientation: Int? = nil) throws -> URL {
        let location = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, type.identifier as CFString, 1, nil))
        let properties = orientation.map { orientation in [kCGImagePropertyOrientation: orientation] as CFDictionary }
        CGImageDestinationAddImage(destination, try bitmap(width: width, height: height), properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return location
    }

    private func writePDF(pageWidth: Double, pageHeight: Double, named name: String) throws -> URL {
        let location = directory.appendingPathComponent(name)
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: pageWidth - 40, height: pageHeight - 40))
        context.endPDFPage()
        context.closePDF()
        return location
    }

    func testAWideImageIsDecodedAtTheWidthItIsShownAt() async throws {
        let location = try writeImage(width: 800, height: 400, named: "Wide.png", type: .png)
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 2400, displayPixelWidth: 200))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 100)
    }

    func testATallImageKeepsItsDisplayWidth() async throws {
        let location = try writeImage(width: 400, height: 800, named: "Tall.png", type: .png)
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 2400, displayPixelWidth: 200))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 400)
    }

    func testTheLongestSideStillBoundsAVeryTallImage() async throws {
        let location = try writeImage(width: 200, height: 2000, named: "Strip.png", type: .png)
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 1000, displayPixelWidth: 150))
        XCTAssertEqual(image.height, 1000)
        XCTAssertEqual(image.width, 100)
    }

    func testAnImageNarrowerThanItsDisplayWidthIsNotEnlarged() async throws {
        let location = try writeImage(width: 80, height: 40, named: "Small.png", type: .png)
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 2400, displayPixelWidth: 1520))
        XCTAssertEqual(image.width, 80)
        XCTAssertEqual(image.height, 40)
    }

    /// A phone photo stored wide but turned upright by its EXIF orientation is shown tall,
    /// so it needs the longer side a tall image needs.
    func testAQuarterTurnedPhotoIsSizedAsItIsShown() async throws {
        let location = try writeImage(width: 800, height: 400, named: "Upright.jpg", type: .jpeg, orientation: 6)
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 2400, displayPixelWidth: 200))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 400)
    }

    func testAPDFPageIsRenderedAtTheWidthItIsShownAt() async throws {
        let location = try writePDF(pageWidth: 400, pageHeight: 800, named: "Drawing.pdf")
        let image = try await ImageFileService().displayImage(at: location, limit: PreviewPixelLimit(maximumPixelDimension: 2400, displayPixelWidth: 200))
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 400)
    }

    func testWithoutADisplayWidthOnlyTheLongestSideIsBounded() async throws {
        let location = try writeImage(width: 800, height: 400, named: "Unbounded.png", type: .png)
        let image = try await ImageFileService().displayImage(at: location, maximumPixelDimension: 300)
        XCTAssertEqual(image.width, 300)
        XCTAssertEqual(image.height, 150)
    }

    func testLongestSideFollowsTheImageShape() {
        let limit = PreviewPixelLimit(maximumPixelDimension: 2400, displayPixelWidth: 1520)
        XCTAssertEqual(limit.longestPixelSide(forWidth: 4032, height: 3024), 1520)
        XCTAssertEqual(limit.longestPixelSide(forWidth: 3024, height: 4032), 2027)
        XCTAssertEqual(limit.longestPixelSide(forWidth: 1480, height: 6000), 2400)
        XCTAssertEqual(limit.longestPixelSide(forWidth: 0, height: 100), 2400)
        XCTAssertEqual(limit.longestPixelSide(forWidth: .nan, height: 100), 2400)
        XCTAssertEqual(PreviewPixelLimit(maximumPixelDimension: 2400).longestPixelSide(forWidth: 4032, height: 3024), 2400)
    }

    func testLimitsStayWithinWhatAPreviewCanUse() {
        XCTAssertEqual(PreviewPixelLimit(maximumPixelDimension: 10).maximumPixelDimension, PreviewPixelLimit.smallestPixelDimension)
        XCTAssertEqual(PreviewPixelLimit(maximumPixelDimension: 100_000).maximumPixelDimension, PreviewPixelLimit.largestPixelDimension)
        XCTAssertEqual(PreviewPixelLimit(maximumPixelDimension: 2400, displayPixelWidth: 1).longestPixelSide(forWidth: 100, height: 100),
                       PreviewPixelLimit.smallestPixelDimension)
    }
}
