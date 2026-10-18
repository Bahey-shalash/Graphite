import XCTest
@testable import GraphiteCore

/// A settings file Graphite cannot read is an error the person sees, never an empty result.
final class VaultStoreConfigurationReadingTests: XCTestCase {
    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: vault)
    }

    /// One byte over the 1 MiB limit on settings files.
    private func writeOversizedConfiguration(named fileName: String) throws {
        let oversizedBytes = 1_048_576 + 1
        try Data(repeating: 0x20, count: oversizedBytes).write(to: vault.appendingPathComponent(".obsidian/\(fileName)"))
    }

    func testBookmarksThrowForAFileOverTheSizeLimitInsteadOfShowingNone() async throws {
        try writeOversizedConfiguration(named: "bookmarks.json")
        let store = VaultStore(root: vault)
        do {
            _ = try await store.bookmarks()
            XCTFail("An unreadable bookmarks file must not read as an empty list.")
        } catch let error as GraphiteError {
            guard case .oversized = error else { return XCTFail("Expected the oversized error, got \(error).") }
        }
    }

    func testCommunityPluginListThrowsForAFileOverTheSizeLimit() async throws {
        try writeOversizedConfiguration(named: "community-plugins.json")
        let store = VaultStore(root: vault)
        do {
            _ = try await store.communityPluginList()
            XCTFail("An unreadable plugin list must not read as no plugins.")
        } catch let error as GraphiteError {
            guard case .oversized = error else { return XCTFail("Expected the oversized error, got \(error).") }
        }
    }

    func testTemplateAndDailyNoteSettingsThrowForAFileOverTheSizeLimit() async throws {
        try writeOversizedConfiguration(named: "templates.json")
        try writeOversizedConfiguration(named: "daily-notes.json")
        let store = VaultStore(root: vault)
        do {
            _ = try await store.templateSettings()
            XCTFail("An unreadable templates file must not read as the defaults.")
        } catch let error as GraphiteError {
            guard case .oversized = error else { return XCTFail("Expected the oversized error, got \(error).") }
        }
        do {
            _ = try await store.dailyNoteSettings()
            XCTFail("An unreadable daily notes file must not read as the defaults.")
        } catch let error as GraphiteError {
            guard case .oversized = error else { return XCTFail("Expected the oversized error, got \(error).") }
        }
    }

    func testUpdatingBookmarksFailsForAFileOverTheSizeLimitAndLeavesItAsItWas() async throws {
        try writeOversizedConfiguration(named: "bookmarks.json")
        let location = vault.appendingPathComponent(".obsidian/bookmarks.json")
        let before = try Data(contentsOf: location)
        let store = VaultStore(root: vault)
        do {
            try await store.updateBookmarks { bookmarks in bookmarks.add(.search("todo")) }
            XCTFail("The update must fail rather than start from an empty list.")
        } catch is GraphiteError {}
        XCTAssertEqual(try Data(contentsOf: location), before)
    }

    func testMissingSettingsFilesStillReadAsEmptyOrDefault() async throws {
        let store = VaultStore(root: vault)
        let bookmarks = try await store.bookmarks()
        XCTAssertEqual(bookmarks.items, [])
        let plugins = try await store.communityPluginList()
        XCTAssertEqual(plugins.enabledIdentifiers, [])
        let templates = try await store.templateSettings()
        XCTAssertEqual(templates, TemplateSettings())
    }
}
