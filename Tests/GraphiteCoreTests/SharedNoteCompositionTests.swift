import XCTest
@testable import GraphiteCore

final class SharedNoteCompositionTests: XCTestCase {
    func testATitleBecomesANoteNameWithoutCharactersNamesMayNotHold() {
        XCTAssertEqual(SharedNoteComposition.noteStem(fromTitle: "Q&A: [draft] #1"), "Q&A draft 1")
        XCTAssertEqual(SharedNoteComposition.noteStem(fromTitle: "a/b\\c|d^e"), "a b c d e")
        XCTAssertEqual(SharedNoteComposition.noteStem(fromTitle: "Line\nbreak\ttab"), "Line break tab")
        XCTAssertEqual(SharedNoteComposition.noteStem(fromTitle: " ..hidden"), "hidden")
        XCTAssertEqual(SharedNoteComposition.noteStem(fromTitle: "Résumé ✏️"), "Résumé ✏️")
    }

    func testATitleWithNothingLeftIsUntitled() {
        XCTAssertEqual(SharedNoteComposition.noteStem(fromTitle: "  "), "Untitled")
        XCTAssertEqual(SharedNoteComposition.noteStem(fromTitle: "[]#|"), "Untitled")
    }

    func testALongTitleIsCutToTheLongestNoteNameAtACharacter() {
        let stem = SharedNoteComposition.noteStem(fromTitle: String(repeating: "é", count: 300))
        XCTAssertLessThanOrEqual(stem.utf8.count, FileNameRules.maximumFileNameBytes - FileNameRules.reservedSuffixBytes)
        XCTAssertNil(FileNameRules.problem(with: stem, isNote: true))
        XCTAssertEqual(Set(stem), ["é"])
    }

    func testTheNoteHasTheTextThenItsEmbedsOnePerLine() {
        XCTAssertEqual(SharedNoteComposition.noteText(sharedText: "Text\n\n", embeds: ["![[A.png]]", "![[B.pdf]]"]), "Text\n\n![[A.png]]\n![[B.pdf]]\n")
        XCTAssertEqual(SharedNoteComposition.noteText(sharedText: "", embeds: ["![[A.png]]"]), "![[A.png]]\n")
        XCTAssertEqual(SharedNoteComposition.noteText(sharedText: " \n", embeds: []), "")
    }

    func testTheItemFollowsTheNoteAfterABlankLine() {
        XCTAssertEqual(SharedNoteComposition.suffixAppending("New\n", to: "Plan"), "\n\nNew\n")
        XCTAssertEqual(SharedNoteComposition.suffixAppending("New\n", to: "Plan\n"), "\nNew\n")
        XCTAssertEqual(SharedNoteComposition.suffixAppending("New\n", to: "Plan\n\n"), "New\n")
        XCTAssertEqual(SharedNoteComposition.suffixAppending("New\n", to: "Plan\n\n\n"), "New\n")
    }

    func testAnEmptyNoteGetsTheItemAlone() {
        XCTAssertEqual(SharedNoteComposition.suffixAppending("New\n", to: ""), "New\n")
        XCTAssertEqual(SharedNoteComposition.suffixAppending("New\n", to: "\n"), "New\n")
        XCTAssertEqual(SharedNoteComposition.suffixAppending("", to: "Plan"), "")
    }

    func testTheItemTakesTheNotesLineEnding() {
        XCTAssertEqual(SharedNoteComposition.suffixAppending("A\nB\n", to: "Plan\r\nDay"), "\r\n\r\nA\r\nB\r\n")
        XCTAssertEqual(SharedNoteComposition.suffixAppending("A\n", to: "Plan\rDay\r"), "\rA\r")
        XCTAssertEqual(SharedNoteComposition.suffixAppending("A\n", to: "Plan\r\n\r\n"), "A\r\n")
    }
}
