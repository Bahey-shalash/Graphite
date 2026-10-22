import XCTest
@testable import MermaidDiagrams

final class SequenceDrawingPartsTests: XCTestCase {
    private func parts(_ body: String) throws -> (SequenceLayout, SequenceDrawingParts) {
        let layout = try SequenceUniformLayout.layout("sequenceDiagram\n" + body)
        return (layout, SequenceDrawingParts(layout: layout))
    }

    func testMessagesAreGroupedByStrokeAndHead() throws {
        let (_, solidOnly) = try parts("A->>B: x\nA-xB: y")
        XCTAssertFalse(solidOnly.solidMessageLines.isEmpty)
        XCTAssertTrue(solidOnly.dottedMessageLines.isEmpty)
        XCTAssertFalse(solidOnly.filledHeads.isEmpty, "The arrow")
        XCTAssertFalse(solidOnly.strokedHeads.isEmpty, "The cross")
        let (_, dottedOpen) = try parts("A--)B: x\nB-->A: y")
        XCTAssertTrue(dottedOpen.solidMessageLines.isEmpty)
        XCTAssertFalse(dottedOpen.dottedMessageLines.isEmpty)
        XCTAssertTrue(dottedOpen.filledHeads.isEmpty, "An open head is stroked")
        XCTAssertFalse(dottedOpen.strokedHeads.isEmpty)
    }

    func testAnOpenHeadReachesItsTipFromBehind() throws {
        let (layout, drawing) = try parts("A-)B: x")
        let head = try XCTUnwrap(layout.messages[0].heads.first)
        let bounds = drawing.strokedHeads.boundingBoxOfPath
        XCTAssertEqual(bounds.maxX, head.tip.x, accuracy: 0.01)
        XCTAssertEqual(bounds.width, 8, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 9, accuracy: 0.01)
    }

    func testParticipantsAreBoxesAndActorsHeadsAndLimbs() throws {
        let (layout, drawing) = try parts("participant A\nactor B")
        XCTAssertTrue(drawing.participantShapes.boundingBoxOfPath.contains(layout.participants[0].frame.insetBy(dx: 1, dy: 1)))
        let figure = layout.headers[1].frame
        XCTAssertEqual(drawing.participantFigureLines.boundingBoxOfPath.minY, figure.minY + 13, accuracy: 0.01)
        XCTAssertEqual(drawing.participantFigureLines.boundingBoxOfPath.maxY, layout.footers[1].frame.minY + 34, accuracy: 0.01)
        XCTAssertEqual(drawing.participantTexts.count, 4)
    }

    func testBlocksGiveTheirFramesSectionsTabsAndTexts() throws {
        let (layout, drawing) = try parts("alt yes\nA->>B: x\nelse no\nB->>A: y\nend")
        let block = try XCTUnwrap(layout.blocks.first)
        XCTAssertEqual(drawing.blockOutlines.boundingBoxOfPath, block.frame)
        XCTAssertEqual(drawing.blockSectionLines.boundingBoxOfPath.minY, block.sections[0].lineY, accuracy: 0.01)
        XCTAssertEqual(drawing.blockTabs.boundingBoxOfPath, block.tab)
        XCTAssertEqual(drawing.blockKeywords.map(\.lines), [["alt"]])
        XCTAssertEqual(drawing.blockTexts.map(\.lines), [["[yes]"], ["[no]"]])
    }

    func testHighlightsKeepTheirOrderAndColors() throws {
        let (_, drawing) = try parts("rect aqua\nrect\nA->>B: x\nend\nend")
        XCTAssertEqual(drawing.highlights.map(\.color), [SequenceHighlightColor(red: 0, green: 1, blue: 1), nil])
    }

    func testNumbersGiveBadgesAndTexts() throws {
        let (_, drawing) = try parts("autonumber\nA->>B: x\nB->>A: y")
        XCTAssertEqual(drawing.numberTexts.map(\.lines), [["1"], ["2"]])
        XCTAssertFalse(drawing.numberBadges.isEmpty)
    }

    func testTheMixedRolesSitBetweenTheBackgroundAndTheForeground() {
        let muted = SequenceRenderer.mixed(CGColor(gray: 1, alpha: 1), CGColor(srgbRed: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255, alpha: 1),
                                           share: SequenceDrawingParts.mutedShare)
        XCTAssertEqual((muted.components?.first ?? 0) * 255, 0x6E, accuracy: 0.5)
    }
}
