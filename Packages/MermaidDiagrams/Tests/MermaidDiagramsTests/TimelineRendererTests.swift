import XCTest
@testable import MermaidDiagrams

/// Pixels read back from a bitmap a timeline is drawn into, in Pele's colors on a white page.
final class TimelineRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func laidOut(_ source: String) throws -> TimelineLayout {
        TimelineLayoutEngine.layout(try TimelineReading.timeline(source), typography: typography)
    }

    private func drawn(_ layout: TimelineLayout, palette: DiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in TimelineRenderer.draw(layout, in: context, palette: palette) }
        return bitmap
    }

    private func assertColor(_ color: [Int], near expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.count, 3, file: file, line: line)
        for (channel, value) in zip(color, expected) { XCTAssertEqual(Double(channel), Double(value), accuracy: 2, "\(color)", file: file, line: line) }
    }

    /// White blended with a color at an event's tint.
    private func eventTint(_ red: Int, _ green: Int, _ blue: Int) -> [Int] {
        [red, green, blue].map { channel in Int((Double(channel) * 0.16 + 255 * 0.84).rounded()) }
    }

    private func beside(_ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + 3, y: frame.midY)
    }

    func testPeriodsAreFilledInTheSeriesColorsAndTheirEventsTinted() throws {
        let layout = try laidOut("timeline\n  2002 : LinkedIn\n  2004 : Facebook")
        let bitmap = try drawn(layout)
        assertColor(bitmap.color(at: beside(layout.periods[0].frame)), near: [0x4C, 0x78, 0xA8])
        assertColor(bitmap.color(at: beside(layout.periods[1].frame)), near: [0xF5, 0x85, 0x18])
        assertColor(bitmap.color(at: beside(layout.periods[0].events[0].frame)), near: eventTint(0x4C, 0x78, 0xA8))
        XCTAssertTrue(bitmap.hasPixel(in: layout.periods[0].events[0].text.frame, darkerThan: 0x80), "The event's text is drawn")
    }

    func testAPeriodsTextIsInTheBackgroundColorOnItsBox() throws {
        let layout = try laidOut("timeline\n  2002")
        let bitmap = try drawn(layout)
        let text = layout.periods[0].text.frame
        var hasLightPixel = false
        for y in Int(text.minY)..<Int(text.maxY) {
            for x in Int(text.minX)..<Int(text.maxX) where bitmap.color(at: CGPoint(x: x, y: y)).allSatisfy({ channel in channel > 0xE0 }) {
                hasLightPixel = true
            }
        }
        XCTAssertTrue(hasLightPixel)
    }

    func testTheAxisRunsBetweenTheDotsInTheLineColor() throws {
        let layout = try laidOut("timeline\n  2002\n  2004")
        let bitmap = try drawn(layout)
        let dots = layout.periods.map(\.dot)
        assertColor(bitmap.color(at: dots[0]), near: [0x4C, 0x78, 0xA8])
        let between = CGRect(x: (dots[0].x + dots[1].x) / 2 - 1, y: dots[0].y - 1.5, width: 2, height: 3)
        XCTAssertTrue(bitmap.hasPixel(in: between, darkerThan: 0x90))
        let tip = try XCTUnwrap(layout.axisArrow?.tip)
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: tip.x - 5, y: tip.y - 2, width: 4, height: 4), darkerThan: 0x90), "The arrow is filled")
    }

    func testSectionsTakeTheirColorAndPeriodsBeforeThemAreMuted() throws {
        let layout = try laidOut("timeline\n  early\n  section One\n  later")
        let bitmap = try drawn(layout)
        assertColor(bitmap.color(at: beside(layout.periods[0].frame)), near: [0x6E, 0x6E, 0x6E])
        assertColor(bitmap.color(at: beside(layout.sections[0].frame)), near: [0x4C, 0x78, 0xA8])
        assertColor(bitmap.color(at: beside(layout.periods[1].frame)), near: [0x4C, 0x78, 0xA8])
    }

    func testOtherSeriesColorsChangeOnlyTheColors() throws {
        let layout = try laidOut("timeline\n  2002")
        var palette = DiagramPalette.peleLight
        palette.series = [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)]
        assertColor(try drawn(layout, palette: palette).color(at: beside(layout.periods[0].frame)), near: [0xFF, 0, 0])
    }

    func testATimelineDownHasItsEventsBesideItsPeriods() throws {
        let layout = try laidOut("timeline TD\n  2002 : LinkedIn")
        let bitmap = try drawn(layout)
        let event = layout.periods[0].events[0].frame
        XCTAssertGreaterThan(event.minX, layout.periods[0].frame.maxX)
        assertColor(bitmap.color(at: beside(event)), near: eventTint(0x4C, 0x78, 0xA8))
    }
}
