import XCTest
import GraphiteCore
@testable import GraphiteUI

final class LibraryDropPlanTests: XCTestCase {
    private func path(_ rawValue: String) throws -> VaultPath { try VaultPath(rawValue) }

    func testItemsMoveIntoTheFolderInTheOrderDragged() throws {
        let moved = LibraryDropPlan.movablePaths([try path("B.md"), try path("A.md")], into: try path("Course"))
        XCTAssertEqual(moved, [try path("B.md"), try path("A.md")])
    }

    func testAnItemAlreadyInTheFolderDoesNotMove() throws {
        let moved = LibraryDropPlan.movablePaths([try path("Course/A.md"), try path("B.md")], into: try path("Course"))
        XCTAssertEqual(moved, [try path("B.md")])
    }

    func testAFolderCannotGoIntoItselfOrItsOwnSubfolder() throws {
        XCTAssertEqual(LibraryDropPlan.movablePaths([try path("Course")], into: try path("Course")), [])
        XCTAssertEqual(LibraryDropPlan.movablePaths([try path("Course")], into: try path("Course/Week 1")), [])
        XCTAssertEqual(LibraryDropPlan.movablePaths([try path("Course")], into: try path("Other")), [try path("Course")])
    }

    func testAFolderMovesIntoASiblingFolder() throws {
        XCTAssertEqual(LibraryDropPlan.movablePaths([try path("A/Notes")], into: try path("B")), [try path("A/Notes")])
    }

    func testAnItemInsideADraggedFolderMovesWithTheFolderNotOnItsOwn() throws {
        let moved = LibraryDropPlan.movablePaths([try path("Course/A.md"), try path("Course"), try path("B.md")], into: try path("Archive"))
        XCTAssertEqual(moved, [try path("Course"), try path("B.md")])
    }

    func testAnItemDraggedTwiceMovesOnce() throws {
        XCTAssertEqual(LibraryDropPlan.movablePaths([try path("A.md"), try path("A.md")], into: try path("Archive")), [try path("A.md")])
    }

    func testDroppingOnTheVaultRootMovesItemsOutOfFolders() throws {
        XCTAssertEqual(LibraryDropPlan.movablePaths([try path("Course/A.md"), try path("B.md")], into: .root), [try path("Course/A.md")])
    }

    func testAnItemOfTheSidebarAndAFileFromAnotherAppAreSortedApart() throws {
        let file = DroppedFile(location: URL(fileURLWithPath: "/tmp/Photo.jpeg"), stagingFolder: nil)
        let plan = LibraryDropPlan.make(from: [.vaultItem("A.md"), .file(file)], into: try path("Archive"))
        XCTAssertEqual(plan.movedPaths, [try path("A.md")])
        XCTAssertEqual(plan.droppedFiles, [file])
    }

    func testAnImpossiblePathMovesNothingAndTheDropIsEmpty() throws {
        let plan = LibraryDropPlan.make(from: [.vaultItem("../outside.md")], into: try path("Archive"))
        XCTAssertTrue(plan.isEmpty)
    }
}
