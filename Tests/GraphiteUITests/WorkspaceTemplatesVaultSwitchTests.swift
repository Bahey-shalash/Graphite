import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The Templates and Daily notes settings belong to the vault they were read from. When the
/// next vault's settings files are there but cannot be read, nothing of the last vault's
/// settings stays in force: no daily note is created from them, and the template and daily
/// note actions are refused until the files can be read.
@MainActor
final class WorkspaceTemplatesVaultSwitchTests: XCTestCase {
    private let testBed = WorkspaceModelTestBed()

    override func tearDown() async throws {
        testBed.tearDown()
    }

    /// Larger than the 1 MiB an Obsidian settings file may hold, so it cannot be read.
    private static let oversizedSettingsFile = #"{"folder": ""# + String(repeating: "x", count: 1_100_000) + #""}"#

    func testUnreadableSettingsInTheNextVaultReplaceTheLastVaultsAndCreateNoDailyNote() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: [
            ".obsidian/daily-notes.json": #"{"folder": "Journal", "autorun": true}"#,
            ".obsidian/templates.json": #"{"folder": "Templates"}"#,
            "Templates/Meeting.md": "# Meeting\n",
        ])
        XCTAssertEqual(workspace.dailyNoteSettings.folder, "Journal", "The first vault's settings were read.")
        XCTAssertEqual(workspace.templateSettings.folder, "Templates")

        let nextVault = try testBed.makeVault(files: [
            ".obsidian/daily-notes.json": Self.oversizedSettingsFile,
            ".obsidian/templates.json": Self.oversizedSettingsFile,
            "Welcome.md": "Welcome\n",
        ])
        try await workspace.openFolderAsVault(nextVault)

        XCTAssertEqual(notes(in: nextVault), ["Welcome.md"], "No daily note is created from the last vault's settings.")
        XCTAssertEqual(workspace.dailyNoteSettings, DailyNoteSettings(), "Settings show nothing of the last vault.")
        XCTAssertEqual(workspace.templateSettings, TemplateSettings())
        XCTAssertNotNil(workspace.errorMessage, "The person is told the settings could not be read.")

        workspace.errorMessage = nil
        await workspace.openDailyNote()
        XCTAssertEqual(notes(in: nextVault), ["Welcome.md"], "Opening today's note is refused rather than run on defaults.")
        XCTAssertNotNil(workspace.errorMessage)
        XCTAssertEqual(workspace.templateFiles(), [], "No templates are offered while the Templates settings cannot be read.")
    }

    func testAVaultWhoseSettingsCanBeReadAgainHasItsTemplateAndDailyNoteActionsBack() async throws {
        let (workspace, _) = try await testBed.openedWorkspace(files: ["Welcome.md": "Welcome\n"])
        let nextVault = try testBed.makeVault(files: [".obsidian/daily-notes.json": Self.oversizedSettingsFile, "Welcome.md": "Welcome\n"])
        try await workspace.openFolderAsVault(nextVault)
        try #"{"folder": "Journal"}"#.write(to: nextVault.appendingPathComponent(".obsidian/daily-notes.json"), atomically: true, encoding: .utf8)

        await workspace.reloadVaultSettings()
        await workspace.openDailyNote()

        XCTAssertEqual(workspace.dailyNoteSettings.folder, "Journal")
        XCTAssertEqual(notes(in: nextVault).count, 2, "Today's note is created once the settings are read.")
        XCTAssertTrue(notes(in: nextVault).contains { path in path.hasPrefix("Journal/") })
    }

    /// The Markdown files of `vault`, by path inside it, sorted.
    private func notes(in vault: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(at: vault.resolvingSymlinksInPath(), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        let root = vault.resolvingSymlinksInPath().path + "/"
        var paths: [String] = []
        while let location = enumerator?.nextObject() as? URL {
            guard location.pathExtension == "md" else { continue }
            paths.append(String(location.resolvingSymlinksInPath().path.dropFirst(root.count)))
        }
        return paths.sorted()
    }
}
