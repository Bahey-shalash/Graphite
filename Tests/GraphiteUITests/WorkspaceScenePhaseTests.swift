import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// What the workspace does as its scene stops being active and becomes active again
/// (`N-10`): the places of the open documents are remembered before any save starts.
@MainActor
final class WorkspaceScenePhaseTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    private func openedWorkspace() async throws -> (workspace: WorkspaceModel, placesKey: String) {
        let vault = try TemporaryVault.make(prefix: "ScenePhaseVault", files: ["Note.md": "Text.\n"], for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Note.md"))
        // Scrolled away from the start: the start of a note is not remembered, as it is where it opens anyway.
        try XCTUnwrap(workspace.markdownSession).savedScrollLocation = 3
        let identifier = try XCTUnwrap(workspace.currentVaultIdentifier)
        return (workspace, WorkspaceModel.placesKey(for: identifier))
    }

    func testPlacesAreRememberedBeforeTheSaveStartsWhenTheSceneStopsBeingActive() async throws {
        let (workspace, placesKey) = try await openedWorkspace()
        XCTAssertNil(device.defaults.data(forKey: placesKey), "Nothing is remembered before the scene leaves.")
        var placesWhenTheSaveStarted: Data?
        var saveCount = 0

        workspace.scenePhaseDidChange(from: .active, to: .inactive) {
            saveCount += 1
            placesWhenTheSaveStarted = self.device.defaults.data(forKey: placesKey)
        }

        XCTAssertEqual(saveCount, 1)
        XCTAssertNotNil(placesWhenTheSaveStarted, "The places were already remembered when the save started.")
    }

    func testGoingFromInactiveToBackgroundSavesAgainWithoutRememberingPlacesAgain() async throws {
        let (workspace, placesKey) = try await openedWorkspace()
        var saveCount = 0

        workspace.scenePhaseDidChange(from: .inactive, to: .background) { saveCount += 1 }

        XCTAssertEqual(saveCount, 1)
        XCTAssertNil(device.defaults.data(forKey: placesKey), "Places are taken only as the scene leaves the active phase.")
    }

    func testBecomingActiveSavesNothing() async throws {
        let (workspace, _) = try await openedWorkspace()
        var saveCount = 0

        workspace.scenePhaseDidChange(from: .inactive, to: .active) { saveCount += 1 }

        XCTAssertEqual(saveCount, 0)
    }
}
