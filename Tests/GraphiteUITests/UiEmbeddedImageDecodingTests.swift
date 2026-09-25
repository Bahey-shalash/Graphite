import XCTest
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI

/// Reading view and Live Preview decode an embedded image once, off the main thread, at
/// the width it is shown at, and draw those pixels without decoding them again.
@MainActor
final class UiEmbeddedImageDecodingTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EmbeddedImageDecoding-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bitmap(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func writePNG(width: Int, height: Int, named name: String) throws -> URL {
        let location = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try bitmap(width: width, height: height, red: 0.2, green: 0.4, blue: 0.8), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return location
    }

    /// The red, green and blue bytes of one pixel, counted from the top-left corner.
    private func colorComponents(of image: CGImage, x pixelColumn: Int, y pixelRow: Int) throws -> [UInt8] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Core Graphics counts rows from the bottom, so the image is moved to put the pixel
        // at the context's only pixel.
        context.draw(image, in: CGRect(x: -pixelColumn, y: pixelRow - image.height + 1, width: image.width, height: image.height))
        let pixelBytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 4)
        return (0..<3).map { componentIndex in pixelBytes[componentIndex] }
    }

    func testDisplayWidthIsTheNarrowerOfTheColumnAndTheEmbedsSize() {
        let column = ReadingConfiguration.readableColumnWidth
        XCTAssertEqual(EmbeddedImageDisplayWidth.pixelWidth(columnWidth: column, displaySize: nil, displayScale: 2), 1520)
        XCTAssertEqual(EmbeddedImageDisplayWidth.pixelWidth(columnWidth: column, displaySize: EmbedDisplaySize(width: 300, height: nil), displayScale: 2), 600)
        XCTAssertEqual(EmbeddedImageDisplayWidth.pixelWidth(columnWidth: nil, displaySize: EmbedDisplaySize(width: 300, height: 100), displayScale: 3), 900)
        // A column as wide as the window leaves only the longest side to bound the image.
        XCTAssertNil(EmbeddedImageDisplayWidth.pixelWidth(columnWidth: nil, displaySize: nil, displayScale: 2))
        // Wider than the longest side a block image may have: that side bounds it anyway.
        XCTAssertEqual(EmbeddedImageDisplayWidth.pixelWidth(columnWidth: 1400, displaySize: nil, displayScale: 2), ReadingThumbnailKind.block.maximumDimension)
        // A view not yet on a screen reports no scale; it is decoded again once it is.
        XCTAssertEqual(EmbeddedImageDisplayWidth.pixelWidth(columnWidth: column, displaySize: nil, displayScale: 0), 760)
    }

    func testBlockThumbnailIsDecodedForTheWidthItIsShownAt() async throws {
        let cache = ReadingImageCache()
        let location = try writePNG(width: 800, height: 400, named: "Photo.png")
        let columnThumbnail = try await cache.thumbnail(for: location, kind: .block, displayPixelWidth: 200)
        XCTAssertEqual(columnThumbnail.image.width, 200)
        XCTAssertEqual(columnThumbnail.image.height, 100)
        XCTAssertEqual(columnThumbnail.aspectRatio, 2)

        let unboundedThumbnail = try await cache.thumbnail(for: location, kind: .block)
        XCTAssertEqual(unboundedThumbnail.image.width, 800)

        // Each width keeps its own decoded image, so neither is shown blurred or oversized.
        XCTAssertTrue(cache.lastThumbnail(for: location, kind: .block, displayPixelWidth: 200)?.image === columnThumbnail.image)
        XCTAssertTrue(cache.lastThumbnail(for: location, kind: .block)?.image === unboundedThumbnail.image)
        XCTAssertNil(cache.lastThumbnail(for: location, kind: .block, displayPixelWidth: 300))
    }

    /// A drawing grows downward, so it is far taller than wide; it is decoded at the
    /// column's width, not squeezed into a longest side meant for a wide photo.
    func testATallImageIsDecodedAtTheColumnsWidth() async throws {
        let cache = ReadingImageCache()
        let location = try writePNG(width: 300, height: 1200, named: "Derivation.png")
        let thumbnail = try await cache.thumbnail(for: location, kind: .block, displayPixelWidth: 150)
        XCTAssertEqual(thumbnail.image.width, 150)
        XCTAssertEqual(thumbnail.image.height, 600)
        XCTAssertEqual(thumbnail.aspectRatio, 0.25)
    }

    /// The decoded image is drawn in the first render, with no decoding step in between:
    /// encoded data would first show a placeholder while it decodes.
    func testDecodedEmbedDrawsItsImageInTheFirstRender() throws {
        let image = try bitmap(width: 40, height: 20, red: 1, green: 0, blue: 0)
        let renderer = ImageRenderer(content: EmbeddedImageView(image: image, aspectRatio: 2, displayWidth: 100, edit: nil, view: nil).frame(width: 100))
        renderer.scale = 1
        let rendered = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(rendered.width, 100)
        XCTAssertEqual(rendered.height, 50)
        let center = try colorComponents(of: rendered, x: 50, y: 25)
        XCTAssertGreaterThan(center[0], 200)
        XCTAssertLessThan(center[1], 60)
        XCTAssertLessThan(center[2], 60)
    }
}
