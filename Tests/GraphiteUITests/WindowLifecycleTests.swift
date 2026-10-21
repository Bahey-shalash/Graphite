import XCTest
import GraphiteCore
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// What quitting and closing a window do with several windows open: quitting saves every
/// window, and a closed window's edits that cannot be saved in place are kept in a copy.
@MainActor
final class WindowLifecycleTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    private func makeVault(note: String) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "WindowVault", for: self).root.resolvingSymlinksInPath()
        try Data("Saved text.".utf8).write(to: vault.appendingPathComponent(note))
        return vault
    }

    private func window(showing note: String, in vault: URL) async throws -> (WorkspaceModel, MarkdownSession) {
        let window = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        try await window.openFolderAsVault(vault)
        await window.open(try VaultPath(note))
        return (window, try XCTUnwrap(window.markdownSession))
    }

    func testQuittingSavesTheDocumentsOfEveryWindow() async throws {
        let firstVault = try makeVault(note: "First.md")
        let secondVault = try makeVault(note: "Second.md")
        // The windows' scenes hold their workspaces; the list of windows holds them weakly.
        let (firstWindow, firstNote) = try await window(showing: "First.md", in: firstVault)
        let (secondWindow, secondNote) = try await window(showing: "Second.md", in: secondVault)
        firstNote.text = "Typed in the first window."
        secondNote.text = "Typed in the second window."

        XCTAssertEqual(processServices.openWindows.all.count, 2)
        for openWindow in processServices.openWindows.all { try await openWindow.saveOpenDocuments() }

        XCTAssertEqual(try String(contentsOf: firstVault.appendingPathComponent("First.md"), encoding: .utf8), "Typed in the first window.")
        XCTAssertEqual(try String(contentsOf: secondVault.appendingPathComponent("Second.md"), encoding: .utf8), "Typed in the second window.")
        withExtendedLifetime((firstWindow, secondWindow)) {}
    }

    func testAClosedWindowsEditsThatConflictAreKeptInACopy() async throws {
        let vault = try makeVault(note: "Lecture.md")
        let (closingWindow, note) = try await window(showing: "Lecture.md", in: vault)
        note.text = "Typed before closing."
        // Another app changes the note meanwhile, so the save in place is refused.
        try Data("Changed in another app.".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        await note.checkExternalChange()
        XCTAssertTrue(note.hasExternalConflict)

        let outcome = await closingWindow.saveBeforeWindowCloses()
        closingWindow.windowDidClose()

        XCTAssertEqual(outcome.copied, ["Lecture Graphite edits.md"])
        XCTAssertEqual(outcome.notCopied, [])
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Lecture Graphite edits.md"), encoding: .utf8), "Typed before closing.")
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Lecture.md"), encoding: .utf8), "Changed in another app.")
        XCTAssertTrue(processServices.openWindows.all.isEmpty)
    }

    func testNewWindowContentOpensTheVaultWithAnEmptyTabAndKeepsTheVaultsTabs() async throws {
        let vault = try makeVault(note: "Lecture.md")
        let (firstWindow, _) = try await window(showing: "Lecture.md", in: vault)
        let vaultIdentifier = try XCTUnwrap(firstWindow.currentVaultIdentifier)
        let secondWindow = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())

        await secondWindow.openVaultOfWindow(vaultIdentifier, tabs: .none, showing: nil)

        XCTAssertEqual(secondWindow.currentVaultIdentifier, vaultIdentifier)
        XCTAssertNil(secondWindow.selection, "A new window starts with an empty tab.")
        XCTAssertEqual(firstWindow.selection, try VaultPath("Lecture.md"))
        let laterLaunch = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        await laterLaunch.openVaultOfWindow(vaultIdentifier, tabs: .vaultsLast, showing: nil)
        XCTAssertEqual(laterLaunch.selection, try VaultPath("Lecture.md"), "The vault's remembered tabs were not replaced by the empty window's.")
    }

    func testEachWindowRestoresItsOwnTabsAfterARelaunch() async throws {
        let vault = try makeVault(note: "Lecture.md")
        try Data("other".utf8).write(to: vault.appendingPathComponent("Exercises.md"))
        let (firstWindow, _) = try await window(showing: "Lecture.md", in: vault)
        let vaultIdentifier = try XCTUnwrap(firstWindow.currentVaultIdentifier)
        let firstWindowsTabs = try XCTUnwrap(firstWindow.windowTabsToKeep())
        // A second window on the vault, left later, is what the device remembers for the vault.
        let (secondWindow, _) = try await window(showing: "Exercises.md", in: vault)
        XCTAssertNotNil(secondWindow.windowTabsToKeep())

        let relaunchedFirstWindow = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
        let keptTabs = try XCTUnwrap(WindowTabs.layout(in: firstWindowsTabs, forVault: vaultIdentifier))
        await relaunchedFirstWindow.openVaultOfWindow(vaultIdentifier, tabs: .window(keptTabs), showing: nil)

        XCTAssertEqual(relaunchedFirstWindow.selection, try VaultPath("Lecture.md"), "The first window's own tabs, not the vault's last ones.")
        XCTAssertNil(WindowTabs.layout(in: firstWindowsTabs, forVault: UUID()), "Tabs kept for another vault are not shown.")
        withExtendedLifetime((firstWindow, secondWindow)) {}
    }
}
