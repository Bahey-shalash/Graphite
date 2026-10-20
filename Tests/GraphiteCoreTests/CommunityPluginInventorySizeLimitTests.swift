import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// How large the files of an installed plugin can be before Graphite will not read them:
/// the manifest, `main.js` and `styles.css`. Exactly the cap is read, one byte over is
/// refused with `oversized` and the plugin is listed as unreadable.
final class CommunityPluginInventorySizeLimitTests: XCTestCase {
    private static let mebibyte = 1_048_576
    private static let manifestText = #"{"id": "sample", "name": "Sample", "version": "1.0.0", "minAppVersion": "1.0.0"}"#

    private var vault: URL!

    override func setUpWithError() throws {
        vault = try TemporaryVault.make(prefix: "PluginSizeVault", for: self).root
    }

    private func installPlugin(manifest: Data, mainScript: Data, styles: Data? = nil) throws {
        let folder = vault.appendingPathComponent(".obsidian/plugins/sample", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try manifest.write(to: folder.appendingPathComponent("manifest.json"))
        try mainScript.write(to: folder.appendingPathComponent("main.js"))
        if let styles { try styles.write(to: folder.appendingPathComponent("styles.css")) }
    }

    private func assertOversized(file: StaticString = #filePath, line: UInt = #line, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("The read should have been refused as oversized.", file: file, line: line)
        } catch GraphiteError.oversized {
        } catch {
            XCTFail("The read failed with \(error) instead of oversized.", file: file, line: line)
        }
    }

    func testAManifestOnDiskIsReadAtTwoHundredFiftySixKibibytesAndTheFolderIsUnreadableOneByteOver() async throws {
        let cap = CommunityPluginManifest.maximumManifestBytes
        let script = Data("module.exports = {};".utf8)
        try installPlugin(manifest: paddedJSON(Self.manifestText, toBytes: cap), mainScript: script)
        let atCap = try await VaultStore(root: vault).installedCommunityPlugins()
        XCTAssertEqual(atCap.plugins.map(\.id), ["sample"])
        XCTAssertTrue(atCap.unreadableFolders.isEmpty)

        try installPlugin(manifest: paddedJSON(Self.manifestText, toBytes: cap + 1), mainScript: script)
        let overCap = try await VaultStore(root: vault).installedCommunityPlugins()
        XCTAssertTrue(overCap.plugins.isEmpty)
        XCTAssertEqual(overCap.unreadableFolders.map(\.folder.rawValue), [".obsidian/plugins/sample"])
    }

    func testMainScriptOnDiskIsReadAtFortyEightMebibytesAndRefusedOneByteOver() async throws {
        let cap = VaultStore.maximumPluginScriptBytes
        let manifest = Data(Self.manifestText.utf8)
        try installPlugin(manifest: manifest, mainScript: Data(repeating: UInt8(ascii: " "), count: cap))
        let store = VaultStore(root: vault)
        let atCap = try await store.installedCommunityPlugins()
        XCTAssertEqual(atCap.plugins.map(\.id), ["sample"])
        let package = try await store.communityPluginPackage(for: try XCTUnwrap(atCap.plugins.first))
        XCTAssertEqual(package.mainScript.utf8.count, cap)

        try installPlugin(manifest: manifest, mainScript: Data(repeating: UInt8(ascii: " "), count: cap + 1))
        let overCap = try await store.installedCommunityPlugins()
        XCTAssertTrue(overCap.plugins.isEmpty)
        XCTAssertEqual(overCap.unreadableFolders.map(\.folder.rawValue), [".obsidian/plugins/sample"])
        await assertOversized { _ = try await store.communityPluginPackage(for: try XCTUnwrap(atCap.plugins.first)) }
    }

    func testStylesOnDiskAreReadAtEightMebibytesAndRefusedOneByteOver() async throws {
        let cap = VaultStore.maximumPluginStylesBytes
        let manifest = Data(Self.manifestText.utf8)
        let script = Data("module.exports = {};".utf8)
        try installPlugin(manifest: manifest, mainScript: script, styles: Data(repeating: UInt8(ascii: " "), count: cap))
        let store = VaultStore(root: vault)
        let installed = try await store.installedCommunityPlugins()
        let plugin = try XCTUnwrap(installed.plugins.first)
        let package = try await store.communityPluginPackage(for: plugin)
        XCTAssertEqual(package.styles.utf8.count, cap)

        try installPlugin(manifest: manifest, mainScript: script, styles: Data(repeating: UInt8(ascii: " "), count: cap + 1))
        await assertOversized { _ = try await store.communityPluginPackage(for: plugin) }
    }
}
