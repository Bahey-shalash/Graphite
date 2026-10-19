import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Closing tabs: a tab closes only after its documents are saved, and only the tabs that
/// were saved close.
@MainActor
final class WorkspaceModelClosingTabsTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    private func replaceOutsideGraphite(_ path: String, in vault: URL, with text: String) throws {
        try Data(text.utf8).write(to: vault.appendingPathComponent(path))
    }

    func testATabWhoseNoteCannotBeSavedStaysOpenAndTheWorkspaceRaisesAnAlertNamingTheNote() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Note.md": "Original."])
        let tabID = try await testBed.open("Note.md", in: workspace)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.text = "Typed in Graphite."
        // Another app changed the file meanwhile, so saving would overwrite its version.
        try replaceOutsideGraphite("Note.md", in: vault, with: "Changed elsewhere.")

        await workspace.closeTab(tabID)

        XCTAssertNotNil(workspace.layout.tab(withID: tabID), "The tab stays open.")
        XCTAssertNotNil(workspace.tabDocuments[tabID]?.markdownSession, "Its note stays loaded with the unsaved text.")
        XCTAssertEqual(session.text, "Typed in Graphite.")
        XCTAssertEqual(try testBed.text(of: "Note.md", in: vault), "Changed elsewhere.", "The other app's version is untouched.")
        let alert = try XCTUnwrap(workspace.errorMessage)
        XCTAssertTrue(alert.contains("“Note.md” could not be saved, so its tab stays open."), alert)
    }

    func testClosingTheOtherTabsClosesNoneWhenOneOfThemCannotBeSaved() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Kept.md": "Kept.", "Fine.md": "Fine.", "Blocked.md": "Blocked."])
        let keptTabID = try await testBed.open("Kept.md", in: workspace)
        _ = await workspace.open(try VaultPath("Fine.md"), placement: .newTab)
        let blockedTabID = try await testBed.open("Blocked.md", in: workspace, placement: .newTab)
        try XCTUnwrap(workspace.openMarkdownSession(at: try VaultPath("Blocked.md"))).text = "Typed."
        try replaceOutsideGraphite("Blocked.md", in: vault, with: "Changed elsewhere.")

        await workspace.closeOtherTabs(keeping: keptTabID)

        XCTAssertEqual(workspace.layout.allTabs.count, 3, "A tab that cannot be saved keeps all the others open too.")
        XCTAssertNotNil(workspace.layout.tab(withID: blockedTabID))
        XCTAssertNotNil(workspace.errorMessage)
    }

    func testClosingTheOtherTabsSavesThemFirstAndLeavesAPinnedTabAndATabAddedWhileTheyWereSaved() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Kept.md": "Kept.", "Other.md": "Other.", "Pinned.md": "Pinned."])
        let keptTabID = try await testBed.open("Kept.md", in: workspace)
        _ = await workspace.open(try VaultPath("Other.md"), placement: .newTab)
        let pinnedTabID = try await testBed.open("Pinned.md", in: workspace, placement: .newTab)
        workspace.togglePin(pinnedTabID)
        try XCTUnwrap(workspace.openMarkdownSession(at: try VaultPath("Other.md"))).text = "Other, edited."

        let closing = Task { @MainActor in await workspace.closeOtherTabs(keeping: keptTabID) }
        // The closing task stops at the save of the edited note; a tab opened now was not saved.
        await Task.yield()
        let addedTabID = workspace.layout.addTab()
        await closing.value

        XCTAssertEqual(try testBed.text(of: "Other.md", in: vault), "Other, edited.", "The closed tab's note was saved first.")
        XCTAssertNotNil(workspace.layout.tab(withID: keptTabID))
        XCTAssertNotNil(workspace.layout.tab(withID: pinnedTabID), "A pinned tab is not closed.")
        XCTAssertNotNil(workspace.layout.tab(withID: addedTabID), "A tab added while the others were saved stays open.")
        XCTAssertEqual(workspace.layout.allTabs.count, 3)
    }

    func testATabIsSavedAgainWhenTheTextChangesWhileItIsBeingSavedBeforeItCloses() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Note.md": "Original.", "Other.md": "Other."])
        let tabID = try await testBed.open("Note.md", in: workspace)
        _ = await workspace.open(try VaultPath("Other.md"), placement: .newTab)
        let session = try XCTUnwrap(workspace.openMarkdownSession(at: try VaultPath("Note.md")))
        session.text = "First edit."

        let closing = Task { @MainActor in await workspace.closeTab(tabID) }
        await Task.yield()
        session.text = "Typed while the first edit was saved."
        await closing.value

        XCTAssertEqual(try testBed.text(of: "Note.md", in: vault), "Typed while the first edit was saved.")
        XCTAssertNil(workspace.layout.tab(withID: tabID), "The tab closed once nothing was left unsaved.")
        XCTAssertNil(workspace.errorMessage)
    }

    func testClosingASideSavesATabOpenedOnItMeanwhileAndClosesTheSideWithAllItsTabs() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Left.md": "Left.", "Right.md": "Right.", "Late.md": "Late."])
        _ = await workspace.open(try VaultPath("Left.md"))
        _ = await workspace.open(try VaultPath("Right.md"), placement: .otherGroup)
        let rightGroupID = workspace.layout.focusedGroupID
        let rightSession = try XCTUnwrap(workspace.openMarkdownSession(at: try VaultPath("Right.md")))
        rightSession.text = "Right, edited."

        // The close saves Right.md again for as long as it finds more typed in it ("a tab on screen stays editable
        // while the others save"). Typing into it between turns keeps the first save going while the tab opens, so
        // the tab is added, loaded and edited during the close however quickly the disk writes. Each save finds the
        // text typed since it began, because this task's turn is already queued ahead of the save's completion.
        let typingInRight = Task { @MainActor in
            while !Task.isCancelled {
                rightSession.text += "."
                await Task.yield()
            }
        }
        let latePath = try VaultPath("Late.md")
        let closing = Task { @MainActor in await workspace.closeGroup(rightGroupID) }
        await Task.yield()
        let lateTabID = workspace.layout.addTab(inGroup: rightGroupID, showing: latePath)
        await workspace.load(latePath, into: lateTabID, pdfPageIndex: nil, recordsHistory: false)
        try XCTUnwrap(workspace.openMarkdownSession(at: latePath)).text = "Late, edited."
        XCTAssertEqual(workspace.layout.groups.count, 2, "The side stays open while the text typed in its first tab is saved.")
        typingInRight.cancel()
        await typingInRight.value
        await closing.value

        XCTAssertEqual(try testBed.text(of: "Right.md", in: vault), rightSession.text, "What was typed last is saved too.")
        XCTAssertTrue(rightSession.text.hasPrefix("Right, edited."))
        XCTAssertEqual(try testBed.text(of: "Late.md", in: vault), "Late, edited.", "A tab opened on the side while the others were saved is saved too.")
        XCTAssertEqual(workspace.layout.groups.count, 1)
        XCTAssertNil(workspace.layout.tab(withID: lateTabID))
    }
}
