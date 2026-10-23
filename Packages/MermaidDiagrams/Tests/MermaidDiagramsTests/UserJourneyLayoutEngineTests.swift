import XCTest
@testable import MermaidDiagrams

/// The user journey laid out with Pele's measurements, with text of fixed widths: cards 7 points a character at 14
/// points (21-point lines), the scale's numbers 6 at 12, the title 8 at 16.
final class UserJourneyLayoutEngineTests: XCTestCase {
    private let taskText = UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21)
    private let scaleText = UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18)
    private let titleText = UniformWidthTextMeasurer()

    private func layout(_ source: String) throws -> UserJourneyLayout {
        UserJourneyLayoutEngine.layout(try UserJourneyReading.userJourney(source), taskText: taskText, scaleText: scaleText, titleText: titleText,
                                       font: DiagramFont(postScriptName: nil, size: 16))
    }

    private static let workingDay = """
    journey
      title My working day
      section Go to work
        Make tea: 5: Me
        Go upstairs: 3: Me
        Do work: 1: Me, Cat
      section Go home
        Go downstairs: 5: Me
        Sit down: 5: Me
    """

    func testCardsStandSideBySideAtTheNarrowestWidth() throws {
        let tasks = try layout("journey\n  a: 5\n  b: 3\n  c: 1").tasks
        XCTAssertEqual(tasks.map(\.frame.width), [144, 144, 144], "124 points of text and 10 on each side")
        XCTAssertEqual(tasks[1].frame.minX - tasks[0].frame.maxX, 12)
        XCTAssertEqual(Set(tasks.map(\.frame.minY)).count, 1)
        XCTAssertEqual(tasks[0].frame.height, 21 + 16, "A line of text and 8 points above and below, with no actor named")
    }

    func testEachFaceSitsAtItsScoreOneLevelApart() throws {
        let faces = try layout("journey\n  a: 5\n  b: 4\n  c: 3\n  d: 2\n  e: 1\n").tasks.map(\.faceCenter.y)
        XCTAssertEqual(zip(faces.dropFirst(), faces).map { lower, upper in lower - upper }, [26, 26, 26, 26])
    }

    func testScoresOutOfTheScaleAreKeptOnItAndNotANumberIsInTheMiddle() throws {
        let tasks = try layout("journey\n  top: 5\n  mid: 3\n  low: 1\n  big: 100\n  neg: -7\n  zero: 0\n"
                               + "  word: abc\n  blank: \n  half: 3.5\n  inf: Infinity\n").tasks
        let (top, middle, low) = (tasks[0].faceCenter.y, tasks[1].faceCenter.y, tasks[2].faceCenter.y)
        XCTAssertEqual(tasks.dropFirst(3).map(\.faceCenter.y), [top, low, low, middle, low, (top + middle) / 2 + (middle - top) / 4, top])
        XCTAssertEqual(tasks.map(\.mood), [.happy, .neutral, .sad, .happy, .sad, .sad, .neutral, .sad, .happy, .happy])
    }

    func testAStemRunsFromTheCardToTheTopOfItsFaceAndALineJoinsTheFaces() throws {
        let layout = try layout("journey\n  a: 5\n  b: 1")
        for task in layout.tasks {
            XCTAssertEqual(task.stem.start, CGPoint(x: task.frame.midX, y: task.frame.maxY))
            XCTAssertEqual(task.stem.segments, [.line(to: CGPoint(x: task.frame.midX, y: task.faceCenter.y - 11))])
        }
        XCTAssertEqual(layout.scoreLine, DiagramPath(start: layout.tasks[0].faceCenter, segments: [.line(to: layout.tasks[1].faceCenter)]))
        XCTAssertNil(try self.layout("journey\n  alone: 3").scoreLine)
    }

    func testTheScaleHasALineAndANumberAtEachLevelLeftOfTheCards() throws {
        let layout = try layout("journey\n  a: 5\n  b: 1")
        XCTAssertEqual(layout.scaleLevels.map(\.score), [5, 4, 3, 2, 1])
        let firstCard = layout.tasks[0].frame
        for level in layout.scaleLevels {
            XCTAssertEqual(level.line.start.x, firstCard.minX - 6)
            XCTAssertEqual(level.line.segments, [.line(to: CGPoint(x: layout.tasks[1].frame.maxX, y: level.line.start.y))])
            XCTAssertEqual(level.text.frame.maxX, firstCard.minX - 12)
            XCTAssertEqual(level.text.center.y, level.line.start.y)
        }
        XCTAssertEqual(layout.scaleLevels.first?.line.start.y, layout.tasks[0].faceCenter.y)
        XCTAssertEqual(layout.scaleLevels.last?.line.start.y, layout.tasks[1].faceCenter.y)
        XCTAssertEqual(layout.scaleLevels[0].line.start.y - layout.tasks[0].frame.maxY, 11 + 16, "A face's radius and 16 points below the cards")
    }

    func testABandSpansItsRunOfTasksAndEmptyOrMissingSectionsHaveNone() throws {
        let layout = try layout("journey\n  first: 3\n  section A\n  section B\n    b1: 3\n    b2: 3\n  section C\n    c1: 3\n  section D\n")
        XCTAssertEqual(layout.sections.map(\.text.lines), [["B"], ["C"]])
        let band = layout.sections[0].frame
        XCTAssertEqual(band.minX, layout.tasks[1].frame.minX)
        XCTAssertEqual(band.maxX, layout.tasks[2].frame.maxX)
        XCTAssertEqual(band.height, 21 + 12, "A line of text and 6 points above and below")
        XCTAssertEqual(layout.tasks[1].frame.minY - band.maxY, 6)
        XCTAssertEqual(layout.tasks[0].frame.minY, layout.tasks[1].frame.minY)
    }

    func testSectionsOfOneNameInARowMakeOneBand() throws {
        let layout = try layout("journey\n  section A\n    a: 3\n  section A\n    b: 3\n  section B\n    c: 3\n  section A\n    d: 3\n")
        XCTAssertEqual(layout.sections.map(\.text.lines), [["A"], ["B"], ["A"]])
        XCTAssertEqual(layout.sections[0].frame.maxX, layout.tasks[1].frame.maxX)
    }

    func testAWordTooWideWidensTheCardsUpToTheirWidestAndIsCut() throws {
        let short = try layout("journey\n  first second: 3\n")
        let wrapped = try layout("journey\n  first<br>second: 3\n")
        XCTAssertEqual(wrapped.tasks[0].text.lines, ["first", "second"])
        XCTAssertGreaterThan(wrapped.size.height, short.size.height)
        let words = try layout("journey\n  " + String(repeating: "several words that go on ", count: 4) + ": 3\n")
        XCTAssertEqual(words.size.width, short.size.width, "Words wrap within the narrowest card")
        let cut = try layout("journey\n  " + String(repeating: "x", count: 200) + ": 3\n")
        XCTAssertEqual(cut.tasks[0].frame.width, 220, "200 points of text at most")
        XCTAssertEqual(cut.tasks[0].text.lines.joined(), String(repeating: "x", count: 200))
        XCTAssertTrue(cut.tasks[0].text.lineWidths.allSatisfy { width in width <= 200 })
    }

    func testActorsDotsLineTheCardsBottomInTheirColorsAndStayInside() throws {
        let day = try layout(Self.workingDay)
        XCTAssertEqual(day.tasks.map { task in task.actorDots.map(\.seriesIndex) }, [[1], [1], [1, 0], [1], [1]], "Cat is first, Me second")
        let card = day.tasks[2].frame
        XCTAssertEqual(day.tasks[2].actorDots.map(\.center), [CGPoint(x: card.midX - 6.5, y: card.maxY - 13), CGPoint(x: card.midX + 6.5, y: card.maxY - 13)])
        XCTAssertEqual(card.height, 21 + 16 + 16, "A line of text, the row of dots and the card's padding")
        let crowd = try layout("journey\n  crowd: 3: " + (0..<60).map { index in "p\(index)" }.joined(separator: ",") + "\n").tasks[0]
        XCTAssertEqual(crowd.actorDots.count, 60)
        for dot in crowd.actorDots {
            XCTAssertGreaterThanOrEqual(dot.center.x - 5, crowd.frame.minX)
            XCTAssertLessThanOrEqual(dot.center.x + 5, crowd.frame.maxX)
        }
    }

    func testANamelessActorHasNoDotAndNoLegendEntry() throws {
        let layout = try layout("journey\n  a: 5:\n  b: 3: , Real,\n")
        XCTAssertEqual(layout.tasks.map(\.actorDots.count), [0, 1])
        XCTAssertEqual(layout.legend.map(\.text.lines), [["Real"]])
        XCTAssertTrue(try self.layout("journey\n  a: 5:\n").legend.isEmpty)
    }

    func testTheLegendIsCenteredBelowTheScaleAndWrapsInsideThePage() throws {
        let day = try layout(Self.workingDay)
        XCTAssertEqual(day.legend.map(\.text.lines), [["Cat"], ["Me"]])
        XCTAssertEqual(day.legend.map(\.dot.seriesIndex), [0, 1])
        XCTAssertEqual(day.legend[0].dot.center.y - (day.scaleLevels[4].line.start.y + 11), 16 + 21 / 2)
        let cardsMiddle = (day.tasks[0].frame.minX + day.tasks[4].frame.maxX) / 2
        let legendSpan = (day.legend[0].dot.center.x - 5, day.legend[1].text.frame.maxX)
        XCTAssertEqual((legendSpan.0 + legendSpan.1) / 2, cardsMiddle, accuracy: 0.001)
        let crowded = try layout("journey\n  one: 3: " + (0..<40).map { index in "Person number \(index)" }.joined(separator: ",") + "\n")
        XCTAssertGreaterThan(Set(crowded.legend.map(\.dot.center.y)).count, 5)
        for entry in crowded.legend {
            XCTAssertGreaterThan(entry.dot.center.x - 5, 0)
            XCTAssertLessThan(entry.text.frame.maxX, crowded.size.width)
        }
    }

    func testTheTitleIsAboveCenteredAndThePageHoldsEverything() throws {
        let day = try layout(Self.workingDay)
        let title = try XCTUnwrap(day.title)
        XCTAssertEqual(title.lines, ["My working day"])
        XCTAssertEqual(title.center.x, day.size.width / 2, accuracy: 0.5)
        XCTAssertEqual(day.sections[0].frame.minY - title.frame.maxY, 16)
        let lowestFace = try XCTUnwrap(day.tasks.map(\.faceCenter.y).max())
        XCTAssertLessThan(lowestFace + 11, day.size.height)
        XCTAssertEqual(day.size.height, (day.legend[1].text.frame.maxY + 8).rounded(.up))
    }

    func testAnEmptyJourneyALoneTitleAndSectionsWithoutTasksDrawNoScale() throws {
        for source in ["journey", "journey\n  title Only", "journey\n  section S\n  section T"] {
            let layout = try layout(source)
            XCTAssertGreaterThan(layout.size.width, 0)
            XCTAssertGreaterThan(layout.size.height, 0)
            XCTAssertTrue(layout.scaleLevels.isEmpty)
            XCTAssertTrue(layout.sections.isEmpty)
        }
        XCTAssertEqual(try layout("journey\n  title Only").size.height, (8 + 24 + 16 + 8), "The title, its gap and the padding")
    }
}
