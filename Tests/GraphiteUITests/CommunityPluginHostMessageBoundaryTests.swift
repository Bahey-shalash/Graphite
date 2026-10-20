import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// What a plugin's messages can change in Graphite: only the seven appearance settings Graphite
/// shares with Obsidian, and links that leave for the system only when they are web or mail
/// addresses. The messages are sent the way the runtime's page sends them, to a host whose
/// vault is open and whose plugins are off.
@MainActor
final class CommunityPluginHostMessageBoundaryTests: XCTestCase {
    private var vault: URL!
    private var workspace: WorkspaceModel!
    private var openedVaultIdentifier: UUID?

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "PluginMessageVault", for: self).root
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try Data("Note.\n".utf8).write(to: vault.appendingPathComponent("Note.md"))
        workspace = WorkspaceModel()
        try await workspace.openFolderAsVault(vault)
        openedVaultIdentifier = workspace.currentVaultIdentifier
    }

    override func tearDown() async throws {
        await workspace.saveVaultAppearanceNow()
        await workspace.communityPlugins.vaultWillClose()
        if let openedVaultIdentifier {
            workspace.vaultLibrary.remove(openedVaultIdentifier)
            CommunityPluginHost.forgetVault(openedVaultIdentifier)
        }
        workspace = nil
        try? FileManager.default.removeItem(at: vault)
    }

    private func setConfig(_ key: String, _ value: Any?) async {
        var message: [String: Any] = ["operation": "appearance.setConfig", "key": key]
        if let value { message["value"] = value }
        _ = await workspace.communityPlugins.answer(message)
    }

    // MARK: Appearance settings

    func testAPluginChangesEachOfTheSevenWhitelistedAppearanceSettings() async throws {
        let before = workspace.vaultAppearance
        XCTAssertEqual(before, ObsidianAppearance(), "The vault starts with Obsidian's defaults.")

        await setConfig("cssTheme", "Minimal")
        await setConfig("enabledCssSnippets", ["tweaks", "../escape", "wide"])
        await setConfig("textFontFamily", "Georgia")
        await setConfig("interfaceFontFamily", "Helvetica")
        await setConfig("monospaceFontFamily", "Menlo")
        await setConfig("baseFontSize", 18)
        await setConfig("baseFontSizeAction", true)

        let after = workspace.vaultAppearance
        XCTAssertEqual(after.cssTheme, "Minimal")
        XCTAssertEqual(after.enabledCssSnippets, ["tweaks", "wide"], "A snippet name that is not one file name is dropped.")
        XCTAssertEqual(after.textFontFamilies.obsidianValue, "Georgia")
        XCTAssertEqual(after.interfaceFontFamilies.obsidianValue, "Helvetica")
        XCTAssertEqual(after.monospaceFontFamilies.obsidianValue, "Menlo")
        XCTAssertEqual(after.baseFontSize, 18)
        XCTAssertTrue(after.adjustsFontSizeQuickly)
    }

    func testAPluginSettingAnyOtherKeyChangesNothing() async throws {
        await setConfig("cssTheme", "Minimal")
        let before = workspace.vaultAppearance

        let otherKeys: [(key: String, value: Any?)] = [
            ("accentColor", "#ff0000"), ("theme", "obsidian"), ("showInlineTitle", false), ("promptDelete", false),
            ("attachmentFolderPath", "../Outside"), ("newFileLocation", "folder"), ("alwaysUpdateLinks", true),
            ("", "x"), ("cssTheme ", "Other"), ("CSSTHEME", "Other"), ("__proto__", ["cssTheme": "Other"]),
            ("userIgnoreFilters", ["Secret"]), ("vimMode", true), ("readableLineLength", false),
        ]
        for (key, value) in otherKeys {
            await setConfig(key, value)
            XCTAssertEqual(workspace.vaultAppearance, before, "“\(key)” changes nothing.")
        }
        await setConfig("cssTheme", nil)
        XCTAssertEqual(workspace.vaultAppearance, before, "A whitelisted key without a value changes nothing either.")
        let message: [String: Any] = ["operation": "appearance.setConfig", "value": "x"]
        _ = await workspace.communityPlugins.answer(message)
        XCTAssertEqual(workspace.vaultAppearance, before, "A setting without a key changes nothing.")
    }

    func testAWhitelistedKeyWithTheWrongKindOfValueChangesNothing() async throws {
        await setConfig("cssTheme", "Minimal")
        let before = workspace.vaultAppearance

        await setConfig("cssTheme", "../Escape")
        await setConfig("cssTheme", 7)
        await setConfig("enabledCssSnippets", "tweaks")
        await setConfig("textFontFamily", ["Georgia"])
        await setConfig("baseFontSize", "18")
        await setConfig("baseFontSizeAction", "yes")

        XCTAssertEqual(workspace.vaultAppearance, before)
    }

    // MARK: Links that leave Graphite

    func testAPluginOpeningANonWebAddressIsIgnored() async throws {
        let host = workspace.communityPlugins
        let refusedAddresses = ["javascript:alert(1)", "file:///etc/hosts", "data:text/html,hi", "ftp://blocked.invalid/file", "tel:+41000000000", "graphite://open?note=x", "not an address", ""]
        for address in refusedAddresses {
            let answer = await host.answer(["operation": "workspace.openExternalLink", "address": address])
            XCTAssertEqual((answer as? [String: Any])?.isEmpty, true, "“\(address)” is answered with nothing and opens nothing.")
        }
    }
}
