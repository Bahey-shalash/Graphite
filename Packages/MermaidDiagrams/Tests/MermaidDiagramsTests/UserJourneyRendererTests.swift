import XCTest
@testable import MermaidDiagrams

/// A user journey drawn into a bitmap at one pixel per point, its pixels read back: the cards, bands, faces, dots,
/// scale and stems in their colors.
final class UserJourneyRendererTests: XCTestCase {
    private static let palette = DiagramPalette(background: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                                foreground: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                                line: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                                surface: CGColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1),
                                                border: CGColor(srgbRed: 0.54, green: 0.54, blue: 0.54, alpha: 1),
                                                alternateSurface: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))

    private func drawn(_ source: String, palette: DiagramPalette = palette) throws -> (UserJourneyLayout, DiagramBitmap) {
        let layout = try UserJourneyReading.uniformLayout(source)
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in UserJourneyRenderer.draw(layout, in: context, palette: palette) }
        return (layout, bitmap)
    }

    private func assertColor(_ color: [Int], is expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.count, 3, file: file, line: line)
        for (channel, value) in zip(color, expected) { XCTAssertEqual(Double(channel), Double(value), accuracy: 3, file: file, line: line) }
    }

    func testCardsAreFilledInTheSurfaceAndOutlinedInTheBorderColor() throws {
        let (layout, bitmap) = try drawn(UserJourneyReading.workingDay)
        let card = layout.tasks[0].frame
        assertColor(bitmap.color(at: CGPoint(x: card.minX + 4, y: card.midY)), is: [242, 242, 242])
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: card.minX - 1, y: card.midY - 2, width: 2, height: 4), darkerThan: 200))
        XCTAssertFalse(bitmap.hasPixel(in: CGRect(x: card.minX - 4, y: card.midY - 2, width: 2, height: 4), darkerThan: 250))
    }

    func testBandsAreFilledInTheSecondSurface() throws {
        let (layout, bitmap) = try drawn(UserJourneyReading.workingDay)
        let band = layout.sections[1].frame
        assertColor(bitmap.color(at: CGPoint(x: band.minX + 4, y: band.midY)), is: [0, 0, 255])
    }

    func testEachFaceShowsItsMood() throws {
        let (layout, bitmap) = try drawn("journey\n  happy: 5\n  neutral: 3\n  sad: 1")
        func hasMouth(_ task: Int, depth: CGFloat) -> Bool {
            let center = layout.tasks[task].faceCenter
            return bitmap.hasPixel(in: CGRect(x: center.x + 3.5, y: center.y + depth - 1, width: 2, height: 2), darkerThan: 200)
        }
        XCTAssertEqual([0, 1, 2].map { task in hasMouth(task, depth: 2) }, [true, false, false], "A smile's corners")
        XCTAssertEqual([0, 1, 2].map { task in hasMouth(task, depth: 6.5) }, [false, false, true], "A frown's corners")
        let neutral = layout.tasks[1].faceCenter
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: neutral.x - 1, y: neutral.y + 4, width: 2, height: 1.5), darkerThan: 200))
        XCTAssertFalse(bitmap.hasPixel(in: CGRect(x: neutral.x - 1, y: neutral.y + 7, width: 2, height: 2), darkerThan: 250), "The face is filled")
    }

    func testActorsDotsAreInTheirSeriesColors() throws {
        let (layout, bitmap) = try drawn(UserJourneyReading.workingDay)
        let doWork = layout.tasks[2].actorDots
        assertColor(bitmap.color(at: doWork[0].center), is: [245, 133, 24])
        assertColor(bitmap.color(at: doWork[1].center), is: [76, 120, 168])
        assertColor(bitmap.color(at: layout.legend[0].dot.center), is: [76, 120, 168])
    }

    func testTheScaleIsInTheSecondSurfaceAndTheStemsAreDashed() throws {
        let (layout, bitmap) = try drawn("journey\n  a: 5\n  b: 1")
        let level = layout.scaleLevels[1].line.start
        let scale = CGRect(x: level.x + 1, y: level.y - 1, width: 3, height: 2)
        let scalePixels = (Int(scale.minY)..<Int(scale.maxY)).flatMap { row in
            (Int(scale.minX)..<Int(scale.maxX)).map { column in bitmap.color(at: CGPoint(x: column, y: row)) }
        }
        XCTAssertTrue(scalePixels.contains { color in color[2] > 200 && color[0] < 160 }, "A bluish pixel of the scale's line")
        let task = layout.tasks[0]
        let stemPixels = (Int(task.frame.maxY) + 1..<Int(task.faceCenter.y - 12)).map { row in
            [CGFloat(-0.5), 0.5].map { offset in bitmap.color(at: CGPoint(x: task.frame.midX + offset, y: CGFloat(row)))[0] }.min() ?? 255
        }
        XCTAssertTrue(stemPixels.contains { level in level < 220 }, "Drawn")
        XCTAssertTrue(stemPixels.contains { level in level > 245 }, "With gaps")
    }

    func testTheTitleAndTheTextAreDrawn() throws {
        let (layout, bitmap) = try drawn(UserJourneyReading.workingDay)
        XCTAssertTrue(bitmap.hasPixel(in: try XCTUnwrap(layout.title).frame, darkerThan: 100))
        XCTAssertTrue(bitmap.hasPixel(in: layout.tasks[0].text.frame, darkerThan: 100))
        XCTAssertTrue(bitmap.hasPixel(in: layout.legend[1].text.frame, darkerThan: 100))
    }

    func testTheSameLayoutPaintsInAnotherPalette() throws {
        var dark = Self.palette
        dark.surface = CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        let (layout, light) = try drawn(UserJourneyReading.workingDay)
        let (_, darkBitmap) = try drawn(UserJourneyReading.workingDay, palette: dark)
        let inside = CGPoint(x: layout.tasks[0].frame.minX + 4, y: layout.tasks[0].frame.midY)
        assertColor(light.color(at: inside), is: [242, 242, 242])
        assertColor(darkBitmap.color(at: inside), is: [51, 51, 51])
    }
}
