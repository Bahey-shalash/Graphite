import XCTest
import SwiftUI
@testable import GraphiteUI

#if os(macOS)
/// The Mac's scenes: one main window and a Settings scene, both on one workspace.
@MainActor
final class GraphiteMacScenesTests: XCTestCase {
    func testTheMainWindowHasTheIdentifierMain() {
        XCTAssertEqual(GraphiteMacScenes.mainWindowIdentifier, "main")
    }

    /// One window for the workspace (never a WindowGroup, which would make a second workspace on
    /// the same index), the Guide's window, which holds no workspace, and Settings.
    func testTheMacAppIsOneWorkspaceWindowTheGuideWindowAndASettingsScene() {
        let scenes = GraphiteMacScenes(workspace: WorkspaceModel())
        let sceneType = String(describing: type(of: scenes.body))
        XCTAssertEqual(sceneType.components(separatedBy: "Window<").count - 1, 2)
        XCTAssertEqual(sceneType.components(separatedBy: "GuideView").count - 1, 1)
        XCTAssertEqual(sceneType.components(separatedBy: "Settings<").count - 1, 1)
        XCTAssertFalse(sceneType.contains("WindowGroup"))
    }
}
#endif
