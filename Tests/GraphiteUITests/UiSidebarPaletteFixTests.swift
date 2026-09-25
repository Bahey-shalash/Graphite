import XCTest
import CoreGraphics
import GraphiteCore
import GraphiteApple
@testable import GraphiteIndex
@testable import GraphiteUI

/// The palettes, the sidebar's rename, and tabs letting go of their documents, run against
/// real vault folders where a workspace is needed.
@MainActor
final class UiSidebarPaletteFixTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var savedGraphitePreferences: [String: Any] = [:]

    override func setUp() async throws {
        // The workspace remembers vaults in the standard preferences; the test process's
        // own preferences are put back as they were afterwards.
        savedGraphitePreferences = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in key.hasPrefix("Graphite") }
    }

    override func tearDown() async throws {
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("Graphite") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, storedValue) in savedGraphitePreferences { UserDefaults.standard.set(storedValue, forKey: key) }
        for directory in temporaryDirectories {
            if let cacheURL = try? VaultIndex.cacheURL(for: directory) { try? FileManager.default.removeItem(at: cacheURL) }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    // MARK: Helpers

    private func makeVault(notes: [String: String] = [:], pdfPageCounts: [String: Int] = [:]) throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("SidebarPaletteVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        temporaryDirectories.append(vault)
        for (path, contents) in notes {
            try Data(contents.utf8).write(to: vault.appendingPathComponent(path))
        }
        for (path, pageCount) in pdfPageCounts {
            try writeBlankPDF(pageCount: pageCount, to: vault.appendingPathComponent(path))
        }
        // The workspace reads the folder through its resolved path, as the file system reports it.
        return vault.resolvingSymlinksInPath()
    }

    private func writeBlankPDF(pageCount: Int, to location: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
        guard let context = CGContext(location as CFURL, mediaBox: &mediaBox, nil) else {
            throw GraphiteError.invalidFile("The test PDF could not be created.")
        }
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func openedWorkspace(_ vault: URL) async throws -> WorkspaceModel {
        let workspace = WorkspaceModel()
        try await workspace.openFolderAsVault(vault)
        return workspace
    }

    private func waitUntil(timeoutSeconds: Double = 20, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else {
                XCTFail("The condition did not become true in time.")
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private func fileText(_ path: String, in vault: URL) -> String? {
        (try? Data(contentsOf: vault.appendingPathComponent(path))).flatMap { data in String(data: data, encoding: .utf8) }
    }

    // MARK: Palettes

    /// "Quick switcher: Open quick switcher" ran before the palette closed, so the close
    /// cleared the switcher it had just opened.
    func testPaletteActionThatOpensAnotherPaletteIsNotUndoneByClosing() {
        var activePalette: String? = "command palette"
        QuickPalette.perform({ activePalette = "quick switcher" }, closing: { activePalette = nil })
        XCTAssertEqual(activePalette, "quick switcher")
    }

    /// Titles followed the query being typed while their highlighted ranges came from the
    /// query the matches were found for, so the wrong letters were marked.
    func testSwitcherTitleFollowsTheQueryTheMatchWasFoundFor() throws {
        let match = QuickSwitcherMatch(path: try VaultPath("Folder/ab.md"), alias: nil, score: 1, matchedRanges: [0..<2])
        XCTAssertEqual(QuickSwitcher.title(of: match, foundFor: "ab"), "ab")
        XCTAssertEqual(QuickSwitcher.title(of: match, foundFor: "fo/ab"), "Folder/ab.md")
        let aliasMatch = QuickSwitcherMatch(path: try VaultPath("Signals.md"), alias: "Fourier", score: 1, matchedRanges: [0..<3])
        XCTAssertEqual(QuickSwitcher.title(of: aliasMatch, foundFor: "fou/"), "Fourier")
    }

    /// A note listing the same alias twice gave two rows with the same identifier.
    func testRepeatedAliasGivesOneSwitcherRow() throws {
        let path = try VaultPath("Signals.md")
        let matches = [
            QuickSwitcherMatch(path: path, alias: "Fourier", score: 2, matchedRanges: [0..<7]),
            QuickSwitcherMatch(path: path, alias: "Fourier", score: 2, matchedRanges: [0..<7]),
            QuickSwitcherMatch(path: path, alias: nil, score: 1, matchedRanges: []),
        ]
        let unique = QuickSwitcher.uniqueMatches(matches)
        XCTAssertEqual(unique.map(\.id), ["Signals.md|Fourier", "Signals.md|"])
    }

    // MARK: Rename

    /// Typing the full file name in the Rename sheet gave "Lecture.md.md".
    func testTypedExtensionIsNotDoubledWhenRenaming() {
        XCTAssertEqual(RenamedFileName.withoutTypedExtension("Lecture.md", fileExtension: "md"), "Lecture")
        XCTAssertEqual(RenamedFileName.withoutTypedExtension(" Lecture.MD ", fileExtension: "md"), "Lecture")
        XCTAssertEqual(RenamedFileName.withoutTypedExtension("Lecture", fileExtension: "md"), "Lecture")
        XCTAssertEqual(RenamedFileName.withoutTypedExtension("Version 1.2", fileExtension: "pdf"), "Version 1.2")
        XCTAssertEqual(RenamedFileName.withoutTypedExtension("Archive.md", fileExtension: ""), "Archive.md")
    }

    // MARK: Tabs

    /// Text typed into the open note while the tab loaded another file was dropped with the
    /// old session: only what was there when the load began had been saved.
    func testTextTypedWhileTheTabLoadsAnotherFileIsSaved() async throws {
        let vault = try makeVault(notes: ["A.md": "original"], pdfPageCounts: ["B.pdf": 3_000])
        let workspace = try await openedWorkspace(vault)
        await workspace.open(try VaultPath("A.md"))
        let session = try XCTUnwrap(workspace.markdownSession)
        let document = workspace.activeDocument
        session.text = "original plus"

        let pdfPath = try VaultPath("B.pdf")
        let opening = Task { await workspace.open(pdfPath) }
        // Once the first save is done the PDF is still being read, and typing goes on.
        try await waitUntil { !session.hasUnsavedChanges && session.text == "original plus" && fileText("A.md", in: vault) == "original plus" }
        let typedWhileOpening = document.isOpening
        session.text = "original plus typing"
        _ = await opening.value

        XCTAssertEqual(workspace.selection, pdfPath)
        guard typedWhileOpening else { throw XCTSkip("The PDF opened before the typing could happen.") }
        XCTAssertEqual(fileText("A.md", in: vault), "original plus typing")
    }

    /// Every PDF opened in a tab stayed in memory until the tab closed. Hidden tabs now keep
    /// only the most recently hidden one; the others reopen, at the same page, when shown.
    func testHiddenTabsLetGoOfOlderPDFsAndReopenThemAtTheSamePage() async throws {
        let vault = try makeVault(pdfPageCounts: ["One.pdf": 5, "Two.pdf": 5, "Three.pdf": 5])
        let workspace = try await openedWorkspace(vault)
        let firstTabIDResult = await workspace.open(try VaultPath("One.pdf"))
        let firstTabID = try XCTUnwrap(firstTabIDResult)
        let firstSession = try XCTUnwrap(workspace.document(for: firstTabID).pdfSession)
        firstSession.currentPageIndex = 3
        let secondTabIDResult = await workspace.open(try VaultPath("Two.pdf"), placement: .newTab)
        let secondTabID = try XCTUnwrap(secondTabIDResult)
        XCTAssertNotNil(workspace.document(for: firstTabID).pdfSession, "The most recently hidden PDF stays open.")

        let thirdTabIDResult = await workspace.open(try VaultPath("Three.pdf"), placement: .newTab)
        let thirdTabID = try XCTUnwrap(thirdTabIDResult)
        XCTAssertEqual(workspace.layout.activeTab.id, thirdTabID)
        XCTAssertNil(workspace.document(for: firstTabID).pdfSession, "An older hidden PDF is let go of.")
        XCTAssertNotNil(workspace.document(for: secondTabID).pdfSession)
        XCTAssertNotNil(workspace.document(for: thirdTabID).pdfSession)

        workspace.activateTab(firstTabID)
        await workspace.loadDocumentIfNeeded(for: firstTabID)
        let reopenedSession = try XCTUnwrap(workspace.document(for: firstTabID).pdfSession)
        XCTAssertFalse(reopenedSession === firstSession)
        XCTAssertEqual(reopenedSession.currentPageIndex, 3)
        XCTAssertEqual(workspace.document(for: firstTabID).loadedPath, try VaultPath("One.pdf"))
    }

    /// A PDF with edits that could not be saved is never let go of.
    func testHiddenPDFWithUnsavedEditsIsKept() async throws {
        let vault = try makeVault(pdfPageCounts: ["One.pdf": 3, "Two.pdf": 3, "Three.pdf": 3])
        let workspace = try await openedWorkspace(vault)
        let firstTabIDResult = await workspace.open(try VaultPath("One.pdf"))
        let firstTabID = try XCTUnwrap(firstTabIDResult)
        let firstSession = try XCTUnwrap(workspace.document(for: firstTabID).pdfSession)
        // A conflict stops every save, so the edit stays unsaved.
        firstSession.hasExternalConflict = true
        try firstSession.apply(.rotate(page: 0, clockwise: true))
        _ = await workspace.open(try VaultPath("Two.pdf"), placement: .newTab)
        _ = await workspace.open(try VaultPath("Three.pdf"), placement: .newTab)
        XCTAssertTrue(workspace.document(for: firstTabID).pdfSession === firstSession)
    }
}

