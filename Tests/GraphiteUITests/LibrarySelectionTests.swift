import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

final class LibrarySelectionTests: XCTestCase {
    private func paths(_ names: String...) throws -> [VaultPath] { try names.map(VaultPath.init) }

    func testATapChoosesATileAndAnotherTapUnchoosesIt() throws {
        let shown = try paths("A.md", "B.md", "C.md")
        var selection = LibrarySelection()
        selection.begin()
        selection.apply(.toggle, to: shown[1], among: shown)
        XCTAssertEqual(selection.chosenPaths, [shown[1]])
        selection.apply(.toggle, to: shown[2], among: shown)
        XCTAssertEqual(selection.chosenPaths, [shown[1], shown[2]])
        selection.apply(.toggle, to: shown[1], among: shown)
        XCTAssertEqual(selection.chosenPaths, [shown[2]])
    }

    func testAPlainClickOnTheMacChoosesTheTileAlone() throws {
        let shown = try paths("A.md", "B.md", "C.md")
        var selection = LibrarySelection()
        selection.begin()
        selection.apply(.toggle, to: shown[0], among: shown)
        selection.apply(.toggle, to: shown[1], among: shown)
        selection.apply(.replace, to: shown[2], among: shown)
        XCTAssertEqual(selection.chosenPaths, [shown[2]])
    }

    func testAShiftClickChoosesEveryTileFromTheLastOneChosenInEitherDirection() throws {
        let shown = try paths("A.md", "B.md", "C.md", "D.md", "E.md")
        var selection = LibrarySelection()
        selection.begin()
        selection.apply(.toggle, to: shown[3], among: shown)
        selection.apply(.extendRange, to: shown[1], among: shown)
        XCTAssertEqual(selection.chosenPaths, Set(shown[1...3]))
        selection.apply(.extendRange, to: shown[4], among: shown)
        XCTAssertEqual(selection.chosenPaths, Set(shown[1...4]), "A second range starts from the last tile clicked: the one the first range ended at is not the anchor.")
    }

    func testAShiftClickWithNoTileChosenYetChoosesJustThatTile() throws {
        let shown = try paths("A.md", "B.md")
        var selection = LibrarySelection()
        selection.begin()
        selection.apply(.extendRange, to: shown[1], among: shown)
        XCTAssertEqual(selection.chosenPaths, [shown[1]])
    }

    func testBeginningWithATileChoosesIt() throws {
        let shown = try paths("A.md", "B.md")
        var selection = LibrarySelection()
        selection.begin(choosing: shown[0])
        XCTAssertTrue(selection.isSelecting)
        XCTAssertTrue(selection.isChosen(shown[0]))
        XCTAssertEqual(selection.anchorPath, shown[0])
    }

    func testCommandTogglesShiftExtendsAndNoKeyIsAPlainClick() {
        XCTAssertEqual(LibrarySelection.Gesture(heldKeys: .command), .toggle)
        XCTAssertEqual(LibrarySelection.Gesture(heldKeys: .shift), .extendRange)
        XCTAssertEqual(LibrarySelection.Gesture(heldKeys: [.command, .shift]), .toggle)
        XCTAssertNil(LibrarySelection.Gesture(heldKeys: []))
        XCTAssertNil(LibrarySelection.Gesture(heldKeys: .option))
    }

    func testSelectAllAndDeselectAll() throws {
        let shown = try paths("A.md", "B.md", "C.md")
        var selection = LibrarySelection()
        selection.begin()
        XCTAssertFalse(selection.hasChosenAll(listedCount: shown.count))
        selection.selectAll(of: shown)
        XCTAssertEqual(selection.chosenCount, 3)
        XCTAssertTrue(selection.hasChosenAll(listedCount: shown.count))
        selection.deselectAll()
        XCTAssertEqual(selection.chosenCount, 0)
        XCTAssertTrue(selection.isSelecting, "Clearing the choice keeps choosing until Done.")
    }

    func testNothingListedIsNeverAllChosen() {
        XCTAssertFalse(LibrarySelection().hasChosenAll(listedCount: 0))
    }

    func testTilesThatAreNoLongerListedLeaveTheChoice() throws {
        let shown = try paths("A.md", "B.md", "C.md")
        var selection = LibrarySelection()
        selection.begin()
        selection.selectAll(of: shown)
        selection.keepListed([shown[0], shown[1]])
        XCTAssertEqual(selection.chosenPaths, [shown[0], shown[1]])
        XCTAssertNil(selection.anchorPath, "The anchor C.md was chosen last and has gone.")
    }

    func testTheChoiceIsReturnedInTheOrderShown() throws {
        let shown = try paths("A.md", "B.md", "C.md")
        var selection = LibrarySelection()
        selection.begin()
        selection.apply(.toggle, to: shown[2], among: shown)
        selection.apply(.toggle, to: shown[0], among: shown)
        XCTAssertEqual(selection.chosenPaths(in: shown), [shown[0], shown[2]])
    }

    func testEndingForgetsEverything() throws {
        let shown = try paths("A.md")
        var selection = LibrarySelection()
        selection.begin(choosing: shown[0])
        selection.end()
        XCTAssertEqual(selection, LibrarySelection())
    }
}
