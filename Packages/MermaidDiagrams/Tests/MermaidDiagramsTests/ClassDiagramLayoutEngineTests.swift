import XCTest
@testable import MermaidDiagrams

final class ClassDiagramLayoutEngineTests: XCTestCase {
    private let accuracy: CGFloat = 0.01
    /// Names 8 points a character on 24-point lines, members 7 on 21, marks 6 at 13 points (rows of 18).
    private let measurers = ClassDiagramTextMeasurers(names: UniformWidthTextMeasurer(),
                                                      members: UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21),
                                                      marks: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20))

    private func layout(_ source: String, title: String? = nil, limits: MermaidDiagramLimits = .standard) throws -> ClassDiagramLayout {
        var diagram = try ClassDiagramReading.classDiagram(source)
        diagram.title = title
        return try ClassDiagramLayoutEngine.layout(diagram, measurers: measurers, font: UniformWidthLayout.font, limits: limits)
    }

    func testABoxHasPelesCompartmentsAroundItsText() throws {
        let duck = try XCTUnwrap(try layout("classDiagram\nclass Duck {\n  +String beakColor\n  +swim()\n  +quack() bool\n}").classes.first)
        // The widest line is "+String beakColor", 17 × 7 points, with 12 points of padding on each side.
        XCTAssertEqual(duck.frame.width, 17 * 7 + 24, accuracy: accuracy)
        // The title 8 + 24 + 8, the attributes 6 + 21 + 6, the methods 6 + 2 × 21 + 6.
        XCTAssertEqual(duck.frame.height, 40 + 33 + 54, accuracy: accuracy)
        let dividers: [CGFloat] = duck.dividerYs.map { y in y - duck.frame.minY }
        XCTAssertEqual(dividers, [40, 73])
        XCTAssertEqual(duck.name.lines, ["Duck"])
        XCTAssertEqual(duck.name.center.y - duck.frame.minY, 20, accuracy: accuracy)
        XCTAssertEqual(duck.members.map(\.text.lines), [["+String beakColor"], ["+swim()"], ["+quack() : bool"]])
        let memberLefts: [CGFloat] = duck.members.map { member in member.text.frame.minX - duck.frame.minX }
        XCTAssertEqual(memberLefts, [12, 12, 12])
        let memberCenters: [CGFloat] = duck.members.map { member in member.text.center.y - duck.frame.minY }
        XCTAssertEqual(memberCenters, [56.5, 89.5, 110.5], "Each line 6 points below its compartment's top, 21 points apart")
    }

    func testAnnotationsSitAboveTheNameAndEmptyCompartmentsKeepTheirHeight() throws {
        let shape = try XCTUnwrap(try layout("classDiagram\nclass Shape <<interface>>").classes.first)
        XCTAssertEqual(shape.annotations.map(\.lines), [["«interface»"]])
        // The title 8 + 18 + 24 + 8, then two empty compartments of 10.
        XCTAssertEqual(shape.frame.height, 58 + 10 + 10, accuracy: accuracy)
        XCTAssertEqual(shape.annotations[0].center.y - shape.frame.minY, 8 + 9, accuracy: accuracy)
        XCTAssertEqual(shape.name.center.y - shape.frame.minY, 38, accuracy: accuracy)
        XCTAssertEqual(shape.frame.width, 11 * 6 + 24, accuracy: accuracy)
        XCTAssertEqual(try XCTUnwrap(try layout("classDiagram\nclass A").classes.first).frame.width, 64, "A box is 64 points wide at least")
    }

    func testTheNameShowsItsLabelAndGenericType() throws {
        let classes = try layout("classDiagram\nclass Square~Shape~\nclass A[\"A class with a label\"]").classes
        XCTAssertEqual(classes.map(\.name.lines), [["Square<Shape>"], ["A class with a label"]])
    }

    func testEachDirectionPlacesTheNextRankOnItsSide() throws {
        func secondFromFirst(_ direction: String) throws -> CGVector {
            let classes = try layout("classDiagram\ndirection \(direction)\nA <|-- B").classes
            return CGVector(dx: classes[1].frame.midX - classes[0].frame.midX, dy: classes[1].frame.midY - classes[0].frame.midY)
        }
        XCTAssertGreaterThan(try secondFromFirst("TB").dy, 0)
        XCTAssertLessThan(try secondFromFirst("BT").dy, 0)
        XCTAssertGreaterThan(try secondFromFirst("LR").dx, 0)
        XCTAssertEqual(try secondFromFirst("LR").dy, 0, accuracy: accuracy)
        XCTAssertLessThan(try secondFromFirst("RL").dx, 0)
    }

    func testRanksAre56PointsApartOr72WhenARelationHasACardinality() throws {
        let plain = try layout("classDiagram\nA --> B").classes
        XCTAssertEqual(plain[1].frame.minY - plain[0].frame.maxY, 56, accuracy: accuracy)
        let counted = try layout("classDiagram\nA \"1\" --> B").classes
        XCTAssertEqual(counted[1].frame.minY - counted[0].frame.maxY, 72, accuracy: accuracy)
    }

    func testAMarkSitsAtTheEndItIsWrittenAtPointingIntoItsClass() throws {
        let laidOut = try layout("classDiagram\nAnimal <|-- Duck")
        let animal = laidOut.classes[0].frame
        let relation = try XCTUnwrap(laidOut.relations.first)
        let mark = try XCTUnwrap(relation.sourceMark)
        XCTAssertEqual(mark.end, .inheritance)
        XCTAssertEqual(mark.tip.x, animal.midX, accuracy: accuracy)
        XCTAssertEqual(mark.tip.y, animal.maxY, accuracy: accuracy)
        XCTAssertEqual(mark.direction, CGVector(dx: 0, dy: -1))
        XCTAssertNil(relation.targetMark)
        XCTAssertGreaterThan(laidOut.classes[1].frame.minY, animal.maxY)
    }

    func testTheLineStopsAtTheBackOfEachMark() throws {
        func ends(_ relation: String) throws -> (start: CGFloat, end: CGFloat) {
            let path = try XCTUnwrap(try layout("classDiagram\nA \(relation) B").relations.first).path
            return (path.start.y, path.allPoints.last?.y ?? 0)
        }
        let plain = try ends("--")
        XCTAssertEqual(try ends("--|>").end, plain.end - 12, accuracy: accuracy)
        XCTAssertEqual(try ends("<|--").start, plain.start + 12, accuracy: accuracy)
        XCTAssertEqual(try ends("*--o").start, plain.start + 16, accuracy: accuracy)
        XCTAssertEqual(try ends("*--o").end, plain.end - 16, accuracy: accuracy)
        XCTAssertEqual(try ends("-->").end, plain.end - 7, accuracy: accuracy)
        XCTAssertEqual(try ends("()--()").start, plain.start + 10, accuracy: accuracy)
    }

    func testARelationsLineStyleAndTextAreKept() throws {
        let relations = try layout("classDiagram\nA ..> B : uses\nB -- C").relations
        XCTAssertEqual(relations.map(\.line), [.dashed, .solid])
        let text = try XCTUnwrap(relations[0].text)
        XCTAssertEqual(text.lines, ["uses"])
        XCTAssertEqual(text.fontSize, 14)
    }

    func testCardinalitiesSitBesideTheirEndsBetweenTheClasses() throws {
        let laidOut = try layout("classDiagram\nCustomer \"1\" --> \"0..*\" Ticket : buys")
        let relation = try XCTUnwrap(laidOut.relations.first)
        let source = try XCTUnwrap(relation.sourceCardinality)
        let target = try XCTUnwrap(relation.targetCardinality)
        XCTAssertEqual(source.lines, ["1"])
        XCTAssertEqual(target.lines, ["0..*"])
        XCTAssertEqual(source.fontSize, 13)
        let customer = laidOut.classes[0].frame
        let ticket = laidOut.classes[1].frame
        let middle = (customer.maxY + ticket.minY) / 2
        XCTAssertGreaterThan(source.center.y, customer.maxY)
        XCTAssertLessThan(source.center.y, middle)
        XCTAssertGreaterThan(target.center.y, middle)
        XCTAssertLessThan(target.center.y, ticket.minY)
        XCTAssertFalse(source.frame.intersects(target.frame))
        XCTAssertGreaterThan(abs(source.center.x - customer.midX), source.size.width / 2, "Beside the line, not on it")
    }

    func testEndsSharingASideSpreadAlongItInTheirOrder() throws {
        let laidOut = try layout("classDiagram\nHub --> A\nHub --> B\nHub --> C")
        let starts = laidOut.relations.map(\.path.start.x)
        XCTAssertEqual(Set(starts).count, 3)
        XCTAssertEqual(starts, starts.sorted())
        let targets = laidOut.classes[1...].map(\.frame.midX)
        XCTAssertEqual(targets, targets.sorted())
    }

    func testAClassThatManyRelationsLeaveIsWidenedForTheirCardinalities() throws {
        let hub = try layout("classDiagram\nclass Hub\nHub \"1\" --> \"a\" A\nHub \"22\" --> \"b\" B\nHub \"3\" --> \"c\" C").classes[0]
        // Three ends, the widest cardinality 2 × 6 points: (3 - 1) × (12 + 24) + 24.
        XCTAssertEqual(hub.frame.width, 2 * 36 + 24, accuracy: accuracy)
        XCTAssertEqual(try layout("classDiagram\ndirection LR\nHub \"1\" --> \"a\" A\nHub \"22\" --> \"b\" B").classes[0].frame.width, 64,
                       "Only a flow that runs down widens")
    }

    func testARelationFromAClassToItselfLoopsOutOfItsRightSide() throws {
        let laidOut = try layout("classDiagram\nclass Node\nNode \"1\" --> \"0..1\" Node : next")
        let node = laidOut.classes[0].frame
        let loop = try XCTUnwrap(laidOut.relations.first)
        XCTAssertNil(loop.sourceMark)
        let mark = try XCTUnwrap(loop.targetMark)
        XCTAssertEqual(mark.tip, CGPoint(x: node.maxX, y: node.midY + 8))
        XCTAssertEqual(mark.direction, CGVector(dx: -1, dy: 0))
        XCTAssertEqual(loop.path.start, CGPoint(x: node.maxX, y: node.midY - 8))
        XCTAssertEqual(loop.path.allPoints.last ?? .zero, CGPoint(x: node.maxX + 7, y: node.midY + 8))
        XCTAssertGreaterThan(try XCTUnwrap(loop.text).frame.minX, node.maxX + 26)
        XCTAssertLessThan(try XCTUnwrap(loop.sourceCardinality).center.y, node.midY - 8)
        XCTAssertGreaterThan(try XCTUnwrap(loop.targetCardinality).center.y, node.midY + 8)
        XCTAssertGreaterThanOrEqual(laidOut.size.width, try XCTUnwrap(loop.text).frame.maxX)
    }

    func testANoteForAClassIsJoinedByADottedLineAndALoneNoteIsNot() throws {
        let laidOut = try layout("classDiagram\nclass MyClass\nnote \"General<br>note\"\nnote for MyClass \"About it\"")
        XCTAssertEqual(laidOut.notes.count, 2)
        XCTAssertEqual(laidOut.notes[0].text.lines, ["General", "note"])
        // Two lines of 21 points with 8 points above and below; 7 characters of 7 points with 12 points each side.
        XCTAssertEqual(laidOut.notes[0].frame.size, CGSize(width: 7 * 7 + 24, height: 42 + 16))
        XCTAssertEqual(laidOut.noteLinks.count, 1)
        let link = laidOut.noteLinks[0]
        XCTAssertEqual(link.line, .dotted)
        XCTAssertNil(link.sourceMark)
        XCTAssertNil(link.targetMark)
        XCTAssertTrue(laidOut.relations.isEmpty)
    }

    func testALollipopInterfaceIsItsNameJoinedToItsClassByARing() throws {
        let laidOut = try layout("classDiagram\nbar ()-- foo")
        XCTAssertEqual(laidOut.interfaces.map(\.lines), [["bar"]])
        XCTAssertEqual(laidOut.classes.count, 1)
        let mark = try XCTUnwrap(laidOut.relations.first?.sourceMark)
        XCTAssertEqual(mark.end, .lollipop)
        XCTAssertLessThanOrEqual(abs(mark.tip.y - laidOut.interfaces[0].center.y), laidOut.interfaces[0].size.height / 2 + 2 + accuracy)
    }

    func testTheDocumentationsAnimalExampleLaysOutWithoutOverlap() throws {
        let laidOut = try layout("""
        classDiagram
            note "From Duck till Zebra"
            Animal <|-- Duck
            note for Duck "can fly<br>can swim<br>can dive<br>can help in debugging"
            Animal <|-- Fish
            Animal <|-- Zebra
            Animal : +int age
            Animal : +String gender
            Animal: +isMammal()
            Animal: +mate()
            class Duck{
                +String beakColor
                +swim()
                +quack()
            }
            class Fish{
                -int sizeInFeet
                -canEat()
            }
            class Zebra{
                +bool is_wild
                +run()
            }
        """, title: "Animal example")
        let frames = laidOut.classes.map(\.frame) + laidOut.notes.map(\.frame)
        for (index, frame) in frames.enumerated() {
            XCTAssertTrue(CGRect(origin: .zero, size: laidOut.size).contains(frame), "\(index)")
            for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other)) }
        }
        let title = try XCTUnwrap(laidOut.title)
        XCTAssertLessThan(title.frame.maxY, frames.map(\.minY).min() ?? 0)
        XCTAssertEqual(title.center.x, laidOut.size.width / 2, accuracy: accuracy)
        XCTAssertEqual(laidOut.relations.count, 3)
        XCTAssertEqual(laidOut.noteLinks.count, 1)
    }

    func testNamespacesAndTheLayoutLimitAreRefused() {
        XCTAssertThrowsError(try layout("classDiagram\nnamespace Shapes {\n  class Triangle\n}")) { error in
            XCTAssertEqual(error as? ClassDiagramLayoutError, .namespacesNotLaidOut)
        }
        var limits = MermaidDiagramLimits.standard
        limits.maximumLayoutPointCount = 2
        XCTAssertThrowsError(try layout("classDiagram\nA --> B\nB --> C", limits: limits)) { error in
            XCTAssertEqual(error as? ClassDiagramLayoutError, .tooManyLayoutPoints(limit: 2))
        }
    }
}
