import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingClassDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAClassDiagram: Error {}

    private func classDiagram(_ source: String) throws -> ReadingClassDiagram {
        guard case .classDiagram(let classDiagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAClassDiagram()
        }
        return classDiagram
    }

    func testAClassDiagramIsLaidOutInTheNotesTextSize() throws {
        let drawn = try classDiagram("classDiagram\n  class Square~Shape~\n  Animal <|-- Square")
        XCTAssertEqual(drawn.layout.font.size, 17)
        XCTAssertEqual(drawn.layout.classes.count, 2)
        XCTAssertEqual(drawn.classNames, ["Square<Shape>", "Animal"])
        XCTAssertEqual(try classDiagram("classDiagram-v2\nclass A").layout.classes.count, 1)
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try classDiagram("---\ntitle: Front title\n---\nclassDiagram\naccDescr: How it fits\nclass A")
        XCTAssertEqual(titled.title, "Front title")
        XCTAssertEqual(titled.description, "How it fits")
        XCTAssertEqual(try classDiagram("classDiagram\naccTitle: Named\nclass A").title, "Named")
    }

    func testAClassDiagramWithNamespacesStaysCode() {
        XCTAssertNil(ReadingDiagram(source: "classDiagram\nnamespace Shapes {\n  class Triangle\n}", typography: typography))
    }

    func testAClassDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "classDiagram\nclass A {\n  +never closed"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedClassBody(identifier: "A"))))
    }

    func testEveryClassDiagramFailureIsExplainedApartFromTheOthers() {
        let earlier: [ReadingDiagramFailure] = [
            .reading(.noDiagram), .layout(.tooManyLayoutPoints(limit: 1)), .layout(.subgraphsNotLaidOut),
            .reading(.invalidSyntax(line: 1, problem: .unclosedShape(closingText: "]"))), .reading(.invalidSyntax(line: 1, problem: .unexpectedText("C"))),
        ]
        let classFailures: [ReadingDiagramFailure] = [.classLayout(.tooManyLayoutPoints(limit: 1)), .classLayout(.namespacesNotLaidOut)]
            + [MermaidSyntaxProblem.expectedName, .expectedRelationLine, .expectedQuotedText, .unclosedClassBody(identifier: "A"),
               .unclosedNamespace(identifier: "N"), .unclosedGenericType, .unclosedAnnotation].map { problem in
                .reading(.invalidSyntax(line: 1, problem: problem))
            }
        let explanations = (earlier + classFailures).map(\.explanation)
        XCTAssertEqual(Set(explanations).count, explanations.count)
    }
}
