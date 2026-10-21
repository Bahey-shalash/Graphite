import XCTest
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

final class AppleFolderArtTests: XCTestCase {
    private func art(_ style: FolderStyle) async throws -> CGImage {
        let directory = try TemporaryVault.make(prefix: "AppleFolderArt", for: self).root
        let image = await AppleFolderArt(standInDirectory: directory).art(for: style, picture: nil, pixels: 64)
        return try XCTUnwrap(image)
    }

    /// The average hue of the opaque pixels, from 0 to 1.
    private func averageHue(of image: CGImage) throws -> Double {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for pixelIndex in 0..<(image.width * image.height) where bytes[pixelIndex * 4 + 3] == 255 {
            red += Double(bytes[pixelIndex * 4]); green += Double(bytes[pixelIndex * 4 + 1]); blue += Double(bytes[pixelIndex * 4 + 2]); count += 1
        }
        let components = [red / count, green / count, blue / count].map { component in component / 255 }
        let maximum = components.max() ?? 0, minimum = components.min() ?? 0
        guard maximum > minimum else { return 0 }
        let delta = maximum - minimum
        let hue: Double = if maximum == components[0] { (components[1] - components[2]) / delta }
            else if maximum == components[1] { 2 + (components[2] - components[0]) / delta }
            else { 4 + (components[0] - components[1]) / delta }
        return (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
    }

    func testAColorAloneIsApplesTintedFolder() async throws {
        let plain = try await art(FolderStyle())
        let green = try await art(FolderStyle(color: .green))
        XCTAssertEqual(try averageHue(of: plain), 0.58, accuracy: 0.05)
        XCTAssertEqual(try averageHue(of: green), 0.37, accuracy: 0.06)
    }

    func testAColorNoTagHasIsTintedToIt() async throws {
        let purple = try await art(FolderStyle(color: .custom(red: 140, green: 40, blue: 200)))
        XCTAssertEqual(try averageHue(of: purple), 0.77, accuracy: 0.05)
    }
}
