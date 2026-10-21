import XCTest
@testable import GraphiteCore

final class UserKeyEquivalentsTests: XCTestCase {
    func testReadsTheModifierMarksAndTheKey() {
        XCTAssertEqual(UserKeyEquivalents.combination(fromKeyEquivalent: "@~b"), KeyCombination([.command, .option], .character("B")))
        XCTAssertEqual(UserKeyEquivalents.combination(fromKeyEquivalent: "^$@k"), KeyCombination([.control, .shift, .command], .character("K")))
        XCTAssertEqual(UserKeyEquivalents.combination(fromKeyEquivalent: "@\u{F700}"), KeyCombination(.command, .named(.arrowUp)))
        XCTAssertEqual(UserKeyEquivalents.combination(fromKeyEquivalent: "\u{F708}"), KeyCombination([], .function(5)))
        XCTAssertEqual(UserKeyEquivalents.combination(fromKeyEquivalent: "@$"), KeyCombination(.command, .character("$")))
        XCTAssertNil(UserKeyEquivalents.combination(fromKeyEquivalent: "@ab"))
    }

    func testMenuPathsAreReadByTheirLastTitleAndAnEmptyEquivalentRemovesTheShortcut() {
        let combinations = UserKeyEquivalents.combinationsByMenuTitle(["\u{1B}File\u{1B}New Note": "@~n", "Close Tab": "", "Broken": "@ab"])
        XCTAssertEqual(combinations["New Note"], .some(KeyCombination([.command, .option], .character("N"))))
        XCTAssertEqual(combinations["Close Tab"], .some(nil))
        XCTAssertNil(combinations["Broken"] as KeyCombination??)
    }
}
