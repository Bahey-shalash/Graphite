import XCTest
@testable import MermaidDiagrams

/// Text is uniform: a participant's 8 points a character (24 high), a message's or note's 7 (21 high), a tab's
/// keyword or a number 6 (18 high).
final class SequenceLayoutEngineTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ body: String) throws -> SequenceLayout {
        try SequenceUniformLayout.layout("sequenceDiagram\n" + body)
    }

    // MARK: Participants

    func testParticipantsSitSideBySideTheGapApartAndAreMirroredBelow() throws {
        let laidOut = try layout("participant A\nparticipant B")
        XCTAssertEqual(laidOut.participants.count, 4)
        XCTAssertEqual(laidOut.headers.map(\.frame.size), [CGSize(width: 64, height: 44), CGSize(width: 64, height: 44)])
        XCTAssertEqual(laidOut.headers[1].frame.minX - laidOut.headers[0].frame.maxX, 40, accuracy: accuracy)
        XCTAssertEqual(laidOut.headers[0].frame.minX, 8, accuracy: accuracy, "Pele's padding")
        for (header, footer) in zip(laidOut.headers, laidOut.footers) { XCTAssertEqual(header.frame.midX, footer.frame.midX, accuracy: accuracy) }
        for (lifeline, header) in zip(laidOut.lifelines, laidOut.headers) {
            XCTAssertEqual(lifeline.x, header.frame.midX, accuracy: accuracy)
            XCTAssertEqual(lifeline.top, header.frame.maxY, accuracy: accuracy)
        }
        XCTAssertEqual(laidOut.lifelines[0].bottom, laidOut.footers[0].frame.minY, accuracy: accuracy)
        XCTAssertEqual(laidOut.size, CGSize(width: 184, height: 8 + 44 + 6 + 20 + 44 + 8))
    }

    func testAParticipantWidensToItsTextAndAnActorStandsAboveIts() throws {
        let laidOut = try layout("participant A as A participant with a long name\nactor B as Bob")
        XCTAssertEqual(laidOut.headers[0].frame.width, 30 * 8 + 32, accuracy: accuracy)
        XCTAssertEqual(laidOut.headers[1].kind, .actor)
        XCTAssertEqual(laidOut.headers[1].frame.size, CGSize(width: 40, height: 34 + 4 + 24))
        XCTAssertEqual(laidOut.headers[1].text.center.y, laidOut.headers[1].frame.minY + 34 + 4 + 12, accuracy: accuracy)
        XCTAssertEqual(laidOut.headers[0].frame.maxY, laidOut.headers[1].frame.maxY, accuracy: accuracy, "Bottoms in line")
    }

    // MARK: Messages

    func testAMessageRunsFromLifelineToLifelineItsTextAboveIt() throws {
        let laidOut = try layout("A->>B: Hi")
        let message = try XCTUnwrap(laidOut.messages.first)
        let (left, right) = (laidOut.lifelineXs[0], laidOut.lifelineXs[1])
        XCTAssertEqual(message.path.start.x, left, accuracy: accuracy)
        XCTAssertEqual(message.path.end.x, right - 7, accuracy: accuracy, "The line stops where the arrow begins")
        XCTAssertEqual(message.heads, [SequenceLayoutArrowhead(kind: .arrow, tip: CGPoint(x: right, y: message.path.start.y), direction: CGVector(dx: 1, dy: 0))])
        let text = try XCTUnwrap(message.text)
        XCTAssertEqual(text.center.x, (left + right) / 2, accuracy: accuracy)
        XCTAssertEqual(text.frame.maxY, message.path.start.y - 4, accuracy: accuracy)
        XCTAssertEqual(message.path.start.y, laidOut.lifelines[0].top + 6 + 14 + 21 + 2, accuracy: accuracy)
        XCTAssertNil(message.textPatch, "No lifeline runs through the text")
    }

    func testAMessageBackPointsLeftAndOneWithoutHeadReachesTheLifeline() throws {
        let laidOut = try layout("A->>B: Hi\nB-->A: Back\nA<<->>B: Both")
        let back = laidOut.messages[1]
        XCTAssertEqual(back.stroke, .dotted)
        XCTAssertTrue(back.heads.isEmpty)
        XCTAssertEqual(back.path.end.x, laidOut.lifelineXs[0], accuracy: accuracy)
        let both = laidOut.messages[2]
        XCTAssertEqual(both.heads.map(\.direction), [CGVector(dx: -1, dy: 0), CGVector(dx: 1, dy: 0)])
        XCTAssertEqual(both.path.start.x, laidOut.lifelineXs[0] + 7, accuracy: accuracy)
    }

    func testEachHeadTakesItsPartOfTheLine() throws {
        let laidOut = try layout("A-xB: x\nA-)B: y")
        XCTAssertEqual(laidOut.messages[0].path.end.x, laidOut.lifelineXs[1] - 4, accuracy: accuracy)
        XCTAssertEqual(laidOut.messages[0].heads.first?.kind, .cross)
        XCTAssertEqual(laidOut.messages[1].path.end.x, laidOut.lifelineXs[1], accuracy: accuracy)
        XCTAssertEqual(laidOut.messages[1].heads.first?.kind, .open)
    }

    func testRowsFollowEachOtherDown() throws {
        let laidOut = try layout("A->>B: one\nB->>A: two\nA->>B: three")
        let rows = laidOut.messages.map(\.path.start.y)
        XCTAssertEqual(rows[1] - rows[0], 14 + 21 + 2, accuracy: accuracy)
        XCTAssertEqual(rows[2] - rows[1], 14 + 21 + 2, accuracy: accuracy)
    }

    func testALongMessageWidensTheGapAndOneAcrossSeveralSharesWhatItLacks() throws {
        let wide = try layout("A->>B: \(String(repeating: "x", count: 30))")
        XCTAssertEqual(wide.lifelineXs[1] - wide.lifelineXs[0], 30 * 7 + 2 * 12 + 10, accuracy: accuracy)
        let across = try layout("participant A\nparticipant B\nparticipant C\nA->>C: \(String(repeating: "x", count: 40))")
        let gaps = [across.lifelineXs[1] - across.lifelineXs[0], across.lifelineXs[2] - across.lifelineXs[1]]
        XCTAssertEqual(gaps[0], gaps[1], accuracy: accuracy)
        XCTAssertEqual(gaps[0] + gaps[1], 40 * 7 + 2 * 12 + 10, accuracy: accuracy)
        XCTAssertNotNil(across.messages[0].textPatch, "B's lifeline runs through the text")
    }

    func testAMessageToItselfLoopsOutToTheRightWithItsTextBeside() throws {
        let laidOut = try layout("A->>A: Think")
        let message = laidOut.messages[0]
        let points = message.path.allPoints
        let lifeline = laidOut.lifelineXs[0]
        XCTAssertEqual(points.map(\.x).max() ?? 0, lifeline + 28, accuracy: accuracy)
        XCTAssertEqual(message.path.end.y - message.path.start.y, 22, accuracy: accuracy)
        XCTAssertEqual(message.heads.first?.tip, CGPoint(x: lifeline, y: message.path.end.y))
        XCTAssertEqual(message.heads.first?.direction, CGVector(dx: -1, dy: 0))
        let text = try XCTUnwrap(message.text)
        XCTAssertEqual(text.frame.minX, lifeline + 28 + 8, accuracy: accuracy)
    }

    func testWrappedTextWrapsAtTheWrappingWidth() throws {
        let laidOut = try layout("A->>B:wrap: \(Array(repeating: "word", count: 12).joined(separator: " "))\nNote over A:wrap: \(Array(repeating: "note", count: 12).joined(separator: " "))")
        XCTAssertGreaterThan(laidOut.messages[0].text?.lines.count ?? 0, 1)
        XCTAssertLessThanOrEqual(laidOut.notes[0].text.size.width, 160)
        XCTAssertGreaterThan(laidOut.notes[0].text.lines.count, 1)
        XCTAssertEqual(try layout("A->>B: \(Array(repeating: "word", count: 12).joined(separator: " "))").messages[0].text?.lines.count, 1)
    }

    // MARK: Activations

    func testAnActivationWidensTheLifelineAndArrowsStopAtItsEdge() throws {
        let laidOut = try layout("A->>+B: Ask\nB-->>-A: Answer")
        let activation = try XCTUnwrap(laidOut.activations.first)
        let lifeline = laidOut.lifelineXs[1]
        XCTAssertEqual(activation.minX, lifeline - 5, accuracy: accuracy)
        XCTAssertEqual(activation.width, 10, accuracy: accuracy)
        XCTAssertEqual(activation.minY, laidOut.messages[0].path.start.y, accuracy: accuracy)
        XCTAssertEqual(activation.maxY, laidOut.messages[1].path.start.y, accuracy: accuracy)
        XCTAssertEqual(laidOut.messages[0].heads.first?.tip.x ?? 0, lifeline - 5, accuracy: accuracy)
        XCTAssertEqual(laidOut.messages[1].path.start.x, lifeline - 5, accuracy: accuracy)
    }

    func testNestedActivationsStepRightTheInnerOneOnTopAndAnOpenOneEndsUnderTheLastRow() throws {
        let laidOut = try layout("A->>B: one\nactivate B\nactivate B\nB->>A: two\ndeactivate B")
        XCTAssertEqual(laidOut.activations.count, 2)
        XCTAssertEqual(laidOut.activations[1].minX - laidOut.activations[0].minX, 4, accuracy: accuracy, "The inner one, drawn last, steps right")
        XCTAssertEqual(laidOut.activations[0].maxY, laidOut.lifelines[1].bottom, accuracy: accuracy)
        XCTAssertGreaterThanOrEqual(laidOut.activations[1].height, 14)
    }

    // MARK: Notes

    func testNotesSitBesideOrOverTheirLifelines() throws {
        let laidOut = try layout("A->>B: Hi\nNote right of A: r\nNote left of A: l\nNote over B: o\nNote over A,B: across")
        let (left, right) = (laidOut.lifelineXs[0], laidOut.lifelineXs[1])
        XCTAssertEqual(laidOut.notes[0].frame.minX, left + 10, accuracy: accuracy)
        XCTAssertEqual(laidOut.notes[1].frame.maxX, left - 10, accuracy: accuracy)
        XCTAssertEqual(laidOut.notes[2].frame.midX, right, accuracy: accuracy)
        XCTAssertEqual(laidOut.notes[3].frame.minX, left - 16, accuracy: accuracy)
        XCTAssertEqual(laidOut.notes[3].frame.maxX, right + 16, accuracy: accuracy)
        XCTAssertEqual(laidOut.notes[0].frame.height, 21 + 12, accuracy: accuracy)
        XCTAssertEqual(laidOut.notes[0].frame.width, 7 + 20, accuracy: accuracy)
        XCTAssertGreaterThan(laidOut.notes[1].frame.minY, laidOut.notes[0].frame.maxY, "Each note has its own row")
    }

    func testANoteBesideAnActiveLifelineMovesPastTheActivation() throws {
        let laidOut = try layout("A->>+B: Hi\nNote right of B: r\nB-->>-A: Bye")
        XCTAssertEqual(laidOut.notes[0].frame.minX, laidOut.lifelineXs[1] + 5 + 10, accuracy: accuracy)
    }

    // MARK: Blocks

    func testABlockFramesWhatItHoldsWithItsTabAndTitle() throws {
        let laidOut = try layout("A->>B: Hi\nloop Each\nB->>A: Again\nend")
        let block = try XCTUnwrap(laidOut.blocks.first)
        XCTAssertEqual(block.frame.minX, laidOut.lifelineXs[0] - 20, accuracy: accuracy)
        XCTAssertEqual(block.frame.maxX, laidOut.lifelineXs[1] + 20, accuracy: accuracy)
        XCTAssertEqual(block.tab, CGRect(x: block.frame.minX, y: block.frame.minY, width: 4 * 6 + 14, height: 20))
        XCTAssertEqual(block.keyword.lines, ["loop"])
        XCTAssertEqual(block.keyword.fontSize, 12)
        XCTAssertEqual(block.title?.lines, ["[Each]"])
        XCTAssertEqual(block.title?.frame.minX ?? 0, block.tab.maxX + 8, accuracy: accuracy)
        XCTAssertGreaterThan(laidOut.messages[1].path.start.y, block.frame.minY + 20)
        XCTAssertEqual(block.frame.maxY, laidOut.messages[1].path.start.y + 12, accuracy: accuracy)
        XCTAssertGreaterThan(block.frame.minY, laidOut.messages[0].path.start.y)
    }

    func testSectionsHaveADashedLineAndTheirTextBetweenTheirMessages() throws {
        let laidOut = try layout("alt is sick\nB->>A: Not so good\nelse is well\nB->>A: Fresh\nend")
        let block = try XCTUnwrap(laidOut.blocks.first)
        XCTAssertEqual(block.keyword.lines, ["alt"])
        let section = try XCTUnwrap(block.sections.first)
        XCTAssertEqual(section.text?.lines, ["[is well]"])
        XCTAssertGreaterThan(section.lineY, laidOut.messages[0].path.start.y)
        XCTAssertLessThan(section.text?.frame.maxY ?? .infinity, laidOut.messages[1].text?.frame.minY ?? 0)
    }

    func testABlockWidensToTheRightForItsTitle() throws {
        let laidOut = try layout("opt \(String(repeating: "t", count: 40))\nA->>B: x\nend")
        let block = try XCTUnwrap(laidOut.blocks.first)
        XCTAssertEqual(block.frame.maxX, (block.title?.frame.maxX ?? 0) + 2 * 8, accuracy: accuracy)
        XCTAssertEqual(block.frame.minX, laidOut.lifelineXs[0] - 20, accuracy: accuracy)
    }

    func testANestedBlockSitsInsideTheOneAroundIt() throws {
        let laidOut = try layout("par outer\nloop inner\nA->>B: x\nend\nend")
        XCTAssertEqual(laidOut.blocks.count, 2)
        let (inner, outer) = (laidOut.blocks[0], laidOut.blocks[1])
        XCTAssertEqual(inner.keyword.lines, ["loop"], "The inner block closes first")
        XCTAssertEqual(inner.frame.minX - outer.frame.minX, 10, accuracy: accuracy)
        XCTAssertGreaterThan(inner.frame.minY, outer.frame.minY)
        XCTAssertLessThan(inner.frame.maxY, outer.frame.maxY)
    }

    func testAHighlightShadesWhatItHoldsInItsColorTheInnerOneOnTop() throws {
        let laidOut = try layout("rect rgb(0, 0, 255)\nrect\nA->>B: x\nend\nend")
        XCTAssertEqual(laidOut.highlights.map(\.color), [SequenceHighlightColor(red: 0, green: 0, blue: 1), nil])
        XCTAssertTrue(laidOut.highlights[0].frame.contains(laidOut.highlights[1].frame))
        XCTAssertEqual(laidOut.highlights[1].frame.minX, laidOut.lifelineXs[0] - 20, accuracy: accuracy)
        XCTAssertTrue(laidOut.blocks.isEmpty)
    }

    // MARK: Numbers, title and limits

    func testAutonumberPutsANumberAtTheTailOfEachMessage() throws {
        let laidOut = try layout("autonumber\nA->>B: one\nNote over A: no number\nB->>A: two\nautonumber off\nA->>B: three")
        XCTAssertEqual(laidOut.messages.map { message in message.number?.text.lines }, [["1"], ["2"], nil])
        let first = try XCTUnwrap(laidOut.messages[0].number)
        XCTAssertEqual(first.frame.midX, laidOut.lifelineXs[0], accuracy: accuracy)
        XCTAssertEqual(first.frame.size, CGSize(width: 16, height: 16))
        XCTAssertEqual(laidOut.messages[0].path.start.x, laidOut.lifelineXs[0] + 8, accuracy: accuracy, "The line starts past the badge")
    }

    func testAutonumberCountsFromItsStartByItsStep() throws {
        let laidOut = try layout("autonumber 10.01 .01\nA->>B: one\nB->>A: two\nA->>B: three\nautonumber 100 50\nA->>B: four\nA->>B: five")
        XCTAssertEqual(laidOut.messages.compactMap { message in message.number?.text.lines.first }, ["10.01", "10.02", "10.03", "100", "150"])
        XCTAssertEqual(laidOut.messages[3].number?.frame.width ?? 0, 3 * 6 + 8, accuracy: accuracy)
    }

    func testTheTitleIsCenteredAboveTheDiagram() throws {
        let laidOut = try layout("title Plan\nA->>B: x")
        let title = try XCTUnwrap(laidOut.title)
        XCTAssertEqual(title.center.x, (laidOut.headers[0].frame.minX + laidOut.headers[1].frame.maxX) / 2, accuracy: accuracy)
        XCTAssertEqual(title.frame.minY, 8, accuracy: accuracy)
        XCTAssertEqual(laidOut.headers[0].frame.minY, 8 + 24 + 12, accuracy: accuracy)
    }

    func testAnEmptyDiagramHasRoomAndNothingInIt() throws {
        let laidOut = try SequenceUniformLayout.layout("sequenceDiagram")
        XCTAssertTrue(laidOut.participants.isEmpty)
        XCTAssertEqual(laidOut.size, CGSize(width: 40 + 16, height: 6 + 20 + 16))
    }

    func testStatementsNotLaidOutAreRefused() {
        XCTAssertThrowsError(try layout("box Group\nparticipant A\nend")) { error in
            XCTAssertEqual(error as? SequenceLayoutError, .statementsNotLaidOut([.box]))
        }
    }

    func testEverythingDrawnIsInsideTheSize() throws {
        let laidOut = try layout("""
            title A title wider than the diagram itself, by far
            autonumber
            actor A
            A->>+B: Hello
            Note left of A: left
            loop Every minute
                B->>B: Think it over
                Note right of B: right
            end
            alt yes
                B-->>-A: Fine
            else no
                B--xA: Lost
            end
            Note over A,B: across
            """)
        let page = CGRect(origin: .zero, size: laidOut.size)
        var frames = laidOut.participants.map(\.frame) + laidOut.notes.map(\.frame) + laidOut.blocks.map(\.frame) + laidOut.activations
        frames += laidOut.messages.compactMap { message in message.text?.frame } + [laidOut.title?.frame].compactMap { frame in frame }
        for frame in frames { XCTAssertTrue(page.contains(frame), "\(frame) is inside \(page)") }
        for message in laidOut.messages { XCTAssertTrue(message.path.allPoints.allSatisfy(page.contains)) }
    }
}
