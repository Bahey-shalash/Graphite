import XCTest
import GraphiteCore
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// "Open in New Window" and ⇧⌥⌘ on a link ask the window's scene for a window on the same
/// vault showing the file, without touching this window's tabs.
@MainActor
final class OpenInNewWindowTests: XCTestCase {
    func testOpeningInANewWindowAsksForAWindowOnTheVaultShowingTheFile() async throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        let vault = try TemporaryVault.make(prefix: "NewWindowVault", for: self).root.resolvingSymlinksInPath()
        try Data("text".utf8).write(to: vault.appendingPathComponent("Lecture.md"))
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        let tabCount = workspace.layout.allTabs.count

        let tabID = await workspace.open(try VaultPath("Lecture.md"), placement: .newWindow)

        XCTAssertNil(tabID)
        XCTAssertEqual(workspace.newWindowRequest, GraphiteWindowContent(vaultIdentifier: workspace.currentVaultIdentifier, opensFreshTabs: true, filePath: "Lecture.md"))
        XCTAssertEqual(workspace.layout.allTabs.count, tabCount, "This window's tabs stay as they were.")
        XCTAssertNil(workspace.selection)
    }

    func testALinkClickedWithShiftOptionCommandOpensInANewWindow() {
        XCTAssertEqual(TabPlacement.forLink(command: false, option: false, shift: false), .currentTab)
        XCTAssertEqual(TabPlacement.forLink(command: true, option: false, shift: false), .newTab)
        XCTAssertEqual(TabPlacement.forLink(command: true, option: true, shift: false), .otherGroup)
        XCTAssertEqual(TabPlacement.forLink(command: true, option: true, shift: true), .newWindow)
        XCTAssertEqual(TabPlacement.forLink(command: false, option: true, shift: true), .currentTab)
    }
}
