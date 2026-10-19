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

    func testTheMacAppIsOneWindowAndASettingsScene() {
        let scenes = GraphiteMacScenes(workspace: WorkspaceModel())
        let sceneType = String(describing: type(of: scenes.body))
        XCTAssertEqual(sceneType.components(separatedBy: "Window<").count - 1, 1)
        XCTAssertEqual(sceneType.components(separatedBy: "Settings<").count - 1, 1)
        XCTAssertFalse(sceneType.contains("WindowGroup"))
    }
}
#endif
