import XCTest
@testable import GraphiteCore

final class FootnoteTests: XCTestCase {
    func testParsesReferencesDefinitionsAndInlineFootnotes() {
        let text = """
            A claim[^source] and another^[Said in class.] and again[^source].
            `code[^x]` is not a reference.

            [^source]: The textbook, chapter 2.
                Continued on an indented line.
            [^unused]: Never referenced.
            """
        let (definitions, references) = Footnotes.parse(text)
        XCTAssertEqual(definitions.map(\.label), ["source", "unused"])
        XCTAssertEqual(definitions.first?.text, "The textbook, chapter 2.\nContinued on an indented line.")
        XCTAssertEqual(references.map { reference in reference.label ?? "inline" }, ["source", "inline", "source"])
        XCTAssertEqual(references[1].inlineText, "Said in class.")
    }

    func testNumbersFootnotesInOrderOfFirstReference() {
        let text = "B[^b] then A[^a] then ^[inline] then B again[^B].\n\n[^a]: Alpha\n[^b]: Beta\n[^c]: Unreferenced\n"
        let (prepared, notes) = Footnotes.preparedForReading(text) { number in "{\(number)}" }
        XCTAssertEqual(prepared, "B{1} then A{2} then {3} then B again{1}.\n\n")
        XCTAssertEqual(notes, [Footnotes.Note(number: 1, text: "Beta"), Footnotes.Note(number: 2, text: "Alpha"),
                               Footnotes.Note(number: 3, text: "inline"), Footnotes.Note(number: 4, text: "Unreferenced")],
                       "Labels ignore case, and a definition nothing refers to is listed last.")
    }

    func testLeavesUndefinedReferencesAndCodeAlone() {
        let text = "Missing[^nope].\n```\n[^a]: in code\n```\n"
        let (prepared, notes) = Footnotes.preparedForReading(text) { number in "{\(number)}" }
        XCTAssertEqual(prepared, text)
        XCTAssertTrue(notes.isEmpty)
        XCTAssertEqual(Footnotes.preparedForReading("No footnotes here.") { _ in "" }.text, "No footnotes here.")
    }

    func testListsFootnotesWithWhereTheyAreReferenced() {
        let text = "One^[first] two[^b].\n\n[^b]: Second\n[^z]: Orphan\n"
        let listed = Footnotes.listed(in: text)
        XCTAssertEqual(listed.map(\.note.text), ["first", "Second", "Orphan"])
        let source = text as NSString
        XCTAssertEqual(listed.map(\.location), [source.range(of: "^[first]").location, source.range(of: "[^b]").location, source.range(of: "[^z]:").location])
    }
}
