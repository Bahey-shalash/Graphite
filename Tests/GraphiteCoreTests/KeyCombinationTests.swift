import XCTest
@testable import GraphiteCore

final class KeyCombinationTests: XCTestCase {
    func testReadsObsidiansModifierNamesWithModAndMetaBothCommand() {
        XCTAssertEqual(KeyCombination(obsidianModifiers: ["Mod", "Shift"], key: "h"), KeyCombination([.command, .shift], .character("H")))
        XCTAssertEqual(KeyCombination(obsidianModifiers: ["Meta"], key: "B"), KeyCombination(.command, .character("B")))
        XCTAssertEqual(KeyCombination(obsidianModifiers: ["Ctrl", "Alt"], key: "ArrowUp"), KeyCombination([.control, .option], .named(.arrowUp)))
        XCTAssertNil(KeyCombination(obsidianModifiers: ["Hyper"], key: "B"), "A modifier Obsidian does not write is not guessed.")
        XCTAssertNil(KeyCombination(obsidianModifiers: ["Mod"], key: ""))
    }

    func testWritesObsidiansNamesInOneOrder() {
        XCTAssertEqual(KeyCombination([.shift, .option, .control, .command], .character("K")).obsidianModifierNames, ["Mod", "Ctrl", "Alt", "Shift"])
    }

    func testReadsEveryKeyNameObsidianWritesAndKeepsUnknownOnes() {
        for namedKey in NamedKey.allCases {
            XCTAssertEqual(ShortcutKey(obsidianName: namedKey.rawValue), .named(namedKey))
            XCTAssertEqual(ShortcutKey(obsidianName: namedKey.rawValue).obsidianName, namedKey.rawValue)
        }
        XCTAssertEqual(ShortcutKey(obsidianName: "Space"), .named(.space))
        XCTAssertEqual(ShortcutKey(obsidianName: "F5"), .function(5))
        XCTAssertEqual(ShortcutKey(obsidianName: "F"), .character("F"))
        XCTAssertEqual(ShortcutKey(obsidianName: "/"), .character("/"))
        XCTAssertEqual(ShortcutKey(obsidianName: "NumpadEnter"), .unknown("NumpadEnter"))
        XCTAssertEqual(ShortcutKey(obsidianName: "NumpadEnter").obsidianName, "NumpadEnter")
    }

    func testOnlyACombinationWithCommandControlOrOptionOrAFunctionKeyCanBeRecorded() {
        XCTAssertTrue(KeyCombination(.command, .character("B")).isRecordable)
        XCTAssertTrue(KeyCombination(.control, .named(.tab)).isRecordable)
        XCTAssertTrue(KeyCombination(.option, .character("X")).isRecordable)
        XCTAssertTrue(KeyCombination([], .function(5)).isRecordable)
        XCTAssertFalse(KeyCombination([], .character("B")).isRecordable)
        XCTAssertFalse(KeyCombination(.shift, .character("B")).isRecordable)
        XCTAssertFalse(KeyCombination(.shift, .named(.tab)).isRecordable)
    }
}
