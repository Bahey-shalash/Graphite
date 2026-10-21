import XCTest
import SwiftUI
@testable import GraphiteUI

#if os(macOS)
/// The Mac's scenes: windows of workspaces, the Guide's window and a Settings scene.
@MainActor
final class GraphiteMacScenesTests: XCTestCase {
    func testTheWorkspaceWindowsHaveTheIdentifierMain() {
        XCTAssertEqual(GraphiteWindow.identifier, "main")
    }

    /// A window group of workspaces (decision 12: windows on one vault share its index), the
    /// Guide's window, which holds no workspace, and Settings.
    func testTheMacAppIsAGroupOfWorkspaceWindowsTheGuideWindowAndASettingsScene() throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let scenes = GraphiteMacScenes(processServices: device.makeServices(), launchMode: .hostedTests)
        let sceneType = String(describing: type(of: scenes.body))
        XCTAssertEqual(sceneType.components(separatedBy: "WindowGroup<").count - 1, 1)
        XCTAssertTrue(sceneType.contains("GraphiteWindowScene"))
        XCTAssertEqual(sceneType.components(separatedBy: "GuideView").count - 1, 1)
        XCTAssertEqual(sceneType.components(separatedBy: "Settings<").count - 1, 1)
    }
}
#endif
