import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// When the workspace refreshes after another app changes vault files: once reports pause for
/// 500 ms, and no later than 2 s after the first report while more keep coming. Time moves on
/// a `ManualClock`, so each deadline is checked just before and at the moment it passes.
@MainActor
final class WorkspaceExternalRefreshTimingTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
        try await super.tearDown()
    }

    private func openedWorkspace(clock: ManualClock) async throws -> (workspace: WorkspaceModel, vault: URL) {
        let vault = try testBed.makeVault(files: ["Note.md": "Text"])
        let workspace = try testBed.isolatedDevice().makeWorkspace(clock: clock)
        try await workspace.openFolderAsVault(vault)
        return (workspace, vault)
    }

    func testAReportedChangeRefreshesTheVaultAfterReportsPauseForHalfASecond() async throws {
        let clock = ManualClock()
        let (workspace, vault) = try await openedWorkspace(clock: clock)
        let versionBeforeTheChange = workspace.drawingVersion

        workspace.scheduleExternalRefresh(vault.appendingPathComponent("Note.md"))
        try await clock.awaitPendingSleepers()
        clock.advance(by: .milliseconds(499))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(workspace.drawingVersion, versionBeforeTheChange)

        clock.advance(by: .milliseconds(1))
        try await waitUntil("the vault to be refreshed") { workspace.drawingVersion == versionBeforeTheChange + 1 }
    }

    func testChangesThatKeepComingRefreshTheVaultTwoSecondsAfterTheFirstReport() async throws {
        let clock = ManualClock()
        let (workspace, vault) = try await openedWorkspace(clock: clock)
        let versionBeforeTheChanges = workspace.drawingVersion
        let note = vault.appendingPathComponent("Note.md")

        // A report every 400 ms keeps postponing the 500 ms pause until the 2 s cap.
        workspace.scheduleExternalRefresh(note)
        for _ in 1...4 {
            try await clock.awaitPendingSleepers()
            clock.advance(by: .milliseconds(400))
            await ManualClock.letResumedTasksRun()
            workspace.scheduleExternalRefresh(note)
        }
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.milliseconds(400)])
        clock.advance(by: .milliseconds(399))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(workspace.drawingVersion, versionBeforeTheChanges)

        clock.advance(by: .milliseconds(1))
        try await waitUntil("the vault to be refreshed") { workspace.drawingVersion == versionBeforeTheChanges + 1 }
    }
}
