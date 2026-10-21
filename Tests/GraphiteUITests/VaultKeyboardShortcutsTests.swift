import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A vault's `.obsidian/hotkeys.json` reaching the menu bar, the editor and the command palette,
/// and Settings › Keyboard Shortcuts writing it (`OB-18`, `ED-28`).
@MainActor
final class VaultKeyboardShortcutsTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    /// Bold on ⌃⌘B, a new note on ⌥⌘N, and an entry of an Obsidian plugin Graphite does not have.
    private let hotkeys = """
    {
      "editor:toggle-bold": [{"modifiers": ["Mod", "Ctrl"], "key": "B"}],
      "file-explorer:new-file": [{"modifiers": ["Mod", "Alt"], "key": "N"}],
      "obsidian-git:commit": [{"modifiers": ["Alt"], "key": "G"}]
    }
    """

    private func openedWorkspace(hotkeysFile: String?) async throws -> (WorkspaceModel, TemporaryVault) {
        var files = ["Note.md": "# Note\n"]
        if let hotkeysFile { files[HotkeyFile.configurationPath] = hotkeysFile }
        let vault = try TemporaryVault.make(prefix: "ShortcutsVault", files: files, for: self)
        let workspace = device.makeWorkspace()
        try await workspace.openFolderAsVault(vault.root)
        return (workspace, vault)
    }

    private func makeWindowActions() -> WindowActions {
        WindowActions(showQuickSwitcher: {}, showSettings: {}, showVaultManager: {}, toggleLinksInspector: {}, toggleSidebar: {}, showSidebar: {},
                      showLinksInspector: {}, create: { _ in }, showTemplatePicker: {}, toggleFocusMode: {})
    }

    func testTheVaultsFileReachesTheMenuBarTheEditorAndThePalette() async throws {
        let (workspace, _) = try await openedWorkspace(hotkeysFile: hotkeys)
        let shortcuts = workspace.keyboardShortcuts

        XCTAssertEqual(shortcuts.menuShortcut(for: .newNote), KeyboardShortcut("n", modifiers: [.command, .option]))
        XCTAssertEqual(shortcuts.menuShortcut(for: .newTab), KeyboardShortcut("t", modifiers: .command), "A command the file does not name keeps its default.")
        XCTAssertEqual(shortcuts.editorKeyCommands.command(matching: KeyCombination([.command, .control], .character("B"))), .toggleBold)
        XCTAssertNil(shortcuts.editorKeyCommands.command(matching: KeyCombination(.command, .character("B"))))

        let paletteCommand = try XCTUnwrap(WorkspaceCommandList.commands(for: workspace, window: makeWindowActions()).first { command in command.id == "new-note" })
        XCTAssertEqual(paletteCommand.shortcut, "⌥⌘N")
    }

    func testEveryPaletteShortcutIsTheOneTheListGivesItsCommand() async throws {
        let (workspace, _) = try await openedWorkspace(hotkeysFile: hotkeys)
        await workspace.open(try VaultPath("Note.md"))
        let table = workspace.keyboardShortcuts.builtInTable

        for command in WorkspaceCommandList.commands(for: workspace, window: makeWindowActions()) {
            let identifier = try XCTUnwrap(command.shortcutCommandIdentifier, "“\(command.title)” is in the list of commands.")
            XCTAssertNotNil(GraphiteCommand(rawValue: identifier), identifier)
            XCTAssertEqual(command.shortcutCombination, table.combinations(for: identifier).first, identifier)
        }
    }

    func testWhileAShortcutIsRecordedTheMenuBarGivesUpItsShortcuts() async throws {
        let (workspace, _) = try await openedWorkspace(hotkeysFile: nil)
        let shortcuts = workspace.keyboardShortcuts

        shortcuts.beginRecording(commandIdentifier: GraphiteCommand.toggleBold.identifier)
        XCTAssertNil(shortcuts.menuShortcut(for: .newNote))
        shortcuts.endRecording()
        XCTAssertEqual(shortcuts.menuShortcut(for: .newNote), KeyboardShortcut("n", modifiers: .command))
    }

    func testAChangeIsWrittenToTheVaultsFileKeepingCommandsGraphiteDoesNotHave() async throws {
        let (workspace, vault) = try await openedWorkspace(hotkeysFile: hotkeys)

        await workspace.changeKeyboardShortcuts(.assign(KeyCombination(.command, .character("T")), commandIdentifier: GraphiteCommand.newNotebook.identifier))

        XCTAssertNil(workspace.errorMessage)
        let written = try HotkeyFile(configurationData: Data(contentsOf: vault.location(of: HotkeyFile.configurationPath)))
        XCTAssertEqual(written.assignedCombinations(for: GraphiteCommand.newNotebook.identifier), [KeyCombination(.command, .character("T"))])
        XCTAssertEqual(written.assignedCombinations(for: GraphiteCommand.newTab.identifier), [], "New Tab gave ⌘T up.")
        XCTAssertEqual(written.assignedCombinations(for: "obsidian-git:commit"), [KeyCombination(.option, .character("G"))])
        XCTAssertNil(workspace.keyboardShortcuts.menuShortcut(for: .newTab))
        XCTAssertEqual(workspace.keyboardShortcuts.menuShortcut(for: .newNotebook), KeyboardShortcut("t", modifiers: .command))

        await workspace.changeKeyboardShortcuts(.resetAll)
        let reset = try HotkeyFile(configurationData: Data(contentsOf: vault.location(of: HotkeyFile.configurationPath)))
        XCTAssertEqual(Array(reset.entries.keys), ["obsidian-git:commit"])
    }

    func testADamagedFileLeavesTheDefaultsAndTheFileAsTheyWere() async throws {
        let damaged = "{ \"editor:toggle-bold\": ["
        let (workspace, vault) = try await openedWorkspace(hotkeysFile: damaged)

        XCTAssertNotNil(workspace.keyboardShortcuts.fileReading.unreadableReason)
        XCTAssertNotNil(workspace.errorMessage, "The person is told once.")
        XCTAssertEqual(workspace.keyboardShortcuts.menuShortcut(for: .newNote), KeyboardShortcut("n", modifiers: .command))
        workspace.errorMessage = nil

        await workspace.changeKeyboardShortcuts(.remove(commandIdentifier: GraphiteCommand.newNote.identifier))

        XCTAssertNotNil(workspace.errorMessage, "A change is refused while the file cannot be read.")
        XCTAssertEqual(try String(contentsOf: vault.location(of: HotkeyFile.configurationPath), encoding: .utf8), damaged)
        workspace.errorMessage = nil
        await workspace.reloadVaultSettings()
        XCTAssertNil(workspace.errorMessage, "Reading the same damaged file again does not tell the person again.")
    }

    func testCommunityPluginCommandsJoinTheListWithTheirDeclaredShortcuts() async throws {
        let (workspace, _) = try await openedWorkspace(hotkeysFile: hotkeys)
        let declared = CommunityPluginCommand(id: "obsidian-git:commit", name: "Git: Commit", needsEditor: false, pluginIdentifier: "obsidian-git",
                                              defaultCombinations: [KeyCombination([.command, .shift], .character("G"))])
        let other = CommunityPluginCommand(id: "quick-add:run", name: "QuickAdd: Run", needsEditor: false, pluginIdentifier: "quick-add",
                                           defaultCombinations: [KeyCombination([.command, .shift], .character("Q"))])

        let table = workspace.keyboardShortcuts.table(pluginCommands: [declared, other])

        XCTAssertEqual(table.combinations(for: "obsidian-git:commit"), [KeyCombination(.option, .character("G"))], "The vault's file changes a plugin's shortcut.")
        XCTAssertEqual(table.combinations(for: "quick-add:run"), [KeyCombination([.command, .shift], .character("Q"))])
        XCTAssertEqual(workspace.keyboardShortcuts.table(pluginCommands: []).combinations(for: "quick-add:run"), [], "A plugin turned off leaves the list.")
    }
}
