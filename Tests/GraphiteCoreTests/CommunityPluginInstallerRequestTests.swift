import XCTest
@testable import GraphiteCore
import GraphiteTestSupport

/// The web addresses `CommunityPluginInstaller` and `ObsidianThemeInstaller` ask for, in order,
/// and which release they install: the repository's current manifest names the version, a
/// newer `minAppVersion` than the provided plugin API falls back to `versions.json`, and every
/// manifest must carry the identifier the plugin is installed under.
final class CommunityPluginInstallerRequestTests: XCTestCase {
    private var vaultFolder: URL!
    private var store: VaultStore!

    override func setUpWithError() throws {
        vaultFolder = try TemporaryVault.make(prefix: "InstallerVault", for: self).root
        store = VaultStore(root: vaultFolder)
        ScriptedGitHubProtocol.script.reset()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vaultFolder)
        ScriptedGitHubProtocol.script.reset()
    }

    private func scriptedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedGitHubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func pluginManifest(identifier: String = "sample", version: String, minimumApplicationVersion: String = "1.0.0") -> String {
        "{\"id\": \"\(identifier)\", \"name\": \"Sample\", \"version\": \"\(version)\", \"minAppVersion\": \"\(minimumApplicationVersion)\", \"author\": \"Someone\", \"description\": \"A sample.\"}"
    }

    private func installedText(_ relativePath: String) throws -> String {
        try String(contentsOf: vaultFolder.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func installedFileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: vaultFolder.appendingPathComponent(relativePath).path)
    }

    // MARK: Plugins

    func testAnInstallAsksForTheHeadManifestThenTheNamedReleasesFilesInOrder() async throws {
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json", pluginManifest(version: "1.2.0"))
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/1.2.0/main.js", "module.exports = 1;")
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/1.2.0/manifest.json", pluginManifest(version: "1.2.0"))
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/1.2.0/styles.css", ".sample { color: red; }")

        let installation = try await CommunityPluginInstaller(store: store, session: scriptedSession())
            .install(repository: "owner/sample-repo", expectedIdentifier: "sample")

        XCTAssertEqual(ScriptedGitHubProtocol.script.requestedAddresses, [
            "https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json",
            "https://github.com/owner/sample-repo/releases/download/1.2.0/main.js",
            "https://github.com/owner/sample-repo/releases/download/1.2.0/manifest.json",
            "https://github.com/owner/sample-repo/releases/download/1.2.0/styles.css",
        ])
        XCTAssertEqual(installation.folder.rawValue, ".obsidian/plugins/sample")
        XCTAssertFalse(installation.isOlderReleaseForCompatibility)
        XCTAssertEqual(try installedText(".obsidian/plugins/sample/main.js"), "module.exports = 1;")
        XCTAssertEqual(try installedText(".obsidian/plugins/sample/styles.css"), ".sample { color: red; }")
        XCTAssertEqual(try installedText(".obsidian/plugins/sample/manifest.json"), pluginManifest(version: "1.2.0"), "the release's manifest is written byte for byte")
    }

    func testAMinimumVersionAboveTheProvidedApiInstallsTheNewestCompatibleReleaseFromVersionsJson() async throws {
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json", pluginManifest(version: "3.0.0", minimumApplicationVersion: "1.14.5"))
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/sample-repo/HEAD/versions.json", "{\"3.0.0\": \"1.14.5\", \"2.1.0\": \"1.14.4\", \"2.0.0\": \"0.15.0\", \"2.2.0-beta.1\": \"1.14.5\"}")
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/2.1.0/main.js", "module.exports = 2;")
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/2.1.0/manifest.json", pluginManifest(version: "2.1.0", minimumApplicationVersion: "1.14.4"))

        let installation = try await CommunityPluginInstaller(store: store, session: scriptedSession())
            .install(repository: "owner/sample-repo", expectedIdentifier: nil, providedApiVersion: "1.14.4")

        XCTAssertEqual(ScriptedGitHubProtocol.script.requestedAddresses, [
            "https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json",
            "https://raw.githubusercontent.com/owner/sample-repo/HEAD/versions.json",
            "https://github.com/owner/sample-repo/releases/download/2.1.0/main.js",
            "https://github.com/owner/sample-repo/releases/download/2.1.0/manifest.json",
            "https://github.com/owner/sample-repo/releases/download/2.1.0/styles.css",
        ])
        XCTAssertTrue(installation.isOlderReleaseForCompatibility)
        XCTAssertEqual(installation.manifest.version, "2.1.0")
        XCTAssertFalse(installedFileExists(".obsidian/plugins/sample/styles.css"), "a release without styles.css installs none")
    }

    func testAMinimumVersionEqualToTheProvidedApiNeedsNoVersionsJson() async throws {
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json", pluginManifest(version: "1.0.0", minimumApplicationVersion: "1.14.4"))
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/1.0.0/main.js", "module.exports = 3;")
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/1.0.0/manifest.json", pluginManifest(version: "1.0.0", minimumApplicationVersion: "1.14.4"))

        _ = try await CommunityPluginInstaller(store: store, session: scriptedSession())
            .install(repository: "owner/sample-repo", expectedIdentifier: "sample")

        XCTAssertFalse(ScriptedGitHubProtocol.script.requestedAddresses.contains { address in address.hasSuffix("/versions.json") })
    }

    func testAMissingVersionsJsonRefusesAnInstallThatNeedsANewerApiAndWritesNothing() async throws {
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json", pluginManifest(version: "3.0.0", minimumApplicationVersion: "9.0.0"))

        do {
            _ = try await CommunityPluginInstaller(store: store, session: scriptedSession())
                .install(repository: "owner/sample-repo", expectedIdentifier: "sample")
            XCTFail("An install that needs a newer API and has no versions.json must be refused.")
        } catch GraphiteError.unavailable {
            // The expected refusal.
        }

        XCTAssertEqual(ScriptedGitHubProtocol.script.requestedAddresses, [
            "https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json",
            "https://raw.githubusercontent.com/owner/sample-repo/HEAD/versions.json",
        ])
        XCTAssertFalse(installedFileExists(".obsidian/plugins/sample"))
    }

    func testAManifestWithAnotherIdentifierThanTheDirectoryEntryIsRefusedBeforeAnyRelease() async throws {
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json", pluginManifest(identifier: "other", version: "1.0.0"))

        do {
            _ = try await CommunityPluginInstaller(store: store, session: scriptedSession())
                .install(repository: "owner/sample-repo", expectedIdentifier: "sample")
            XCTFail("A repository holding another plugin than the directory entry must be refused.")
        } catch GraphiteError.invalidFile {
            // The expected refusal.
        }

        XCTAssertEqual(ScriptedGitHubProtocol.script.requestedAddresses, ["https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json"])
        XCTAssertFalse(installedFileExists(".obsidian/plugins"))
    }

    func testAReleaseWhoseManifestHasAnotherIdentifierThanTheCurrentManifestIsRefusedAndWritesNothing() async throws {
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/sample-repo/HEAD/manifest.json", pluginManifest(version: "1.0.0"))
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/1.0.0/main.js", "module.exports = 4;")
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/sample-repo/releases/download/1.0.0/manifest.json", pluginManifest(identifier: "renamed", version: "1.0.0"))

        do {
            _ = try await CommunityPluginInstaller(store: store, session: scriptedSession())
                .install(repository: "owner/sample-repo", expectedIdentifier: "sample")
            XCTFail("A release for another plugin must be refused.")
        } catch GraphiteError.invalidFile {
            // The expected refusal.
        }

        XCTAssertFalse(installedFileExists(".obsidian/plugins"))
    }

    // MARK: Directories

    func testTheDirectoriesAreObsidiansReleasesRepositorysHeadFiles() async throws {
        XCTAssertEqual(CommunityPluginInstaller.directoryAddress, "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/HEAD/community-plugins.json")
        XCTAssertEqual(ObsidianThemeInstaller.directoryAddress, "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/HEAD/community-css-themes.json")

        ScriptedGitHubProtocol.script.answer(CommunityPluginInstaller.directoryAddress,
                                             "[{\"id\": \"sample\", \"name\": \"Sample\", \"author\": \"Someone\", \"description\": \"A sample.\", \"repo\": \"owner/sample-repo\"}]")
        let pluginEntries = try await CommunityPluginInstaller(store: store, session: scriptedSession()).directory()
        XCTAssertEqual(pluginEntries.map(\.id), ["sample"])

        ScriptedGitHubProtocol.script.answer(ObsidianThemeInstaller.directoryAddress,
                                             "[{\"name\": \"Minimal\", \"author\": \"Someone\", \"repo\": \"owner/minimal\", \"modes\": [\"dark\", \"light\"]}]")
        let themeEntries = try await ObsidianThemeInstaller(store: store, session: scriptedSession()).directory()
        XCTAssertEqual(themeEntries.map(\.name), ["Minimal"])

        XCTAssertEqual(ScriptedGitHubProtocol.script.requestedAddresses, [CommunityPluginInstaller.directoryAddress, ObsidianThemeInstaller.directoryAddress])
    }

    func testAThemeInstallAsksForTheHeadManifestThenTheReleaseFilesAndFallsBackToTheHeadStyleSheet() async throws {
        let entry = ObsidianThemeDirectoryEntry(name: "Minimal", author: "Someone", repo: "owner/minimal")
        let manifest = "{\"name\": \"Minimal\", \"version\": \"7.0.0\"}"
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/minimal/HEAD/manifest.json", manifest)
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/minimal/releases/download/7.0.0/manifest.json", manifest)
        ScriptedGitHubProtocol.script.answer("https://github.com/owner/minimal/releases/download/7.0.0/theme.css", "body { color: blue; }")

        try await ObsidianThemeInstaller(store: store, session: scriptedSession()).install(entry)

        XCTAssertEqual(ScriptedGitHubProtocol.script.requestedAddresses, [
            "https://raw.githubusercontent.com/owner/minimal/HEAD/manifest.json",
            "https://github.com/owner/minimal/releases/download/7.0.0/manifest.json",
            "https://github.com/owner/minimal/releases/download/7.0.0/theme.css",
        ])
        XCTAssertEqual(try installedText(".obsidian/themes/Minimal/theme.css"), "body { color: blue; }")

        // A repository without that release gives its files from the default branch.
        ScriptedGitHubProtocol.script.reset()
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/minimal/HEAD/manifest.json", manifest)
        ScriptedGitHubProtocol.script.answer("https://raw.githubusercontent.com/owner/minimal/HEAD/theme.css", "body { color: green; }")

        try await ObsidianThemeInstaller(store: store, session: scriptedSession()).install(entry)

        XCTAssertEqual(ScriptedGitHubProtocol.script.requestedAddresses, [
            "https://raw.githubusercontent.com/owner/minimal/HEAD/manifest.json",
            "https://github.com/owner/minimal/releases/download/7.0.0/manifest.json",
            "https://github.com/owner/minimal/releases/download/7.0.0/theme.css",
            "https://raw.githubusercontent.com/owner/minimal/HEAD/theme.css",
        ])
        XCTAssertEqual(try installedText(".obsidian/themes/Minimal/theme.css"), "body { color: green; }")
    }
}

/// Answers the addresses a test scripted, 404 for any other, and records every address asked for.
private final class ScriptedGitHubProtocol: URLProtocol {
    final class Script: @unchecked Sendable {
        // Requests arrive on URL loading threads; the lock orders them.
        private let lock = NSLock()
        private var bodiesByAddress: [String: Data] = [:]
        private var addresses: [String] = []
        var requestedAddresses: [String] { lock.withLock { addresses } }
        func answer(_ address: String, _ body: String) { lock.withLock { bodiesByAddress[address] = Data(body.utf8) } }
        func record(_ address: String) -> Data? { lock.withLock { addresses.append(address); return bodiesByAddress[address] } }
        func reset() { lock.withLock { bodiesByAddress = [:]; addresses = [] } }
    }

    static let script = Script()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.script.record(url.absoluteString)
        guard let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
