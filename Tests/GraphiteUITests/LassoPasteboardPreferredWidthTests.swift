#if canImport(UIKit)
import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import GraphiteUI

/// The width, in points, a pasted image is given before it is kept to the space there is: a
/// screenshot taken here keeps its point size, an image with a resolution above 72 dots per
/// inch its size on paper, and any other half its pixels.
@MainActor
final class LassoPasteboardPreferredWidthTests: XCTestCase {
    private func imageData(width: Int, height: Int, type: UTType = .png, dotsPerInch: Double? = nil, orientation: Int? = nil) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(UIColor.systemTeal.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [:]
        if let dotsPerInch {
            properties[kCGImagePropertyDPIWidth] = dotsPerInch
            properties[kCGImagePropertyDPIHeight] = dotsPerInch
        }
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testAnImageWithoutAResolutionIsPastedAtHalfItsPixels() throws {
        XCTAssertEqual(LassoPasteboard.preferredWidth(ofImageData: try imageData(width: 410, height: 100)), 205)
    }

    func testAnImageWithAResolutionAboveSeventyTwoIsPastedAtItsSizeOnPaper() throws {
        XCTAssertEqual(try XCTUnwrap(LassoPasteboard.preferredWidth(ofImageData: try imageData(width: 400, height: 100, type: .jpeg, dotsPerInch: 144))), 200, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(LassoPasteboard.preferredWidth(ofImageData: try imageData(width: 420, height: 100, type: .jpeg, dotsPerInch: 72))), 210, accuracy: 0.01,
                       "Seventy-two itself is no stated resolution: half the pixels.")
    }

    func testAScreenshotTakenHereKeepsItsPointSizeWhateverItsScale() throws {
        let screenshot = UIGraphicsImageRenderer(size: CGSize(width: 111, height: 222), format: { () -> UIGraphicsImageRendererFormat in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            return format
        }()).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 111, height: 222))
        }
        LassoPasteboard.rememberScreenshot(screenshot)
        XCTAssertEqual(LassoPasteboard.preferredWidth(ofImageData: try imageData(width: 333, height: 666)), 111, "333 pixels taken at 3 per point.")
        XCTAssertEqual(LassoPasteboard.preferredWidth(ofImageData: try imageData(width: 333, height: 665)), 166.5, "Another height is another image.")
    }

    func testATurnedImagesWidthIsItsStoredHeight() throws {
        XCTAssertEqual(LassoPasteboard.preferredWidth(ofImageData: try imageData(width: 300, height: 800, type: .jpeg, orientation: 6)), 400, "Shown turned, the 800 stored rows are its width.")
    }

    func testBytesThatAreNoImageHaveNoPreferredWidth() {
        XCTAssertNil(LassoPasteboard.preferredWidth(ofImageData: Data("not an image".utf8)))
    }
}
#endif
