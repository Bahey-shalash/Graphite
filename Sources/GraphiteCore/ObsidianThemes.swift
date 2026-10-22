import Foundation

/// A theme listed in Obsidian's community directory
/// (`obsidianmd/obsidian-releases/community-css-themes.json`).
public struct ObsidianThemeDirectoryEntry: Decodable, Identifiable, Equatable, Sendable {
    /// The theme's name, which is also its folder under `.obsidian/themes`.
    public let name: String
    public let author: String
    /// The GitHub repository the theme comes from, `owner/name`.
    public let repo: String
    /// `dark` and `light`, the appearances the theme styles.
    public let modes: [String]

    public var id: String { name }

    public init(name: String, author: String, repo: String, modes: [String] = ["dark", "light"]) {
        self.name = name; self.author = author; self.repo = repo; self.modes = modes
    }

    private enum CodingKeys: String, CodingKey { case name, author, repo, modes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        repo = try container.decode(String.self, forKey: .repo)
        modes = try container.decodeIfPresent([String].self, forKey: .modes) ?? []
    }

    /// The entries whose name or author matches `query`: names equal to it first, then names
    /// starting with it, names containing it, and authors.
    public static func search(_ entries: [Self], for query: String) -> [Self] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return entries }
        func rank(of entry: Self) -> Int? {
            if entry.name.compare(trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return 0 }
            if entry.name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return 1 }
            if entry.name.localizedCaseInsensitiveContains(trimmedQuery) { return 2 }
            return entry.author.localizedCaseInsensitiveContains(trimmedQuery) ? 3 : nil
        }
        let rankedEntries = entries.enumerated().compactMap { position, entry in rank(of: entry).map { entryRank in (entryRank, position, entry) } }
        return rankedEntries.sorted { first, second in (first.0, first.1) < (second.0, second.1) }.map { ranked in ranked.2 }
    }
}

/// A CSS snippet file in `.obsidian/snippets`, as Settings lists it.
public struct ObsidianSnippet: Equatable, Sendable {
    /// The file's name without `.css`, which is also its name in `enabledCssSnippets`.
    public let name: String
    /// What the file's opening comment says it does, or nil when it has none.
    public let description: String?

    public init(name: String, description: String?) {
        self.name = name; self.description = description
    }
}

/// Theme and CSS snippet files in a vault, where Obsidian keeps them: a theme is a folder
/// `.obsidian/themes/<name>/` with `theme.css` and `manifest.json`; a snippet is a file
/// `.obsidian/snippets/<name>.css`.
public enum ObsidianStyleFiles {
    public static let themesFolderPath = ".obsidian/themes"
    public static let snippetsFolderPath = ".obsidian/snippets"
    /// The largest theme read. The largest of the most downloaded themes, with its fonts
    /// written into the file, is about 3 MB.
    public static let maximumThemeBytes = 8 * 1_048_576
    public static let maximumSnippetBytes = 1_048_576

    /// Whether `name` can be a theme folder or snippet file name: one path component.
    public static func isUsableName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
            && name.rangeOfCharacter(from: .controlCharacters) == nil
    }

    public static func themeStyleSheetPath(named name: String) throws -> VaultPath {
        guard isUsableName(name) else { throw GraphiteError.invalidPath(name) }
        return try VaultPath(themesFolderPath).appending(name).appending("theme.css")
    }

    public static func snippetPath(named name: String) throws -> VaultPath {
        guard isUsableName(name) else { throw GraphiteError.invalidPath(name) }
        return try VaultPath(snippetsFolderPath).appending(name + ".css")
    }

    /// The longest snippet description shown; a longer first sentence is cut at a word.
    public static let maximumSnippetDescriptionCharacters = 140

    /// What a snippet says it does: the first sentence of the comment its file opens with, as
    /// most snippets begin (`/* Square bullets for unordered lists */`). Nil when the file opens
    /// with a rule, or with Style Settings' `@settings` block, which describes options instead.
    public static func snippetDescription(of styleSheet: String) -> String? {
        let openingText = styleSheet.drop { character in character.isWhitespace || character == "\u{FEFF}" }
        guard openingText.hasPrefix("/*"), let commentEnd = openingText.range(of: "*/") else { return nil }
        let commentLines = openingText[openingText.index(openingText.startIndex, offsetBy: 2)..<commentEnd.lowerBound]
            .split(whereSeparator: \.isNewline)
            .map { line in line.trimmingCharacters(in: .whitespaces).drop { character in character == "*" }.trimmingCharacters(in: .whitespaces) }
            // Banner lines such as `=====` or `-----` frame a title; they say nothing.
            .filter { line in line.contains { character in character.isLetter || character.isNumber } }
        let commentText = commentLines.joined(separator: " ")
        guard !commentText.isEmpty, !commentText.hasPrefix("@settings") else { return nil }
        let sentenceEnd = commentText.indices.first { index in
            let nextIndex = commentText.index(after: index)
            return ".!?".contains(commentText[index]) && (nextIndex == commentText.endIndex || commentText[nextIndex] == " ")
        }
        let firstSentence = sentenceEnd.map { index in String(commentText[...index]) } ?? commentText
        guard firstSentence.count > maximumSnippetDescriptionCharacters else { return firstSentence }
        let shortened = firstSentence.prefix(maximumSnippetDescriptionCharacters)
        let wordEnd = shortened.lastIndex(of: " ") ?? shortened.endIndex
        return shortened[..<wordEnd].trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }

    /// Whether a changed location is a theme or snippet file, so styles are read again.
    public static func isStyleFile(_ location: URL) -> Bool {
        let components = location.standardizedFileURL.pathComponents
        guard let configurationIndex = components.lastIndex(of: ".obsidian"), configurationIndex + 1 < components.count else { return false }
        let folder = components[configurationIndex + 1]
        return folder == "themes" || folder == "snippets"
    }
}

extension VaultStore {
    /// The themes installed in the vault, by folder name, sorted: folders that hold a `theme.css`.
    public func installedThemeNames() -> [String] {
        guard let folder = try? VaultPath(ObsidianStyleFiles.themesFolderPath).url(in: root),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { name in
            ObsidianStyleFiles.isUsableName(name) && FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).appendingPathComponent("theme.css").path)
        }.sorted { leftName, rightName in leftName.localizedStandardCompare(rightName) == .orderedAscending }
    }

    /// The CSS snippets in the vault, by name without `.css`, sorted.
    public func snippetNames() -> [String] {
        guard let folder = try? VaultPath(ObsidianStyleFiles.snippetsFolderPath).url(in: root),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { name in name.lowercased().hasSuffix(".css") }
            .map { name in String(name.dropLast(4)) }
            .filter(ObsidianStyleFiles.isUsableName)
            .sorted { leftName, rightName in leftName.localizedStandardCompare(rightName) == .orderedAscending }
    }

    /// The CSS snippets in the vault, sorted, each with what its opening comment says it does.
    public func snippets() -> [ObsidianSnippet] {
        snippetNames().map { name in
            ObsidianSnippet(name: name, description: snippetStyleSheet(named: name).flatMap(ObsidianStyleFiles.snippetDescription(of:)))
        }
    }

    /// A theme's `theme.css`, or nil when it is missing, unreadable or larger than Graphite reads.
    public func themeStyleSheet(named name: String) -> String? {
        guard let path = try? ObsidianStyleFiles.themeStyleSheetPath(named: name),
              (try? fileExists(path)) == true,
              let snapshot = try? read(path, maximumBytes: ObsidianStyleFiles.maximumThemeBytes) else { return nil }
        return String(decoding: snapshot.data, as: UTF8.self)
    }

    /// A snippet's CSS, or nil when it is missing, unreadable or too large.
    public func snippetStyleSheet(named name: String) -> String? {
        guard let path = try? ObsidianStyleFiles.snippetPath(named: name),
              (try? fileExists(path)) == true,
              let snapshot = try? read(path, maximumBytes: ObsidianStyleFiles.maximumSnippetBytes) else { return nil }
        return String(decoding: snapshot.data, as: UTF8.self)
    }
}

/// Installs community themes as Obsidian 1.14 does: the theme's current `manifest.json` in
/// its repository names a version, and that GitHub release's `manifest.json` and `theme.css`
/// are written to `.obsidian/themes/<name>/`; a repository without that release gives its
/// files from the default branch instead. The manifest's name must be the directory's.
public struct ObsidianThemeInstaller: Sendable {
    public let store: VaultStore
    private let session: URLSession

    public static let directoryAddress = "https://raw.githubusercontent.com/obsidianmd/obsidian-releases/HEAD/community-css-themes.json"
    static let maximumDirectoryBytes = 8 * 1_048_576
    static let maximumManifestBytes = 65_536

    public init(store: VaultStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    public func directory() async throws -> [ObsidianThemeDirectoryEntry] {
        let data = try await download(Self.directoryAddress, maximumBytes: Self.maximumDirectoryBytes) ?? Data()
        guard let entries = try? JSONDecoder().decode([ObsidianThemeDirectoryEntry].self, from: data) else {
            throw GraphiteError.invalidFile("Obsidian's list of community themes could not be read.")
        }
        return entries.filter { entry in CommunityPluginInstaller.isUsableRepository(entry.repo) && ObsidianStyleFiles.isUsableName(entry.name) }
    }

    /// Downloads the theme and writes it into the vault, replacing an older copy.
    public func install(_ entry: ObsidianThemeDirectoryEntry) async throws {
        guard CommunityPluginInstaller.isUsableRepository(entry.repo), ObsidianStyleFiles.isUsableName(entry.name) else { throw GraphiteError.invalidPath(entry.repo) }
        let rawBase = "https://raw.githubusercontent.com/\(entry.repo)/HEAD/"
        guard let currentManifestData = try await download(rawBase + "manifest.json", maximumBytes: Self.maximumManifestBytes) else {
            throw GraphiteError.unavailable("“\(entry.name)” has no manifest.json; Graphite does not install themes from before Obsidian 1.0.")
        }
        let version = Self.manifestValue("version", in: currentManifestData) ?? ""
        var manifestData: Data?
        var styleSheet: Data?
        if !version.isEmpty, !version.contains("/"), !version.contains("..") {
            let releaseBase = "https://github.com/\(entry.repo)/releases/download/\(version)/"
            manifestData = try await download(releaseBase + "manifest.json", maximumBytes: Self.maximumManifestBytes)
            styleSheet = try await download(releaseBase + "theme.css", maximumBytes: ObsidianStyleFiles.maximumThemeBytes)
        }
        if manifestData == nil || styleSheet == nil {
            manifestData = currentManifestData
            styleSheet = try await download(rawBase + "theme.css", maximumBytes: ObsidianStyleFiles.maximumThemeBytes)
        }
        guard let manifestData, let styleSheet else { throw GraphiteError.unavailable("“\(entry.name)” has no theme.css.") }
        guard Self.manifestValue("name", in: manifestData) == entry.name else {
            throw GraphiteError.invalidFile("The theme's manifest names another theme than “\(entry.name)”.")
        }
        let folder = try VaultPath(ObsidianStyleFiles.themesFolderPath).appending(entry.name)
        try await write(manifestData, to: folder.appending("manifest.json"))
        try await write(styleSheet, to: folder.appending("theme.css"))
    }

    static func manifestValue(_ key: String, in manifestData: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any])?[key] as? String
    }

    private func write(_ data: Data, to path: VaultPath) async throws {
        try await store.createDirectory(path.parent)
        let expectation: WriteExpectation = try await store.fileExists(path) ? .revision(try await store.read(path).revision) : .absent
        _ = try await store.save(data, at: path, expecting: expectation)
    }

    /// The bytes at `address`, or nil when it is missing (HTTP 404).
    private func download(_ address: String, maximumBytes: Int) async throws -> Data? {
        guard let url = URL(string: address) else { throw GraphiteError.invalidPath(address) }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { throw GraphiteError.unavailable("GitHub did not answer over HTTP.") }
        if httpResponse.statusCode == 404 { return nil }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GraphiteError.unavailable("Downloading \(url.lastPathComponent) failed (HTTP \(httpResponse.statusCode)).")
        }
        guard data.count <= maximumBytes else { throw GraphiteError.oversized("\(url.lastPathComponent) is larger than Graphite accepts for a theme.") }
        return data
    }
}
