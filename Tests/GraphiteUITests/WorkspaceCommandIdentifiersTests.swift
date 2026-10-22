import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The command palette's commands through a workspace on a device of its own: the
/// identifiers the recent-commands list keeps (`ST-06`), and the sidebar and inspector panels
/// some of them remember in the device's preferences (`ST-07`).
@MainActor
final class WorkspaceCommandIdentifiersTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    /// What a window did when a command ran, for the commands that ask the window.
    private final class WindowRecorder {
        var shownSidebar = 0
        var shownLinksInspector = 0
    }

    private func makeWindowActions(_ recorder: WindowRecorder = WindowRecorder()) -> WindowActions {
        WindowActions(showQuickSwitcher: {}, showSettings: {}, showVaultManager: {}, toggleLinksInspector: {},
                      toggleSidebar: {}, showSidebar: { recorder.shownSidebar += 1 },
                      showLinksInspector: { recorder.shownLinksInspector += 1 },
                      create: { _ in }, showTemplatePicker: {}, toggleFocusMode: {})
    }

    private func openedWorkspace() async throws -> WorkspaceModel {
        let vault = try TemporaryVault.make(prefix: "CommandIdentifiersVault", files: ["Folder/Note.md": "# Heading\n\nText.\n"], for: self).root
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        await workspace.open(try VaultPath("Folder/Note.md"))
        return workspace
    }

    private func command(_ identifier: String, in workspace: WorkspaceModel, window: WindowActions) throws -> PaletteCommand {
        try XCTUnwrap(WorkspaceCommandList.commands(for: workspace, window: window).first { command in command.id == identifier }, identifier)
    }

    // MARK: ST-06

    func testAWorkspaceWithNoVaultOpenListsTheseCommandIdentifiers() {
        let identifiers = WorkspaceCommandList.commands(for: device.makeWorkspace(), window: makeWindowActions()).map(\.id)

        XCTAssertEqual(identifiers, Self.identifiersWithNoVaultOpen)
    }

    func testAWorkspaceWithANoteOpenListsTheseCommandIdentifiers() async throws {
        let workspace = try await openedWorkspace()

        let identifiers = WorkspaceCommandList.commands(for: workspace, window: makeWindowActions()).map(\.id)

        XCTAssertEqual(identifiers, Self.identifiersWithANoteOpen)
    }

    // MARK: ST-07

    func testOpeningTheLocalGraphAndTheLocalMapRememberTheRightSidebarPanelInTheWorkspacesPreferences() async throws {
        let workspace = try await openedWorkspace()
        let recorder = WindowRecorder()
        let window = makeWindowActions(recorder)

        try command("graph-local", in: workspace, window: window).run()
        XCTAssertEqual(device.defaults.string(forKey: "GraphiteInspectorPanel"), "graph")
        try command("map-local", in: workspace, window: window).run()
        XCTAssertEqual(device.defaults.string(forKey: "GraphiteInspectorPanel"), "map")

        XCTAssertEqual(recorder.shownLinksInspector, 2, "The right sidebar is shown for both.")
    }

    func testShowingBookmarksAndRevealingAFileRememberTheLeftSidebarPanelInTheWorkspacesPreferences() async throws {
        let workspace = try await openedWorkspace()
        let recorder = WindowRecorder()
        let window = makeWindowActions(recorder)

        try command("bookmarks-show", in: workspace, window: window).run()
        XCTAssertEqual(device.defaults.string(forKey: "sidebarPanel"), "bookmarks")
        try command("reveal", in: workspace, window: window).run()
        XCTAssertEqual(device.defaults.string(forKey: "sidebarPanel"), "files")
        XCTAssertEqual(workspace.expandedFolders, [try VaultPath("Folder")], "Revealing opens the folders above the file.")

        device.defaults.set("tags", forKey: "sidebarPanel")
        workspace.reveal(folder: try VaultPath("Folder"))
        XCTAssertEqual(device.defaults.string(forKey: "sidebarPanel"), "files")
        XCTAssertEqual(recorder.shownSidebar, 1, "Only the bookmarks command asks the window to show the sidebar.")
    }

    // MARK: Golden lists

    /// The identifiers as the palette lists them with the default core plugins and no vault open.
    static let identifiersWithNoVaultOpen = [
        "switcher", "search", "new-note", "new-notebook", "new-folder", "toggle-left-sidebar", "settings", "vaults", "collapse-folders",
        "new-base", "new-canvas", "new-tab", "close-tab", "pin-tab", "toggle-stacked-tabs", "split-right", "file-recovery-all", "workspace-focus",
        "graph-open", "map-open", "bookmarks-show", "daily-today", "daily-previous", "daily-next", "record", "record-video",
    ]

    /// The same with `Folder/Note.md` open in the only tab: the file, tab, note and editing commands join the list.
    static let identifiersWithANoteOpen = [
        "switcher", "search", "new-note", "new-notebook", "new-folder", "toggle-left-sidebar", "settings", "vaults", "collapse-folders",
        "new-base", "new-canvas", "new-tab", "close-tab", "pin-tab", "toggle-stacked-tabs", "split-right", "move-tab", "file-recovery-all", "file-recovery-note",
        "copy-url", "workspace-focus", "graph-open", "graph-local", "map-open", "map-local", "bookmarks-show", "bookmarks-file",
        "daily-today", "daily-previous", "daily-next", "rename", "move", "copy", "delete", "reveal",
        "toggle-reading", "toggle-source", "toggle-right-sidebar", "find-in-note", "replace-in-note", "toggle-fold", "fold-all", "unfold-all",
        "insert-template", "heading-1", "heading-2", "heading-3", "heading-4", "heading-5", "heading-6", "task", "table", "math", "callout",
        "new-notebook-in-note", "record", "record-video",
    ]
}
