import XCTest
import GraphiteCore
@testable import GraphiteUI

/// The recent files the quick switcher lists before anything is typed.
@MainActor
final class WorkspaceModelRecentFilesTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    func testTheRecentFilesKeptHoldAtMostThirtyPaths() {
        XCTAssertEqual(RecentFiles.maximumCount, 30)
    }

    func testRecentFilesListedAreTheExistingOnesMostRecentFirstUpToTheLimit() async throws {
        var files: [String: String] = [:]
        for number in 0..<25 { files["Note \(number).md"] = "Note \(number)." }
        let (workspace, _) = try await testBed.openedWorkspace(files: files)
        // Recorded oldest first, so "Note 24" is the most recent; one that is gone is skipped.
        for number in 0..<25 { workspace.recentFiles.record(try VaultPath("Note \(number).md")) }
        workspace.recentFiles.record(try VaultPath("Deleted elsewhere.md"))
        workspace.recentFiles.record(try VaultPath("Note 24.md"))

        let listed = workspace.existingRecentFiles(limit: 20)

        XCTAssertEqual(listed.count, 20)
        XCTAssertEqual(listed.map(\.rawValue), (0..<20).map { offset in "Note \(24 - offset).md" })
        XCTAssertFalse(listed.contains { path in path.rawValue == "Deleted elsewhere.md" })
    }

    func testTheOpenFileIsLeftOutOfTheRecentFilesListed() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Open.md": "Open.", "Recent.md": "Recent."])
        workspace.recentFiles.record(try VaultPath("Recent.md"))
        workspace.recentFiles.record(try VaultPath("Open.md"))

        XCTAssertEqual(workspace.existingRecentFiles(limit: 20, excluding: [try VaultPath("Open.md")]).map(\.rawValue), ["Recent.md"])
        XCTAssertEqual(workspace.existingRecentFiles(limit: 20).map(\.rawValue), ["Open.md", "Recent.md"])
    }

    func testTheRecentFilesListedAreNothingBeforeAVaultIsOpen() {
        XCTAssertEqual(WorkspaceModel().existingRecentFiles(limit: 20), [])
    }
}
