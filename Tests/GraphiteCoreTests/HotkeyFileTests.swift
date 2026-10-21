import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// `.obsidian/hotkeys.json` as Obsidian writes it, read and written by `HotkeyFile` and the
/// vault store (`OB-18`).
final class HotkeyFileTests: XCTestCase {
    /// As Obsidian writes it, with a command Graphite does not have and an entry in a form it
    /// cannot read.
    private let obsidianFile = """
    {
      "editor:toggle-bold": [
        {
          "modifiers": [
            "Mod",
            "Shift"
          ],
          "key": "B"
        }
      ],
      "editor:toggle-italics": [],
      "obsidian-git:commit": [
        {
          "modifiers": [
            "Alt"
          ],
          "key": "G",
          "futureField": 3
        }
      ],
      "editor:swap-line-up": "not a list"
    }
    """

    private func file() throws -> HotkeyFile { try HotkeyFile(configurationData: Data(obsidianFile.utf8)) }

    func testReadsAssignedShortcutsRemovedShortcutsAndEntriesItCannotRead() throws {
        let hotkeys = try file()
        XCTAssertEqual(hotkeys.assignedCombinations(for: "editor:toggle-bold"), [KeyCombination([.command, .shift], .character("B"))])
        XCTAssertEqual(hotkeys.assignedCombinations(for: "editor:toggle-italics"), [], "An empty list means the shortcuts were removed.")
        XCTAssertNil(hotkeys.assignedCombinations(for: "editor:swap-line-up"), "An entry in another form leaves the command its defaults.")
        XCTAssertNil(hotkeys.assignedCombinations(for: "editor:toggle-code"), "A command the file does not name keeps its defaults.")
    }

    func testAWriteKeepsTheEntriesOfCommandsGraphiteDoesNotHaveAndThoseItCannotRead() throws {
        var hotkeys = try file()
        hotkeys.assign([KeyCombination(.command, .character("J"))], to: "editor:toggle-bold")
        let written = try HotkeyFile(configurationData: hotkeys.configurationData())
        let original = try file()

        XCTAssertEqual(written.entries["obsidian-git:commit"], original.entries["obsidian-git:commit"], "Every field, unknown ones included, round-trips.")
        XCTAssertEqual(written.entries["editor:swap-line-up"], .string("not a list"))
        XCTAssertEqual(written.assignedCombinations(for: "editor:toggle-bold"), [KeyCombination(.command, .character("J"))])
    }

    func testIsWrittenAsJavaScriptsJSONStringifyLaysItOut() {
        var hotkeys = HotkeyFile()
        hotkeys.assign([KeyCombination([.command, .option, .shift], .named(.arrowUp))], to: "editor:swap-line-up")
        hotkeys.assign([], to: "editor:toggle-bold")
        let expected = """
        {
          "editor:swap-line-up": [
            {
              "key": "ArrowUp",
              "modifiers": [
                "Mod",
                "Alt",
                "Shift"
              ]
            }
          ],
          "editor:toggle-bold": []
        }
        """
        XCTAssertEqual(String(decoding: hotkeys.configurationData(), as: UTF8.self), expected)
    }

    func testAMissingOrBlankFileHasNoChanges() throws {
        XCTAssertEqual(try HotkeyFile(configurationData: nil), HotkeyFile())
        XCTAssertEqual(try HotkeyFile(configurationData: Data(" \n".utf8)), HotkeyFile())
    }

    func testAFileThatIsNotJSONOrNotAnObjectCannotBeRead() {
        XCTAssertThrowsError(try HotkeyFile(configurationData: Data("{ \"editor:toggle-bold\": [".utf8))) { error in
            XCTAssertEqual(error as? HotkeyFileProblem, .notJSON)
        }
        XCTAssertThrowsError(try HotkeyFile(configurationData: Data("[]".utf8))) { error in
            XCTAssertEqual(error as? HotkeyFileProblem, .notAnObject)
        }
    }

    // MARK: Through the vault store

    func testADamagedFileIsLeftAsItIsAndNoChangeIsWritten() async throws {
        let damaged = "{ \"editor:toggle-bold\": [ broken"
        let vault = try TemporaryVault.make(prefix: "DamagedHotkeys", files: [HotkeyFile.configurationPath: damaged], for: self)
        let store = VaultStore(root: vault.root)

        do {
            _ = try await store.hotkeys()
            XCTFail("A damaged file cannot be read.")
        } catch {
            XCTAssertEqual(error as? HotkeyFileProblem, .notJSON)
        }
        do {
            try await store.updateHotkeys { file in
                var changed = file
                changed.assign([], to: "editor:toggle-bold")
                return changed
            }
            XCTFail("A damaged file is never written.")
        } catch {
            XCTAssertEqual(error as? HotkeyFileProblem, .notJSON)
        }
        XCTAssertEqual(try String(contentsOf: vault.location(of: HotkeyFile.configurationPath), encoding: .utf8), damaged)
    }

    func testAVaultWithoutTheFileGetsOneOnlyWhenThereIsAChange() async throws {
        let vault = try TemporaryVault.make(prefix: "NoHotkeys", for: self)
        let store = VaultStore(root: vault.root)
        let location = vault.location(of: HotkeyFile.configurationPath)

        try await store.updateHotkeys { file in file }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))

        try await store.updateHotkeys { file in
            var changed = file
            changed.assign([KeyCombination(.command, .character("J"))], to: "editor:toggle-bold")
            return changed
        }
        let written = try await store.hotkeys()
        XCTAssertEqual(written.assignedCombinations(for: "editor:toggle-bold"), [KeyCombination(.command, .character("J"))])
    }

    func testAnUnchangedFileKeepsItsBytes() async throws {
        let vault = try TemporaryVault.make(prefix: "UnchangedHotkeys", files: [HotkeyFile.configurationPath: obsidianFile], for: self)
        let store = VaultStore(root: vault.root)

        try await store.updateHotkeys { file in file }

        XCTAssertEqual(try String(contentsOf: vault.location(of: HotkeyFile.configurationPath), encoding: .utf8), obsidianFile)
    }
}
