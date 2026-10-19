import XCTest
@testable import GraphiteCore

/// How much `CommunityPluginInstaller` accepts from the plugin directory and a plugin's
/// release: exactly the cap is installed, one byte over is refused with `oversized` before
/// anything is written. The session answers from memory, so no request leaves the process.
final class CommunityPluginInstallerSizeLimitTests: XCTestCase {
    private static let mebibyte = 1_048_576
    private static let repository = "owner/sample-plugin"
    private static let currentManifestAddress = "https://raw.githubusercontent.com/owner/sample-plugin/HEAD/manifest.json"
    private static let versionsAddress = "https://raw.githubusercontent.com/owner/sample-plugin/HEAD/versions.json"
    private static let releaseFolderAddress = "https://github.com/owner/sample-plugin/releases/download/1.0.0/"
    private static let manifestText = #"{"id": "sample", "name": "Sample", "version": "1.0.0", "minAppVersion": "1.0.0"}"#
    private static let manifestNeedingNewerObsidianText = #"{"id": "sample", "name": "Sample", "version": "1.0.0", "minAppVersion": "99.0.0"}"#

    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("PluginInstallVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    // MARK: Helpers

    private func installer(answering answers: [String: Data]) -> CommunityPluginInstaller {
        let session = CommunityPluginDownloadStub.session { address in
            answers[address.absoluteString].map { body in .ok(body) } ?? .notFound
        }
        return CommunityPluginInstaller(store: VaultStore(root: vault), session: session)
    }

    /// The answers of a plugin with a normal release, with `overrides` replacing some of them.
    private func releaseAnswers(overriding overrides: [String: Data] = [:]) -> [String: Data] {
        let manifest = Data(Self.manifestText.utf8)
        let normal: [String: Data] = [
            Self.currentManifestAddress: manifest,
            Self.releaseFolderAddress + "manifest.json": manifest,
            Self.releaseFolderAddress + "main.js": Data("module.exports = {};".utf8),
        ]
        return normal.merging(overrides) { _, override in override }
    }

    private func assertOversized(_ description: String, file: StaticString = #filePath, line: UInt = #line, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("\(description) should have been refused as oversized.", file: file, line: line)
        } catch GraphiteError.oversized {
        } catch {
            XCTFail("\(description) failed with \(error) instead of oversized.", file: file, line: line)
        }
    }

    private func assertNothingWritten(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian/plugins").path), "A refused download writes nothing.", file: file, line: line)
    }

    private func assertOnlyGitHubWasAsked(file: StaticString = #filePath, line: UInt = #line) {
        let hosts = Set(CommunityPluginDownloadStub.requestedAddresses.compactMap(\.host))
        XCTAssertTrue(hosts.isSubset(of: ["raw.githubusercontent.com", "github.com"]), "\(hosts)", file: file, line: line)
    }

    // MARK: Caps

    func testTheCapsAreTheDocumentedSizes() {
        XCTAssertEqual(CommunityPluginInstaller.maximumDirectoryBytes, 16 * Self.mebibyte)
        XCTAssertEqual(CommunityPluginInstaller.maximumSmallFileBytes, Self.mebibyte)
        XCTAssertEqual(CommunityPluginManifest.maximumManifestBytes, 256 * 1024)
        XCTAssertEqual(VaultStore.maximumPluginScriptBytes, 48 * Self.mebibyte)
        XCTAssertEqual(VaultStore.maximumPluginStylesBytes, 8 * Self.mebibyte)
    }

    func testThePluginDirectoryIsReadAtSixteenMebibytesAndRefusedOneByteOver() async throws {
        let cap = CommunityPluginInstaller.maximumDirectoryBytes
        let atCap = installer(answering: [CommunityPluginInstaller.directoryAddress: paddedJSON("[]", toBytes: cap)])
        let entries = try await atCap.directory()
        XCTAssertTrue(entries.isEmpty)

        let overCap = installer(answering: [CommunityPluginInstaller.directoryAddress: paddedJSON("[]", toBytes: cap + 1)])
        await assertOversized("The directory one byte over") { _ = try await overCap.directory() }
        assertOnlyGitHubWasAsked()
    }

    func testAPluginManifestIsInstalledAtTwoHundredFiftySixKibibytesAndRefusedOneByteOver() async throws {
        let cap = CommunityPluginManifest.maximumManifestBytes
        let atCap = installer(answering: releaseAnswers(overriding: [
            Self.currentManifestAddress: paddedJSON(Self.manifestText, toBytes: cap),
            Self.releaseFolderAddress + "manifest.json": paddedJSON(Self.manifestText, toBytes: cap),
        ]))
        let installation = try await atCap.install(repository: Self.repository, expectedIdentifier: "sample")
        XCTAssertEqual(installation.manifest.identifier, "sample")
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent(".obsidian/plugins/sample/manifest.json")).count, cap)

        try FileManager.default.removeItem(at: vault.appendingPathComponent(".obsidian"))
        let overCurrentManifest = installer(answering: releaseAnswers(overriding: [Self.currentManifestAddress: paddedJSON(Self.manifestText, toBytes: cap + 1)]))
        await assertOversized("The repository's manifest one byte over") { _ = try await overCurrentManifest.install(repository: Self.repository, expectedIdentifier: "sample") }
        let overReleaseManifest = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "manifest.json": paddedJSON(Self.manifestText, toBytes: cap + 1)]))
        await assertOversized("The release's manifest one byte over") { _ = try await overReleaseManifest.install(repository: Self.repository, expectedIdentifier: "sample") }
        assertNothingWritten()
        assertOnlyGitHubWasAsked()
    }

    func testVersionsFileIsReadAtOneMebibyteAndRefusedOneByteOver() async throws {
        let cap = CommunityPluginInstaller.maximumSmallFileBytes
        let versionsText = #"{"1.0.0": "0.1.0"}"#
        let overrides: [String: Data] = [Self.currentManifestAddress: Data(Self.manifestNeedingNewerObsidianText.utf8)]

        let atCap = installer(answering: releaseAnswers(overriding: overrides.merging([Self.versionsAddress: paddedJSON(versionsText, toBytes: cap)]) { _, override in override }))
        let installation = try await atCap.install(repository: Self.repository, expectedIdentifier: "sample")
        XCTAssertTrue(installation.isOlderReleaseForCompatibility, "The versions file at the cap was read and chose the older release.")

        try FileManager.default.removeItem(at: vault.appendingPathComponent(".obsidian"))
        let overCap = installer(answering: releaseAnswers(overriding: overrides.merging([Self.versionsAddress: paddedJSON(versionsText, toBytes: cap + 1)]) { _, override in override }))
        await assertOversized("versions.json one byte over") { _ = try await overCap.install(repository: Self.repository, expectedIdentifier: "sample") }
        assertNothingWritten()
    }

    func testMainScriptIsInstalledAtFortyEightMebibytesAndRefusedOneByteOver() async throws {
        let cap = VaultStore.maximumPluginScriptBytes
        let atCap = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "main.js": Data(count: cap)]))
        _ = try await atCap.install(repository: Self.repository, expectedIdentifier: "sample")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent(".obsidian/plugins/sample/main.js").path)[.size] as? Int, cap)

        try FileManager.default.removeItem(at: vault.appendingPathComponent(".obsidian"))
        let overCap = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "main.js": Data(count: cap + 1)]))
        await assertOversized("main.js one byte over") { _ = try await overCap.install(repository: Self.repository, expectedIdentifier: "sample") }
        assertNothingWritten()
    }

    func testStylesAreInstalledAtEightMebibytesAndRefusedOneByteOver() async throws {
        let cap = VaultStore.maximumPluginStylesBytes
        let atCap = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "styles.css": Data(count: cap)]))
        _ = try await atCap.install(repository: Self.repository, expectedIdentifier: "sample")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent(".obsidian/plugins/sample/styles.css").path)[.size] as? Int, cap)

        try FileManager.default.removeItem(at: vault.appendingPathComponent(".obsidian"))
        let overCap = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "styles.css": Data(count: cap + 1)]))
        await assertOversized("styles.css one byte over") { _ = try await overCap.install(repository: Self.repository, expectedIdentifier: "sample") }
        assertNothingWritten()
        assertOnlyGitHubWasAsked()
    }
}
