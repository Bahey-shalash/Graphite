import XCTest
import PDFKit
import GraphiteCore
@testable import GraphiteUI

/// Loading a file into a tab: the latest request wins, what the tab showed is saved before
/// it is replaced, and a failure shows where the person looks.
@MainActor
final class WorkspaceModelLoadingTabsTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    func testOfTwoOverlappingLoadsIntoOneTabOnlyTheSecondsSessionIsInstalled() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["First.md": "First.", "Second.md": "Second."])
        let tabID = workspace.layout.activeTab.id

        let firstPath = try VaultPath("First.md"), secondPath = try VaultPath("Second.md")
        // Both are queued on the main actor before this test suspends, so the second begins before
        // the first, which waits for the store's read, can continue: however fast the read is.
        let first = Task { @MainActor in await workspace.load(firstPath, into: tabID, pdfPageIndex: nil, recordsHistory: true) }
        let second = Task { @MainActor in await workspace.load(secondPath, into: tabID, pdfPageIndex: nil, recordsHistory: true) }
        let didLoadFirst = await first.value
        let didLoadSecond = await second.value

        XCTAssertFalse(didLoadFirst, "The earlier request was replaced.")
        XCTAssertTrue(didLoadSecond)
        XCTAssertEqual(workspace.document(for: tabID).markdownSession?.path.rawValue, "Second.md")
        XCTAssertEqual(workspace.document(for: tabID).loadedPath?.rawValue, "Second.md")
        XCTAssertEqual(workspace.layout.tab(withID: tabID)?.path?.rawValue, "Second.md")
        XCTAssertFalse(workspace.document(for: tabID).isOpening)
    }

    func testTheNoteATabShowedIsSavedWithAllItsChangesBeforeTheNewFileReplacesIt() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Old.md": "Old.", "New.md": "New."])
        let tabID = try await testBed.open("Old.md", in: workspace)
        try XCTUnwrap(workspace.markdownSession).text = "Old, edited."

        let didLoad = await workspace.load(try VaultPath("New.md"), into: tabID, pdfPageIndex: nil, recordsHistory: true)

        XCTAssertTrue(didLoad)
        XCTAssertEqual(try testBed.text(of: "Old.md", in: vault), "Old, edited.")
        XCTAssertEqual(workspace.document(for: tabID).markdownSession?.path.rawValue, "New.md")
    }

    func testTextTypedWhileTheNewFileLoadsIsSavedBeforeTheOldSessionGoes() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Old.md": "Old.", "New.md": "New."])
        let tabID = try await testBed.open("Old.md", in: workspace)
        let oldSession = try XCTUnwrap(workspace.markdownSession)

        let newPath = try VaultPath("New.md")
        let loading = Task { @MainActor in await workspace.load(newPath, into: tabID, pdfPageIndex: nil, recordsHistory: true) }
        await Task.yield()
        oldSession.text = "Typed while New.md was read."
        _ = await loading.value

        XCTAssertEqual(try testBed.text(of: "Old.md", in: vault), "Typed while New.md was read.")
        XCTAssertEqual(workspace.document(for: tabID).markdownSession?.path.rawValue, "New.md")
    }

    func testAFileAnotherTabOpenedMeanwhileIsActivatedThereAndTheLoadingTabKeepsWhatItShowed() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Mine.md": "Mine.", "Contested.md": "Contested."])
        let loadingTabID = try await testBed.open("Mine.md", in: workspace)
        let otherTabID = workspace.layout.addTab()
        workspace.layout.focus(tabID: loadingTabID)

        let contestedPath = try VaultPath("Contested.md")
        let loading = Task { @MainActor in await workspace.load(contestedPath, into: loadingTabID, pdfPageIndex: nil, recordsHistory: true) }
        await Task.yield()
        // The other tab shows the file before the loading tab has swapped its session in.
        workspace.layout.show(contestedPath, inTab: otherTabID, recordsHistory: true)
        let didLoad = await loading.value

        XCTAssertFalse(didLoad)
        XCTAssertEqual(workspace.layout.tabID(showing: try VaultPath("Contested.md")), otherTabID)
        XCTAssertEqual(workspace.layout.activeTab.id, otherTabID, "The tab that has the file is activated.")
        XCTAssertEqual(workspace.document(for: loadingTabID).markdownSession?.path.rawValue, "Mine.md")
        XCTAssertEqual(workspace.layout.tab(withID: loadingTabID)?.path?.rawValue, "Mine.md")
    }

    func testAFileThatCannotBeOpenedRaisesAnAlertAndTheTabShowsTheFailure() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Note.md": "Note."])
        let tabID = workspace.layout.activeTab.id

        let didLoad = await workspace.load(try VaultPath("Gone.md"), into: tabID, pdfPageIndex: nil, recordsHistory: true)

        XCTAssertFalse(didLoad)
        XCTAssertEqual(workspace.document(for: tabID).loadFailure?.path.rawValue, "Gone.md")
        XCTAssertNotNil(workspace.errorMessage)
    }

    func testARestoredTabWhoseFileCannotBeOpenedShowsTheFailureInTheTabAndRaisesNoAlert() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Note.md": "Note."])
        let tabID = workspace.layout.activeTab.id
        workspace.layout.show(try VaultPath("Gone.md"), inTab: tabID, recordsHistory: false)

        await workspace.loadDocumentIfNeeded(for: tabID)

        XCTAssertEqual(workspace.document(for: tabID).loadFailure?.path.rawValue, "Gone.md")
        XCTAssertNil(workspace.errorMessage, "An alert for every restored tab would pile up.")
        XCTAssertFalse(workspace.document(for: tabID).isOpening)
    }

    func testAPasswordProtectedPDFAsksInItsTabKeepingThePageAskedForAndNoAlert() async throws {
        let (workspace, vault) = try await testBed.openedWorkspace(files: ["Note.md": "Note."])
        let protectedLocation = vault.appendingPathComponent("Locked.pdf")
        let document = PDFDocument()
        for pageIndex in 0..<3 { document.insert(PDFPage(), at: pageIndex) }
        XCTAssertTrue(document.write(to: protectedLocation, withOptions: [.userPasswordOption: "open sesame", .ownerPasswordOption: "owner secret"]))
        let tabID = workspace.layout.activeTab.id

        let didLoad = await workspace.load(try VaultPath("Locked.pdf"), into: tabID, pdfPageIndex: 2, recordsHistory: true)

        XCTAssertFalse(didLoad)
        let failure = try XCTUnwrap(workspace.document(for: tabID).loadFailure)
        XCTAssertTrue(failure.needsPassword)
        XCTAssertEqual(failure.requestedPageIndex, 2)
        XCTAssertEqual(workspace.layout.tab(withID: tabID)?.path?.rawValue, "Locked.pdf", "The tab shows the PDF's name while it asks.")
        XCTAssertNil(workspace.errorMessage)

        await workspace.unlockPDF(inTab: tabID, password: "wrong")
        let stillAsking = try XCTUnwrap(workspace.document(for: tabID).loadFailure)
        XCTAssertTrue(stillAsking.needsPassword)
        XCTAssertEqual(stillAsking.requestedPageIndex, 2, "A wrong password keeps the requested page.")
        XCTAssertNil(workspace.pdfPasswords[try VaultPath("Locked.pdf")], "A wrong password is not kept.")

        await workspace.unlockPDF(inTab: tabID, password: "open sesame")
        XCTAssertNil(workspace.document(for: tabID).loadFailure)
        XCTAssertEqual(workspace.document(for: tabID).pdfSession?.currentPageIndex, 2)
    }
}
