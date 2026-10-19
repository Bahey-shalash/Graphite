import XCTest
@testable import GraphiteCore

/// How much `ObsidianThemeInstaller` accepts from the theme directory and a theme's release,
/// and how large a theme or snippet file in the vault is read. Exactly the cap works, one
/// byte over is refused, and the session answers from memory so nothing leaves the process.
final class ObsidianThemeInstallerSizeLimitTests: XCTestCase {
    private static let mebibyte = 1_048_576
    private static let entry = ObsidianThemeDirectoryEntry(name: "Mint", author: "Someone", repo: "owner/mint-theme")
    private static let currentManifestAddress = "https://raw.githubusercontent.com/owner/mint-theme/HEAD/manifest.json"
    private static let releaseFolderAddress = "https://github.com/owner/mint-theme/releases/download/1.0.0/"
    private static let manifestText = #"{"name": "Mint", "version": "1.0.0"}"#

    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("ThemeInstallVault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    private func installer(answering answers: [String: Data]) -> ObsidianThemeInstaller {
        let session = CommunityPluginDownloadStub.session { address in
            answers[address.absoluteString].map { body in .ok(body) } ?? .notFound
        }
        return ObsidianThemeInstaller(store: VaultStore(root: vault), session: session)
    }

    private func releaseAnswers(overriding overrides: [String: Data] = [:]) -> [String: Data] {
        let manifest = Data(Self.manifestText.utf8)
        let normal: [String: Data] = [
            Self.currentManifestAddress: manifest,
            Self.releaseFolderAddress + "manifest.json": manifest,
            Self.releaseFolderAddress + "theme.css": Data("body {}".utf8),
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent(".obsidian").path), "A refused download writes nothing.", file: file, line: line)
    }

    private func assertOnlyGitHubWasAsked(file: StaticString = #filePath, line: UInt = #line) {
        let hosts = Set(CommunityPluginDownloadStub.requestedAddresses.compactMap(\.host))
        XCTAssertTrue(hosts.isSubset(of: ["raw.githubusercontent.com", "github.com"]), "\(hosts)", file: file, line: line)
    }

    // MARK: Downloads

    func testTheCapsAreTheDocumentedSizes() {
        XCTAssertEqual(ObsidianThemeInstaller.maximumDirectoryBytes, 8 * Self.mebibyte)
        XCTAssertEqual(ObsidianThemeInstaller.maximumManifestBytes, 64 * 1024)
        XCTAssertEqual(ObsidianStyleFiles.maximumThemeBytes, 8 * Self.mebibyte)
        XCTAssertEqual(ObsidianStyleFiles.maximumSnippetBytes, Self.mebibyte)
    }

    func testTheThemeDirectoryIsReadAtEightMebibytesAndRefusedOneByteOver() async throws {
        let cap = ObsidianThemeInstaller.maximumDirectoryBytes
        let atCap = installer(answering: [ObsidianThemeInstaller.directoryAddress: paddedJSON("[]", toBytes: cap)])
        let entries = try await atCap.directory()
        XCTAssertTrue(entries.isEmpty)

        let overCap = installer(answering: [ObsidianThemeInstaller.directoryAddress: paddedJSON("[]", toBytes: cap + 1)])
        await assertOversized("The directory one byte over") { _ = try await overCap.directory() }
        assertOnlyGitHubWasAsked()
    }

    func testAThemeManifestIsInstalledAtSixtyFourKibibytesAndRefusedOneByteOver() async throws {
        let cap = ObsidianThemeInstaller.maximumManifestBytes
        let atCap = installer(answering: releaseAnswers(overriding: [
            Self.currentManifestAddress: paddedJSON(Self.manifestText, toBytes: cap),
            Self.releaseFolderAddress + "manifest.json": paddedJSON(Self.manifestText, toBytes: cap),
        ]))
        try await atCap.install(Self.entry)
        XCTAssertEqual(try Data(contentsOf: vault.appendingPathComponent(".obsidian/themes/Mint/manifest.json")).count, cap)

        try FileManager.default.removeItem(at: vault.appendingPathComponent(".obsidian"))
        let overCurrentManifest = installer(answering: releaseAnswers(overriding: [Self.currentManifestAddress: paddedJSON(Self.manifestText, toBytes: cap + 1)]))
        await assertOversized("The repository's manifest one byte over") { try await overCurrentManifest.install(Self.entry) }
        let overReleaseManifest = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "manifest.json": paddedJSON(Self.manifestText, toBytes: cap + 1)]))
        await assertOversized("The release's manifest one byte over") { try await overReleaseManifest.install(Self.entry) }
        assertNothingWritten()
        assertOnlyGitHubWasAsked()
    }

    func testAThemeStyleSheetIsInstalledAtEightMebibytesAndRefusedOneByteOver() async throws {
        let cap = ObsidianStyleFiles.maximumThemeBytes
        let atCap = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "theme.css": Data(count: cap)]))
        try await atCap.install(Self.entry)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent(".obsidian/themes/Mint/theme.css").path)[.size] as? Int, cap)

        try FileManager.default.removeItem(at: vault.appendingPathComponent(".obsidian"))
        let overCap = installer(answering: releaseAnswers(overriding: [Self.releaseFolderAddress + "theme.css": Data(count: cap + 1)]))
        await assertOversized("theme.css one byte over") { try await overCap.install(Self.entry) }
        assertNothingWritten()
    }

    // MARK: Files already in the vault

    func testAThemeInTheVaultIsReadAtEightMebibytesAndLeftOutOneByteOver() async throws {
        let cap = ObsidianStyleFiles.maximumThemeBytes
        let themeFolder = vault.appendingPathComponent(".obsidian/themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themeFolder.appendingPathComponent("AtCap"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: themeFolder.appendingPathComponent("OverCap"), withIntermediateDirectories: true)
        try Data(repeating: UInt8(ascii: "a"), count: cap).write(to: themeFolder.appendingPathComponent("AtCap/theme.css"))
        try Data(repeating: UInt8(ascii: "a"), count: cap + 1).write(to: themeFolder.appendingPathComponent("OverCap/theme.css"))

        let store = VaultStore(root: vault)
        let themeAtCap = await store.themeStyleSheet(named: "AtCap")
        XCTAssertEqual(themeAtCap?.utf8.count, cap)
        let themeOverCap = await store.themeStyleSheet(named: "OverCap")
        XCTAssertNil(themeOverCap)
    }

    func testASnippetInTheVaultIsReadAtOneMebibyteAndLeftOutOneByteOver() async throws {
        let cap = ObsidianStyleFiles.maximumSnippetBytes
        let snippetFolder = vault.appendingPathComponent(".obsidian/snippets", isDirectory: true)
        try FileManager.default.createDirectory(at: snippetFolder, withIntermediateDirectories: true)
        try Data(repeating: UInt8(ascii: "a"), count: cap).write(to: snippetFolder.appendingPathComponent("at-cap.css"))
        try Data(repeating: UInt8(ascii: "a"), count: cap + 1).write(to: snippetFolder.appendingPathComponent("over-cap.css"))

        let store = VaultStore(root: vault)
        let snippetAtCap = await store.snippetStyleSheet(named: "at-cap")
        XCTAssertEqual(snippetAtCap?.utf8.count, cap)
        let snippetOverCap = await store.snippetStyleSheet(named: "over-cap")
        XCTAssertNil(snippetOverCap)
    }
}
