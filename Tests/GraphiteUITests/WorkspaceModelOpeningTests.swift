import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Which tab a file opens in: one tab per file, found by the spelling the file system has.
@MainActor
final class WorkspaceModelOpeningTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    func testOpeningAFileUnderADifferentCapitalisationShowsItInTheTabThatHasItOnAVolumeThatIgnoresCapitals() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Note.md": "Note."])
        guard FileManager.default.fileExists(atPath: vault.appendingPathComponent("note.md").path) else {
            throw XCTSkip("The temporary folder's volume tells capitals apart, so one spelling cannot reach the other file.")
        }

        let firstTabID = await workspace.open(try VaultPath("note.md"))
        let secondTabID = await workspace.open(try VaultPath("Note.md"))

        XCTAssertEqual(firstTabID, secondTabID)
        XCTAssertEqual(workspace.layout.allTabs.count, 1)
        XCTAssertEqual(workspace.layout.allTabs.first?.path?.rawValue, "Note.md", "The tab keeps the file system's spelling.")
        XCTAssertEqual(workspace.markdownSession?.path.rawValue, "Note.md")
    }

    func testStoredPathIsTheFileSystemsSpellingAndAMissingFileKeepsTheRequestedOne() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Folder/Note.md": "Note."])
        guard FileManager.default.fileExists(atPath: vault.appendingPathComponent("folder/note.md").path) else {
            throw XCTSkip("The temporary folder's volume tells capitals apart.")
        }

        XCTAssertEqual(workspace.storedPath(for: try VaultPath("folder/note.md")).rawValue, "Folder/Note.md")
        XCTAssertEqual(workspace.storedPath(for: try VaultPath("Missing/Gone.md")).rawValue, "Missing/Gone.md")
    }

    func testOpeningAFileAlreadyOpenInAnotherTabActivatesThatTabInsteadOfOpeningItTwice() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["One.md": "One.", "Two.md": "Two."])
        let oneTabID = await workspace.open(try VaultPath("One.md"))
        let twoTabID = await workspace.open(try VaultPath("Two.md"), placement: .newTab)
        XCTAssertEqual(workspace.layout.allTabs.count, 2)
        XCTAssertEqual(workspace.layout.activeTab.id, twoTabID)

        let reopenedTabID = await workspace.open(try VaultPath("One.md"), placement: .newTab)

        XCTAssertEqual(reopenedTabID, oneTabID)
        XCTAssertEqual(workspace.layout.allTabs.count, 2, "No third tab is made for a file a tab has.")
        XCTAssertEqual(workspace.layout.activeTab.id, oneTabID)
    }

    func testAFileOpenedOnTheOtherSideStaysInItsTabWithoutMovingFocusWhenTheLinkDoesNotTakeFocus() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["One.md": "One.", "Two.md": "Two."])
        _ = await workspace.open(try VaultPath("One.md"))
        let twoTabID = await workspace.open(try VaultPath("Two.md"), placement: .otherGroup)
        let focusedGroupBefore = workspace.layout.focusedGroupID
        XCTAssertEqual(workspace.layout.activeTab.id, twoTabID)
        workspace.focusGroup(try XCTUnwrap(workspace.layout.groups.first).id)
        XCTAssertNotEqual(workspace.layout.focusedGroupID, focusedGroupBefore)
        let focusedGroupAfterRefocus = workspace.layout.focusedGroupID

        let sameTabID = await workspace.open(try VaultPath("Two.md"), takesFocus: false)

        XCTAssertEqual(sameTabID, twoTabID)
        XCTAssertEqual(workspace.layout.allTabs.count, 2)
        XCTAssertEqual(workspace.layout.focusedGroupID, focusedGroupAfterRefocus, "The tab is shown where it is; focus stays.")
    }
}
