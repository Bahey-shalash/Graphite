import XCTest
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import GraphiteCore
@testable import GraphiteUI

/// A Live Preview embed keeps showing its drawing when its view is made again (scrolled
/// back into view, or the cursor leaving its line), and a changed file reaches the rendered
/// blocks in place rather than rebuilding them: rebuilt views blanked every drawing in the
/// note for a few frames after each save.
@MainActor
final class UiLivePreviewEmbedContinuityTests: XCTestCase {
    private var vault: URL!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("EmbedContinuity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func writeRedPNG(named name: String) throws -> URL {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let location = vault.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(location as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return location
    }

    /// The red, green and blue bytes of one pixel, counted from the top-left corner.
    private func colorComponents(of image: CGImage, x pixelColumn: Int, y pixelRow: Int) throws -> [UInt8] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -pixelColumn, y: pixelRow - image.height + 1, width: image.width, height: image.height))
        let pixelBytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 4)
        return (0..<3).map { componentIndex in pixelBytes[componentIndex] }
    }

    private func embedBlock(_ markdown: String) throws -> (block: LivePreviewBlock, embed: EmbedReference) {
        let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: markdown as NSString).first)
        guard case .embed(let embed) = block.kind else { throw XCTSkip("The scanner did not find an embed in \(markdown).") }
        return (block, embed)
    }

    /// A lookup that never ends, as the index can be slow to answer: what the view draws
    /// in its first frame cannot come from it.
    private func environment(drawingVersion: Int = 0) -> LivePreviewEnvironment {
        LivePreviewEnvironment(root: vault, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: drawingVersion,
                               resolve: { _, _ in
                                   try? await Task.sleep(for: .seconds(3_600))
                                   return nil
                               },
                               open: { _ in }, follow: { _, _ in }, updateProperties: nil)
    }

    /// The first frame of a new view of the block, 300 points wide.
    private func firstFrame(of block: LivePreviewBlock) throws -> CGImage {
        let renderer = ImageRenderer(content: LivePreviewWidgetView(block: block, environment: environment(), revealSource: {}, reportHeight: { _ in })
            .frame(width: 300))
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    func testANewViewOfAnEmbedShownBeforeDrawsItsPictureInItsFirstFrame() async throws {
        let location = try writeRedPNG(named: "Diagram.png")
        let (block, embed) = try embedBlock("![[Diagram.png]]")
        // What an earlier view of the embed left behind: the decoded picture and where it was found.
        _ = try await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: nil)
        LivePreviewEmbedImageLocations.remember(.init(path: try VaultPath("Diagram.png"), location: location), for: embed, in: vault)

        let rendered = try firstFrame(of: block)
        // The picture fills the column beside the source button, two to one, under 4 points of padding.
        XCTAssertGreaterThan(rendered.height, 100, "The first frame shows a progress indicator rather than the picture.")
        let middle = try colorComponents(of: rendered, x: 100, y: rendered.height / 2)
        XCTAssertGreaterThan(middle[0], 200)
        XCTAssertLessThan(middle[1], 60)
        XCTAssertLessThan(middle[2], 60)
    }

    /// The counterpart: an embed never shown has nothing to show while it is looked up.
    func testAnEmbedNotShownBeforeWaitsForItsLookup() async throws {
        let location = try writeRedPNG(named: "Unseen.png")
        _ = try await ReadingImageCache.shared.thumbnail(for: location, kind: .block, displayPixelWidth: nil)
        let (block, _) = try embedBlock("![[Unseen.png]]")

        let rendered = try firstFrame(of: block)
        XCTAssertLessThan(rendered.height, 100)
        let middle = try colorComponents(of: rendered, x: 100, y: rendered.height / 2)
        XCTAssertLessThan(middle[0], 200, "An embed never shown drew a picture before its lookup ended.")
    }

    func testAnEmbedThatNoLongerFindsItsImageForgetsIt() throws {
        let (_, embed) = try embedBlock("![[Removed.png]]")
        let foundImage = LivePreviewEmbedImageLocations.FoundImage(path: try VaultPath("Removed.png"), location: vault.appendingPathComponent("Removed.png"))
        LivePreviewEmbedImageLocations.remember(foundImage, for: embed, in: vault)
        XCTAssertEqual(LivePreviewEmbedImageLocations.foundImage(for: embed, in: vault), foundImage)

        let otherVault = vault.appendingPathComponent("Other")
        XCTAssertNil(LivePreviewEmbedImageLocations.foundImage(for: embed, in: otherVault), "Another vault's embed of the same name found this image.")

        LivePreviewEmbedImageLocations.forget(embed, in: vault)
        XCTAssertNil(LivePreviewEmbedImageLocations.foundImage(for: embed, in: vault))
    }

    func testTheRememberedImagesStartOverPastTheirLimit() throws {
        let (_, firstEmbed) = try embedBlock("![[First.png]]")
        let firstImage = LivePreviewEmbedImageLocations.FoundImage(path: try VaultPath("First.png"), location: vault.appendingPathComponent("First.png"))
        LivePreviewEmbedImageLocations.remember(firstImage, for: firstEmbed, in: vault)
        for embedNumber in 0..<LivePreviewEmbedImageLocations.maximumCount {
            let (_, embed) = try embedBlock("![[Image \(embedNumber).png]]")
            let foundImage = LivePreviewEmbedImageLocations.FoundImage(path: try VaultPath("Image \(embedNumber).png"),
                                                                       location: vault.appendingPathComponent("Image \(embedNumber).png"))
            LivePreviewEmbedImageLocations.remember(foundImage, for: embed, in: vault)
        }
        XCTAssertNil(LivePreviewEmbedImageLocations.foundImage(for: firstEmbed, in: vault), "The remembered images grew past their limit.")
    }

    /// A file changing (a drawing saved, or the note itself, whose own save the system reports
    /// back) changes only the drawing version of the blocks' signature, so the editor gives
    /// every block the new environment in place.
    func testAChangedFileChangesOnlyTheDrawingVersionOfTheSignature() {
        let beforeChange = LivePreviewWidgetSignature(environment: environment(drawingVersion: 4), accentHex: "#2d5da1", notePath: "Note.md")
        let afterChange = LivePreviewWidgetSignature(environment: environment(drawingVersion: 5), accentHex: "#2d5da1", notePath: "Note.md")
        XCTAssertEqual(beforeChange.appearance, afterChange.appearance)
        XCTAssertEqual(beforeChange.index, afterChange.index)
        XCTAssertNotEqual(beforeChange, afterChange)
    }
}
