import XCTest
@testable import MermaidDiagrams

/// The cases of Mermaid 12.1.0's `journeyDb.spec.js` (as Pele ports it in `tests/compat/journey`), which hand the
/// database a task's text and data directly: a name may hold a `#` there, which ends the text in a diagram.
final class UserJourneyDiagramBuilderTests: XCTestCase {
    func testTasksAndActorsAreAdded() throws {
        var builder = UserJourneyDiagramBuilder(limits: .standard)
        builder.apply(.title("Shopping"))
        builder.apply(.description("A user journey for family shopping"))
        try builder.addSection(DiagramLabel("Journey to the shops"))
        try builder.addTask(DiagramLabel("Get car keys"), data: ":5:Dad")
        try builder.addTask(DiagramLabel("Go to car"), data: ":3:Dad, Mum, Child#1, Child#2")
        try builder.addTask(DiagramLabel("Drive to supermarket"), data: ":4:Dad")
        try builder.addSection(DiagramLabel("Do shopping"))
        try builder.addTask(DiagramLabel("Go shopping"), data: ":5:Mum")
        let diagram = builder.diagram
        XCTAssertEqual(diagram.accessibilityTitle, "Shopping")
        XCTAssertEqual(diagram.accessibilityDescription, "A user journey for family shopping")
        XCTAssertEqual(diagram.tasks, [
            UserJourneyTask(label: DiagramLabel("Get car keys"), score: 5, actors: ["Dad"], sectionIndex: 0),
            UserJourneyTask(label: DiagramLabel("Go to car"), score: 3, actors: ["Dad", "Mum", "Child#1", "Child#2"], sectionIndex: 0),
            UserJourneyTask(label: DiagramLabel("Drive to supermarket"), score: 4, actors: ["Dad"], sectionIndex: 0),
            UserJourneyTask(label: DiagramLabel("Go shopping"), score: 5, actors: ["Mum"], sectionIndex: 1),
        ])
        XCTAssertEqual(diagram.actorNames, ["Child#1", "Child#2", "Dad", "Mum"])
        XCTAssertEqual(diagram.sections.map(\.spokenText), ["Journey to the shops", "Do shopping"])
    }

    func testANewBuilderHoldsNothing() {
        let diagram = UserJourneyDiagramBuilder(limits: .standard).diagram
        XCTAssertTrue(diagram.tasks.isEmpty)
        XCTAssertTrue(diagram.sections.isEmpty)
        XCTAssertTrue(diagram.actorNames.isEmpty)
        XCTAssertNil(diagram.accessibilityTitle)
        XCTAssertNil(diagram.accessibilityDescription)
    }

    func testActorsAreSortedByTheirUTF16CodeUnitsAsMermaidSortsThem() throws {
        var builder = UserJourneyDiagramBuilder(limits: .standard)
        try builder.addTask(DiagramLabel("a"), data: ":3:éa, zed, Zed, \u{1F600}, \u{FF21}")
        XCTAssertEqual(builder.diagram.actorNames, ["Zed", "zed", "éa", "\u{1F600}", "\u{FF21}"], "A surrogate pair sorts before U+FF21, as in JavaScript")
    }

    func testATitleOfSpacesLeavesNone() {
        var builder = UserJourneyDiagramBuilder(limits: .standard)
        builder.setTitle("  My day ")
        XCTAssertEqual(builder.diagram.title, "My day")
        builder.setTitle("   ")
        XCTAssertNil(builder.diagram.title)
    }
}
