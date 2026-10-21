import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// Two windows of one process on the same vault share its index (decision 12 of
/// `Docs/solid/rewrite-foundations.md`). Each window used to open the vault's cache file
/// itself; two of them failed each other's writes ("database is locked") and pruned each
/// other's rows on rescan.
@MainActor
final class SharedVaultIndexTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var processServices: ProcessServices!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        processServices = device.makeServices()
    }

    private func makeVault(notes: [String: String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "SharedIndexVault", for: self).root
        for (path, contents) in notes {
            let location = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        return vault.resolvingSymlinksInPath()
    }

    /// A window of this process: a workspace over the services every window shares.
    private func makeWindow() -> WorkspaceModel {
        WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
    }

    private func indexedWindow(on vault: URL) async throws -> WorkspaceModel {
        let window = makeWindow()
        try await window.openFolderAsVault(vault)
        try await waitUntil { window.hasCompletedIndexScan && !window.isIndexing }
        return window
    }

    private func searchedPaths(_ query: String, in window: WorkspaceModel) async -> Set<String> {
        window.searchQuery = query
        await window.search()
        return Set(window.searchResults.map(\.path.rawValue))
    }

    private static func manyNotes(count: Int) -> [String: String] {
        var notes: [String: String] = [:]
        for noteNumber in 1...count { notes["Notes/Note \(noteNumber).md"] = "shared word \(noteNumber) links [[Note \(noteNumber + 1)]]" }
        return notes
    }

    func testTwoWindowsOnOneVaultShareOneIndexAndBothFinishTheirScans() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 120))
        let firstWindow = makeWindow()
        let secondWindow = makeWindow()

        // Both open while the first scan may still be running.
        try await firstWindow.openFolderAsVault(vault)
        try await secondWindow.openFolderAsVault(vault)
        try await waitUntil { firstWindow.hasCompletedIndexScan && !firstWindow.isIndexing && secondWindow.hasCompletedIndexScan && !secondWindow.isIndexing }

        XCTAssertEqual(firstWindow.currentVaultIdentifier, secondWindow.currentVaultIdentifier)
        XCTAssertIdentical(try XCTUnwrap(firstWindow.index), try XCTUnwrap(secondWindow.index))
        XCTAssertNil(firstWindow.errorMessage)
        XCTAssertNil(secondWindow.errorMessage, "A second scan of the same file used to fail while the first ran.")
        XCTAssertEqual(firstWindow.indexingMessage, "120 files")
        XCTAssertEqual(secondWindow.indexingMessage, "120 files")
    }

    func testARescanInOneWindowKeepsTheRowsTheOtherWindowWrote() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 40))
        let firstWindow = try await indexedWindow(on: vault)
        let secondWindow = try await indexedWindow(on: vault)

        await firstWindow.createNote(named: "Written in the first window", in: .root)
        try await waitUntil { await self.searchedPaths("Written", in: secondWindow).contains("Written in the first window.md") }
        let versionBeforeRescan = secondWindow.indexVersion
        secondWindow.startIndexing()
        try await waitUntil { !secondWindow.isIndexing && secondWindow.indexVersion > versionBeforeRescan }
        // The first window hears the scan the second asked for.
        try await waitUntil { !firstWindow.isIndexing }

        let fileCount = try await XCTUnwrap(firstWindow.index).fileCount()
        XCTAssertEqual(fileCount, 41)
        let foundInFirstWindow = await searchedPaths("shared", in: firstWindow)
        XCTAssertEqual(foundInFirstWindow.count, 40)
        XCTAssertNil(firstWindow.errorMessage)
        XCTAssertNil(secondWindow.errorMessage)
    }

    func testAScanAskedForWhileAnotherWindowsScanRunsFollowsIt() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 200))
        let firstWindow = makeWindow()
        try await firstWindow.openFolderAsVault(vault)
        XCTAssertTrue(firstWindow.isIndexing)
        let secondWindow = makeWindow()
        try await secondWindow.openFolderAsVault(vault)
        let versionBeforeScans = secondWindow.indexVersion

        secondWindow.startIndexing()
        try await waitUntil { !secondWindow.isIndexing && !firstWindow.isIndexing }

        XCTAssertGreaterThanOrEqual(secondWindow.indexVersion - versionBeforeScans, 2, "The running scan, then the one asked for during it.")
        XCTAssertTrue(firstWindow.hasCompletedIndexScan)
        XCTAssertNil(secondWindow.errorMessage)
    }

    func testAWindowOpeningAVaultAnotherWindowScannedDoesNotScanItAgain() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 10))
        let firstWindow = try await indexedWindow(on: vault)
        let firstVersion = firstWindow.indexVersion

        let secondWindow = try await indexedWindow(on: vault)

        XCTAssertEqual(secondWindow.indexingMessage, "10 files")
        XCTAssertEqual(firstWindow.indexVersion, firstVersion, "No scan ran for the second window.")
    }

    func testClosingOneWindowKeepsTheIndexOfTheOtherAndTheLastClosesIt() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 5))
        let firstWindow = try await indexedWindow(on: vault)
        let secondWindow = try await indexedWindow(on: vault)
        let vaultIdentifier = try XCTUnwrap(firstWindow.currentVaultIdentifier)

        firstWindow.windowDidClose()

        XCTAssertTrue(processServices.vaultIndexes.isOpen(vaultIdentifier))
        let foundAfterClose = await searchedPaths("shared", in: secondWindow)
        XCTAssertEqual(foundAfterClose.count, 5)
        secondWindow.startIndexing()
        try await waitUntil { !secondWindow.isIndexing }
        XCTAssertNil(secondWindow.errorMessage)

        secondWindow.windowDidClose()

        XCTAssertFalse(processServices.vaultIndexes.isOpen(vaultIdentifier))
    }

    func testAWindowLetGoOfWithoutClosingStillLetsTheIndexClose() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 3))
        var window: WorkspaceModel? = try await indexedWindow(on: vault)
        let vaultIdentifier = try XCTUnwrap(window?.currentVaultIdentifier)
        weak var weakWindow = window

        window = nil

        try await waitUntil { weakWindow == nil }
        XCTAssertFalse(processServices.vaultIndexes.isOpen(vaultIdentifier))
    }

    func testTwoVaultsInTwoWindowsKeepAnIndexEach() async throws {
        let firstVault = try makeVault(notes: ["First.md": "only in the first vault"])
        let secondVault = try makeVault(notes: ["Second.md": "only in the second vault"])

        let firstWindow = try await indexedWindow(on: firstVault)
        let secondWindow = try await indexedWindow(on: secondVault)

        XCTAssertNotIdentical(try XCTUnwrap(firstWindow.index), try XCTUnwrap(secondWindow.index))
        let foundInFirst = await searchedPaths("only", in: firstWindow)
        let foundInSecond = await searchedPaths("only", in: secondWindow)
        XCTAssertEqual(foundInFirst, ["First.md"])
        XCTAssertEqual(foundInSecond, ["Second.md"])
    }

    func testRebuildingInOneWindowRescansForTheOther() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 30))
        let firstWindow = try await indexedWindow(on: vault)
        let secondWindow = try await indexedWindow(on: vault)
        let secondVersionBeforeRebuild = secondWindow.indexVersion

        await firstWindow.rebuildIndex()
        try await waitUntil { firstWindow.hasCompletedIndexScan && !firstWindow.isIndexing && secondWindow.indexVersion > secondVersionBeforeRebuild && !secondWindow.isIndexing }

        XCTAssertTrue(secondWindow.hasCompletedIndexScan)
        let found = await searchedPaths("shared", in: secondWindow)
        XCTAssertEqual(found.count, 30)
        XCTAssertNil(firstWindow.errorMessage)
        XCTAssertNil(secondWindow.errorMessage)
    }

    /// Every window on the vault hears that the index was emptied before the new scan
    /// ends, so none follows a link into a note it would create twice.
    func testEveryLeaseHearsTheIndexEmptiedBeforeTheRebuildsScanEnds() async throws {
        let vault = try makeVault(notes: Self.manyNotes(count: 5))
        let vaultIdentifier = UUID()
        let rebuildingLease = try await processServices.vaultIndexes.lease(forVault: vaultIdentifier, root: vault)
        let watchingLease = try await processServices.vaultIndexes.lease(forVault: vaultIdentifier, root: vault)
        XCTAssertIdentical(rebuildingLease.index, watchingLease.index)
        var heardEvents: [String] = []
        let listening = Task { @MainActor in
            for await event in watchingLease.events {
                switch event {
                case .scanStarted: heardEvents.append("started")
                case .scanFinished: heardEvents.append("finished")
                case .scanCancelled: heardEvents.append("cancelled")
                case .scanFailed: heardEvents.append("failed")
                case .emptied: heardEvents.append("emptied")
                }
            }
        }
        rebuildingLease.requestScan(.always)
        try await waitUntil { heardEvents.last == "finished" }

        try await rebuildingLease.rebuild()
        try await waitUntil { heardEvents.count == 5 }

        XCTAssertEqual(heardEvents, ["started", "finished", "emptied", "started", "finished"])
        rebuildingLease.end()
        watchingLease.end()
        await listening.value
        XCTAssertFalse(processServices.vaultIndexes.isOpen(vaultIdentifier))
    }

    func testAVaultOpenInAnotherWindowCannotBeRemovedFromTheList() async throws {
        let sharedVault = try makeVault(notes: ["Note.md": "text"])
        let otherVault = try makeVault(notes: ["Other.md": "text"])
        let firstWindow = try await indexedWindow(on: sharedVault)
        let vault = try XCTUnwrap(firstWindow.vaultLibrary.vault(withIdentifier: try XCTUnwrap(firstWindow.currentVaultIdentifier)))
        let secondWindow = try await indexedWindow(on: otherVault)

        XCTAssertThrowsError(try secondWindow.removeFromVaultList(vault)) { error in
            XCTAssertEqual(error as? VaultRemovalRefusal, .openInAnotherWindow)
        }
        XCTAssertNotNil(secondWindow.vaultLibrary.vault(withIdentifier: vault.id))
    }
}
