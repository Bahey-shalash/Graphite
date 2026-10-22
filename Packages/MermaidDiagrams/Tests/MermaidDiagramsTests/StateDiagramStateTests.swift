import XCTest
@testable import MermaidDiagrams

final class StateDiagramStateTests: XCTestCase {
    func testAStateWithoutADescriptionIsNamedByItsIdentifier() {
        XCTAssertEqual(StateDiagramState(identifier: "Idle", kind: .state).name, DiagramLabel("Idle"))
    }

    func testTheFirstDescriptionIsTheName() {
        let state = StateDiagramState(identifier: "s1", kind: .state, descriptions: [DiagramLabel("Waiting"), DiagramLabel("for input")])
        XCTAssertEqual(state.name, DiagramLabel("Waiting"))
    }

    func testEachStereotypeNamesItsKindInAnyCase() {
        XCTAssertEqual(StateDiagramStateKind(stereotype: "fork"), .fork)
        XCTAssertEqual(StateDiagramStateKind(stereotype: "JOIN"), .join)
        XCTAssertEqual(StateDiagramStateKind(stereotype: "Choice"), .choice)
        XCTAssertNil(StateDiagramStateKind(stereotype: "start"))
    }
}
