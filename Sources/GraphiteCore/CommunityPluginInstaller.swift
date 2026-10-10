import Foundation

/// A plugin listed in Obsidian's community directory
/// (`obsidianmd/obsidian-releases/community-plugins.json`).
public struct CommunityPluginDirectoryEntry: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let author: String
    public let description: String
    /// The GitHub repository the releases come from, `owner/name`.
    public let repo: String

    public init(id: String, name: String, author: String, description: String, repo: String) {
        self.id = id; self.name = name; self.author = author; self.description = description; self.repo = repo
    }
}

/// Installs community plugins the way Obsidian does: the plugin's current manifest from its
/// repository names the release, and that GitHub release's `main.js`, `manifest.json` and
/// `styles.css` are written into `.obsidian/plugins/<id>/`. A plugin's `data.json` (its
/// settings) is never touched, so an update keeps them. Nothing runs during installation.
public struct CommunityPluginInstaller: Sendable {
    public let store: VaultStore
    private let session: URLSession

    public static let directoryAddress = "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/HEAD/community-plugins.json"
    static let maximumDirectoryBytes = 16 * 1_048_576
    static let maximumSmallFileBytes = 1_048_576

    public init(store: VaultStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    // MARK: The directory

    public func directory() async throws -> [CommunityPluginDirectoryEntry] {
        let data = try await download(Self.directoryAddress, maximumBytes: Self.maximumDirectoryBytes, isOptional: false) ?? Data()
        guard let entries = try? JSONDecoder().decode([CommunityPluginDirectoryEntry].self, from: data) else {
            throw GraphiteError.invalidFile("Obsidian's list of community plugins could not be read.")
        }
        return entries.filter { entry in Self.isUsableRepository(entry.repo) && CommunityPluginManifest.isUsableIdentifier(entry.id) }
    }

    /// `owner/name`, each part made of the characters GitHub allows.
    public static func isUsableRepository(_ repository: String) -> Bool {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return parts.count == 2 && parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    // MARK: Installing

    public struct Installation: Sendable {
        public let manifest: CommunityPluginManifest
        public let folder: VaultPath
        /// True when a release older than the newest was chosen, because the newest needs
        /// a newer plugin API than Graphite provides.
        public let isOlderReleaseForCompatibility: Bool
    }

    /// Installs or updates a plugin from its GitHub releases. `expectedIdentifier` is the
    /// directory's identifier, which the release's manifest must match.
    public func install(repository: String, expectedIdentifier: String?, providedApiVersion: String = CommunityPluginCompatibility.providedApiVersion) async throws -> Installation {
        guard Self.isUsableRepository(repository) else { throw GraphiteError.invalidPath(repository) }
        let rawBase = "https://raw.githubusercontent.com/\(repository)/HEAD/"
        guard let currentManifestData = try await download(rawBase + "manifest.json", maximumBytes: CommunityPluginManifest.maximumManifestBytes, isOptional: false) else {
            throw GraphiteError.unavailable("“\(repository)” has no manifest.json.")
        }
        let currentManifest = try CommunityPluginManifest(manifestData: currentManifestData)
        if let expectedIdentifier, currentManifest.identifier != expectedIdentifier {
            throw GraphiteError.invalidFile("The repository's plugin is “\(currentManifest.identifier)”, not “\(expectedIdentifier)”.")
        }
        var version = currentManifest.version
        var isOlderRelease = false
        if let required = currentManifest.minimumApplicationVersion, ObsidianVersionNumber.compare(required, providedApiVersion) == .orderedDescending {
            // As Obsidian does, an older release whose `minAppVersion` fits is chosen from versions.json.
            guard let versionsData = try await download(rawBase + "versions.json", maximumBytes: Self.maximumSmallFileBytes, isOptional: true),
                  let compatibleVersion = Self.newestCompatibleVersion(versionsData: versionsData, providedApiVersion: providedApiVersion) else {
                throw GraphiteError.unavailable("“\(currentManifest.name)” needs Obsidian \(required) or newer, and no older release works with the plugin API Graphite provides (\(providedApiVersion)).")
            }
            version = compatibleVersion
            isOlderRelease = true
        }
        guard !version.isEmpty, !version.contains("/"), !version.contains("..") else { throw GraphiteError.invalidFile("The plugin's version “\(version)” is not usable.") }
        let releaseBase = "https://github.com/\(repository)/releases/download/\(version)/"
        guard let mainScript = try await download(releaseBase + "main.js", maximumBytes: VaultStore.maximumPluginScriptBytes, isOptional: false),
              let releaseManifestData = try await download(releaseBase + "manifest.json", maximumBytes: CommunityPluginManifest.maximumManifestBytes, isOptional: false) else {
            throw GraphiteError.unavailable("Release \(version) of “\(currentManifest.name)” is missing main.js or manifest.json.")
        }
        let styles = try await download(releaseBase + "styles.css", maximumBytes: VaultStore.maximumPluginStylesBytes, isOptional: true)
        let releaseManifest = try CommunityPluginManifest(manifestData: releaseManifestData)
        guard releaseManifest.identifier == currentManifest.identifier else {
            throw GraphiteError.invalidFile("Release \(version) is for “\(releaseManifest.identifier)”, not “\(currentManifest.identifier)”.")
        }
        let folder = try VaultPath(CommunityPluginList.pluginsFolderPath).appending(releaseManifest.identifier)
        try await write(mainScript, to: folder.appending("main.js"))
        try await write(releaseManifestData, to: folder.appending("manifest.json"))
        if let styles { try await write(styles, to: folder.appending("styles.css")) }
        return Installation(manifest: releaseManifest, folder: folder, isOlderReleaseForCompatibility: isOlderRelease)
    }

    /// The newest plugin version in versions.json (`{"1.2.0": "0.15.0", …}`, plugin version
    /// to the oldest Obsidian it needs) that the provided API satisfies.
    static func newestCompatibleVersion(versionsData: Data, providedApiVersion: String) -> String? {
        guard let versions = try? JSONSerialization.jsonObject(with: versionsData) as? [String: Any] else { return nil }
        return versions.compactMap { pluginVersion, requiredVersion -> String? in
            guard let requiredVersion = requiredVersion as? String,
                  ObsidianVersionNumber.compare(requiredVersion, providedApiVersion) != .orderedDescending else { return nil }
            return pluginVersion
        }.max { firstVersion, secondVersion in ObsidianVersionNumber.compare(firstVersion, secondVersion) == .orderedAscending }
    }

    /// Replaces whatever is there now, as an update does.
    private func write(_ data: Data, to path: VaultPath) async throws {
        try await store.createDirectory(path.parent)
        let expectation: WriteExpectation
        let isReplacingFile = try await store.fileExists(path)
        if isReplacingFile {
            expectation = .revision(try await store.read(path).revision)
        } else {
            expectation = .absent
        }
        _ = try await store.save(data, at: path, expecting: expectation)
    }

    /// The bytes at `address`; nil for a missing optional file.
    private func download(_ address: String, maximumBytes: Int, isOptional: Bool) async throws -> Data? {
        guard let url = URL(string: address) else { throw GraphiteError.invalidPath(address) }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { throw GraphiteError.unavailable("GitHub did not answer over HTTP.") }
        if httpResponse.statusCode == 404, isOptional { return nil }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GraphiteError.unavailable("Downloading \(url.lastPathComponent) failed (HTTP \(httpResponse.statusCode)).")
        }
        guard data.count <= maximumBytes else { throw GraphiteError.oversized("\(url.lastPathComponent) is larger than Graphite accepts for a plugin.") }
        return data
    }
}
